pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Minutniki KClock (kclockd) przez kclock_bridge.py. Wyspa nie ma własnych:
// pokazuje i steruje tymi z aplikacji, więc obie strony widzą to samo.
//
// Pozostały czas liczymy tu, z `endsAt` (odliczanie) albo `length - elapsed`
// (pauza) — mostek wysyła stan tylko przy zmianie, nie co sekundę.
Singleton {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    property int restartDelayMs: 3000
    property int maxFailures: 3

    // Minutnik właśnie zadzwonił — wyspa pokazuje wtedy kartę zegara.
    signal rang(var timer)

    // ---------------------------------------------------------------
    // Stan
    // ---------------------------------------------------------------

    readonly property alias available: priv.available   // false = brak KClock / mostek padł
    readonly property alias timers: priv.timers

    // Wyspa ustawia (Binding), gdy sama pokazuje minutniki — wtedy własne
    // powiadomienia KClock o minutnikach są zbędne (NotificationService).
    property bool shownOnIsland: false

    // „Aktywny” = coś się na nim dzieje: odlicza, dzwoni albo stoi
    // w połowie. Pełny i zatrzymany to tylko gotowe ustawienie z listy.
    function isActive(t) { return t.running || t.ringing || t.elapsed > 0; }
    readonly property var activeTimers: priv.timers.filter(t => root.isActive(t))

    // Ten, który widać w pigułce: dzwoniący, potem najbliższy końca, potem
    // zatrzymany w połowie.
    readonly property var featured: {
        const a = activeTimers;
        if (a.length === 0) return null;
        const rank = t => t.ringing ? 0 : (t.running ? 1 : 2);
        return a.slice().sort((x, y) => rank(x) - rank(y)
            || (x.running && y.running ? x.endsAt - y.endsAt : 0))[0];
    }

    // Tyka tylko, gdy coś odlicza — inaczej zegar sekundowy budziłby
    // powiązania wyspy bez potrzeby.
    SystemClock {
        id: tick
        precision: SystemClock.Seconds
        enabled: root.activeTimers.some(t => t.running)
    }
    readonly property double now: tick.enabled ? tick.date.getTime() : Date.now()

    // Sekundy do końca. Zaokrąglone w górę: "0:01" ma wisieć, dopóki
    // naprawdę nie minie, a nie zmieniać się w "0:00" sekundę za wcześnie.
    function remaining(t) {
        if (!t) return 0;
        if (t.ringing) return 0;
        if (t.running) return Math.max(0, Math.ceil((t.endsAt - root.now) / 1000));
        return Math.max(0, t.length - t.elapsed);
    }

    // 45 → "0:45", 840 → "14:00", 3725 → "1:02:05"
    function format(seconds) {
        const s = Math.max(0, Math.round(seconds));
        const pad = n => (n < 10 ? "0" : "") + n;
        const h = Math.floor(s / 3600);
        const m = Math.floor(s / 60) % 60;
        return (h > 0 ? h + ":" + pad(m) : m) + ":" + pad(s % 60);
    }

    // Etykieta pomocnicza: własna nazwa albo długość. KClock nazywa każdy
    // nowy minutnik "Timer", co nic nie mówi.
    function caption(t) {
        if (t.label !== "" && t.label !== "Timer") return t.label;
        const m = Math.round(t.length / 60);
        return t.length % 60 === 0 ? m + " min" : root.format(t.length);
    }

    // Nowy minutnik w KClock, od razu odliczający. "Timer" jak nazywa je
    // sama aplikacja — caption() pokaże wtedy długość.
    function add(seconds) {
        if (!proc.running || seconds <= 0) return;
        proc.write(JSON.stringify({ cmd: "add", length: Math.round(seconds), label: "Timer" }) + "\n");
    }

    function toggle(t) { send("toggle", t); }
    function reset(t) { send("reset", t); }
    function dismiss(t) { send("dismiss", t); }
    function openApp() { Quickshell.execDetached(["kclock"]); }

    function send(cmd, t) {
        if (!t || !proc.running) return;
        proc.write(JSON.stringify({ cmd: cmd, id: t.id }) + "\n");
    }

    QtObject {
        id: priv
        property bool available: false
        property var timers: []
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

        command: ["python3", Quickshell.shellPath("kclock_bridge.py")]
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
                    console.log("[kclock] " + msg.text);
                } else if (msg.type === "state") {
                    const before = priv.timers;
                    priv.available = msg.available === true;
                    priv.timers = msg.timers || [];
                    for (const t of priv.timers) {
                        const old = before.find(o => o.id === t.id);
                        if (t.ringing && old && !old.ringing) root.rang(t);
                    }
                }
            }
        }

        onStarted: priv.startedAt = Date.now()

        onExited: (exitCode, exitStatus) => {
            priv.available = false;
            // 3 = KClock nie jest zainstalowany; restart nic nie zmieni.
            if (exitCode === 3) return;
            if (Date.now() - priv.startedAt > 10000) priv.failures = 0;
            if (++priv.failures >= root.maxFailures) {
                console.warn("kclock_bridge.py kończy się (kod " + exitCode + "), minutniki wyłączone.");
            } else {
                retry.restart();
            }
        }
    }
}
