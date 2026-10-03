//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Punkt wejścia. Uruchom:  qs -p ~/PluDynamicIslandQuickshell
ShellRoot {
    id: root

    // Ukrywanie wyspy z zewnątrz, np. skrótem klawiszowym:
    //   qs -p ~/PluDynamicIslandQuickshell ipc call island toggle
    //
    // Na Hyprlandzie jest też skrót globalny (niżej) — na KDE zostaje IPC,
    // bo wl-global-shortcuts wystawia tylko Hyprland.
    // Stan w PersistentProperties, bo instancja przeładowuje pliki na żywo —
    // zwykła właściwość wracałaby do false i schowana wyspa wyskakiwała po edycji.
    PersistentProperties {
        id: persist
        reloadableId: "islandState"

        property bool hidden: false
    }

    IpcHandler {
        target: "island"

        function toggle(): void { persist.hidden = !persist.hidden; }
        function hide(): void { persist.hidden = true; }
        function show(): void { persist.hidden = false; }
        function isHidden(): bool { return persist.hidden; }

        // Dock PluDE (~/PluDE): klik w plakietkę powiadomień na ikonie.
        // appId na razie tylko przechodzi dalej — karta pokazuje całą historię.
        function showNotifications(appId: string): void { DockLink.showNotificationsRequested(appId); }

        // Pasek PluDE: klik w ikonę Wi-Fi / Bluetootha. "wifi" | "bluetooth";
        // drugie wywołanie z tą samą nakładką ją zamyka.
        function toggleOverlay(mode: string): void { DockLink.overlayRequested(mode); }
    }

    // Stan dla docka PluDE — patrz DockLink.qml. Tylko ukrycie skrótem:
    // pełny ekran dock rozpoznaje sam.
    Binding {
        target: DockLink
        property: "islandHidden"
        value: persist.hidden
    }

    // Okno na pełnym ekranie (gra, film) chowa wyspę na SWOIM monitorze.
    // ToplevelManager, nie Quickshell.Hyprland: działa na każdym kompozytorze
    // z wlr-foreign-toplevel-management, a na KWinie lista jest pusta i
    // warunek po prostu nigdy nie zachodzi (bez ostrzeżeń).
    function fullscreenOn(screen) {
        const t = ToplevelManager.activeToplevel;
        if (!t || !t.fullscreen || !screen) return false;
        const scr = t.screens;
        if (scr.length === 0) return true;
        for (let i = 0; i < scr.length; i++) if (scr[i].name === screen.name) return true;
        return false;
    }

    // Skrót globalny Hyprlanda. Protokół hyprland-global-shortcuts-v1 nie
    // przypisuje klawisza — robi to konfiguracja kompozytora, a my tylko
    // zgłaszamy nazwę skrótu. W ~/.config/hypr/hyprland.conf:
    //
    //   bind = SUPER, I, global, quickshell:islandToggle
    //
    // Loader, a nie gołe GlobalShortcut, bo poza Hyprlandem (KDE) protokołu
    // nie ma i sam obiekt zgłasza ostrzeżenie przy każdym starcie.
    // Brakująca zmienna to `null`, nie `undefined` (zmierzone) — porównanie
    // z `undefined` było zawsze prawdziwe i Loader ładował skrót także na KDE.
    readonly property bool onHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    Loader {
        active: root.onHyprland

        source: "HyprlandShortcut.qml"

        onLoaded: item.activated.connect(() => persist.hidden = !persist.hidden)
    }

    // Monitor, na którym ma siedzieć wyspa.
    //
    // Quickshell nie zna pojęcia "monitora głównego" — Wayland go nie ma — a
    // kolejność Quickshell.screens NIE odpowiada priorytetom kompozytora
    // (na desktopie z KDE screens[0] to HDMI-A-1, czyli ten drugi). Dlatego
    // można wskazać monitor po nazwie; pusta nazwa = wybór automatyczny.
    //
    // Nazwy monitorów wypisze:  hyprctl monitors    (Hyprland)
    //                           kscreen-doctor -o   (KDE)
    // Ustawiane w config.jsonc ("general.screen"), nie tutaj.
    readonly property string islandScreen: IslandConfig.general.screen

    readonly property var targetScreens: {
        const all = Quickshell.screens;

        if (root.islandScreen !== "") {
            const named = all.filter(s => s.name === root.islandScreen);
            if (named.length > 0) return named;
        }

        // Bez nazwy albo monitor odłączony — ten w punkcie (0,0). Hyprland
        // i KDE stawiają tam monitor główny.
        const atOrigin = all.filter(s => s.x === 0 && s.y === 0);
        if (atOrigin.length > 0) return atOrigin;

        return all.length > 0 ? [all[0]] : [];
    }

    Variants {
        model: root.targetScreens

        DynamicIsland {
            id: island

            // Pełny ekran chowa wyspę tą samą drogą co skrót: razem z zamknięciem
            // nakładki, bo schowane okno z klawiaturą Exclusive zjadałoby klawisze.
            hiddenByUser: persist.hidden || root.fullscreenOn(island.modelData)

            Connections {
                target: DockLink
                function onShowNotificationsRequested(appId) {
                    if (island.hiddenByUser) return;
                    island.showCardNotice(island.cardNotifications, island.notificationDuration);
                }
                function onOverlayRequested(mode) {
                    if (island.hiddenByUser) return;
                    if (mode !== "wifi" && mode !== "bluetooth") return;
                    if (island.overlayMode === mode) island.closeOverlay();
                    else if (!island.justClosedOutside()) island.openOverlay(mode);
                }
            }
        }
    }
}
