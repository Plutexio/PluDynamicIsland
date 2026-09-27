import QtQuick

// Zamiennik ClippingRectangle z Quickshell.Widgets: ten sam shader, inna droga
// podania zawartości.
//
// ClippingRectangle zbiera zawartość samodzielnym ShaderEffectSource z włączonym
// wygładzaniem, którego nie da się wyłączyć z zewnątrz. Przy ułamkowym
// skalowaniu (DP-1: 1,7) tekstura nie leży 1:1 na pikselach ekranu i filtr
// liniowy rozmywał czcionkę w wyspie. Zmierzone na zrzucie z natywnej
// rozdzielczości (spectacle -m): 671 półszarych pikseli na krawędziach glifów
// przy ClippingRectangle, 338 przy zwykłym Rectangle, ~290 tutaj. MultiEffect
// z maską rozmywa tak samo jak ClippingRectangle.
//
// API jak w ClippingRectangle, w zakresie, którego używa wyspa.
Item {
    id: root

    // Przy nieprzezroczystej ramce nic nie zmienia (tak jak w oryginale).
    property bool contentUnderBorder: false
    property bool contentInsideBorder: !contentUnderBorder
    property alias antialiasing: rectangle.antialiasing
    property color color: "white"
    readonly property Pen border: Pen {}
    property alias radius: rectangle.radius

    default property alias data: contentItem.data
    property alias children: contentItem.children
    readonly property alias contentItem: contentItem

    component Pen: QtObject {
        property real width: 0
        property color color: "black"
        property bool pixelAligned: true
    }

    // Maska kształtu dla shadera: czerwony kanał = wnętrze, zielony = ramka.
    Rectangle {
        id: rectangle
        anchors.fill: parent
        color: "#ffff0000"
        border.color: "#ff00ff00"
        border.width: root.border.width
        border.pixelAligned: root.border.pixelAligned
        layer.enabled: true
        visible: false
    }

    Item {
        anchors.fill: parent

        // Bez wygładzania, celowo. Tekstura ma ceil(168 × 1,7) = 286 px na 285,6 px
        // ekranu, więc nie leży 1:1 na pikselach i filtr liniowy miesza sąsiednie
        // teksele — to właśnie rozmywało tekst (smooth jest domyślnie włączone
        // w ShaderEffectSource ClippingRectangle). Najbliższy sąsiad przesuwa się
        // o ułamek teksla na całej szerokości, więc nie gubi kolumn.
        layer.enabled: true
        layer.smooth: false
        layer.samplerName: "content"
        layer.effect: ShaderEffect {
            fragmentShader: `qrc:/Quickshell/Widgets/shaders/cliprect${root.contentUnderBorder ? "-ub" : ""}.frag.qsb`
            property Rectangle rect: rectangle
            property color backgroundColor: root.color
            property color borderColor: root.border.color
        }

        Item {
            id: contentItem
            anchors.fill: parent
            anchors.margins: root.contentInsideBorder ? root.border.width : 0
        }
    }
}
