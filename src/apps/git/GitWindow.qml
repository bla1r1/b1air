import QtQuick
import QtCore
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import Ui

ApplicationWindow {
    id: window

    // Colours for every stock control in the window — tooltips, scroll bars,
    // combo boxes, text fields — from the desktop palette. Left to the Basic
    // style they were its own: a pale-yellow tooltip, light-grey bars.
    palette.window: Design.surface
    palette.windowText: Design.text
    palette.base: Design.sunken
    palette.alternateBase: Design.raised
    palette.text: Design.text
    palette.button: Design.raised
    palette.buttonText: Design.text
    palette.brightText: Design.text
    palette.highlight: Design.accent
    palette.highlightedText: Design.accentText
    palette.toolTipBase: Design.raised
    palette.toolTipText: Design.text
    palette.placeholderText: Design.textFaint
    palette.light: Design.highest
    palette.midlight: Design.high
    palette.mid: Design.line
    palette.dark: Design.sunken
    palette.shadow: Design.ground
    title: GitBackend.repoName ? I18n.tr("Git — %1", GitBackend.repoName) : I18n.tr("Git")
    width: Design.s(1040)
    height: Design.s(680)
    // Low enough for a window tiled to half a small screen; the layout
    // follows the width from there (sidebar, toolbar cells, file lists).
    minimumWidth: 480
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
    // ── Right-click menus ──────────────────────────────────────────────────
    // One of each, at window level, handed the path it is about before it
    // opens. A Menu per list row would be a few hundred popups in History.
    // The suite's menu; disabled entries stay visible here, greyed, because
    // in a git client "you cannot do this now" is information.
    component ContextMenu: AppMenu {
        property string target: ""
        delegate: AppMenuItem { showDisabled: true }
    }
    component MenuLine: AppMenuSeparator {}

    function showMenu(menu, target) {
        window.repoDropdownOpen = false;
        window.branchDropdownOpen = false;
        window.accountsDropdownOpen = false;
        menu.target = target;
        menu.popup();
    }

    // The repository itself.
    ContextMenu {
        id: repoMenu
        Action { text: I18n.tr("Open in Terminal"); onTriggered: GitBackend.openTerminal(repoMenu.target) }
        Action { text: I18n.tr("Show in Files"); onTriggered: GitBackend.openFileManager(repoMenu.target) }
        MenuLine {}
        Action {
            text: GitBackend.webUrl.indexOf("gitlab") >= 0 ? I18n.tr("View on GitLab") : I18n.tr("View on GitHub")
            enabled: GitBackend.webUrl !== ""
            onTriggered: GitBackend.openOnWeb()
        }
        Action {
            text: GitBackend.webUrl.indexOf("gitlab") >= 0 ? I18n.tr("Create merge request") : I18n.tr("Create pull request")
            enabled: window.canOpenPr
            onTriggered: GitBackend.openPullRequest()
        }
        MenuLine {}
        Action { text: I18n.tr("Copy path"); onTriggered: GitBackend.copyText(GitBackend.absolutePath(repoMenu.target)) }
    }
    // A repository in the list, which may not be the open one: target is
    // its absolute path, and the actions go straight to the tools.
    ContextMenu {
        id: repoListMenu
        Action { text: I18n.tr("Open"); onTriggered: { GitBackend.openRepo(repoListMenu.target); } }
        Action { text: I18n.tr("Open in Terminal"); onTriggered: GitBackend.openTerminal(repoListMenu.target) }
        Action { text: I18n.tr("Show in Files"); onTriggered: GitBackend.openFileManager(repoListMenu.target) }
        MenuLine {}
        Action { text: I18n.tr("Copy path"); onTriggered: GitBackend.copyText(repoListMenu.target) }
    }
    // A changed file. Stage and unstage are already a click on the checkbox;
    // here too because a right-click is where people look for them.
    ContextMenu {
        id: fileMenu
        property bool staged: false
        property bool conflicted: false
        Action { text: I18n.tr("Open"); onTriggered: GitBackend.openFile(fileMenu.target) }
        Action { text: I18n.tr("Show in Files"); onTriggered: GitBackend.openFileManager(fileMenu.target) }
        Action { text: I18n.tr("Open folder in Terminal"); onTriggered: GitBackend.openTerminal(fileMenu.target) }
        MenuLine {}
        Action { text: I18n.tr("Copy path"); onTriggered: GitBackend.copyText(GitBackend.absolutePath(fileMenu.target)) }
        Action { text: I18n.tr("Copy relative path"); onTriggered: GitBackend.copyText(fileMenu.target) }
        MenuLine {}
        Action {
            text: fileMenu.conflicted ? I18n.tr("Mark as resolved") : fileMenu.staged ? I18n.tr("Unstage") : I18n.tr("Stage")
            onTriggered: fileMenu.staged ? GitBackend.unstageFile(fileMenu.target) : GitBackend.stageFile(fileMenu.target)
        }
        Action {
            text: I18n.tr("Ignore file")
            onTriggered: GitBackend.ignorePattern("/" + fileMenu.target)
        }
        Action {
            readonly property string ext: {
                const name = fileMenu.target.split("/").pop();
                const i = name.lastIndexOf(".");
                return i > 0 ? name.slice(i) : "";
            }
            text: ext !== "" ? I18n.tr("Ignore all %1 files", ext) : I18n.tr("Ignore all files like this")
            enabled: ext !== ""
            onTriggered: GitBackend.ignorePattern("*" + ext)
        }
        MenuLine {}
        Action {
            text: I18n.tr("Discard changes…")
            onTriggered: {
                const path = fileMenu.target;
                window.ask({
                    title: I18n.tr("Discard changes?"),
                    text: I18n.tr("Changes to %1 will be thrown away. A copy goes to the trash.", path),
                    confirm: I18n.tr("Discard"), destructive: true,
                    accept: () => GitBackend.discardFiles([path])
                });
            }
        }
    }

    ContextMenu {
        id: changesMenu
        Action { text: I18n.tr("Stage all"); onTriggered: GitBackend.stageAll() }
        Action { text: I18n.tr("Unstage all"); onTriggered: GitBackend.unstageAll() }
        MenuLine {}
        Action {
            text: I18n.tr("Discard all changes…")
            enabled: GitBackend.changedFiles.length > 0
            onTriggered: window.ask({
                title: I18n.tr("Discard all changes?"),
                text: I18n.trn("%1 changed file will be reset. A copy goes to the trash.", "%1 changed files will be reset. Copies go to the trash.", GitBackend.changedFiles.length),
                confirm: I18n.tr("Discard all"), destructive: true,
                accept: () => GitBackend.discardAll()
            })
        }
    }
    // A file of a commit: the version on disk now, which is what opens.
    ContextMenu {
        id: commitFileMenu
        Action { text: I18n.tr("Open"); onTriggered: GitBackend.openFile(commitFileMenu.target) }
        Action { text: I18n.tr("Show in Files"); onTriggered: GitBackend.openFileManager(commitFileMenu.target) }
        MenuLine {}
        Action { text: I18n.tr("Copy path"); onTriggered: GitBackend.copyText(GitBackend.absolutePath(commitFileMenu.target)) }
        Action { text: I18n.tr("Copy relative path"); onTriggered: GitBackend.copyText(commitFileMenu.target) }
    }
    ContextMenu {
        id: commitMenu
        property string subject: ""
        Action { text: I18n.tr("Copy SHA"); onTriggered: GitBackend.copyText(commitMenu.target) }
        Action { text: I18n.tr("Copy message"); onTriggered: GitBackend.copyText(commitMenu.subject) }
        MenuLine {}
        Action {
            text: I18n.tr("Revert changes in commit")
            enabled: !window.busy
            onTriggered: GitBackend.revertCommit(commitMenu.target)
        }
        Action {
            text: I18n.tr("Create branch from commit…")
            onTriggered: {
                const hash = commitMenu.target;
                window.ask({ title: I18n.tr("Create branch"), text: I18n.tr("A new branch starting at this commit."),
                             input: true, placeholder: I18n.tr("Branch name"), confirm: I18n.tr("Create branch"),
                             accept: v => GitBackend.createBranchAt(v, hash) });
            }
        }
        Action {
            text: I18n.tr("Create tag…")
            onTriggered: {
                const hash = commitMenu.target;
                window.ask({ title: I18n.tr("Create tag"), text: I18n.tr("A tag on this commit."),
                             input: true, placeholder: I18n.tr("Tag name, e.g. v1.0"), confirm: I18n.tr("Create tag"),
                             accept: v => GitBackend.createTag(v, hash) });
            }
        }
    }

    // A pull request makes sense for a published branch that isn't the default one.
    readonly property bool canOpenPr: GitBackend.webUrl !== "" && GitBackend.upstream !== ""
                                      && GitBackend.branchName !== GitBackend.defaultBranch

    // One dialog for confirmations and names:
    // { title, text, input, value, placeholder, confirm, destructive, accept(value) }
    property var dialog: null
    function ask(spec) {
        window.repoDropdownOpen = false;
        window.accountsDropdownOpen = false;
        window.dialog = spec;
        dialogInput.text = spec.value || "";
        if (spec.input) dialogInput.forceActiveFocus();
    }
    function closeDialog(accepted) {
        const d = window.dialog;
        window.dialog = null;
        if (accepted && d && d.accept) {
            const v = dialogInput.text.trim();
            if (d.input && v === "") return;
            d.accept(v);
        }
    }

    // A branch switch waiting on what to do with uncommitted changes.
    property string pendingSwitch: ""
    property string pendingRemoveWorktree: ""

    ContextMenu {
        id: branchMenu
        property string worktree: ""
        readonly property bool isCurrent: branchMenu.target === GitBackend.branchName
        Action {
            text: I18n.tr("Merge into %1", GitBackend.branchName)
            enabled: !branchMenu.isCurrent && !GitBackend.mergeState.active
            onTriggered: { window.branchDropdownOpen = false; GitBackend.mergeBranch(branchMenu.target); }
        }
        Action {
            text: I18n.tr("Rename…")
            onTriggered: {
                const from = branchMenu.target;
                window.ask({ title: I18n.tr("Rename branch"), text: I18n.tr("New name for %1.", from),
                             input: true, value: from, placeholder: I18n.tr("Branch name"), confirm: I18n.tr("Rename"),
                             accept: v => GitBackend.renameBranch(from, v) });
            }
        }
        MenuLine {}
        Action {
            text: branchMenu.worktree !== "" ? I18n.tr("Open its worktree") : I18n.tr("Open in new worktree")
            enabled: !branchMenu.isCurrent
            onTriggered: {
                const path = branchMenu.worktree !== "" ? branchMenu.worktree
                                                        : GitBackend.createWorktree(branchMenu.target);
                if (path !== "") { window.branchDropdownOpen = false; GitBackend.openRepo(path); }
            }
        }
    }

    ContextMenu {
        id: worktreeMenu
        property bool removable: false
        Action { text: I18n.tr("Open"); onTriggered: { window.branchDropdownOpen = false; GitBackend.openRepo(worktreeMenu.target); } }
        Action { text: I18n.tr("Open in Terminal"); onTriggered: GitBackend.openTerminal(worktreeMenu.target) }
        Action { text: I18n.tr("Show in Files"); onTriggered: GitBackend.openFileManager(worktreeMenu.target) }
        MenuLine {}
        Action { text: I18n.tr("Copy path"); onTriggered: GitBackend.copyText(worktreeMenu.target) }
        Action {
            text: I18n.tr("Remove worktree…")
            enabled: worktreeMenu.removable
            onTriggered: { window.branchDropdownOpen = true; window.pendingRemoveWorktree = worktreeMenu.target; }
        }
    }

    component ToolbarCell: Rectangle {
        id: cell
        property string icon: ""
        property string caption: ""
        property string title: ""
        property string badge: ""
        property bool spinning: false
        property bool dropdown: false
        property bool open: false
        // compact: icon and one line, sized to its text — for the tools on
        // the right, which are not the three cells of the original.
        property bool compact: false
        property bool leftDivider: false
        signal clicked()
        signal rightClicked()

        Layout.fillHeight: true
        // The three main cells share the bar's width up to their natural
        // size, rather than holding a fixed 250 each: in a window tiled to half
        // a 1920 screen they did not fit, and the last one was cut off.
        Layout.preferredWidth: compact ? cellRow.implicitWidth + Design.s(24) : Design.s(250)
        Layout.maximumWidth: compact ? cellRow.implicitWidth + Design.s(24) : Design.s(250)
        Layout.minimumWidth: compact ? cellRow.implicitWidth + Design.s(24) : Design.s(110)
        Layout.fillWidth: !compact
        radius: Design.s(Design.radius.card)
        border.width: 1
        border.color: open ? Design.accent : Design.tint(Design.text, 0.06)
        color: open ? Design.tint(Design.accent, 0.22)
             : cellArea.pressed && enabled ? Design.active
             : cellArea.containsMouse && enabled ? Design.hover : Design.raised
        opacity: enabled || spinning ? 1.0 : 0.5

        Behavior on color { ColorAnimation { duration: Design.duration.fast } }

        // Right divider, and a left one where a group starts after a gap.
        Rectangle {
            visible: false
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: window.colBorder
        }
        Rectangle {
            visible: false && cell.leftDivider
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: window.colBorder
        }

        // Not anchors.fill: a compact cell takes its width from this row, and
        // a row that also filled the cell would make that width depend on
        // itself.
        RowLayout {
            id: cellRow
            x: Design.s(cell.compact ? 12 : 14)
            width: cell.compact ? implicitWidth : cell.width - Design.s(26)
            height: parent.height
            spacing: Design.s(cell.compact ? 7 : 12)

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: cellIcon.implicitWidth
                implicitHeight: cellIcon.implicitHeight
                Text {
                    id: cellIcon
                    anchors.centerIn: parent
                    visible: !cell.spinning
                    text: cell.icon
                    font.family: Design.font.icon
                    font.pixelSize: Design.s(cell.compact ? 14 : 17)
                    color: cell.open ? window.colBlue : window.colFg
                }
                // A separate glyph, so the icon is never left at an angle.
                Text {
                    id: cellSpinner
                    anchors.centerIn: parent
                    visible: cell.spinning
                    text: "󰝲"
                    font.family: Design.font.icon
                    font.pixelSize: cellIcon.font.pixelSize
                    color: window.colBlue
                    RotationAnimator on rotation {
                        running: cellSpinner.visible
                        from: 0; to: 360; duration: 900
                        loops: Animation.Infinite
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: !cell.compact
                Layout.alignment: Qt.AlignVCenter
                spacing: Design.s(1)

                Text {
                    visible: !cell.compact
                    Layout.fillWidth: true
                    text: cell.caption
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(Design.font.caption)
                    color: window.colDim
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: !cell.compact
                    spacing: Design.s(6)
                    Text {
                        Layout.fillWidth: !cell.compact
                        text: cell.title
                        font.family: Design.font.sans
                        font.pixelSize: Design.s(cell.compact ? 12 : 13)
                        font.weight: cell.compact ? Font.Normal : Font.DemiBold
                        color: window.colFg
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: cell.badge !== ""
                        Layout.preferredWidth: badgeText.implicitWidth + Design.s(10)
                        Layout.preferredHeight: Design.s(16)
                        radius: height / 2
                        color: Design.tint(Design.text, 0.14)
                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: cell.badge
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(Design.font.caption)
                            font.weight: Font.DemiBold
                            color: window.colFg
                        }
                    }
                }
            }

            Text {
                visible: cell.dropdown
                text: cell.open ? "󰅃" : "󰅀"
                font.family: Design.font.icon
                font.pixelSize: Design.s(12)
                color: window.colDim
                Layout.alignment: Qt.AlignVCenter
            }
        }

        MouseArea {
            id: cellArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: cell.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (!cell.enabled) return;
                if (mouse.button === Qt.RightButton) cell.rightClicked();
                else cell.clicked();
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: window.close()
    }

    Shortcut {
        sequence: "F5"
        onActivated: GitBackend.refresh()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            window.repoDropdownOpen = false;
            window.branchDropdownOpen = false;
            window.accountsDropdownOpen = false;
            window.pendingSwitch = "";
            window.pendingRemoveWorktree = "";
            window.pendingDeleteBranch = "";
            window.pendingTrashRepo = "";
        }
    }

    Shortcut {
        sequence: "Ctrl+O"
        onActivated: GitBackend.pickRepoFolder()
    }

    Shortcut {
        sequence: "Ctrl+R"
        onActivated: GitBackend.refresh()
    }

    // GitHub Desktop's keys.
    Shortcut { sequence: "Ctrl+1"; onActivated: window.currentTab = 0 }
    Shortcut { sequence: "Ctrl+2"; onActivated: window.currentTab = 1 }
    Shortcut { sequence: "Ctrl+T"; onActivated: { window.repoDropdownOpen = !window.repoDropdownOpen; window.branchDropdownOpen = false; } }
    Shortcut { sequence: "Ctrl+B"; onActivated: { window.branchDropdownOpen = !window.branchDropdownOpen; window.repoDropdownOpen = false; } }
    Shortcut { sequence: "Ctrl+P"; onActivated: if (!window.busy && GitBackend.hasRemote) GitBackend.push() }
    Shortcut { sequence: "Ctrl+Shift+P"; onActivated: if (!window.busy && GitBackend.upstream !== "") GitBackend.pull() }
    Shortcut { sequence: "Ctrl+Shift+F"; onActivated: if (!window.busy && GitBackend.hasRemote) GitBackend.fetch() }
    Shortcut { sequence: "Ctrl+`"; onActivated: GitBackend.openTerminal("") }

    property int currentTab: 0 // 0: Changes, 1: History
    property string repoFilter: ""
    property string pendingDeleteBranch: ""
    // Deleting a repository is not something to do on one click, so the row
    // asks first and names what it is about to move to the trash.
    property string pendingTrashRepo: ""
    readonly property string homePath: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "")
    readonly property var filteredRepos: {
        const q = window.repoFilter.trim().toLowerCase();
        if (q === "") return GitBackend.repos;
        return GitBackend.repos.filter(r => r.name.toLowerCase().includes(q)
                                         || r.path.toLowerCase().includes(q));
    }
    // Read from the repository (FETCH_HEAD), so it survives a restart and
    // counts a fetch made in a terminal.
    readonly property string lastFetchText: {
        if (!window.hasRepo) return I18n.tr("No repository");
        if (!GitBackend.lastFetchTime) return I18n.tr("Never fetched");
        return I18n.tr("Last fetched %1", window.relTime(GitBackend.lastFetchTime));
    }
    // The one action the sync cell offers, GitHub Desktop's order: a branch
    // with no upstream is published; with commits to pull, pulling comes
    // first, since a push would be refused; then push; otherwise fetch.
    readonly property string syncAction: !window.hasRepo || !GitBackend.hasRemote ? "none"
        : GitBackend.upstream === "" ? "publish"
        : GitBackend.behindCount > 0 ? "pull"
        : GitBackend.aheadCount > 0 ? "push" : "fetch"
    property bool repoDropdownOpen: false
    property bool branchDropdownOpen: false
    property bool accountsDropdownOpen: false

    // "3 weeks ago", "1 month ago". The history used git's own %cr, which
    // keeps counting weeks until the tenth — a commit from two months back
    // read "9 weeks ago". Here weeks stop at four.
    // windowNow ticks once a minute so "just now" does not stay just now.
    property real windowNow: Date.now()
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: window.windowNow = Date.now()
    }
    function relTime(t) {
        if (!t) return "";
        const sec = Math.max(0, Math.floor(window.windowNow / 1000 - t));
        if (sec < 60) return I18n.tr("just now");
        const min = Math.floor(sec / 60);
        if (min < 60) return I18n.trn("%1 minute ago", "%1 minutes ago", min);
        const hr = Math.floor(min / 60);
        if (hr < 24) return I18n.trn("%1 hour ago", "%1 hours ago", hr);
        const days = Math.floor(hr / 24);
        if (days < 7) return days === 1 ? I18n.tr("yesterday") : I18n.trn("%1 day ago", "%1 days ago", days);
        if (days < 28) return I18n.trn("%1 week ago", "%1 weeks ago", Math.floor(days / 7));
        const months = Math.max(1, Math.floor(days / 30.44));
        if (months < 12) return I18n.trn("%1 month ago", "%1 months ago", months);
        return I18n.trn("%1 year ago", "%1 years ago", Math.max(1, Math.floor(days / 365.25)));
    }

    // A file's state as an icon rather than a letter: the Octicons git diff
    // set, which is what the letters were standing in for. Same colours as
    // before; the word is in the tooltip.
    function statusIcon(st) {
        if (st === "conflicted") return "";
        return st === "added" ? "" : st === "deleted" ? ""
             : st === "renamed" ? "" : "";
    }
    function statusColor(st) {
        if (st === "conflicted") return window.colRed;
        return st === "added" ? window.colGreen : st === "deleted" ? window.colRed
             : st === "renamed" ? window.colCyan : window.colOrange;
    }
    function statusWord(st) {
        if (st === "conflicted") return I18n.tr("Conflicted");
        return st === "added" ? I18n.tr("Added") : st === "deleted" ? I18n.tr("Deleted")
             : st === "renamed" ? I18n.tr("Renamed") : I18n.tr("Modified");
    }
    // "Blair and Claude", "Blair and 2 others" — how GitHub Desktop names a
    // commit with co-authors. Only the author was shown before, so a commit
    // written together credited one person.
    function people(author, coAuthors) {
        const co = (coAuthors || []).filter(n => n !== author);
        if (co.length === 0) return author || "";
        if (co.length === 1) return I18n.tr("%1 and %2", author, co[0]);
        return I18n.trn("%2 and %1 other", "%2 and %1 others", co.length, author);
    }
    function initials(name) {
        const words = (name || "?").split(/[\s._-]+/).filter(w => w.length > 0);
        if (words.length === 0) return "?";
        return (words[0][0] + (words.length > 1 ? words[1][0] : "")).toUpperCase();
    }
    readonly property bool busy: GitBackend.busy !== ""

    function commitNow() {
        if (!window.hasRepo || window.busy || sumInput.text.trim() === "") return;
        let msg = sumInput.text.trim();
        if (descInput.text.trim()) msg += "\n\n" + descInput.text.trim();
        // The fields are cleared when the commit has gone in (onCommitted
        // below), not here: a commit that failed took the message with it.
        GitBackend.commit(msg);
    }
    readonly property int stagedCount: GitBackend.changedFiles.filter(f => f.isStaged).length
    readonly property bool syncBusy: ["push", "publish", "pull", "fetch"].indexOf(GitBackend.busy) >= 0

    readonly property var githubAccount: GitBackend.accounts.find(a => a.provider === "github") || null

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
            // TOOLBAR — GitHub Desktop's
            // ══════════════════════════════════════════════════════════════════
            // Flush cells the full height of the bar, divided by a hairline,
            // square, with the open one lit — the shape GitHub Desktop has. The
            // bar before this was a row of rounded, outlined pills with gaps
            // between them and two loose arrow buttons for push and pull, which
            // read as a web form rather than that app. The arrows are gone into
            // the third cell, which is one action at a time as in the original:
            // Publish branch, Pull origin, Push origin, or Fetch origin.
            //
            // A full border on a bar that spans the window draws its left and
            // right edges on top of the frame's own; what separates the bar from
            // what is under it is one line, so that is what it has.
            // Restyled to the suite's toolbar: no bar of its own colour and no
            // rule; the three cells are capsules like every other app's
            // controls, and still open the same dropdowns.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(60)
                color: "transparent"
                z: 20

                // Progress of the running operation: fills when git reports a
                // percentage, slides back and forth when it doesn't.
                Item {
                    id: progressLine
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 2
                    visible: window.busy
                    clip: true
                    z: 2

                    Rectangle {
                        visible: GitBackend.progress >= 0
                        height: parent.height
                        width: parent.width * Math.max(0, GitBackend.progress) / 100
                        color: window.colBlue
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        id: slider
                        visible: GitBackend.progress < 0
                        height: parent.height
                        width: parent.width * 0.25
                        radius: 1
                        color: window.colBlue
                        SequentialAnimation on x {
                            running: progressLine.visible && GitBackend.progress < 0
                            loops: Animation.Infinite
                            NumberAnimation { from: -slider.width; to: progressLine.width; duration: 1100; easing.type: Easing.InOutQuad }
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.md)
                    anchors.rightMargin: Design.s(Design.space.md)
                    anchors.topMargin: Design.s(Design.space.sm)
                    anchors.bottomMargin: Design.s(Design.space.xs)
                    spacing: Design.s(Design.space.sm)

                    ToolbarCell {
                        id: repoBtn
                        icon: "󰊢"
                        caption: I18n.tr("Current repository")
                        title: GitBackend.repoName || I18n.tr("No repository")
                        dropdown: true
                        open: window.repoDropdownOpen
                        onRightClicked: if (window.hasRepo) window.showMenu(repoMenu, "")
                        onClicked: {
                            window.repoDropdownOpen = !window.repoDropdownOpen;
                            window.branchDropdownOpen = false;
                            window.accountsDropdownOpen = false;
                        }
                    }

                    ToolbarCell {
                        id: branchBtn
                        // The branch name is the one value here that can be
                        // arbitrarily long, so this cell elides instead of
                        // pushing the rest of the bar along.
                        icon: ""
                        spinning: GitBackend.busy === "checkout" || GitBackend.busy === "merge"
                        caption: spinning ? GitBackend.busyText : I18n.tr("Current branch")
                        title: window.hasRepo ? GitBackend.branchName : "—"
                        dropdown: true
                        open: window.branchDropdownOpen
                        enabled: window.hasRepo && !window.busy
                        onClicked: {
                            window.branchDropdownOpen = !window.branchDropdownOpen;
                            window.repoDropdownOpen = false;
                            window.accountsDropdownOpen = false;
                        }
                    }

                    ToolbarCell {
                        id: syncBtn
                        enabled: window.syncAction !== "none" && !window.busy
                        spinning: window.syncBusy || GitBackend.fetching
                        icon: window.syncAction === "publish" ? "󰅧"
                            : window.syncAction === "pull" ? "󰁅"
                            : window.syncAction === "push" ? "󰁝" : "󰑐"
                        title: window.syncAction === "publish" ? I18n.tr("Publish branch")
                             : window.syncAction === "pull" ? I18n.tr("Pull %1", GitBackend.remoteName)
                             : window.syncAction === "push" ? I18n.tr("Push %1", GitBackend.remoteName)
                             : window.syncAction === "fetch" ? I18n.tr("Fetch %1", GitBackend.remoteName)
                             : I18n.tr("Fetch origin")
                        caption: window.syncBusy ? GitBackend.busyText
                               : !window.hasRepo ? I18n.tr("No repository")
                               : !GitBackend.hasRemote ? I18n.tr("This repository has no remote")
                               : GitBackend.fetching ? I18n.tr("Fetching…")
                               : GitBackend.upstreamGone ? I18n.tr("Deleted on %1 — publish again?", GitBackend.remoteName)
                               : window.syncAction === "publish" ? I18n.tr("Publish this branch to %1", GitBackend.remoteName)
                               : window.lastFetchText
                        // Counts beside the title, as the original draws them:
                        // what is waiting in each direction.
                        badge: (GitBackend.behindCount > 0 ? GitBackend.behindCount + "↓" : "")
                             + (GitBackend.behindCount > 0 && GitBackend.aheadCount > 0 ? " " : "")
                             + (GitBackend.aheadCount > 0 && window.syncAction !== "publish" ? GitBackend.aheadCount + "↑" : "")
                        onClicked: {
                            if (window.syncAction === "pull") GitBackend.pull();
                            else if (window.syncAction === "push" || window.syncAction === "publish") GitBackend.push();
                            else GitBackend.fetch();
                        }
                    }

                    Item { Layout.fillWidth: true; Layout.minimumWidth: 0 }

                    // Beyond the original: accounts. Terminal and Files were
                    // two more cells here; they moved to the right-click menus
                    // (on the repository, a file, a commit), where they open
                    // the thing clicked rather than always the repository root.
                    ToolbarCell {
                        id: accountsBtn
                        compact: true
                        leftDivider: true
                        icon: "󰀉"
                        title: window.githubAccount && window.githubAccount.login ? window.githubAccount.login : I18n.tr("Accounts")
                        open: window.accountsDropdownOpen
                        onClicked: {
                            window.accountsDropdownOpen = !window.accountsDropdownOpen;
                            window.repoDropdownOpen = false;
                            window.branchDropdownOpen = false;
                            if (window.accountsDropdownOpen) GitBackend.refreshAccounts();
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
                    spacing: 0

                    // ── LEFT SIDEBAR (Changes & History) ──────────────────────
                    // The two panels were butted against each other and against
                    // the window edge with square corners, so this was the only
                    // surface in the suite that did not look like the rest of
                    // it: Files and the monitor are rounded cards with room
                    // around them.
                    Rectangle {
                        // A share of the window, within bounds, rather than a
                        // fixed 320: tiled to half a screen the diff beside it
                        // was left with too little room to read.
                        Layout.preferredWidth: Math.round(Math.max(Design.s(224), Math.min(Design.s(340), window.width * 0.28)))
                        Layout.fillHeight: true
                        // The sidebar of every app: sunken, flush with the
                        // window edge, a hairline on the right.
                        color: Design.sunken
                        clip: true
                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Design.line; z: 5 }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Top Sidebar Tab Switcher: [ Changes (N) ] [ History ]
Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(48)
                                BarGroup {
                                    anchors.centerIn: parent
                                    BarButton {
                                        label: I18n.tr("Changes") + (GitBackend.changedFiles.length ? "  " + GitBackend.changedFiles.length : "")
                                        glyph: "\u{f0279}"
                                        checked: window.currentTab === 0
                                        onClicked: window.currentTab = 0
                                    }
                                    BarButton {
                                        label: I18n.tr("History")
                                        glyph: "\u{f02da}"
                                        checked: window.currentTab === 1
                                        onClicked: {
                                            window.currentTab = 1;
                                            // Open on the newest commit rather
                                            // than an empty panel.
                                            if (GitBackend.selectedCommit === "" && GitBackend.history.count > 0)
                                                GitBackend.selectCommit(GitBackend.history.hashAt(0));
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

                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            onClicked: window.showMenu(changesMenu, "")
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(8)
                                            anchors.rightMargin: Design.s(10)
                                            spacing: Design.s(8)

                                            // Stage everything, or nothing; a dash when it's mixed.
                                            Rectangle {
                                                readonly property int staged: GitBackend.changedFiles.filter(f => f.isStaged).length
                                                readonly property int total: GitBackend.changedFiles.length
                                                visible: total > 0
                                                Layout.preferredWidth: Design.s(16)
                                                Layout.preferredHeight: Design.s(16)
                                                radius: Design.s(3)
                                                color: staged > 0 ? window.colGreen : "transparent"
                                                border.color: staged > 0 ? window.colGreen : window.colDim
                                                border.width: 1
                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: parent.staged > 0
                                                    text: parent.staged === parent.total ? "✓" : "–"
                                                    font.pixelSize: Design.s(Design.font.caption)
                                                    font.bold: true
                                                    color: Design.accentText
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: parent.staged === parent.total ? GitBackend.unstageAll() : GitBackend.stageAll()
                                                }
                                            }

                                            Text {
                                                text: GitBackend.changedFiles.length === 0 ? I18n.tr("No changed files")
                                                    : GitBackend.changedFiles.length + (GitBackend.changedFiles.length === 1 ? " changed file" : " changed files")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.bold: true
                                                color: window.colDim
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: I18n.tr("Stage All")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: window.colGreen
                                                opacity: window.hasRepo ? 1.0 : 0.45
                                                enabled: window.hasRepo
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: GitBackend.stageAll()
                                                }
                                            }
                                            Text { text: "•"; font.pixelSize: Design.s(Design.font.caption); color: window.colDim }
                                            Text {
                                                text: I18n.tr("Unstage All")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
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

                                    // A merge waiting to be finished or aborted.
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Design.s(34)
                                        visible: GitBackend.mergeState.active === true
                                        readonly property int conflicts: GitBackend.mergeState.conflicts || 0
                                        color: conflicts > 0 ? Design.tint(Design.danger, 0.14) : Design.tint(Design.ok, 0.14)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(10)
                                            anchors.rightMargin: Design.s(10)
                                            spacing: Design.s(10)
                                            Text {
                                                Layout.fillWidth: true
                                                text: I18n.tr("Merging %1 — %2", GitBackend.mergeState.branch || "",
                                                             parent.parent.conflicts > 0
                                                             ? I18n.trn("%1 conflict", "%1 conflicts", parent.parent.conflicts)
                                                             : I18n.tr("ready"))
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.bold: true
                                                color: parent.parent.conflicts > 0 ? window.colRed : window.colGreen
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: GitBackend.busy === "commit" ? I18n.tr("Committing…") : I18n.tr("Commit merge")
                                                visible: parent.parent.conflicts === 0
                                                enabled: !window.busy
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.bold: true
                                                color: window.colGreen
                                                MouseArea { anchors.fill: parent; anchors.margins: -Design.s(4); cursorShape: Qt.PointingHandCursor; onClicked: GitBackend.commitMerge() }
                                            }
                                            Text {
                                                text: I18n.tr("Abort")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: window.colDim
                                                MouseArea { anchors.fill: parent; anchors.margins: -Design.s(4); cursorShape: Qt.PointingHandCursor; onClicked: GitBackend.abortMerge() }
                                            }
                                        }
                                    }

                                    // Changes this app stashed when leaving
                                    // this branch, offered back on return.
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Design.s(34)
                                        visible: GitBackend.branchStash.ref !== undefined
                                        color: Design.tint(Design.accent, 0.12)

                                        property bool confirmDiscard: false

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(10)
                                            anchors.rightMargin: Design.s(10)
                                            spacing: Design.s(8)
                                            Text {
                                                Layout.fillWidth: true
                                                text: parent.parent.confirmDiscard ? I18n.tr("Delete the stash for good?")
                                                    : I18n.tr("Stashed changes (%1)", GitBackend.branchStash.files || 0)
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.bold: true
                                                color: parent.parent.confirmDiscard ? window.colRed : window.colBlue
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: parent.parent.confirmDiscard ? I18n.tr("Delete") : I18n.tr("Restore")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.bold: true
                                                color: parent.parent.confirmDiscard ? window.colRed : window.colGreen
                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -Design.s(4)
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        const bar = parent.parent.parent;
                                                        if (bar.confirmDiscard) GitBackend.discardStash();
                                                        else GitBackend.restoreStash();
                                                        bar.confirmDiscard = false;
                                                    }
                                                }
                                            }
                                            Text {
                                                text: parent.parent.confirmDiscard ? I18n.tr("Keep") : I18n.tr("Discard")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: window.colDim
                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -Design.s(4)
                                                    cursorShape: Qt.PointingHandCursor
                                                    // Discarding loses work, so it
                                                    // asks once, in place.
                                                    onClicked: parent.parent.parent.confirmDiscard = !parent.parent.parent.confirmDiscard
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
                                                        font.pixelSize: Design.s(Design.font.caption)
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

                                                // File state icon
                                                Text {
                                                    text: window.statusIcon(modelData.status)
                                                    font.family: Design.font.mono
                                                    font.pixelSize: Design.s(13)
                                                    color: window.statusColor(modelData.status)
                                                }

                                                // File Name
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.path
                                                    font.family: Design.font.mono
                                                    font.pixelSize: Design.s(Design.font.caption)
                                                    color: fileCard.isSelected ? Design.text : window.colFg
                                                    elide: Text.ElideMiddle
                                                }
                                            }

                                            MouseArea {
                                                id: fArea
                                                // Under the row, not over it: declared
                                                // after the checkbox it sat on top of it,
                                                // and ticking a file selected it instead
                                                // of staging it.
                                                z: -1
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                onClicked: (mouse) => {
                                                    GitBackend.selectFile(modelData.path);
                                                    if (mouse.button === Qt.RightButton) {
                                                        fileMenu.staged = modelData.isStaged;
                                                        fileMenu.conflicted = modelData.status === "conflicted";
                                                        window.showMenu(fileMenu, modelData.path);
                                                    }
                                                }
                                            }
                                            ToolTip.visible: fArea.containsMouse
                                            ToolTip.delay: 800
                                            ToolTip.text: window.statusWord(modelData.status) + (modelData.isStaged ? ", staged" : "")
                                        }
                                    }

                                    // Bottom GitHub Desktop Commit Box
                                    // The commit box is the foot of the panel,
                                    // so its separator is on top of it.
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: Design.s(176) + (lastCommitBar.visible ? Design.s(40) : 0)
                                                + (identityWarning.visible ? Design.s(18) : 0)
                                        color: Design.tint(Design.ground, 0.90)

                                        Connections {
                                            target: GitBackend
                                            function onCommitted() {
                                                sumInput.text = "";
                                                descInput.text = "";
                                            }
                                            function onRestoreMessage(summary, description) {
                                                sumInput.text = summary;
                                                descInput.text = description;
                                            }
                                        }

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

                                            // The latest commit, while it can still be taken back.
                                            Rectangle {
                                                id: lastCommitBar
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Design.s(34)
                                                visible: GitBackend.lastCommit.canUndo === true
                                                radius: Design.s(5)
                                                color: window.colBg
                                                border.color: window.colBorder
                                                border.width: 1

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: Design.s(8)
                                                    anchors.rightMargin: Design.s(6)
                                                    spacing: Design.s(8)
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 0
                                                        Text {
                                                            text: I18n.tr("Committed %1", window.relTime(GitBackend.lastCommit.time))
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.caption)
                                                            color: window.colDim
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: GitBackend.lastCommit.subject || ""
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.caption)
                                                            font.bold: true
                                                            color: window.colFg
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                    Rectangle {
                                                        Layout.preferredWidth: undoText.implicitWidth + Design.s(16)
                                                        Layout.preferredHeight: Design.s(22)
                                                        radius: Design.s(4)
                                                        opacity: window.busy ? 0.5 : 1
                                                        color: undoArea.containsMouse ? Design.tint(Design.text, 0.12) : "transparent"
                                                        border.color: window.colBorder
                                                        border.width: 1
                                                        Text {
                                                            id: undoText
                                                            anchors.centerIn: parent
                                                            text: GitBackend.busy === "undo" ? I18n.tr("Undoing…") : I18n.tr("Undo")
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.caption)
                                                            font.bold: true
                                                            color: window.colFg
                                                        }
                                                        MouseArea {
                                                            id: undoArea
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            enabled: !window.busy
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: GitBackend.undoLastCommit()
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                id: identityWarning
                                                Layout.fillWidth: true
                                                visible: window.hasRepo && (!GitBackend.identity.name || !GitBackend.identity.email)
                                                text: I18n.tr("Set your name and email: git config user.name / user.email")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: window.colOrange
                                                elide: Text.ElideRight
                                            }

                                            // Summary (Required)
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: Design.s(36)
                                                radius: Design.s(Design.radius.ctl)
                                                color: Design.raised
                                                opacity: window.hasRepo ? 1.0 : 0.5
                                                border.color: sumInput.activeFocus ? Design.accent : Design.line
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
                                                    anchors.leftMargin: Design.s(Design.space.md)
                                                    anchors.rightMargin: Design.s(Design.space.md)
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(Design.font.body)
                                                    color: window.colFg
                                                    selectByMouse: true
                                                    clip: true
                                                    Keys.onPressed: (e) => {
                                                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) {
                                                            window.commitNow();
                                                            e.accepted = true;
                                                        }
                                                    }

                                                    Text {
                                                        text: I18n.tr("Summary (required)")
                                                        font.family: Design.font.sans
                                                        font.pixelSize: Design.s(Design.font.body)
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
                                                Layout.minimumHeight: Design.s(56)
                                                radius: Design.s(Design.radius.ctl)
                                                color: Design.raised
                                                opacity: window.hasRepo ? 1.0 : 0.5
                                                border.color: descInput.activeFocus ? Design.accent : Design.line
                                                border.width: 1

                                                TextArea {
                                                    id: descInput
                                                    enabled: window.hasRepo
                                                    anchors.fill: parent
                                                    leftPadding: Design.s(Design.space.md)
                                                    rightPadding: Design.s(Design.space.md)
                                                    topPadding: Design.s(Design.space.sm)
                                                    bottomPadding: Design.s(Design.space.sm)
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(Design.font.body)
                                                    color: window.colFg
                                                    selectByMouse: true
                                                    background: null
                                                    wrapMode: TextEdit.Wrap

                                                    Text {
                                                        x: descInput.leftPadding
                                                        y: descInput.topPadding
                                                        text: I18n.tr("Description")
                                                        font.family: Design.font.sans
                                                        font.pixelSize: Design.s(Design.font.body)
                                                        color: window.colDim
                                                        visible: !descInput.text && !descInput.activeFocus
                                                    }
                                                }
                                            }

                                            // Commit Action Button
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: Design.s(36)
                                                radius: height / 2
                                                readonly property bool committing: GitBackend.busy === "commit"
                                                readonly property bool ready: window.hasRepo && sumInput.text.trim().length > 0 && !window.busy
                                                color: ready ? (commitArea.containsMouse ? Qt.lighter(window.colBlue, 1.1) : window.colBlue) : Design.raised
                                                enabled: ready

                                                Row {
                                                    id: commitSpin
                                                    anchors.centerIn: parent
                                                    spacing: Design.s(6)
                                                    visible: parent.committing
                                                    Text {
                                                        text: "󰝲"
                                                        font.family: Design.font.icon
                                                        font.pixelSize: Design.s(12)
                                                        color: window.colFg
                                                        RotationAnimator on rotation { running: commitSpin.visible; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                                                    }
                                                    Text {
                                                        text: I18n.tr("Committing…")
                                                        font.family: Design.font.sans
                                                        font.pixelSize: Design.s(Design.font.caption)
                                                        font.bold: true
                                                        color: window.colFg
                                                    }
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    width: parent.width - Design.s(Design.space.lg) * 2
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideMiddle
                                                    visible: !parent.committing
                                                    // Nothing ticked commits everything.
                                                    text: !window.hasRepo ? I18n.tr("No repository open")
                                                          : window.stagedCount === 0 && GitBackend.changedFiles.length > 0
                                                            ? I18n.tr("Commit all to %1", GitBackend.branchName)
                                                            : I18n.tr("Commit to %1", GitBackend.branchName)
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(Design.font.body)
                                                    font.bold: true
                                                    color: parent.ready ? Design.accentText : window.colDim
                                                }

                                                MouseArea {
                                                    id: commitArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: window.commitNow()
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
                                    model: GitBackend.history
                                    spacing: 1
                                    ScrollBar.vertical: ScrollBar {}

                                    // The rows were hover-only: nothing
                                    // happened on click, so a commit's files
                                    // and changes could not be seen at all.
                                    delegate: Rectangle {
                                        width: historyList.width
                                        height: Design.s(52)
                                        readonly property bool isSelected: GitBackend.selectedCommit === model.fullHash
                                        color: isSelected ? Design.tint(Design.accent, 0.18)
                                                          : (hArea.containsMouse ? Design.tint(Design.text, 0.05) : "transparent")
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
                                                    text: model.message || I18n.tr("Commit")
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(Design.font.caption)
                                                    font.bold: true
                                                    color: window.colFg
                                                    elide: Text.ElideRight
                                                }
                                                // Pushed or not. A cloud with a
                                                // tick when a remote has it, an
                                                // upload arrow in the warning
                                                // colour when only this
                                                // machine does.
                                                Text {
                                                    visible: model.sync !== ""
                                                    text: model.sync === "local" ? "󰅧" : "󰅠"
                                                    font.family: Design.font.mono
                                                    font.pixelSize: Design.s(13)
                                                    color: model.sync === "local" ? window.colOrange : window.colDim
                                                    opacity: model.sync === "local" ? 1.0 : 0.6
                                                }
                                                Rectangle {
                                                    width: Design.s(54); height: Design.s(18); radius: Design.s(3)
                                                    color: Design.tint(Design.accent, 0.15)
                                                    Text { anchors.centerIn: parent; text: model.hash || ""; font.family: Design.font.mono; font.pixelSize: Design.s(Design.font.caption); color: window.colBlue }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                text: window.people(model.author || I18n.tr("User"), model.coAuthors) + " • " + window.relTime(model.time)
                                                      + (model.sync === "local" ? " • not pushed" : "")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: window.colDim
                                            }
                                        }

                                        MouseArea {
                                            id: hArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: (mouse) => {
                                                GitBackend.selectCommit(model.fullHash);
                                                if (mouse.button === Qt.RightButton) {
                                                    commitMenu.subject = model.message;
                                                    window.showMenu(commitMenu, model.fullHash);
                                                }
                                            }
                                        }
                                        ToolTip.visible: hArea.containsMouse
                                        ToolTip.delay: 800
                                        ToolTip.text: model.sync === "local" ? I18n.tr("Not pushed — on no remote yet")
                                                    : model.sync === "pushed" ? I18n.tr("Pushed") : I18n.tr("This repository has no remote")
                                    }
                                }
                            }
                        }
                    }

                    // ── RIGHT MAIN PANEL (File Diff Viewer) ───────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Design.surface
                        clip: true

                        // One diff row, shared by the working-tree diff and a
                        // commit's: two copies of this delegate would drift.
                        Component {
                            id: diffRowDelegate

                            Rectangle {
                                width: ListView.view ? ListView.view.width : 0
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
                                    // Layout.preferredWidth, not width: a
                                    // RowLayout ignores width, so both number
                                    // columns shrank to their text and the
                                    // new-line number sat on top of the old.
                                    Text {
                                        Layout.preferredWidth: Design.s(42)
                                        text: modelData.oldLine || ""
                                        horizontalAlignment: Text.AlignRight
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: window.colDim
                                        rightPadding: 8
                                    }

                                    // New Line Num
                                    Text {
                                        Layout.preferredWidth: Design.s(42)
                                        text: modelData.newLine || ""
                                        horizontalAlignment: Text.AlignRight
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: window.colDim
                                        rightPadding: 8
                                    }

                                    // Line Content
                                    Text {
                                        id: diffLineText
                                        Layout.fillWidth: true
                                        text: modelData.text || ""
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: {
                                            if (modelData.type === "add") return window.colGreen;
                                            if (modelData.type === "del") return window.colRed;
                                            if (modelData.type === "header") return window.colBlue;
                                            return window.colFg;
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            visible: window.currentTab === 0

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
                                        font.pixelSize: Design.s(Design.font.body)
                                        font.bold: true
                                        color: window.colFg
                                        Layout.fillWidth: true
                                        elide: Text.ElideMiddle
                                    }

                                    Text {
                                        text: GitBackend.statusSummary
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
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
                                delegate: diffRowDelegate

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
                                        text: GitBackend.isRepo ? I18n.tr("No changes to display") : I18n.tr("No Git Repository Open")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(14)
                                        font.bold: true
                                        color: window.colFg
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: GitBackend.isRepo ? I18n.tr("Working directory is clean") : I18n.tr("Select a repository from the top menu or open a folder.")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.body)
                                        color: window.colDim
                                    }

                                    // What to do next, as GitHub Desktop suggests it.
                                    ColumnLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.topMargin: Design.s(8)
                                        Layout.preferredWidth: Math.min(Design.s(460), diffList.width - Design.s(40))
                                        spacing: Design.s(8)
                                        visible: GitBackend.isRepo && GitBackend.changedFiles.length === 0

                                        Repeater {
                                            model: {
                                                const items = [];
                                                const remote = GitBackend.remoteName || "origin";
                                                if (window.syncAction === "publish")
                                                    items.push({ title: I18n.tr("Publish your branch"), text: I18n.tr("Put %1 on %2.", GitBackend.branchName, remote), button: I18n.tr("Publish branch"), run: "push" });
                                                else if (GitBackend.behindCount > 0)
                                                    items.push({ title: I18n.trn("Pull %1 commit from %2", "Pull %1 commits from %2", GitBackend.behindCount, remote), text: I18n.tr("They're on the remote and not here yet."), button: I18n.tr("Pull"), run: "pull" });
                                                else if (GitBackend.aheadCount > 0)
                                                    items.push({ title: I18n.trn("Push %1 commit to %2", "Push %1 commits to %2", GitBackend.aheadCount, remote), text: I18n.tr("They're only on this machine."), button: I18n.tr("Push"), run: "push" });
                                                if (window.canOpenPr)
                                                    items.push({ title: I18n.tr("Create a pull request"), text: I18n.tr("From %1 into %2.", GitBackend.branchName, GitBackend.defaultBranch), button: I18n.tr("Create pull request"), run: "pr" });
                                                items.push({ title: I18n.tr("Open in the terminal"), text: GitBackend.repoPath, button: I18n.tr("Terminal"), run: "term" });
                                                items.push({ title: I18n.tr("Show in Files"), text: I18n.tr("Browse the repository's folder."), button: I18n.tr("Files"), run: "files" });
                                                if (GitBackend.webUrl !== "")
                                                    items.push({ title: I18n.tr("View on the web"), text: GitBackend.webUrl, button: I18n.tr("Open"), run: "web" });
                                                return items;
                                            }
                                            delegate: Rectangle {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Design.s(52)
                                                radius: Design.s(8)
                                                color: window.colBg
                                                border.color: window.colBorder
                                                border.width: 1
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: Design.s(14)
                                                    anchors.rightMargin: Design.s(10)
                                                    spacing: Design.s(10)
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: Design.s(2)
                                                        Text {
                                                            text: modelData.title
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.body)
                                                            font.bold: true
                                                            color: window.colFg
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: modelData.text
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.caption)
                                                            color: window.colDim
                                                            elide: Text.ElideMiddle
                                                        }
                                                    }
                                                    Rectangle {
                                                        readonly property bool primary: index === 0 && ["push", "pull"].indexOf(modelData.run) >= 0
                                                        Layout.preferredWidth: sugText.implicitWidth + Design.s(20)
                                                        Layout.preferredHeight: Design.s(26)
                                                        radius: Design.s(5)
                                                        opacity: window.busy ? 0.5 : 1
                                                        color: primary ? (sugArea.containsMouse ? Qt.lighter(window.colBlue, 1.1) : window.colBlue)
                                                                       : (sugArea.containsMouse ? Design.tint(Design.text, 0.12) : "transparent")
                                                        border.color: primary ? "transparent" : window.colBorder
                                                        border.width: 1
                                                        Text {
                                                            id: sugText
                                                            anchors.centerIn: parent
                                                            text: modelData.button
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.caption)
                                                            font.bold: true
                                                            color: parent.primary ? Design.accentText : window.colFg
                                                        }
                                                        MouseArea {
                                                            id: sugArea
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            enabled: !window.busy
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                const r = modelData.run;
                                                                if (r === "push") GitBackend.push();
                                                                else if (r === "pull") GitBackend.pull();
                                                                else if (r === "pr") GitBackend.openPullRequest();
                                                                else if (r === "term") GitBackend.openTerminal("");
                                                                else if (r === "files") GitBackend.openFileManager("");
                                                                else if (r === "web") GitBackend.openOnWeb();
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

                        // ── A commit from History ─────────────────────────────
                        // With the History tab up this panel used to go on
                        // showing the working-tree diff, which has nothing to
                        // do with the commit list beside it. Now: what the
                        // commit is, the files it touched, and the diff of the
                        // one picked.
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            visible: window.currentTab === 1

                            // Commit header: subject, author, date, hash, body.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: commitHead.implicitHeight + Design.s(20)
                                visible: GitBackend.selectedCommit !== ""
                                color: Design.tint(Design.ground, 0.8)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: window.colBorder
                                }

                                ColumnLayout {
                                    id: commitHead
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Design.s(14)
                                    anchors.rightMargin: Design.s(14)
                                    spacing: Design.s(4)

                                    Text {
                                        Layout.fillWidth: true
                                        text: GitBackend.commitInfo.subject || ""
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(13)
                                        font.bold: true
                                        color: window.colFg
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Design.s(8)

                                        // One initial-disc per person, the
                                        // author first, overlapping as the
                                        // original stacks its avatars. The
                                        // full list is in the tooltip.
                                        Row {
                                            id: peopleRow
                                            spacing: -Design.s(5)
                                            readonly property var names: [GitBackend.commitInfo.author || ""]
                                                .concat((GitBackend.commitInfo.coAuthors || [])
                                                        .filter(n => n !== GitBackend.commitInfo.author))
                                            Repeater {
                                                model: peopleRow.names
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    required property int index
                                                    z: peopleRow.names.length - index
                                                    width: Design.s(20); height: width; radius: width / 2
                                                    color: [window.colBlue, window.colPurple, window.colGreen, window.colOrange, window.colCyan][index % 5]
                                                    border.color: Design.tint(Design.ground, 0.8)
                                                    border.width: 2
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: window.initials(parent.modelData)
                                                        font.family: Design.font.sans
                                                        font.pixelSize: Design.s(Design.font.caption)
                                                        font.bold: true
                                                        color: Design.accentText
                                                    }
                                                }
                                            }
                                            // A handler, not a MouseArea: an
                                            // Item child of a Row is laid out
                                            // by it, and one sized to the Row
                                            // widens the Row it is sized to —
                                            // the layout pass never ends.
                                            HoverHandler { id: peopleHover }
                                            ToolTip.visible: peopleHover.hovered
                                            ToolTip.delay: 300
                                            ToolTip.text: peopleRow.names.join("\n")
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: window.people(GitBackend.commitInfo.author || "", GitBackend.commitInfo.coAuthors) + "  •  "
                                                  + (GitBackend.commitInfo.date || "") + "  •  "
                                                  + (GitBackend.commitInfo.hash || "") + "  •  "
                                                  + GitBackend.commitFiles.length
                                                  + (GitBackend.commitFiles.length === 1 ? " file" : " files")
                                                  + (GitBackend.selectedCommitSync === "local" ? "  •  not pushed"
                                                     : GitBackend.selectedCommitSync === "pushed" ? "  •  pushed" : "")
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: window.colDim
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: GitBackend.commitInfo.body || ""
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: window.colFg
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 4
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 0
                                visible: GitBackend.selectedCommit !== ""

                                // The commit's files.
                                ListView {
                                    id: commitFileList
                                    Layout.preferredWidth: Math.round(Math.max(Design.s(150), Math.min(Design.s(260), window.width * 0.2)))
                                    Layout.fillHeight: true
                                    clip: true
                                    model: GitBackend.commitFiles
                                    spacing: 1
                                    ScrollBar.vertical: ScrollBar {}

                                    delegate: Rectangle {
                                        id: commitFileRow
                                        width: commitFileList.width
                                        height: Design.s(30)
                                        readonly property bool isSelected: GitBackend.commitFile === modelData.path
                                        color: isSelected ? Design.tint(Design.accent, 0.18)
                                                          : (cfArea.containsMouse ? Design.tint(Design.text, 0.05) : "transparent")

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(10)
                                            anchors.rightMargin: Design.s(8)
                                            spacing: Design.s(8)

                                            Text {
                                                text: window.statusIcon(modelData.status)
                                                font.family: Design.font.mono
                                                font.pixelSize: Design.s(13)
                                                color: window.statusColor(modelData.status)
                                            }

                                            // The name first, the directory
                                            // after it dimmed: in a narrow
                                            // column a middle-elided full path
                                            // hides exactly the part that
                                            // tells two files apart.
                                            Text {
                                                Layout.maximumWidth: commitFileRow.width * 0.6
                                                text: modelData.name
                                                font.family: Design.font.mono
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: window.colFg
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.path.substring(0, modelData.path.length - modelData.name.length)
                                                font.family: Design.font.mono
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: window.colDim
                                                elide: Text.ElideLeft
                                            }
                                        }

                                        MouseArea {
                                            id: cfArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: (mouse) => {
                                                GitBackend.selectCommitFile(modelData.path);
                                                if (mouse.button === Qt.RightButton) {
                                                    window.showMenu(commitFileMenu, modelData.path);
                                                }
                                            }
                                        }

                                        ToolTip.visible: cfArea.containsMouse
                                        ToolTip.delay: 600
                                        ToolTip.text: window.statusWord(modelData.status) + ": "
                                                      + (modelData.oldPath ? modelData.oldPath + " → " + modelData.path
                                                                           : modelData.path)
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 1
                                    Layout.fillHeight: true
                                    color: window.colBorder
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 0

                                    // The path of the file shown, in full —
                                    // the list beside it has room only for
                                    // the name.
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: Design.s(30)
                                        visible: GitBackend.commitFile !== ""
                                        color: Design.tint(Design.ground, 0.4)

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 1
                                            color: window.colBorder
                                        }

                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(12)
                                            anchors.rightMargin: Design.s(12)
                                            verticalAlignment: Text.AlignVCenter
                                            text: GitBackend.commitFile
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.caption)
                                            font.bold: true
                                            color: window.colFg
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    ListView {
                                        id: commitDiffList
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        model: GitBackend.commitDiff
                                        delegate: diffRowDelegate
                                        ScrollBar.vertical: ScrollBar {}

                                        Text {
                                            anchors.centerIn: parent
                                            visible: GitBackend.commitDiff.length === 0
                                            // A rename with identical content
                                            // has no hunks; say what happened
                                            // to it instead of "nothing".
                                            readonly property var shown: GitBackend.commitFiles.find(f => f.path === GitBackend.commitFile)
                                            text: GitBackend.commitFiles.length === 0
                                                  ? I18n.tr("This commit changes no files")
                                                  : (shown && shown.oldPath)
                                                    ? I18n.tr("Renamed from %1, content unchanged", shown.oldPath)
                                                    : I18n.tr("No textual changes in this file")
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.body)
                                            color: window.colDim
                                        }
                                    }
                                }
                            }

                            // Nothing picked yet.
                            ColumnLayout {
                                Layout.alignment: Qt.AlignCenter
                                Layout.fillHeight: true
                                spacing: Design.s(12)
                                visible: GitBackend.selectedCommit === ""

                                Item { Layout.fillHeight: true }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "󰜘"
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(48)
                                    color: window.colDim
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: GitBackend.isRepo ? I18n.tr("Select a commit") : I18n.tr("No Git Repository Open")
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(14)
                                    font.bold: true
                                    color: window.colFg
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: GitBackend.isRepo ? I18n.tr("Its files and changes appear here.")
                                                            : I18n.tr("Select a repository from the top menu or open a folder.")
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.body)
                                    color: window.colDim
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════════════════════════════
                // Clicking outside a popup closes it.
                //
                // Nothing sat behind these, so once one was open the only way
                // to dismiss it was to find the button that opened it — every
                // other click went to whatever was underneath and the popup
                // stayed. Below the popups (z 50) and above the workspace, so
                // it catches the clicks they do not.
                MouseArea {
                    anchors.fill: parent
                    z: 40
                    visible: window.repoDropdownOpen || window.branchDropdownOpen || window.accountsDropdownOpen
                    onClicked: {
                        window.repoDropdownOpen = false;
                        window.branchDropdownOpen = false;
                        window.accountsDropdownOpen = false;
                        window.pendingSwitch = "";
                        window.pendingRemoveWorktree = "";
                        window.pendingDeleteBranch = "";
                        window.pendingTrashRepo = "";
                    }
                }

                // REPOSITORY SELECTOR DROPDOWN POPUP
                // ══════════════════════════════════════════════════════════════
                // Hangs from its cell, flush with its left edge, as the
                // original's does.
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.leftMargin: repoBtn.x
                    width: Math.min(Design.s(420), parent.width - repoBtn.x - Design.s(8))
                    height: Design.s(330)
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

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Repositories")
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(Design.font.body)
                                font.bold: true
                                color: window.colBlue
                            }
                            // No "rescan": the list is what has been opened
                            // here, on purpose. Searching the disk both missed
                            // the repository in use and filled the list with
                            // whatever else it found.
                            Text {
                                text: GitBackend.repos.length + (GitBackend.repos.length === 1 ? " repository" : " repositories")
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(Design.font.caption)
                                color: window.colDim
                            }
                        }

                        // Open a folder the way every other application does.
                        // The only way in used to be typing a path into a text
                        // field, with no browser of any kind.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(30)
                            radius: Design.s(5)
                            color: openArea.containsMouse ? Design.tint(Design.accent, 0.30) : Design.tint(Design.accent, 0.18)
                            border.color: window.colBlue
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: Design.s(6)
                                Text { text: "󰉋"; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: window.colBlue }
                                Text {
                                    text: I18n.tr("Open repository…")
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(11)
                                    font.bold: true
                                    color: window.colFg
                                }
                            }

                            MouseArea {
                                id: openArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: GitBackend.pickRepoFolder()
                            }
                        }

                        // Filter, which doubles as the old path field: a path
                        // typed in full still opens on Enter.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(28)
                            radius: Design.s(5)
                            color: window.colBg
                            border.color: window.colBorder
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(8)
                                anchors.rightMargin: Design.s(8)
                                spacing: Design.s(6)

                                Text { text: "󰍉"; font.family: Design.font.mono; font.pixelSize: Design.s(11); color: window.colDim }

                                TextInput {
                                    id: repoFilterInput
                                    Layout.fillWidth: true
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: window.colFg
                                    selectByMouse: true
                                    clip: true
                                    onTextChanged: window.repoFilter = text
                                    onAccepted: {
                                        if (text.startsWith("/") || text.startsWith("~")) {
                                            GitBackend.addRepo(text.replace("~", window.homePath));
                                            window.repoDropdownOpen = false;
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: repoFilterInput.text === ""
                                        text: I18n.tr("Filter, or type a path")
                                        font: repoFilterInput.font
                                        color: window.colDim
                                    }
                                }
                            }
                        }

                        ListView {
                            id: repoList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 1
                            model: window.filteredRepos

                            delegate: Rectangle {
                                id: repoRowItem
                                required property var modelData
                                width: repoList.width
                                height: Design.s(34)
                                radius: Design.s(4)
                                readonly property bool isCurrent: modelData.path === GitBackend.repoPath
                                color: repoItemArea.containsMouse ? Design.tint(Design.accent, 0.20)
                                     : (isCurrent ? Design.tint(Design.accent, 0.10) : "transparent")

                                MouseArea {
                                    id: repoItemArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) {
                                            window.showMenu(repoListMenu, repoRowItem.modelData.path);
                                            return;
                                        }
                                        GitBackend.openRepo(repoRowItem.modelData.path);
                                        window.repoDropdownOpen = false;
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Design.s(8)
                                    anchors.rightMargin: Design.s(4)
                                    spacing: Design.s(8)

                                    Text { text: "󰊢"; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: window.colBlue }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            text: repoRowItem.modelData.name
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            font.bold: true
                                            color: window.colFg
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: repoRowItem.modelData.path
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: window.colDim
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    // Two different things, so two buttons:
                                    // take it off the list, or delete the
                                    // working tree. Only the first is one
                                    // click; the second asks below, by name.
                                    Rectangle {
                                        Layout.preferredWidth: Design.s(22)
                                        Layout.preferredHeight: Design.s(22)
                                        radius: Design.s(4)
                                        visible: repoItemArea.containsMouse || trashArea.containsMouse || forgetArea.containsMouse
                                        color: trashArea.containsMouse ? Design.tint(Design.danger, 0.30) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰩹"
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(11)
                                            color: trashArea.containsMouse ? window.colRed : window.colDim
                                        }
                                        MouseArea {
                                            id: trashArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            // Never straight to the deletion:
                                            // the confirmation strip below
                                            // names the directory first.
                                            onClicked: window.pendingTrashRepo = repoRowItem.modelData.path
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: Design.s(22)
                                        Layout.preferredHeight: Design.s(22)
                                        radius: Design.s(4)
                                        visible: repoItemArea.containsMouse || trashArea.containsMouse || forgetArea.containsMouse
                                        color: forgetArea.containsMouse ? Design.tint(Design.warn, 0.30) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: forgetArea.containsMouse ? window.colFg : window.colDim
                                        }
                                        MouseArea {
                                            id: forgetArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: GitBackend.forgetRepo(repoRowItem.modelData.path)
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: window.filteredRepos.length === 0
                            text: GitBackend.repos.length === 0
                                ? I18n.tr("Nothing here yet — open a repository with the button above.")
                                : I18n.tr("Nothing matches that filter.")
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(Design.font.caption)
                            color: window.colDim
                            wrapMode: Text.WordWrap
                        }

                        // Deleting the working tree, asked for explicitly and
                        // by name. It goes to the trash rather than being
                        // removed: a repository is somebody's work, and the
                        // file manager beside it treats delete the same way.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(56)
                            visible: window.pendingTrashRepo !== ""
                            radius: Design.s(5)
                            color: Design.tint(Design.danger, 0.15)
                            border.color: window.colRed
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(6)
                                spacing: Design.s(4)

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Move %1 to the trash? This deletes the whole working tree.", window.pendingTrashRepo)
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: window.colFg
                                    wrapMode: Text.WordWrap
                                }

                                RowLayout {
                                    spacing: Design.s(6)
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: I18n.tr("Cancel")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: window.colDim
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Design.s(4)
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.pendingTrashRepo = ""
                                        }
                                    }
                                    Text {
                                        text: I18n.tr("Move to trash")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.bold: true
                                        color: window.colRed
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Design.s(4)
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                GitBackend.trashRepo(window.pendingTrashRepo);
                                                window.pendingTrashRepo = "";
                                            }
                                        }
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
                    anchors.leftMargin: Math.max(0, Math.min(branchBtn.x, parent.width - width))
                    width: Math.min(Design.s(300), parent.width - Design.s(8))
                    height: Math.min(parent.height - Design.s(8),
                                     Design.s(300)
                                     + (window.pendingSwitch !== "" ? Design.s(140) : 0)
                                     + (window.pendingRemoveWorktree !== "" ? Design.s(60) : 0)
                                     + (GitBackend.worktrees.length > 1 ? Design.s(30 + 30 * GitBackend.worktrees.length) : 0))
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
                            text: I18n.tr("Branches")
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(Design.font.body)
                            font.bold: true
                            color: window.colGreen
                        }

                        // Creating a branch needed a terminal before this.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(28)
                            radius: Design.s(5)
                            color: window.colBg
                            border.color: window.colBorder
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(8)
                                anchors.rightMargin: Design.s(4)
                                spacing: Design.s(6)

                                TextInput {
                                    id: newBranchInput
                                    Layout.fillWidth: true
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: window.colFg
                                    selectByMouse: true
                                    clip: true
                                    // Enter opens an existing branch, or creates one with this name.
                                    onAccepted: {
                                        const name = text.trim();
                                        if (name === "") return;
                                        if (GitBackend.branches.indexOf(name) >= 0) {
                                            text = "";
                                            if (name === GitBackend.branchName) return;
                                            if (GitBackend.changedFiles.length > 0) { window.pendingSwitch = name; return; }
                                            window.branchDropdownOpen = false;
                                            GitBackend.switchBranch(name);
                                        } else if (GitBackend.createBranch(name)) {
                                            text = "";
                                            window.branchDropdownOpen = false;
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: newBranchInput.text === ""
                                        text: I18n.tr("Filter, or type a new branch name")
                                        font: newBranchInput.font
                                        color: window.colDim
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: Design.s(52)
                                    Layout.preferredHeight: Design.s(20)
                                    radius: Design.s(3)
                                    opacity: newBranchInput.text.trim() === "" ? 0.4 : 1.0
                                    color: window.colGreen
                                    Text {
                                        anchors.centerIn: parent
                                        text: I18n.tr("New")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.bold: true
                                        color: window.colBg
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: newBranchInput.text.trim() !== ""
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (GitBackend.createBranch(newBranchInput.text)) {
                                                newBranchInput.text = "";
                                                window.branchDropdownOpen = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ListView {
                            id: branchList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 1
                            model: {
                                const q = newBranchInput.text.trim().toLowerCase();
                                return q === "" ? GitBackend.branches
                                                : GitBackend.branches.filter(b => b.toLowerCase().indexOf(q) >= 0);
                            }

                            delegate: Rectangle {
                                id: branchRowItem
                                required property var modelData
                                width: branchList.width
                                height: Design.s(28)
                                radius: Design.s(4)
                                readonly property bool isCurrent: modelData === GitBackend.branchName
                                color: isCurrent ? Design.tint(Design.ok, 0.25)
                                     : (bArea.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")

                                MouseArea {
                                    id: bArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        const wt = (GitBackend.branchInfo[branchRowItem.modelData] || {}).worktree || "";
                                        if (mouse.button === Qt.RightButton) {
                                            branchMenu.worktree = wt;
                                            branchMenu.target = branchRowItem.modelData;
                                            branchMenu.popup();
                                            return;
                                        }
                                        if (branchRowItem.isCurrent) return;
                                        // Checked out elsewhere: open that worktree instead.
                                        if (wt !== "") {
                                            window.branchDropdownOpen = false;
                                            GitBackend.openRepo(wt);
                                            return;
                                        }
                                        // Uncommitted work: ask first, below.
                                        if (GitBackend.changedFiles.length > 0) {
                                            window.pendingSwitch = branchRowItem.modelData;
                                            return;
                                        }
                                        GitBackend.switchBranch(branchRowItem.modelData);
                                        window.branchDropdownOpen = false;
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Design.s(6)
                                    anchors.rightMargin: Design.s(4)
                                    spacing: Design.s(6)

                                    Text { text: ""; font.family: Design.font.mono; font.pixelSize: Design.s(11); color: window.colGreen }
                                    Text {
                                        Layout.fillWidth: true
                                        text: branchRowItem.modelData
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(11)
                                        font.bold: branchRowItem.isCurrent
                                        color: window.colFg
                                        elide: Text.ElideMiddle
                                    }
                                    // Where it stands against its remote.
                                    Text {
                                        readonly property var info: GitBackend.branchInfo[branchRowItem.modelData] || ({})
                                        visible: text !== ""
                                        text: info.worktree ? "in worktree"
                                            : info.gone ? "deleted on remote"
                                            : !info.upstream ? "local only"
                                            : (info.behind > 0 ? info.behind + "↓ " : "") + (info.ahead > 0 ? info.ahead + "↑" : "")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: info.gone ? window.colOrange : window.colDim
                                    }
                                    Text {
                                        text: "✓"
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.bold: true
                                        color: window.colGreen
                                        visible: branchRowItem.isCurrent
                                    }

                                    // Not offered for the branch you are on:
                                    // git refuses that one, and a button whose
                                    // only outcome is an error message is worse
                                    // than no button.
                                    Rectangle {
                                        Layout.preferredWidth: Design.s(20)
                                        Layout.preferredHeight: Design.s(20)
                                        radius: Design.s(4)
                                        visible: !branchRowItem.isCurrent && (bArea.containsMouse || delArea.containsMouse)
                                        color: delArea.containsMouse ? Design.tint(Design.danger, 0.30) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: delArea.containsMouse ? window.colRed : window.colDim
                                        }
                                        MouseArea {
                                            id: delArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                // Plain delete first. git refuses
                                                // one whose work is not merged
                                                // anywhere, and that refusal is
                                                // turned into the question below
                                                // rather than an error nobody can
                                                // act on.
                                                if (!GitBackend.deleteBranch(branchRowItem.modelData, false))
                                                    window.pendingDeleteBranch = branchRowItem.modelData;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Worktrees, only when there is more than the main one.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            visible: GitBackend.worktrees.length > 1

                            Text {
                                text: I18n.tr("Worktrees")
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(Design.font.body)
                                font.bold: true
                                color: window.colGreen
                                bottomPadding: Design.s(4)
                            }

                            Repeater {
                                model: GitBackend.worktrees
                                delegate: Rectangle {
                                    id: wtRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Design.s(30)
                                    radius: Design.s(4)
                                    color: modelData.current ? Design.tint(Design.ok, 0.25)
                                         : (wtArea.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Design.s(6)
                                        anchors.rightMargin: Design.s(6)
                                        spacing: Design.s(6)
                                        Text { text: "󰉋"; font.family: Design.font.mono; font.pixelSize: Design.s(11); color: window.colGreen }
                                        Text {
                                            text: wtRow.modelData.branch || ""
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(11)
                                            font.bold: wtRow.modelData.current
                                            color: window.colFg
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: wtRow.modelData.path
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: window.colDim
                                            elide: Text.ElideLeft
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                    MouseArea {
                                        id: wtArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: (mouse) => {
                                            if (mouse.button === Qt.RightButton) {
                                                worktreeMenu.removable = !wtRow.modelData.main && !wtRow.modelData.current;
                                                worktreeMenu.target = wtRow.modelData.path;
                                                worktreeMenu.popup();
                                                return;
                                            }
                                            if (wtRow.modelData.current) return;
                                            const path = wtRow.modelData.path;
                                            window.branchDropdownOpen = false;
                                            GitBackend.openRepo(path);
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(52)
                            visible: window.pendingRemoveWorktree !== ""
                            radius: Design.s(5)
                            color: Design.tint(Design.danger, 0.15)
                            border.color: window.colRed
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(6)
                                spacing: Design.s(4)
                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Remove the worktree at %1?", window.pendingRemoveWorktree)
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: window.colFg
                                    elide: Text.ElideMiddle
                                }
                                RowLayout {
                                    spacing: Design.s(10)
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: I18n.tr("Cancel")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: window.colDim
                                        MouseArea { anchors.fill: parent; anchors.margins: -Design.s(4); cursorShape: Qt.PointingHandCursor; onClicked: window.pendingRemoveWorktree = "" }
                                    }
                                    Text {
                                        text: I18n.tr("Remove")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.bold: true
                                        color: window.colRed
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Design.s(4)
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const path = window.pendingRemoveWorktree;
                                                window.pendingRemoveWorktree = "";
                                                GitBackend.removeWorktree(path);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Uncommitted changes and a different branch picked:
                        // GitHub Desktop's question.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: switchCol.implicitHeight + Design.s(12)
                            visible: window.pendingSwitch !== ""
                            radius: Design.s(5)
                            color: Design.tint(Design.accent, 0.12)
                            border.color: window.colBlue
                            border.width: 1

                            ColumnLayout {
                                id: switchCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Design.s(6)
                                spacing: Design.s(4)

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.trn("You have %1 changed file on %2.", "You have %1 changed files on %2.",
                                                   GitBackend.changedFiles.length, GitBackend.branchName)
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.caption)
                                    font.bold: true
                                    color: window.colFg
                                    wrapMode: Text.WordWrap
                                }

                                // A fixed model, the wording computed in
                                // the row: a model built from pendingSwitch
                                // was rebuilt — its rows destroyed — the
                                // moment a click cleared it, and the click
                                // handler died halfway through.
                                Repeater {
                                    model: ["stash", "bring"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        readonly property string title: modelData === "stash"
                                            ? I18n.tr("Leave my changes on %1", GitBackend.branchName)
                                            : I18n.tr("Bring my changes to %1", window.pendingSwitch)
                                        readonly property string detail: modelData === "stash"
                                            ? I18n.tr("They are stashed, and offered back when you return.")
                                            : I18n.tr("They come along, uncommitted.")
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Design.s(36)
                                        radius: Design.s(4)
                                        color: optArea.containsMouse ? Design.tint(Design.accent, 0.22) : window.colBg
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(8)
                                            anchors.rightMargin: Design.s(8)
                                            spacing: 0
                                            Text {
                                                Layout.fillWidth: true
                                                text: parent.parent.title
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.bold: true
                                                color: window.colFg
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: parent.parent.detail
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: window.colDim
                                                elide: Text.ElideRight
                                            }
                                        }
                                        MouseArea {
                                            id: optArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const branch = window.pendingSwitch;
                                                const mode = parent.modelData;
                                                window.pendingSwitch = "";
                                                window.branchDropdownOpen = false;
                                                GitBackend.switchBranch(branch, mode);
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignRight
                                    text: I18n.tr("Cancel")
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: window.colDim
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -Design.s(4)
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: window.pendingSwitch = ""
                                    }
                                }
                            }
                        }

                        // The second question, asked only when git said no.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(52)
                            visible: window.pendingDeleteBranch !== ""
                            radius: Design.s(5)
                            color: Design.tint(Design.danger, 0.15)
                            border.color: window.colRed
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(6)
                                spacing: Design.s(4)

                                Text {
                                    Layout.fillWidth: true
                                    text: "\"" + window.pendingDeleteBranch + "\" is not merged anywhere. Deleting it loses its commits."
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: window.colFg
                                    wrapMode: Text.WordWrap
                                }

                                RowLayout {
                                    spacing: Design.s(6)
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: I18n.tr("Cancel")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: window.colDim
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Design.s(4)
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.pendingDeleteBranch = ""
                                        }
                                    }
                                    Text {
                                        text: I18n.tr("Delete anyway")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.bold: true
                                        color: window.colRed
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Design.s(4)
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                GitBackend.deleteBranch(window.pendingDeleteBranch, true);
                                                window.pendingDeleteBranch = "";
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ACCOUNTS POPUP
                // ══════════════════════════════════════════════════════════════
                // One row per hosting service. Signing in runs the service's
                // own CLI in a terminal; with the CLI missing the row says so
                // and offers nothing, rather than a button that cannot work.
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.leftMargin: Math.max(0, Math.min(accountsBtn.x, parent.width - width))
                    width: Design.s(300)
                    height: accCol.implicitHeight + Design.s(20)
                    radius: Design.s(8)
                    color: window.colHeader
                    border.color: window.colBlue
                    border.width: 1
                    z: 50
                    visible: window.accountsDropdownOpen

                    ColumnLayout {
                        id: accCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Design.s(10)
                        spacing: Design.s(8)

                        Text {
                            text: I18n.tr("Accounts")
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(Design.font.body)
                            font.bold: true
                            color: window.colBlue
                        }

                        Repeater {
                            model: GitBackend.accounts

                            delegate: Rectangle {
                                id: accItem
                                required property var modelData
                                readonly property bool signedIn: !!modelData.login
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(46)
                                radius: Design.s(6)
                                color: window.colBg
                                border.color: window.colBorder
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Design.s(10)
                                    anchors.rightMargin: Design.s(8)
                                    spacing: Design.s(10)

                                    Text {
                                        text: accItem.modelData.provider === "github" ? "" : ""
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(18)
                                        color: accItem.modelData.provider === "gitlab" ? window.colOrange : window.colFg
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            text: accItem.modelData.name
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.body)
                                            font.bold: true
                                            color: window.colFg
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: !accItem.modelData.installed ? I18n.tr("%1 is not installed", accItem.modelData.cli)
                                                : accItem.signedIn ? I18n.tr("Signed in as %1", accItem.modelData.login)
                                                : I18n.tr("Not signed in")
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: accItem.signedIn ? window.colGreen : window.colDim
                                        }
                                    }

                                    Rectangle {
                                        visible: accItem.modelData.installed
                                        Layout.preferredWidth: accBtnText.implicitWidth + Design.s(16)
                                        Layout.preferredHeight: Design.s(24)
                                        radius: Design.s(5)
                                        color: accBtnArea.containsMouse
                                               ? (accItem.signedIn ? Design.tint(Design.danger, 0.25) : Qt.lighter(window.colBlue, 1.1))
                                               : (accItem.signedIn ? "transparent" : window.colBlue)
                                        border.color: accItem.signedIn ? window.colBorder : "transparent"
                                        border.width: 1
                                        Text {
                                            id: accBtnText
                                            anchors.centerIn: parent
                                            text: accItem.signedIn ? I18n.tr("Sign out") : I18n.tr("Sign in")
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            font.bold: !accItem.signedIn
                                            color: accItem.signedIn ? window.colFg : Design.accentText
                                        }
                                        MouseArea {
                                            id: accBtnArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (accItem.signedIn) GitBackend.signOut(accItem.modelData.provider);
                                                else {
                                                    GitBackend.signIn(accItem.modelData.provider);
                                                    window.accountsDropdownOpen = false;
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
        }
    }

    // The dialog from window.ask().
    Rectangle {
        parent: window.contentItem
        anchors.fill: parent
        z: 95
        visible: window.dialog !== null
        color: Qt.rgba(0, 0, 0, 0.45)

        MouseArea { anchors.fill: parent; onClicked: window.closeDialog(false) }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Design.s(40), Design.s(400))
            height: dialogCol.implicitHeight + Design.s(32)
            radius: Design.s(10)
            color: window.colHeader
            border.color: window.colBorder
            border.width: 1

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: dialogCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Design.s(16)
                spacing: Design.s(10)

                Text {
                    text: window.dialog ? window.dialog.title : ""
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(14)
                    font.bold: true
                    color: window.colFg
                }
                Text {
                    Layout.fillWidth: true
                    text: window.dialog ? (window.dialog.text || "") : ""
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(Design.font.caption)
                    color: window.colDim
                    wrapMode: Text.Wrap
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(30)
                    visible: window.dialog !== null && window.dialog.input === true
                    radius: Design.s(5)
                    color: window.colBg
                    border.color: dialogInput.activeFocus ? window.colBlue : window.colBorder
                    border.width: 1
                    TextInput {
                        id: dialogInput
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(8)
                        anchors.rightMargin: Design.s(8)
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Design.font.mono
                        font.pixelSize: Design.s(Design.font.body)
                        color: window.colFg
                        selectByMouse: true
                        clip: true
                        onAccepted: window.closeDialog(true)
                        Keys.onEscapePressed: window.closeDialog(false)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: dialogInput.text === ""
                            text: window.dialog ? (window.dialog.placeholder || "") : ""
                            font: dialogInput.font
                            color: window.colDim
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(8)
                    Item { Layout.fillWidth: true }
                    Repeater {
                        model: ["cancel", "confirm"]
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool isConfirm: modelData === "confirm"
                            readonly property bool danger: isConfirm && window.dialog !== null && window.dialog.destructive === true
                            Layout.preferredWidth: dlgBtnText.implicitWidth + Design.s(24)
                            Layout.preferredHeight: Design.s(28)
                            radius: Design.s(5)
                            color: !isConfirm ? (dlgBtnArea.containsMouse ? Design.tint(Design.text, 0.12) : "transparent")
                                 : danger ? (dlgBtnArea.containsMouse ? Qt.lighter(window.colRed, 1.1) : window.colRed)
                                 : (dlgBtnArea.containsMouse ? Qt.lighter(window.colBlue, 1.1) : window.colBlue)
                            border.color: isConfirm ? "transparent" : window.colBorder
                            border.width: 1
                            Text {
                                id: dlgBtnText
                                anchors.centerIn: parent
                                text: parent.isConfirm ? (window.dialog ? (window.dialog.confirm || "OK") : "OK") : I18n.tr("Cancel")
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(Design.font.caption)
                                font.bold: parent.isConfirm
                                color: parent.isConfirm ? Design.accentText : window.colFg
                            }
                            MouseArea {
                                id: dlgBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.closeDialog(parent.isConfirm)
                            }
                        }
                    }
                }
            }
        }
    }

    // What just happened, or what went wrong. Errors stay until clicked.
    Connections {
        target: GitBackend
        function onNotice(message) { toast.show(message, false); }
        function onCommandFailed(message) { toast.show(message, true); }
    }

    Rectangle {
        id: toast
        property bool isError: false
        property string message: ""

        function show(msg, err) {
            toast.message = msg;
            toast.isError = err;
            hideTimer.interval = err ? 8000 : 2500;
            hideTimer.restart();
            toast.shown = true;
        }
        property bool shown: false

        parent: window.contentItem
        z: 100
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - (shown ? height + Design.s(24) : -Design.s(10))
        width: Math.min(parent.width - Design.s(40), toastRow.implicitWidth + Design.s(28))
        height: toastRow.implicitHeight + Design.s(18)
        radius: Design.s(10)
        color: window.colHeader
        border.color: isError ? window.colRed : window.colBorder
        border.width: 1
        opacity: shown ? 1 : 0
        visible: opacity > 0

        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Timer { id: hideTimer; onTriggered: toast.shown = false }

        RowLayout {
            id: toastRow
            anchors.centerIn: parent
            width: Math.min(implicitWidth, toast.parent.width - Design.s(68))
            spacing: Design.s(10)
            Text {
                text: toast.isError ? "󰀦" : "󰄬"
                font.family: Design.font.icon
                font.pixelSize: Design.s(15)
                color: toast.isError ? window.colRed : window.colGreen
                Layout.alignment: Qt.AlignTop
            }
            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: Design.s(520)
                text: toast.message
                font.family: Design.font.sans
                font.pixelSize: Design.s(Design.font.body)
                color: window.colFg
                wrapMode: Text.Wrap
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toast.shown = false
        }
    }
}
