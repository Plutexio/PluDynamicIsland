import QtQuick

// Fala wokół wyspy przy zdarzeniu (powiadomienie, AirPodsy, minutnik…):
// dwa pierścienie rozchodzą się od krawędzi i gasną, jak "ping" w iOS.
// Jednorazowa — gra po `play()` i staje, więc nie podlega loopAnimations.
//
// Pierścień idzie za ANIMOWANĄ geometrią celu, nie za migawką z chwili
// startu: powiadomienie rozwija wyspę w tym samym momencie, a pierścień
// liczony od pigułki zostałby pod rosnącą wyspą i nikt by go nie zobaczył.
// Rodzeństwo wyspy (ten sam rodzic), więc x/y celu są w tym samym układzie.
Item {
    id: ripple

    property Item target
    property bool enabled: IslandConfig.effects.ripple
    property real spread: 22       // o ile pierścień odchodzi od krawędzi, px
    property int duration: 900
    property int ringDelayMs: 170
    property real startOpacity: 0.55
    property color color: "#f2f2f2"

    // Przez tyle ms od startu fala milczy: przeładowanie na żywo w trakcie
    // rozmowy na Discordzie (mostek zgłasza inVoice od nowa) albo przy
    // podłączonej ładowarce dawałoby falę przy każdej edycji pliku.
    property int startupGraceMs: 4000
    property double startedAt: 0
    Component.onCompleted: startedAt = Date.now()

    signal fired()

    function play(c) {
        if (!enabled || target === null) return;
        if (Date.now() - startedAt < startupGraceMs) return;
        ripple.color = c;
        ripple.fired();
    }

    Repeater {
        model: 2

        delegate: Rectangle {
            id: ring

            required property int index
            property real p: 0
            readonly property real s: ripple.spread * p

            x: ripple.target ? ripple.target.x - s : 0
            y: ripple.target ? ripple.target.y - s : 0
            width: ripple.target ? ripple.target.width + 2 * s : 0
            height: ripple.target ? ripple.target.height + 2 * s : 0
            // Promień rośnie razem z odległością — pierścień zostaje
            // równoległy do krawędzi (pigułka zostaje pigułką).
            radius: ripple.target ? Math.min(ripple.target.radius + s, height / 2) : 0

            color: "transparent"
            border.width: 2 - p
            border.color: ripple.color
            antialiasing: true

            visible: p > 0 && p < 1
            opacity: ripple.startOpacity * (1 - p) * (index === 0 ? 1 : 0.6)

            Connections {
                target: ripple
                function onFired() { anim.restart(); }
            }

            SequentialAnimation {
                id: anim
                PauseAnimation { duration: ring.index * ripple.ringDelayMs }
                NumberAnimation {
                    target: ring
                    property: "p"
                    from: 0.001
                    to: 1
                    duration: ripple.duration
                    easing.type: Easing.OutCubic
                }
                PropertyAction { target: ring; property: "p"; value: 0 }
            }
        }
    }
}
