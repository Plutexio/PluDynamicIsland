pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Spektrum dźwięku z cavy. Singleton, żeby chodził najwyżej jeden proces
// niezależnie od tego, ile wysp go pyta.
Singleton {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    // Ustawienia z config.jsonc (IslandConfig, sekcja "spectrum").
    readonly property int barCount: IslandConfig.spectrum.bars

    // 60 fps zamiast 30 to nie tylko płynniejszy rysunek — własny filtr cavy
    // liczy się per klatka, więc podniesienie framerate samo w sobie
    // przyspiesza reakcję słupków (zmierzone: 66 -> 117 punktów zmiany/s).
    // Domyślnie per maszyna (IslandConfig) — na laptopie 30.
    readonly property int framerate: IslandConfig.cavaFramerate

    // Wygładzanie po stronie cavy (filtry integral + gravity), 0-100.
    // Domyślne cavy to 77 i wygląda zaspanie. 35 daje ~2,8x wiecej życia,
    // a skok między klatkami trzyma w okolicy 3 punktów, więc słupki
    // nie zaczynają migotać. Niżej = szybciej i nerwowo, wyżej = leniwie.
    readonly property int noiseReduction: IslandConfig.spectrum.noiseReduction
    readonly property int lingerMs: IslandConfig.spectrum.lingerMs   // ile trzymać cavę przy życiu po zatrzymaniu muzyki

    // ---------------------------------------------------------------
    // Stan
    // ---------------------------------------------------------------

    // Ktoś chce widzieć spektrum (np. wyspa, gdy muzyka gra).
    property bool wanted: false

    // Poziomy 0..1, długości barCount.
    readonly property alias levels: priv.levels

    // Czy cava faktycznie działa. Jak nie — wyspa wraca do zwykłej kropki.
    readonly property alias available: priv.available

    QtObject {
        id: priv
        property var levels: new Array(root.barCount).fill(0)
        property bool available: true
        property int failures: 0
        property double startedAt: 0
        property bool stopRequested: false
        property bool restartRequested: false
        property string lastError: ""
    }

    // Zatrzymanie z naszej inicjatywy. Musimy je odnotować, bo Quickshell ubija
    // proces SIGTERM-em, a to daje exitCode 15 / CrashExit — nie do odróżnienia
    // po samym kodzie od cavy, która padła sama z siebie.
    function stopCava() {
        if (!proc.running) return;
        priv.stopRequested = true;
        proc.running = false;
    }

    // Cava padła, choć miała grać — spróbuj jeszcze raz za chwilę.
    Timer {
        id: retry
        interval: 1500
        onTriggered: if (root.wanted && priv.available) proc.running = true
    }

    // Po zatrzymaniu muzyki nie ubijamy cavy od razu: pauza w utworze nie
    // powinna kosztować restartu procesu (autosens musiałby się uczyć od nowa).
    Timer {
        id: linger
        interval: root.lingerMs
        onTriggered: root.stopCava()
    }

    // Konfig cavy powstaje przy starcie procesu, więc każda zmiana jego
    // parametrów (edycja config.jsonc, UPower rozpoznający laptopa ~1 s po
    // starcie) wymaga restartu. Start dopiero w onExited — przestawienie
    // `running` na true, zanim stary proces zejdzie, nic by nie dało.
    function restartForConfig() {
        if (!proc.running) return;
        priv.restartRequested = true;
        stopCava();
    }
    onFramerateChanged: restartForConfig()
    onNoiseReductionChanged: restartForConfig()
    // Stara cava dalej przysyła ramki ze starą liczbą słupków, a parser
    // odrzuca każdą o złej długości — słupki zamarłyby do restartu.
    onBarCountChanged: {
        priv.levels = new Array(barCount).fill(0);
        restartForConfig();
    }

    onWantedChanged: {
        if (wanted) {
            linger.stop();
            if (priv.available) proc.running = true;
        } else if (proc.running) {
            linger.restart();
        }
    }

    Process {
        id: proc

        // Konfig cavy leci przez heredoc do pliku w $XDG_RUNTIME_DIR, a potem
        // `exec` podmienia powłokę na cavę — dzięki temu zabicie procesu przez
        // Quickshella ubija samą cavę, a nie zostawia jej osieroconej pod sh.
        //
        // channels = mono, bo przy stereo cava wymaga parzystej liczby słupków.
        command: ["sh", "-c", `
conf="\${XDG_RUNTIME_DIR:-/tmp}/quickshell-island-cava.conf"
cat > "$conf" <<EOF
[general]
framerate = ${root.framerate}
bars = ${root.barCount}
autosens = 1
[input]
method = pipewire
source = auto
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 100
channels = mono
bar_delimiter = 59
frame_delimiter = 10
[smoothing]
noise_reduction = ${root.noiseReduction}
EOF
exec cava -p "$conf"
`]

        stdout: SplitParser {
            splitMarker: "\n"

            onRead: data => {
                // Cava potrafi na starcie wypluć sekwencję tytułu terminala,
                // więc każdą klatkę walidujemy zamiast ufać, że to liczby.
                const parts = data.split(";");
                const out = [];

                for (let i = 0; i < parts.length; i++) {
                    const t = parts[i].trim();
                    if (t === "") continue;          // ogonek po ostatnim ';'
                    const n = parseInt(t, 10);
                    if (!isFinite(n)) return;        // śmieci — pomijamy klatkę
                    out.push(Math.max(0, Math.min(1, n / 100)));
                }

                if (out.length === root.barCount) priv.levels = out;
            }
        }

        // Stderr trzymamy, żeby przy awarii było co wpisać do logu zamiast
        // samego kodu wyjścia.
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const t = data.trim();
                if (t !== "") priv.lastError = t;
            }
        }

        onStarted: {
            priv.startedAt = Date.now();
            priv.lastError = "";
        }

        onExited: (exitCode, exitStatus) => {
            priv.levels = new Array(root.barCount).fill(0);

            // Sami o to poprosiliśmy — nic się nie stało.
            if (priv.stopRequested) {
                priv.stopRequested = false;
                if (priv.restartRequested) {
                    priv.restartRequested = false;
                    if (root.wanted && priv.available) proc.running = true;
                }
                return;
            }

            // Proces, który przeżył dłuższą chwilę, działał poprawnie —
            // nie chcemy, żeby pojedyncze potknięcia sumowały się przez
            // wiele godzin sesji i w końcu wyłączyły wizualizację.
            if (Date.now() - priv.startedAt > 10000) priv.failures = 0;

            // Cava nie działa (brak w systemie, zły backend audio…).
            // Po dwóch nieudanych startach odpuszczamy i wyspa wraca do kropki,
            // zamiast w kółko odpalać proces, który i tak padnie.
            if (++priv.failures >= 2) {
                priv.available = false;
                console.warn("cava nie działa (kod " + exitCode + "), wyspa wraca do kropki."
                    + (priv.lastError !== "" ? " Ostatni błąd: " + priv.lastError : ""));
            } else if (root.wanted) {
                retry.restart();
            }
        }
    }
}
