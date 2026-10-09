import QtQuick
import QtQuick.Shapes

// Korektor na całą wyspę: nagłówek z przełącznikiem, gotowe i własne
// ustawienia w przewijanym rzędzie, 10 suwaków pasm z krzywą odpowiedzi.
// Otwiera go klik w wizualizator na karcie muzyki; stan i dźwięk są
// w EqualizerService.
//
// Suwaki i chipy NIE mają hoverEnabled tam, gdzie to niepotrzebne: element
// z hoverem zabiera go podkładce wyspy (patrz DynamicIsland, hover z trzech
// źródeł) i musiałby trafić do `hovering`. Te, które go mają, są w nim
// policzone — chipy licznikiem, bo delegaty powstają i giną.
Item {
    id: panel

    property color accent: "#38d47a"
    signal closed()

    readonly property bool hovering: btnBack.hovering || eqSwitch.hovering
        || chipRow.hoveredChips > 0 || plusMouse.containsMouse

    readonly property bool on: EqualizerService.enabled && EqualizerService.available
    readonly property real maxGain: EqualizerService.maxGain

    // Kolumna pasma ma niecałkowitą szerokość (408 / 10), więc wszystko, co
    // ma stać ostro na pikselach (tor, gałka), zaokrąglamy osobno.
    readonly property real colWidth: graph.width / EqualizerService.bandCount
    // Gałka (14 px) nie może wyjść poza obszar na skrajnych wartościach.
    readonly property real knobPad: 8

    function centerX(i) { return (i + 0.5) * colWidth; }
    function yOf(db) {
        return knobPad + (maxGain - db) / (2 * maxGain) * (graph.height - 2 * knobPad);
    }
    function dbOf(y) {
        return maxGain - (y - knobPad) / (graph.height - 2 * knobPad) * 2 * maxGain;
    }
    function formatDb(db) {
        const v = Math.abs(db) < 0.05 ? 0 : db;
        return (v > 0 ? "+" : "") + (Number.isInteger(v) ? v : v.toFixed(1));
    }

    // Zaznaczony chip ma być widać — przy otwarciu panelu własne ustawienia
    // stoją na końcu rzędu, daleko poza krawędzią.
    function revealSelected() {
        const kids = chipRow.children;
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i];
            if (c.selected !== true) continue;
            const margin = 24;   // szerokość wygaszenia krawędzi
            const maxX = Math.max(0, chipFlick.contentWidth - chipFlick.width);
            if (c.x - margin < chipFlick.contentX)
                chipFlick.contentX = Math.max(0, c.x - margin);
            else if (c.x + c.width + margin > chipFlick.contentX + chipFlick.width)
                chipFlick.contentX = Math.min(maxX, c.x + c.width + margin - chipFlick.width);
            return;
        }
    }

    onVisibleChanged: if (visible) Qt.callLater(revealSelected)
    Connections {
        target: EqualizerService
        function onPresetKeyChanged() { Qt.callLater(panel.revealSelected); }
    }

    // ---- krzywa odpowiedzi ----
    // Suma filtrów dzwonowych według wzorów RBJ (biquad "peaking") przy
    // 48 kHz. LSP liczy filtr RLC trochę inaczej, więc to przybliżenie
    // kształtu, a nie pomiar — ale pokazuje to, czego same suwaki nie
    // pokażą: sąsiednie podbicia sumują się powyżej wartości suwaka.
    readonly property int curveSamples: 96

    function bellDb(f, f0, gain) {
        if (gain === 0) return 0;
        const fs = 48000;
        const A = Math.pow(10, gain / 40);
        const w0 = 2 * Math.PI * f0 / fs;
        const alpha = Math.sin(w0) / (2 * EqualizerService.bandQ);
        const cw = Math.cos(w0);
        const b0 = 1 + alpha * A, b1 = -2 * cw, b2 = 1 - alpha * A;
        const a0 = 1 + alpha / A, a1 = -2 * cw, a2 = 1 - alpha / A;
        const w = 2 * Math.PI * f / fs;
        const c1 = Math.cos(w), s1 = Math.sin(w), c2 = Math.cos(2 * w), s2 = Math.sin(2 * w);
        const nr = b0 + b1 * c1 + b2 * c2, ni = b1 * s1 + b2 * s2;
        const dr = a0 + a1 * c1 + a2 * c2, di = a1 * s1 + a2 * s2;
        return 10 * Math.log10((nr * nr + ni * ni) / (dr * dr + di * di));
    }

    // Oś x jest logarytmiczna i zgodna z kolumnami: środek kolumny i to
    // 31,25 Hz · 2^i, więc pasma (co oktawę) leżą dokładnie pod gałkami.
    readonly property var curve: {
        const bands = EqualizerService.bands;
        const freqs = EqualizerService.frequencies;
        const w = graph.width;
        const pts = [];
        if (w <= 0) return pts;
        for (let k = 0; k <= curveSamples; k++) {
            const x = w * k / curveSamples;
            const f = 31.25 * Math.pow(2, x / colWidth - 0.5);
            let db = 0;
            for (let i = 0; i < bands.length; i++) db += bellDb(f, freqs[i], bands[i]);
            pts.push(Qt.point(x, yOf(Math.max(-maxGain, Math.min(maxGain, db)))));
        }
        return pts;
    }
    // Wypełnienie między krzywą a linią 0 dB.
    readonly property var curveFill: curve.length === 0 ? []
        : [Qt.point(0, yOf(0))].concat(curve, [Qt.point(graph.width, yOf(0))])

    // ---- nagłówek ----
    Item {
        id: header

        x: 16
        y: 14
        width: parent.width - 32
        height: 30

        IslandButton {
            id: btnBack
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            kind: "back"
            onClicked: panel.closed()
        }

        Column {
            anchors.left: btnBack.right
            anchors.leftMargin: 11
            anchors.right: eqSwitch.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: "Korektor"
                color: "#f5f5f5"
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: !EqualizerService.available ? "Filtr nie wstał — czy jest lsp-plugins-lv2?"
                    : panel.on ? EqualizerService.presetName : "Wyłączony"
                color: !EqualizerService.available ? "#e5484d" : "#9a9aa2"
                font.pixelSize: 11
            }
        }

        // Przełącznik zawsze klikalny: przy niedostępnym filtrze włączenie
        // to ponowna próba (np. po doinstalowaniu wtyczek).
        IslandSwitch {
            id: eqSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: panel.on
            accent: panel.accent
            onToggled: EqualizerService.setEnabled(!panel.on)
        }
    }

    // ---- gotowe i własne ustawienia ----
    Flickable {
        id: chipFlick

        x: 16
        y: header.y + header.height + 10
        width: parent.width - 32
        height: 26
        contentWidth: chipRow.width
        contentHeight: height
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: chipRow

            spacing: 6
            // Licznik zamiast OR po delegatach — patrz komentarz na górze.
            property int hoveredChips: 0

            Repeater {
                model: EqualizerService.choices

                delegate: Rectangle {
                    id: chip

                    required property var modelData
                    readonly property bool selected: EqualizerService.presetKey === modelData.key
                    // Usuwanie tylko z zaznaczonego własnego — krzyżyk na każdym
                    // chipie zachęcałby do przypadkowych kliknięć.
                    readonly property bool deletable: modelData.custom && selected

                    width: label.implicitWidth + 24 + (deletable ? 16 : 0)
                    height: 26
                    radius: 13
                    antialiasing: true
                    color: selected ? (panel.on ? panel.accent : Qt.rgba(1, 1, 1, 0.3))
                        : Qt.rgba(1, 1, 1, chipMouse.containsMouse ? 0.16 : 0.08)
                    scale: chipMouse.pressed ? 0.94 : 1

                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                    Text {
                        id: label
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.name
                        color: chip.selected && panel.on ? "#0a0a0c" : "#e2e2e6"
                        font.pixelSize: 12
                        font.weight: chip.selected ? Font.DemiBold : Font.Normal
                    }

                    property bool counted: false
                    function syncHover() {
                        const now = chipMouse.containsMouse;
                        if (now === counted) return;
                        counted = now;
                        chipRow.hoveredChips += now ? 1 : -1;
                    }
                    // Delegat zniszczony pod kursorem (usunięty własny) zostawiłby
                    // licznik zawyżony, a wyspa nigdy by się nie zwinęła.
                    Component.onDestruction: if (counted) chipRow.hoveredChips -= 1

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: chip.syncHover()
                        onClicked: EqualizerService.selectPreset(chip.modelData.key)
                    }

                    // Krzyżyk deklarowany później, więc leży nad MouseArea chipa.
                    Item {
                        visible: chip.deletable
                        x: parent.width - 24
                        width: 22
                        height: parent.height

                        IslandIcon {
                            anchors.centerIn: parent
                            kind: "close"
                            size: 12
                            color: delMouse.pressed ? "#000000" : (panel.on ? "#0a0a0c" : "#e2e2e6")
                        }

                        MouseArea {
                            id: delMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: EqualizerService.deleteCustom(chip.modelData.key)
                        }
                    }
                }
            }

            // Zapis bieżących pasm jako nowe własne ustawienie.
            Rectangle {
                width: 26
                height: 26
                radius: 13
                antialiasing: true
                visible: EqualizerService.canSaveCustom
                color: Qt.rgba(1, 1, 1, plusMouse.containsMouse ? 0.16 : 0.08)
                scale: plusMouse.pressed ? 0.9 : 1

                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                IslandIcon {
                    anchors.centerIn: parent
                    kind: "plus"
                    size: 14
                    color: "#e2e2e6"
                }

                MouseArea {
                    id: plusMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Nowy chip od razu jest zaznaczony, więc przewinięcie do
                    // niego załatwia revealSelected.
                    onClicked: EqualizerService.saveCustom()
                }
            }
        }
    }

    // Wygaszenie krawędzi rzędu: ucięty chip wygląda wtedy na "jest
    // więcej", a nie na błąd układu. Kolor tła wyspy.
    Rectangle {
        x: chipFlick.x
        y: chipFlick.y
        width: 24
        height: chipFlick.height
        visible: !chipFlick.atXBeginning
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#0a0a0c" }
            GradientStop { position: 1; color: Qt.rgba(0.04, 0.04, 0.05, 0) }
        }
    }

    Rectangle {
        x: chipFlick.x + chipFlick.width - width
        y: chipFlick.y
        width: 24
        height: chipFlick.height
        visible: !chipFlick.atXEnd
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0.04, 0.04, 0.05, 0) }
            GradientStop { position: 1; color: "#0a0a0c" }
        }
    }

    // ---- pasma ----
    Item {
        id: graph

        x: 16
        y: chipFlick.y + chipFlick.height + 12
        width: parent.width - 32
        height: parent.height - y - 14 - labels.height - 4

        opacity: panel.on ? 1 : 0.45
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Siatka: 0 dB wyraźnie, ±6 dB ledwo.
        Repeater {
            model: [panel.maxGain / 2, 0, -panel.maxGain / 2]

            delegate: Rectangle {
                required property real modelData
                x: 0
                y: Math.round(panel.yOf(modelData))
                width: graph.width
                height: 1
                color: Qt.rgba(1, 1, 1, modelData === 0 ? 0.14 : 0.05)
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                fillColor: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.16)
                PathPolyline { path: panel.curveFill }
            }

            ShapePath {
                strokeColor: panel.accent
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline { path: panel.curve }
            }
        }

        Repeater {
            model: EqualizerService.bandCount

            delegate: Item {
                id: band

                required property int index
                readonly property real db: EqualizerService.bands[index] ?? 0
                readonly property real cx: panel.centerX(index)
                readonly property real knobY: panel.yOf(db)

                x: 0
                width: graph.width
                height: graph.height
                // Dymek z wartością wystaje na sąsiednie kolumny.
                z: drag.pressed ? 2 : 0

                // Tor
                Rectangle {
                    x: Math.round(band.cx - 1)
                    y: panel.knobPad
                    width: 2
                    height: graph.height - 2 * panel.knobPad
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // Wypełnienie od 0 dB do gałki
                Rectangle {
                    readonly property real y0: panel.yOf(0)
                    x: Math.round(band.cx - 2)
                    y: Math.min(y0, band.knobY)
                    width: 4
                    height: Math.abs(band.knobY - y0)
                    radius: 2
                    antialiasing: true
                    color: panel.accent
                    opacity: 0.85
                }

                Rectangle {
                    id: knob
                    x: Math.round(band.cx - 7)
                    y: band.knobY - 7
                    width: 14
                    height: 14
                    radius: 7
                    antialiasing: true
                    color: "#f2f2f2"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.25)
                    scale: drag.pressed ? 1.2 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                }

                // Wartość przy przeciąganiu. Przy gałce na górze — pod nią,
                // inaczej wchodziłaby na rząd ustawień.
                Rectangle {
                    visible: drag.pressed
                    width: valueText.implicitWidth + 12
                    height: 18
                    radius: 9
                    antialiasing: true
                    x: Math.round(band.cx - width / 2)
                    y: knob.y > 24 ? knob.y - height - 6 : knob.y + knob.height + 6
                    color: "#f2f2f2"

                    Text {
                        id: valueText
                        anchors.centerIn: parent
                        text: panel.formatDb(band.db) + " dB"
                        color: "#0a0a0c"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }

                // Obszar chwytu = cała kolumna, żeby nie trzeba było celować
                // w 14 px gałki. Klik ustawia wartość tam, gdzie kliknięto,
                // podwójny wraca do 0 dB. preventStealing: przeciągnięcie
                // wychodzące poza kolumnę dalej należy do tego suwaka.
                MouseArea {
                    id: drag

                    x: Math.round(band.cx - panel.colWidth / 2)
                    width: Math.round(panel.colWidth)
                    height: parent.height
                    preventStealing: true
                    cursorShape: Qt.SizeVerCursor

                    function set(y) { EqualizerService.setBand(band.index, panel.dbOf(y)); }

                    onPressed: mouse => set(mouse.y)
                    onPositionChanged: mouse => { if (pressed) set(mouse.y); }
                    onDoubleClicked: EqualizerService.setBand(band.index, 0)

                    // Kółko: 1 dB na ząbek, sumowane jak w pigułce głośności
                    // (touchpad przysyła drobne porcje). Wyspa ma swoje kółko
                    // wyłączone na czas korektora, więc nic nie przecieka.
                    WheelHandler {
                        target: null
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        property real accum: 0

                        onWheel: event => {
                            const dy = event.angleDelta.y;
                            if (dy === 0) return;
                            if ((accum > 0) !== (dy > 0)) accum = 0;
                            accum += dy;
                            while (Math.abs(accum) >= 120) {
                                EqualizerService.setBand(band.index, band.db + (accum > 0 ? 1 : -1));
                                accum += accum > 0 ? -120 : 120;
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- częstotliwości ----
    Item {
        id: labels

        x: graph.x
        y: graph.y + graph.height + 4
        width: graph.width
        height: 14

        Repeater {
            model: EqualizerService.labels

            delegate: Text {
                required property int index
                required property string modelData
                x: Math.round(panel.centerX(index) - width / 2)
                text: modelData
                color: "#78787f"
                font.pixelSize: 10
            }
        }
    }
}
