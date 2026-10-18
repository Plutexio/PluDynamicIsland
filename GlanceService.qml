pragma Singleton

import QtQuick
import Quickshell

// Zerknięcia: krótkie komunikaty w zwiniętej pigułce — głośność, ładowarka,
// mikrofon / kamera, koniec komendy w terminalu, dowolny skrypt przez IPC
// (`ipc call island glance`). Pigułka rośnie na ich czas, ale wyspa się nie
// rozwija: to ma być zerknięcie, a nie karta pod kursorem.
//
// Jedna kolejka dla wszystkich. Wcześniej każde zerknięcie miało własną
// flagę, timer i piętro w `restingWidth`, a każde nowe dokładało warunek
// w kilku miejscach wyspy; dwa naraz nadpisywały się bez żadnej reguły.
//
// Reguły:
// - ten sam `key` co pokazywany = podmiana na miejscu i licznik od nowa
//   (kolejne naciśnięcia klawisza głośności to jedno zerknięcie);
// - wyższy `priority` wypiera bieżące, które wraca do kolejki z resztą
//   swojego czasu, jeśli może czekać (`waitMs` > 0) i zostało mu dość
//   (`minRemainingMs`), a niższy albo równy staje w kolejce;
// - `waitMs` = ile wpis może czekać w kolejce; 0 = teraz albo wcale
//   (głośność sprzed pół minuty nikogo nie obchodzi);
// - `suppressed` (wyspa rozwinięta albo schowana) zdejmuje bieżące — skoro
//   ktoś sięga po kartę, to jej chce — a nowe odkłada albo odrzuca.
Singleton {
    id: root

    // Przerwa między dwoma zerknięciami z kolejki: pigułka zdąży wrócić do
    // zegara, więc widać, że to dwa komunikaty, a nie podmiana tekstu.
    property int gapMs: 380
    // Wyparte zerknięcie, któremu zostało mniej, nie wraca: mignęłoby tylko.
    property int minRemainingMs: 1200

    // Ustawia wyspa (Binding): rozwinięta albo schowana.
    property bool suppressed: false

    // Pokazywane zerknięcie albo null. Zawsze nowy obiekt — powiązania
    // przeliczają się przy każdej podmianie.
    readonly property alias current: priv.current

    QtObject {
        id: priv
        property var current: null
        property var queue: []
        property int serial: 0
        property double shownAt: 0
    }

    // spec (wszystko opcjonalne):
    //   key        — tożsamość do podmiany na miejscu; brak = każde osobno
    //   icon       — nazwa z IslandIcon (nieznana → "bell")
    //   title      — tekst po lewej, obcinany przy braku miejsca
    //   value      — tekst po prawej
    //   progress   — 0–1, pasek zamiast tytułu; brak = bez paska
    //   iconColor, valueColor, barColor
    //   minWidth   — najmniejsza szerokość pigułki, px
    //   durationMs, priority, waitMs — patrz reguły wyżej
    function show(spec) {
        const g = normalize(spec);

        if (priv.current && priv.current.key === g.key) {
            present(g);
            return;
        }
        if (root.suppressed) {
            enqueue(g);
            return;
        }
        if (!priv.current) {
            gapTimer.stop();
            present(g);
            return;
        }
        if (g.priority > priv.current.priority) {
            // Z pełnym czasem komenda wyparta dwa razy pokazałaby się trzy
            // razy po 4 s (zmierzone), choć widać ją było już przez większość.
            const left = priv.current.durationMs - (Date.now() - priv.shownAt);
            if (left >= root.minRemainingMs)
                enqueue(Object.assign({}, priv.current, { durationMs: left, queuedAt: Date.now() }));
            present(g);
            return;
        }
        enqueue(g);
    }

    function dismiss(key) {
        priv.queue = priv.queue.filter(g => g.key !== key);
        if (priv.current && priv.current.key === key) finish();
    }

    function normalize(spec) {
        return {
            key: spec.key ?? ("glance-" + (++priv.serial)),
            icon: spec.icon ?? "bell",
            title: spec.title ?? "",
            value: spec.value ?? "",
            progress: typeof spec.progress === "number" ? Math.max(0, Math.min(1, spec.progress)) : -1,
            iconColor: spec.iconColor ?? "#f2f2f2",
            valueColor: spec.valueColor ?? "#f2f2f2",
            barColor: spec.barColor ?? "#ededf0",
            minWidth: spec.minWidth ?? 0,
            durationMs: spec.durationMs ?? 2500,
            priority: spec.priority ?? 1,
            waitMs: spec.waitMs ?? 0,
            queuedAt: Date.now()
        };
    }

    function enqueue(g) {
        if (g.waitMs <= 0) return;
        priv.queue = priv.queue.filter(q => q.key !== g.key).concat([g]);
    }

    function present(g) {
        // Podmiana tego samego klucza nie zeruje shownAt — liczy się czas na ekranie.
        if (!priv.current || priv.current.key !== g.key) priv.shownAt = Date.now();
        priv.current = g;
        shownTimer.interval = g.durationMs;
        shownTimer.restart();
    }

    function finish() {
        shownTimer.stop();
        priv.current = null;
        if (priv.queue.length > 0) gapTimer.restart();
    }

    // Najwyższy priorytet, przy remisie najstarszy. Przeterminowane wypadają.
    function next() {
        if (root.suppressed || priv.current) return;
        const now = Date.now();
        const q = priv.queue.filter(g => now - g.queuedAt <= g.waitMs);
        if (q.length === 0) {
            priv.queue = [];
            return;
        }
        let best = 0;
        for (let i = 1; i < q.length; i++) if (q[i].priority > q[best].priority) best = i;
        const g = q.splice(best, 1)[0];
        priv.queue = q;
        present(g);
    }

    onSuppressedChanged: {
        if (suppressed) {
            gapTimer.stop();
            shownTimer.stop();
            priv.current = null;
        } else if (priv.queue.length > 0) {
            gapTimer.restart();
        }
    }

    Timer {
        id: shownTimer
        onTriggered: root.finish()
    }

    Timer {
        id: gapTimer
        interval: root.gapMs
        onTriggered: root.next()
    }
}
