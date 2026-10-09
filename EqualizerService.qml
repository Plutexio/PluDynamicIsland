pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Korektor dźwięku: 10 pasm na korektorze parametrycznym z lsp-plugins (LV2),
// wpiętym w PipeWire jako "smart filter" WirePlumbera.
//
// Smart filter, a nie wirtualny sink ustawiony jako domyślny (jak robi to
// EasyEffects): domyślnym wyjściem zostaje prawdziwe urządzenie, a WirePlumber
// sam wpina filtr przed nie i przenosi go razem ze zmianą wyjścia. Dzięki
// temu nie zmienia się nic, co patrzy na domyślny sink — głośność
// w AudioService, routedHere AirPodsów, wybór wyjścia w pigułce. Cava słucha
// monitora urządzenia, więc widmo pokazuje dźwięk już PO korekcji.
//
// Filtr to osobny proces `pipewire -c` (moduł filter-chain), dziecko wyspy:
// znika razem z nią i wtedy dźwięk wraca prosto do urządzenia (zmierzone —
// strumień przepina się sam). Wyłączony korektor = brak procesu, więc
// "wyłączony" znaczy bit w bit to samo, co bez wyspy.
//
// Zmiana pasm NIE restartuje procesu (to byłaby przerwa w dźwięku) —
// wartości idą w locie przez `pw-cli set-param … Props`.
Singleton {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    // Środki pasm, co oktawę. Pasma są rozstawione równo na osi
    // logarytmicznej, więc w panelu stoją w równych kolumnach.
    readonly property var frequencies: [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    readonly property var labels: ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    readonly property int bandCount: frequencies.length

    property real maxGain: 12          // zakres suwaka, ±dB
    property real gainStep: 0.5        // krok suwaka, dB
    // Dobroć filtrów dzwonowych. 1,41 to szerokość ~1 oktawy — sąsiednie
    // pasma zachodzą na siebie tak, że równe ustawienie daje gładką krzywą
    // zamiast grzebienia.
    property real bandQ: 1.41

    // Obniżenie wejścia o największe podbicie. Bez tego +6 dB na basie
    // przesterowuje głośny utwór na wyjściu do urządzenia (PipeWire obcina
    // przy konwersji do formatu karty). config.jsonc: equalizer.autoHeadroom.
    readonly property bool autoHeadroom: IslandConfig.equalizer.autoHeadroom

    readonly property string pluginUri: "http://lsp-plug.in/plugins/lv2/para_equalizer_x16_stereo"
    readonly property string sinkName: "island_eq"   // node.name wejścia filtra, po nim celuje pw-cli

    // pw-cli to proces na każdą zmianę (zmierzone: ~5 ms). Przeciąganie
    // suwaka daje dziesiątki zmian na sekundę, więc wysyłamy najwyżej co
    // tyle ms — zawsze najświeższy stan, nie kolejkę starych.
    property int applyIntervalMs: 40
    property int saveDelayMs: 600
    property int maxCustom: 8

    // Gotowe ustawienia (dB, od 31 Hz do 16 kHz).
    readonly property var presets: [
        { key: "flat",       name: "Płasko",      bands: [ 0,  0,  0,  0,  0,  0,  0,  0,  0,  0] },
        { key: "bass",       name: "Bas",         bands: [ 6,  5,  4,  2,  0,  0,  0,  0,  0,  0] },
        { key: "treble",     name: "Soprany",     bands: [ 0,  0,  0,  0,  0,  1,  2,  4,  5,  6] },
        { key: "vocal",      name: "Wokal",       bands: [-2, -2, -1,  0,  2,  4,  4,  2,  0, -1] },
        { key: "rock",       name: "Rock",        bands: [ 5,  4,  2, -1, -2, -1,  2,  3,  4,  4] },
        { key: "pop",        name: "Pop",         bands: [-1,  1,  3,  4,  3,  0, -1, -1,  1,  2] },
        { key: "electronic", name: "Elektronika", bands: [ 5,  4,  1,  0, -2,  1,  0,  1,  4,  5] },
        { key: "jazz",       name: "Jazz",        bands: [ 3,  2,  1,  2, -1, -1,  0,  1,  2,  3] },
        { key: "classical",  name: "Klasyka",     bands: [ 4,  3,  2,  1, -1, -1,  0,  2,  3,  4] },
        { key: "speech",     name: "Mowa",        bands: [-4, -3, -1,  1,  3,  4,  3,  1, -1, -3] }
    ]

    // ---------------------------------------------------------------
    // Stan
    // ---------------------------------------------------------------

    readonly property alias enabled: priv.enabled
    readonly property alias bands: priv.bands            // dB, bandCount liczb
    readonly property alias presetKey: priv.presetKey    // klucz gotowego | "custom:<id>" | "" = ręcznie
    readonly property alias custom: priv.custom          // [{id, name, bands}]
    readonly property alias available: priv.available    // false = filtr nie wstaje (brak lsp-plugins-lv2?)
    readonly property alias lastError: priv.lastError
    // Filtr naprawdę siedzi w grafie PipeWire (nie tylko proces wystartował).
    readonly property alias active: priv.nodePresent

    readonly property bool canSaveCustom: priv.custom.length < maxCustom

    // Gotowe + własne, w kolejności chipów w panelu.
    readonly property var choices: presets.map(p => ({ key: p.key, name: p.name, custom: false }))
        .concat(priv.custom.map(c => ({ key: "custom:" + c.id, name: c.name, custom: true })))

    readonly property string presetName: {
        const k = priv.presetKey;
        if (k === "") return "Własne ustawienia";
        const c = root.choices.find(p => p.key === k);
        return c ? c.name : "Własne ustawienia";
    }

    QtObject {
        id: priv

        property bool enabled: false
        property var bands: new Array(root.bandCount).fill(0)
        property string presetKey: "flat"
        property var custom: []

        property bool available: true
        property int failures: 0
        property double startedAt: 0
        property bool stopRequested: false
        property string lastError: ""

        property bool nodePresent: false
        property bool dirty: false
        property bool loaded: false
    }

    // ---- zmiany z UI ----
    // Dotknięcie korektora (pasmo, gotowe ustawienie) włącza go: suwak, który
    // przesuwa się bez słyszalnego skutku, wygląda na zepsuty.

    function setEnabled(on) {
        // Włączenie po awarii to nowa próba — może wtyczki właśnie doszły.
        if (on && !priv.available) {
            priv.available = true;
            priv.failures = 0;
        }
        priv.enabled = !!on;
        scheduleSave();
    }

    function setBand(index, db) {
        if (index < 0 || index >= root.bandCount) return;
        const v = Math.round(clampGain(db) / root.gainStep) * root.gainStep;
        if (priv.bands[index] === v && priv.enabled) return;

        const next = priv.bands.slice();
        next[index] = v;
        priv.bands = next;

        // Własne ustawienie aktywne -> poprawiamy je w miejscu. Gotowe
        // zostaje nietknięte, a stan przechodzi w "ręczny".
        const id = customId(priv.presetKey);
        if (id !== "") {
            priv.custom = priv.custom.map(c => c.id === id ? { id: c.id, name: c.name, bands: next } : c);
        } else {
            priv.presetKey = "";
        }

        priv.enabled = true;
        changed();
    }

    function selectPreset(key) {
        const id = customId(key);
        const src = id !== "" ? priv.custom.find(c => c.id === id) : root.presets.find(p => p.key === key);
        if (!src) return;
        priv.bands = src.bands.slice();
        priv.presetKey = key;
        priv.enabled = true;
        changed();
    }

    // Zapisuje bieżące pasma jako nowe własne ustawienie i od razu je wybiera.
    // Nazwa z najniższym wolnym numerem; zmienić ją można w equalizer.json
    // (wyspa czyta plik na żywo) — w UI nie ma pola tekstowego, bo to
    // wymagałoby klawiatury Exclusive jak w nakładkach.
    function saveCustom() {
        if (!root.canSaveCustom) return;
        const used = priv.custom.map(c => c.name);
        let n = 1;
        while (used.indexOf("Własny " + n) >= 0) n++;
        const id = Date.now().toString(36);
        priv.custom = priv.custom.concat([{ id: id, name: "Własny " + n, bands: priv.bands.slice() }]);
        priv.presetKey = "custom:" + id;
        scheduleSave();
    }

    function deleteCustom(key) {
        const id = customId(key);
        if (id === "") return;
        priv.custom = priv.custom.filter(c => c.id !== id);
        // Pasma zostają — usunięcie zapisu nie ma zmieniać tego, co słychać.
        if (priv.presetKey === key) priv.presetKey = "";
        scheduleSave();
    }

    function customId(key) {
        return typeof key === "string" && key.startsWith("custom:") ? key.slice(7) : "";
    }

    function clampGain(db) {
        const v = Number(db);
        return isFinite(v) ? Math.max(-root.maxGain, Math.min(root.maxGain, v)) : 0;
    }

    function changed() {
        scheduleSave();
        if (filter.running) {
            priv.dirty = true;
            if (!applyTimer.running) applyTimer.start();
        }
    }

    // ---- przeliczenia dla wtyczki ----
    // LSP przyjmuje wzmocnienia LINIOWO (port "G", 0,0158–63), nie w dB.

    function dbToGain(db) { return Math.pow(10, db / 20); }

    function inputGain() {
        if (!root.autoHeadroom) return 1;
        return dbToGain(-Math.max(0, ...priv.bands));
    }

    // Wartości startowe w configu filtra — proces rusza od razu z bieżącymi
    // pasmami, bez mrugnięcia płaskim dźwiękiem przed pierwszym pw-cli.
    function controlBlock() {
        const parts = ['"g_in" = ' + inputGain().toFixed(6)];
        for (let i = 0; i < root.bandCount; i++) {
            parts.push('"ft_' + i + '" = 1');    // 1 = Bell; pasma 10–15 zostają Off (domyślne 0)
            parts.push('"f_' + i + '" = ' + root.frequencies[i]);
            parts.push('"q_' + i + '" = ' + root.bandQ);
            parts.push('"g_' + i + '" = ' + dbToGain(priv.bands[i]).toFixed(6));
        }
        return parts.join(" ");
    }

    function paramsPod() {
        const parts = ['"eq:g_in"', inputGain().toFixed(6)];
        for (let i = 0; i < root.bandCount; i++)
            parts.push('"eq:g_' + i + '"', dbToGain(priv.bands[i]).toFixed(6));
        return "{ params = [ " + parts.join(" ") + " ] }";
    }

    onAutoHeadroomChanged: changed()

    // ---------------------------------------------------------------
    // Proces filtra
    // ---------------------------------------------------------------

    readonly property bool wanted: priv.enabled && priv.available && priv.loaded
    onWantedChanged: wanted ? startFilter() : stopFilter()

    function startFilter() {
        if (filter.running) return;
        filter.command = ["sh", "-c", root.filterScript()];
        filter.running = true;
    }

    // Jak w cavie: SIGTERM od Quickshella daje exitCode 15 / CrashExit, nie
    // do odróżnienia od awarii, więc własne zatrzymanie trzeba odnotować.
    function stopFilter() {
        if (!filter.running) return;
        priv.stopRequested = true;
        filter.running = false;
    }

    // Config przez heredoc do $XDG_RUNTIME_DIR, potem `exec`, żeby Quickshell
    // ubijał samego pipewire'a, a nie sh nad nim. Heredoc w apostrofach —
    // powłoka nie rozwija w nim niczego.
    //
    // capture = wejście filtra (sink, do którego WirePlumber wpina strumienie),
    // playback = wyjście do urządzenia. filter.smart bez filter.smart.target
    // = filtr dla DOMYŚLNEGO wyjścia, idzie za nim przy przełączeniu.
    // node.passive na wyjściu: bez dźwięku urządzenie może zasnąć jak zwykle.
    function filterScript() {
        return `
conf="\${XDG_RUNTIME_DIR:-/tmp}/quickshell-island-eq.conf"
cat > "$conf" <<'EOF'
context.properties = { log.level = 1 }
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-rt args = { } flags = [ ifexists nofail ] }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-filter-chain
      args = {
        node.description = "Korektor wyspy"
        media.name = "Korektor wyspy"
        filter.graph = {
          nodes = [
            { type = lv2 name = eq plugin = "${root.pluginUri}"
              control = { ${root.controlBlock()} } }
          ]
          inputs = [ "eq:in_l" "eq:in_r" ]
          outputs = [ "eq:out_l" "eq:out_r" ]
        }
        audio.position = [ FL FR ]
        capture.props = {
          node.name = "${root.sinkName}"
          media.class = Audio/Sink
          filter.smart = true
          filter.smart.name = "pludynamicisland-eq"
        }
        playback.props = {
          node.name = "${root.sinkName}_out"
          node.passive = true
        }
      }
    }
]
EOF
exec pipewire -c "$conf"
`;
    }

    Process {
        id: filter

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
            if (priv.stopRequested) {
                priv.stopRequested = false;
                // Włączony z powrotem, zanim stary proces zszedł.
                if (root.wanted) root.startFilter();
                return;
            }

            if (Date.now() - priv.startedAt > 10000) priv.failures = 0;

            // Brak wtyczki LV2 kończy pipewire'a od razu (zmierzone: kod 234).
            // Po dwóch takich startach odpuszczamy, zamiast mielić w kółko.
            if (++priv.failures >= 2) {
                priv.available = false;
                console.warn("Korektor nie wstał (kod " + exitCode + "), sprawdź lsp-plugins-lv2."
                    + (priv.lastError !== "" ? " Ostatni błąd: " + priv.lastError : ""));
            } else if (root.wanted) {
                retry.restart();
            }
        }
    }

    Timer {
        id: retry
        interval: 1500
        onTriggered: if (root.wanted) root.startFilter()
    }

    // ---- wysyłanie pasm w locie ----

    Timer {
        id: applyTimer
        interval: root.applyIntervalMs
        onTriggered: root.flush()
    }

    function flush() {
        // Węzła jeszcze nie ma — wyśle go pojawienie się (onNodePresentChanged).
        // pw-cli na nieistniejący węzeł kończy się kodem 0 i samym "unknown
        // global" na stderr, więc i tak nie dałoby się na nim polegać.
        if (!priv.dirty || !priv.nodePresent) return;
        // Poprzedni jeszcze leci — onExited wyśle to, co zebrało się w międzyczasie.
        if (setter.running) return;
        priv.dirty = false;
        setter.command = ["pw-cli", "set-param", root.sinkName, "Props", root.paramsPod()];
        setter.running = true;
    }

    // pw-cli wypisuje na stdout zrzut ustawionego obiektu — parser bez
    // obsługi, żeby nie trafiał do logu wyspy.
    Process {
        id: setter
        stdout: SplitParser {}
        onExited: if (priv.dirty) applyTimer.restart()
    }

    // Pojawienie się węzła po starcie: pasma zmienione między startem procesu
    // a wejściem filtra do grafu trzeba dosłać.
    function scanNodes() {
        const v = Pipewire.nodes.values;
        let found = false;
        for (let i = 0; i < v.length; i++)
            if (v[i].name === root.sinkName) { found = true; break; }
        priv.nodePresent = found;
    }

    Connections {
        target: Pipewire.nodes
        function onObjectInsertedPost() { root.scanNodes(); }
        function onObjectRemovedPost() { root.scanNodes(); }
    }

    Connections {
        target: priv
        function onNodePresentChanged() {
            if (!priv.nodePresent) return;
            priv.dirty = true;
            root.flush();
        }
    }

    // ---------------------------------------------------------------
    // Zapis stanu
    // ---------------------------------------------------------------

    // Stan przełączany w wyspie, więc osobny plik JSON (jak airpods.json),
    // nie config.jsonc — ten jest tylko do odczytu, zapis zgubiłby komentarze.
    function scheduleSave() { if (priv.loaded) saveTimer.restart(); }

    function snapshot() {
        return {
            enabled: priv.enabled,
            preset: priv.presetKey,
            bands: priv.bands,
            custom: priv.custom
        };
    }

    Timer {
        id: saveTimer
        interval: root.saveDelayMs
        onTriggered: stateFile.setText(JSON.stringify(root.snapshot(), null, 2) + "\n")
    }

    function validBands(b) {
        return Array.isArray(b) && b.length === root.bandCount && b.every(x => typeof x === "number" && isFinite(x));
    }

    function applyFile(text) {
        let s;
        try { s = JSON.parse(text); } catch (e) {
            console.warn("[equalizer] " + stateFile.path + " jest uszkodzony, zostaje poprzedni stan");
            return;
        }
        if (s === null || typeof s !== "object") return;

        // Własny zapis wraca przez obserwację pliku — nic się nie zmieniło,
        // a przypisanie pasm wysłałoby pw-cli bez powodu.
        if (JSON.stringify(s) === JSON.stringify(root.snapshot())) return;

        const custom = Array.isArray(s.custom)
            ? s.custom.filter(c => c && typeof c.id === "string" && typeof c.name === "string" && validBands(c.bands))
                      .map(c => ({ id: c.id, name: c.name, bands: c.bands.map(clampGain) }))
            : [];
        priv.custom = custom;
        if (validBands(s.bands)) priv.bands = s.bands.map(clampGain);
        if (typeof s.preset === "string") priv.presetKey = s.preset;
        priv.enabled = s.enabled === true;
        if (filter.running) {
            priv.dirty = true;
            if (!applyTimer.running) applyTimer.start();
        }
    }

    FileView {
        id: stateFile

        path: IslandConfig.configDir + "/equalizer.json"
        // Synchronicznie: proces filtra rusza z pasmami z pliku, a nie
        // najpierw z płaskimi i chwilę później z właściwymi.
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        // Pierwszy odczyt (blockLoading, jeszcze w trakcie budowy singletonu)
        // bierze Component.onCompleted — tu tylko późniejsze edycje pliku.
        onLoaded: if (priv.loaded) root.applyFile(text())
    }

    Component.onCompleted: {
        // Brak pliku = pierwszy start; zapis dopiero przy pierwszej zmianie.
        if (stateFile.loaded) applyFile(stateFile.text());
        priv.loaded = true;
        scanNodes();
    }
}
