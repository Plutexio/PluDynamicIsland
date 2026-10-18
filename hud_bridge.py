#!/usr/bin/env python3
"""
Jasność ekranu, Caps Lock i Num Lock dla zerknięć wyspy.

Jasność, dwie drogi:
- KDE: org.kde.ScreenBrightness (PowerDevil, Plasma 6.2+). Obejmuje też
  monitory zewnętrzne przez DDC — na desktopie /sys/class/backlight jest
  pusty. Sygnał BrightnessChanged(display, wartość, klient, kontekst) idzie
  tylko przy zmianie, osobno dla każdego ekranu (zmierzone: dwa naraz przy
  jednym kroku). Przyciemnianie przy bezczynności idzie osobnym mnożnikiem
  (setDimmingRatio), nie przez jasność, więc nie daje sygnału.
- Reszta (Hyprland na laptopie): /sys/class/backlight/*. sysfs zgłasza
  inotify IN_MODIFY przy zapisie (brightnessctl) i przy zmianie z klawisza
  w firmware (sysfs_notify na actual_brightness).

Caps Lock / Num Lock: diody klawiatury w /sys/class/leds/*::capslock
i *::numlock, które ustawia kompozytor. Klient Waylanda bez fokusu klawiatury stanu modyfikatorów nie
dostaje, a /dev/input wymaga grupy input. Dioda nie zgłasza zmian (jasność
LED zmienia się bez sysfs_notify), więc odpytujemy — odczyt pliku sysfs
to mikrosekundy. Kilka klawiatur = OR.

  stdout -> QML : {"type":"brightness", "value": 0–1}     tylko zmiany
                  {"type":"capslock"|"numlock", "on": bool, "initial": bool}
                  {"type":"log", "text": "..."}

Kod wyjścia 0 = rodzic zamknął stdin.
"""

import ctypes
import glob
import json
import os
import sys

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

KDE_SERVICE = "org.kde.ScreenBrightness"
KDE_PATH = "/org/kde/ScreenBrightness"
KDE_IFACE = "org.kde.ScreenBrightness"
KDE_DISPLAY_IFACE = "org.kde.ScreenBrightness.Display"

LOCK_POLL_MS = 150
LOCK_KEYS = ("capslock", "numlock")

IN_MODIFY = 0x00000002


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def log(text):
    emit({"type": "log", "text": text})


def read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


class Bridge:
    def __init__(self):
        self.bus = dbus.SessionBus()
        self.max_by_display = {}
        self.last_backlight = None
        self.locks = {}   # klawisz -> ostatni stan
        self.lock_files = {k: sorted(glob.glob("/sys/class/leds/*::" + k + "/brightness")) for k in LOCK_KEYS}

        if self.bus.name_has_owner(KDE_SERVICE) or KDE_SERVICE in self.bus.list_activatable_names():
            self.watch_kde()
        else:
            self.watch_backlight()

        for k in LOCK_KEYS:
            if not self.lock_files[k]:
                log("brak diody " + k + " w /sys/class/leds — zerknięcie wyłączone")
        if any(self.lock_files.values()):
            self.poll_locks(initial=True)
            GLib.timeout_add(LOCK_POLL_MS, self.poll_locks)

        GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, self.on_stdin)

    # ---- jasność: KDE ----

    def watch_kde(self):
        self.bus.add_signal_receiver(
            self.on_kde_brightness,
            dbus_interface=KDE_IFACE,
            signal_name="BrightnessChanged",
            bus_name=KDE_SERVICE,
        )
        self.bus.add_signal_receiver(
            lambda display, max_value, value: self.max_by_display.__setitem__(str(display), int(max_value)),
            dbus_interface=KDE_IFACE,
            signal_name="BrightnessRangeChanged",
            bus_name=KDE_SERVICE,
        )

    def kde_max(self, display):
        if display not in self.max_by_display:
            try:
                obj = self.bus.get_object(KDE_SERVICE, KDE_PATH + "/" + display)
                self.max_by_display[display] = int(obj.Get(
                    KDE_DISPLAY_IFACE, "MaxBrightness",
                    dbus_interface="org.freedesktop.DBus.Properties", timeout=3))
            except dbus.DBusException:
                return 0
        return self.max_by_display[display]

    def on_kde_brightness(self, display, value, client, context):
        # Na wszelki wypadek, gdyby przyciemnianie kiedyś szło przez jasność.
        if "dim" in str(context).lower():
            return
        top = self.kde_max(str(display))
        if top > 0:
            emit({"type": "brightness", "value": round(int(value) / top, 4)})

    # ---- jasność: sysfs ----

    def watch_backlight(self):
        devices = sorted(glob.glob("/sys/class/backlight/*"))
        if not devices:
            log("brak podświetlenia w /sys/class/backlight i brak PowerDevil — zerknięcie jasności wyłączone")
            return
        self.backlight = devices[0]
        self.backlight_max = read_int(self.backlight + "/max_brightness") or 0
        self.last_backlight = read_int(self.backlight + "/actual_brightness")

        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        self.ino = libc.inotify_init1(os.O_NONBLOCK)
        for name in ("brightness", "actual_brightness"):
            libc.inotify_add_watch(self.ino, (self.backlight + "/" + name).encode(), IN_MODIFY)
        GLib.io_add_watch(self.ino, GLib.IO_IN, self.on_backlight)

    def on_backlight(self, fd, condition):
        try:
            os.read(fd, 4096)
        except BlockingIOError:
            pass
        value = read_int(self.backlight + "/actual_brightness")
        if value is not None and value != self.last_backlight and self.backlight_max > 0:
            self.last_backlight = value
            emit({"type": "brightness", "value": round(value / self.backlight_max, 4)})
        return True

    # ---- Caps Lock / Num Lock ----

    def poll_locks(self, initial=False):
        for k, files in self.lock_files.items():
            if not files:
                continue
            on = any((read_int(f) or 0) > 0 for f in files)
            if on != self.locks.get(k):
                self.locks[k] = on
                emit({"type": k, "on": on, "initial": initial})
        return True

    # ---- stdin ----

    def on_stdin(self, fd, condition):
        if not sys.stdin.readline():
            GLib.idle_add(loop.quit)
            return False
        return True


loop = None


def main():
    global loop
    DBusGMainLoop(set_as_default=True)
    loop = GLib.MainLoop()
    Bridge()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
