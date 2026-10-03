pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Konfiguracja użytkownika: ~/.config/PluDynamicIsland/config.jsonc —
// poza projektem, żeby zmiana ustawień nie ruszała plików w gicie i żeby
// laptop i desktop mogły mieć różne wartości przy tym samym kodzie.
//
// Domyślne wartości i ich opis są w config.default.jsonc w projekcie. Ten
// sam plik jest szablonem kopii użytkownika: brak kopii -> zapisujemy go
// w całości, z komentarzami, żeby było co edytować. Kopia nadpisuje tylko
// to, co w niej jest, więc nowe opcje działają też ze starą kopią.
//
// JSONC, nie JSON i nie JsonAdapter: plik ma być edytowany ręcznie, a bez
// komentarzy nikt nie wie, co znaczy "pulseMin": 0.35. Ceną jest brak zapisu
// z poziomu wyspy — stan przełączany w UI (autoPause AirPodsów) zostaje
// w osobnym pliku z JsonAdapterem.
Singleton {
    id: root

    // Katalog wszystkich plików wyspy (też discord.json, token, airpods.json).
    // Dawniej ~/.config/quickshell-island — pliki z niego przejmują ich
    // właściciele (discord_bridge.py, AirPodsService), każdy swój, bo tylko
    // właściciel wie, kiedy zaczyna go czytać; wspólna przeprowadzka z QML
    // ścigałaby się ze startem mostków.
    readonly property string configDir: Quickshell.env("HOME") + "/.config/PluDynamicIsland"
    readonly property string legacyDir: Quickshell.env("HOME") + "/.config/quickshell-island"
    readonly property string userPath: configDir + "/config.jsonc"

    // Wynik scalenia domyślnych z kopią użytkownika. Komponenty czytają
    // sekcje (IslandConfig.expand.collapseDelay) do własnych nazwanych
    // właściwości na górze pliku.
    property var values: defaults
    readonly property var general: values.general
    readonly property var cards: values.cards
    readonly property var expand: values.expand
    readonly property var clock: values.clock
    readonly property var spectrum: values.spectrum
    readonly property var battery: values.battery
    readonly property var volume: values.volume
    readonly property var pills: values.pills
    readonly property var notifications: values.notifications
    readonly property var bluetooth: values.bluetooth
    readonly property var wifi: values.wifi

    // ---- wartości wyprowadzone ----

    // Każda klatka animacji w pętli to klatka całego ekranu w kompozytorze —
    // na laptopie (Intel UHD 630, 4K) puls obwódki trzymał GPU na 74% zamiast 11%.
    readonly property bool loopAnimations: general.loopAnimations === "on"
        || (general.loopAnimations !== "off" && !onLaptop)

    // Poniżej 60 wyspa nie dogładza słupków między klatkami (patrz
    // spectrumSmoothingMs), inaczej rysowałaby dalej co vsync.
    readonly property int cavaFramerate: spectrum.framerate > 0 ? spectrum.framerate
                                                                : (onLaptop ? 30 : 60)

    // `ready` przychodzi ~1 s po starcie; do tego czasu traktujemy maszynę
    // jak desktop, ale na laptopie i tak nie ma jeszcze czego animować
    // (obwódka czeka na tę samą baterię).
    readonly property bool onLaptop: UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery

    function cardHidden(key) { return cards.hidden.indexOf(key) >= 0; }

    // ---- walidacja ----

    // Poza typem (brany z wartości domyślnej) sprawdzamy tylko to, co
    // potrafi coś zepsuć: liczby ujemne (wszystkie), zakresy poniżej
    // i wartości z listy. Zła wartość -> ostrzeżenie i domyślna, nie
    // zgadywanie, co autor miał na myśli.
    readonly property var ranges: ({
        "spectrum.bars": [1, 12],
        "spectrum.framerate": [0, 240],
        "spectrum.noiseReduction": [0, 100],
        "battery.lowLevel": [0, 1],
        "battery.pulseMin": [0, 1],
        "battery.ringWidth": [0.5, 8],
        "volume.step": [0.005, 0.25],
        "notifications.historyLimit": [1, 500],
        "pills.maxWidth": [60, 600],
        "general.topMargin": [0, 200]
    })
    readonly property var choices: ({
        "general.loopAnimations": ["auto", "on", "off"],
        "cards.hidden": ["music", "discord", "clock", "connectivity", "notifications", "airpods"]
    })

    // ---- pliki ----

    // Synchronicznie: wartości muszą istnieć, zanim pierwszy komponent
    // przeczyta IslandConfig.expand.collapseDelay — inaczej start sypałby
    // "Unable to assign [undefined]".
    FileView {
        id: defaultsFile
        path: Quickshell.shellPath("config.default.jsonc")
        blockLoading: true
    }

    property var defaults: {
        const parsed = root.parseJsonc(defaultsFile.text(), "config.default.jsonc");
        if (parsed === null) console.warn("[config] config.default.jsonc w projekcie jest uszkodzony");
        return parsed ?? {};
    }

    FileView {
        id: userFile
        path: root.userPath
        blockLoading: true
        // Brak pliku to zwykły pierwszy start, nie błąd do logu.
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
        // Zapis dopiero po wyjściu z obsługi błędu odczytu — wołany w niej
        // setText trafia na kończącą się operację i Quickshell go gubi
        // ("got operation finished from dropped operation").
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) return;
            console.log("[config] brak " + root.userPath + ", zapisuję domyślny");
            Qt.callLater(() => userFile.setText(defaultsFile.text()));
        }
        // Obserwacja pliku, którego nie było, nic nie łapie — bez ponownego
        // wczytania pierwsza edycja świeżej kopii przeszłaby bez echa.
        onSaved: reload()
    }

    // Nowe domyślne (edycja projektu) też muszą przejść przez scalenie.
    onDefaultsChanged: if (userFile.loaded) apply(userFile.text())

    function apply(text) {
        const user = parseJsonc(text, root.userPath);
        // Błąd składni w połowie edycji nie może wyzerować całej konfiguracji —
        // zostaje ostatnia dobra.
        if (user === null) return;
        values = merge(defaults, user, "");
    }

    // ---- JSONC ----

    // Własny parser zamiast JSON.parse: V4 przy błędzie mówi tylko
    // "Parse error", bez miejsca, a w ręcznie edytowanym pliku linia błędu
    // to jedyna użyteczna informacja. Przy okazji rozumie komentarze
    // i przecinek po ostatnim elemencie.
    function parseJsonc(src, name) {
        if (src === undefined || src === null) return null;
        const text = String(src);
        let pos = 0;

        function fail(msg) { throw { jsonc: true, msg: msg, pos: pos }; }

        function skip() {
            for (;;) {
                while (pos < text.length && /\s/.test(text[pos])) pos++;
                if (text.startsWith("//", pos)) {
                    while (pos < text.length && text[pos] !== "\n") pos++;
                } else if (text.startsWith("/*", pos)) {
                    const end = text.indexOf("*/", pos + 2);
                    if (end < 0) fail("niezamknięty komentarz /*");
                    pos = end + 2;
                } else {
                    return;
                }
            }
        }

        function token(re, what) {
            const m = re.exec(text.slice(pos));
            if (!m) fail("oczekiwano: " + what);
            pos += m[0].length;
            return m[0];
        }

        function value() {
            skip();
            const c = text[pos];
            if (c === "{") return object();
            if (c === "[") return list();
            if (c === "\"") return string();
            if (c === "-" || (c >= "0" && c <= "9"))
                return Number(token(/^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/, "liczba"));
            if (text.startsWith("true", pos)) { pos += 4; return true; }
            if (text.startsWith("false", pos)) { pos += 5; return false; }
            if (text.startsWith("null", pos)) { pos += 4; return null; }
            fail(pos >= text.length ? "plik urywa się w połowie" : "nieoczekiwany znak '" + c + "'");
        }

        // Napis w cudzysłowie, bez nowej linii w środku; sekwencje \n, \" itd.
        // rozwija JSON.parse na samym napisie.
        function string() {
            return JSON.parse(token(/^"(?:[^"\\\n]|\\.)*"/, "napis w \"cudzysłowie\""));
        }

        function object() {
            const out = {};
            pos++;
            for (;;) {
                skip();
                if (text[pos] === "}") { pos++; return out; }
                if (text[pos] !== "\"") fail("oczekiwano nazwy w \"cudzysłowie\" albo }");
                const key = string();
                skip();
                if (text[pos] !== ":") fail("oczekiwano : po \"" + key + "\"");
                pos++;
                out[key] = value();
                skip();
                if (text[pos] === ",") { pos++; continue; }
                if (text[pos] === "}") { pos++; return out; }
                fail(pos >= text.length ? "plik urywa się, brakuje }" : "brak przecinka po \"" + key + "\"");
            }
        }

        function list() {
            const out = [];
            pos++;
            for (;;) {
                skip();
                if (text[pos] === "]") { pos++; return out; }
                out.push(value());
                skip();
                if (text[pos] === ",") { pos++; continue; }
                if (text[pos] === "]") { pos++; return out; }
                fail(pos >= text.length ? "plik urywa się, brakuje ]" : "brak przecinka w liście");
            }
        }

        try {
            skip();
            if (text[pos] !== "{") fail("plik ma zaczynać się od {");
            const result = object();
            skip();
            if (pos < text.length) fail("coś po ostatnim }");
            return result;
        } catch (e) {
            if (!e.jsonc) throw e;
            const before = text.slice(0, e.pos).split("\n");
            console.warn("[config] " + name + ":" + before.length + ":" + (before[before.length - 1].length + 1)
                         + ": " + e.msg + " — zostaje poprzednia konfiguracja");
            return null;
        }
    }

    // ---- scalanie ----

    function kind(v) {
        if (Array.isArray(v)) return "lista";
        if (v === null) return "null";
        switch (typeof v) {
        case "object": return "obiekt";
        case "number": return "liczba";
        case "string": return "tekst";
        case "boolean": return "true/false";
        }
        return typeof v;
    }

    function merge(def, user, path) {
        if (user === undefined) return def;
        const where = "[config] " + (path === "" ? "plik" : path);

        if (kind(def) !== kind(user)) {
            console.warn(where + ": oczekiwano: " + kind(def) + ", jest: " + kind(user) + " — biorę domyślne");
            return def;
        }

        if (kind(def) === "obiekt") {
            const out = {};
            for (const k in def) out[k] = merge(def[k], user[k], path === "" ? k : path + "." + k);
            for (const k in user) {
                if (!(k in def)) console.warn(where + ": nieznane ustawienie \"" + k + "\" (literówka?) — pomijam");
            }
            return out;
        }

        const allowed = choices[path];
        if (kind(def) === "lista") {
            if (!allowed) return user;
            const bad = user.filter(x => allowed.indexOf(x) < 0);
            if (bad.length > 0)
                console.warn(where + ": nieznane wartości " + JSON.stringify(bad) + ", dozwolone: " + allowed.join(", "));
            return user.filter(x => allowed.indexOf(x) >= 0);
        }

        if (allowed && allowed.indexOf(user) < 0) {
            console.warn(where + ": \"" + user + "\" nie jest jedną z: " + allowed.join(", ") + " — biorę domyślne");
            return def;
        }

        if (kind(def) === "liczba") {
            const r = ranges[path] ?? [0, Infinity];
            if (!isFinite(user) || user < r[0] || user > r[1]) {
                console.warn(where + ": " + user + " poza zakresem "
                             + r[0] + "–" + (r[1] === Infinity ? "∞" : r[1]) + " — biorę domyślne");
                return def;
            }
        }

        // Domyślny kolor ("#...") wymusza kolor: Qt zamieniłby literówkę
        // w czerń bez słowa.
        if (kind(def) === "tekst" && def.startsWith("#")
                && !/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(user)) {
            console.warn(where + ": \"" + user + "\" to nie kolor #rrggbb — biorę domyślne");
            return def;
        }

        return user;
    }
}
