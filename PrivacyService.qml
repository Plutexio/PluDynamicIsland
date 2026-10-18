pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Co w tej chwili nagrywa albo odbiera: ekran, mikrofon, kamera. Wyspa
// pokazuje to pigułką udostępniania i kropką prywatności jak w iOS
// (pomarańczowa = mikrofon, zielona = kamera).
//
// Ekran i mikrofon: `pw-dump -m` zamiast odpytywania co kilka sekund.
// Pierwszy zrzut to wszystkie obiekty, potem przychodzi tablica z każdą
// zmianą, a usunięty obiekt to {"id": N, "info": null}. Aktualizacja zawiera
// pełny stan i właściwości (nie deltę), więc wystarczy podmienić wpis w mapie.
//
// Kamera: camera_watch.py — patrz komentarz w nim, czemu nie PipeWire.
Singleton {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    // Odbiorcy strumienia wideo, którzy NIE są udostępnianiem ekranu:
    // plasmashell konsumuje kwin_wayland na potrzeby miniatur okien.
    property var ignoredScreenApps: ["plasmashell"]
    // Aplikacje, które nie zapalają kropki mikrofonu (np. easyeffects
    // trzyma mikrofon stale, żeby go filtrować).
    readonly property var ignoredMicApps: IslandConfig.privacy.ignoredApps

    // Przez tyle ms od startu nie zgłaszamy started(): instancja przeładowuje
    // się na żywo i trwająca rozmowa dawałaby zerknięcie przy każdej edycji.
    property int startupGraceMs: 3000

    property int restartDelayMs: 3000
    property int maxFailures: 3

    // Mikrofon albo kamera właśnie zaczęły być używane. kind: "mic" | "camera".
    signal started(string kind, var apps)

    // ---------------------------------------------------------------
    // Stan
    // ---------------------------------------------------------------

    readonly property alias screenActive: priv.screenActive
    readonly property alias screenApp: priv.screenApp            // kto odbiera ekran
    readonly property alias screenElapsedSeconds: priv.screenElapsedSeconds

    readonly property alias micApps: priv.micApps
    readonly property bool micActive: priv.micApps.length > 0
    readonly property var cameraApps: {
        const out = [];
        for (const h of priv.cameraHolders) {
            // PipeWire trzyma urządzenie w imieniu swojego klienta —
            // właściwą nazwę daje link do strumienia.
            const names = (h.name === "pipewire" || h.name === "wireplumber")
                ? (priv.pwCameraApps.length > 0 ? priv.pwCameraApps : ["PipeWire"])
                : [root.pretty(h.name)];
            for (const n of names) if (out.indexOf(n) < 0) out.push(n);
        }
        return out;
    }
    readonly property bool cameraActive: cameraApps.length > 0

    readonly property alias available: priv.available    // false = pw-dump nie działa

    QtObject {
        id: priv
        property bool screenActive: false
        property string screenApp: ""
        property double screenStart: 0
        property int screenElapsedSeconds: 0
        property var micApps: []
        property var pwCameraApps: []
        property var cameraHolders: []
        property bool available: true
        property int failures: 0
        property double startedAt: 0
        property bool stopRequested: false
        property int cameraFailures: 0
        property double createdAt: Date.now()

        // id -> { cls, app, state, camera, monitor } dla węzłów,
        // id -> { out, in, state } dla linków. Reszty obiektów nie trzymamy.
        property var nodes: ({})
        property var links: ({})
        property var lines: []
    }

    // Ta sama pułapka co z timerem rozmowy: Timer 1000 ms dryfuje i licznik
    // potrafi skoczyć o 2. SystemClock tyka równo z sekundą.
    SystemClock {
        id: shareClock
        precision: SystemClock.Seconds
        enabled: priv.screenActive && priv.screenStart > 0
    }

    Binding {
        target: priv
        property: "screenElapsedSeconds"
        value: (priv.screenActive && priv.screenStart > 0)
            ? Math.max(0, Math.floor((shareClock.date.getTime() - priv.screenStart) / 1000))
            : 0
    }

    function pretty(name) {
        return name === "" ? "Nieznana aplikacja" : name.charAt(0).toUpperCase() + name.slice(1);
    }

    // Chromium (Brave, Discord) podpisuje strumień mikrofonu nazwą silnika
    // WebRTC, a nie aplikacji — wtedy lepsza jest nazwa pliku wykonywalnego.
    function appOf(props) {
        const name = props["application.name"] || "";
        if (name === "" || /^(webrtc voiceengine|chromium( input)?|alsa plug-in.*)$/i.test(name))
            return props["application.process.binary"] || props["node.name"] || name;
        return name;
    }

    // Bez wielkości liter: w zerknięciu nazwa ma wielką literę (pretty),
    // a w PipeWire zwykle małą.
    function micIgnored(app) {
        const a = app.toLowerCase();
        return root.ignoredMicApps.some(x => x.toLowerCase() === a);
    }

    function applyUpdate(objects) {
        let changed = false;

        for (let i = 0; i < objects.length; i++) {
            const o = objects[i];
            if (o.info === null) {
                if (o.id in priv.nodes) { delete priv.nodes[o.id]; changed = true; }
                if (o.id in priv.links) { delete priv.links[o.id]; changed = true; }
                continue;
            }

            if (o.type === "PipeWire:Interface:Link") {
                priv.links[o.id] = {
                    out: o.info["output-node-id"],
                    in: o.info["input-node-id"],
                    state: o.info.state || ""
                };
                changed = true;
                continue;
            }
            if (o.type !== "PipeWire:Interface:Node") continue;

            const props = o.info.props || {};
            const cls = props["media.class"] || "";
            const api = props["device.api"] || "";
            priv.nodes[o.id] = {
                cls: cls,
                app: root.appOf(props),
                state: o.info.state || "",
                camera: cls === "Video/Source" && (api === "v4l2" || api === "libcamera"),
                // Pomiar poziomu (pasek w mikserze) to nie nagrywanie.
                monitor: props["stream.monitor"] === true || props["stream.monitor"] === "true"
            };
            changed = true;
        }

        if (changed) root.evaluate();
    }

    function evaluate() {
        // Mikrofon = aktywny link ze źródła (mikrofonu) do strumienia aplikacji.
        // Po samej klasie strumienia się nie da: cava to też Stream/Input/Audio,
        // tyle że podpięty do Audio/Sink, czyli monitora wyjścia (zmierzone).
        const mic = [];
        const pwCam = [];
        const camStreams = {};
        for (const id in priv.links) {
            const l = priv.links[id];
            if (l.state !== "active") continue;
            const src = priv.nodes[l.out];
            const dst = priv.nodes[l.in];
            if (!src || !dst || dst.state !== "running") continue;

            if (src.cls.startsWith("Audio/Source") && dst.cls === "Stream/Input/Audio"
                    && !dst.monitor && !root.micIgnored(dst.app)) {
                const n = root.pretty(dst.app);
                if (mic.indexOf(n) < 0) mic.push(n);
            } else if (src.camera && dst.cls === "Stream/Input/Video") {
                camStreams[l.in] = true;
                const n = root.pretty(dst.app);
                if (pwCam.indexOf(n) < 0) pwCam.push(n);
            }
        }

        // Ekran = działający strumień wideo do aplikacji, który nie idzie
        // z kamery i nie należy do samego pulpitu.
        let screen = "";
        for (const id in priv.nodes) {
            const n = priv.nodes[id];
            if (n.cls !== "Stream/Input/Video" || n.state !== "running" || camStreams[id]) continue;
            if (root.ignoredScreenApps.indexOf(n.app) !== -1) continue;
            screen = n.app !== "" ? n.app : "Nieznana aplikacja";
            break;
        }

        const nowActive = screen !== "";
        if (nowActive && !priv.screenActive) {
            priv.screenStart = Date.now();
            console.log("[privacy] start udostępniania: " + screen);
        } else if (!nowActive && priv.screenActive) {
            priv.screenStart = 0;
            console.log("[privacy] koniec udostępniania");
        }
        priv.screenActive = nowActive;
        priv.screenApp = screen;

        if (JSON.stringify(mic) !== JSON.stringify(priv.micApps)) priv.micApps = mic;
        if (JSON.stringify(pwCam) !== JSON.stringify(priv.pwCameraApps)) priv.pwCameraApps = pwCam;
    }

    onMicActiveChanged: if (micActive) announce("mic", micApps)
    onCameraActiveChanged: if (cameraActive) announce("camera", cameraApps)

    function announce(kind, apps) {
        console.log("[privacy] " + (kind === "mic" ? "mikrofon" : "kamera") + ": " + apps.join(", "));
        if (Date.now() - priv.createdAt < root.startupGraceMs) return;
        root.started(kind, apps);
    }

    // ---- PipeWire ----

    Timer {
        id: retry
        interval: root.restartDelayMs
        onTriggered: if (priv.available) proc.running = true
    }

    Process {
        id: proc

        command: ["pw-dump", "-m", "-N"]
        running: true

        // pw-dump drukuje tablice wieloliniowo. Granica to samotny "]" na
        // początku linii — wszystko w środku jest wcięte, więc nie ma
        // fałszywych trafień.
        stdout: SplitParser {
            splitMarker: "\n"

            onRead: data => {
                priv.lines.push(data);
                if (data !== "]") return;

                const text = priv.lines.join("\n");
                priv.lines = [];

                let objects;
                try {
                    objects = JSON.parse(text);
                } catch (e) {
                    console.warn("[privacy] nieczytelna tablica z pw-dump, pomijam");
                    return;
                }
                if (Array.isArray(objects)) root.applyUpdate(objects);
            }
        }

        onStarted: {
            priv.startedAt = Date.now();
            priv.nodes = ({});
            priv.links = ({});
            priv.lines = [];
        }

        onExited: (exitCode, exitStatus) => {
            priv.nodes = ({});
            priv.links = ({});
            priv.lines = [];
            root.evaluate();

            // SIGTERM od Quickshella daje exitCode 15 / CrashExit — patrz CavaService.
            if (priv.stopRequested) {
                priv.stopRequested = false;
                return;
            }

            if (Date.now() - priv.startedAt > 10000) priv.failures = 0;

            if (++priv.failures >= root.maxFailures) {
                priv.available = false;
                console.warn("pw-dump -m nie działa (kod " + exitCode + "), udostępnianie ekranu i mikrofon bez podglądu.");
            } else {
                retry.restart();
            }
        }
    }

    // ---- kamera ----

    Timer {
        id: cameraRetry
        interval: root.restartDelayMs
        onTriggered: cameraProc.running = true
    }

    Process {
        id: cameraProc

        command: ["python3", Quickshell.shellPath("camera_watch.py")]
        // Otwarte stdin trzyma pomocnika przy życiu — jego EOF to koniec wyspy.
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
                if (msg.type === "camera") priv.cameraHolders = msg.holders || [];
            }
        }

        onExited: (exitCode, exitStatus) => {
            priv.cameraHolders = [];
            if (++priv.cameraFailures >= root.maxFailures) {
                console.warn("camera_watch.py kończy się (kod " + exitCode + "), kropka kamery wyłączona.");
            } else {
                cameraRetry.restart();
            }
        }
    }
}
