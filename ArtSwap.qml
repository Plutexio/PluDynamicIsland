import QtQuick

// Okładka z przejściem przy zmianie utworu. Dwa obrazki na zmianę: nowy
// wczytuje się w tle, a przejście startuje dopiero, gdy jest gotowy —
// inaczej między okładkami mignąłby pusty kwadrat.
//
// Dwa tryby: przenikanie z lekkim przybliżeniem (domyślnie) i obrót wokół
// osi pionowej (`flip`). Obrót musi kręcić całym zaokrąglonym kontenerem,
// nie samym obrazkiem — obrazek obracany wewnątrz płaskiego przycięcia
// wyglądałby jak przesuwany. Dlatego komponent tylko wystawia `flipAngle`,
// a właściciel wstawia go do własnego `transform`.
Item {
    id: swap

    property string source: ""
    property size sourceSize: Qt.size(64, 64)
    property int fillMode: Image.PreserveAspectCrop
    property bool animated: true
    property bool flip: false
    property int duration: flip ? 560 : 420

    // Przednia okładka jest wczytana — na nią czekają placeholder i klik.
    readonly property bool ready: front.status === Image.Ready && frontKey !== ""
    // Kąt dla Rotation właściciela: stara okładka obraca się do krawędzi
    // (0 -> 90), w połowie podmiana, nowa wraca z drugiej strony (-90 -> 0).
    readonly property real flipAngle: flip && t < 1 ? (t < 0.5 ? t * 180 : (t - 1) * 180) : 0

    property bool aFront: true
    readonly property Image front: aFront ? imgA : imgB
    readonly property Image back: aFront ? imgB : imgA

    // Adres, o który poproszono każdą warstwę. Porównujemy TEN tekst, nie
    // Image.source: url po drodze się normalizuje ("%20" wraca jako spacja,
    // zmierzone) i dla takiej okładki z MPRIS porównanie nie trafiało nigdy —
    // nowa okładka nie była uznawana za gotową i zostawała poprzednia.
    property string keyA: ""
    property string keyB: ""
    readonly property string frontKey: aFront ? keyA : keyB
    readonly property string backKey: aFront ? keyB : keyA

    // Postęp przejścia, 1 = spoczynek.
    property real t: 1

    onSourceChanged: load()
    Component.onCompleted: load()

    function setLayer(img, key) {
        if (img === imgA) swap.keyA = key;
        else swap.keyB = key;
        img.source = key;
    }

    function load() {
        if (swap.source === "") {
            anim.stop();
            swap.t = 1;
            swap.setLayer(imgA, "");
            swap.setLayer(imgB, "");
            return;
        }
        if (swap.frontKey === swap.source) return;
        // W trakcie przejścia tylna warstwa to STARA okładka, która jest
        // właśnie na ekranie — podmiana zgasiłaby ją w pół obrotu, a koniec
        // przejścia (onFinished czyści tylną) skasowałby nową, jeszcze
        // wczytywaną. Przy szybkim przełączaniu utworów zostawała wtedy
        // poprzednia okładka (zmierzone: okładka z sieci ładująca się dłużej
        // niż reszta obrotu). Nowa poczeka; onFinished woła load() jeszcze raz.
        if (anim.running) return;
        const img = swap.back;
        if (swap.backKey !== swap.source) swap.setLayer(img, swap.source);
        // Okładka z bufora bywa gotowa od razu. statusChanged przychodzi
        // wtedy JESZCZE W TRAKCIE przypisania i sam woła swapNow — `img`
        // przestaje być tylną warstwą. Bez tego sprawdzenia drugi swapNow
        // zamieniał warstwy z powrotem: na wierzch wracała stara okładka,
        // koniec obrotu kasował nową, load() robił to samo od nowa i obrót
        // kręcił się w kółko (zmierzone przy szybkim skakaniu między dwiema
        // okładkami, które już raz były na ekranie).
        if (img === swap.back && img.status === Image.Ready) swap.swapNow();
    }

    function swapNow() {
        // Pierwsza okładka (albo okładka po pustej) pojawia się bez przejścia —
        // nie ma czego obracać.
        const instant = !swap.animated || swap.front.status !== Image.Ready || swap.frontKey === "";
        swap.aFront = !swap.aFront;
        anim.stop();
        if (instant) {
            swap.t = 1;
            swap.setLayer(swap.back, "");
        } else {
            anim.restart();
        }
    }

    NumberAnimation {
        id: anim
        target: swap
        property: "t"
        from: 0
        to: 1
        duration: swap.duration
        easing.type: swap.flip ? Easing.InOutQuad : Easing.OutCubic
        // Stara okładka nie jest już potrzebna — zwalniamy pamięć. Potem
        // ewentualna zmiana, która przyszła w trakcie przejścia.
        onFinished: {
            swap.setLayer(swap.back, "");
            swap.load();
        }
    }

    component Slot: Image {
        anchors.fill: parent
        fillMode: swap.fillMode
        asynchronous: true
        cache: true
        sourceSize: swap.sourceSize
        smooth: true
    }

    Slot {
        id: imgA
        z: swap.aFront ? 1 : 0
        onStatusChanged: if (status === Image.Ready && imgA === swap.back && swap.keyA === swap.source) swap.swapNow()
    }

    Slot {
        id: imgB
        z: swap.aFront ? 0 : 1
        onStatusChanged: if (status === Image.Ready && imgB === swap.back && swap.keyB === swap.source) swap.swapNow()
    }

    // Przednia wchodzi nad tylną, tylna stoi pod spodem w pełnej jasności —
    // przy przenikaniu obu naraz środek przejścia byłby ciemniejszy.
    states: [
        State {
            when: swap.flip
            PropertyChanges { imgA.opacity: swap.aFront === (swap.t >= 0.5) ? 1 : 0 }
            PropertyChanges { imgB.opacity: swap.aFront !== (swap.t >= 0.5) ? 1 : 0 }
        },
        State {
            when: !swap.flip
            PropertyChanges { imgA.opacity: swap.aFront ? swap.t : 1 }
            PropertyChanges { imgB.opacity: swap.aFront ? 1 : swap.t }
            PropertyChanges { imgA.scale: swap.aFront ? 1.08 - 0.08 * swap.t : 1 }
            PropertyChanges { imgB.scale: swap.aFront ? 1 : 1.08 - 0.08 * swap.t }
        }
    ]
}
