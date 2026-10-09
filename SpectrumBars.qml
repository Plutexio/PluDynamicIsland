import QtQuick

// Słupki widma z cavy. Jeden komponent dla zwiniętej pigułki i dla karty
// muzyki — różnią się tylko skalą, a kolor (pas okładki, akcent, szarość
// na pauzie) ma być w obu identyczny.
Row {
    id: bars

    property real barWidth: 2
    property real minBarHeight: 3      // w ciszy zostaje czytelna kreska, a nie znikające słupki
    property real maxBarHeight: 16

    property bool playing: false
    property var colors: []            // kolor słupka z jego pasa okładki; brak = accent
    property color accent: "#38d47a"
    property int colorFadeMs: 450
    property int smoothingMs: 28

    spacing: 2
    height: maxBarHeight

    Repeater {
        model: CavaService.barCount

        delegate: Rectangle {
            required property int index
            readonly property real level: CavaService.levels[index] ?? 0

            width: bars.barWidth
            radius: bars.barWidth / 2
            antialiasing: true
            color: !bars.playing ? "#4a4a4f"
                : bars.colors[index] !== undefined ? bars.colors[index] : bars.accent

            Behavior on color { ColorAnimation { duration: bars.colorFadeMs } }

            height: bars.minBarHeight + level * (bars.maxBarHeight - bars.minBarHeight)
            // Row ustawia tylko x, więc pionowe wyśrodkowanie robimy
            // sami — anchors wewnątrz positionera potrafią się gryźć.
            y: (bars.height - height) / 2

            // Poniżej 60 fps dogładzanie trwałoby prawie cały odstęp
            // między klatkami i wyspa rysowałaby dalej co vsync —
            // obniżenie framerate nic by nie dało.
            Behavior on height {
                enabled: CavaService.framerate >= 60
                NumberAnimation {
                    duration: bars.smoothingMs
                    easing.type: Easing.OutQuad
                }
            }
        }
    }
}
