import QtQuick

// Pytanie o aktualizację na całą wyspę: lista nowych commitów z master
// i Tak / Nie. Ten sam panel pokazuje potem wynik — "Zaktualizowano" albo
// powód odmowy. Stan jest w UpdateService.
//
// Wiersze listy celowo bez hovera: element z hoverem zabiera go podkładce
// wyspy (patrz DynamicIsland, hover z trzech źródeł) i musiałby trafić
// do `hovering`. Liczą się tylko przyciski.
Item {
    id: panel

    property color accent: "#5b8cff"

    readonly property bool hovering: btnNo.hovering || btnYes.hovering || btnClose.hovering

    readonly property string phase: UpdateService.phase
    readonly property bool asking: phase === "available" || phase === "applying"
    readonly property var commits: UpdateService.commits

    // Wysokość idzie za treścią: lista do maxRows wierszy (dłuższa się
    // przewija), błąd na dwie linie, sukces sam nagłówek — znika po chwili
    // bez klikania. chromeHeight = nagłówek, przyciski i odstępy między nimi.
    property int rowHeight: 24
    property int maxRows: 5
    readonly property int chromeHeight: 124
    readonly property int headerOnlyHeight: 66
    readonly property int maxHeight: chromeHeight + maxRows * rowHeight
    implicitWidth: 440
    implicitHeight: phase === "done" ? headerOnlyHeight
        : phase === "failed" ? chromeHeight + 2 * rowHeight
        : chromeHeight + Math.min(maxRows, Math.max(1, commits.length)) * rowHeight

    readonly property color tint: phase === "failed" ? "#e5484d"
        : phase === "done" ? "#30d158" : accent

    // 1 nowa zmiana, 2–4 nowe zmiany, 5–21 nowych zmian, 22 nowe zmiany…
    function changesLabel(n) {
        const tens = n % 100, ones = n % 10;
        if (n === 1) return "1 nowa zmiana";
        if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) return n + " nowe zmiany";
        return n + " nowych zmian";
    }

    // ---- nagłówek ----
    Item {
        id: header

        x: 18
        y: 16
        width: parent.width - 36
        height: 34

        Rectangle {
            id: badge

            width: 34
            height: 34
            radius: 17
            color: Qt.rgba(panel.tint.r, panel.tint.g, panel.tint.b, 0.18)

            Behavior on color { ColorAnimation { duration: 200 } }

            IslandIcon {
                anchors.centerIn: parent
                kind: panel.phase === "failed" ? "warning"
                    : panel.phase === "done" ? "check" : "refresh"
                size: 16
                color: panel.tint
            }
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: panel.phase === "failed" ? "Nie udało się zaktualizować"
                    : panel.phase === "done" ? "Zaktualizowano"
                    : "Dostępna aktualizacja wyspy"
                color: "#f5f5f5"
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: panel.phase === "failed" ? UpdateService.failReason
                    : panel.phase === "done" ? "Wyspa jest teraz na " + UpdateService.doneShort
                    : panel.changesLabel(panel.commits.length) + " na " + UpdateService.branch
                color: panel.phase === "failed" ? "#e5484d" : "#9a9aa2"
                font.pixelSize: 11
            }
        }
    }

    // ---- treść: lista commitów albo szczegół błędu ----
    Item {
        id: body

        x: 18
        y: header.y + header.height + 14
        width: parent.width - 36
        height: footer.y - y - 12

        ListView {
            id: list

            anchors.fill: parent
            visible: panel.asking
            clip: true
            model: panel.commits
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                required property var modelData

                width: list.width
                height: panel.rowHeight

                Rectangle {
                    x: 3
                    y: (parent.height - height) / 2
                    width: 5
                    height: 5
                    radius: 2.5
                    color: Qt.rgba(1, 1, 1, 0.3)
                }

                Text {
                    x: 16
                    width: hash.x - x - 10
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: modelData.subject
                    color: "#e2e2e6"
                    font.pixelSize: 12
                }

                Text {
                    id: hash

                    anchors.right: parent.right
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.short
                    color: "#78787f"
                    font.pixelSize: 11
                    font.family: "monospace"
                }
            }
        }

        // Ucięta lista ma wyglądać na "jest więcej", a nie na błąd układu.
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 22
            visible: list.visible && !list.atYEnd
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0.04, 0.04, 0.05, 0) }
                GradientStop { position: 1; color: "#0a0a0c" }
            }
        }

        Text {
            anchors.fill: parent
            visible: panel.phase === "failed"
            text: UpdateService.failDetail
            wrapMode: Text.WrapAnywhere
            elide: Text.ElideRight
            color: "#9a9aa2"
            font.pixelSize: 11
            font.family: "monospace"
        }
    }

    // ---- przyciski ----
    Item {
        id: footer

        x: 18
        y: parent.height - height - 16
        width: parent.width - 36
        height: 32
        visible: panel.phase !== "done"

        Text {
            anchors.left: parent.left
            anchors.right: buttons.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            visible: panel.asking
            elide: Text.ElideRight
            text: panel.phase === "applying" ? "Aktualizuję…" : "Zaktualizować teraz?"
            color: "#c8c8ce"
            font.pixelSize: 12
        }

        Row {
            id: buttons

            anchors.right: parent.right
            spacing: 8

            IslandTextButton {
                id: btnNo
                visible: panel.asking
                enabled: panel.phase === "available"
                text: "Nie"
                onClicked: UpdateService.decline()
            }

            IslandTextButton {
                id: btnYes
                visible: panel.asking
                enabled: panel.phase === "available" || busy
                primary: true
                accent: panel.accent
                busy: panel.phase === "applying"
                text: "Tak"
                onClicked: if (!busy) UpdateService.accept()
            }

            IslandTextButton {
                id: btnClose
                visible: !panel.asking
                text: "OK"
                onClicked: UpdateService.dismiss()
            }
        }
    }
}
