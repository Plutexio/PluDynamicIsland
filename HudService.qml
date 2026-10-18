pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Jasność ekranu, Caps Lock i Num Lock z hud_bridge.py — źródła zerknięć jak
// głośność. Skąd mostek to bierze (PowerDevil / sysfs, dioda klawiatury),
// opisuje on sam.
Singleton {
    id: root

    property int restartDelayMs: 3000
    property int maxFailures: 3

    // Zmiana jasności spoza wyspy, 0–1. Pierwszego odczytu nie ma —
    // mostek wysyła tylko zmiany.
    signal brightnessNudged(real value)
    // Przełączenie Caps Locka (bez stanu zastanego przy starcie).
    signal capsLockToggled(bool on)
    signal numLockToggled(bool on)

    readonly property alias capsLock: priv.capsLock
    readonly property alias numLock: priv.numLock

    QtObject {
        id: priv
        property bool capsLock: false
        property bool numLock: false
        property int failures: 0
        property double startedAt: 0
    }

    Timer {
        id: retry
        interval: root.restartDelayMs
        onTriggered: proc.running = true
    }

    Process {
        id: proc

        command: ["python3", Quickshell.shellPath("hud_bridge.py")]
        // Otwarte stdin trzyma mostek przy życiu — jego EOF to koniec wyspy.
        stdinEnabled: true
        running: true

        stdout: SplitParser {
            splitMarker: "\n"

            onRead: data => {
                let msg;
                try {
                    msg = JSON.parse(data);
                } catch (e) {
                    return;
                }

                if (msg.type === "log") {
                    console.log("[hud] " + msg.text);
                } else if (msg.type === "brightness") {
                    root.brightnessNudged(msg.value);
                } else if (msg.type === "capslock") {
                    priv.capsLock = msg.on === true;
                    if (!msg.initial) root.capsLockToggled(priv.capsLock);
                } else if (msg.type === "numlock") {
                    priv.numLock = msg.on === true;
                    if (!msg.initial) root.numLockToggled(priv.numLock);
                }
            }
        }

        onStarted: priv.startedAt = Date.now()

        onExited: (exitCode, exitStatus) => {
            if (Date.now() - priv.startedAt > 10000) priv.failures = 0;
            if (++priv.failures >= root.maxFailures) {
                console.warn("hud_bridge.py kończy się (kod " + exitCode + "), zerknięcia jasności i Caps / Num Lock wyłączone.");
            } else {
                retry.restart();
            }
        }
    }
}
