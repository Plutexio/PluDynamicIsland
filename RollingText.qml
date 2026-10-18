import QtQuick

// Tekst, który przy zmianie wjeżdża od dołu, a stary odjeżdża w górę —
// tytuł i wykonawca przy zmianie utworu. Przycięty do własnej wysokości
// (prostokątnie, ale tekst nie ma zaokrąglonych rogów), więc nie najeżdża
// na sąsiednie wiersze karty.
//
// API jak zwykłego Text w zakresie, którego używa karta muzyki. Szerokość
// ustawia właściciel (Layout.fillWidth), a elide działa na obu warstwach.
Item {
    id: rolling

    property string text: ""
    property color color: "#f5f5f5"
    property font font
    property int elide: Text.ElideRight
    property bool animated: true
    property int duration: 380

    implicitWidth: current.implicitWidth
    implicitHeight: current.implicitHeight
    clip: t < 1

    // Pierwsza wartość bez animacji, potem każda zmiana jedzie.
    property string shown: ""
    property string previous: ""
    property real t: 1

    Component.onCompleted: shown = text
    onTextChanged: {
        if (!animated || shown === "") {
            shown = text;
            return;
        }
        previous = shown;
        shown = text;
        anim.restart();
    }

    NumberAnimation {
        id: anim
        target: rolling
        property: "t"
        from: 0
        to: 1
        duration: rolling.duration
        easing.type: Easing.OutCubic
    }

    Text {
        id: current
        width: rolling.width
        y: (1 - rolling.t) * rolling.height
        opacity: rolling.t
        text: rolling.shown
        color: rolling.color
        font: rolling.font
        elide: rolling.elide
    }

    Text {
        width: rolling.width
        y: -rolling.t * rolling.height
        opacity: 1 - rolling.t
        visible: rolling.t < 1
        text: rolling.previous
        color: rolling.color
        font: rolling.font
        elide: rolling.elide
    }
}
