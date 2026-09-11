import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import Ui

ApplicationWindow {
    id: window
    title: GitBackend.repoName ? "Git — " + GitBackend.repoName : "Git"
    width: Design.s(1040)
    height: Design.s(680)
    minimumWidth: 700
    minimumHeight: 450
    visible: true
    color: "transparent"
    flags: Qt.Window

    // With no repository open, every action in this window is a no-op: staging,
    // committing, fetching and pushing all need one. They were all live anyway
    // — "Stage All" and "Unstage All" clickable, the commit fields editable,
    // and a commit button reading "Commit to —" with a dash where the branch
    // goes. Nothing happened and nothing said why.
    // isRepo, not repoPath: when the search finds no .git the backend still
    // sets repoPath to the directory it started from, so that is never empty.
    readonly property bool hasRepo: GitBackend.isRepo

    // A second, hand-rolled Tokyo Night palette used to live here alongside the
    // Catppuccin one in Ui/Design.qml, so this window never followed the theme.
    // The names stay — they are used throughout the file — but each now resolves
    // to a design-system role, exactly as FilesWindow.qml was already migrated.
    readonly property color colBg: Design.surface
    readonly property color colDark: Design.ground
    readonly property color colHeader: Design.sunken
    readonly property color colSunken: Design.sunken
    readonly property color colBorder: Design.glassBorder
    readonly property color colBorderSubtle: Design.line
    readonly property color colBlue: Design.accent
    readonly property color colPurple: Design.mauve
    readonly property color colCyan: Design.sapphire
    readonly property color colGreen: Design.ok
    readonly property color colOrange: Design.warn
    readonly property color colRed: Design.danger
    readonly property color colFg: Design.text
    readonly property color colDim: Design.textDim

    // GitBackend::refresh() has been Q_INVOKABLE since the app was written and
    // was never called from anywhere in the UI, so a repo changed in a terminal
    // stayed stale on screen until the window was closed and reopened.
    // b1air-monitor already uses F5 for exactly this.
    Shortcut {
        sequence: "Escape"
        onActivated: window.close()
    }

    Shortcut {
        sequence: "F5"
        onActivated: GitBackend.refresh()
    }

    Shortcut {
        sequence: "Ctrl+R"
        onActivated: GitBackend.refresh()
    }

    property int currentTab: 0 // 0: Changes, 1: History
    property bool repoDropdownOpen: false
    property bool branchDropdownOpen: false

    Rectangle {
        id: windowFrame
        anchors.fill: parent
        // No corners or outline of our own: sway draws both, and only sway
        // knows which window has focus. The app drew a fixed 1px line and sway
        // was told `border none` for it, so ours were the only windows on the
        // desktop that did not light up when focused. SwayFX's corner_radius
        // rounds the surface; a 14px radius inside its 10px one left slivers.
        radius: 0
        color: window.colBg
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ══════════════════════════════════════════════════════════════════
            // GITHUB DESKTOP TOP TOOLBAR (42px)
            // ══════════════════════════════════════════════════════════════════
            // A full border on a bar that spans the window draws its left and
            // right edges directly on top of the frame's own, and its top edge
            // on nothing at all. What separates a bar from what is under it is
            // one line, so that is what it has. The same correction is made to
            // every header inside the panels below — the window used to be a
            // grid of hairline boxes because each one drew four sides.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(42)
                color: window.colHeader
                z: 20

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: window.colBorder
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(12)
                    anchors.rightMargin: Design.s(12)
                    spacing: Design.s(8)

                    // 1. Current Repository Selector
                    Rectangle {
                        id: repoBtn
                        width: repoRow.implicitWidth + Design.s(20)
                        height: Design.s(28)
                        radius: Design.s(6)
                        color: repoArea.containsMouse || window.repoDropdownOpen ? Design.tint(Design.accent, 0.18) : Design.tint(Design.raised, 0.60)
                        border.color: window.repoDropdownOpen ? window.colBlue : window.colBorder
                        border.width: 1

                        Row {
                            id: repoRow
                            anchors.centerIn: parent
                            spacing: Design.s(6)
                            Text {
                                text: "󰊢"
                                font.family: Design.font.mono
                                font.pixelSize: Design.s(13)
                                color: window.colBlue
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Current Repository:"
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(10)
                                color: window.colDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: GitBackend.repoName
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(12)
                                font.bold: true
                                color: window.colFg
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: window.repoDropdownOpen ? "󰅃" : "󰅀"
                                font.family: Design.font.mono
                                font.pixelSize: Design.s(11)
                                color: window.colDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: repoArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                window.repoDropdownOpen = !window.repoDropdownOpen;
                                window.branchDropdownOpen = false;
                            }
                        }
                    }

                    // 2. Current Branch Selector
                    Rectangle {
                        id: branchBtn
                        width: branchRow.implicitWidth + Design.s(20)
                        height: Design.s(28)
                        radius: Design.s(6)
                        color: branchArea.containsMouse || window.branchDropdownOpen ? Design.tint(Design.ok, 0.18) : Design.tint(Design.raised, 0.60)
                        border.color: window.branchDropdownOpen ? window.colGreen : window.colBorder
                        border.width: 1

                        Row {
                            id: branchRow
                            anchors.centerIn: parent
                            spacing: Design.s(6)
                            Text {
                                text: ""
                                font.family: Design.font.mono
                                font.pixelSize: Design.s(13)
                                color: window.colGreen
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Current Branch:"
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(10)
                                color: window.colDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: GitBackend.branchName
                                font.family: Design.font.mono
                                font.pixelSize: Design.s(11)
                                font.bold: true
                                color: window.colGreen
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: window.branchDropdownOpen ? "󰅃" : "󰅀"
                                font.family: Design.font.mono
                                font.pixelSize: Design.s(11)
                                color: window.colDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: branchArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                window.branchDropdownOpen = !window.branchDropdownOpen;
                                window.repoDropdownOpen = false;
                            }
                        }
                    }

                    // 3. Fetch / Push / Pull Action Pill
                    Rectangle {
                        id: syncBtn
                        width: syncRow.implicitWidth + Design.s(20)
                        height: Design.s(28)
                        radius: Design.s(6)
                        color: syncArea.containsMouse ? Design.tint(Design.accent, 0.22) : Design.tint(Design.raised, 0.60)
                        border.color: window.colBorder
                        border.width: 1

                        Row {
                            id: syncRow
                            anchors.centerIn: parent
                            spacing: Design.s(6)
                            Text {
                                text: "󰑐"
                                font.family: Design.font.mono
                                font.pixelSize: Design.s(12)
                                color: window.colBlue
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Fetch origin"
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(11)
                                font.bold: true
                                color: window.colFg
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        opacity: window.hasRepo ? 1.0 : 0.45
                        enabled: window.hasRepo

                        MouseArea {
                            id: syncArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: GitBackend.fetch()
                        }
                    }

                    // Push / Pull Quick Actions
                    Row {
                        spacing: Design.s(4)
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            width: Design.s(28); height: Design.s(28); radius: Design.s(6)
                            color: pushArea.containsMouse ? Design.tint(Design.mauve, 0.25) : "transparent"
                            border.color: pushArea.containsMouse ? window.colPurple : window.colBorder
                            border.width: 1
                            opacity: window.hasRepo ? 1.0 : 0.45
                            enabled: window.hasRepo
                            Text { anchors.centerIn: parent; text: "󰜮"; font.family: Design.font.mono; font.pixelSize: Design.s(13); color: window.colPurple }
                            MouseArea { id: pushArea; anchors.fill: parent; hoverEnabled: true; cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: GitBackend.push() }
                        }

                        Rectangle {
                            width: Design.s(28); height: Design.s(28); radius: Design.s(6)
                            opacity: window.hasRepo ? 1.0 : 0.45
                            enabled: window.hasRepo
                            color: pullArea.containsMouse ? Design.tint(Design.sapphire, 0.25) : "transparent"
                            border.color: pullArea.containsMouse ? window.colCyan : window.colBorder
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "󰜱"; font.family: Design.font.mono; font.pixelSize: Design.s(13); color: window.colCyan }
                            MouseArea { id: pullArea; anchors.fill: parent; hoverEnabled: true; cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: GitBackend.pull() }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Quick External Tools
                    Row {
                        spacing: Design.s(4)
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            width: termRow.implicitWidth + Design.s(14)
                            height: Design.s(26)
                            radius: Design.s(6)
                            color: termArea.containsMouse ? Design.tint(Design.text, 0.12) : "transparent"
                            border.color: window.colBorder
                            border.width: 1

                            Row {
                                id: termRow
                                anchors.centerIn: parent
                                spacing: Design.s(5)
                                Text { text: "󰞷"; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: window.colFg }
                                Text { text: "Terminal"; font.family: Design.font.sans; font.pixelSize: Design.s(11); color: window.colFg }
                            }
                            MouseArea { id: termArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: GitBackend.openTerminal() }
                        }

                        Rectangle {
                            width: filesRow.implicitWidth + Design.s(14)
                            height: Design.s(26)
                            radius: Design.s(6)
                            color: filesArea.containsMouse ? Design.tint(Design.text, 0.12) : "transparent"
                            border.color: window.colBorder
                            border.width: 1

                            Row {
                                id: filesRow
                                anchors.centerIn: parent
                                spacing: Design.s(5)
                                Text { text: "󰉋"; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: window.colFg }
                                Text { text: "Files"; font.family: Design.font.sans; font.pixelSize: Design.s(11); color: window.colFg }
                            }
                            MouseArea { id: filesArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: GitBackend.openFileManager() }
                        }
                    }
                }
            }

            // ══════════════════════════════════════════════════════════════════
            // MAIN WORKSPACE (Left: Changes/History Sidebar, Right: Diff View)
            // ══════════════════════════════════════════════════════════════════
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.md)
                    spacing: Design.s(Design.space.md)

                    // ── LEFT SIDEBAR (Changes & History) ──────────────────────
                    // The two panels were butted against each other and against
                    // the window edge with square corners, so this was the only
                    // surface in the suite that did not look like the rest of
                    // it: Files and the monitor are rounded cards with room
                    // around them.
                    Rectangle {
                        Layout.preferredWidth: Design.s(320)
                        Layout.fillHeight: true
                        radius: Design.s(Design.radius.card)
                        color: window.colDark
                        border.color: window.colBorder
                        border.width: 1
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Top Sidebar Tab Switcher: [ Changes (N) ] [ History ]
                            Rectangle {
                                Layout.fillWidth: true
                                height: Design.s(36)
                                color: Design.tint(Design.ground, 0.8)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: window.colBorder
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 0

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        color: window.currentTab === 0 ? window.colDark : "transparent"
                                        border.color: window.currentTab === 0 ? window.colBlue : "transparent"
                                        border.width: window.currentTab === 0 ? 1 : 0

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Changes (" + GitBackend.changedFiles.length + ")"
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(12)
                                            font.bold: true
                                            color: window.currentTab === 0 ? window.colBlue : window.colDim
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.currentTab = 0
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        color: window.currentTab === 1 ? window.colDark : "transparent"
                                        border.color: window.currentTab === 1 ? window.colBlue : "transparent"
                                        border.width: window.currentTab === 1 ? 1 : 0

                                        Text {
                                            anchors.centerIn: parent
                                            text: "History"
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(12)
                                            font.bold: true
                                            color: window.currentTab === 1 ? window.colBlue : window.colDim
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.currentTab = 1
                                        }
                                    }
                                }
                            }

                            // Tab 0: Changes File List & Commit Box
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: window.currentTab === 0

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 0

                                    // Stage All / Unstage All Bar
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: Design.s(28)
                                        color: Design.tint(Design.ground, 0.40)

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 1
                                            color: window.colBorder
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(10)
                                            anchors.rightMargin: Design.s(10)

                                            Text {
                                                text: "Changed Files"
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(11)
                                                font.bold: true
                                                color: window.colDim
                                            }
                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: "Stage All"
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(10)
                                                color: window.colGreen
                                                opacity: window.hasRepo ? 1.0 : 0.45
                                                enabled: window.hasRepo
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: GitBackend.stageAll()
                                                }
                                            }
                                            Text { text: "•"; font.pixelSize: Design.s(8); color: window.colDim }
                                            Text {
                                                text: "Unstage All"
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(10)
                                                color: window.colRed
                                                opacity: window.hasRepo ? 1.0 : 0.45
                                                enabled: window.hasRepo
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: GitBackend.unstageAll()
                                                }
                                            }
                                        }
                                    }

                                    // Changed Files ListView
                                    ListView {
                                        id: changedList
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        model: GitBackend.changedFiles
                                        spacing: 1

                                        delegate: Rectangle {
                                            id: fileCard
                                            width: changedList.width
                                            height: Design.s(32)
                                            color: isSelected ? Design.tint(Design.accent, 0.18) : (fArea.containsMouse ? Design.tint(Design.text, 0.05) : "transparent")

                                            readonly property bool isSelected: GitBackend.selectedFile === modelData.path

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Design.s(8)
                                                anchors.rightMargin: Design.s(8)
                                                spacing: Design.s(8)

                                                // Staged Checkbox
                                                Rectangle {
                                                    width: Design.s(16)
                                                    height: Design.s(16)
                                                    radius: Design.s(3)
                                                    color: modelData.isStaged ? window.colGreen : "transparent"
                                                    border.color: modelData.isStaged ? window.colGreen : window.colDim
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "✓"
                                                        font.pixelSize: Design.s(10)
                                                        font.bold: true
                                                        color: Design.accentText
                                                        visible: modelData.isStaged
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData.isStaged) GitBackend.unstageFile(modelData.path);
                                                            else GitBackend.stageFile(modelData.path);
                                                        }
                                                    }
                                                }

                                                // File Status Badge (M, A, D)
                                                Text {
                                                    text: modelData.status === "added" ? "A" : (modelData.status === "deleted" ? "D" : "M")
                                                    font.family: Design.font.mono
                                                    font.pixelSize: Design.s(10)
                                                    font.bold: true
                                                    color: modelData.status === "added" ? window.colGreen : (modelData.status === "deleted" ? window.colRed : window.colOrange)
                                                }

                                                // File Name
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.path
                                                    font.family: Design.font.mono
                                                    font.pixelSize: Design.s(11)
                                                    color: fileCard.isSelected ? "#ffffff" : window.colFg
                                                    elide: Text.ElideMiddle
                                                }
                                            }

                                            MouseArea {
                                                id: fArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: GitBackend.selectFile(modelData.path)
                                            }
                                        }
                                    }

                                    // Bottom GitHub Desktop Commit Box
                                    // The commit box is the foot of the panel,
                                    // so its separator is on top of it.
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: Design.s(130)
                                        color: Design.tint(Design.ground, 0.90)

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            height: 1
                                            color: window.colBorder
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Design.s(10)
                                            spacing: Design.s(6)

                                            // Summary (Required)
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: Design.s(28)
                                                radius: Design.s(4)
                                                color: window.colBg
                                                opacity: window.hasRepo ? 1.0 : 0.5
                                                border.color: sumInput.activeFocus ? window.colBlue : window.colBorder
                                                border.width: 1

                                                TextInput {
                                                    id: sumInput
                                                    // The commit button was
                                                    // gated on having a
                                                    // repository and these two
                                                    // fields were not, so with
                                                    // none open you could type a
                                                    // whole commit message into
                                                    // a box that had nowhere to
                                                    // send it.
                                                    enabled: window.hasRepo
                                                    anchors.fill: parent
                                                    anchors.margins: Design.s(6)
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(11)
                                                    color: window.colFg
                                                    selectByMouse: true
                                                    clip: true

                                                    Text {
                                                        text: "Summary (required)"
                                                        font.family: Design.font.sans
                                                        font.pixelSize: Design.s(11)
                                                        color: window.colDim
                                                        visible: !sumInput.text && !sumInput.activeFocus
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }

                                            // Description (Optional)
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                radius: Design.s(4)
                                                color: window.colBg
                                                opacity: window.hasRepo ? 1.0 : 0.5
                                                border.color: descInput.activeFocus ? window.colBlue : window.colBorder
                                                border.width: 1

                                                TextArea {
                                                    id: descInput
                                                    enabled: window.hasRepo
                                                    anchors.fill: parent
                                                    anchors.margins: Design.s(4)
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(11)
                                                    color: window.colFg
                                                    selectByMouse: true
                                                    background: null
                                                    wrapMode: TextEdit.Wrap

                                                    Text {
                                                        text: "Description"
                                                        font.family: Design.font.sans
                                                        font.pixelSize: Design.s(11)
                                                        color: window.colDim
                                                        visible: !descInput.text && !descInput.activeFocus
                                                    }
                                                }
                                            }

                                            // Commit Action Button
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: Design.s(28)
                                                radius: Design.s(5)
                                                readonly property bool ready: window.hasRepo && sumInput.text.trim().length > 0
                                                color: ready ? (commitArea.containsMouse ? Qt.lighter(window.colBlue, 1.1) : window.colBlue) : Design.tint(Design.accent, 0.20)
                                                enabled: ready

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: window.hasRepo ? "Commit to " + GitBackend.branchName
                                                                         : "No repository open"
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(11)
                                                    font.bold: true
                                                    color: parent.ready ? Design.accentText : window.colDim
                                                }

                                                MouseArea {
                                                    id: commitArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: {
                                                        let fullMsg = sumInput.text.trim();
                                                        if (descInput.text.trim()) fullMsg += "\n\n" + descInput.text.trim();
                                                        GitBackend.commit(fullMsg);
                                                        sumInput.text = "";
                                                        descInput.text = "";
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Tab 1: History Commit List
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: window.currentTab === 1

                                ListView {
                                    id: historyList
                                    anchors.fill: parent
                                    clip: true
                                    model: GitBackend.commitHistory
                                    spacing: 1

                                    delegate: Rectangle {
                                        width: historyList.width
                                        height: Design.s(52)
                                        color: hArea.containsMouse ? Design.tint(Design.text, 0.05) : "transparent"
                                        border.color: Design.tint(Design.accent, 0.08)
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Design.s(8)
                                            spacing: Design.s(3)

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.message || "Commit"
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(11)
                                                    font.bold: true
                                                    color: window.colFg
                                                    elide: Text.ElideRight
                                                }
                                                Rectangle {
                                                    width: Design.s(54); height: Design.s(18); radius: Design.s(3)
                                                    color: Design.tint(Design.accent, 0.15)
                                                    Text { anchors.centerIn: parent; text: modelData.hash || ""; font.family: Design.font.mono; font.pixelSize: Design.s(9); color: window.colBlue }
                                                }
                                            }

                                            Text {
                                                text: (modelData.author || "User") + " • " + (modelData.date || "")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(10)
                                                color: window.colDim
                                            }
                                        }

                                        MouseArea {
                                            id: hArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── RIGHT MAIN PANEL (File Diff Viewer) ───────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Design.s(Design.radius.card)
                        color: window.colDark
                        border.color: window.colBorder
                        border.width: 1
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Diff File Header Bar
                            // Names the file being shown, and nothing else. It
                            // used to state the panel's empty condition too —
                            // "Open a repository" — directly above the centred
                            // empty state reading "No Git Repository Open", so
                            // the same sentence was on screen twice in two
                            // wordings. One message, in the middle, where there
                            // is room for it.
                            Rectangle {
                                Layout.fillWidth: true
                                height: Design.s(36)
                                visible: GitBackend.selectedFile !== ""
                                color: Design.tint(Design.ground, 0.8)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: window.colBorder
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Design.s(14)
                                    anchors.rightMargin: Design.s(14)
                                    spacing: Design.s(8)

                                    Text {
                                        text: "󰈙"
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(13)
                                        color: window.colBlue
                                    }

                                    Text {
                                        text: GitBackend.selectedFile
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(12)
                                        font.bold: true
                                        color: window.colFg
                                        Layout.fillWidth: true
                                        elide: Text.ElideMiddle
                                    }

                                    Text {
                                        text: GitBackend.statusSummary
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(11)
                                        color: window.colDim
                                    }
                                }
                            }

                            // Diff Lines ListView
                            ListView {
                                id: diffList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: GitBackend.currentDiff

                                delegate: Rectangle {
                                    width: diffList.width
                                    height: Math.max(20, diffLineText.implicitHeight + 4)

                                    color: {
                                        if (modelData.type === "add") return Design.tint(Design.ok, 0.14);
                                        if (modelData.type === "del") return Design.tint(Design.danger, 0.16);
                                        if (modelData.type === "header") return Design.tint(Design.accent, 0.12);
                                        return "transparent";
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0

                                        // Old Line Num
                                        Text {
                                            width: Design.s(42)
                                            text: modelData.oldLine || ""
                                            horizontalAlignment: Text.AlignRight
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(11)
                                            color: window.colDim
                                            rightPadding: 8
                                        }

                                        // New Line Num
                                        Text {
                                            width: Design.s(42)
                                            text: modelData.newLine || ""
                                            horizontalAlignment: Text.AlignRight
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(11)
                                            color: window.colDim
                                            rightPadding: 8
                                        }

                                        // Line Content
                                        Text {
                                            id: diffLineText
                                            Layout.fillWidth: true
                                            text: modelData.text || ""
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(11)
                                            color: {
                                                if (modelData.type === "add") return window.colGreen;
                                                if (modelData.type === "del") return window.colRed;
                                                if (modelData.type === "header") return window.colBlue;
                                                return window.colFg;
                                            }
                                        }
                                    }
                                }

                                // Empty State when clean
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: Design.s(12)
                                    visible: GitBackend.currentDiff.length === 0

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "󰊢"
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(48)
                                        color: window.colDim
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: GitBackend.isRepo ? "No changes to display" : "No Git Repository Open"
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(14)
                                        font.bold: true
                                        color: window.colFg
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: GitBackend.isRepo ? "Working directory is clean" : "Select a repository from the top menu or open a folder."
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(12)
                                        color: window.colDim
                                    }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════════════════════════════
                // REPOSITORY SELECTOR DROPDOWN POPUP
                // ══════════════════════════════════════════════════════════════
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.leftMargin: Design.s(12)
                    width: Design.s(380)
                    height: Design.s(280)
                    radius: Design.s(8)
                    color: window.colHeader
                    border.color: window.colBlue
                    border.width: 1
                    z: 50
                    visible: window.repoDropdownOpen

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Design.s(10)
                        spacing: Design.s(8)

                        Text {
                            text: "Switch Local Repository"
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(12)
                            font.bold: true
                            color: window.colBlue
                        }

                        // Path Input Field
                        Rectangle {
                            Layout.fillWidth: true
                            height: Design.s(30)
                            radius: Design.s(5)
                            color: window.colBg
                            border.color: window.colBorder
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(6)
                                spacing: Design.s(6)

                                TextInput {
                                    id: customPathInput
                                    Layout.fillWidth: true
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(11)
                                    color: window.colFg
                                    text: GitBackend.repoPath
                                    selectByMouse: true
                                    onAccepted: {
                                        GitBackend.openRepo(customPathInput.text);
                                        window.repoDropdownOpen = false;
                                    }
                                }

                                Rectangle {
                                    width: Design.s(44); height: Design.s(20); radius: Design.s(3)
                                    color: window.colBlue
                                    Text { anchors.centerIn: parent; text: "Open"; font.bold: true; font.pixelSize: Design.s(10); color: "#101014" }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            GitBackend.openRepo(customPathInput.text);
                                            window.repoDropdownOpen = false;
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            text: "Discovered Repositories:"
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(10)
                            color: window.colDim
                        }

                        // Discovered Repos List
                        ListView {
                            id: discoveredList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: GitBackend.discoverRepos()

                            delegate: Rectangle {
                                width: discoveredList.width
                                height: Design.s(32)
                                radius: Design.s(4)
                                color: discArea.containsMouse ? Design.tint(Design.accent, 0.20) : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Design.s(6)
                                    spacing: Design.s(8)

                                    Text { text: "󰊢"; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: window.colBlue }
                                    Text { text: modelData.name; font.family: Design.font.sans; font.pixelSize: Design.s(11); font.bold: true; color: window.colFg }
                                    Text { text: modelData.path; font.family: Design.font.mono; font.pixelSize: Design.s(9); color: window.colDim; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                }

                                MouseArea {
                                    id: discArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        GitBackend.openRepo(modelData.path);
                                        window.repoDropdownOpen = false;
                                    }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════════════════════════════
                // BRANCH SWITCHER DROPDOWN POPUP
                // ══════════════════════════════════════════════════════════════
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.leftMargin: Design.s(180)
                    width: Design.s(260)
                    height: Design.s(220)
                    radius: Design.s(8)
                    color: window.colHeader
                    border.color: window.colGreen
                    border.width: 1
                    z: 50
                    visible: window.branchDropdownOpen

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Design.s(10)
                        spacing: Design.s(8)

                        Text {
                            text: "Switch Branch"
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(12)
                            font.bold: true
                            color: window.colGreen
                        }

                        ListView {
                            id: branchList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: GitBackend.branches

                            delegate: Rectangle {
                                width: branchList.width
                                height: Design.s(28)
                                radius: Design.s(4)
                                color: modelData === GitBackend.branchName ? Design.tint(Design.ok, 0.25) : (bArea.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Design.s(6)
                                    spacing: Design.s(6)

                                    Text { text: ""; font.family: Design.font.mono; font.pixelSize: Design.s(11); color: window.colGreen }
                                    Text { text: modelData; font.family: Design.font.mono; font.pixelSize: Design.s(11); font.bold: modelData === GitBackend.branchName; color: window.colFg; Layout.fillWidth: true }
                                    Text { text: "✓"; font.pixelSize: Design.s(11); font.bold: true; color: window.colGreen; visible: modelData === GitBackend.branchName }
                                }

                                MouseArea {
                                    id: bArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        GitBackend.switchBranch(modelData);
                                        window.branchDropdownOpen = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
