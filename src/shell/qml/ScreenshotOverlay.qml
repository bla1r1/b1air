import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import B1air.Daemon
import Quickshell.Wayland
import Quickshell.Io
import "Ui"
import "./Services"

PanelWindow {
    id: root
    color: "transparent"

    WlrLayershell.namespace: "qs-screenshot-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    
    exclusionMode: ExclusionMode.Ignore 
    focusable: true
    // Quickshell has no cursorScreen property — the singleton exposes screens
    // and nothing else — so this assignment evaluated to undefined and the
    // overlay opened on the default screen no matter where the user was.
    screen: Screens.focused
    width: screen.width
    height: screen.height

    
    property color dimColor: Qt.alpha(Design.ground, 0.50)
    property color selectionTint: Qt.alpha(Design.accentAlt, 0.05)
    property color handleColor: Design.text
    property color accentColor: Design.accentAlt

    property bool isEditMode: Quickshell.env("QS_SCREENSHOT_EDIT") === "true"
    readonly property string scriptDir: Quickshell.env("QS_SCRIPT_DIR") || (Quickshell.env("HOME") + "/.config/sway/scripts")
    
    property string cachedMode: Quickshell.env("QS_CACHED_MODE") || "false"
    property bool isVideoMode: cachedMode === "true"

    onIsVideoModeChanged: {
        Sys.writeFile("~/.cache/qs_screenshot_mode", root.isVideoMode ? "true\n" : "false\n");
        
        // Smart Geometry Snapping for Portal Support
        if (root.isVideoMode) {
            root.preStartX = root.startX; 
            root.preStartY = root.startY;
            root.preEndX = root.endX; 
            root.preEndY = root.endY;
            
            root.startX = 0; 
            root.startY = 0; 
            root.endX = root.width; 
            root.endY = root.height;
            root.hasSelection = true;
        } else {
            root.startX = root.preStartX; 
            root.startY = root.preStartY;
            root.endX = root.preEndX; 
            root.endY = root.preEndY;
            
            if (Math.abs(root.endX - root.startX) < 10 || Math.abs(root.endY - root.startY) < 10) {
                root.hasSelection = false;
            }
        }
    }
    
    // --- Audio State Persistence ---
    property real deskVol: Quickshell.env("QS_DESK_VOL") ? parseFloat(Quickshell.env("QS_DESK_VOL")) : 1.0
    property bool deskMute: Quickshell.env("QS_DESK_MUTE") === "true"
    property real micVol: Quickshell.env("QS_MIC_VOL") ? parseFloat(Quickshell.env("QS_MIC_VOL")) : 1.0
    property bool micMute: Quickshell.env("QS_MIC_MUTE") === "true"
    property string micDevice: Quickshell.env("QS_MIC_DEV") || ""

    function saveAudioPrefs() {
        let data = `${deskVol},${deskMute},${micVol},${micMute},${micDevice}`
        Sys.writeFile("~/.cache/qs_audio_prefs", data);
    }

    // --- Dynamic Mic Loader ---
    ListModel { id: micModel }
    
    Component.onCompleted: {
        Screens.refresh();
        let micData = Quickshell.env("QS_MIC_LIST") || ""
        if (micData.trim() !== "") {
            let lines = micData.trim().split('\n')
            for (let line of lines) {
                let parts = line.split('|')
                if (parts.length >= 2) {
                    micModel.append({ devName: parts[0], devDesc: parts.slice(1).join('|') })
                }
            }
        }
        
        if (root.micDevice === "" && micModel.count > 0) {
            root.micDevice = micModel.get(0).devName
            saveAudioPrefs()
        }
    }

    // --- Geometry State ---
    property string cachedGeom: Quickshell.env("QS_CACHED_GEOM") || ""
    property var cachedParts: cachedGeom.trim() !== "" ? cachedGeom.trim().split(",") : []
    property bool hasValidCache: cachedParts.length === 4 && parseFloat(cachedParts[2]) > 10

    property real startX: hasValidCache ? parseFloat(cachedParts[0]) : 0
    property real startY: hasValidCache ? parseFloat(cachedParts[1]) : 0
    property real endX: hasValidCache ? (parseFloat(cachedParts[0]) + parseFloat(cachedParts[2])) : 0
    property real endY: hasValidCache ? (parseFloat(cachedParts[1]) + parseFloat(cachedParts[3])) : 0
    
    property bool hasSelection: hasValidCache
    property bool isSelecting: false
    property bool isMaximized: false
    property real preStartX: 0
    property real preStartY: 0
    property real preEndX: 0
    property real preEndY: 0

    property real selX: Math.min(startX, endX)
    property real selY: Math.min(startY, endY)
    property real selW: Math.abs(endX - startX)
    property real selH: Math.abs(endY - startY)
    
    // grim, satty and the QR scanner all take a region in the compositor's
    // global coordinates; selX and selY are local to this window, which sits on
    // whichever screen the cursor was on. On the primary screen the two are the
    // same number and nothing looked wrong. On any other screen they are not,
    // so a selection made there was captured from the corresponding spot on the
    // first screen instead.
    readonly property int screenOffsetX: root.screen ? root.screen.x : 0
    readonly property int screenOffsetY: root.screen ? root.screen.y : 0

    property string geometryString: `${Math.round(selX) + screenOffsetX},${Math.round(selY) + screenOffsetY} ${Math.round(selW)}x${Math.round(selH)}`
    property int interactionMode: 0
    property real anchorX: 0; property real anchorY: 0
    property real initX: 0; property real initY: 0
    property real initW: 0; property real initH: 0

    // --- QR Scanner State ---
    property bool isScanningQr: false
    property bool showQrPopup: false
    property bool isQrSuccess: false
    ListModel { id: qrModel }

    function saveCache() {
        if (root.hasSelection && !root.isVideoMode) {
            let data = Math.round(root.selX) + "," + Math.round(root.selY) + "," + Math.round(root.selW) + "," + Math.round(root.selH);
            Sys.writeFile("~/.cache/qs_screenshot_geom", data);
        }
    }

    ParallelAnimation {
        id: maximizeAnim
        property real targetStartX; property real targetStartY
        property real targetEndX; property real targetEndY

        NumberAnimation { target: root; property: "startX"; to: maximizeAnim.targetStartX; duration: Design.duration.base; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "startY"; to: maximizeAnim.targetStartY; duration: Design.duration.base; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "endX"; to: maximizeAnim.targetEndX; duration: Design.duration.base; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "endY"; to: maximizeAnim.targetEndY; duration: Design.duration.base; easing.type: Easing.InOutQuad }
        onFinished: root.saveCache()
    }

    function toggleMaximize() {
        if (root.isVideoMode) return; // Disable maximization toggle during video mode
        if (!isMaximized) {
            preStartX = root.startX; preStartY = root.startY;
            preEndX = root.endX; preEndY = root.endY;
            maximizeAnim.targetStartX = 0; maximizeAnim.targetStartY = 0;
            maximizeAnim.targetEndX = root.width; maximizeAnim.targetEndY = root.height;
            isMaximized = true;
        } else {
            maximizeAnim.targetStartX = preStartX; maximizeAnim.targetStartY = preStartY;
            maximizeAnim.targetEndX = preEndX; maximizeAnim.targetEndY = preEndY;
            isMaximized = false;
        }
        maximizeAnim.restart();
    }

    // --- Keyboard Shortcuts ---
    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
    Shortcut { sequence: "Return"; onActivated: { if (root.hasSelection) root.executeCapture(root.isEditMode && !root.isVideoMode, root.isVideoMode) } }
    Shortcut { sequence: "Tab"; onActivated: root.isVideoMode = !root.isVideoMode }

    // --- Global Reusable Toolbar Button ---
    component ToolbarBtn: Rectangle {
        id: tBtn
        property string iconTxt: ""
        property string label: ""
        property bool isDanger: false
        signal clicked()

        Layout.preferredHeight: Design.s(36)
        Layout.preferredWidth: label !== "" ? (txt.implicitWidth + Design.s(36)) : Design.s(36)
        radius: Design.s(18)
        color: maBtn.containsMouse ? (isDanger ? Qt.alpha(Design.danger, 0.2) : Design.raised) : "transparent"
        Behavior on color { ColorAnimation { duration: Design.duration.fast } }

        RowLayout {
            anchors.centerIn: parent; spacing: Design.s(6)
            Text { font.family: Design.font.icon; text: tBtn.iconTxt; color: tBtn.isDanger ? Design.danger : Design.text; font.pixelSize: Design.s(18) }
            Text { id: txt; visible: tBtn.label !== ""; font.family: Design.font.mono; font.weight: Design.weight.semibold; text: tBtn.label; color: tBtn.isDanger ? Design.danger : Design.text; font.pixelSize: Design.s(13) }
        }
        Clickable { id: maBtn; onClicked: tBtn.clicked() }
    }

    Item {
        anchors.fill: parent
        z: 1
        Rectangle {
            anchors.fill: parent
            color: root.dimColor
            opacity: (!root.isSelecting && !root.hasSelection) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: Design.duration.fast } }
            Text {
                anchors.centerIn: parent
                text: root.isVideoMode ? I18n.tr("Click Record (Portal handles area selection)") : I18n.tr("Select region to capture")
                font.family: Design.font.mono; font.weight: Design.weight.semibold; font.pixelSize: Design.s(24); color: Design.text
            }
        }
        Item {
            anchors.fill: parent
            opacity: (root.isSelecting || root.hasSelection) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: Design.duration.fast } }
            Rectangle { x: 0; y: 0; width: parent.width; height: root.selY; color: root.dimColor } 
            Rectangle { x: 0; y: root.selY + root.selH; width: parent.width; height: parent.height - (root.selY + root.selH); color: root.dimColor }
            Rectangle { x: 0; y: root.selY; width: root.selX; height: root.selH; color: root.dimColor } 
            Rectangle { x: root.selX + root.selW; y: root.selY; width: parent.width - (root.selX + root.selW); height: root.selH; color: root.dimColor } 
        }
    }

    // The Main Selection Border
    Rectangle {
        visible: root.isSelecting || root.hasSelection
        x: root.selX; y: root.selY; width: root.selW; height: root.selH
        color: (root.showQrPopup && root.isQrSuccess) ? Qt.alpha(Design.ok, 0.15) : (root.isVideoMode ? Qt.alpha(Design.danger, 0.05) : root.selectionTint)
        border.color: (root.showQrPopup && root.isQrSuccess) ? Design.ok : (root.isVideoMode ? Design.danger : root.accentColor)
        border.width: Design.s(4)
        z: 5
    }

    Repeater {
        model: qrModel
        delegate: Rectangle {
            visible: opacity > 0
            opacity: (root.showQrPopup && model.qSuccess && model.qW > 0) ? 1.0 : 0.0
            property real pad: (root.showQrPopup && model.qSuccess) ? Design.s(5) : 0
            x: model.qW > 0 ? (model.qX - pad) : model.qX
            y: model.qH > 0 ? (model.qY - pad) : model.qY
            width: model.qW > 0 ? (model.qW + (pad * 2)) : 0
            height: model.qH > 0 ? (model.qH + (pad * 2)) : 0
            color: Qt.alpha(Design.ok, 0.25)
            border.color: Design.ok
            border.width: Design.s(3)
            radius: Design.s(8)
            z: 34
            Behavior on opacity { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutQuart } }
            Behavior on pad { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutQuart } }
        }
    }

    component Handle: Rectangle {
        width: Design.s(20); height: Design.s(20); radius: Design.s(10)
        color: root.handleColor; border.color: root.accentColor; border.width: Design.s(4)
        visible: (root.hasSelection || root.isSelecting) && !root.isScanningQr && !root.showQrPopup && !root.isVideoMode; z: 10
    }
    Handle { x: root.selX - width / 2; y: root.selY - height / 2 } 
    Handle { x: root.selX + root.selW - width / 2; y: root.selY - height / 2 } 
    Handle { x: root.selX - width / 2; y: root.selY + root.selH - height / 2 } 
    Handle { x: root.selX + root.selW - width / 2; y: root.selY + root.selH - height / 2 } 

    Clickable {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 20
        function getInteractionMode(mx, my, mods) {
            if (!root.hasSelection) return 1; 
            if (mods & Qt.ShiftModifier) return 2; 

            let margin = Design.s(20) 
            
            // Check if mouse is on the specific coordinate lines
            let onLeftLine = Math.abs(mx - root.selX) <= margin; 
            let onRightLine = Math.abs(mx - (root.selX + root.selW)) <= margin
            let onTopLine = Math.abs(my - root.selY) <= margin; 
            let onBottomLine = Math.abs(my - (root.selY + root.selH)) <= margin

            // Check if mouse is actually within the span of the selection (plus margin)
            let withinX = mx >= (root.selX - margin) && mx <= (root.selX + root.selW + margin);
            let withinY = my >= (root.selY - margin) && my <= (root.selY + root.selH + margin);

            // Corner checks (always require being on both lines)
            if (onTopLine && onLeftLine) return 3; 
            if (onTopLine && onRightLine) return 5;
            if (onBottomLine && onLeftLine) return 8; 
            if (onBottomLine && onRightLine) return 10;
            
            // Edge checks (require being on the line AND within the perpendicular bounds)
            if (onTopLine && withinX) return 4; 
            if (onBottomLine && withinX) return 9;
            if (onLeftLine && withinY) return 6; 
            if (onRightLine && withinY) return 7;
            
            return 1;
        }
        onPositionChanged: (mouse) => {
            if (root.isVideoMode) { cursorShape = Qt.ArrowCursor; return; }

            let mode = root.isSelecting ? root.interactionMode : getInteractionMode(mouse.x, mouse.y, mouse.modifiers)
            switch(mode) {
                case 2: cursorShape = Qt.ClosedHandCursor; break;
                case 3: case 10: cursorShape = Qt.SizeFDiagCursor; break;
                case 5: case 8: cursorShape = Qt.SizeBDiagCursor; break;
                case 4: case 9: cursorShape = Qt.SizeVerCursor; break;
                case 6: case 7: cursorShape = Qt.SizeHorCursor; break;
                default: cursorShape = Qt.CrossCursor; break;
            }

            if (!root.isSelecting) return;
            let dx = mouse.x - root.anchorX; let dy = mouse.y - root.anchorY
            let clamp = (val, min, max) => Math.max(min, Math.min(max, val))

            if (root.interactionMode === 1) { 
                root.endX = clamp(mouse.x, 0, root.width); root.endY = clamp(mouse.y, 0, root.height)
            } else if (root.interactionMode === 2) { 
                let targetX = clamp(root.initX + dx, 0, root.width - root.initW); let targetY = clamp(root.initY + dy, 0, root.height - root.initH)
                root.startX = targetX; root.startY = targetY; root.endX = targetX + root.initW; root.endY = targetY + root.initH;
            } else { 
                let nx = root.initX, ny = root.initY, nw = root.initW, nh = root.initH
                if ([3, 6, 8].includes(root.interactionMode)) { nx = clamp(root.initX + dx, 0, root.initX + root.initW - 10); nw = root.initW + (root.initX - nx) }
                if ([5, 7, 10].includes(root.interactionMode)) { nw = clamp(root.initW + dx, 10, root.width - root.initX) }
                if ([3, 4, 5].includes(root.interactionMode)) { ny = clamp(root.initY + dy, 0, root.initY + root.initH - 10); nh = root.initH + (root.initY - ny) }
                if ([8, 9, 10].includes(root.interactionMode)) { nh = clamp(root.initH + dy, 10, root.height - root.initY) }
                root.startX = nx; root.startY = ny; root.endX = nx + nw; root.endY = ny + nh;
            }
        }
        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) { Qt.quit(); return; }
            if (root.isVideoMode) return; 

            root.isScanningQr = false;
            root.showQrPopup = false;
            qrWaitTimer.stop();

            maximizeAnim.stop() 
            root.interactionMode = getInteractionMode(mouse.x, mouse.y, mouse.modifiers)
            root.isSelecting = true
            if (root.interactionMode !== 1) root.isMaximized = false;
            root.anchorX = mouse.x; root.anchorY = mouse.y
            root.initX = root.selX; root.initY = root.selY; root.initW = root.selW; root.initH = root.selH;

            if (root.interactionMode === 1) {
                let clamp = (val, min, max) => Math.max(min, Math.min(max, val))
                let clampedX = clamp(mouse.x, 0, root.width); let clampedY = clamp(mouse.y, 0, root.height)
                root.startX = clampedX; root.startY = clampedY; root.endX = clampedX; root.endY = clampedY;
                root.hasSelection = false; root.isMaximized = false
            }
        }
        onReleased: {
            if (root.isSelecting) {
                root.isSelecting = false
                if (root.selW > 10 && root.selH > 10) {
                    root.hasSelection = true; root.saveCache()
                } else { root.hasSelection = false }
            }
        }
    }

    // --- Main Bottom Toolbar ---
    Rectangle {
        id: toolbar
        z: 30 
        
        property bool fitsOutsideBottom: (root.selY + root.selH + height + Design.s(15)) <= root.height
        property bool fitsOutsideTop: (root.selY - height - Design.s(15)) >= 0
        property bool fitsInside: root.selH >= (height + Design.s(30)) && root.selW >= (width + Design.s(20))

        visible: root.hasSelection && !root.isSelecting && (fitsOutsideBottom || fitsOutsideTop || fitsInside) && !root.isScanningQr && !root.showQrPopup
        x: Math.max(Design.s(10), Math.min(parent.width - width - Design.s(10), root.selX + (root.selW / 2) - (width / 2)))
        y: fitsOutsideBottom ? (root.selY + root.selH + Design.s(15)) : (fitsOutsideTop ? (root.selY - height - Design.s(15)) : (root.selY + root.selH - height - Design.s(15)))

        width: toolbarLayout.width + Design.s(16)
        height: Design.s(52)
        radius: Design.s(26)
        color: Design.surface
        border.color: Design.hover
        border.width: Design.s(2)

        property bool popUpwards: (toolbar.y + Design.s(200)) > root.height

        component AudioControl: RowLayout {
            property string iconOn: ""
            property string iconOff: ""
            property real volumeValue: 1.0
            property bool mutedValue: false
            property bool hasDropdown: false
            
            signal volumeUpdate(real newVol)
            signal muteUpdate(bool newMute)
            signal dropdownClicked()

            spacing: Design.s(4)

            Rectangle {
                width: Design.s(30); height: Design.s(30); radius: Design.s(15)
                color: maIcon.containsMouse ? Design.hover : "transparent"
                Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                Text {
                    anchors.centerIn: parent
                    font.family: Design.font.icon
                    text: parent.parent.mutedValue ? parent.parent.iconOff : parent.parent.iconOn
                    color: parent.parent.mutedValue ? Design.danger : Design.text
                    font.pixelSize: Design.s(16)
                }
                Clickable {
                    id: maIcon
                    onClicked: parent.parent.muteUpdate(!parent.parent.mutedValue)
                }
            }

            // Explicitly QtQuick.Controls.Slider: bare "Slider" resolves to
            // Ui/Slider.qml (a completely different, icon+label capsule
            // component with no from/to/value/handle), which crashed this
            // file on load with "Cannot assign to non-existent property
            // 'handle'" — the reason it never actually worked.
            QQC.Slider {
                Layout.preferredWidth: Design.s(60)
                from: 0.0; to: 1.0; value: parent.volumeValue
                onValueChanged: parent.volumeUpdate(value)

                background: Rectangle {
                    x: parent.leftPadding; y: parent.topPadding + parent.availableHeight / 2 - height / 2
                    implicitWidth: Design.s(60); implicitHeight: Design.s(4)
                    width: parent.availableWidth; height: implicitHeight
                    radius: Design.s(2)
                    color: Design.active
                    Rectangle { width: parent.parent.visualPosition * parent.width; height: parent.height; color: parent.parent.parent.mutedValue ? Design.textDim : Design.accentAlt; radius: Design.s(2) }
                }
                handle: Rectangle {
                    x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                    y: parent.topPadding + parent.availableHeight / 2 - height / 2
                    implicitWidth: Design.s(12); implicitHeight: Design.s(12); radius: Design.s(6)
                    color: parent.parent.parent.mutedValue ? Design.textDim : Design.accentAlt
                }
            }

            Rectangle {
                visible: parent.hasDropdown
                width: Design.s(20); height: Design.s(30); color: "transparent"
                Text {
                    anchors.centerIn: parent
                    font.family: Design.font.icon
                    text: toolbar.popUpwards ? "󰅃" : "󰅀"
                    color: Design.text
                    font.pixelSize: Design.s(16)
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.parent.dropdownClicked() }
            }
        }

        Rectangle {
            id: micDropdown
            visible: false
            width: Design.s(280)
            height: micModel.count === 0 ? Design.s(40) : Math.min(Design.s(180), micModel.count * Design.s(36))
            x: micAudio.x - Design.s(40)
            y: toolbar.popUpwards ? (-height - Design.s(8)) : (toolbar.height + Design.s(8))
            color: Design.surface
            border.color: Design.hover; border.width: Design.s(2)
            radius: Design.s(8)
            z: 50

            Text {
                visible: micModel.count === 0
                anchors.centerIn: parent
                text: I18n.tr("No Microphones (Install pulseaudio)")
                color: Design.textDim
                font.pixelSize: Design.s(12)
            }

            ListView {
                visible: micModel.count > 0
                anchors.fill: parent; anchors.margins: Design.s(4)
                model: micModel
                clip: true
                delegate: Rectangle {
                    width: ListView.view.width; height: Design.s(32); radius: Design.s(6)
                    color: maList.containsMouse ? Design.raised : "transparent"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: Design.s(6)
                        Text { text: model.devDesc; color: root.micDevice === model.devName ? Design.accentAlt : Design.text; font.pixelSize: Design.s(12); elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    Clickable {
                        id: maList
                        onClicked: { root.micDevice = model.devName; root.saveAudioPrefs(); micDropdown.visible = false }
                    }
                }
            }
        }

        RowLayout {
            id: toolbarLayout
            anchors.centerIn: parent
            spacing: Design.s(8)

            Rectangle {
                width: Design.s(80); height: Design.s(36); radius: Design.s(18)
                color: Design.raised
                
                RowLayout {
                    anchors.fill: parent; anchors.margins: Design.s(4); spacing: 0
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: Design.s(14)
                        color: !root.isVideoMode ? Design.active : "transparent"
                        Behavior on color { ColorAnimation { duration: Design.duration.base } }
                        Text { anchors.centerIn: parent; font.family: Design.font.icon; text: "󰄄"; color: !root.isVideoMode ? Design.text : Design.textDim; font.pixelSize: Design.s(16) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.isVideoMode = false }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: Design.s(14)
                        color: root.isVideoMode ? Design.active : "transparent"
                        Behavior on color { ColorAnimation { duration: Design.duration.base } }
                        Text { anchors.centerIn: parent; font.family: Design.font.icon; text: ""; color: root.isVideoMode ? Design.text : Design.textDim; font.pixelSize: Design.s(16) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.isVideoMode = true }
                    }
                }
            }

            Rectangle { width: Design.s(2); Layout.fillHeight: true; Layout.topMargin: Design.s(10); Layout.bottomMargin: Design.s(10); color: Design.raised; radius: Design.s(1) }

            AudioControl { 
                id: deskAudio; visible: root.isVideoMode; iconOn: "󰓃"; iconOff: "󰓄" 
                volumeValue: root.deskVol; mutedValue: root.deskMute
                onVolumeUpdate: (v) => { root.deskVol = v; root.saveAudioPrefs() }
                onMuteUpdate: (m) => { root.deskMute = m; root.saveAudioPrefs() }
            }
            
            AudioControl { 
                id: micAudio; visible: root.isVideoMode; iconOn: "󰍬"; iconOff: "󰍭"; hasDropdown: true
                volumeValue: root.micVol; mutedValue: root.micMute
                onVolumeUpdate: (v) => { root.micVol = v; root.saveAudioPrefs() }
                onMuteUpdate: (m) => { root.micMute = m; root.saveAudioPrefs() }
                onDropdownClicked: micDropdown.visible = !micDropdown.visible
            }

            Rectangle { visible: root.isVideoMode; width: Design.s(2); Layout.fillHeight: true; Layout.topMargin: Design.s(10); Layout.bottomMargin: Design.s(10); color: Design.raised; radius: Design.s(1) }

            ToolbarBtn { visible: !root.isVideoMode; iconTxt: "󰄄"; label: I18n.tr("Capture"); onClicked: root.executeCapture(false, false) }
            ToolbarBtn { visible: root.isVideoMode; iconTxt: "󰑊"; label: I18n.tr("Record"); isDanger: true; onClicked: root.executeCapture(false, true) }

            ToolbarBtn { visible: !root.isVideoMode; iconTxt: "󰏫"; onClicked: root.executeCapture(true, false) }
            ToolbarBtn { visible: !root.isVideoMode; iconTxt: "⿻"; onClicked: root.performQrScan() }

            Rectangle { width: Design.s(2); Layout.fillHeight: true; Layout.topMargin: Design.s(10); Layout.bottomMargin: Design.s(10); color: Design.raised; radius: Design.s(1) }
            
            ToolbarBtn { visible: !root.isVideoMode; iconTxt: root.isMaximized ? "" : ""; onClicked: root.toggleMaximize() }
            ToolbarBtn { iconTxt: "󰅖"; isDanger: true; onClicked: Qt.quit() }
        }
    }

    Repeater {
        model: qrModel
        delegate: Rectangle {
            id: qrPopupItem
            visible: opacity > 0
            opacity: (root.showQrPopup && !root.isSelecting) ? 1.0 : 0.0
            
            x: model.qTargetX
            y: model.qTargetY + (model.fitsTop ? (1.0 - opacity) * Design.s(15) : -(1.0 - opacity) * Design.s(15))
            
            width: qrPopupLayout.implicitWidth + Design.s(32)
            height: Design.s(52)
            radius: Design.s(26)
            color: Design.surface
            border.color: model.qSuccess ? Design.ok : Design.danger
            border.width: Design.s(2)

            property bool isHovered: maHover.containsMouse

            scale: isHovered ? 1.0 : model.qBaseScale
            z: isHovered ? 100 : (40 - index)
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutQuart } }
            Behavior on scale { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutQuart } }

            Clickable { id: maHover; acceptedButtons: Qt.NoButton }

            RowLayout {
                id: qrPopupLayout
                anchors.centerIn: parent
                spacing: Design.s(8)

                Text {
                    text: model.qText
                    color: model.qSuccess ? Design.text : Design.danger
                    font.family: Design.font.mono
                    font.pixelSize: Design.s(13)
                    font.weight: Design.weight.semibold
                    Layout.maximumWidth: Design.s(400)
                    Layout.leftMargin: Design.s(8)
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Rectangle { visible: model.qSuccess; width: Design.s(2); Layout.fillHeight: true; Layout.topMargin: Design.s(10); Layout.bottomMargin: Design.s(10); color: Design.raised; radius: Design.s(1) }

                ToolbarBtn {
                    visible: model.qSuccess
                    iconTxt: "󰆏"
                    onClicked: {
                        Quickshell.execDetached(["b1air-clip", "copy", "--", model.qText]);
                        root.showQrPopup = false;
                    }
                }

                ToolbarBtn {
                    visible: model.qSuccess && (model.qText.startsWith("http://") || model.qText.startsWith("https://"))
                    iconTxt: "󰌹"
                    onClicked: {
                        Quickshell.execDetached(["xdg-open", model.qText]);
                        Qt.quit();
                    }
                }

                Rectangle { width: Design.s(2); Layout.fillHeight: true; Layout.topMargin: Design.s(10); Layout.bottomMargin: Design.s(10); color: Design.raised; radius: Design.s(1) }
                ToolbarBtn { iconTxt: "󰅖"; isDanger: true; onClicked: root.showQrPopup = false }
            }
        }
    }

    Process {
        id: qrReaderProcess
        property string accumulated: ""
        command: ["cat", (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/b1air/qr_result"]
        stdout: SplitParser { splitMarker: ""; onRead: data => qrReaderProcess.accumulated += data }
        
        onExited: (exitCode) => {
            let res = qrReaderProcess.accumulated.trim()
            qrReaderProcess.accumulated = ""
            root.isScanningQr = false
            qrModel.clear()
    
            if (exitCode !== 0 || res === "") {
                qrModel.append({ 
                    qX: root.selX + (root.selW / 2), qY: root.selY + (root.selH / 2), qW: 0, qH: 0, 
                    qText: I18n.tr("Scan timed out or failed."), qSuccess: false,
                    qTargetX: root.selX + (root.selW / 2) - Design.s(100), qTargetY: root.selY + (root.selH / 2),
                    qBaseScale: 1.0, fitsTop: false 
                })
                root.isQrSuccess = false
                root.showQrPopup = true
                return
            }

            let lines = res.split('\n');
            let anySuccess = false;
            let qrs = [];

            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line === "") continue;
                let delimiterIdx = line.indexOf('|||');
                if (delimiterIdx === -1) continue;

                let coordStr = line.substring(0, delimiterIdx);
                let actualText = line.substring(delimiterIdx + 3).replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
                let coords = coordStr.split(',');

                if (coords.length === 4 && !isNaN(parseInt(coords[0]))) {
                    let x = parseInt(coords[0]); let y = parseInt(coords[1]); let w = parseInt(coords[2]); let h = parseInt(coords[3]);
                    
                    let successState = !(actualText === "NOT_FOUND" || actualText.startsWith("ERROR:"));
                    if (successState) anySuccess = true;
                    let cleanText = successState ? actualText.replace(/^QR-Code:/, "") : (actualText === "NOT_FOUND" ? I18n.tr("No QR code found.") : actualText);
                    
                    let estTextWidth = Math.min(Design.s(400), cleanText.length * Design.s(8.5));
                    let pw = estTextWidth + (successState ? Design.s(140) : Design.s(40)); 
                    let ph = Design.s(52);
                    let absX = root.selX + x; let absY = root.selY + y;
                    let cx = absX + (w / 2);
                    let fitsTop = (absY - ph - Design.s(15)) >= root.selY;
                    let idealX = cx - (pw / 2);
                    let targetX = Math.max(Design.s(10), Math.min(root.width - pw - Design.s(10), idealX));
                    let targetY = fitsTop ? (absY - ph - Design.s(15)) : (absY + h + Design.s(15));

                    qrs.push({ qX: absX, qY: absY, qW: w, qH: h, qText: cleanText, qSuccess: successState, pw: pw, ph: ph, targetX: targetX, targetY: targetY, cx: targetX + (pw / 2), cy: targetY + (ph / 2), scale: 1.0, fitsTop: fitsTop });
                }
            }

            for (let pass = 0; pass < 5; pass++) {
                for (let i = 0; i < qrs.length; i++) {
                    for (let j = i + 1; j < qrs.length; j++) {
                        let A = qrs[i]; let B = qrs[j];
                        let dx = Math.abs(A.cx - B.cx); let dy = Math.abs(A.cy - B.cy);
                        let req_x = (A.pw * A.scale + B.pw * B.scale) / 2 + Design.s(10);
                        let req_y = (A.ph * A.scale + B.ph * B.scale) / 2 + Design.s(10);
                        
                        if (dx < req_x && dy < req_y) {
                            let factorX = dx > 0 ? (dx - Design.s(10)) * 2 / (A.pw + B.pw) : 0;
                            let factorY = dy > 0 ? (dy - Design.s(10)) * 2 / (A.ph + B.ph) : 0;
                            let maxFactor = Math.max(factorX, factorY);
                            maxFactor = Math.max(0.35, maxFactor); 
                            A.scale = Math.min(A.scale, maxFactor); B.scale = Math.min(B.scale, maxFactor);
                        }
                    }
                }
            }

            if (qrs.length === 0) {
                qrModel.append({ 
                    qX: root.selX + (root.selW / 2), qY: root.selY + (root.selH / 2), qW: 0, qH: 0, 
                    qText: I18n.tr("No QR code found."), qSuccess: false,
                    qTargetX: root.selX + (root.selW / 2) - Design.s(100), qTargetY: root.selY + (root.selH / 2),
                    qBaseScale: 1.0, fitsTop: false 
                });
            } else {
                for (let i = 0; i < qrs.length; i++) {
                    qrModel.append({ qX: qrs[i].qX, qY: qrs[i].qY, qW: qrs[i].qW, qH: qrs[i].qH, qText: qrs[i].qText, qSuccess: qrs[i].qSuccess, qTargetX: qrs[i].targetX, qTargetY: qrs[i].targetY, qBaseScale: qrs[i].scale, fitsTop: qrs[i].fitsTop });
                }
            }

            root.isQrSuccess = anySuccess;
            root.showQrPopup = true
            Sys.removeFile((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/b1air/qr_result")
        }
    }
    
    Timer {
        id: qrWaitTimer
        interval: 1200  
        repeat: false
        onTriggered: qrReaderProcess.running = true
    }
    
    function performQrScan() {
            Sys.removeFile((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/b1air/qr_result")
        root.isScanningQr = true; root.showQrPopup = false; qrModel.clear()
        Quickshell.execDetached(["b1air-daemon", "scan-qr", root.geometryString])
        qrWaitTimer.start()
    }   
    
    // Add this Timer alongside your other timers (e.g. near qrWaitTimer)
    Timer {
        id: captureTimer
        property bool pendingRecord: false
        property bool pendingEditor: false
        interval: 80   // enough for Sway to actually unmap the surface
        repeat: false
        onTriggered: {
            if (pendingRecord) {
                let args = ["b1air-daemon", "record", "toggle", "--geometry", root.geometryString,
                            "--desk-vol", String(root.deskVol), "--desk-mute", String(root.deskMute),
                            "--mic-vol", String(root.micVol), "--mic-mute", String(root.micMute)];
                if (root.micDevice !== "" && /^[A-Za-z0-9_.:@-]+$/.test(root.micDevice)) args.push("--mic-dev", root.micDevice);
                Quickshell.execDetached(args);
            } else {
                let args = ["b1air-daemon", "capture", "--geometry", root.geometryString];
                if (pendingEditor) args.push("--edit");
                Quickshell.execDetached(args);
            }
            Qt.quit()
        }
    }
    
    function executeCapture(openEditor, isRecord) {
        root.visible = false          // hide overlay immediately
        captureTimer.pendingRecord = isRecord
        captureTimer.pendingEditor = openEditor
        captureTimer.start()          // fire grim only after compositor unmaps us
    }
}
