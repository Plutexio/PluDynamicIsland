#!/usr/bin/env python3
"""
Mostek między wyspą (Quickshell) a minutnikami KClock (kclockd).

Wyspa nie ma własnych minutników — pokazuje i steruje tymi z KClock, więc
minutnik nastawiony w aplikacji odlicza na wyspie, a zatrzymany na wyspie
stoi też w aplikacji. Quickshell nie ma klienta D-Bus w QML, stąd ten skrypt.

Interfejs kclockd (zmierzone na kclock 26.08):
  /Timers               org.kde.kclock.TimerModel: timers() -> as,
                        timerAdded(s), timerRemoved(s), addTimer, removeTimer
  /Timers/<id>          org.kde.kclock.Timer: label, length (s), running,
                        ringing, looping, timeCompleted (epoch s), elapsed() (s),
                        toggleRunning(), reset(), dismiss(), uuid()

Pułapki (zmierzone):
- timers() zwraca id w formie ścieżki (bez klamer i myślników), a
  removeTimer chce uuid() w klamrach — z id ścieżki nic nie robi.
- timeCompleted = teraz + reszta, przeliczane przy każdym odczycie na pauzie,
  więc pozostały czas na pauzie to length - elapsed(), nie timeCompleted.
- Właściwości są oznaczone emits-change, ale kclockd NIE wysyła
  PropertiesChanged — tylko sygnały w stylu Qt na interfejsie minutnika
  (runningChanged, timeCompletedChanged, ringingChanged…).
- kclockd SAM SIĘ ZAMYKA, gdy nic nie odlicza, i wstaje z aktywacji D-Bus
  przy pierwszym wywołaniu. Zniknięcie nazwy to więc zwykły stan, nie
  awaria: lista zostaje (minutniki są zapisane w konfiguracji kclockd),
  a komenda z wyspy sama go obudzi. Wywołanie trafione w chwilę zamykania
  dostaje ServiceUnknown "not activatable" (zmierzone) — stąd jedna
  ponowiona próba komendy.
- Przy usuwaniu sygnały minutnika przychodzą, gdy obiekt jeszcze istnieje,
  więc odczyt po nich widzi go dalej; timerRemoved zdejmuje go od razu.

  stdout -> QML : {"type":"state", "available": bool, "timers": [
                     {id, label, length, running, ringing, looping,
                      elapsed, endsAt (epoch ms, tylko gdy running)}]}
                  {"type":"log", "text": "..."}
  stdin  <- QML : {"cmd":"toggle"|"reset"|"dismiss", "id": "<id>"}
                  {"cmd":"add", "length": <s>, "label": "..."} — nowy, od razu odlicza

Kod wyjścia 0 = rodzic zamknął stdin, 3 = KClock nie jest zainstalowany
(serwis wtedy nie restartuje).
"""

import json
import sys
import time

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

SERVICE = "org.kde.kclockd"
MODEL_PATH = "/Timers"
MODEL_IFACE = "org.kde.kclock.TimerModel"
TIMER_IFACE = "org.kde.kclock.Timer"
PROPS_IFACE = "org.freedesktop.DBus.Properties"

# Świeżo aktywowany kclockd ma już nazwę, ale jeszcze nie /Timers
# (zmierzone: UnknownObject zaraz po starcie) — wtedy kilka ponowień.
RETRY_MS = 1500
MAX_RETRIES = 5

# Lokalna usługa odpowiada od razu; długi domyślny timeout (25 s) przy
# kclockd w trakcie zamykania zamroziłby mostek.
CALL_TIMEOUT = 3

last_emitted = None


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def log(text):
    emit({"type": "log", "text": text})


class Bridge:
    def __init__(self):
        self.bus = dbus.SessionBus()
        self.timers = {}      # id -> słownik stanu
        self.order = []       # kolejność jak w KClock
        self.retries = 0
        self.retry_source = None

        self.bus.add_signal_receiver(
            self.on_owner_changed,
            dbus_interface="org.freedesktop.DBus",
            signal_name="NameOwnerChanged",
            arg0=SERVICE,
        )
        self.bus.add_signal_receiver(
            lambda *_: self.refresh_all(),
            dbus_interface=MODEL_IFACE,
            signal_name="timerAdded",
            bus_name=SERVICE,
        )
        self.bus.add_signal_receiver(
            self.on_timer_removed,
            dbus_interface=MODEL_IFACE,
            signal_name="timerRemoved",
            bus_name=SERVICE,
        )
        # Bez signal_name: każdy sygnał minutnika (runningChanged,
        # ringingChanged, timeCompletedChanged…) to powód do odczytu.
        self.bus.add_signal_receiver(
            self.on_timer_signal,
            dbus_interface=TIMER_IFACE,
            bus_name=SERVICE,
            path_keyword="path",
        )

        GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, self.on_stdin)
        # Pierwszy odczyt budzi kclockd, jeśli spał — bez tego karta nie
        # miałaby czego pokazać, dopóki ktoś nie otworzy KClock.
        self.refresh_all()

    # ---- odczyt ----

    def read_timer(self, tid):
        obj = self.bus.get_object(SERVICE, MODEL_PATH + "/" + tid, introspect=False)
        props = obj.GetAll(TIMER_IFACE, dbus_interface=PROPS_IFACE, timeout=CALL_TIMEOUT)
        elapsed = int(obj.elapsed(dbus_interface=TIMER_IFACE, timeout=CALL_TIMEOUT))
        running = bool(props.get("running", False))
        return {
            "id": str(tid),
            "label": str(props.get("label", "")),
            "length": int(props.get("length", 0)),
            "running": running,
            "ringing": bool(props.get("ringing", False)),
            "looping": bool(props.get("looping", False)),
            "elapsed": elapsed,
            "endsAt": int(props.get("timeCompleted", 0)) * 1000 if running else 0,
        }

    def refresh_all(self):
        try:
            model = self.bus.get_object(SERVICE, MODEL_PATH, introspect=False)
            ids = [str(t) for t in model.timers(dbus_interface=MODEL_IFACE, timeout=CALL_TIMEOUT)]
        except dbus.DBusException as e:
            if self.retries < MAX_RETRIES and self.retry_source is None:
                self.retries += 1
                self.retry_source = GLib.timeout_add(RETRY_MS, self.retry)
            else:
                log("kclockd nie odpowiada: " + e.get_dbus_name())
            return
        self.retries = 0
        timers = {}
        for tid in ids:
            try:
                timers[tid] = self.read_timer(tid)
            except dbus.DBusException:
                continue
        self.timers = timers
        self.order = [t for t in ids if t in timers]
        self.emit_state()

    def on_timer_removed(self, uid):
        # uuid w klamrach albo id ścieżki — sprowadzamy do id ścieżki.
        tid = str(uid).strip("{}").replace("-", "")
        self.timers.pop(tid, None)
        self.order = [t for t in self.order if t != tid]
        self.emit_state()

    def retry(self):
        self.retry_source = None
        self.refresh_all()
        return False

    def on_timer_signal(self, *args, path=None):
        if not path or not path.startswith(MODEL_PATH + "/"):
            return
        tid = path[len(MODEL_PATH) + 1:]
        try:
            self.timers[tid] = self.read_timer(tid)
        except dbus.DBusException:
            return
        if tid not in self.order:
            self.order.append(tid)
        self.emit_state()

    def on_owner_changed(self, name, old, new):
        if new:
            self.refresh_all()
        else:
            # Zamknął się sam, bo nic nie odliczało — lista zostaje.
            for t in self.timers.values():
                t["running"] = False
                t["ringing"] = False
                t["endsAt"] = 0
            self.emit_state()

    def emit_state(self):
        global last_emitted
        state = {"type": "state", "available": True,
                 "timers": [self.timers[t] for t in self.order if t in self.timers]}
        snapshot = json.dumps(state, sort_keys=True)
        if snapshot == last_emitted:
            return
        last_emitted = snapshot
        emit(state)

    # ---- stdin ----

    def on_stdin(self, fd, condition):
        line = sys.stdin.readline()
        if not line:
            GLib.idle_add(loop.quit)
            return False
        try:
            cmd = json.loads(line)
        except ValueError:
            log(f"śmieci na stdin: {line[:80]!r}")
            return True

        if cmd.get("cmd") == "add":
            self.add_timer(int(cmd.get("length", 0)), str(cmd.get("label", "")))
            return True

        method = {"toggle": "toggleRunning", "reset": "reset", "dismiss": "dismiss"}.get(cmd.get("cmd"))
        tid = str(cmd.get("id", ""))
        if method is None or tid not in self.timers:
            log(f"nieznana komenda albo minutnik: {line.strip()[:80]}")
            return True

        # Asynchronicznie: wywołanie budzi uśpiony kclockd, co trwa chwilę,
        # a mostek ma w tym czasie dalej czytać sygnały.
        self.call(MODEL_PATH + "/" + tid, TIMER_IFACE, method, ())
        return True

    def call(self, path, iface, method, args, retried=False):
        def failed(e):
            if not retried:
                GLib.timeout_add(RETRY_MS, lambda: self.call(path, iface, method, args, True) and False)
            else:
                log(f"{method} nie przeszło: {e.get_dbus_name()}")

        # Proxy przy każdym wywołaniu — stary trzymałby nazwę unikalną
        # procesu, który się już zamknął.
        obj = self.bus.get_object(SERVICE, path, introspect=False)
        obj.get_dbus_method(method, iface)(
            *args,
            reply_handler=lambda *_: None,
            error_handler=failed,
            timeout=CALL_TIMEOUT,
        )


    def add_timer(self, length, label):
        if length <= 0:
            log(f"odrzucam minutnik o długości {length}")
            return
        # addTimer(length, label, looping, commandTimeout, running) — sygnatura
        # "isbsb" z introspekcji; nowy minutnik wraca do nas przez timerAdded.
        self.call(MODEL_PATH, MODEL_IFACE, "addTimer", (dbus.Int32(length), label, False, "", True))


loop = None


def kclock_installed(bus):
    dbus_obj = bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus")
    names = dbus_obj.ListActivatableNames(dbus_interface="org.freedesktop.DBus")
    return SERVICE in names or bool(dbus_obj.NameHasOwner(SERVICE, dbus_interface="org.freedesktop.DBus"))


def main():
    global loop
    DBusGMainLoop(set_as_default=True)
    if not kclock_installed(dbus.SessionBus()):
        emit({"type": "state", "available": False, "timers": []})
        return 3
    loop = GLib.MainLoop()
    Bridge()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
