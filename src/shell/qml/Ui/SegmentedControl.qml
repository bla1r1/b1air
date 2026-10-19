import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C

// =============================================================================
// SegmentedControl component for 2-5 mutually exclusive choices.
//
// Track with equal-width segments and an animated selection indicator.
// Supports keyboard navigation (Left/Right arrows, Tab, FocusRing).
// =============================================================================

Rectangle {
    id: root

    // Model can be array of strings ["One", "Two"] or objects
    // [{ id: "one", label: "One", icon?: "...", tip?: "..." }]. An item with an
    // icon and no label is a square icon segment; its tip names it on hover.
    property var model: []
    property int currentIndex: 0
    property string current: "" // id or string value
    property string size: "md"  // "sm" (28) | "md" (32)

    signal picked(var id, int index)
    signal activated(int index)

    readonly property int count: root.model ? root.model.length : 0

    function _itemId(idx) {
        if (!root.model || idx < 0 || idx >= root.model.length) return "";
        const it = root.model[idx];
        return (typeof it === "object" && it !== null && it.id !== undefined) ? it.id : String(it);
    }

    function _itemLabel(idx) {
        if (!root.model || idx < 0 || idx >= root.model.length) return "";
        const it = root.model[idx];
        return (typeof it === "object" && it !== null && it.label !== undefined) ? it.label : String(it);
    }

    function _itemTip(idx) {
        if (!root.model || idx < 0 || idx >= root.model.length) return "";
        const it = root.model[idx];
        return (typeof it === "object" && it !== null && it.tip !== undefined) ? it.tip : "";
    }

    // Icons only: every item has an icon and no label.
    readonly property bool iconsOnly: {
        if (!root.model || root.count === 0) return false;
        for (let i = 0; i < root.count; ++i) {
            const it = root.model[i];
            if (typeof it !== "object" || it === null || !it.icon || (it.label !== undefined && it.label !== "")) return false;
        }
        return true;
    }

    function _itemIcon(idx) {
        if (!root.model || idx < 0 || idx >= root.model.length) return "";
        const it = root.model[idx];
        return (typeof it === "object" && it !== null && it.icon !== undefined) ? it.icon : "";
    }

    onCurrentChanged: {
        if (root.model && root.current !== "") {
            for (let i = 0; i < root.model.length; ++i) {
                if (root._itemId(i) === root.current) {
                    if (root.currentIndex !== i) root.currentIndex = i;
                    break;
                }
            }
        }
    }

    // `current` is the caller's: assigning it here broke a binding such as
    // `current: window.currentTab` on the first click, and the control then
    // stopped following the state it showed. The choice goes out by picked().
    onModelChanged: _syncFromCurrent()
    Component.onCompleted: _syncFromCurrent()
    function _syncFromCurrent() {
        if (!root.model || root.current === "") return;
        for (let i = 0; i < root.model.length; ++i)
            if (root._itemId(i) === root.current) { root.currentIndex = i; return; }
    }

    function selectIndex(idx) {
        if (idx >= 0 && idx < root.count) {
            root.currentIndex = idx;
            const id = root._itemId(idx);
            root.picked(id, idx);
            root.activated(idx);
        }
    }

    readonly property real _targetHeight: size === "sm" ? Design.s(Design.size.sm) : Design.s(Design.size.md)
    implicitHeight: _targetHeight
    Layout.preferredHeight: _targetHeight

    // Minimum width based on count and padding
    implicitWidth: iconsOnly
        ? count * _targetHeight + Design.s(Design.space.xxs) * 2
        : Math.max(Design.s(Design.width.segment), count * Design.s(size === "sm" ? Design.width.segmentSm : Design.width.segmentMd))
    Layout.preferredWidth: implicitWidth

    radius: Design.s(Design.radius.ctl)
    color: Design.well
    border.width: 1
    border.color: Design.glassBorder
    opacity: enabled ? 1.0 : Design.opacity.disabled

    readonly property real _pad: Design.s(Design.space.xxs)
    readonly property real _segWidth: count > 0 ? (width - _pad * 2) / count : 0

    // Animated selection indicator
    Rectangle {
        id: indicator
        visible: root.count > 0 && root.currentIndex >= 0 && root.currentIndex < root.count
        y: root._pad
        height: root.height - root._pad * 2
        width: root._segWidth
        x: root._pad + root.currentIndex * root._segWidth
        radius: Math.max(2, root.radius - root._pad)
        color: Design.translucent ? Design.veilBold : Design.raised
        border.width: 1
        border.color: Design.glassBorder

        Behavior on x {
            NumberAnimation { duration: Design.duration.fast; easing.type: Design.easing }
        }
    }

    Row {
        id: segmentRow
        anchors.fill: parent
        anchors.margins: root._pad

        Repeater {
            model: root.count

            Item {
                id: segItem
                width: root._segWidth
                height: segmentRow.height
                // No clip: the label is held to the segment's width and
                // elides. A clip here was drawn past the clip of a scrolled
                // view around it by Qt's software renderer (Settings in its
                // own window): the segments' labels hung below the setup's card.

                readonly property int itemIndex: index
                readonly property bool isSelected: root.currentIndex === index
                readonly property bool isHovered: segMa.containsMouse

                RowLayout {
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, segItem.width - Design.s(Design.space.xs) * 2)
                    spacing: Design.s(Design.space.xs)

                    Icon {
                        visible: root._itemIcon(index) !== ""
                        text: root._itemIcon(index)
                        role: root.size === "sm" ? "caption" : "body"
                        Layout.alignment: Qt.AlignVCenter
                        color: segItem.isSelected ? Design.accent : Design.textDim
                    }

                    Label {
                        visible: text !== ""
                        text: root._itemLabel(index)
                        role: root.size === "sm" ? "footnote" : "body"
                        weight: segItem.isSelected ? Design.weight.semibold : Design.weight.regular
                        color: segItem.isSelected ? Design.text : (segItem.isHovered ? Design.text : Design.textDim)
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                C.ToolTip.visible: segMa.containsMouse && root._itemTip(index) !== ""
                C.ToolTip.text: root._itemTip(index)
                C.ToolTip.delay: 600

                MouseArea {
                    id: segMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        root.forceActiveFocus(Qt.MouseFocusReason);
                        root.selectIndex(index);
                    }
                }
            }
        }
    }

    activeFocusOnTab: enabled
    Accessible.role: Accessible.PageTabList
    Accessible.name: root.current

    Keys.onLeftPressed: function(event) {
        if (root.enabled && root.currentIndex > 0) {
            root.selectIndex(root.currentIndex - 1);
            event.accepted = true;
        }
    }

    Keys.onRightPressed: function(event) {
        if (root.enabled && root.currentIndex < root.count - 1) {
            root.selectIndex(root.currentIndex + 1);
            event.accepted = true;
        }
    }

    FocusRing {
        target: root
        cornerRadius: root.radius + Design.s(Design.space.xxs)
    }
}
