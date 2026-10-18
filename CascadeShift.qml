import QtQuick

// Wejście kaskadowe: przesunięcie, które po pokazaniu karty wraca na
// miejsce z opóźnieniem zależnym od `step`. Kilka bloków karty z kolejnymi
// numerami wpływa więc po kolei, od lewej albo od góry.
//
// To transformacja, nie opacity ani y: bloki kart mają już własne
// powiązania opacity (np. okładka chowa się na czas podglądu), a y ustawiają
// layouty. Translate niczego nie przestawia w układzie i niczego nie
// nadpisuje. Wygaszanie zostaje przy pasku kart (cardStrip.opacity) —
// przesunięte bloki wchodzą razem z nim, a te z większym `step` wyraźnie
// później.
//
// Użycie: `transform: CascadeShift { step: 1; shown: slot.current }`.
Translate {
    id: shift

    property int step: 0
    property bool shown: false
    property bool enabled: IslandConfig.effects.cascade
    property int stepMs: 55
    property int duration: 460
    property real distance: 12

    property real progress: 1
    y: (1 - progress) * distance

    onShownChanged: {
        anim.stop();
        if (shown && enabled) {
            progress = 0;
            anim.start();
        } else {
            progress = 1;
        }
    }

    property Animation anim: SequentialAnimation {
        PauseAnimation { duration: shift.step * shift.stepMs }
        NumberAnimation {
            target: shift
            property: "progress"
            to: 1
            duration: shift.duration
            easing.type: Easing.OutBack
            easing.overshoot: 1.4
        }
    }
}
