import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import B1air.Daemon
import Quickshell.Io
import "../Ui"
import "../Services"
import "../Services" as Services

// =============================================================================
// macOS-style Expanding Spotlight Search (Dynamic Apps, Math, System Actions)
// =============================================================================

PopupShell {
    id: window
    framed: false

    property string query: ""
    property int selectedIndex: 0
    property string calcResult: ""
    readonly property var systemApps: window.systemAppsMapped
    property string smartType: "calc"

    readonly property bool hasResults: window.query.trim().length > 0 || window.calcResult !== ""

    // ── Dynamic Apps Scanner ─────────────────────────────────────────────────
    // The scan lives in Services/Apps, shared with Launchpad; only the mapping
    // to this launcher's row shape is here.
    readonly property var systemAppsMapped: Services.Apps.list.map(app => ({
        name: app.name,
        desc: app.comment || I18n.tr("Installed Application"),
        icon: app.icon || "\u{f108}",
        app_id: app.icon || "",
        cmd: app.exec,
        cat: "Applications",
        terminal: app.terminal === true
    }))


    // ── Core System Actions ──────────────────────────────────────────────────
    readonly property var baseApps: [
        { name: "Terminal", desc: I18n.tr("Native b1air terminal emulator"), icon: "\u{f120}", cmd: "b1air-term", cat: "System" },
        { name: "Launchpad", desc: I18n.tr("Full application launcher"), icon: "\u{f009}", cmd: "b1air-shell toggle launchpad", cat: "System" },
        { name: "File Manager", desc: I18n.tr("Native b1air file manager"), icon: "\u{f07b}", cmd: "b1air-files", cat: "System" },
        { name: "Settings", desc: I18n.tr("System & Desktop Settings"), icon: "\u{f013}", cmd: "b1air-shell toggle settings", cat: "System" },
        { name: "Control Center", desc: I18n.tr("Quick toggles & notifications"), icon: "\u{f0f3}", cmd: "b1air-shell toggle control", cat: "System" },
        { name: "Clipboard History", desc: I18n.tr("Search clipboard history & snippets"), icon: "\u{f0ea}", cmd: "b1air-shell toggle clipboard", cat: "Utilities" },
        { name: "Calendar & Weather", desc: I18n.tr("View date, calendar and forecasts"), icon: "\u{f073}", cmd: "b1air-shell toggle calendar", cat: "Utilities" },
        { name: "Color Dropper", desc: I18n.tr("Pick screen color to clipboard"), icon: "\u{f1fb}", cmd: "b1air-daemon color-picker", cat: "Utilities" },
        { name: "Lock Screen", desc: I18n.tr("Lock current user session"), icon: "\u{f023}", cmd: "b1air-daemon power lock", cat: "Session" },
        { name: "Power Menu", desc: I18n.tr("Shutdown, reboot, sleep options"), icon: "\u{f011}", cmd: "b1air-shell toggle session", cat: "Session" },
        { name: "Screenshot", desc: I18n.tr("Capture selected region"), icon: "\u{f030}", cmd: "b1air-daemon screenshot area", cat: "Utilities" },
        { name: "Task Manager", desc: I18n.tr("Native b1air system monitor"), icon: "\u{f080}", cmd: "b1air-monitor", cat: "System" }
    ]

    function evaluateMath(expr) {
        const clean = expr.trim();
        if (!/^[\d\s\+\-\*\/\%\(\)\.\,\^sqrtPIEsincoztan]+$/i.test(clean)) return "";
        if (!/[\+\-\*\/\%]|sqrt|sin|cos|tan/i.test(clean)) return "";
        try {
            let sanitized = clean.replace(/sqrt\(([^)]+)\)/gi, "Math.sqrt($1)")
                                 .replace(/sin\(([^)]+)\)/gi, "Math.sin($1)")
                                 .replace(/cos\(([^)]+)\)/gi, "Math.cos($1)")
                                 .replace(/tan\(([^)]+)\)/gi, "Math.tan($1)")
                                 .replace(/\^/g, "**")
                                 .replace(/\bPI\b/gi, "Math.PI")
                                 .replace(/\bE\b/gi, "Math.E");
            const res = Function('"use strict"; return (' + sanitized + ')')();
            if (typeof res === "number" && !isNaN(res) && isFinite(res)) {
                return (Math.round(res * 100000) / 100000).toString();
            }
        } catch (e) {}
        return "";
    }

    function evaluateSmart(expr) {
        const clean = expr.trim();
        if (!clean) return { result: "", type: "" };
        const mathRes = evaluateMath(clean);
        if (mathRes) {
            return { result: mathRes, type: "calc" };
        }
        return { result: "", type: "" };
    }

    onQueryChanged: {
        const smart = evaluateSmart(window.query);
        window.calcResult = smart.result;
        window.smartType = smart.type;
        window.selectedIndex = 0;
    }

    readonly property var allApps: window.baseApps.concat(window.systemApps)

    readonly property var filteredApps: {
        const q = window.query.trim().toLowerCase();
        if (!q) return [];
        return window.allApps.filter(a => {
            return a.name.toLowerCase().includes(q) ||
                   a.desc.toLowerCase().includes(q) ||
                   a.cat.toLowerCase().includes(q) ||
                   a.cmd.toLowerCase().includes(q);
        });
    }

    function cleanExec(cmd) {
        return cmd.replace(/%[a-zA-Z]/g, "").trim();
    }

    function safeLaunchCommand(cmd) {
        const value = (cmd || "").trim();
        const forbidden = [";", "&", "|", "`", "$", "<", ">", "\\", "\n", "\r", "(", ")", "{", "}", "[", "]", "*", "?", "!", "~"];
        if (!value || value.length > 512 || forbidden.some(c => value.includes(c))) return false;
        Sway.command("exec " + value);
        return true;
    }

    function execute(item) {
        window.close();
        let cmd = "";
        if (typeof item === "string") {
            cmd = item.trim();
        } else if (item && item.cmd) {
            cmd = item.cmd.trim();
        }
        if (!cmd) return;

        cmd = cleanExec(cmd);
        safeLaunchCommand(cmd);
    }

    function getAppGlyph(name) {
        const n = (name || "").toLowerCase();
        if (n.includes("term") || n.includes("foot") || n.includes("bash") || n.includes("sh")) return "\u{f120}";
        if (n.includes("file") || n.includes("thunar") || n.includes("nemo") || n.includes("bulk")) return "\u{f07b}";
        if (n.includes("setting") || n.includes("pref") || n.includes("control")) return "\u{f013}";
        if (n.includes("cal") || n.includes("time") || n.includes("clock")) return "\u{f073}";
        if (n.includes("music") || n.includes("audio") || n.includes("sound") || n.includes("play")) return "\u{f001}";
        if (n.includes("browser") || n.includes("web") || n.includes("firefox") || n.includes("chrom")) return "\u{f269}";
        if (n.includes("code") || n.includes("edit") || n.includes("vim") || n.includes("text")) return "\u{f121}";
        if (n.includes("spotlight") || n.includes("search") || n.includes("find")) return "\u{f002}";
        if (n.includes("drop") || n.includes("color") || n.includes("picker")) return "\u{f1fb}";
        if (n.includes("task") || n.includes("monitor") || n.includes("btop") || n.includes("top")) return "\u{f080}";
        if (n.includes("lock")) return "\u{f023}";
        if (n.includes("power") || n.includes("shut") || n.includes("exit")) return "\u{f011}";
        if (n.includes("clip") || n.includes("copy")) return "\u{f0ea}";
        if (n.includes("cmake") || n.includes("build") || n.includes("dev")) return "\u{f085}";
        if (n.includes("avahi") || n.includes("vnc") || n.includes("ssh") || n.includes("net")) return "\u{f0317}";
        return "\u{f108}";
    }

    function getAppColor(name) {
        const n = (name || "").toLowerCase();
        if (n.includes("term") || n.includes("foot")) return Design.green;
        if (n.includes("file") || n.includes("thunar") || n.includes("bulk")) return Design.peach;
        if (n.includes("setting") || n.includes("pref") || n.includes("control")) return Design.blue;
        if (n.includes("cal") || n.includes("time") || n.includes("clock")) return Design.red;
        if (n.includes("music") || n.includes("audio")) return Design.mauve;
        if (n.includes("browser") || n.includes("web") || n.includes("firefox")) return Design.peach;
        if (n.includes("code") || n.includes("vim")) return Design.teal;
        if (n.includes("spotlight") || n.includes("search")) return Design.sapphire;
        if (n.includes("cmake")) return Design.yellow;
        return Design.accent;
    }

    function copyResult() {
        if (window.calcResult) {
            Quickshell.execDetached(["wl-copy", window.calcResult]);
            window.close();
        }
    }

    Component.onCompleted: {
        Qt.callLater(() => searchInput.forceActiveFocus());
    }
    onActiveFocusChanged: {
        if (activeFocus) Qt.callLater(() => searchInput.forceActiveFocus());
    }
    onVisibleChanged: {
        if (visible) Qt.callLater(() => searchInput.forceActiveFocus());
    }

    // ── Floating Spotlight Card (Expands smoothly when results appear) ──────
    Rectangle {
        id: spotlightCard
        anchors.centerIn: parent
        width: parent.width
        height: window.hasResults ? Design.s(450) : Design.s(58)
        radius: Design.s(16)
        color: Design.tint(Design.ground, 0.94)
        border.color: searchInput.activeFocus ? Design.tint(Design.accent, 0.5) : Design.glassBorder
        border.width: 1
        clip: true

        Behavior on height {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── 1. Top Search Bar (macOS Pill style) ───────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(58)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(18)
                    anchors.rightMargin: Design.s(18)
                    spacing: Design.s(12)

                    Icon {
                        text: "\u{f002}" // Search magnifying glass
                        role: "body"
                        color: searchInput.activeFocus ? Design.accent : Design.textDim
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Design.font.sans
                        font.weight: Design.weight.medium
                        font.pixelSize: Design.s(17)
                        color: Design.text
                        selectByMouse: true
                        clip: true

                        text: window.query
                        onTextChanged: window.query = text

                        Keys.onEscapePressed: window.close()
                        Keys.onDownPressed: {
                            const total = window.calcResult ? window.filteredApps.length + 1 : window.filteredApps.length;
                            if (total > 0) window.selectedIndex = (window.selectedIndex + 1) % total;
                        }
                        Keys.onUpPressed: {
                            const total = window.calcResult ? window.filteredApps.length + 1 : window.filteredApps.length;
                            if (total > 0) window.selectedIndex = (window.selectedIndex - 1 + total) % total;
                        }
                        Keys.onReturnPressed: {
                            if (window.calcResult && window.selectedIndex === 0) {
                                window.copyResult();
                            } else {
                                const adjIdx = window.calcResult ? window.selectedIndex - 1 : window.selectedIndex;
                                if (adjIdx >= 0 && adjIdx < window.filteredApps.length) {
                                    window.execute(window.filteredApps[adjIdx]);
                                } else if (window.query.trim()) {
                                    window.execute(window.query.trim());
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Search apps, commands, or calculate (e.g. 24 * 7)...")
                            color: Design.textDim
                            font: parent.font
                            visible: !searchInput.text
                        }
                    }

                    // Clear button
                    IconButton {
                        visible: searchInput.text.length > 0
                        icon: "\u{f00d}"
                        role: "caption"
                        onClicked: {
                            searchInput.text = "";
                            searchInput.forceActiveFocus();
                        }
                    }

                    // ESC shortcut badge
                    Badge {
                        text: "ESC"
                        tone: Design.textDim
                    }
                }
            }

            // ── Separator Line ─────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Design.tint(Design.line, 0.4)
                visible: window.hasResults
            }

            // ── 2. Results Container ───────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: window.hasResults

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(12)
                    spacing: Design.s(8)

                    // ── Math & Calculator Result Card ──────────────────────────
                    Rectangle {
                        visible: window.calcResult !== ""
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(48)
                        radius: Design.s(Design.radius.ctl)
                        color: window.selectedIndex === 0 ? Design.tint(Design.accent, 0.16) : Design.sunken
                        border.color: window.selectedIndex === 0 ? Design.accent : Design.glassBorder
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Design.s(14)
                            anchors.rightMargin: Design.s(14)
                            spacing: Design.s(12)

                            Icon {
                                text: "\u{f1ec}" // Calculator
                                color: Design.accent
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Label {
                                    text: window.calcResult
                                    weight: Design.weight.bold
                                    color: Design.accent
                                    role: "subhead"
                                }
                                Label {
                                    text: I18n.tr("Calculation • Press Enter to copy")
                                    role: "caption"
                                    dim: true
                                }
                            }

                            Badge {
                                text: I18n.tr("↵ Copy")
                                tone: Design.accent
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: window.copyResult()
                        }
                    }

                    // ── Applications & Commands List ───────────────────────────
                    ListView {
                        id: resultsView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        reuseItems: true
                        model: window.filteredApps

                        delegate: Rectangle {
                            id: resultRow
                            required property var modelData
                            required property int index

                            readonly property bool isSelected: {
                                const targetIdx = window.calcResult ? window.selectedIndex - 1 : window.selectedIndex;
                                return targetIdx === index;
                            }

                            width: resultsView.width
                            height: Design.s(48)
                            radius: Design.s(Design.radius.ctl)
                            color: isSelected ? Design.tint(Design.accent, 0.16) : (rowHover.containsMouse ? Design.tint(Design.line, 0.2) : "transparent")
                            border.color: isSelected ? Design.tint(Design.accent, 0.4) : "transparent"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(12)
                                anchors.rightMargin: Design.s(12)
                                spacing: Design.s(12)

                                // App Icon
                                Rectangle {
                                    width: Design.s(32)
                                    height: Design.s(32)
                                    radius: Design.s(8)
                                    color: Design.tint(window.getAppColor(modelData.name), isSelected ? 0.25 : 0.14)
                                    border.color: isSelected ? window.getAppColor(modelData.name) : Design.tint(window.getAppColor(modelData.name), 0.3)
                                    border.width: 1

                                    Icon {
                                        anchors.centerIn: parent
                                        text: window.getAppGlyph(modelData.name)
                                        role: "caption"
                                        color: window.getAppColor(modelData.name)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Label {
                                        text: modelData.name
                                        weight: isSelected ? Design.weight.bold : Design.weight.medium
                                        color: isSelected ? Design.accent : Design.text
                                    }
                                    Label {
                                        text: modelData.desc
                                        role: "caption"
                                        dim: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Badge {
                                    text: I18n.tr(modelData.cat || "App")
                                    tone: isSelected ? Design.accent : Design.textDim
                                }
                            }

                            MouseArea {
                                id: rowHover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: window.execute(modelData)
                            }
                        }
                    }

                    // ── Zero Search Results State ──────────────────────────────
                    Item {
                        visible: window.filteredApps.length === 0 && window.calcResult === ""
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Design.s(Design.space.xs)
                            Icon {
                                Layout.alignment: Qt.AlignHCenter
                                text: "\u{f002}"
                                role: "title"
                                color: Design.textDim
                            }
                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: I18n.tr("No matching apps or commands")
                                weight: Design.weight.semibold
                            }
                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: I18n.tr("Press Enter to run \"%1\" as a terminal command", window.query)
                                role: "caption"
                                dim: true
                            }
                        }
                    }
                }
            }
        }
    }
}
