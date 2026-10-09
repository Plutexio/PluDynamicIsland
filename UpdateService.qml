pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Aktualizacje z gita: przy starcie wyspy `git fetch` i porównanie HEAD
// z origin/master. Nowe commity -> wyspa rozwija się z listą i pyta.
// "Tak" = fast-forward do commita, który użytkownik widział; "Nie" = ten
// commit pomijamy na stałe (update.json), pytanie wróci przy następnym.
//
// Aktualizacja NIGDY nie rusza cudzej pracy: brudne drzewo, lokalne commity
// albo inna gałąź -> odmowa z powodem, bez stasha i bez merge'a.
Singleton {
    id: root

    // Gałąź, którą śledzimy. Na innej (gałąź robocza) nie sprawdzamy wcale.
    property string branch: "master"
    // Pierwsza próba chwilę po starcie: przy logowaniu sieć często jeszcze
    // nie wstała, a fetch bez sieci i tak by tylko poczekał na timeout.
    property int startDelayMs: 5000
    // Nieudany fetch (brak sieci) -> kolejna próba po tylu ms, najwyżej
    // maxAttempts razy na uruchomienie.
    property int retryMs: 60000
    property int maxAttempts: 5
    // Ile czekać na wynik aktualizacji, zanim uznamy ją za zawieszoną.
    property int applyTimeoutMs: 60000
    // "Zaktualizowano" wisi tyle ms i znika sam.
    property int doneMs: 3500

    readonly property bool checkEnabled: IslandConfig.updates.check
    readonly property string projectDir: Quickshell.shellDir
    readonly property string resultPath: Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-island-update.txt"

    // "idle" | "available" | "applying" | "done" | "failed"
    readonly property string phase: persist.phase
    readonly property bool prompting: phase !== "idle"
    // [{ hash, short, subject }], najnowszy pierwszy.
    readonly property var commits: {
        try { return JSON.parse(persist.commitsJson); } catch (e) { return []; }
    }
    readonly property string failReason: persist.failReason
    readonly property string failDetail: persist.failDetail
    readonly property string doneShort: persist.doneShort

    function accept() {
        if (persist.phase !== "available") return;
        persist.phase = "applying";
        persist.applyStartedAt = Date.now();
        // Odłączony, nie Process: merge podmienia pliki projektu, Quickshell
        // przeładowuje się w trakcie i niszczy Process razem ze starą
        // generacją — a zniszczony Process zabija dziecko. Git ubity
        // w połowie checkoutu zostawia index.lock i pół drzewa. Wynik
        // wraca plikiem, który czyta już nowa generacja (stan przechodzi
        // przez PersistentProperties).
        Quickshell.execDetached(["sh", "-c", root.applyScript, "sh",
                                 root.projectDir, root.branch, root.resultPath, persist.tip]);
    }

    function decline() {
        if (persist.phase !== "available") return;
        skipFile.skipped = persist.tip;
        persist.phase = "idle";
    }

    // Zamknięcie komunikatu po błędzie / sukcesie. Po błędzie commit NIE
    // jest pomijany — przy następnym starcie pytanie wróci.
    function dismiss() {
        if (persist.phase === "failed" || persist.phase === "done") persist.phase = "idle";
    }

    // ---- stan przez przeładowanie ----
    // Wyspa przeładowuje pliki na żywo, a sama aktualizacja jest takim
    // przeładowaniem. Bez tego nowa generacja zgubiłaby "applying" (i nie
    // przeczytała wyniku) albo sprawdzała od nowa po każdej edycji pliku.
    PersistentProperties {
        id: persist
        reloadableId: "updateService"

        // true dopiero po ZAKOŃCZONYM sprawdzeniu: przeładowanie w trakcie
        // fetcha ubija proces, więc nowa generacja ma zacząć od nowa.
        property bool checked: false
        property string phase: "idle"
        property string commitsJson: "[]"
        property string tip: ""
        property string failReason: ""
        property string failDetail: ""
        property string doneShort: ""
        property double applyStartedAt: 0

        onLoaded: {
            if (!checked && root.checkEnabled) startTimer.start();
        }
    }

    Timer {
        id: startTimer
        interval: root.startDelayMs
        onTriggered: checkProc.running = true
    }

    property int attempts: 0

    Timer {
        id: retryTimer
        interval: root.retryMs
        onTriggered: checkProc.running = true
    }

    // ---- sprawdzanie ----
    // Kody wyjścia: 21 = inna gałąź, 22 = fetch nieudany (sieć). GIT_TERMINAL_PROMPT
    // i BatchMode: remote wymagający logowania ma się wyłożyć, a nie wisieć
    // na pytaniu o hasło, którego nikt nie zobaczy.
    readonly property string checkScript: `
        cd "$1" || exit 20
        [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$2" ] || exit 21
        export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes"
        timeout 30 git fetch --quiet origin "$2" || exit 22
        git log --format="%H%x1f%h%x1f%s" "HEAD..origin/$2"
    `

    Process {
        id: checkProc

        command: ["sh", "-c", root.checkScript, "sh", root.projectDir, root.branch]
        stdout: StdioCollector { id: checkOut }

        onExited: (code, status) => {
            root.attempts++;
            if (code === 22 && root.attempts < root.maxAttempts) {
                retryTimer.start();
                return;
            }
            persist.checked = true;
            if (code === 21) return;   // gałąź robocza, nie nasza sprawa
            if (code !== 0) {
                console.log("[update] nie udało się sprawdzić aktualizacji (kod " + code + ")");
                return;
            }
            root.handleCommits(checkOut.text);
        }
    }

    function handleCommits(text) {
        const list = text.split("\n").filter(l => l !== "").map(l => {
            const f = l.split("\x1f");
            return { hash: f[0], short: f[1], subject: f.slice(2).join("\x1f") };
        });
        if (list.length === 0) return;
        if (list[0].hash === skipFile.skipped) {
            console.log("[update] " + list[0].short + " pominięty wcześniej, nie pytam");
            return;
        }
        console.log("[update] nowe commity na " + root.branch + ": " + list.length);
        persist.commitsJson = JSON.stringify(list);
        persist.tip = list[0].hash;
        persist.phase = "available";
    }

    // ---- aktualizacja ----
    // Nieśledzone pliki (zostawione sondy, logi) nie blokują: merge ich nie
    // rusza, a gdyby nowy commit miał nadpisać któryś z nich, git sam
    // odmówi ("would be overwritten") i trafi to do "failed" ze szczegółem.
    //
    // Fast-forward do `tip`, czyli dokładnie do commita z listy, którą
    // użytkownik zatwierdził — bez ponownego fetcha, który mógłby dociągnąć
    // coś, czego nie widział. Wynik: pierwsza linia kod, druga szczegół,
    // trzecia tip (odsiewa wynik starszej próby). Zapis przez mv, żeby
    // odczyt nie trafił na pół pliku.
    readonly property string applyScript: `
        out=$3; tip=$4
        rm -f "$out"
        finish() {
            printf "%s\\n%s\\n%s\\n" "$1" "$(printf "%s" "$2" | tr "\\n" " ")" "$tip" > "$out.tmp"
            mv -f "$out.tmp" "$out"
            exit 0
        }
        cd "$1" || finish failed "brak katalogu $1"
        head=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        [ "$head" = "$2" ] || finish branch "$head"
        dirty=$(git status --porcelain --untracked-files=no 2>&1)
        [ -z "$dirty" ] || finish dirty "$(printf "%s\\n" "$dirty" | head -n 4)"
        ahead=$(git rev-list --count "$tip..HEAD" 2>&1)
        [ "$ahead" = 0 ] || finish ahead "$ahead"
        err=$(git merge --ff-only --quiet "$tip" 2>&1) || finish failed "$err"
        finish done "$(git rev-parse --short HEAD)"
    `

    FileView {
        id: resultFile
        path: root.resultPath
        printErrors: false
        onLoaded: root.handleResult(text())
    }

    // Plik pojawia się dopiero po wyjściu gita, a obserwacja nieistniejącego
    // pliku nie łapie jego powstania — więc odpytujemy, tylko w trakcie.
    Timer {
        interval: 300
        repeat: true
        running: root.phase === "applying"
        onTriggered: {
            if (Date.now() - persist.applyStartedAt > root.applyTimeoutMs) {
                root.fail("timeout", "");
                return;
            }
            resultFile.reload();
        }
    }

    function handleResult(text) {
        if (persist.phase !== "applying") return;
        const lines = text.split("\n");
        if (lines.length < 3 || lines[2] !== persist.tip) return;
        const code = lines[0];
        const detail = lines[1];
        if (code === "done") {
            console.log("[update] zaktualizowano do " + detail);
            persist.doneShort = detail;
            persist.phase = "done";
        } else {
            root.fail(code, detail);
        }
    }

    function fail(code, detail) {
        console.warn("[update] aktualizacja odrzucona: " + code + (detail !== "" ? " — " + detail : ""));
        persist.failReason = ({
            dirty: "Masz niezapisane zmiany w projekcie",
            ahead: "Masz lokalne commity, których nie ma na " + root.branch,
            branch: "Projekt nie jest na gałęzi " + root.branch,
            timeout: "Git nie odpowiedział",
            failed: "Git odmówił aktualizacji"
        })[code] ?? "Nieznany błąd";
        persist.failDetail = code === "ahead" ? detail + " do przodu — zaktualizuj ręcznie (git pull)"
            : code === "dirty" ? detail
            : code === "branch" ? "Teraz: " + detail
            : detail;
        persist.phase = "failed";
    }

    Timer {
        interval: root.doneMs
        running: root.phase === "done"
        onTriggered: root.dismiss()
    }

    // ---- pominięte commity ----
    // Stan per maszyna, poza projektem (jak airpods.json). Brak pliku =
    // nic nie pominięto; zapisuje go dopiero pierwsze "Nie".
    FileView {
        id: skipStore
        path: IslandConfig.configDir + "/update.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: skipFile
            property string skipped: ""
        }
    }
}
