import QtQuick
import QtQuick.Shapes

// Mała pigułka obok wyspy (rozmowa, udostępnianie, minutnik), która przy
// pojawieniu się wypływa ze swojego źródła jak kropla: startuje jako kółko
// schowane pod krawędzią źródła, rośnie do pełnej szerokości i odjeżdża
// trochę ZA miejsce spoczynku, ciągnąc za sobą przewężającą się szyjkę
// (`bridge`). Szyjka pęka, a pigułka wraca na miejsce jak puszczona gumka.
//
// Źródłem jest wyspa albo sąsiednia pigułka (minutnik za udostępnianiem).
// `originEdge` to krawędź źródła po stronie pigułki, `toRight` — w którą
// stronę pigułka odpływa. Właściciel ustawia `implicitWidth` (pełna
// szerokość) i wkłada treść; pozycji nie ustawia, liczy ją ta pigułka.
//
// Pigułka leży POD wyspą (z ujemne u właściciela): wypływa spod jej
// krawędzi, a nie przez nią. Chowanie zostaje twarde (visible: shown) —
// przy rozwijaniu pigułka ma zniknąć od razu, żeby nie wystawała spod
// rosnącej wyspy.
Rectangle {
    id: pill

    property bool shown: false
    property bool liquid: IslandConfig.effects.liquidPills
    property bool toRight: true
    property real originEdge: 0
    property real gap: 8
    // Źródło jeszcze się kurczy (wyspa wraca z rozwinięcia albo zerknięcia):
    // pigułka czeka, aż jego krawędź dojedzie na miejsce, inaczej
    // wypłynęłaby z krawędzi, która zaraz odjedzie.
    property bool originBusy: false
    property int originWaitMs: 300
    // Dwie fazy: wypłynięcie z rozciągnięciem szyjki (flowMs), potem po jej
    // pęknięciu sprężysty powrót na miejsce (settleMs, z chybotaniem).
    property int flowMs: 560
    property int settleMs: 700
    // Jak daleko pigułka odjeżdża, ciągnąc szyjkę (odstęp od źródła, px).
    // Większy od odstępu spoczynkowego: przy dawnym zakresie 0–7 px szyjka
    // żyła ułamek sekundy i prawie jej nie było widać.
    property real stretchGap: Math.max(16, gap * 2.2)

    default property alias content: body.data

    // Postęp wypływania: 0 = kropla pod krawędzią źródła, 1 = na miejscu,
    // sepStretch = najdalej, przy rozciągniętej szyjce. Szerokość bierze
    // wartość przyciętą, więc za miejscem spoczynku pigułka już nie rośnie.
    property real sep: 1
    readonly property real grow: Math.max(0, Math.min(1, sep))
    readonly property real sepStretch: (h + stretchGap) / (gap + h)

    // Szyjka pękła w tym wypływaniu. Bez zatrzasku wracałaby przy
    // chybotaniu, gdy pigułka podjedzie znów bliżej źródła.
    property bool snapped: true

    readonly property real h: height
    width: h + (implicitWidth - h) * grow
    x: toRight ? originEdge - h + sep * (gap + h)
               : originEdge + h - sep * (gap + h) - width

    radius: height / 2
    color: "#0a0a0c"
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    visible: shown
    opacity: shown ? 1 : 0
    // Bez cieczy zostaje dawne wejście: lekkie powiększenie od strony wyspy.
    scale: shown || liquid ? 1 : 0.9
    transformOrigin: toRight ? Item.Left : Item.Right

    // Kropla jest kryjąca od pierwszej klatki — i tak wypływa spod wyspy.
    // Wygaszana przez 220 ms była na tle półprzezroczysta i szara, przez co
    // całe wypływanie ginęło (widać na zrzutach).
    Behavior on opacity {
        enabled: !pill.liquid
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
    }

    onShownChanged: {
        flow.stop();
        if (shown && liquid) {
            sep = 0;
            snapped = false;
            wait.duration = originBusy ? originWaitMs : 0;
            flow.start();
        } else {
            sep = 1;
            snapped = true;
        }
    }

    SequentialAnimation {
        id: flow
        PauseAnimation { id: wait }
        // Wypłynięcie: szybko spod krawędzi, potem coraz wolniej — szyjka
        // rozciąga się na końcu tej fazy, gdzie ruch zwalnia, więc widać ją
        // najdłużej tuż przed pęknięciem.
        NumberAnimation {
            target: pill
            property: "sep"
            to: pill.sepStretch
            duration: pill.flowMs
            easing.type: Easing.OutCubic
        }
        // Po pęknięciu pigułka wraca na miejsce jak puszczona gumka.
        NumberAnimation {
            target: pill
            property: "sep"
            to: 1
            duration: pill.settleMs
            easing.type: Easing.OutElastic
            easing.amplitude: 1
            easing.period: 0.45
        }
        ScriptAction { script: pill.snapped = true }
    }

    // Treść wchodzi pod koniec drogi, gdy pigułka ma już prawie pełną
    // szerokość — wcześniej wystawałaby poza zaokrąglone końce.
    Item {
        id: body
        anchors.fill: parent
        opacity: Math.max(0, Math.min(1, (pill.sep - 0.7) / 0.3))
    }

    // ---- szyjka między źródłem a pigułką ----
    // Od środka zaokrąglenia źródła do środka zaokrąglenia pigułki, pod
    // oboma (z: -1 względem pigułki, a pigułka i tak leży pod wyspą), więc
    // widać tylko część między ich łukami. Póki pigułka zachodzi na źródło,
    // wypełnia wcięcie między dwoma łukami i oba kształty wyglądają na
    // jedną kroplę. Potem górna i dolna krawędź wklęsają, aż przy odstępie
    // `breakGap` (tuż przed największym rozciągnięciem) szyjka ma zerową
    // grubość i pęka — na dobre, do następnego wypływania (`snapped`).
    //
    // Ugięcie idzie za odstępem w px, nie za postępem animacji: przy progu
    // z postępu (0,72) szyjka pękała, zanim pigułka w ogóle wyjechała spod
    // źródła (szczelina otwiera się dopiero przy h / (gap + h) ≈ 0,81) —
    // zmierzone zrzutem z animacją spowolnioną do 8 s, szyjki nie było widać.
    Shape {
        id: bridge

        readonly property real originCap: (pill.toRight ? pill.originEdge - pill.h / 2
                                                        : pill.originEdge + pill.h / 2) - pill.x
        readonly property real pillCap: pill.toRight ? pill.h / 2 : pill.width - pill.h / 2
        // Odstęp między krawędzią źródła a bliższą krawędzią pigułki. Pęka
        // przed odstępem spoczynkowym, więc w spoczynku szyjki nie ma.
        readonly property real gapPx: pill.toRight ? pill.x - pill.originEdge
                                                   : pill.originEdge - (pill.x + pill.width)
        // Pęka tuż przed największym rozciągnięciem.
        readonly property real breakGap: pill.stretchGap - 2
        // Ugięcie w połowie szyjki. Punkt kontrolny krzywej kwadratowej leży
        // dwa razy głębiej niż jej środek. Potęga > 1: szyjka długo trzyma
        // grubość i cienieje gwałtownie dopiero przed pęknięciem — przy
        // liniowym ugięciu robiła się nitką już w połowie drogi.
        readonly property real stretch: Math.max(0, Math.min(1, gapPx / breakGap))
        readonly property real pinch: pill.h / 2 * Math.pow(stretch, 1.8)

        onStretchChanged: if (stretch >= 1) pill.snapped = true

        z: -1
        x: Math.min(originCap, pillCap)
        width: Math.abs(pillCap - originCap)
        height: pill.h
        visible: pill.liquid && !pill.snapped && pill.sep > 0.01 && gapPx < breakGap
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: pill.color
            strokeColor: "transparent"
            strokeWidth: 0

            startX: 0
            startY: 0
            PathQuad { x: bridge.width; y: 0; controlX: bridge.width / 2; controlY: 2 * bridge.pinch }
            PathLine { x: bridge.width; y: bridge.height }
            PathQuad { x: 0; y: bridge.height; controlX: bridge.width / 2; controlY: bridge.height - 2 * bridge.pinch }
            PathLine { x: 0; y: 0 }
        }
    }
}
