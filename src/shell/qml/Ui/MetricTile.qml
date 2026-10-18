import QtQuick
import QtQuick.Layouts

// =============================================================================
// One measured figure: a ring gauge (or a glyph), the figure, what it is and
// a line of detail. Moved here from Monitor's MetricCard so the Control
// Center and anything else that shows a reading draws it the same way.
//
//   MetricTile { label: "CPU"; value: "23%"; sub: "8 cores"; pct: 23; tone: Design.accent }
//
// `tone` is the reading's colour: a named hue for data, ok/warn/danger only
// when the figure is a status.
// =============================================================================

Rectangle {
    id: tile

    property string label: ""
    property string value: ""
    property string sub: ""
    property color tone: Design.accent
    // 0..100 draws a ring; below 0 draws the glyph instead.
    property real pct: -1
    property string glyph: ""

    Layout.fillWidth: true
    implicitHeight: Design.s(Design.size.avatar)
    radius: Design.s(Design.radius.card)
    color: Design.translucent ? Design.glassCard : Design.raised
    border.color: Design.glassBorder
    border.width: Design.border

    RowLayout {
        anchors.fill: parent
        anchors.margins: Design.s(Design.space.md)
        spacing: Design.s(Design.space.md)

        Item {
            Layout.preferredWidth: Design.s(Design.size.art)
            Layout.preferredHeight: Design.s(Design.size.art)
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Design.tint(tile.tone, 0.12)
                border.color: Design.tint(tile.tone, 0.35)
                border.width: Design.s(Design.focusWidth)
            }

            Canvas {
                id: ring
                anchors.fill: parent
                visible: tile.pct >= 0
                // Painted once when first shown; these repaint it when it has
                // a size and whenever the figure moves.
                Component.onCompleted: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const r = Math.min(width, height) / 2 - Design.s(Design.border);
                    ctx.beginPath();
                    ctx.arc(width / 2, height / 2, r, -Math.PI / 2,
                            -Math.PI / 2 + (Math.max(0, Math.min(100, tile.pct)) / 100) * 2 * Math.PI);
                    ctx.strokeStyle = tile.tone;
                    ctx.lineWidth = Design.s(Design.space.xs);
                    ctx.lineCap = "round";
                    ctx.stroke();
                }
                Connections {
                    target: tile
                    function onPctChanged() { ring.requestPaint(); }
                    function onToneChanged() { ring.requestPaint(); }
                }
            }

            Icon {
                anchors.centerIn: parent
                visible: tile.pct < 0 && tile.glyph !== ""
                text: tile.glyph
                role: "subhead"
                color: tile.tone
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Design.s(Design.space.xxs)

            Label { Layout.fillWidth: true; text: tile.label; role: "caption"; weight: Design.weight.semibold; dim: true; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; text: tile.value; role: "subhead"; weight: Design.weight.semibold; tabular: true; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; visible: text !== ""; text: tile.sub; role: "caption"; dim: true; elide: Text.ElideRight }
        }
    }
}
