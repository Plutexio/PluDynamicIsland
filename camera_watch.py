#!/usr/bin/env python3
"""Kto trzyma otwartą kamerę — dla kropki prywatności wyspy.

PipeWire widzi kamerę tylko wtedy, gdy aplikacja idzie przez niego. Brave,
Chrome i Discord (Electron) domyślnie otwierają /dev/video* WPROST, z
pominięciem PipeWire, więc z pw-dump kamery w rozmowie nie widać wcale.
Jedyne pewne źródło to otwarte deskryptory w /proc.

Bez odpytywania: inotify zgłasza IN_OPEN / IN_CLOSE także na plikach
urządzeń (zmierzone na /dev/video0), a /proc przeglądamy dopiero po
zdarzeniu. Jedno open() potrafi pociągnąć kilka krótkich otwarć przez inne
procesy (zmierzone: 4 pary open/close na jedno otwarcie), stąd SETTLE.

Na stdout linia JSON przy każdej zmianie zbioru:
  {"type": "camera", "holders": [{"pid": 1234, "name": "brave"}]}
Koniec stdin (wyspa zamknięta) kończy proces.
"""

import ctypes
import json
import os
import select
import struct
import sys
import time

IN_OPEN = 0x00000020
IN_CLOSE = 0x00000008 | 0x00000010
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_NONBLOCK = os.O_NONBLOCK

# Czas na uspokojenie się serii otwarć, zanim przejrzymy /proc. Krótkie
# sondowanie urządzenia (lista kamer w przeglądarce) mieści się w tym oknie
# i nie zapala kropki.
SETTLE = 0.3

libc = ctypes.CDLL("libc.so.6", use_errno=True)


def video_devices():
    try:
        return sorted("/dev/" + n for n in os.listdir("/dev") if n.startswith("video"))
    except OSError:
        return []


def holders():
    me = os.getpid()
    found = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == me:
            continue
        fd_dir = "/proc/" + pid + "/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            # Procesy innych użytkowników i te, które właśnie zniknęły.
            continue
        for fd in fds:
            try:
                target = os.readlink(fd_dir + "/" + fd)
            except OSError:
                continue
            if target.startswith("/dev/video"):
                try:
                    with open("/proc/" + pid + "/comm") as f:
                        name = f.read().strip()
                except OSError:
                    name = ""
                found[int(pid)] = name
                break
    return [{"pid": p, "name": found[p]} for p in sorted(found)]


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main():
    fd = libc.inotify_init1(IN_NONBLOCK)
    if fd < 0:
        print("inotify_init1 nie działa", file=sys.stderr)
        return 1

    def watch(path, mask):
        if libc.inotify_add_watch(fd, path.encode(), mask) < 0:
            print("nie da się obserwować " + path, file=sys.stderr)

    # Kamera na USB może dojść później — /dev mówi, kiedy pojawi się nowa.
    watch("/dev", IN_CREATE | IN_DELETE)
    for dev in video_devices():
        watch(dev, IN_OPEN | IN_CLOSE)

    last = None
    due = time.monotonic()  # pierwszy stan od razu

    while True:
        timeout = None if due is None else max(0.0, due - time.monotonic())
        ready, _, _ = select.select([fd, sys.stdin], [], [], timeout)

        if sys.stdin in ready and not sys.stdin.readline():
            return 0

        if fd in ready:
            try:
                buf = os.read(fd, 65536)
            except BlockingIOError:
                buf = b""
            i = 0
            while i < len(buf):
                _wd, mask, _cookie, length = struct.unpack_from("iIII", buf, i)
                name = buf[i + 16:i + 16 + length].rstrip(b"\0").decode(errors="replace")
                i += 16 + length
                if mask & IN_CREATE and name.startswith("video"):
                    watch("/dev/" + name, IN_OPEN | IN_CLOSE)
            due = time.monotonic() + SETTLE

        if due is not None and time.monotonic() >= due:
            due = None
            now = holders()
            if now != last:
                last = now
                emit({"type": "camera", "holders": now})


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
