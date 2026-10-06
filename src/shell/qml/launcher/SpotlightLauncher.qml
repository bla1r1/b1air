import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import B1air.Daemon
import "../Ui"
import "../Services"
import "../Services" as Services
import "../settings" as SettingsIndex

// =============================================================================
// Spotlight: one field, and what it finds in sections — a sum or a unit
// conversion, applications, Settings pages, files in the home folder, the
// desktop's own commands — with the selected result previewed beside the
// list. Enter opens it; a calculation or conversion is copied.
// =============================================================================

PopupShell {
    id: window
    framed: false

    property string query: ""
    property int selectedIndex: 0
    readonly property bool hasQuery: window.query.trim().length > 0

    // ── Sources ──────────────────────────────────────────────────────────────

    // The desktop's own commands, with what they do.
    readonly property var commands: [
        { name: I18n.tr("Launchpad"), desc: I18n.tr("Full application launcher"), glyph: "\u{f009}", cmd: "b1air-shell toggle launchpad" },
        { name: I18n.tr("Control Center"), desc: I18n.tr("Quick toggles & notifications"), glyph: "\u{f0f3}", cmd: "b1air-shell toggle control" },
        { name: I18n.tr("Clipboard History"), desc: I18n.tr("Search clipboard history & snippets"), glyph: "\u{f0ea}", cmd: "b1air-shell toggle clipboard" },
        { name: I18n.tr("Calendar & Weather"), desc: I18n.tr("View date, calendar and forecasts"), glyph: "\u{f073}", cmd: "b1air-shell toggle calendar" },
        { name: I18n.tr("Color Dropper"), desc: I18n.tr("Pick screen color to clipboard"), glyph: "\u{f1fb}", cmd: "b1air-daemon color-picker" },
        { name: I18n.tr("Screenshot"), desc: I18n.tr("Capture selected region"), glyph: "\u{f030}", cmd: "b1air-daemon screenshot area" },
        { name: I18n.tr("Lock Screen"), desc: I18n.tr("Lock current user session"), glyph: "\u{f023}", cmd: "b1air-daemon power lock" },
        { name: I18n.tr("Power Menu"), desc: I18n.tr("Shutdown, reboot, sleep options"), glyph: "\u{f011}", cmd: "b1air-shell toggle session" }
    ]

    SettingsIndex.SettingsPages { id: settingsPages }

    // ── Calculator and units ─────────────────────────────────────────────────

    function evaluateMath(expr) {
        const clean = expr.trim().replace(/,/g, ".");
        if (!/^[\d\s\+\-\*\/\%\(\)\.\^a-z]+$/i.test(clean)) return "";
        if (!/[\+\-\*\/\%\^]|sqrt|sin|cos|tan/i.test(clean)) return "";
        if (/[a-z]/i.test(clean.replace(/sqrt|sin|cos|tan|pi|\be\b/gi, ""))) return "";
        try {
            const sanitized = clean.replace(/sqrt\(/gi, "Math.sqrt(").replace(/sin\(/gi, "Math.sin(")
                                   .replace(/cos\(/gi, "Math.cos(").replace(/tan\(/gi, "Math.tan(")
                                   .replace(/\^/g, "**").replace(/\bpi\b/gi, "Math.PI").replace(/\be\b/gi, "Math.E");
            const res = Function('"use strict"; return (' + sanitized + ')')();
            if (typeof res === "number" && isFinite(res)) return window.number(res);
        } catch (e) {}
        return "";
    }

    function number(v) {
        return Number(Math.round(v * 1e6) / 1e6).toLocaleString(I18n.locale, "f", 6).replace(/[.,]?0+$/, "");
    }

    // "10 km in mi", "100 f to c", "5 gb в mib": a factor to a base unit per
    // kind, temperatures by formula.
    readonly property var units: ({
        // length (m)
        mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], km: ["len", 1000],
        in: ["len", 0.0254], ft: ["len", 0.3048], yd: ["len", 0.9144], mi: ["len", 1609.344],
        // mass (kg)
        mg: ["mass", 1e-6], g: ["mass", 0.001], kg: ["mass", 1], t: ["mass", 1000], oz: ["mass", 0.028349523125], lb: ["mass", 0.45359237],
        // volume (l)
        ml: ["vol", 0.001], l: ["vol", 1], gal: ["vol", 3.785411784], floz: ["vol", 0.0295735295625],
        // data (bytes)
        b: ["data", 1], kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12],
        kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
        // time (s)
        ms: ["time", 0.001], s: ["time", 1], min: ["time", 60], h: ["time", 3600], d: ["time", 86400], wk: ["time", 604800],
        // speed (m/s)
        kmh: ["speed", 1 / 3.6], mph: ["speed", 0.44704], mps: ["speed", 1], kn: ["speed", 0.514444],
        // temperature
        c: ["temp", 0], f: ["temp", 0], k: ["temp", 0]
    })
    function convert(expr) {
        const m = expr.trim().toLowerCase().replace(/°/g, "").replace("km/h", "kmh").replace("m/s", "mps")
                      .match(/^(-?[\d.,]+)\s*([a-z]+)\s+(?:in|to|в|у|into)\s+([a-z]+)$/);
        if (!m) return "";
        const v = parseFloat(m[1].replace(",", ".")), a = window.units[m[2]], b = window.units[m[3]];
        if (isNaN(v) || !a || !b || a[0] !== b[0]) return "";
        let out;
        if (a[0] === "temp") {
            const toC = { c: x => x, f: x => (x - 32) * 5 / 9, k: x => x - 273.15 };
            const fromC = { c: x => x, f: x => x * 9 / 5 + 32, k: x => x + 273.15 };
            out = fromC[m[3]](toC[m[2]](v));
        } else {
            out = v * a[1] / b[1];
        }
        return window.number(out) + " " + m[3];
    }

    // ── Files ────────────────────────────────────────────────────────────────
    // Names in the home folder, five levels deep, hidden ones left out — a
    // second after typing stops, and at most a second and a half of looking.
    property var fileHits: []
    Timer {
        id: fileDelay
        interval: 220
        onTriggered: {
            const q = window.query.trim();
            if (q.length < 2 || window.calcResult !== "") { window.fileHits = []; return; }
            fileFind.running = false;
            fileFind.command = ["sh", "-c",
                "cd \"$HOME\" && timeout 1.5 find . -maxdepth 5 -not -path '*/.*' -iname \"*$1*\" -print 2>/dev/null | head -n 24",
                "sh", q];
            fileFind.running = true;
        }
    }
    Process {
        id: fileFind
        stdout: StdioCollector {
            onStreamFinished: {
                const home = Quickshell.env("HOME");
                window.fileHits = this.text.split("\n").filter(l => l.length > 2)
                    .map(l => home + l.slice(1));
            }
        }
    }

    // ── Results ──────────────────────────────────────────────────────────────

    readonly property string calcResult: window.hasQuery ? (window.evaluateMath(window.query) || window.convert(window.query)) : ""

    onQueryChanged: {
        window.selectedIndex = 0;
        window.fileHits = [];
        fileDelay.restart();
    }

    function matches(q, ...fields) {
        return fields.some(f => String(f || "").toLowerCase().includes(q));
    }

    // One flat list, in sections, for the keyboard to walk.
    readonly property var results: {
        const q = window.query.trim().toLowerCase();
        if (!q) return [];
        const out = [];
        if (window.calcResult !== "")
            out.push({ section: I18n.tr("Calculator"), kind: "calc", title: window.calcResult,
                       sub: window.query.trim(), glyph: "\u{f1ec}" });

        const apps = Services.Apps.list.filter(a => window.matches(q, a.name, a.comment, a.exec, a.category));
        // What starts with the words first, then the rest.
        apps.sort((x, y) => (y.name.toLowerCase().startsWith(q) ? 1 : 0) - (x.name.toLowerCase().startsWith(q) ? 1 : 0));
        for (const a of apps.slice(0, 6))
            out.push({ section: I18n.tr("Applications"), kind: "app", title: a.name,
                       sub: a.comment || "", image: Services.Apps.iconSource(a.iconPath || a.icon), cmd: a.exec, terminal: a.terminal === true });

        for (const p of settingsPages.list.filter(p => !p.isHeader && window.matches(q, p.label, p.desc, p.tags, p.id)).slice(0, 4))
            out.push({ section: I18n.tr("Settings"), kind: "setting", title: p.label, sub: p.desc, glyph: p.icon, page: p.id });

        for (const f of window.fileHits.slice(0, 8)) {
            const name = f.split("/").pop();
            out.push({ section: I18n.tr("Files"), kind: "file", title: name,
                       sub: f.slice(0, f.length - name.length - 1).replace(Quickshell.env("HOME"), "~"), path: f,
                       glyph: window.fileGlyph(name),
                       // A picture or a video by its cached thumbnail.
                       image: window.isImage(f) || window.isVideo(f) ? "image://thumb/" + encodeURIComponent(f) : "" });
        }

        for (const c of window.commands.filter(c => window.matches(q, c.name, c.desc)))
            out.push({ section: I18n.tr("Commands"), kind: "command", title: c.name, sub: c.desc, glyph: c.glyph, cmd: c.cmd });

        if (out.length === 0)
            out.push({ section: I18n.tr("Commands"), kind: "run", title: I18n.tr("Run “%1”", window.query.trim()),
                       sub: I18n.tr("As a command"), glyph: "\u{f120}", cmd: window.query.trim() });
        return out;
    }
    readonly property var selected: window.results[Math.min(window.selectedIndex, window.results.length - 1)] || null

    function fileGlyph(name) {
        const ext = (name.split(".").length > 1 ? name.split(".").pop() : "").toLowerCase();
        if (["png", "jpg", "jpeg", "webp", "gif", "svg", "heic", "bmp"].includes(ext)) return "\u{f03e}";
        if (["mp3", "flac", "ogg", "opus", "m4a", "wav"].includes(ext)) return "\u{f001}";
        if (["mp4", "mkv", "webm", "mov", "avi"].includes(ext)) return "\u{f008}";
        if (["pdf"].includes(ext)) return "\u{f0226}";
        if (["zip", "tar", "gz", "zst", "7z", "xz"].includes(ext)) return "\u{f05c4}";
        if (ext === "") return "\u{f07b}";
        return "\u{f0214}";
    }
    function isImage(path) { return /\.(png|jpe?g|webp|gif|svg|bmp|heic|avif)$/i.test(path || ""); }
    function isVideo(path) { return /\.(mp4|mkv|webm|mov|avi)$/i.test(path || ""); }

    // ── Doing it ─────────────────────────────────────────────────────────────

    function safeLaunchCommand(cmd) {
        const value = (cmd || "").replace(/%[a-zA-Z]/g, "").trim();
        const forbidden = [";", "&", "|", "`", "$", "<", ">", "\\", "\n", "\r", "(", ")", "{", "}", "[", "]", "*", "?", "!", "~"];
        if (!value || value.length > 512 || forbidden.some(c => value.includes(c))) return false;
        Sway.command("exec " + value);
        return true;
    }

    function run(item) {
        if (!item) return;
        if (item.kind === "calc") {
            Quickshell.execDetached(["b1air-clip", "copy", "--", item.title.replace(/\s+[a-z]+$/, "")]);
            window.close();
            return;
        }
        window.close();
        if (item.kind === "setting") Quickshell.execDetached(["b1air-settings", item.page]);
        else if (item.kind === "file") Quickshell.execDetached(["xdg-open", item.path]);
        else if (item.kind === "app" && item.terminal) Quickshell.execDetached(["b1air-term", "-e", "sh", "-c", item.cmd.replace(/%[a-zA-Z]/g, "")]);
        else window.safeLaunchCommand(item.cmd);
    }

    // Reveal a file in Files instead of opening it (Ctrl+Enter).
    function reveal(item) {
        if (!item || item.kind !== "file") return;
        window.close();
        Quickshell.execDetached(["b1air-files", item.path]);
    }

    Component.onCompleted: {
        Qt.callLater(() => searchInput.forceActiveFocus());
        if (window.hasQuery) fileDelay.start();
    }
    onVisibleChanged: if (visible) Qt.callLater(() => searchInput.forceActiveFocus())

    // ═════════════════════════════════════════════════════════════════════════
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: parent.width
        // As tall as what it found, up to the window; at least room for the
        // preview.
        height: window.hasQuery
            ? Math.min(parent.height, Design.s(59) + Math.max(Design.s(320), list.contentHeight + Design.s(Design.space.sm) * 2))
            : Design.s(58)
        radius: Design.s(16)
        color: Design.glassBg
        border.color: Design.glassBorder
        border.width: 1
        clip: true
        Behavior on height { NumberAnimation { duration: Design.duration.fast + 50; easing.type: Easing.OutCubic } }

        // The lit top edge of the glass.
        Rectangle {
            visible: Design.translucent
            anchors.top: parent.top; anchors.topMargin: 1
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: parent.radius; anchors.rightMargin: parent.radius
            height: 1
            color: Design.glassEdge
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── The field ───────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(58)
                Layout.leftMargin: Design.s(18)
                Layout.rightMargin: Design.s(18)
                spacing: Design.s(12)

                Icon { text: "\u{f002}"; role: "subhead"; color: Design.textDim }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(20)
                    color: Design.text
                    selectByMouse: true
                    clip: true
                    text: window.query
                    onTextChanged: window.query = text

                    Keys.onEscapePressed: window.close()
                    Keys.onDownPressed: if (window.results.length) window.selectedIndex = (window.selectedIndex + 1) % window.results.length
                    Keys.onUpPressed: if (window.results.length) window.selectedIndex = (window.selectedIndex - 1 + window.results.length) % window.results.length
                    Keys.onReturnPressed: event => {
                        if (event.modifiers & Qt.ControlModifier) window.reveal(window.selected);
                        else window.run(window.selected);
                    }
                    // Tab jumps to the next section.
                    Keys.onTabPressed: {
                        const cur = window.selected ? window.selected.section : "";
                        for (let i = 1; i <= window.results.length; i++) {
                            const j = (window.selectedIndex + i) % window.results.length;
                            if (window.results[j].section !== cur) { window.selectedIndex = j; return; }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Spotlight Search")
                        color: Design.textFaint
                        font: parent.font
                        visible: !searchInput.text
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.glassBorder; visible: window.hasQuery }

            // ── Results | preview ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: window.hasQuery
                spacing: 0

                ListView {
                    id: list
                    Layout.preferredWidth: parent.width * 0.55
                    Layout.fillHeight: true
                    Layout.margins: Design.s(Design.space.sm)
                    clip: true
                    model: window.results
                    currentIndex: window.selectedIndex
                    highlightMoveDuration: 0
                    ScrollBar.vertical: OverflowBar {}
                    section.property: "section"
                    section.delegate: Label {
                        required property string section
                        width: list.width
                        topPadding: Design.s(Design.space.sm)
                        bottomPadding: Design.s(2)
                        leftPadding: Design.s(Design.space.sm)
                        text: section
                        role: "caption"
                        weight: Design.weight.semibold
                        color: Design.textFaint
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool on: index === window.selectedIndex
                        width: list.width
                        height: Design.s(38)
                        radius: Design.s(7)
                        color: row.on ? Design.accent : (rowMa.containsMouse ? Design.glassHover : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Design.s(Design.space.sm)
                            anchors.rightMargin: Design.s(Design.space.sm)
                            spacing: Design.s(Design.space.sm)
                            Item {
                                Layout.preferredWidth: Design.s(22)
                                Layout.preferredHeight: Design.s(22)
                                IconImage {
                                    anchors.fill: parent
                                    visible: !!row.modelData.image
                                    source: row.modelData.image || ""
                                    mipmap: true
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    visible: !row.modelData.image
                                    text: row.modelData.glyph || ""
                                    color: row.on ? Design.accentText : Design.textDim
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                color: row.on ? Design.accentText : Design.text
                                weight: row.modelData.kind === "calc" ? Design.weight.semibold : Design.weight.regular
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.maximumWidth: list.width * 0.45
                                text: row.modelData.kind === "file" ? row.modelData.sub : ""
                                visible: text !== ""
                                role: "caption"
                                color: row.on ? Design.tint(Design.accentText, 0.75) : Design.textFaint
                                elide: Text.ElideMiddle
                            }
                        }
                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { window.selectedIndex = row.index; window.run(row.modelData); }
                            onEntered: window.selectedIndex = row.index
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Design.glassBorder }

                // The preview of what is selected.
                Item {
                    id: preview
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property var it: window.selected
                    readonly property bool picture: !!preview.it && preview.it.kind === "file"
                                                    && (window.isImage(preview.it.path) || window.isVideo(preview.it.path))

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - Design.s(Design.space.xl) * 2
                        spacing: Design.s(Design.space.md)
                        visible: !!preview.it
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: preview.picture ? parent.width : Design.s(88)
                            Layout.preferredHeight: preview.picture ? Design.s(160) : Design.s(88)
                            Image {
                                anchors.fill: parent
                                visible: preview.picture
                                // The picture itself; a video by a frame of it.
                                source: !preview.picture ? ""
                                      : window.isImage(preview.it.path) ? Paths.fileUrl(preview.it.path)
                                      : "image://thumb/" + encodeURIComponent(preview.it.path)
                                sourceSize: Qt.size(Design.s(400), Design.s(340))
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            IconImage {
                                anchors.fill: parent
                                visible: !preview.picture && !!preview.it && !!preview.it.image
                                source: preview.it ? (preview.it.image || "") : ""
                                mipmap: true
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: !preview.picture && !!preview.it && !preview.it.image
                                radius: Design.s(20)
                                color: Design.tint(Design.accent, 0.16)
                                Text {
                                    anchors.centerIn: parent
                                    text: preview.it ? (preview.it.glyph || "") : ""
                                    font.family: Design.font.icon
                                    font.pixelSize: Design.s(44)
                                    color: Design.accent
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: preview.it ? preview.it.title : ""
                            role: preview.it && preview.it.kind === "calc" ? "display" : "subhead"
                            weight: Design.weight.semibold
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: !preview.it ? ""
                                : preview.it.kind === "calc" ? "= " + preview.it.title + "\n" + preview.it.sub
                                : preview.it.sub
                            visible: text !== "" && !(preview.it && preview.it.kind === "calc")
                            dim: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            role: "caption"
                            color: Design.textFaint
                            text: !preview.it ? ""
                                : preview.it.kind === "calc" ? I18n.tr("Enter copies the result")
                                : preview.it.kind === "file" ? I18n.tr("Enter opens it, Ctrl+Enter shows it in Files")
                                : preview.it.kind === "setting" ? I18n.tr("Enter opens this page of Settings")
                                : I18n.tr("Enter opens it · Tab goes to the next section")
                        }
                    }
                }
            }
        }
    }
}
