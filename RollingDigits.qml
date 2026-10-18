import QtQuick

// Zegar, w którym przewija się tylko zmieniona cyfra, jak w liczniku:
// nowa wjeżdża od dołu, stara odjeżdża w górę. Każdy znak ma własną
// komórkę przyciętą do wysokości wiersza.
//
// Cyfry tabelaryczne (tnum) są tu konieczne, nie ozdobne: przy cyfrach
// proporcjonalnych "1" jest węższa od "0" i przejście 10 -> 11 zmieniałoby
// szerokość całego zegara w trakcie animacji — reszta wiersza drgałaby.
Row {
    id: digits

    property string text: ""
    property color color: "#f2f2f2"
    property int pixelSize: 14
    property int weight: Font.DemiBold
    property bool animated: true
    property int duration: 340

    Repeater {
        // Zmiana długości (inny format w konfiguracji) przebudowuje komórki,
        // a nowe startują bez animacji — patrz Component.onCompleted.
        model: digits.text.length

        delegate: Item {
            id: cell

            required property int index
            readonly property string ch: digits.text.charAt(index)

            property string shown: ""
            property string previous: ""
            property real t: 1

            width: current.implicitWidth
            height: current.implicitHeight
            clip: t < 1

            Component.onCompleted: shown = ch
            onChChanged: {
                if (!digits.animated || shown === "") {
                    shown = ch;
                    return;
                }
                previous = shown;
                shown = ch;
                anim.restart();
            }

            NumberAnimation {
                id: anim
                target: cell
                property: "t"
                from: 0
                to: 1
                duration: digits.duration
                easing.type: Easing.OutCubic
            }

            Text {
                id: current
                y: (1 - cell.t) * cell.height
                text: cell.shown
                color: digits.color
                font.pixelSize: digits.pixelSize
                font.weight: digits.weight
                font.features: { "tnum": 1 }
            }

            Text {
                y: -cell.t * cell.height
                opacity: 1 - cell.t
                visible: cell.t < 1
                text: cell.previous
                color: digits.color
                font.pixelSize: digits.pixelSize
                font.weight: digits.weight
                font.features: { "tnum": 1 }
            }
        }
    }
}
