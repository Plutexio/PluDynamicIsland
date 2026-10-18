import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Wayland

// Pływająca "wyspa" na górze ekranu: w spoczynku pokazuje tylko zegar,
// po najechaniu myszką (lub kliknięciu wyspy) rozwija się w karuzelę kart
// (AirPods | muzyka | Discord | zegar | łączność | powiadomienia) przewijaną
// kółkiem; karta AirPodsów istnieje tylko wtedy, gdy słuchawki są połączone.
// Karta łączności otwiera nakładki Wi-Fi i Bluetootha, które zastępują całą
// karuzelę i rozciągają wyspę do własnego rozmiaru. Dodatkowo sama się rozwija
// na chwilę, gdy zmieni się utwór — tak jak w iOS. Podczas rozmowy na
// Discordzie obok zwiniętej pigułki stoi druga, mała, z nazwą kanału i timerem.
PanelWindow {
    id: root

    // Variants przekazuje tu ekran, na którym ma żyć ta instancja wyspy.
    // Domyślne null, a nie undefined — inaczej Quickshell krzyczy przy
    // użyciu komponentu bez Variants.
    property var modelData: null
    screen: modelData

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    // Wartości z IslandConfig pochodzą z ~/.config/PluDynamicIsland/config.jsonc
    // (opis i domyślne: config.default.jsonc). Tu zostają nazwane właściwości,
    // żeby reszta pliku nie musiała wiedzieć, skąd się biorą.

    readonly property string uiLocale: IslandConfig.general.locale
    readonly property int topMargin: IslandConfig.general.topMargin
    readonly property int collapseDelay: IslandConfig.expand.collapseDelay   // ile ms po zjechaniu myszką wyspa się zwija
    // Auto-rozwinięcia: czy i na ile ms (zmiana utworu, powiadomienie,
    // start transferu plików, połączenie AirPodsów).
    readonly property bool expandOnTrackChange: IslandConfig.expand.onTrackChange
    readonly property int noticeDuration: IslandConfig.expand.trackChangeMs
    readonly property bool expandOnNotification: IslandConfig.expand.onNotification
    readonly property int notificationDuration: IslandConfig.expand.notificationMs
    readonly property bool expandOnTransfer: IslandConfig.expand.onTransfer
    readonly property int jobNoticeDuration: IslandConfig.expand.transferMs
    readonly property bool expandOnAirPods: IslandConfig.expand.onAirPods
    readonly property int airPodsNoticeDuration: IslandConfig.expand.airPodsMs
    // Pasek głośności w zwiniętej pigułce: czy i na ile ms.
    readonly property bool volumeNoticeEnabled: IslandConfig.volume.notice
    readonly property int volumeNoticeDuration: IslandConfig.volume.noticeMs
    property int jobBarGap: 4                 // przerwa między wyspą a paskiem postępu pod nią

    // Formaty zegara (Qt.formatTime). Szerokość zwiniętej pigułki jest stała,
    // więc format z sekundami może się w niej nie zmieścić obok widma.
    readonly property string clockPillFormat: IslandConfig.clock.pillFormat
    readonly property string clockCardFormat: IslandConfig.clock.cardFormat
    readonly property string clockDateFormat: IslandConfig.clock.dateFormat

    // Obwódka baterii wokół zwiniętej pigułki (tylko laptop). Grubość
    // w px — parzysta nie musi być, bo linia leży wewnątrz krawędzi, a nie
    // na niej. Poniżej progu, bez ładowania, obwódka robi się czerwona.
    readonly property bool batteryRingEnabled: IslandConfig.battery.ring
    readonly property real batteryRingWidth: IslandConfig.battery.ringWidth
    readonly property real batteryLowLevel: IslandConfig.battery.lowLevel
    // Kolory obwódki: na baterii, na zasilaczu i przy niskim poziomie.
    readonly property color batteryColor: IslandConfig.battery.color
    readonly property color batteryChargingColor: IslandConfig.battery.chargingColor
    readonly property color batteryLowColor: IslandConfig.battery.lowColor
    // Pulsowanie przy ładowaniu (tylko z IslandConfig.loopAnimations): pełny
    // cykl (przygaśnięcie i powrót) w ms i jasność w najciemniejszym punkcie (0–1).
    readonly property int batteryPulseMs: IslandConfig.battery.pulseMs
    readonly property real batteryPulseMin: IslandConfig.battery.pulseMin
    // Podłączenie / odłączenie ładowarki: zwinięta pigułka poszerza się
    // na tyle ms do powerNoticeWidth i pokazuje stan zasilania.
    readonly property bool powerNoticeEnabled: IslandConfig.battery.chargerNotice
    readonly property int powerNoticeDuration: IslandConfig.battery.chargerNoticeMs
    property int powerNoticeWidth: 232

    // Zerknięcia (GlanceService): wysokość pigułki, margines treści po bokach,
    // szerokość paska postępu i górna granica szerokości (dłuższy tytuł jest
    // obcinany). Wysokość parzysta, jak collapsedHeight — patrz "Pułapki
    // geometryczne". Pasek 168 daje pigułkę głośności 280 px.
    property int glanceHeight: 44
    property int glancePadding: 18
    property int glanceBarWidth: 168
    property int glanceMaxWidth: 380
    // Kropka prywatności (mikrofon / kamera) przy prawej krawędzi pigułki.
    readonly property bool privacyDotEnabled: IslandConfig.privacy.dot
    // Kropka zabiera prawy margines treści: bez tego dotykała wartości
    // zerknięcia ("mikrofon●", zmierzone zrzutem). Parzysta, jak reszta.
    readonly property bool privacyDotShown: privacyDotEnabled && !expanded
                                            && (PrivacyService.micActive || PrivacyService.cameraActive)
    readonly property int glanceDotSpace: privacyDotShown ? 10 : 0
    readonly property bool privacyGlanceEnabled: IslandConfig.privacy.glance
    readonly property int privacyGlanceDuration: IslandConfig.privacy.glanceMs
    // Jasność i Caps Lock: zerknięcia i stała ikonka w pigułce przy Caps Locku.
    readonly property bool brightnessGlanceEnabled: IslandConfig.glances.brightness
    readonly property bool capsGlanceEnabled: IslandConfig.glances.capsLock
    readonly property bool numGlanceEnabled: IslandConfig.glances.numLock
    readonly property bool capsIndicatorEnabled: IslandConfig.glances.capsIndicator
    readonly property int hudGlanceDuration: IslandConfig.glances.hudMs
    // Minutniki KClock na karcie zegara; dzwoniący rozwija wyspę na tyle ms.
    readonly property bool timersEnabled: IslandConfig.clock.timers
    readonly property bool expandOnTimer: IslandConfig.expand.onTimer
    readonly property int timerNoticeDuration: IslandConfig.expand.timerMs

    // Dogładzanie słupków widma po stronie QML. Przy 60 fps klatka przychodzi
    // co ~17 ms, więc 28 ms to niecałe dwie klatki — słupek zdąży prawie
    // dobiec do celu, zanim przyjdzie następny. Poprzednie 90 ms oznaczało,
    // że nie dobiegał nigdy, i to właśnie dawało wrażenie ospałości.
    readonly property int spectrumSmoothingMs: IslandConfig.spectrum.smoothingMs

    // Kolor widma z okładki (jak w iOS). Z palety okładki wygrywa kolor
    // o największej chromie (max − min kanałów RGB, 0–1), a jego jasność
    // i nasycenie HSL (0–1) są dociągane do zakresu czytelnego na czarnej
    // pigułce. Przy dolnej granicy 0,62 czerwień robiła się różowa; górna
    // nie daje bladym, prawie białym odcieniom wyjść na biało.
    // Pas, którego najżywszy kolor ma chromę poniżej artGrayChroma, uchodzi
    // za szary i bierze ŚREDNIĄ jasność pasa w granicach artGray*Lightness.
    // Wcześniej szary pas dostawał na sztywno 0,88, więc ciemna okładka
    // z odrobiną bieli dawała całe białe słupki.
    readonly property bool spectrumFromArt: IslandConfig.spectrum.colorFromArt
    readonly property color spectrumFallbackColor: IslandConfig.spectrum.fallbackColor
    property real artAccentMinLightness: 0.55
    property real artAccentMaxLightness: 0.72
    property real artAccentMinSaturation: 0.5
    property real artGrayChroma: 0.12
    property real artGrayMinLightness: 0.5
    property real artGrayMaxLightness: 0.8
    readonly property int artAccentFadeMs: IslandConfig.spectrum.colorFadeMs

    // Przewijanie kart kółkiem. Jeden ząbek kółka to 120 jednostek angleDelta;
    // touchpad przysyła drobne porcje, które się sumują. Po przeskoku karty
    // kolejne zdarzenia są ignorowane przez wheelCooldownMs, żeby jedno
    // machnięcie (z bezwładnością touchpada) nie przeskoczyło dwóch kart.
    property int wheelStepDelta: 120
    readonly property int wheelCooldownMs: IslandConfig.expand.wheelCooldownMs

    readonly property bool voicePillEnabled: IslandConfig.pills.voice
    readonly property bool screencastPillEnabled: IslandConfig.pills.screencast
    readonly property bool timerPillEnabled: IslandConfig.pills.timer
    readonly property int pillGap: IslandConfig.pills.gap             // odstęp pigułek (rozmowa, udostępnianie) od wyspy
    readonly property int pillMaxWidth: IslandConfig.pills.maxWidth   // dłuższe nazwy kanałów / aplikacji są obcinane

    // Efekty (opis w config.default.jsonc). Fala, ciecz pigułek i kaskada
    // czytają swoje przełączniki same, w EventRipple / LiquidPill / CascadeShift.
    readonly property bool glassEdge: IslandConfig.effects.glassEdge
    readonly property bool artGlow: IslandConfig.effects.artGlow
    readonly property bool carouselDepth: IslandConfig.effects.carouselDepth
    readonly property bool trackChangeEffect: IslandConfig.effects.trackChange
    readonly property bool rollingClock: IslandConfig.effects.rollingClock
    // Kolory fali: zwykłe zdarzenie, minutnik, ładowarka, wejście na kanał.
    property color rippleColor: "#f2f2f2"
    property color rippleTimerColor: "#ff9f0a"
    property color rippleChargeColor: "#30d158"
    property color rippleVoiceColor: "#5865f2"
    // Szklana ramka: grubość w px (1 = jak dawna ramka).
    property real glassRimWidth: 1
    // Poświata karty muzyki: krycie rozmytej okładki (0–1) i krycie koloru
    // widma u dołu karty. Wyżej tekst traci kontrast na jasnych okładkach.
    property real artGlowOpacity: 0.42
    property real artGlowTint: 0.22

    // Rozmiar nakładek (Wi-Fi, Bluetooth). Wpisany tutaj, a nie brany
    // z implicitWidth panelu, bo panele siedzą w Loaderze i przy zamkniętej
    // nakładce w ogóle nie istnieją — a wysokość OKNA musi być stała, żeby
    // otwarcie nakładki nie przestawiało rozmiaru powierzchni layer-shella.
    property int overlayWidth: 620
    property int overlayHeight: 360

    // Podgląd okładki: klik w okładkę na karcie muzyki rozciąga ją na całą
    // wyspę. Kwadrat, bo okładki są kwadratowe — nic nie jest przycinane.
    // Nie węższy niż karta muzyki (440): okładka leży na jej lewym skraju
    // (−206…−134 px od środka), więc przy węższym podglądzie kursor, który
    // właśnie w nią kliknął, wypadłby poza maskę i wyspa zwinęłaby się
    // w chwili otwarcia. artPreviewMs to czas przelotu okładki na miejsce.
    property int artPreviewSize: 440
    property int artPreviewMs: 480

    // Korektor (klik w wizualizator na karcie muzyki) zajmuje całą wyspę.
    // Szerokość z tego samego powodu co podgląd okładki: wizualizator stoi
    // na karcie muzyki, więc węższy korektor wyrzuciłby kursor poza maskę.
    property int eqWidth: 440
    property int eqHeight: 250

    // Pytanie o aktualizację (UpdateService) też zajmuje całą wyspę.
    // Wysokość idzie za treścią panelu (liczba commitów, wynik).
    readonly property int updateWidth: updatePanel.implicitWidth
    readonly property int updateHeight: updatePanel.implicitHeight

    // ---------------------------------------------------------------
    // Okno
    // ---------------------------------------------------------------

    anchors {
        top: true
        left: true
        right: true
        // Okno ZAWSZE na cały ekran, choć wyspa zajmuje górę: przy nakładce
        // klik poza wyspą ma trafić w nas (outsideCatcher). Wejście ogranicza
        // maska, więc reszta ekranu normalnie działa. Rozciąganie okna tylko
        // na czas nakładki przestawiało powierzchnię w trakcie animacji
        // otwarcia (zmierzone: klatka 42–84 ms zamiast 17, widać przeskok).
        bottom: true
    }

    // Wysokość okna idzie za najwyższą kartą, nie jest wpisana na sztywno:
    // karta wyższa niż okno wyglądała na uciętą od dołu (powiadomienia, 170 px
    // przy dawnych 160 px okna). Zapas na dole kryje przestrzelenie sprężyny
    // (OutBack z overshoot 0.9 wychodzi ~3% ponad cel, czyli ~4 px przy
    // rozwijaniu z pigułki) i pasek postępu transferu wiszący pod wyspą.
    // Karta powiadomień zmienia wysokość (dymek jest niższy niż historia),
    // ale okno liczy się od jej wyższego wariantu — inaczej każde powiadomienie
    // przestawiałoby rozmiar okna layer-shell tam i z powrotem.
    //
    // Karta AirPodsów i nakładki wchodzą do rachunku ZAWSZE, także gdy ich
    // akurat nie widać — z tego samego powodu: ani połączenie słuchawek, ani
    // otwarcie formularza nie ma przestawiać rozmiaru okna layer-shella.
    readonly property int maxCardHeight: Math.max(...cardHeights, airpods.implicitHeight,
                                                  notifications.historyHeight, overlayHeight,
                                                  artPreviewSize, eqHeight, updatePanel.maxHeight)
    property int bottomReserve: 6
    implicitHeight: topMargin + maxCardHeight + bottomReserve + jobBarGap + jobBar.height
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore   // nie rezerwujemy miejsca — wyspa "unosi się" nad oknami

    // Klawiatura TYLKO na czas formularza. Exclusive, nie OnDemand: OnDemand
    // daje klawiaturę dopiero po kliknięciu w powierzchnię, a pole formularza
    // bierze kursor samo (fPsk.take()) i wtedy nie dostałoby ani znaku.
    // Poza nakładką None — wyspa nie ma prawa łapać klawiszy, bo przykryłaby
    // skróty kompozytora.
    WlrLayershell.keyboardFocus: root.overlayOpen
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    // Ukrycie skrótem (IpcHandler w shell.qml). Najpierw wygaszamy treść, potem
    // chowamy całe okno: samo przezroczyste okno nadal łapałoby kursor maską
    // i rozwijało się pod niewidoczną ręką.
    property bool hiddenByUser: false
    property real shownOpacity: hiddenByUser ? 0 : 1
    Behavior on shownOpacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    contentItem.opacity: shownOpacity
    visible: !hiddenByUser || shownOpacity > 0

    // Przypięta wyspa wróciłaby po odkryciu od razu rozwinięta, a schowane
    // okno z klawiaturą Exclusive zjadałoby wszystkie klawisze — stąd i
    // zamknięcie nakładki.
    onHiddenByUserChanged: if (hiddenByUser) { pinned = false; overlayMode = ""; }

    // Rozmiar DOCELOWY wyspy — bez animacji. Maska wejściowa i obszar reagujący
    // na kursor muszą wyprzedzać animację rozwijania: gdyby szły za animowaną
    // szerokością (520 ms), kursor jadący do skrajnego przycisku wyprzedziłby
    // ją, wypadł poza region wejściowy okna, dostalibyśmy "pointer leave"
    // i wyspa zwinęłaby się w trakcie sięgania po przycisk.
    //
    // Bierzemy większy z rozmiarów: przy rozwijaniu od razu docelowy,
    // przy zwijaniu maska kurczy się razem z wyspą.
    readonly property int reachWidth: Math.ceil(Math.max(island.width, expanded ? expandedWidth : restingWidth))
    readonly property int reachHeight: Math.ceil(Math.max(island.height, expanded ? expandedHeight : restingHeight))

    // Myszkę łapie wyłącznie sam kształt wyspy (plus pigułka rozmowy, gdy jest).
    // Bez tego niewidoczny pasek na całej szerokości ekranu zjadałby kliknięcia
    // w pasek zadań / pulpit.
    mask: Region {
        x: Math.round((root.width - root.reachWidth) / 2)
        y: root.topMargin
        width: root.reachWidth
        height: root.reachHeight
        radius: Math.min(island.radius, root.reachHeight / 2)

        // Region pigułki bierze geometrię podkładki hovera, nie samej pigułki —
        // podkładka ma szerokość 0 poza rozmową, więc wtedy nic nie łapie.
        Region {
            item: pillHoverArea
            radius: root.collapsedHeight / 2
        }

        // Przy nakładce całe okno (czyli cały ekran) — patrz outsideCatcher.
        Region {
            width: root.overlayOpen ? root.width : 0
            height: root.overlayOpen ? root.height : 0
        }
    }

    // ---------------------------------------------------------------
    // Stan
    // ---------------------------------------------------------------

    property bool hovered: false

    // Kursor jest "na wyspie", gdy stoi nad podkładką ALBO nad którymś
    // przyciskiem ALBO nad pigułką rozmowy. Sumujemy wszystkie źródła, bo
    // przycisk pod kursorem przejmuje hover na wyłączność i podkładka przestaje
    // go widzieć — bez tego wyspa zwijałaby się w chwili najechania na przycisk.
    readonly property bool controlsHovered: btnPrev.hovering || btnPlay.hovering || btnNext.hovering
        || btnMic.hovering || btnDeaf.hovering || btnLeave.hovering
        || outputChip.hovering || outputChipIdle.hovering || micSwitch.hovering
        || connectivity.hovering || notifications.hovering || airpods.hovering
        || (overlay.item ? overlay.item.hovering : false)
        || eqPanel.hovering || updatePanel.hovering || clockCard.hovering
    readonly property bool pointerInside: areaHover.hovered || controlsHovered || pillHover.hovered

    onPointerInsideChanged: {
        // Pod otwartą nakładką karuzeli nie widać, a przestawienie karty
        // zmieniłoby ją użytkownikowi pod ręką na czas po zamknięciu.
        if (pointerInside && !root.overlayOpen) {
            // Przy dwóch pigułkach każda otwiera swoją kartę: pigułka rozmowy
            // Discorda, główna muzykę (zegar, gdy nic nie gra). Ustawiamy ją PRZED
            // hovered, żeby wyspa od razu rosła do rozmiaru tej karty, a nie
            // najpierw do poprzedniej i dopiero potem przesuwała. Poza rozmową
            // jest jedna pigułka i wyspa pamięta ostatnio używaną kartę.
            if (pillHover.hovered) root.setCard(root.cardDiscord, false);
            else if (root.inVoice && !root.expanded) root.setCard(root.hasPlayer ? root.cardMusic : root.cardClock, false);
            collapseTimer.stop();
            root.hovered = true;
        } else {
            collapseTimer.restart();
        }
    }
    property bool pinned: false
    property bool notice: false   // krótkie auto-rozwinięcie, "powiadomienie"

    // ---- zerknięcia w zwiniętej pigułce ----
    // Kolejka, priorytety i czasy są w GlanceService; tu tylko źródła, które
    // należą do wyspy, i rysowanie. Rozwinięta albo schowana wyspa wstrzymuje
    // zerknięcia — najechanie w trakcie zdejmuje bieżące, bo skoro ktoś sięga
    // po kartę, to jej chce, a nie HUD-u wracającego po zjechaniu kursorem.
    Binding {
        target: GlanceService
        property: "suppressed"
        value: root.expanded || root.hiddenByUser
    }

    readonly property var glance: GlanceService.current
    readonly property bool glanceShown: glance !== null && !expanded
    // Ostatnie zerknięcie zostaje do rysowania, kiedy bieżące już zniknęło —
    // inaczej treść znikałaby w chwili startu wygaszania, a nie po nim.
    property var glanceView: null
    onGlanceChanged: if (glance) glanceView = glance

    // Szerokość z treści, nie z animowanej wyspy: tekst stoi w miejscu,
    // a wyspa go odsłania, rozsuwając się. Parzysta — patrz glanceHeight.
    readonly property int glanceWidth: {
        const natural = Math.ceil(glanceRow.implicitWidth) + 2 * glancePadding + glanceDotSpace;
        const w = Math.max(collapsedWidth, glanceView ? glanceView.minWidth : 0, Math.min(glanceMaxWidth, natural));
        return Math.ceil(w / 2) * 2;
    }

    // Zmiana głośności spoza wyspy (klawisze multimedialne, pavucontrol).
    // Najwyższy priorytet: to odpowiedź na własny ruch użytkownika i musi
    // przyjść od razu. Rozwinięta wyspa pokazuje głośność w pigułce wyjścia,
    // więc zerknięcie wtedy przepada (waitMs 0).
    Connections {
        target: AudioService

        function onVolumeNudged() {
            if (!root.volumeNoticeEnabled) return;
            const muted = AudioService.muted;
            const v = AudioService.volume;
            GlanceService.show({
                key: "volume",
                icon: muted ? "volumeOff" : (v < 0.5 ? "volumeLow" : "volume"),
                iconColor: muted ? "#e5484d" : "#f2f2f2",
                progress: v,
                // Wyciszone: pasek zostaje, ale przygaszony — widać poziom,
                // do którego wróci odciszenie.
                barColor: muted ? "#5a5a62" : "#ededf0",
                value: Math.round(v * 100) + "%",
                valueColor: muted ? "#78787f" : "#f2f2f2",
                durationMs: root.volumeNoticeDuration,
                priority: 4
            });
        }
    }

    // ---- ładowarka ----
    // Jak w iOS: zwinięta pigułka rozsuwa się na chwilę na boki i pokazuje
    // "Ładowanie 48%" / "Na baterii". Źródłem jest UPower.onBattery, nie stan
    // baterii: `state` dochodzi do Charging z opóźnieniem, a flaga zasilacza
    // zmienia się od razu.

    // -1 = brak punktu odniesienia. Zmierzone: przy starcie onBattery
    // przeskakuje z domyślnego false na prawdziwą wartość ZANIM displayDevice
    // zgłosi ready, więc zmiany sprzed `available` się nie liczą, a pierwszy
    // odczyt po nim tylko ustawia odniesienie — inaczej każdy start (i każde
    // przeładowanie na żywo) na baterii udawałby odłączenie ładowarki.
    property int knownPowerSource: -1

    function checkPowerSource() {
        if (!batteryRing.available) return;
        const now = UPower.onBattery ? 1 : 0;
        const changed = root.knownPowerSource >= 0 && now !== root.knownPowerSource;
        root.knownPowerSource = now;
        if (!changed) return;
        const onBattery = now === 1;
        if (!onBattery) ripple.play(root.rippleChargeColor);
        if (!root.powerNoticeEnabled) return;
        GlanceService.show({
            key: "power",
            icon: "bolt",
            iconColor: onBattery ? "#8e8e93" : "#30d158",
            title: onBattery ? "Na baterii" : "Ładowanie",
            value: Math.round(batteryRing.level * 100) + "%",
            valueColor: batteryRing.low ? "#ff453a" : (onBattery ? "#f2f2f2" : "#30d158"),
            minWidth: root.powerNoticeWidth,
            durationMs: root.powerNoticeDuration,
            priority: 3,
            waitMs: 3000
        });
    }

    Connections {
        target: UPower
        function onOnBatteryChanged() { root.checkPowerSource(); }
    }

    Connections {
        target: batteryRing
        function onAvailableChanged() { root.checkPowerSource(); }
    }

    // ---- mikrofon / kamera ----
    // Start nagrywania: zerknięcie z nazwą aplikacji, potem już tylko kropka.
    Connections {
        target: PrivacyService

        function onStarted(kind, apps) {
            if (!root.privacyGlanceEnabled) return;
            const camera = kind === "camera";
            GlanceService.show({
                key: "privacy-" + kind,
                icon: camera ? "camera" : "mic",
                iconColor: camera ? "#30d158" : "#ff9f0a",
                title: apps.join(", "),
                value: camera ? "kamera" : "mikrofon",
                valueColor: "#9a9aa2",
                durationMs: root.privacyGlanceDuration,
                priority: 2,
                waitMs: 5000
            });
        }
    }

    // ---- jasność, Caps Lock, Num Lock ----
    // Jak głośność: odpowiedź na własny klawisz, więc najwyższy priorytet
    // i teraz albo wcale.
    Connections {
        target: HudService

        function onBrightnessNudged(value) {
            if (!root.brightnessGlanceEnabled) return;
            GlanceService.show({
                key: "brightness",
                icon: "brightness",
                progress: value,
                value: Math.round(value * 100) + "%",
                durationMs: root.hudGlanceDuration,
                priority: 4
            });
        }

        function onCapsLockToggled(on) {
            if (!root.capsGlanceEnabled) return;
            GlanceService.show({
                key: "capslock",
                icon: "capsLock",
                iconColor: on ? "#f2f2f2" : "#8e8e93",
                title: "Caps Lock",
                value: on ? "włączony" : "wyłączony",
                valueColor: on ? "#f2f2f2" : "#8e8e93",
                durationMs: root.hudGlanceDuration,
                priority: 4
            });
        }

        // Bez stałej ikonki jak przy Caps Locku: Num Lock jest zwykle
        // włączony, więc ikonka wisiałaby w pigułce cały czas.
        function onNumLockToggled(on) {
            if (!root.numGlanceEnabled) return;
            GlanceService.show({
                key: "numlock",
                icon: "numLock",
                iconColor: on ? "#f2f2f2" : "#8e8e93",
                title: "Num Lock",
                value: on ? "włączony" : "wyłączony",
                valueColor: on ? "#f2f2f2" : "#8e8e93",
                durationMs: root.hudGlanceDuration,
                priority: 4
            });
        }
    }

    // ---- minutniki KClock ----
    // Dzwoniący minutnik rozwija wyspę na karcie zegara, gdzie jest przycisk
    // wyciszenia. Własne powiadomienia KClock o minutnikach połyka wtedy
    // NotificationService — pokazywałyby to samo drugi raz (patrz shownOnIsland).
    Binding {
        target: TimerService
        property: "shownOnIsland"
        value: root.timersEnabled && root.cardClock >= 0 && TimerService.available
    }

    Connections {
        target: TimerService

        function onRang(timer) {
            ripple.play(root.rippleTimerColor);
            if (root.expandOnTimer) root.showCardNotice(root.cardClock, root.timerNoticeDuration);
        }
    }

    // Rozmiar zwiniętej wyspy w danej chwili. collapsedWidth/Height zostają
    // stałe: od nich liczą się pozycje pigułek rozmowy i udostępniania, które
    // na czas poszerzenia po prostu znikają, zamiast skakać na boki.
    readonly property int restingWidth: glanceShown ? glanceWidth : collapsedWidth
    readonly property int restingHeight: glanceShown ? glanceHeight : collapsedHeight
    readonly property bool restingWide: glanceShown

    // Zwinięcie zamyka podgląd okładki — inaczej następne najechanie
    // otwierałoby od razu wielką okładkę zamiast karty.
    onExpandedChanged: if (!expanded) {
        root.artPreview = false;
        root.eqView = false;
    }

    // ---- podgląd okładki ----
    // Tak jak nakładka, NIE jest kartą karuzeli (slot ma 440 px szerokości,
    // a podgląd jest też wyższy). Pokazuje się tylko nad kartą muzyki:
    // zmiana karty (kółko, powiadomienie, AirPodsy) go zamyka, a nie zostawia
    // w tle do ponownego pojawienia się.
    property bool artPreview: false
    readonly property bool artPreviewShown: artPreview && expanded && !overlayOpen
        && !updateShown && hasPlayer && currentKey === "music"
    onCurrentKeyChanged: {
        artPreview = false;
        eqView = false;
    }

    // ---- korektor ----
    // Tak jak podgląd okładki: zastępuje kartę muzyki, nie jest kartą.
    // Bez warunku hasPlayer — zamknięcie odtwarzacza w trakcie ustawiania
    // pasm nie ma wyrywać panelu spod ręki.
    property bool eqView: false
    readonly property bool eqShown: eqView && expanded && !overlayOpen && !updateShown
        && currentKey === "music"

    // ---- aktualizacja ----
    // Jak korektor: zastępuje karuzelę, nie jest kartą. Sama rozwija wyspę
    // i trzyma ją rozwiniętą do odpowiedzi — pytanie przychodzi przy starcie,
    // bez kursora na wyspie, i zwinięte po prostu by przepadło. Nakładka
    // (np. pytanie o PIN z BlueZ) ma pierwszeństwo; pytanie wraca po niej.
    readonly property bool updateShown: UpdateService.prompting && !overlayOpen

    function openEqualizer() {
        root.artPreview = false;
        root.eqView = true;
    }

    // ---- nakładki (Wi-Fi, Bluetooth) ----
    // "" | "wifi" | "bluetooth". Nakładka zastępuje pasek kart i rozciąga
    // wyspę do overlayWidth x overlayHeight. Świadomie NIE jest kartą
    // karuzeli: karta musiałaby zmieścić się w slocie (slotWidth = 440),
    // a podniesienie slotu przestawiłoby geometrię wszystkich kart.
    property string overlayMode: ""
    readonly property bool overlayOpen: overlayMode !== ""

    function openOverlay(mode) {
        root.pinned = false;      // nakładka i tak trzyma wyspę rozwiniętą
        root.overlayMode = mode;
    }

    function closeOverlay() { root.overlayMode = ""; }

    // Klik poza wyspą zamyka nakładkę (outsideCatcher). Przez
    // overlayReopenGuardMs po takim zamknięciu toggleOverlay z IPC jej nie
    // otwiera: klik w Wi-Fi na pasku PluDE zamyka ją tym samym kliknięciem,
    // a gdyby pasek też go dostał, jego toggle otworzyłby ją z powrotem.
    property double outsideClosedAt: 0
    property int overlayReopenGuardMs: 400
    // Funkcja, nie właściwość: Date.now() nie jest zależnością powiązania.
    function justClosedOutside() { return Date.now() - outsideClosedAt < overlayReopenGuardMs; }

    readonly property bool expanded: hovered || pinned || notice || overlayOpen || updateShown

    // Karta (nazwa, nie indeks), do której wrócić po auto-rozwinięciu;
    // "" = nie wracać (muzyka zostaje na muzyce). Powiadomienie i transfer
    // pokazują swoją kartę tylko na chwilę — użytkownik, który jej nie dotknął,
    // ma dostać z powrotem tę, na której skończył.
    property string keyBeforeNotice: ""

    onNoticeChanged: {
        if (notice || keyBeforeNotice === "") return;
        const card = cardKeys.indexOf(keyBeforeNotice);
        if (!hovered && !pinned && card >= 0) setCard(card, false);
        keyBeforeNotice = "";
    }

    // Kursor na wyspie wstrzymuje wygaszanie powiadomienia, żeby dało się
    // kliknąć akcję.
    Binding {
        target: NotificationService
        property: "held"
        value: root.hovered || root.pinned
    }

    // ---- karty ----
    // Rozwinięta wyspa to karuzela: każda karta ma własny rozmiar docelowy,
    // wyspa animuje się do rozmiaru aktywnej.
    //
    // Karta AirPodsów istnieje tylko przy połączonych słuchawkach, na lewo od
    // muzyki, więc indeksy wszystkich kart przesuwają się wtedy o jeden. Dlatego aktywna
    // karta jest pamiętana po NAZWIE (currentKey), a indeks z niej wyprowadzony —
    // przy indeksie trzymanym wprost połączenie słuchawek przełączyłoby
    // użytkownikowi kartę pod ręką (muzyka -> AirPodsy).
    //
    // Karty ukryte w konfiguracji (cards.hidden) wypadają z listy, więc ich
    // indeks to -1 — setCard() i showCardNotice() takie odrzucają, a slot
    // się chowa. Pusta lista zepsułaby rozmiar wyspy, stąd zegar awaryjnie.
    readonly property var cardKeys: {
        const all = airPodsShown
            ? ["airpods", "music", "discord", "clock", "connectivity", "notifications"]
            : ["music", "discord", "clock", "connectivity", "notifications"];
        const shown = all.filter(k => !IslandConfig.cardHidden(k));
        return shown.length > 0 ? shown : ["clock"];
    }
    readonly property int cardMusic: cardKeys.indexOf("music")
    readonly property int cardAirPods: cardKeys.indexOf("airpods")   // -1 bez słuchawek (albo ukryta)
    readonly property int cardDiscord: cardKeys.indexOf("discord")
    readonly property int cardClock: cardKeys.indexOf("clock")
    readonly property int cardConnectivity: cardKeys.indexOf("connectivity")
    readonly property int cardNotifications: cardKeys.indexOf("notifications")
    readonly property int cardCount: cardKeys.length

    // Ustawiane w Connections na AirPodsService, nie powiązaniem: przed zmianą
    // układu kart trzeba zgasić animateCardChange, a powiązanie nie daje
    // kontroli nad kolejnością. Bez tego po ostatnim przewinięciu kółkiem
    // pasek kart przejechałby przy połączeniu słuchawek o jeden slot.
    property bool airPodsShown: false
    Component.onCompleted: airPodsShown = AirPodsService.connected

    // Wartość początkowa podąża za odtwarzaczem (muzyka, gdy coś gra, inaczej
    // zegar) dopóki użytkownik pierwszy raz nie przewinie — wtedy powiązanie
    // pęka i wyspa pamięta ostatnio używaną kartę.
    property string currentKey: hasPlayer ? "music" : "clock"
    // Karta, której już nie ma (AirPodsy rozłączone w trakcie) -> pierwsza.
    // Connections niżej i tak przestawia wtedy currentKey na muzykę.
    readonly property int currentCard: Math.max(0, cardKeys.indexOf(currentKey))

    readonly property var cardSizes: ({
        music: [hasPlayer ? 440 : 296, hasPlayer ? 118 : 98],
        airpods: [airpods.implicitWidth, airpods.implicitHeight],
        discord: [440, 118],
        clock: [clockCard.implicitWidth, clockCard.implicitHeight],
        connectivity: [connectivity.implicitWidth, connectivity.implicitHeight],
        notifications: [notifications.implicitWidth, notifications.implicitHeight]
    })
    readonly property var cardWidths: cardKeys.map(k => cardSizes[k][0])
    readonly property var cardHeights: cardKeys.map(k => cardSizes[k][1])

    // Slot karuzeli = największa karta. Musi być stały, żeby przesunięcie
    // paska było liniowe w indeksie.
    readonly property int slotWidth: 440

    // Przejazd karuzeli animuje się TYLKO wtedy, gdy kartę zmienia użytkownik
    // kółkiem. Kartę ustawioną przez samą wyspę (powiadomienie, start transferu,
    // zmiana utworu, najechanie na pigułkę rozmowy) chcemy mieć na miejscu od
    // razu: wyspa rozwija się wtedy jednocześnie z przejazdem kart i widać
    // przewijanie, którego nikt nie zamawiał.
    //
    // Flagę ustawiamy PRZED zmianą karty i zostaje ona do następnej zmiany —
    // nie ma czego zerować po animacji, a Behavior sprawdza `enabled` dopiero
    // w chwili, gdy powiązanie stripOffset przeliczy się na nową wartość.
    property bool animateCardChange: false

    function setCard(card, animated) {
        if (card < 0 || card >= root.cardCount) return;
        root.animateCardChange = animated === true;
        root.currentKey = root.cardKeys[card];
    }

    function stepCard(delta) {
        const next = Math.max(0, Math.min(root.cardCount - 1, root.currentCard + delta));
        if (next !== root.currentCard) root.setCard(next, true);
    }

    // Wybór odtwarzacza. Przeglądarki potrafią wystawić dwa wpisy MPRIS dla tej
    // samej karty — np. surowy Brave (tytuł "(12) Coś tam - YouTube", bez
    // okładki) i plasma-browser-integration (czysty tytuł + okładka). Dlatego
    // punktujemy kandydatów zamiast brać pierwszego z brzegu. Przy remisie
    // wygrywa wcześniejszy, więc wybór nie skacze w tę i z powrotem.
    readonly property var player: {
        const all = Mpris.players.values;
        let best = null;
        let bestScore = -1;

        for (let i = 0; i < all.length; i++) {
            const p = all[i];
            const score = (p.isPlaying ? 4 : 0)
                + ((p.trackTitle || "") !== "" ? 2 : 0)
                + ((p.trackArtUrl || "") !== "" ? 1 : 0);

            if (score > bestScore) {
                best = p;
                bestScore = score;
            }
        }

        return best;
    }

    readonly property bool hasPlayer: player !== null
    readonly property bool isPlaying: hasPlayer && player.isPlaying
    // Przeglądarki wkładają w tytuł licznik powiadomień ("(12) Coś tam") —
    // obcinamy go, bo to szum, a nie nazwa utworu.
    readonly property string trackTitle: {
        if (!hasPlayer) return "";
        return (player.trackTitle || "").replace(/^\(\d+\)\s*/, "");
    }
    readonly property string trackArtist: hasPlayer ? (player.trackArtist || "") : ""

    readonly property string artUrl: {
        if (!hasPlayer) return "";
        const u = player.trackArtUrl || "";
        if (u === "") return "";
        return u.startsWith("/") ? "file://" + u : u;
    }

    readonly property real trackLength: (hasPlayer && player.lengthSupported) ? player.length : 0
    readonly property bool hasProgress: hasPlayer && player.positionSupported && trackLength > 0
    readonly property real progress: hasProgress
        ? Math.max(0, Math.min(1, player.position / trackLength))
        : 0

    // Wyspa dopasowuje rozmiar do aktywnej karty.
    readonly property int collapsedWidth: 168
    readonly property int collapsedHeight: 34
    readonly property int expandedWidth: overlayOpen ? overlayWidth
        : updateShown ? updateWidth
        : artPreviewShown ? artPreviewSize
        : eqShown ? eqWidth : cardWidths[currentCard]
    readonly property int expandedHeight: overlayOpen ? overlayHeight
        : updateShown ? updateHeight
        : artPreviewShown ? artPreviewSize
        : eqShown ? eqHeight : cardHeights[currentCard]

    // ---- Discord ----
    readonly property bool inVoice: DiscordService.inVoice

    // Teksty karty Discorda poza rozmową. Błąd z mostka jest krótkim kluczem,
    // tu zamieniamy go na coś, co mówi użytkownikowi, co zrobić.
    readonly property string discordTitle: inVoice
        ? DiscordService.channelName
        : (DiscordService.connected ? "Nie jesteś na kanale" : "Discord niepołączony")
    readonly property string discordSubtitle: {
        if (inVoice) return formatTime(DiscordService.elapsedSeconds);
        if (DiscordService.connected) return "Wejdź na kanał głosowy";
        switch (DiscordService.error) {
        case "brak konfiguracji": return "Brak ~/.config/PluDynamicIsland/discord.json";
        case "Discord nie działa": return "Uruchom Discorda";
        case "autoryzacja nieudana": return "Autoryzacja nieudana, sprawdź log";
        case "mostek nie działa": return "Mostek nie działa, sprawdź log";
        default: return "Łączenie…";
        }
    }

    function formatTime(seconds) {
        if (!isFinite(seconds) || seconds < 0) return "0:00";
        const total = Math.floor(seconds);
        const m = Math.floor(total / 60);
        const s = total % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // ---------------------------------------------------------------
    // Czas, zdarzenia
    // ---------------------------------------------------------------

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // Krótkie auto-rozwinięcie przy zmianie utworu / play-pauza (jak Dynamic Island)
    Connections {
        target: root.player

        function onPostTrackChanged() { root.showNotice(); }
        function onIsPlayingChanged() { root.showNotice(); }
    }

    // Powiadomienie dotyczy muzyki, więc pokazuje kartę muzyki — nawet jeśli
    // wyspa została zostawiona na innej — i już na niej zostaje.
    function showNotice() {
        if (!root.expandOnTrackChange || root.cardMusic < 0) return;
        if (!root.hasPlayer || root.trackTitle === "") return;
        if (root.overlayOpen || root.updateShown) return;
        root.keyBeforeNotice = "";
        root.setCard(root.cardMusic, false);
        root.notice = true;
        noticeTimer.interval = root.noticeDuration;
        noticeTimer.restart();
    }

    // Powiadomienie pulpitu / start transferu: karta powiadomień na chwilę,
    // potem powrót do poprzedniej.
    function showCardNotice(card, duration) {
        // Nakładka ma pierwszeństwo: wyskakująca karta powiadomień w trakcie
        // wpisywania hasła zabrałaby wyspę spod ręki. Wpis i tak zostaje
        // w historii, więc nic nie ginie.
        if (root.overlayOpen) return;
        // To samo przy korektorze: przeciągany suwak zniknąłby spod kursora.
        // Przy pytaniu o aktualizację karta przykryłaby je przed odpowiedzią.
        if (root.eqShown || root.updateShown) return;
        // Karta ukryta w konfiguracji — rozwinięcie pokazałoby inną, bez powodu.
        if (card < 0) return;
        if (root.currentCard !== card && root.keyBeforeNotice === "")
            root.keyBeforeNotice = root.currentKey;
        root.setCard(card, false);
        root.notice = true;
        noticeTimer.interval = duration;
        noticeTimer.restart();
    }

    Timer {
        id: noticeTimer
        interval: root.noticeDuration
        onTriggered: root.notice = false
    }

    Connections {
        target: NotificationService

        function onNotified(entry) {
            ripple.play(root.rippleColor);
            if (root.expandOnNotification) root.showCardNotice(root.cardNotifications, root.notificationDuration);
        }
        function onJobStarted(job) {
            if (root.expandOnTransfer) root.showCardNotice(root.cardNotifications, root.jobNoticeDuration);
        }
    }

    // Parowanie potrafi zacząć URZĄDZENIE (klawiatura, telefon), a nie my.
    // BlueZ pyta wtedy naszego agenta z otwartym wywołaniem D-Bus i własnym
    // limitem czasu — bez tego pytanie nie miałoby się gdzie pokazać i po
    // prostu by wygasło.
    //
    // Tylko przy ZAMKNIĘTEJ nakładce: wyrwanie panelu Wi-Fi w trakcie
    // wpisywania hasła skasowałoby to, co użytkownik już wpisał. Pytanie
    // odrzuci wtedy limit czasu i wystarczy sparować jeszcze raz.
    Connections {
        target: BluetoothService

        function onAskingChanged() {
            if (BluetoothService.asking && !root.overlayOpen) root.openOverlay("bluetooth");
        }
    }

    // AirPodsy: karta wchodzi do karuzeli i wychodzi z niej razem z połączeniem.
    // Przyjście słuchawek pokazuje ją na chwilę (bateria na pierwszy rzut oka),
    // potem wyspa wraca do poprzedniej karty.
    Connections {
        target: AirPodsService

        function onConnectedChanged() {
            root.animateCardChange = false;
            root.airPodsShown = AirPodsService.connected;
            if (!AirPodsService.connected) root.pausedByEar = false;
            if (!AirPodsService.connected && root.currentKey === "airpods")
                root.setCard(root.hasPlayer ? root.cardMusic : root.cardClock, false);
        }

        function onArrived() {
            ripple.play(root.rippleColor);
            if (root.expandOnAirPods) root.showCardNotice(root.cardAirPods, root.airPodsNoticeDuration);
        }

        // Pauza po wyjęciu słuchawki i wznowienie po włożeniu, jak w iOS.
        // Tylko gdy dźwięk idzie przez AirPodsy (routedHere). Wznawiamy
        // wyłącznie to, co sami zapauzowaliśmy, i dopiero gdy w uszach jest
        // znów tyle słuchawek, ile było przed pauzą — wyjęcie drugiej przy
        // już zapauzowanej muzyce niczego nie zmienia.
        function onEarsChanged(previous, current) {
            if (!AirPodsService.autoPause || !AirPodsService.routedHere) return;
            if (current < previous) {
                if (root.isPlaying && root.player.canPause) {
                    root.player.pause();
                    root.pausedByEar = true;
                    root.earsBeforePause = previous;
                }
            } else if (root.pausedByEar && current >= root.earsBeforePause) {
                root.pausedByEar = false;
                if (root.hasPlayer && !root.isPlaying && root.player.canPlay) root.player.play();
            }
        }
    }

    // Klik w nóżkę (1 = play/pauza, 2 = następny, 3 = poprzedni). Gest liczy
    // mostek — AirPodsy wysyłają każde wciśnięcie osobno.
    Connections {
        target: AirPodsService

        function onMediaAction(action) {
            if (!root.hasPlayer) return;
            const p = root.player;
            if (action === "playpause" && p.canTogglePlaying) p.togglePlaying();
            else if (action === "next" && p.canGoNext) p.next();
            else if (action === "previous" && p.canGoPrevious) p.previous();
        }
    }

    Binding {
        target: AirPodsService
        property: "playing"
        value: root.isPlaying
    }

    // Muzyka zapauzowana przez wyjęcie słuchawki — do wznowienia po włożeniu.
    // Gaśnie, gdy użytkownik sam coś zrobi z odtwarzaniem albo słuchawki
    // się rozłączą; inaczej włożenie słuchawek godzinę później puściłoby
    // muzykę, której nikt nie chciał.
    property bool pausedByEar: false
    property int earsBeforePause: 0
    onIsPlayingChanged: if (isPlaying) pausedByEar = false
    onPlayerChanged: pausedByEar = false

    // Drobne opóźnienie zwijania — żeby wyspa nie migała przy krawędzi.
    Timer {
        id: collapseTimer
        interval: root.collapseDelay
        onTriggered: root.hovered = false
    }

    // Koniec rozmowy: karta Discorda traci sens, wracamy do muzyki (lub zegara).
    Connections {
        target: DiscordService

        function onInVoiceChanged() {
            if (DiscordService.inVoice) ripple.play(root.rippleVoiceColor);
            if (!DiscordService.inVoice && root.currentCard === root.cardDiscord)
                root.setCard(root.hasPlayer ? root.cardMusic : root.cardClock, false);
        }
    }

    // Cava kosztuje proces i ~30 przebudzeń na sekundę, więc chodzi tylko
    // wtedy, gdy faktycznie coś gra. Sam serwis dokłada jeszcze karencję,
    // żeby pauza w utworze nie restartowała procesu.
    Binding {
        target: CavaService
        property: "wanted"
        value: root.isPlaying
    }

    // ---- kolor widma z okładki ----
    // ColorQuantizer czyta TYLKO pliki lokalne: okładkę Spotify (https://)
    // odrzuca z "Failed to load image". Dlatego okładkę wczytuje zwykły Image
    // (ten sam rozmiar co miniaturka, więc bierze ją z bufora), zrzuca się do
    // pliku i dopiero plik idzie do kwantyzatora. grabToImage działa też
    // przy visible: false (zmierzone). Parametr w URL-u wymusza ponowne
    // wczytanie, bo plik jest jeden, a ta sama ścieżka nie zmieniłaby `source`.
    readonly property string artSamplePath: Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-island-art.png"
    property int artSampleSerial: 0

    // Do czasu policzenia koloru nowej okładki zostaje poprzedni — przejście
    // przez zieleń przy każdej zmianie utworu wyglądałoby na mrugnięcie.
    property color artAccent: spectrumFallbackColor
    property bool artAccentValid: false
    property color spectrumColor: spectrumFromArt && artAccentValid && artUrl !== "" ? artAccent : spectrumFallbackColor

    Behavior on spectrumColor { ColorAnimation { duration: root.artAccentFadeMs } }

    function pickArtAccent(colors) {
        const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        let best = null;
        let bestChroma = -1;
        let lightness = 0;
        for (const c of colors) {
            const chroma = Math.max(c.r, c.g, c.b) - Math.min(c.r, c.g, c.b);
            if (chroma > bestChroma) {
                best = c;
                bestChroma = chroma;
            }
            lightness += c.hslLightness / colors.length;
        }
        if (best === null) return null;

        if (bestChroma < root.artGrayChroma) {
            // Przenosimy chromę, nie nasycenie HSL: prawie czarny #121116 ma
            // w HSL nasycenie ~0,1 i po rozjaśnieniu wychodził fioletowy.
            const l = clamp(lightness, root.artGrayMinLightness, root.artGrayMaxLightness);
            return Qt.hsla(Math.max(0, best.hslHue),
                           Math.min(1, bestChroma / (1 - Math.abs(2 * l - 1))), l, 1);
        }
        return Qt.hsla(best.hslHue,
                       Math.max(root.artAccentMinSaturation, best.hslSaturation),
                       clamp(best.hslLightness, root.artAccentMinLightness, root.artAccentMaxLightness), 1);
    }

    Image {
        id: artSampler

        visible: false
        asynchronous: true
        cache: true
        sourceSize.width: 64
        sourceSize.height: 64
        source: root.artUrl

        onStatusChanged: {
            if (status !== Image.Ready) return;
            const url = root.artUrl;
            grabToImage(result => {
                // Utwór zdążył się zmienić, zanim przyszedł zrzut.
                if (url !== root.artUrl) return;
                if (!result.saveToFile(root.artSamplePath)) return;
                root.artSampleSerial++;
            }, Qt.size(64, 64));
        }
    }

    readonly property string artSampleUrl: artSampleSerial > 0
        ? "file://" + artSamplePath + "?" + artSampleSerial
        : ""

    ColorQuantizer {
        id: artQuantizer

        // 8 kolorów. Median cut dzieli piksele na kubełki o podobnej liczności,
        // więc kolejność nie mówi nic o dominacji — stąd wybór po chromie.
        source: root.artSampleUrl
        depth: 3
        rescaleSize: 64

        onColorsChanged: {
            const accent = root.pickArtAccent(colors);
            if (accent === null) return;
            root.artAccent = accent;
            root.artAccentValid = true;
        }
    }

    // Każdy słupek widma ma kolor swojego pionowego pasa okładki, od lewej.
    // imageRect jest w pikselach PLIKU, a zrzut ma rozmiar fizyczny (64 px
    // × skala ekranu, na DP-1 109 px), więc szerokość bierzemy z wczytanego
    // pliku. Sama średnia pasa (depth 0) wychodzi błotnista — z czterech
    // kolorów pasa wygrywa najżywszy, tą samą regułą co akcent całości.
    // Do policzenia nowych pasów zostają stare, jak przy artAccent.
    property var barColors: []
    // Kolory pasów dla słupków; pusta lista = wszystkie w akcencie.
    readonly property var spectrumBarColors: spectrumFromArt && artUrl !== "" ? barColors : []

    Image {
        id: artSample

        visible: false
        asynchronous: true
        cache: false
        source: root.artSampleUrl
    }

    Instantiator {
        model: artSample.status === Image.Ready ? CavaService.barCount : 0

        delegate: ColorQuantizer {
            required property int index

            readonly property real sliceWidth: artSample.implicitWidth / CavaService.barCount

            source: root.artSampleUrl
            imageRect: Qt.rect(Math.round(index * sliceWidth), 0,
                               Math.round(sliceWidth), artSample.implicitHeight)
            depth: 2
            rescaleSize: 64

            onColorsChanged: {
                const color = root.pickArtAccent(colors);
                if (color === null) return;
                const next = root.barColors.slice();
                next[index] = color;
                root.barColors = next;
            }
        }
    }

    // MPRIS nie wysyła pozycji sam z siebie — trzeba go dopytać.
    // Robimy to tylko wtedy, gdy pasek postępu jest w ogóle widoczny.
    Timer {
        running: root.expanded && root.currentCard === root.cardMusic && root.isPlaying && root.hasProgress
        interval: 500
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    // ---------------------------------------------------------------
    // Wyspa
    // ---------------------------------------------------------------

    // Podkładka łapiąca kursor, w rozmiarze DOCELOWYM wyspy — dzięki temu
    // kursor sięgający po skrajny przycisk nie ucieka przed animacją.
    //
    // Leży POD wyspą celowo. Qt dostarcza hover tylko najwyższemu elementowi,
    // który go przyjmuje, więc gdyby leżała na wierzchu (tak było wcześniej),
    // zjadałaby hover przyciskom — klikanie działało, bo goły Item nie
    // przyjmuje klawiszy myszy, ale podświetlanie już nie. Teraz przyciski
    // dostają hover jako pierwsze, a ta podkładka łapie resztę powierzchni.
    // Klik poza wyspą przy otwartej nakładce ją zamyka. Nakładka trzyma
    // klawiaturę Exclusive, a wtedy Hyprland nie oddaje kliknięć NIKOMU
    // innemu (zmierzone wirtualnym wskaźnikiem: pasek PluDE ani okna nic nie
    // dostają, HyprlandFocusGrab też nie widzi kliknięcia). Dlatego łapiemy
    // je sami: okno i maska rosną na cały ekran, a ten obszar leży pod
    // całą treścią. Klik w tło samej wyspy (poza przyciskami) przepuszczamy.
    MouseArea {
        id: outsideCatcher
        anchors.fill: parent
        z: -1
        enabled: root.overlayOpen
        onPressed: mouse => {
            const p = mapToItem(island, mouse.x, mouse.y);
            if (island.contains(p)) { mouse.accepted = false; return; }
            root.outsideClosedAt = Date.now();
            root.closeOverlay();
        }
    }

    Item {
        id: hoverArea

        anchors.top: parent.top
        anchors.topMargin: root.topMargin
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.reachWidth
        height: root.reachHeight

        HoverHandler { id: areaHover }
    }

    // Podkładka hovera pigułki rozmowy. Żyje przez CAŁĄ rozmowę, także gdy
    // wyspa jest rozwinięta i pigułka schowana: prawy koniec pigułki wystaje
    // poza zasięg rozwiniętej wyspy (±220 px), więc gdyby podkładka znikała
    // razem z pigułką, kursor stojący na jej końcu wypadałby poza maskę,
    // wyspa by się zwijała, pigułka wracała pod kursor — i tak w kółko.
    Item {
        id: pillHoverArea

        x: Math.round((root.width + root.collapsedWidth) / 2) + root.pillGap
        y: root.topMargin
        width: root.inVoice && root.voicePillEnabled ? voicePill.implicitWidth : 0
        height: root.collapsedHeight

        HoverHandler { id: pillHover }
    }

    IslandClip {
        id: island

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: root.topMargin

        width: root.expanded ? root.expandedWidth : root.restingWidth
        height: root.expanded ? root.expandedHeight : root.restingHeight
        radius: root.expanded ? 30 : height / 2

        color: "#0a0a0c"
        // Ze szklaną krawędzią ramkę rysuje glassRim (gradient), nie IslandClip.
        border.width: root.glassEdge ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
        contentUnderBorder: true

        // Sprężyste, płynne rozciąganie w stylu iOS
        Behavior on width {
            NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        }
        Behavior on height {
            NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        }
        Behavior on radius {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }

        scale: mouseArea.pressed ? 0.97 : 1.0
        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
        }

        // Klikanie w wyspę przypina ją rozwiniętą. Hover NIE jest tu obsługiwany —
        // ta MouseArea ma rozmiar animowanej wyspy, więc gubiłaby kursor
        // (patrz hoverArea wyżej). Kółka też nie bierze (brak onWheel), więc
        // zdarzenia lecą do WheelHandlera niżej.
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            // Nakładka i tak trzyma wyspę rozwiniętą, a klik w tło formularza
            // przypinałby ją tylko po to, żeby po zamknięciu została otwarta.
            // To samo przy pytaniu o aktualizację.
            enabled: !root.overlayOpen && !root.updateShown
            onClicked: root.pinned = !root.pinned
        }

        // Kółko przewija karty. Siedzi na wyspie, nie na podkładce hovera —
        // podkładka leży pod spodem i zdarzenia by do niej nie doszły.
        WheelHandler {
            id: wheel

            target: null
            // Pod nakładką kółko należy do jej list, nie do karuzeli; nad
            // korektorem do suwaków (poza nimi nie robi nic — przewinięcie
            // karty zamknęłoby panel pod ręką).
            enabled: root.expanded && !root.overlayOpen && !root.eqShown && !root.updateShown
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real accum: 0

            onWheel: event => {
                if (wheelCooldown.running) return;

                // Kółko w dół (ujemne y) i przesunięcie w prawo (dodatnie x)
                // idą do następnej karty.
                const dy = event.angleDelta.y;
                const dx = event.angleDelta.x;
                accum += dy !== 0 ? -dy : dx;

                if (Math.abs(accum) >= root.wheelStepDelta) {
                    root.stepCard(accum > 0 ? 1 : -1);
                    accum = 0;
                    wheelCooldown.restart();
                }
            }

            onEnabledChanged: accum = 0
        }

        Timer {
            id: wheelCooldown
            interval: root.wheelCooldownMs
            onTriggered: wheel.accum = 0
        }

        // ---- widok zwinięty: zerknięcie --------------------------------
        // Treść GlanceService: ikona, tytuł albo pasek, wartość po prawej.
        // Szerokość stała (docelowa), nie z animowanej wyspy — treść stoi
        // w miejscu, a wyspa ją odsłania, rozsuwając się.
        RowLayout {
            id: glanceRow

            readonly property var g: root.glanceView
            readonly property bool hasBar: g !== null && g.progress >= 0

            // Od lewej krawędzi DOCELOWEJ szerokości, nie centerIn: miejsce
            // na kropkę jest tylko po prawej.
            anchors.verticalCenter: parent.verticalCenter
            x: (parent.width - root.glanceWidth) / 2 + root.glancePadding
            width: root.glanceWidth - 2 * root.glancePadding - root.glanceDotSpace
            spacing: 10

            opacity: root.glanceShown ? 1 : 0
            visible: opacity > 0.01

            // Wejście z opóźnieniem, żeby treść nie wystawała poza wyspę,
            // która dopiero zaczyna rosnąć.
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: root.glanceShown ? 120 : 0 }
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
            }

            IslandIcon {
                id: glanceIcon
                Layout.alignment: Qt.AlignVCenter
                // Nazwa z IPC może być dowolna, a nieznana dałaby ikonę "play".
                kind: glanceRow.g && glanceIcon.paths[glanceRow.g.icon] ? glanceRow.g.icon : "bell"
                size: 18
                color: glanceRow.g ? glanceRow.g.iconColor : "#f2f2f2"
                Behavior on color { ColorAnimation { duration: 140 } }
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                visible: !glanceRow.hasBar && text !== ""
                text: glanceRow.g ? glanceRow.g.title : ""
                color: "#f2f2f2"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: root.glanceBarWidth
                Layout.preferredHeight: 6
                Layout.alignment: Qt.AlignVCenter
                visible: glanceRow.hasBar
                radius: 3
                antialiasing: true
                color: Qt.rgba(1, 1, 1, 0.16)

                Rectangle {
                    width: parent.width * (glanceRow.hasBar ? glanceRow.g.progress : 0)
                    height: parent.height
                    radius: parent.radius
                    antialiasing: true
                    color: glanceRow.g ? glanceRow.g.barColor : "#ededf0"

                    Behavior on width {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on color { ColorAnimation { duration: 160 } }
                }
            }

            // Przy pasku stała szerokość, żeby nie drgał przy przejściu
            // z "9%" na "100%".
            Text {
                Layout.preferredWidth: glanceRow.hasBar ? 38 : implicitWidth
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignRight
                visible: text !== ""
                text: glanceRow.g ? glanceRow.g.value : ""
                color: glanceRow.g ? glanceRow.g.valueColor : "#f2f2f2"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }

        // ---- widok zwinięty: sam zegar + kropka statusu ----------------

        RowLayout {
            anchors.centerIn: parent
            spacing: 7

            opacity: (root.expanded || root.glanceShown) ? 0 : 1
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: root.expanded ? 110 : 320
                    easing.type: Easing.OutCubic
                }
            }

            // Miniaturka okładki tego, co gra. Pokazujemy ją dopiero, gdy
            // obrazek naprawdę się wczytał — inaczej w pigułce siedziałby
            // pusty szary kwadracik.
            IslandClip {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                Layout.alignment: Qt.AlignVCenter
                radius: 7
                color: "#17171a"
                visible: miniArt.status === Image.Ready

                Image {
                    id: miniArt
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 64
                    sourceSize.height: 64
                    source: root.artUrl
                }
            }

            RollingDigits {
                Layout.alignment: Qt.AlignVCenter
                text: Qt.formatTime(clock.date, root.clockPillFormat)
                color: "#f2f2f2"
                pixelSize: 14
                weight: Font.DemiBold
                animated: root.rollingClock
            }

            // Wizualizacja spektrum z cavy w miejscu dawnej kropki statusu.
            SpectrumBars {
                id: spectrum

                Layout.preferredHeight: maxBarHeight
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasPlayer && CavaService.available

                barWidth: 2
                maxBarHeight: 16
                playing: root.isPlaying
                colors: root.spectrumBarColors
                accent: root.spectrumColor
                colorFadeMs: root.artAccentFadeMs
                smoothingMs: root.spectrumSmoothingMs
            }

            // Awaryjnie, gdy cavy nie ma albo nie wstała — stara kropka statusu.
            // Puls tylko z IslandConfig.loopAnimations.
            Rectangle {
                id: playbackDot
                width: 6; height: 6; radius: 3
                antialiasing: true
                color: root.isPlaying ? root.spectrumColor : "#4a4a4f"
                visible: root.hasPlayer && !CavaService.available
                Layout.alignment: Qt.AlignVCenter

                SequentialAnimation on opacity {
                    running: root.isPlaying && !CavaService.available && IslandConfig.loopAnimations
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    // Pauza muzyki w połowie cyklu zostawiłaby kropkę przygaszoną.
                    onRunningChanged: if (!running) playbackDot.opacity = 1
                }
            }

            // Wyłączony mikrofon systemowy. Tylko stan OFF — włączony to norma
            // i stała ikona byłaby szumem, a o wyciszeniu łatwo zapomnieć.
            // Bez micReady: przez pierwsze sekundy micOn jest false, bo
            // PipeWire jeszcze nie wstał, i ikona mignęłaby na starcie.
            IslandIcon {
                Layout.alignment: Qt.AlignVCenter
                kind: "micOff"
                size: 14
                color: "#e5484d"
                visible: AudioService.micReady && !AudioService.micOn
            }

            // Caps Lock włączony — o nim łatwo zapomnieć, jak o wyciszeniu.
            IslandIcon {
                Layout.alignment: Qt.AlignVCenter
                kind: "capsLock"
                size: 14
                color: "#f2f2f2"
                visible: root.capsIndicatorEnabled && HudService.capsLock
            }
        }

        // ---- kropka prywatności ----------------------------------------
        // Jak w iOS: pomarańczowa = mikrofon, zielona = kamera (kamera ma
        // pierwszeństwo, bo zwykle idzie z mikrofonem). Tylko w zwiniętej
        // pigułce — rozwinięta ma swoją treść, a rozmowę widać na karcie.
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            antialiasing: true
            color: PrivacyService.cameraActive ? "#30d158" : "#ff9f0a"

            opacity: root.privacyDotShown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // ---- widok rozwinięty: pasek kart ------------------------------
        // Każda karta ma zawartość o stałym rozmiarze, wyśrodkowaną w slocie
        // o szerokości największej karty. Wyspa animuje swój rozmiar i przycina —
        // dzięki temu przy animacji nic się nie rozjeżdża, treść po prostu
        // "wyłania się" spod krawędzi, tak jak w iOS. Sąsiednie karty są
        // poza wyspą, bo slot jest szerszy niż każda z nich.

        Item {
            id: cardStrip

            width: root.slotWidth * root.cardCount
            height: parent.height

            property real stripOffset: root.currentCard * root.slotWidth
            Behavior on stripOffset {
                enabled: root.animateCardChange
                NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
            }

            // Środek liczony z ANIMOWANEJ szerokości wyspy — aktywna karta
            // zostaje w środku przez cały czas rozciągania.
            x: (island.width - root.slotWidth) / 2 - stripOffset

            readonly property bool shown: root.expanded && !root.overlayOpen && !root.artPreviewShown
                && !root.eqShown && !root.updateShown
            opacity: shown ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: cardStrip.shown ? 380 : 130
                    easing.type: Easing.OutCubic
                }
            }

            // ---- karta: muzyka ----
            CardSlot {
                id: musicSlot
                card: root.cardMusic
                slotWidth: root.slotWidth
                stripOffset: cardStrip.stripOffset
                depth: root.carouselDepth
                current: cardStrip.shown && root.currentCard === card

                // Z odtwarzaczem: okładka, tytuł, postęp, kontrolki.
                Item {
                    id: musicCard

                    anchors.centerIn: parent
                    width: root.cardWidths[root.cardMusic]
                    height: root.cardHeights[root.cardMusic]
                    visible: root.hasPlayer

                    // Poświata: rozmyta okładka pod treścią i światło w kolorze
                    // widma od dołu. Wystaje poza kartę o glowBleed, bo wyspa
                    // przestrzela sprężyną (~3%) i przy dokładnym rozmiarze na
                    // brzegach mignąłby ciemny pas. Rozmycie liczy się tylko
                    // przy zmianie okładki — źródło stoi, więc w spoczynku to
                    // jeden prostokąt z gotowej tekstury.
                    Item {
                        id: musicGlow

                        readonly property int glowBleed: 24

                        anchors.fill: parent
                        anchors.margins: -glowBleed
                        visible: root.artGlow && glowArt.ready

                        ArtSwap {
                            id: glowArt
                            anchors.fill: parent
                            visible: false
                            source: root.artGlow ? root.artUrl : ""
                            sourceSize: Qt.size(48, 48)
                            animated: root.trackChangeEffect
                            duration: 700
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: glowArt
                            autoPaddingEnabled: false
                            blurEnabled: true
                            blur: 1
                            blurMax: 48
                            saturation: 0.25
                            brightness: -0.12
                            opacity: root.artGlowOpacity
                        }

                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 1; color: Qt.alpha(root.spectrumColor, root.artGlowTint) }
                            }
                        }
                    }

                    RowLayout {
                        id: musicRow

                        anchors.fill: parent
                        anchors.margins: 14
                        anchors.bottomMargin: 16
                        spacing: 13

                        IslandClip {
                            id: musicArt

                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 72
                            Layout.alignment: Qt.AlignVCenter
                            radius: 17
                            color: "#17171a"

                            // Podgląd rysuje w tym miejscu własną kopię okładki
                            // i z niego startuje, więc ta chowa się na czas lotu.
                            opacity: artPreviewLayer.visible ? 0 : 1
                            scale: artClick.pressed ? 0.94 : 1
                            Behavior on scale {
                                NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
                            }

                            // Obrót przy zmianie utworu kręci całym zaokrąglonym
                            // kafelkiem (patrz ArtSwap), a nie obrazkiem w środku.
                            transform: [
                                Rotation {
                                    origin.x: musicArt.width / 2
                                    origin.y: musicArt.height / 2
                                    axis { x: 0; y: 1; z: 0 }
                                    angle: art.flipAngle
                                },
                                CascadeShift { step: 0; shown: musicSlot.current }
                            ]

                            IslandIcon {
                                anchors.centerIn: parent
                                kind: "play"
                                size: 26
                                color: "#4a4a52"
                                visible: !art.ready
                            }

                            ArtSwap {
                                id: art
                                anchors.fill: parent
                                source: root.artUrl
                                sourceSize: Qt.size(144, 144)
                                animated: root.trackChangeEffect
                                flip: true
                            }

                            // Bez hovera, więc nie zabiera go podkładce i nie musi
                            // trafiać do controlsHovered. Klik nie przypina wyspy —
                            // MouseArea wyspy leży niżej i go nie dostaje.
                            MouseArea {
                                id: artClick
                                anchors.fill: parent
                                enabled: art.ready
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.eqView = false;
                                    root.artPreview = true;
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            transform: CascadeShift { step: 1; shown: musicSlot.current }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                RollingText {
                                    Layout.fillWidth: true
                                    text: root.trackTitle !== "" ? root.trackTitle : "Nic nie gra"
                                    color: "#f5f5f5"
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    animated: root.trackChangeEffect
                                }

                                // Wizualizator, jak fala w rozwiniętej wyspie iOS.
                                // Klik otwiera korektor. Bez hovera (nie zabiera
                                // go podkładce), jak okładka obok. Obwódka
                                // w kolorze widma = korektor włączony.
                                Rectangle {
                                    id: eqToggle

                                    Layout.preferredWidth: cardBars.width + 14
                                    Layout.preferredHeight: 20
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 7
                                    antialiasing: true
                                    color: Qt.rgba(1, 1, 1, eqClick.pressed ? 0.16 : 0.07)
                                    border.width: 1
                                    border.color: EqualizerService.enabled && EqualizerService.available
                                        ? Qt.rgba(root.spectrumColor.r, root.spectrumColor.g, root.spectrumColor.b, 0.7)
                                        : "transparent"
                                    scale: eqClick.pressed ? 0.92 : 1

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on scale {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
                                    }

                                    SpectrumBars {
                                        id: cardBars
                                        anchors.centerIn: parent
                                        barWidth: 3
                                        maxBarHeight: 12
                                        playing: root.isPlaying
                                        colors: root.spectrumBarColors
                                        accent: root.spectrumColor
                                        colorFadeMs: root.artAccentFadeMs
                                        smoothingMs: root.spectrumSmoothingMs
                                    }

                                    MouseArea {
                                        id: eqClick
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openEqualizer()
                                    }
                                }
                            }

                            RollingText {
                                Layout.fillWidth: true
                                text: root.trackArtist
                                color: "#9a9aa2"
                                font.pixelSize: 12
                                visible: root.trackArtist !== ""
                                animated: root.trackChangeEffect
                                // Wykonawca dojeżdża odrobinę wolniej niż tytuł —
                                // schodkiem wygląda to na jedną zmianę, a nie dwie naraz.
                                duration: 460
                            }

                            // Wyjście dźwięku i głośność w jednym: klik w ikonę
                            // wycisza, klik w resztę przełącza wyjście, kółko
                            // zmienia głośność.
                            AudioOutputChip {
                                id: outputChip
                                Layout.topMargin: 4
                                maxWidth: 180
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 7
                                visible: root.hasProgress

                                Text {
                                    text: root.formatTime(root.hasPlayer ? root.player.position : 0)
                                    color: "#78787f"
                                    font.pixelSize: 10
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 3
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 1.5
                                    antialiasing: true
                                    color: Qt.rgba(1, 1, 1, 0.13)

                                    Rectangle {
                                        width: parent.width * root.progress
                                        height: parent.height
                                        radius: parent.radius
                                        antialiasing: true
                                        color: "#ededf0"

                                        Behavior on width {
                                            NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
                                        }
                                    }
                                }

                                Text {
                                    text: root.formatTime(root.trackLength)
                                    color: "#78787f"
                                    font.pixelSize: 10
                                }
                            }
                        }

                        RowLayout {
                            // 7 zamiast 5, żeby pierścienie hovera sąsiadów się nie stykały
                            spacing: 7
                            Layout.alignment: Qt.AlignVCenter
                            transform: CascadeShift { step: 2; shown: musicSlot.current }

                            IslandButton {
                                id: btnPrev
                                kind: "prev"
                                enabled: root.hasPlayer && root.player.canGoPrevious
                                onClicked: root.player.previous()
                            }

                            IslandButton {
                                id: btnPlay
                                kind: root.isPlaying ? "pause" : "play"
                                big: true
                                enabled: root.hasPlayer && root.player.canTogglePlaying
                                onClicked: root.player.togglePlaying()
                            }

                            IslandButton {
                                id: btnNext
                                kind: "next"
                                enabled: root.hasPlayer && root.player.canGoNext
                                onClicked: root.player.next()
                            }
                        }
                    }
                }

                // Bez odtwarzacza: krótka informacja zamiast pustej karty.
                Item {
                    anchors.centerIn: parent
                    width: root.cardWidths[root.cardMusic]
                    height: root.cardHeights[root.cardMusic]
                    visible: !root.hasPlayer

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        transform: CascadeShift { shown: musicSlot.current }

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            radius: 12
                            color: "#17171a"

                            IslandIcon {
                                anchors.centerIn: parent
                                kind: "play"
                                size: 18
                                color: "#4a4a52"
                            }
                        }

                        ColumnLayout {
                            spacing: 2

                            Text {
                                text: "Nic nie gra"
                                color: "#f5f5f5"
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: "Włącz coś, a pojawi się tutaj"
                                color: "#9a9aa2"
                                font.pixelSize: 12
                            }

                            AudioOutputChip {
                                id: outputChipIdle
                                Layout.topMargin: 4
                                maxWidth: 200
                            }
                        }
                    }
                }
            }

            // ---- karta AirPodsów (tylko przy połączonych słuchawkach) ----
            CardSlot {
                id: airpodsSlot
                card: root.cardAirPods
                slotWidth: root.slotWidth
                stripOffset: cardStrip.stripOffset
                depth: root.carouselDepth
                current: cardStrip.shown && root.currentCard === card

                AirPodsCard {
                    id: airpods
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    active: airpodsSlot.current
                }
            }

            // ---- karta: Discord ----
            CardSlot {
                id: discordSlot
                card: root.cardDiscord
                slotWidth: root.slotWidth
                stripOffset: cardStrip.stripOffset
                depth: root.carouselDepth
                current: cardStrip.shown && root.currentCard === card

                Item {
                    anchors.centerIn: parent
                    width: root.cardWidths[root.cardDiscord]
                    height: root.cardHeights[root.cardDiscord]

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        anchors.bottomMargin: 16
                        spacing: 13

                        IslandClip {
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 72
                            Layout.alignment: Qt.AlignVCenter
                            radius: 17
                            color: "#17171a"
                            transform: CascadeShift { step: 0; shown: discordSlot.current }

                            IslandIcon {
                                anchors.centerIn: parent
                                kind: "discord"
                                size: 34
                                color: DiscordService.connected ? "#5865f2" : "#4a4a52"

                                Behavior on color {
                                    ColorAnimation { duration: 300 }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            transform: CascadeShift { step: 1; shown: discordSlot.current }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.discordTitle
                                color: "#f5f5f5"
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.discordSubtitle
                                color: root.inVoice ? "#38d47a" : "#9a9aa2"
                                font.pixelSize: 12
                                visible: text !== ""
                            }

                            // Mikrofon dla całego systemu (wszystkie źródła
                            // PipeWire), niezależny od wyciszenia w Discordzie.
                            RowLayout {
                                Layout.topMargin: 4
                                spacing: 7

                                IslandSwitch {
                                    id: micSwitch
                                    Layout.alignment: Qt.AlignVCenter
                                    checked: AudioService.micOn
                                    enabled: AudioService.micReady
                                    onToggled: AudioService.setMicOn(!AudioService.micOn)
                                }

                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: AudioService.micOn ? "Mikrofon systemowy" : "Mikrofon wyłączony"
                                    color: AudioService.micOn ? "#e2e2e6" : "#e5484d"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    opacity: micSwitch.opacity
                                }
                            }
                        }

                        RowLayout {
                            spacing: 7
                            Layout.alignment: Qt.AlignVCenter
                            transform: CascadeShift { step: 2; shown: discordSlot.current }

                            IslandButton {
                                id: btnMic
                                kind: DiscordService.muted ? "micOff" : "mic"
                                accented: DiscordService.muted
                                enabled: DiscordService.connected
                                onClicked: DiscordService.setMute(!DiscordService.muted)
                            }

                            IslandButton {
                                id: btnDeaf
                                kind: DiscordService.deafened ? "headsetOff" : "headset"
                                accented: DiscordService.deafened
                                enabled: DiscordService.connected
                                onClicked: DiscordService.setDeafen(!DiscordService.deafened)
                            }

                            IslandButton {
                                id: btnLeave
                                kind: "callEnd"
                                big: true
                                accented: true
                                enabled: root.inVoice
                                onClicked: DiscordService.leave()
                            }
                        }
                    }
                }
            }

            // ---- karta: zegar + minutniki KClock ----
            CardSlot {
                id: clockSlot
                card: root.cardClock
                slotWidth: root.slotWidth
                stripOffset: cardStrip.stripOffset
                depth: root.carouselDepth
                current: cardStrip.shown && root.currentCard === card

                ClockCard {
                    id: clockCard
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight

                    date: clock.date
                    timeFormat: root.clockCardFormat
                    dateFormat: root.clockDateFormat
                    localeName: root.uiLocale
                    timersEnabled: root.timersEnabled
                    rollingDigits: root.rollingClock
                    active: clockSlot.current
                }
            }

            // ---- karta: łączność (Wi-Fi, Bluetooth, urządzenia) ----
            CardSlot {
                id: connectivitySlot
                card: root.cardConnectivity
                slotWidth: root.slotWidth
                stripOffset: cardStrip.stripOffset
                depth: root.carouselDepth
                current: cardStrip.shown && root.currentCard === card

                ConnectivityCard {
                    id: connectivity
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    active: connectivitySlot.current

                    onOpenWifi: root.openOverlay("wifi")
                    onOpenBluetooth: root.openOverlay("bluetooth")
                }
            }

            // ---- karta: powiadomienia i transfery ----
            CardSlot {
                id: notificationsSlot
                card: root.cardNotifications
                slotWidth: root.slotWidth
                stripOffset: cardStrip.stripOffset
                depth: root.carouselDepth
                current: cardStrip.shown && root.currentCard === card

                NotificationCard {
                    id: notifications
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    active: notificationsSlot.current
                }
            }
        }

        // ---- kropki: która karta jest aktywna ---------------------------

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            spacing: 4

            opacity: cardStrip.opacity
            visible: cardStrip.visible

            Repeater {
                model: root.cardCount

                delegate: Rectangle {
                    required property int index
                    readonly property bool active: index === root.currentCard

                    width: active ? 10 : 4
                    height: 4
                    radius: 2
                    antialiasing: true
                    color: active ? "#f2f2f2" : Qt.rgba(1, 1, 1, 0.25)

                    Behavior on width {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }
            }
        }

        // ---- podgląd okładki ------------------------------------------
        // Okładka wylatuje z miejsca, w którym stoi na karcie muzyki, i rośnie
        // do rozmiaru całej wyspy (w zamknięciu wraca tą samą drogą). Oba końce
        // są powiązaniami, nie migawką z mapToItem: wyspa w tym czasie sama
        // zmienia rozmiar, a karta muzyki jedzie za jej środkiem. Pozycja
        // okładki w wyspie to suma x/y rodziców, bo mapToItem nie jest
        // zależnością i nie przeliczyłby się w trakcie animacji.
        Item {
            id: artPreviewLayer

            anchors.fill: parent

            property real progress: root.artPreviewShown ? 1 : 0
            Behavior on progress {
                NumberAnimation { duration: root.artPreviewMs; easing.type: Easing.OutCubic }
            }

            visible: progress > 0.001
            // Zwinięcie wyspy w trakcie podglądu: okładka gaśnie razem
            // z kartami, zamiast lecieć do karty, której już nie widać.
            opacity: root.expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

            readonly property real fromX: cardStrip.x + musicSlot.x + musicCard.x + musicRow.x + musicArt.x
            readonly property real fromY: cardStrip.y + musicSlot.y + musicCard.y + musicRow.y + musicArt.y

            function lerp(a, b) { return a + (b - a) * progress; }

            IslandClip {
                id: previewArt

                x: artPreviewLayer.lerp(artPreviewLayer.fromX, 0)
                y: artPreviewLayer.lerp(artPreviewLayer.fromY, 0)
                width: artPreviewLayer.lerp(musicArt.width, island.width)
                height: artPreviewLayer.lerp(musicArt.height, island.height)
                radius: artPreviewLayer.lerp(musicArt.radius, island.radius)
                color: "#17171a"

                // Najpierw miniaturka z karty (ten sam rozmiar źródła, więc
                // z bufora, od razu), nad nią pełna rozdzielczość, gdy dojdzie —
                // inaczej lot zaczynałby się od pustego kwadratu.
                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 144
                    sourceSize.height: 144
                    source: root.artUrl
                }

                Image {
                    id: previewArtFull
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: root.artPreviewSize * 2
                    sourceSize.height: root.artPreviewSize * 2
                    // Duża wersja tylko przy otwartym podglądzie — to kilka MB
                    // w pamięci na każdą okładkę, której nikt nie ogląda.
                    source: artPreviewLayer.visible ? root.artUrl : ""
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                // Przyciemnienie pod tekstem — okładka bywa jasna u dołu.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * 0.42
                    opacity: previewInfo.opacity
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.78) }
                    }
                }

                // Treść o stałej szerokości (docelowej), przypięta do dołu:
                // w trakcie lotu nie przelicza się elide, tylko wyłania.
                ColumnLayout {
                    id: previewInfo

                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 20
                    anchors.bottomMargin: 18
                    width: root.artPreviewSize - 40
                    spacing: 2

                    // Wchodzi pod koniec lotu, wychodzi od razu na starcie powrotu.
                    opacity: Math.max(0, (artPreviewLayer.progress - 0.6) / 0.4)

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.trackTitle
                        color: "#ffffff"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.trackArtist
                        color: Qt.rgba(1, 1, 1, 0.72)
                        font.pixelSize: 13
                        visible: root.trackArtist !== ""
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 8
                        visible: root.hasProgress

                        Text {
                            text: root.formatTime(root.hasPlayer ? root.player.position : 0)
                            color: Qt.rgba(1, 1, 1, 0.7)
                            font.pixelSize: 10
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 3
                            Layout.alignment: Qt.AlignVCenter
                            radius: 1.5
                            antialiasing: true
                            color: Qt.rgba(1, 1, 1, 0.22)

                            Rectangle {
                                width: parent.width * root.progress
                                height: parent.height
                                radius: parent.radius
                                antialiasing: true
                                color: "#ffffff"

                                Behavior on width {
                                    NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Text {
                            text: root.formatTime(root.trackLength)
                            color: Qt.rgba(1, 1, 1, 0.7)
                            font.pixelSize: 10
                        }
                    }
                }

                // Klik w podgląd wraca do karty. Tylko przy otwartym — w trakcie
                // powrotu klik ma trafiać w kartę, która już się wyłania.
                MouseArea {
                    anchors.fill: parent
                    enabled: root.artPreviewShown
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.artPreview = false
                }
            }
        }

        // ---- korektor ----------------------------------------------------
        // Stały rozmiar docelowy, wyśrodkowany: wyspa rośnie i go odsłania,
        // jak treść kart. Bez Loadera — panel jest lekki, a niewidoczny nie
        // kosztuje rysowania; krzywa przelicza się tylko przy zmianie pasm.
        EqualizerPanel {
            id: eqPanel

            anchors.centerIn: parent
            width: root.eqWidth
            height: root.eqHeight

            accent: root.spectrumColor
            opacity: root.eqShown ? 1 : 0
            visible: opacity > 0.01
            enabled: root.eqShown

            Behavior on opacity {
                NumberAnimation { duration: root.eqShown ? 300 : 120; easing.type: Easing.OutCubic }
            }

            onClosed: root.eqView = false
        }

        // ---- aktualizacja ------------------------------------------------
        UpdatePanel {
            id: updatePanel

            anchors.centerIn: parent
            width: root.updateWidth
            height: root.updateHeight

            // Ta sama sprężyna co wyspa: panel jest wyśrodkowany, więc skok
            // jego wysokości (lista -> "Zaktualizowano", 196 -> 66 px)
            // przesunąłby nagłówek o kilkadziesiąt px w chwili, gdy wyspa
            // dopiero rusza.
            Behavior on height {
                NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
            }

            opacity: root.updateShown ? 1 : 0
            visible: opacity > 0.01
            enabled: root.updateShown

            Behavior on opacity {
                NumberAnimation { duration: root.updateShown ? 300 : 120; easing.type: Easing.OutCubic }
            }
        }

        // ---- nakładki: Wi-Fi i Bluetooth -------------------------------
        // Zastępują cały pasek kart. Panel powstaje dopiero przy otwarciu —
        // skaner Wi-Fi i skanowanie Bluetootha włączają się w jego
        // Component.onCompleted i mają zgasnąć razem z nim.
        //
        // focus na hoście, nie na Loaderze: Escape ma działać także wtedy,
        // gdy kursor klawiatury siedzi w polu tekstowym. TextInput nie
        // połyka Escape, więc klawisz idzie w górę drzewa i trafia tutaj.
        FocusScope {
            id: overlayHost

            anchors.centerIn: parent
            width: root.overlayWidth
            height: root.overlayHeight

            focus: root.overlayOpen
            opacity: root.overlayOpen ? 1 : 0
            visible: opacity > 0.01
            enabled: root.overlayOpen

            Behavior on opacity {
                NumberAnimation { duration: root.overlayOpen ? 260 : 120; easing.type: Easing.OutCubic }
            }

            Keys.onEscapePressed: event => {
                root.closeOverlay();
                event.accepted = true;
            }

            // Panel budujemy asynchronicznie i niszczymy dopiero po animacji
            // zamknięcia. Synchronicznie budowa WifiPanel zatrzymywała
            // pierwszą klatkę otwarcia na 145–195 ms, a zniszczenie klatkę
            // zamknięcia na ~100 ms (zmierzone). Animacje liczą się z zegara,
            // więc po takiej przerwie wyspa przeskakiwała. Treść i tak wchodzi
            // przez opacity overlayHost.
            //
            // shownMode zostaje po zamknięciu (overlayMode wraca do ""), żeby
            // panel dotrwał do końca animacji. overlayLingerMs > 520 ms zmiany
            // rozmiaru wyspy.
            property string shownMode: ""
            property int overlayLingerMs: 600
            Connections {
                target: root
                function onOverlayModeChanged() {
                    if (root.overlayMode !== "") overlayHost.shownMode = root.overlayMode;
                    else overlayLinger.restart();
                }
            }
            Timer {
                id: overlayLinger
                interval: overlayHost.overlayLingerMs
                onTriggered: if (!root.overlayOpen) overlayHost.shownMode = "";
            }

            Loader {
                id: overlay

                anchors.fill: parent
                asynchronous: true
                active: overlayHost.shownMode !== ""
                source: overlayHost.shownMode === "wifi" ? "WifiPanel.qml"
                    : overlayHost.shownMode === "bluetooth" ? "BluetoothPanel.qml"
                    : ""

                onLoaded: item.closed.connect(root.closeOverlay)
            }
        }
    }

    // ---------------------------------------------------------------
    // Pasek postępu transferu — pod wyspą, z małą przerwą
    // ---------------------------------------------------------------

    // Celowo poza wyspą, nie w środku: ma być widoczny także przy zwiniętej
    // pigułce, a nie zabierać jej miejsca. Idzie za animowaną szerokością
    // i wysokością wyspy, więc przy rozwijaniu zjeżdża razem z krawędzią.
    Rectangle {
        id: jobBar

        readonly property bool shown: NotificationService.hasJobs

        anchors.horizontalCenter: parent.horizontalCenter
        y: island.y + island.height + root.jobBarGap
        width: Math.max(40, island.width - 24)
        height: 3
        radius: 1.5
        antialiasing: true
        color: Qt.rgba(1, 1, 1, 0.16)

        opacity: shown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        Rectangle {
            width: parent.width * NotificationService.jobProgress
            height: parent.height
            radius: parent.radius
            antialiasing: true
            color: "#5b8cff"
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }
    }

    // ---------------------------------------------------------------
    // Szklana krawędź i fala przy zdarzeniach
    // ---------------------------------------------------------------

    // Ramka z gradientem zamiast jednolitej: jaśniejsza u góry, gasnąca
    // w dół — wyspa wygląda na wypukłą, a nie na płaską czarną plamę.
    // Rectangle nie umie gradientu na ramce, więc to pierścień wypełniony
    // gradientem: dwa zaokrąglone prostokąty w jednej ścieżce z OddEvenFill
    // (zewnętrzny minus wewnętrzny). Rodzeństwo wyspy, jak obwódka baterii —
    // IslandClip rysowałby treść nad nim. Na karcie muzyki z poświatą dół
    // ramki łapie kolor widma.
    Shape {
        id: glassRim

        readonly property real w: root.glassRimWidth
        readonly property real r: Math.min(island.radius, height / 2)
        property color bottomColor: musicGlow.visible && root.currentKey === "music" && root.expanded
                                             && cardStrip.shown
            ? Qt.alpha(root.spectrumColor, 0.32) : Qt.rgba(1, 1, 1, 0.07)
        Behavior on bottomColor { ColorAnimation { duration: 400 } }

        x: island.x
        y: island.y
        width: island.width
        height: island.height
        scale: island.scale
        visible: root.glassEdge
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillRule: ShapePath.OddEvenFill
            strokeColor: "transparent"
            strokeWidth: 0
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: 0; y2: glassRim.height
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.26) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.06) }
                GradientStop { position: 1; color: glassRim.bottomColor }
            }

            PathRectangle {
                width: glassRim.width
                height: glassRim.height
                radius: glassRim.r
            }
            PathRectangle {
                x: glassRim.w
                y: glassRim.w
                width: glassRim.width - 2 * glassRim.w
                height: glassRim.height - 2 * glassRim.w
                radius: Math.max(0, glassRim.r - glassRim.w)
            }
        }
    }

    EventRipple {
        id: ripple
        anchors.fill: parent
        target: island
    }

    // ---------------------------------------------------------------
    // Obwódka baterii — pasek postępu po obrysie zwiniętej pigułki
    // ---------------------------------------------------------------

    // Rodzeństwo wyspy, nie dziecko: IslandClip rysuje swoją ramkę NAD
    // zawartością, więc od środka obwódka szłaby pod nią. Kopiuje geometrię
    // i skalę wyspy, żeby przy kliknięciu i zwijaniu nie odstawała.
    // Obrys zaczyna się u góry pośrodku i idzie zgodnie z zegarem, a długość
    // przycina `trim.end` — dash pattern liczy w grubościach linii i przy
    // zmianie rozmiaru wyspy trzeba by go przeliczać.
    // UPower.displayDevice to zbiorcza bateria; na desktopie nie jest
    // `isLaptopBattery` i obwódki nie ma wcale. `percentage` jest 0–1
    // (zmierzone: 0,48 przy 48 w /sys/class/power_supply/BAT0/capacity),
    // a `ready` przychodzi ~1 s po starcie — UPower startuje z aktywacji D-Bus.
    Shape {
        id: batteryRing

        readonly property var battery: UPower.displayDevice
        readonly property bool available: battery.ready && battery.isLaptopBattery
        readonly property real level: available ? Math.max(0, Math.min(1, battery.percentage)) : 0
        readonly property bool charging: battery.state === UPowerDeviceState.Charging
                                         || battery.state === UPowerDeviceState.FullyCharged
        readonly property bool low: level <= root.batteryLowLevel && !charging
        // Na zasilaczu (także FullyCharged) zielona, na baterii jasna.
        property color ringColor: low ? root.batteryLowColor
                                  : (charging ? root.batteryChargingColor : root.batteryColor)
        Behavior on ringColor { ColorAnimation { duration: 400; easing.type: Easing.OutCubic } }
        // Pulsuje tylko prawdziwe ładowanie — FullyCharged na zasilaczu stoi
        // spokojnie, inaczej laptop przy biurku mrugałby bez końca.
        readonly property bool pulsing: battery.state === UPowerDeviceState.Charging

        // Jasność linii jako alfa koloru, nie `opacity` Shape — tamta już
        // steruje chowaniem obwódki przy rozwinięciu i animacje by się gryzły.
        property real pulse: 1
        SequentialAnimation on pulse {
            running: batteryRing.pulsing && batteryRing.visible && IslandConfig.loopAnimations
            loops: Animation.Infinite
            NumberAnimation { to: root.batteryPulseMin; duration: root.batteryPulseMs / 2; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: root.batteryPulseMs / 2; easing.type: Easing.InOutSine }
            // Zatrzymana w połowie zostawiłaby linię przygaszoną na stałe.
            onRunningChanged: if (!running) batteryRing.pulse = 1
        }

        // Linia leży w całości wewnątrz obrysu wyspy (wcięcie o pół grubości).
        readonly property real inset: root.batteryRingWidth / 2
        readonly property real x0: inset
        readonly property real y0: inset
        readonly property real x1: width - inset
        readonly property real y1: height - inset
        readonly property real r: Math.max(0, Math.min(island.radius, height / 2) - inset)

        x: island.x
        y: island.y
        width: island.width
        height: island.height
        scale: island.scale

        // Tylko w spoczynku: rozwinięta wyspa ma własną treść, a zielona rama
        // wokół formularza Wi-Fi czy karty muzyki tylko by rozpraszała.
        opacity: available && root.batteryRingEnabled && !root.expanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.batteryRingWidth
            strokeColor: Qt.alpha(batteryRing.ringColor, batteryRing.pulse)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            trim.end: batteryRing.level

            startX: batteryRing.width / 2
            startY: batteryRing.y0

            PathLine { x: batteryRing.x1 - batteryRing.r; y: batteryRing.y0 }
            PathArc { x: batteryRing.x1; y: batteryRing.y0 + batteryRing.r; radiusX: batteryRing.r; radiusY: batteryRing.r }
            PathLine { x: batteryRing.x1; y: batteryRing.y1 - batteryRing.r }
            PathArc { x: batteryRing.x1 - batteryRing.r; y: batteryRing.y1; radiusX: batteryRing.r; radiusY: batteryRing.r }
            PathLine { x: batteryRing.x0 + batteryRing.r; y: batteryRing.y1 }
            PathArc { x: batteryRing.x0; y: batteryRing.y1 - batteryRing.r; radiusX: batteryRing.r; radiusY: batteryRing.r }
            PathLine { x: batteryRing.x0; y: batteryRing.y0 + batteryRing.r }
            PathArc { x: batteryRing.x0 + batteryRing.r; y: batteryRing.y0; radiusX: batteryRing.r; radiusY: batteryRing.r }
            PathLine { x: batteryRing.width / 2; y: batteryRing.y0 }
        }
    }

    // ---------------------------------------------------------------
    // Pigułka rozmowy — obok zwiniętej wyspy, tylko podczas rozmowy
    // ---------------------------------------------------------------

    // Pigułki leżą pod wyspą (z ujemne) i wypływają spod jej krawędzi — patrz
    // LiquidPill. Kursora nie łapią same: pigułka rozmowy ma podkładkę
    // pillHoverArea w miejscu spoczynku, reszta jest czysto informacyjna.
    // Wyspa w chwili pojawienia się pigułki bywa jeszcze szersza (wraca
    // z rozwinięcia albo zerknięcia) — wtedy pigułka czeka (originBusy).
    readonly property bool islandShrinking: island.width > root.collapsedWidth + 2

    LiquidPill {
        id: voicePill

        // visible ustawione twardo (w LiquidPill), nie z opacity: pigułka ma
        // zniknąć w chwili rozwinięcia, żeby nie wystawała spod rosnącej wyspy.
        // Animowane jest tylko pojawianie się.
        shown: root.inVoice && root.voicePillEnabled && !root.expanded && !root.restingWide

        z: -0.5
        toRight: true
        originEdge: Math.round((root.width + root.collapsedWidth) / 2)
        gap: root.pillGap
        originBusy: root.islandShrinking
        y: pillHoverArea.y
        height: root.collapsedHeight
        implicitWidth: Math.min(root.pillMaxWidth, pillRow.implicitWidth + 24)

        RowLayout {
            id: pillRow

            anchors.centerIn: parent
            width: Math.min(implicitWidth, root.pillMaxWidth - 24)
            spacing: 6

            // Pulsująca kropka — trwa rozmowa. Puls tylko z IslandConfig.loopAnimations.
            Rectangle {
                id: voiceDot
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                Layout.alignment: Qt.AlignVCenter
                radius: 3
                antialiasing: true
                color: "#38d47a"

                SequentialAnimation on opacity {
                    running: voicePill.shown && IslandConfig.loopAnimations
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    // Wyłączenie w ustawieniach w połowie cyklu zostawiłoby kropkę przygaszoną.
                    onRunningChanged: if (!running) voiceDot.opacity = 1
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: 110
                elide: Text.ElideRight
                text: DiscordService.channelName
                color: "#f2f2f2"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Text {
                text: root.formatTime(DiscordService.elapsedSeconds)
                color: "#9a9aa2"
                font.pixelSize: 12
            }

            // Deafen ma pierwszeństwo — wyciszone słuchawki oznaczają też mikrofon.
            IslandIcon {
                Layout.alignment: Qt.AlignVCenter
                kind: DiscordService.deafened ? "headsetOff" : "micOff"
                size: 13
                color: "#e5484d"
                visible: DiscordService.muted || DiscordService.deafened
            }
        }
    }

    // ---------------------------------------------------------------
    // Pigułka udostępniania ekranu — po lewej od zwiniętej wyspy
    // ---------------------------------------------------------------

    // Czysto informacyjna: nie ma podkładki hovera ani regionu w masce, więc
    // kursor przechodzi przez nią do okien pod spodem. Nie ma karty, którą
    // mogłaby otwierać — udostępnianie to stan, nie sterowanie.
    LiquidPill {
        id: screencastPill

        shown: PrivacyService.screenActive && root.screencastPillEnabled
               && !root.expanded && !root.restingWide

        // Lewa strona, lustrzanie do pigułki rozmowy po prawej.
        z: -0.5
        toRight: false
        originEdge: Math.round((root.width - root.collapsedWidth) / 2)
        gap: root.pillGap
        originBusy: root.islandShrinking
        y: root.topMargin
        height: root.collapsedHeight
        implicitWidth: Math.min(root.pillMaxWidth, screencastRow.implicitWidth + 24)

        RowLayout {
            id: screencastRow

            anchors.centerIn: parent
            width: Math.min(implicitWidth, root.pillMaxWidth - 24)
            spacing: 6

            // Czerwona pulsująca kropka — jak wskaźnik nagrywania. Puls tylko
            // z IslandConfig.loopAnimations.
            Rectangle {
                id: screencastDot
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                Layout.alignment: Qt.AlignVCenter
                radius: 3
                antialiasing: true
                color: "#ff4b4b"

                SequentialAnimation on opacity {
                    running: screencastPill.shown && IslandConfig.loopAnimations
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                    onRunningChanged: if (!running) screencastDot.opacity = 1
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: 110
                elide: Text.ElideRight
                text: PrivacyService.screenApp
                color: "#f2f2f2"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Text {
                text: root.formatTime(PrivacyService.screenElapsedSeconds)
                color: "#ffb450"
                font.pixelSize: 12
            }
        }
    }

    // ---------------------------------------------------------------
    // Pigułka minutnika — po lewej, za pigułką udostępniania
    // ---------------------------------------------------------------

    // Informacyjna jak udostępnianie: bez hovera i bez regionu w masce.
    // Sterowanie jest na karcie zegara. Pokazuje TimerService.featured:
    // dzwoniący, potem najbliższy końca, potem zatrzymany w połowie.
    LiquidPill {
        id: timerPill

        readonly property var timer: TimerService.featured
        readonly property int more: TimerService.activeTimers.length - 1

        shown: timer !== null && root.timerPillEnabled && root.timersEnabled
               && !root.expanded && !root.restingWide

        // Za pigułką udostępniania, gdy jest (i z niej wypływa); inaczej
        // przy samej wyspie.
        z: -0.5
        toRight: false
        originEdge: screencastPill.shown ? screencastPill.x : Math.round((root.width - root.collapsedWidth) / 2)
        gap: root.pillGap
        originBusy: root.islandShrinking
        y: root.topMargin
        height: root.collapsedHeight
        implicitWidth: timerRow.implicitWidth + 24

        RowLayout {
            id: timerRow

            readonly property color tint: !timerPill.timer ? "#8e8e93"
                : timerPill.timer.ringing ? "#ff453a"
                : timerPill.timer.running ? "#ff9f0a" : "#8e8e93"

            anchors.centerIn: parent
            spacing: 6

            IslandIcon {
                Layout.alignment: Qt.AlignVCenter
                kind: timerPill.timer && timerPill.timer.ringing ? "bell"
                    : (timerPill.timer && !timerPill.timer.running ? "pause" : "timer")
                size: 14
                color: timerRow.tint
            }

            Text {
                text: timerPill.timer ? TimerService.format(TimerService.remaining(timerPill.timer)) : ""
                color: timerRow.tint
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }

            // Więcej aktywnych minutników niż jeden.
            Text {
                visible: timerPill.more > 0
                text: "+" + timerPill.more
                color: "#8e8e93"
                font.pixelSize: 11
            }
        }
    }
}
