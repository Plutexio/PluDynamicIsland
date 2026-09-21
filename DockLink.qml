pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ---------------------------------------------------------------
// Stan dla docka PluDE (~/PluDE), który chodzi jako OSOBNY proces
// Quickshella. Wyspa przepisuje $XDG_RUNTIME_DIR/plude/island.json przy
// każdej zmianie (z krótkim zwłokiem) i co heartbeatMs bez zmian — po tym
// dock poznaje, że wyspa żyje, i gasi plakietki, gdy przestanie.
//
// Plik, a nie powiadamianie docka przez IPC: zrestartowany dock ma od razu
// dostać aktualny stan, a powiadomienie wysłane w trakcie jego restartu by
// przepadło. W drugą stronę (dock → wyspa) idzie IPC, patrz shell.qml.
//
// Kluczem aplikacji jest id wpisu .desktop — ta sama droga co przycisk
// "otwórz aplikację" w historii (NotificationService.resolveApp), a dock
// rozwiązuje swoje okna do tych samych id.
// ---------------------------------------------------------------
Singleton {
    id: root

    property int heartbeatMs: 5000
    property int debounceMs: 150

    // Ukrycie wyspy skrótem (persist.hidden w shell.qml) — dock chowa się
    // razem z nią, jeśli tak ma w ustawieniach.
    property bool islandHidden: false

    // Dock prosi o pokazanie karty powiadomień (klik w plakietkę).
    signal showNotificationsRequested(string appId)

    // ---- stan ----

    // { id: [czas epoch ms, …] } — wpisy powiadomień w historii. Transfery
    // pomijamy: mają własny pasek postępu na ikonie, a zakończony transfer
    // nie jest czymś, co dock ma liczyć jako nieprzeczytane.
    readonly property var notifications: {
        NotificationService.appCount;   // id rozwiązuje się dopiero po skanie .desktop
        const out = {};
        const h = NotificationService.history;
        for (let i = 0; i < h.length; i++) {
            if (h[i].kind === "job") continue;
            const id = NotificationService.appIdFor(h[i]);
            if (id === "") continue;
            if (!out[id]) out[id] = [];
            out[id].push(new Date(h[i].time).getTime());
        }
        return out;
    }

    // { id: { progress: 0–1, count: n } } — średnia z trwających transferów aplikacji.
    readonly property var jobs: {
        NotificationService.appCount;
        const sums = {};
        const jobs = NotificationService.jobs;
        for (let i = 0; i < jobs.length; i++) {
            const e = NotificationService.resolveApp(jobs[i].desktopEntry, jobs[i].applicationName);
            if (!e) continue;
            if (!sums[e.id]) sums[e.id] = { sum: 0, count: 0 };
            sums[e.id].sum += (jobs[i].percent || 0) / 100;
            sums[e.id].count++;
        }
        const out = {};
        for (const id in sums)
            out[id] = { progress: Math.max(0, Math.min(1, sums[id].sum / sums[id].count)), count: sums[id].count };
        return out;
    }

    readonly property var discord: ({
        inVoice: DiscordService.inVoice,
        muted: DiscordService.muted,
        deafened: DiscordService.deafened,
        channelName: DiscordService.channelName
    })

    readonly property string payload: JSON.stringify({
        notifications: root.notifications,
        jobs: root.jobs,
        discord: root.discord,
        hidden: root.islandHidden
    })

    onPayloadChanged: debounce.restart()

    // ---- zapis ----

    function write() {
        const s = JSON.parse(root.payload);
        s.updated = Date.now();
        file.setText(JSON.stringify(s));
    }

    Timer {
        id: debounce
        interval: root.debounceMs
        onTriggered: root.write()
    }

    Timer {
        interval: root.heartbeatMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.write()
    }

    FileView {
        id: file
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/plude/island.json"
        // Pliku nie czytamy — tylko piszemy. Bez tego FileView wczytuje go
        // od razu, a brak pliku przy pierwszym starcie dawałby ostrzeżenie.
        preload: false
        printErrors: false
    }
}
