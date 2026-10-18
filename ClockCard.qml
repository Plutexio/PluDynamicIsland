import QtQuick
import QtQuick.Layouts

// Karta "zegar": duży zegar z datą, a obok minutniki z KClock (TimerService).
// Bez KClock albo bez minutników karta jest tym, czym była — samym zegarem
// 296 × 98. Plusik w rogu dodaje nowy (czas kółkiem albo z presetów),
// klik w zegar otwiera KClock — tam się minutniki nazywa i usuwa.
//
// Jak ConnectivityCard: stały rozmiar (trzecia geometria z DynamicIsland)
// i jedno `hovering`, które wyspa dolicza do controlsHovered.
Item {
    id: card

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    property int rowHeight: 34       // przycisk 30 + oddech na pierścień hovera
    property int rowSpacing: 2
    property int visibleRows: 3      // więcej = lista przewijana kółkiem
    property int clockColumnWidth: 172   // "sobota, 17 października" przy 150 się obcinała
    // Kropki stron karuzeli siedzą 6 px nad dolną krawędzią wyspy i nachodziły
    // na ostatni wiersz (zmierzone zrzutem) — stąd większy margines na dole.
    property int listTopMargin: 8
    property int listBottomMargin: 14

    // Z wyspy: jeden zegar systemowy i formaty z konfiguracji.
    property date date: new Date()
    property string timeFormat: "hh:mm"
    property string dateFormat: "dddd, d MMMM"
    property string localeName: "pl_PL"

    // Wyspa wyłącza, gdy minutniki są schowane w konfiguracji.
    property bool timersEnabled: true
    // Karta widoczna na rozwiniętej wyspie. Zejście z niej zamyka wybierak —
    // inaczej następne otwarcie karty zaczynałoby od pół-wybranego minutnika.
    property bool active: false
    // Cyfry zegara przewijają się przy zmianie (RollingDigits).
    property bool rollingDigits: true

    // Wybierak nowego minutnika: krok kółka w minutach (z Shiftem większy),
    // presety i zakres. Ostatni wybór zostaje na następny raz.
    property var presetMinutes: [1, 5, 10, 25]
    property int wheelStepMinutes: 1
    property int wheelShiftStepMinutes: 5
    property int maxMinutes: 999
    property int wheelNotch: 120          // pełny ząbek angleDelta — patrz AudioOutputChip
    property int draftMinutes: 5

    readonly property bool canAdd: timersEnabled && TimerService.available
    property bool adding: false
    onActiveChanged: if (!active) adding = false
    onCanAddChanged: if (!canAdd) adding = false

    readonly property bool hasTimers: timersEnabled && TimerService.available && TimerService.timers.length > 0
    readonly property bool wide: hasTimers || adding

    implicitWidth: wide ? 440 : 296
    implicitHeight: hasTimers && !adding
        ? Math.max(98, listTopMargin + listBottomMargin
                   + Math.min(TimerService.timers.length, visibleRows) * (rowHeight + rowSpacing) - rowSpacing)
        : 98

    // ---------------------------------------------------------------
    // Stan
    // ---------------------------------------------------------------

    readonly property bool hovering: clockArea.containsMouse || timerList.hoveredRows > 0
        || addArea.containsMouse || btnLess.hovering || btnMore.hovering || btnStart.hovering
        || presetRow.hoveredChips > 0

    function stepDraft(minutes) {
        card.draftMinutes = Math.max(1, Math.min(card.maxMinutes, card.draftMinutes + minutes));
    }

    function startDraft() {
        TimerService.add(card.draftMinutes * 60);
        card.adding = false;
    }

    // ---------------------------------------------------------------
    // Zegar
    // ---------------------------------------------------------------

    Item {
        id: clockColumn

        transform: CascadeShift { step: 0; shown: card.active }
        x: card.wide ? 14 : 0
        width: card.wide ? card.clockColumnWidth : card.width
        height: card.height

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1

            // Na szerokiej karcie mniejszy: przy 30 px "20:12:44" zaczynał
            // się pod plusikiem w rogu (zmierzone zrzutem).
            RollingDigits {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatTime(card.date, card.timeFormat)
                color: "#f5f5f5"
                pixelSize: card.wide ? 26 : 30
                weight: Font.Light
                animated: card.rollingDigits
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: clockColumn.width
                elide: Text.ElideRight
                text: card.date.toLocaleDateString(Qt.locale(card.localeName), card.dateFormat)
                color: clockArea.containsMouse ? "#c8c8cc" : "#9a9aa2"
                font.pixelSize: 12
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }

        // Tylko przy KClock — bez niego klik nic by nie otworzył.
        MouseArea {
            id: clockArea
            anchors.fill: parent
            enabled: TimerService.available
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: TimerService.openApp()
        }
    }

    // ---------------------------------------------------------------
    // Minutniki
    // ---------------------------------------------------------------

    Item {
        anchors.left: clockColumn.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.top: parent.top
        anchors.topMargin: card.listTopMargin
        anchors.bottom: parent.bottom
        anchors.bottomMargin: card.listBottomMargin
        visible: card.hasTimers && !card.adding
        transform: CascadeShift { step: 1; shown: card.active }

        // Granica listy: patrz ConnectivityCard — bez tego kółko na końcu
        // listy przełączałoby kartę.
        WheelHandler {
            target: null
            enabled: timerList.contentHeight > timerList.height
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        }

        ListView {
            id: timerList

            // Licznik zamiast OR po delegatach — patrz ConnectivityCard.
            // Tu tym ważniejszy, że model to tablica z mostka, podmieniana przy
            // każdej zmianie stanu, więc delegaty giną po każdym kliknięciu.
            property int hoveredRows: 0

            anchors.fill: parent
            clip: true
            spacing: card.rowSpacing
            boundsBehavior: Flickable.StopAtBounds
            model: TimerService.timers

            delegate: Item {
                id: row

                required property var modelData
                readonly property var timer: modelData
                readonly property bool active: TimerService.isActive(timer)
                readonly property int secondsLeft: TimerService.remaining(timer)

                width: timerList.width
                height: card.rowHeight

                readonly property bool hot: btnToggle.hovering || btnReset.hovering || btnDismiss.hovering
                property bool counted: false
                onHotChanged: {
                    if (hot === counted) return;
                    counted = hot;
                    timerList.hoveredRows += hot ? 1 : -1;
                }
                // Delegat zniszczony w trakcie hovera zostawiłby licznik
                // zawyżony — a wtedy wyspa nigdy by się nie zwinęła.
                Component.onDestruction: if (counted) timerList.hoveredRows -= 1

                Text {
                    id: timeText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    text: row.timer.ringing ? "0:00" : TimerService.format(row.secondsLeft)
                    color: row.timer.ringing ? "#ff453a"
                         : row.timer.running ? "#ff9f0a"
                         : row.active ? "#f2f2f2" : "#c8c8cc"
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    // Cyfry o stałej szerokości: inaczej podpis obok drgałby
                    // przy każdej sekundzie.
                    font.features: { "tnum": 1 }
                    Behavior on color { ColorAnimation { duration: 160 } }
                }

                Text {
                    anchors.left: timeText.right
                    anchors.leftMargin: 8
                    anchors.right: buttons.left
                    anchors.rightMargin: 8
                    anchors.baseline: timeText.baseline
                    elide: Text.ElideRight
                    text: row.timer.ringing ? "Koniec · " + TimerService.caption(row.timer)
                                            : TimerService.caption(row.timer)
                    color: "#8e8e93"
                    font.pixelSize: 11
                }

                // Postęp pod czasem — tylko gdy minutnik ruszył.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: buttons.left
                    anchors.rightMargin: 8
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3
                    height: 2
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.1)
                    visible: row.active && !row.timer.ringing

                    Rectangle {
                        width: parent.width * (row.timer.length > 0 ? 1 - row.secondsLeft / row.timer.length : 0)
                        height: parent.height
                        radius: parent.radius
                        color: row.timer.running ? "#ff9f0a" : "#8e8e93"
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }

                Row {
                    id: buttons
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    IslandButton {
                        id: btnReset
                        kind: "refresh"
                        visible: row.active && !row.timer.ringing
                        onClicked: TimerService.reset(row.timer)
                    }

                    IslandButton {
                        id: btnToggle
                        kind: row.timer.running ? "pause" : "play"
                        visible: !row.timer.ringing
                        onClicked: TimerService.toggle(row.timer)
                    }

                    IslandButton {
                        id: btnDismiss
                        kind: "close"
                        visible: row.timer.ringing
                        accented: true
                        accent: "#ff453a"
                        onClicked: TimerService.dismiss(row.timer)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Nowy minutnik
    // ---------------------------------------------------------------

    // Plusik w lewym górnym rogu — prawy zajmują przyciski pierwszego
    // minutnika z listy. Bliżej rogu się nie da: wyspa ma tu promień 30
    // i róg kółka wchodziłby pod zaokrąglenie.
    Rectangle {
        id: addButton

        x: 12
        y: 10
        width: 22
        height: 22
        radius: 11
        antialiasing: true
        visible: card.canAdd
        color: Qt.rgba(1, 1, 1, addArea.containsMouse ? 0.16 : (card.adding ? 0.1 : 0))
        Behavior on color { ColorAnimation { duration: 140 } }

        IslandIcon {
            anchors.centerIn: parent
            kind: card.adding ? "close" : "plus"
            size: 15
            color: addArea.containsMouse || card.adding ? "#f2f2f2" : "#8e8e93"
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        // Nad zegarem: jego MouseArea (otwieranie KClock) jest deklarowana
        // wcześniej, więc ta leży wyżej i zabiera klik w samym rogu.
        MouseArea {
            id: addArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.adding = !card.adding
        }
    }

    Item {
        id: picker

        anchors.left: clockColumn.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.top: parent.top
        anchors.topMargin: card.listTopMargin
        anchors.bottom: parent.bottom
        anchors.bottomMargin: card.listBottomMargin
        visible: card.adding

        // Obrót sumowany do pełnego ząbka, jak głośność w AudioOutputChip —
        // touchpad przysyła drobne porcje i bez tego jedno machnięcie dawało
        // kilkadziesiąt kroków. Zdarzenie jest połykane, żeby nie przełączyło
        // karty.
        property real wheelAccum: 0

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const dy = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
                if (dy === 0) return;
                if ((picker.wheelAccum > 0) !== (dy > 0)) picker.wheelAccum = 0;
                picker.wheelAccum += dy;
                const step = (event.modifiers & Qt.ShiftModifier) ? card.wheelShiftStepMinutes : card.wheelStepMinutes;
                while (Math.abs(picker.wheelAccum) >= card.wheelNotch) {
                    card.stepDraft(picker.wheelAccum > 0 ? step : -step);
                    picker.wheelAccum += picker.wheelAccum > 0 ? -card.wheelNotch : card.wheelNotch;
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6

                // Strzałka w dół obrócona na boki — IslandIcon ma tylko "chevron".
                IslandButton {
                    id: btnLess
                    kind: "chevron"
                    rotation: 90
                    y: (btnStart.height - height) / 2
                    enabled: card.draftMinutes > 1
                    onClicked: card.stepDraft(-card.wheelStepMinutes)
                }

                // Z godzinami ("1:45:00") mniejsza czcionka — przy 26 px
                // tekst wchodził pod strzałki (zmierzone zrzutem).
                Text {
                    width: 104
                    height: btnStart.height
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: TimerService.format(card.draftMinutes * 60)
                    color: "#f5f5f5"
                    font.pixelSize: card.draftMinutes >= 60 ? 21 : 26
                    font.weight: Font.Light
                    font.features: { "tnum": 1 }
                }

                IslandButton {
                    id: btnMore
                    kind: "chevron"
                    rotation: -90
                    y: (btnStart.height - height) / 2
                    enabled: card.draftMinutes < card.maxMinutes
                    onClicked: card.stepDraft(card.wheelStepMinutes)
                }

                Item { width: 6; height: 1 }

                IslandButton {
                    id: btnStart
                    kind: "play"
                    big: true
                    accented: true
                    accent: "#ff9f0a"
                    onClicked: card.startDraft()
                }
            }

            Row {
                id: presetRow

                // Licznik jak w liście — chipy to Repeater.
                property int hoveredChips: 0

                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6

                Repeater {
                    model: card.presetMinutes

                    delegate: Rectangle {
                        id: chip

                        required property int modelData
                        readonly property bool picked: card.draftMinutes === modelData

                        width: chipText.implicitWidth + 18
                        height: 24
                        radius: 12
                        antialiasing: true
                        color: chip.picked ? Qt.rgba(1, 0.62, 0.04, 0.22)
                             : Qt.rgba(1, 1, 1, chipArea.containsMouse ? 0.16 : 0.07)
                        Behavior on color { ColorAnimation { duration: 140 } }

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData + " min"
                            color: chip.picked ? "#ff9f0a" : "#c8c8cc"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.draftMinutes = chip.modelData
                            property bool counted: false
                            onContainsMouseChanged: {
                                if (containsMouse === counted) return;
                                counted = containsMouse;
                                presetRow.hoveredChips += containsMouse ? 1 : -1;
                            }
                            Component.onDestruction: if (counted) presetRow.hoveredChips -= 1
                        }
                    }
                }
            }
        }
    }
}
