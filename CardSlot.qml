import QtQuick

// Slot karuzeli kart: stała szerokość (największa karta), zawartość
// wyśrodkowana przez właściciela. Do tego głębia przy przewijaniu kółkiem —
// karta odjeżdżająca od środka maleje i przygasa, wjeżdżająca rośnie.
//
// Odległość liczy się z `stripOffset` paska, czyli z tej samej animowanej
// wartości, która przesuwa karty. W spoczynku aktywna karta ma odległość 0,
// a reszta ≥ 1 i i tak leży poza wyspą — efekt nic nie kosztuje, póki nikt
// nie przewija. Kartę ustawioną przez wyspę (powiadomienie) pasek stawia
// bez animacji, więc i tu nic się nie dzieje.
Item {
    id: slot

    property int card: -1
    property int slotWidth: 440
    property real stripOffset: 0
    property bool depth: true
    // Ta karta jest teraz na wyspie (rozwiniętej, bez nakładki) — od tego
    // startuje wejście kaskadowe treści.
    property bool current: false

    // Skala i przygaszenie przy odległości jednego slotu. Skala zostawia
    // kartę czytelną; mocniej zmniejszona wyglądała, jakby odpadała.
    property real minScale: 0.9
    property real minOpacity: 0.35

    readonly property real distance: Math.min(1, Math.abs(x - stripOffset) / slotWidth)

    x: card * slotWidth
    width: slotWidth
    height: parent ? parent.height : 0
    visible: card >= 0

    scale: depth ? 1 - (1 - minScale) * distance : 1
    opacity: depth ? 1 - (1 - minOpacity) * distance : 1
}
