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
    palette.light: Design.active
    palette.midlight: Design.hover
    palette.mid: Design.line
    palette.dark: Design.sunken
    palette.shadow: Design.ground
    title: GitBackend.repoName ? I18n.tr("Git — %1", GitBackend.repoName) : I18n.tr("Git")
    width: Design.s(Design.window.largeWidth)
    height: Design.s(Design.window.largeHeight)
    // Low enough for a window tiled to half a small screen; the layout
    // follows the width from there (sidebar, toolbar cells, file lists).
    minimumWidth: Design.s(Design.window.minWidth)
    minimumHeight: Design.s(Design.window.minHeight)
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
        Action { text: I18n.tr("Open in Editor"); onTriggered: GitBackend.openInEditor(repoMenu.target) }
        AppMenuSeparator {}
        Action { text: I18n.tr("Repository settings…"); onTriggered: settingsDialog.show() }
        Action {
            text: I18n.tr("Publish to GitHub…")
            enabled: !GitBackend.hasRemote
            onTriggered: publishDialog.show()
        }
        AppMenuSeparator {}
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
        AppMenuSeparator {}
        Action { text: I18n.tr("Copy path"); onTriggered: GitBackend.copyText(GitBackend.absolutePath(repoMenu.target)) }
    }
    // A repository in the list, which may not be the open one: target is
    // its absolute path, and the actions go straight to the tools.
    ContextMenu {
        id: repoListMenu
        Action { text: I18n.tr("Open"); onTriggered: { GitBackend.openRepo(repoListMenu.target); } }
        Action { text: I18n.tr("Open in Terminal"); onTriggered: GitBackend.openTerminal(repoListMenu.target) }
        Action { text: I18n.tr("Show in Files"); onTriggered: GitBackend.openFileManager(repoListMenu.target) }
        AppMenuSeparator {}
        Action { text: I18n.tr("Copy path"); onTriggered: GitBackend.copyText(repoListMenu.target) }
    }
    // A changed file. Stage and unstage are already a click on the checkbox;
    // here too because a right-click is where people look for them.
    ContextMenu {
        id: fileMenu
        property bool staged: false
        property bool conflicted: false
        Action { text: I18n.tr("Open"); onTriggered: GitBackend.openFile(fileMenu.target) }
        Action { text: I18n.tr("Open in Editor"); onTriggered: GitBackend.openInEditor(fileMenu.target) }
        Action {
            text: I18n.tr("Open submodule")
            enabled: GitBackend.submodules.some(m => m.path === fileMenu.target)
            onTriggered: GitBackend.openRepo(GitBackend.absolutePath(fileMenu.target))
        }
        Action { text: I18n.tr("Show in Files"); onTriggered: GitBackend.openFileManager(fileMenu.target) }
        Action { text: I18n.tr("Open folder in Terminal"); onTriggered: GitBackend.openTerminal(fileMenu.target) }
        AppMenuSeparator { visible: fileMenu.conflicted }
        // A conflict settled with one side whole, as GitHub Desktop offers it.
        Action {
            text: I18n.tr("Use my version (%1)", GitBackend.branchName)
            enabled: fileMenu.conflicted
            onTriggered: GitBackend.resolveWith(fileMenu.target, "mine")
        }
        Action {
            text: I18n.tr("Use their version (%1)", GitBackend.mergeState.branch || I18n.tr("incoming"))
            enabled: fileMenu.conflicted
            onTriggered: GitBackend.resolveWith(fileMenu.target, "theirs")
        }
        AppMenuSeparator {}
        Action { text: I18n.tr("Copy path"); onTriggered: GitBackend.copyText(GitBackend.absolutePath(fileMenu.target)) }
        Action { text: I18n.tr("Copy relative path"); onTriggered: GitBackend.copyText(fileMenu.target) }
        AppMenuSeparator {}
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
        AppMenuSeparator {}
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

    // A commit dragged onto another in History: where it goes.
    ContextMenu {
        id: dropMenu
        property string hash: ""
        property int index: -1
        property string subject: ""
        Action {
            text: I18n.tr("Move above “%1”", dropMenu.subject)
            onTriggered: GitBackend.reorderCommit(dropMenu.hash, dropMenu.target, false)
        }
        Action {
            readonly property string below: GitBackend.history.hashAt(dropMenu.index + 1)
            text: I18n.tr("Move below “%1”", dropMenu.subject)
            enabled: below !== "" && below !== dropMenu.hash
            onTriggered: GitBackend.reorderCommit(dropMenu.hash, below, false)
        }
        AppMenuSeparator {}
        Action {
            text: I18n.tr("Squash into “%1”", dropMenu.subject)
            onTriggered: GitBackend.reorderCommit(dropMenu.hash, dropMenu.target, true)
        }
    }

    // Lines of the diff, on a right click on their numbers.
    ContextMenu {
        id: lineMenu
        property var rows: []
        Action {
            text: lineMenu.rows.length === 1 ? I18n.tr("Discard this line…") : I18n.tr("Discard these lines…")
            onTriggered: {
                const rows = lineMenu.rows;
                window.ask({
                    title: rows.length === 1 ? I18n.tr("Discard this line?") : I18n.tr("Discard these lines?"),
                    text: I18n.tr("The change goes back to what the last commit has. A copy of the file goes to the trash."),
                    confirm: I18n.tr("Discard"), destructive: true,
                    accept: () => GitBackend.discardLines(rows)
                });
            }
        }
    }

    ContextMenu {
        id: changesMenu
        Action { text: I18n.tr("Stage all"); onTriggered: GitBackend.stageAll() }
        Action { text: I18n.tr("Unstage all"); onTriggered: GitBackend.unstageAll() }
        AppMenuSeparator {}
        Action {
            text: I18n.tr("Stash all changes")
            enabled: GitBackend.changedFiles.length > 0 && GitBackend.branchStash.ref === undefined
            onTriggered: GitBackend.stashAll()
        }
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
        AppMenuSeparator {}
        Action { text: I18n.tr("Copy path"); onTriggered: GitBackend.copyText(GitBackend.absolutePath(commitFileMenu.target)) }
        Action { text: I18n.tr("Copy relative path"); onTriggered: GitBackend.copyText(commitFileMenu.target) }
    }
    ContextMenu {
        id: commitMenu
        property string subject: ""
        // On no remote yet: history that may be rewritten.
        property bool local: false
        property bool isHead: false
        // The commit before it is on no remote either, so the two can swap.
        property bool olderLocal: false
        property bool pushed: false
        property var tags: []
        Action { text: I18n.tr("Copy SHA"); onTriggered: GitBackend.copyText(commitMenu.target) }
        Action { text: I18n.tr("Copy message"); onTriggered: GitBackend.copyText(commitMenu.subject) }
        Action {
            text: GitBackend.webUrl.indexOf("gitlab") >= 0 ? I18n.tr("View on GitLab") : I18n.tr("View on GitHub")
            enabled: GitBackend.webUrl !== "" && commitMenu.pushed
            onTriggered: GitBackend.openCommitOnWeb(commitMenu.target)
        }
        AppMenuSeparator {}
        Action {
            text: I18n.tr("Amend commit…")
            enabled: commitMenu.isHead && GitBackend.lastCommit.canAmend === true && !window.busy
            onTriggered: window.startAmend()
        }
        // Any commit on no remote yet, not only the last: its message, its
        // files, its place, or gone.
        Action {
            text: I18n.tr("Edit message…")
            enabled: commitMenu.local && !window.busy
                     && GitBackend.changedFiles.length === 0
            onTriggered: rewordDialog.show(commitMenu.target)
        }
        Action {
            text: I18n.tr("Edit commit's changes")
            enabled: commitMenu.local && !window.busy && GitBackend.changedFiles.length === 0
            onTriggered: GitBackend.editCommit(commitMenu.target)
        }
        Action {
            text: I18n.tr("Move up (later)")
            enabled: commitMenu.local && !commitMenu.isHead && !window.busy && GitBackend.changedFiles.length === 0
            onTriggered: GitBackend.moveCommit(commitMenu.target, 1)
        }
        Action {
            text: I18n.tr("Move down (earlier)")
            enabled: commitMenu.local && commitMenu.olderLocal && !window.busy && GitBackend.changedFiles.length === 0
            onTriggered: GitBackend.moveCommit(commitMenu.target, -1)
        }
        Action {
            text: I18n.tr("Squash into previous commit")
            enabled: commitMenu.local && !window.busy && GitBackend.changedFiles.length === 0
            onTriggered: {
                const hash = commitMenu.target;
                window.ask({ title: I18n.tr("Squash commit?"),
                             text: I18n.tr("It becomes part of the commit before it, both messages kept."),
                             confirm: I18n.tr("Squash"), accept: () => GitBackend.squashIntoParent(hash) });
            }
        }
        Action {
            text: I18n.tr("Drop commit…")
            enabled: commitMenu.local && !window.busy && GitBackend.changedFiles.length === 0
            onTriggered: {
                const hash = commitMenu.target;
                window.ask({ title: I18n.tr("Drop this commit?"),
                             text: I18n.tr("Its changes are taken out of the branch, and the commits after it are rewritten without them."),
                             confirm: I18n.tr("Drop"), destructive: true,
                             accept: () => GitBackend.dropCommit(hash) });
            }
        }
        Action {
            text: I18n.tr("Reset to this commit…")
            // Only while what it undoes is this machine's alone.
            enabled: !commitMenu.isHead && !window.busy
                     && (!GitBackend.hasRemote || GitBackend.upstream === "" || GitBackend.aheadCount > 0)
            onTriggered: {
                const hash = commitMenu.target;
                window.ask({ title: I18n.tr("Reset to this commit?"),
                             text: I18n.tr("%1 moves back here. The commits after it are undone; their changes stay as uncommitted changes.", GitBackend.branchName),
                             confirm: I18n.tr("Reset"), destructive: true,
                             accept: () => GitBackend.resetToCommit(hash) });
            }
        }
        Action {
            text: I18n.tr("Cherry-pick onto branch…")
            enabled: !window.busy
            onTriggered: {
                const hash = commitMenu.target;
                window.ask({ title: I18n.tr("Cherry-pick commit"),
                             text: I18n.tr("Copy this commit onto a branch. Leave the name as it is for the current one."),
                             input: true, value: GitBackend.branchName, placeholder: I18n.tr("Branch name"),
                             confirm: I18n.tr("Cherry-pick"),
                             accept: v => GitBackend.cherryPick(hash, v) });
            }
        }
        AppMenuSeparator {}
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
            text: commitMenu.tags.length ? I18n.tr("Delete tag %1…", commitMenu.tags[0]) : I18n.tr("Delete tag…")
            enabled: commitMenu.tags.length > 0
            onTriggered: {
                const tag = commitMenu.tags[0];
                window.ask({ title: I18n.tr("Delete tag %1?", tag),
                             text: I18n.tr("Only here; a copy already pushed stays on the remote."),
                             confirm: I18n.tr("Delete"), destructive: true,
                             accept: () => GitBackend.deleteTag(tag) });
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
    // The three dropdowns are Ui's Popover now; the flags stay the one way
    // the rest of the file opens and closes them.
    onRepoDropdownOpenChanged: repoDropdownOpen ? repoPop.open() : repoPop.close()
    onBranchDropdownOpenChanged: {
        if (!branchDropdownOpen) { branchPop.close(); return; }
        branchPop.open();
        if (window.branchView === "prs") GitBackend.refreshPullRequests();
    }
    onAccountsDropdownOpenChanged: accountsDropdownOpen ? accountsPop.open() : accountsPop.close()
    // Closed by Esc or a click outside: clear what was half-done in it.
    function closeDropdowns() {
        window.repoDropdownOpen = false;
        window.branchDropdownOpen = false;
        window.accountsDropdownOpen = false;
        window.pendingSwitch = "";
        window.pendingRemoveWorktree = "";
        window.pendingDeleteBranch = "";
        window.pendingTrashRepo = "";
    }

    property var dialog: null
    function ask(spec) {
        window.repoDropdownOpen = false;
        window.accountsDropdownOpen = false;
        window.dialog = spec;
        dialogInput.text = spec.value || "";
        askDialog.open();
        if (spec.input) dialogInput.focusInput();
    }
    function closeDialog(accepted) {
        const d = window.dialog;
        window.dialog = null;
        if (accepted && d && d.accept) {
            const v = dialogInput.text.trim();
            // Nothing typed: ask again rather than act on an empty name.
            if (d.input && v === "") { window.ask(d); return; }
            d.accept(v);
        }
    }

    // A branch switch waiting on what to do with uncommitted changes.
    property string pendingSwitch: ""
    property string pendingRemoveWorktree: ""

    ContextMenu {
        id: branchMenu
        property string worktree: ""
        property bool remote: false
        readonly property bool isCurrent: branchMenu.target === GitBackend.branchName
        Action {
            text: I18n.tr("Merge into %1", GitBackend.branchName)
            enabled: !branchMenu.isCurrent && !GitBackend.mergeState.active
            onTriggered: { window.branchDropdownOpen = false; GitBackend.mergeBranch(branchMenu.target); }
        }
        Action {
            text: I18n.tr("Rebase %1 onto this", GitBackend.branchName)
            enabled: !branchMenu.isCurrent && !GitBackend.mergeState.active && GitBackend.changedFiles.length === 0
            onTriggered: {
                const onto = branchMenu.target;
                window.branchDropdownOpen = false;
                window.ask({ title: I18n.tr("Rebase %1?", GitBackend.branchName),
                             text: I18n.tr("Its own commits are replayed on top of %1. If they were pushed, pushing again needs a force push.", onto),
                             confirm: I18n.tr("Rebase"), accept: () => GitBackend.rebaseBranch(onto) });
            }
        }
        Action {
            text: I18n.tr("Rename…")
            enabled: !branchMenu.remote
            onTriggered: {
                const from = branchMenu.target;
                window.ask({ title: I18n.tr("Rename branch"), text: I18n.tr("New name for %1.", from),
                             input: true, value: from, placeholder: I18n.tr("Branch name"), confirm: I18n.tr("Rename"),
                             accept: v => GitBackend.renameBranch(from, v) });
            }
        }
        AppMenuSeparator {}
        Action {
            text: branchMenu.worktree !== "" ? I18n.tr("Open its worktree") : I18n.tr("Open in new worktree")
            enabled: !branchMenu.isCurrent && !branchMenu.remote
            onTriggered: {
                const path = branchMenu.worktree !== "" ? branchMenu.worktree
                                                        : GitBackend.createWorktree(branchMenu.target);
                if (path !== "") { window.branchDropdownOpen = false; GitBackend.openRepo(path); }
            }
        }
    }

    // Every way to talk to the remote, on the sync cell's right click; the
    // cell itself does the one that applies.
    ContextMenu {
        id: syncMenu
        Action { text: I18n.tr("Fetch"); enabled: GitBackend.hasRemote && !window.busy; onTriggered: GitBackend.fetch() }
        Action { text: I18n.tr("Pull"); enabled: GitBackend.upstream !== "" && !window.busy; onTriggered: GitBackend.pull() }
        Action { text: I18n.tr("Push"); enabled: GitBackend.hasRemote && !window.busy; onTriggered: GitBackend.push() }
        AppMenuSeparator {}
        Action {
            text: I18n.tr("Force push…")
            enabled: GitBackend.upstream !== "" && !window.busy && GitBackend.aheadCount > 0
            onTriggered: window.ask({
                title: I18n.tr("Force push %1?", GitBackend.branchName),
                text: I18n.tr("What %1 has for this branch is replaced by yours. It is refused if someone pushed since the last fetch.", GitBackend.remoteName),
                confirm: I18n.tr("Force push"), destructive: true,
                accept: () => GitBackend.forcePush()
            })
        }
        AppMenuSeparator {}
        Action {
            text: I18n.tr("Update from %1", GitBackend.defaultBranch)
            enabled: GitBackend.defaultBranch !== "" && GitBackend.defaultBranch !== GitBackend.branchName && !window.busy
                     && !GitBackend.mergeState.active
            onTriggered: GitBackend.updateFromDefault()
        }
        Action {
            text: I18n.tr("Publish to GitHub…")
            enabled: !GitBackend.hasRemote && window.hasRepo
            onTriggered: publishDialog.show()
        }
    }

    ContextMenu {
        id: worktreeMenu
        property bool removable: false
        Action { text: I18n.tr("Open"); onTriggered: { window.branchDropdownOpen = false; GitBackend.openRepo(worktreeMenu.target); } }
        Action { text: I18n.tr("Open in Terminal"); onTriggered: GitBackend.openTerminal(worktreeMenu.target) }
        Action { text: I18n.tr("Show in Files"); onTriggered: GitBackend.openFileManager(worktreeMenu.target) }
        AppMenuSeparator {}
        Action { text: I18n.tr("Copy path"); onTriggered: GitBackend.copyText(worktreeMenu.target) }
        Action {
            text: I18n.tr("Remove worktree…")
            enabled: worktreeMenu.removable
            onTriggered: { window.branchDropdownOpen = true; window.pendingRemoveWorktree = worktreeMenu.target; }
        }
    }

    // Half of a side-by-side row: one line, its number, and (in the working
    // tree's diff) the number as the place to stage it.
    component SplitHalf: Rectangle {
        id: half
        property var side: null
        property bool working: false
        readonly property real textHeight: halfText.implicitHeight
        readonly property bool stageable: working && !!side && side.canStage === true
        clip: true
        color: !side ? Design.tint(Design.text, 0.03)
             : side.type === "add" ? Design.tint(Design.ok, 0.10)
             : side.type === "del" ? Design.tint(Design.danger, 0.11) : "transparent"
        Rectangle {
            visible: !!half.side && (half.side.type === "add" || half.side.type === "del")
            width: Design.s(Design.focusWidth)
            height: parent.height
            color: half.side && half.side.type === "add" ? Design.ok : Design.danger
        }
        Rectangle {
            visible: half.stageable
            x: Design.s(Design.focusWidth)
            width: Design.s(Design.size.row) - Design.s(Design.focusWidth)
            height: parent.height
            color: half.side && half.side.staged ? Design.tint(Design.accent, halfArea.containsMouse ? 0.55 : 0.4)
                 : halfArea.containsMouse ? Design.tint(Design.accent, 0.15) : "transparent"
        }
        MouseArea {
            id: halfArea
            enabled: half.stageable
            width: Design.s(Design.size.row)
            height: parent.height
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    lineMenu.rows = [half.side.i];
                    window.showMenu(lineMenu, "");
                } else {
                    GitBackend.setLinesStaged([half.side.i], !half.side.staged);
                }
            }
        }
        Rectangle {
            visible: !!half.side && !!half.side.chg && (!!half.side.html || half.side.text.indexOf("\t") < 0)
            x: Design.s(Design.size.row) + (visible ? window.colX(half.side.text, half.side.chg[0]) : 0)
            width: visible ? window.colX(half.side.text, half.side.chg[1]) - window.colX(half.side.text, half.side.chg[0]) : 0
            height: parent.height
            color: half.side && half.side.type === "add" ? Design.tint(Design.ok, 0.28) : Design.tint(Design.danger, 0.30)
        }
        Text {
            width: Design.s(Design.size.row)
            anchors.verticalCenter: parent.verticalCenter
            text: half.side && half.side.n !== undefined ? String(half.side.n) : ""
            horizontalAlignment: Text.AlignRight
            rightPadding: 8
            font.family: Design.font.mono
            font.pixelSize: Design.s(Design.font.caption)
            color: Design.textDim
        }
        Text {
            id: halfText
            x: Design.s(Design.size.row)
            anchors.verticalCenter: parent.verticalCenter
            // Coloured code (syntax.cpp) where the language is known.
            textFormat: half.side && half.side.html ? Text.StyledText : Text.PlainText
            text: !half.side ? "" : half.side.html ? half.side.html : half.side.text
            font.family: Design.font.mono
            font.pixelSize: Design.s(Design.font.caption)
            color: Design.text
        }
    }

    // A picture before and after, side by side, on a checked ground so
    // transparency shows.
    component ImageCompare: Item {
        id: cmp
        property var pair: ({ before: "", after: "" })
        RowLayout {
            anchors.fill: parent
            anchors.margins: Design.s(Design.space.md)
            spacing: Design.s(Design.space.md)
            Repeater {
                model: [{ label: I18n.tr("Before"), url: cmp.pair.before || "", tone: Design.danger },
                        { label: I18n.tr("After"), url: cmp.pair.after || "", tone: Design.ok }]
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Design.s(Design.space.xs)
                    RowLayout {
                        Layout.fillWidth: true
                        Label { role: "caption"; weight: Design.weight.semibold; color: modelData.tone; text: modelData.label }
                        Label {
                            Layout.fillWidth: true
                            role: "caption"; dim: true
                            horizontalAlignment: Text.AlignRight
                            text: pic.status === Image.Ready ? pic.implicitWidth + " × " + pic.implicitHeight : ""
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Design.s(Design.radius.ctl)
                        color: Design.sunken
                        border.color: Design.tint(modelData.tone, 0.5)
                        border.width: Design.border
                        clip: true
                        Image {
                            id: pic
                            anchors.fill: parent
                            anchors.margins: Design.s(Design.space.sm)
                            source: modelData.url
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                        }
                        Label {
                            anchors.centerIn: parent
                            visible: modelData.url === ""
                            role: "caption"; dim: true
                            text: I18n.tr("None")
                        }
                    }
                }
            }
        }
    }

    // One cell of the toolbar: the repository, the branch, the sync, and the
    // compact tools on the right. One line at a control's height, as every
    // button in the suite; what each cell is ("Current repository") is its
    // tooltip — the two-line 60 px cells were GitHub Desktop's, not ours.
    component ToolbarCell: Rectangle {
        id: cell
        property string icon: ""
        property string caption: ""
        property string title: ""
        property string badge: ""
        property bool spinning: false
        property bool dropdown: false
        property bool open: false
        // compact: sized to its text — for the tools on the right.
        property bool compact: false
        // flat: a row of the sidebar (the repository, the branch) — its whole
        // width, no fill or outline until it is pointed at or open.
        property bool flat: false
        property bool leftDivider: false
        signal clicked()
        signal rightClicked()

        Layout.alignment: Qt.AlignVCenter
        Layout.preferredHeight: Design.s(Design.size.md)
        // The three main cells share the bar's width up to their natural
        // size: in a window tiled to half a screen they still fit.
        Layout.preferredWidth: compact ? cellRow.implicitWidth + Design.s(Design.space.md) * 2 : flat ? -1 : Design.s(Design.width.select)
        Layout.maximumWidth: compact ? cellRow.implicitWidth + Design.s(Design.space.md) * 2 : flat ? Number.POSITIVE_INFINITY : Design.s(Design.width.select)
        Layout.minimumWidth: compact ? cellRow.implicitWidth + Design.s(Design.space.md) * 2 : flat ? 0 : Design.s(Design.width.field)
        Layout.fillWidth: !compact
        radius: Design.s(Design.radius.ctl)
        border.width: flat ? 0 : Design.border
        border.color: open ? Design.tint(Design.accent, 0.35) : Design.glassBorder
        color: open ? Design.selection
             : flat ? (cellArea.pressed && enabled ? Design.active
                       : cellArea.containsMouse && enabled ? Design.glassHover : "transparent")
             : Design.translucent
               ? (cellArea.pressed && enabled ? Design.tint(Design.text, 0.20)
                  : cellArea.containsMouse && enabled ? Design.veilBold : Design.well)
               : (cellArea.pressed && enabled ? Design.active
                  : cellArea.containsMouse && enabled ? Design.hover : Design.raised)
        opacity: enabled || spinning ? 1.0 : Design.opacity.disabled

        Behavior on color { ColorAnimation { duration: Design.duration.fast } }

        // Not anchors.fill: a compact cell takes its width from this row, and
        // a row that also filled the cell would make that width depend on
        // itself.
        RowLayout {
            id: cellRow
            x: Design.s(Design.space.md)
            width: cell.compact ? implicitWidth : cell.width - Design.s(Design.space.md) * 2
            height: parent.height
            spacing: Design.s(Design.space.sm)

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: cellIcon.implicitWidth
                implicitHeight: cellIcon.implicitHeight
                Icon {
                    id: cellIcon
                    anchors.centerIn: parent
                    visible: !cell.spinning
                    text: cell.icon
                    role: "body"
                    color: cell.open ? Design.accent : Design.text
                }
                // A separate glyph, so the icon is never left at an angle.
                Icon {
                    id: cellSpinner
                    anchors.centerIn: parent
                    visible: cell.spinning
                    text: "󰝲"
                    role: "body"
                    color: Design.accent
                    RotationAnimator on rotation {
                        running: cellSpinner.visible
                        from: 0; to: 360; duration: 900
                        loops: Animation.Infinite
                    }
                }
            }

            Label {
                Layout.fillWidth: !cell.compact
                Layout.alignment: Qt.AlignVCenter
                text: cell.title
                weight: cell.compact ? Design.weight.regular : Design.weight.medium
                elide: Text.ElideRight
            }

            Badge {
                visible: cell.badge !== ""
                Layout.alignment: Qt.AlignVCenter
                text: cell.badge
                tone: Design.textDim
            }

            Icon {
                visible: cell.dropdown
                text: cell.open ? "󰅃" : "󰅀"
                role: "caption"
                color: Design.textDim
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

        ToolTip.visible: cellArea.containsMouse && cell.caption !== ""
        ToolTip.delay: 600
        ToolTip.text: cell.caption

        activeFocusOnTab: cell.enabled
        Accessible.role: Accessible.Button
        Accessible.name: cell.caption !== "" ? cell.caption + ": " + cell.title : cell.title
        Keys.onReturnPressed: event => { cell.clicked(); event.accepted = true; }
        Keys.onSpacePressed: event => { cell.clicked(); event.accepted = true; }
        FocusRing { target: cell }
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
    readonly property string syncAction: !window.hasRepo ? "none"
        : !GitBackend.hasRemote ? "publishRepo"
        : GitBackend.upstream === "" ? "publish"
        : GitBackend.behindCount > 0 ? "pull"
        : GitBackend.aheadCount > 0 ? "push" : "fetch"
    property bool repoDropdownOpen: false
    // A commit being dragged in History, and the row it is over.
    property string dragHash: ""
    property int dragOver: -1
    // The branch list or the pull requests, in the branch dropdown.
    property string branchView: "branches"
    readonly property bool onGithub: GitBackend.webUrl.indexOf("github.com") >= 0
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
    // Code in the theme's colours (syntax.cpp), handed over again when the
    // theme changes.
    readonly property var syntaxPalette: ({
        keyword: String(Design.mauve), string: String(Design.green), comment: String(Design.textFaint),
        number: String(Design.peach), type: String(Design.yellow)
    })
    onSyntaxPaletteChanged: GitBackend.setSyntaxPalette(window.syntaxPalette)
    Component.onCompleted: GitBackend.setSyntaxPalette(window.syntaxPalette)

    // The diff's monospace advance, to place the marks under changed words
    // (the rows' "chg", in columns).
    FontMetrics {
        id: monoMetrics
        font.family: Design.font.mono
        font.pixelSize: Design.s(Design.font.caption)
    }
    // Where column `col` of a line starts, measured on the line itself: a
    // multiple of one character's width drifts, the drawn advances being
    // rounded. Tabs as the coloured lines draw them, four spaces.
    function colX(text, col) {
        return monoMetrics.advanceWidth(String(text || "").replace(/\t/g, "    ").slice(0, col));
    }

    // Unified or side by side, remembered.
    property bool splitDiff: false
    Settings {
        category: "diff"
        property alias split: window.splitDiff
    }

    // The diff's rows as pairs for side by side: a run of removed lines next
    // to the run of added lines after it, line for line; context on both
    // sides. Each side keeps its row's index, for staging.
    function splitRows(rows) {
        const out = [];
        const side = (r, i) => r ? { n: r.type === "add" ? r.newLine : r.oldLine, text: r.text.slice(1), type: r.type,
                                    i: i, staged: r.staged === true, canStage: r.canStage === true, html: r.html || "",
                                    chg: r.chg || null } : null;
        let dels = [], adds = [];
        const flush = () => {
            for (let k = 0; k < Math.max(dels.length, adds.length); ++k)
                out.push({ kind: "pair", l: dels[k] || null, r: adds[k] || null });
            dels = []; adds = [];
        };
        for (let i = 0; i < rows.length; ++i) {
            const r = rows[i];
            if (r.type === "del") { if (adds.length) flush(); dels.push(side(r, i)); continue; }
            if (r.type === "add") { adds.push(side(r, i)); continue; }
            flush();
            if (r.type === "header") { out.push({ kind: "header", text: r.text, i: i }); continue; }
            if (r.text.startsWith("\\")) continue;
            out.push({ kind: "pair", l: { n: r.oldLine, text: r.text.slice(1), type: "ctx", i: i, html: r.html || "" },
                                     r: { n: r.newLine, text: r.text.slice(1), type: "ctx", i: i, html: r.html || "" } });
        }
        flush();
        return out;
    }

    // Pictures are compared as pictures.
    function isImage(path) {
        return /\.(png|jpe?g|gif|webp|bmp|svg|ico|avif)$/i.test(path || "");
    }

    // The stageable rows of the hunk whose header is row i of the diff.
    function hunkRows(i) {
        const rows = [];
        const d = GitBackend.currentDiff;
        for (let j = i + 1; j < d.length && d[j].type !== "header"; ++j)
            if (d[j].canStage) rows.push(j);
        return rows;
    }

    function statusIcon(st) {
        if (st === "conflicted") return "";
        return st === "added" ? "" : st === "deleted" ? ""
             : st === "renamed" ? "" : "";
    }
    function statusColor(st) {
        if (st === "conflicted") return Design.danger;
        return st === "added" ? Design.ok : st === "deleted" ? Design.danger
             : st === "renamed" ? Design.sapphire : Design.warn;
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
    // An author: their GitHub picture when there is one (AvatarCache,
    // avatar_cache.cpp), the initials in a coloured disc until then and
    // otherwise. Painted round on a Canvas — the software renderer this
    // window uses cannot clip an Image to a circle.
    component AuthorAvatar: Rectangle {
        id: av
        property string name: ""
        property string email: ""
        property color tone: Design.accent
        property int ring: 2
        readonly property string picture: (Avatars.revision, Avatars.url(av.email))
        width: Design.s(Design.size.mini); height: width; radius: width / 2
        color: av.tone
        border.color: "transparent"
        border.width: av.ring

        Text {
            anchors.centerIn: parent
            visible: !face.ready
            text: window.initials(av.name)
            font.family: Design.font.sans
            font.pixelSize: Math.max(8, Math.round(av.width * 0.45))
            font.weight: Design.weight.semibold
            color: Design.accentText
        }
        Canvas {
            id: face
            property bool ready: false
            anchors.fill: parent
            anchors.margins: av.ring
            visible: ready
            onWidthChanged: requestPaint()
            // imageLoaded comes only for a picture this Canvas had to read:
            // one Qt already holds (the same author higher up the history,
            // a row scrolled back into view) is loaded at once, silently, and
            // a disc that waited for the signal kept its initials for good.
            // So it is asked straight after, and on the signal as well.
            function show() {
                face.ready = av.picture !== "" && face.isImageLoaded(av.picture);
                if (face.ready) requestPaint();
            }
            function load() {
                face.ready = false;
                if (av.picture === "") return;
                face.loadImage(av.picture);
                face.show();
            }
            Component.onCompleted: face.load()
            Connections {
                target: av
                function onPictureChanged() { face.load(); }
            }
            onImageLoaded: face.show()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                if (!face.ready || av.picture === "") return;
                ctx.save();
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, Math.min(width, height) / 2, 0, 2 * Math.PI);
                ctx.closePath();
                ctx.clip();
                ctx.drawImage(av.picture, 0, 0, width, height);
                ctx.restore();
            }
        }
    }

    function initials(name) {
        const words = (name || "?").split(/[\s._-]+/).filter(w => w.length > 0);
        if (words.length === 0) return "?";
        return (words[0][0] + (words.length > 1 ? words[1][0] : "")).toUpperCase();
    }
    readonly property bool busy: GitBackend.busy !== ""

    // Amending: the commit box rewrites the last commit, its message loaded
    // into the fields, until it is done or cancelled.
    property bool amending: false
    function startAmend() {
        window.currentTab = 0;
        window.amending = true;
        sumInput.text = GitBackend.lastCommit.subject || "";
        descInput.text = GitBackend.lastCommit.body || "";
        sumInput.forceActiveFocus();
    }
    function cancelAmend() {
        window.amending = false;
        sumInput.text = "";
        descInput.text = "";
    }
    // "Name <email>" entries, comma separated, as Co-authored-by trailers —
    // how GitHub credits a commit to more than one person.
    property bool coAuthorsOpen: false
    readonly property var coAuthorList: coAuthorInput.text.split(",").map(t => t.trim())
        .filter(t => /^[^<>]+<[^<>@\s]+@[^<>\s]+>$/.test(t))
    function commitNow() {
        if (!window.hasRepo || window.busy || sumInput.text.trim() === "") return;
        let msg = sumInput.text.trim();
        let body = descInput.text.trim();
        if (window.coAuthorsOpen && window.coAuthorList.length > 0)
            body += (body ? "\n\n" : "") + window.coAuthorList.map(a => "Co-authored-by: " + a).join("\n");
        if (body) msg += "\n\n" + body;
        // The fields are cleared when the commit has gone in (onCommitted
        // below), not here: a commit that failed took the message with it.
        GitBackend.commit(msg, window.amending);
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
        color: Design.glassBg
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0


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
                        Layout.preferredWidth: Math.round(Math.max(Design.s(Design.width.sidebar), Math.min(Design.s(Design.width.dialog), window.width * 0.28)))
                        Layout.fillHeight: true
                        // The sidebar of every app (Ui/AppSidebar's look): a
                        // pane of its own, rounded and set in from the window's
                        // edges — the glass, or without blur a solid card one
                        // step up. It holds a list and a commit box that fill
                        // its height, so it is not an AppSidebar itself.
                        Layout.leftMargin: Design.s(Design.space.sm)
                        Layout.topMargin: Design.s(Design.space.sm)
                        Layout.bottomMargin: Design.s(Design.space.sm)
                        // Concentric with the window, as Ui/AppSidebar.
                        radius: Design.s(Design.concentric(Design.radius.window, Design.space.sm))
                        color: Design.translucent ? Design.glassSidebar : Design.raised
                        border.width: Design.border
                        border.color: Design.glassBorder
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Where you are: the repository and the branch, at the head
                            // of the sidebar as Files has its places — the toolbar holds
                            // only what acts on them.
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.margins: Design.s(Design.space.sm)
                                Layout.bottomMargin: Design.s(Design.space.xs)
                                spacing: Design.s(Design.space.xxs)

                                ToolbarCell {
                                    id: repoBtn
                                    flat: true
                                    icon: "\u{f024b}"   // the repository: a folder
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
                                    flat: true
                                    // The branch name is the one value here that can be
                                    // arbitrarily long, so this cell elides instead of
                                    // pushing the rest of the bar along.
                                    icon: "\u{f062c}"
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
                            }

                            // Top Sidebar Tab Switcher: [ Changes (N) ] [ History ]
Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(Design.size.art)
                                // One choice of view: a segmented control, as in
                                // Monitor and Files; it was two toggle buttons.
                                SegmentedControl {
                                    anchors.centerIn: parent
                                    size: "sm"
                                    model: [
                                        { id: "0", label: I18n.tr("Changes") + (GitBackend.changedFiles.length ? "  " + GitBackend.changedFiles.length : ""), icon: "\u{f0279}" },
                                        { id: "1", label: I18n.tr("History"), icon: "\u{f02da}" }
                                    ]
                                    current: String(window.currentTab)
                                    onPicked: id => {
                                        window.currentTab = Number(id);
                                        // Open on the newest commit rather than an
                                        // empty panel.
                                        if (window.currentTab === 1 && GitBackend.selectedCommit === "" && GitBackend.history.count > 0)
                                            GitBackend.selectCommit(GitBackend.history.hashAt(0));
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
                                        height: Design.s(Design.size.sm)
                                        color: "transparent"

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 1
                                            color: Design.glassBorder
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            onClicked: window.showMenu(changesMenu, "")
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(Design.space.sm)
                                            anchors.rightMargin: Design.s(Design.space.sm)
                                            spacing: Design.s(Design.space.sm)

                                            // Stage everything, or nothing; a dash when it's mixed.
                                            Rectangle {
                                                readonly property int staged: GitBackend.changedFiles.filter(f => f.isStaged).length
                                                readonly property int total: GitBackend.changedFiles.length
                                                visible: total > 0
                                                Layout.preferredWidth: Design.s(Design.size.micro)
                                                Layout.preferredHeight: Design.s(Design.size.micro)
                                                radius: Design.s(Design.radius.sm)
                                                color: staged > 0 ? Design.accent : "transparent"
                                                border.color: staged > 0 ? Design.accent : Design.textDim
                                                border.width: Design.border
                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: parent.staged > 0
                                                    text: parent.staged === parent.total ? "✓" : "–"
                                                    font.pixelSize: Design.s(Design.font.caption)
                                                    font.weight: Design.weight.semibold
                                                    color: Design.accentText
                                                }
                                                Clickable {
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
                                                font.weight: Design.weight.semibold
                                                color: Design.textDim
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            // Commands, so buttons in the text colour: green
                                            // and red are what a file's state is, not what
                                            // a click does.
                                            // One command, the one that applies: Stage All
                                            // while anything is unstaged, Unstage All once
                                            // everything is. Two side by side did not fit a
                                            // narrow pane ("Unstage A…").
                                            Button {
                                                readonly property bool allStaged: GitBackend.changedFiles.length > 0
                                                                                  && window.stagedCount === GitBackend.changedFiles.length
                                                variant: "ghost"; size: "sm"
                                                label: allStaged ? I18n.tr("Unstage All") : I18n.tr("Stage All")
                                                enabled: window.hasRepo && GitBackend.changedFiles.length > 0
                                                onClicked: allStaged ? GitBackend.unstageAll() : GitBackend.stageAll()
                                            }
                                        }
                                    }

                                    // A merge waiting to be finished or aborted.
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Design.s(Design.size.md)
                                        visible: GitBackend.mergeState.active === true
                                        readonly property int conflicts: GitBackend.mergeState.conflicts || 0
                                        color: conflicts > 0 ? Design.tint(Design.danger, 0.14)
                                             : GitBackend.mergeState.editing ? Design.tint(Design.accent, 0.14) : Design.tint(Design.ok, 0.14)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(Design.space.sm)
                                            anchors.rightMargin: Design.s(Design.space.sm)
                                            spacing: Design.s(Design.space.sm)
                                            Text {
                                                Layout.fillWidth: true
                                                readonly property string kind: GitBackend.mergeState.kind || "merge"
                                                readonly property string what: kind === "rebase" ? I18n.tr("Rebasing onto %1", GitBackend.mergeState.branch || "")
                                                    : kind === "cherry-pick" ? I18n.tr("Cherry-picking %1", GitBackend.mergeState.branch || "")
                                                    : kind === "revert" ? I18n.tr("Reverting %1", GitBackend.mergeState.branch || "")
                                                    : I18n.tr("Merging %1", GitBackend.mergeState.branch || "")
                                                text: GitBackend.mergeState.editing
                                                      ? I18n.tr("Editing %1 — change files, stage them, then Continue",
                                                                GitBackend.mergeState.editingSubject || GitBackend.mergeState.editing)
                                                      : what + " — " + (parent.parent.conflicts > 0
                                                             ? I18n.trn("%1 conflict", "%1 conflicts", parent.parent.conflicts)
                                                             : I18n.tr("ready"))
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.weight: Design.weight.semibold
                                                color: parent.parent.conflicts > 0 ? Design.danger : Design.ok
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: window.busy ? I18n.tr("Continuing…")
                                                    : (GitBackend.mergeState.kind || "merge") === "merge" ? I18n.tr("Commit merge") : I18n.tr("Continue")
                                                visible: parent.parent.conflicts === 0
                                                enabled: !window.busy
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.weight: Design.weight.semibold
                                                color: Design.ok
                                                Clickable { anchors.fill: parent; anchors.margins: -Design.s(Design.space.xs); cursorShape: Qt.PointingHandCursor; onClicked: GitBackend.commitMerge() }
                                            }
                                            Text {
                                                text: I18n.tr("Abort")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: Design.textDim
                                                Clickable { anchors.fill: parent; anchors.margins: -Design.s(Design.space.xs); cursorShape: Qt.PointingHandCursor; onClicked: GitBackend.abortMerge() }
                                            }
                                        }
                                    }

                                    // Git LFS: the repository keeps large files
                                    // there, and this machine cannot fetch them
                                    // yet — GitHub Desktop asks the same.
                                    Rectangle {
                                        readonly property var lfs: GitBackend.lfs
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: lfsText.implicitHeight + Design.s(Design.space.md)
                                        visible: lfs.used === true && (lfs.installed !== true || lfs.ready !== true)
                                        color: Design.tint(Design.warn, 0.12)
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(Design.space.sm)
                                            anchors.rightMargin: Design.s(Design.space.xs)
                                            spacing: Design.s(Design.space.sm)
                                            Label {
                                                id: lfsText
                                                Layout.fillWidth: true
                                                role: "caption"
                                                wrapMode: Text.Wrap
                                                text: parent.parent.lfs.installed !== true
                                                      ? I18n.tr("This repository keeps large files in Git LFS. Install git-lfs to get them.")
                                                      : I18n.tr("This repository keeps large files in Git LFS, not set up here yet.")
                                            }
                                            Button {
                                                visible: parent.parent.lfs.installed === true
                                                size: "sm"
                                                label: I18n.tr("Set up")
                                                enabled: !window.busy
                                                onClicked: GitBackend.setupLfs()
                                            }
                                        }
                                    }

                                    // Changes this app stashed when leaving
                                    // this branch, offered back on return.
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Design.s(Design.size.md)
                                        visible: GitBackend.branchStash.ref !== undefined
                                        color: Design.well

                                        property bool confirmDiscard: false

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(Design.space.sm)
                                            anchors.rightMargin: Design.s(Design.space.sm)
                                            spacing: Design.s(Design.space.sm)
                                            Text {
                                                Layout.fillWidth: true
                                                text: parent.parent.confirmDiscard ? I18n.tr("Delete the stash for good?")
                                                    : I18n.tr("Stashed changes (%1)", GitBackend.branchStash.files || 0)
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.weight: Design.weight.semibold
                                                color: parent.parent.confirmDiscard ? Design.danger : Design.text
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: parent.parent.confirmDiscard ? I18n.tr("Delete") : I18n.tr("Restore")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.weight: Design.weight.semibold
                                                color: parent.parent.confirmDiscard ? Design.danger : Design.text
                                                Clickable {
                                                    anchors.fill: parent
                                                    anchors.margins: -Design.s(Design.space.xs)
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
                                                color: Design.textDim
                                                Clickable {
                                                    anchors.fill: parent
                                                    anchors.margins: -Design.s(Design.space.xs)
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
                                        ScrollBar.vertical: OverflowBar {}
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        model: GitBackend.changedFiles
                                        spacing: 1

                                        EmptyState {
                                            parent: changedList
                                            anchors.centerIn: parent
                                            width: parent.width
                                            visible: window.hasRepo && changedList.count === 0
                                            icon: "\u{f012c}"
                                            title: I18n.tr("No changes")
                                            hint: I18n.tr("Your working tree is clean.")
                                        }

                                        delegate: Rectangle {
                                            id: fileCard
                                            // A rounded row set in from the pane's edges, as
                                            // Files' sidebar rows: a square band inside a
                                            // rounded pane was the one square thing in it.
                                            x: Design.s(Design.space.xs)
                                            width: changedList.width - Design.s(Design.space.xs) * 2
                                            radius: Design.s(Design.radius.ctl)
                                            height: Design.s(Design.size.md)
                                            color: isSelected ? Design.selection : (fArea.containsMouse ? Design.tint(Design.text, 0.05) : "transparent")

                                            readonly property bool isSelected: GitBackend.selectedFile === modelData.path

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Design.s(Design.space.sm)
                                                anchors.rightMargin: Design.s(Design.space.sm)
                                                spacing: Design.s(Design.space.sm)

                                                // Staged Checkbox
                                                Rectangle {
                                                    width: Design.s(Design.size.micro)
                                                    height: Design.s(Design.size.micro)
                                                    radius: Design.s(Design.radius.sm)
                                                    color: modelData.isStaged ? Design.accent : "transparent"
                                                    border.color: modelData.isStaged ? Design.accent : Design.textDim
                                                    border.width: Design.border

                                                    Text {
                                                        anchors.centerIn: parent
                                                        // Some lines staged, some not.
                                                        text: modelData.partial ? "–" : "✓"
                                                        font.pixelSize: Design.s(Design.font.caption)
                                                        font.weight: Design.weight.semibold
                                                        color: Design.accentText
                                                        visible: modelData.isStaged
                                                    }

                                                    Clickable {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData.isStaged && !modelData.partial) GitBackend.unstageFile(modelData.path);
                                                            else GitBackend.stageFile(modelData.path);
                                                        }
                                                    }
                                                }

                                                // File state icon
                                                Text {
                                                    text: window.statusIcon(modelData.status)
                                                    font.family: Design.font.mono
                                                    font.pixelSize: Design.s(Design.font.body)
                                                    color: window.statusColor(modelData.status)
                                                }

                                                // File Name
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.path
                                                    font.family: Design.font.mono
                                                    font.pixelSize: Design.s(Design.font.caption)
                                                    color: fileCard.isSelected ? Design.text : Design.text
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
                                        height: Design.s(Design.width.label) + (lastCommitBar.visible ? Design.s(Design.size.row) : 0)
                                                + (identityWarning.visible ? Design.s(Design.space.lg) : 0)
                                                + (amendBar.visible ? Design.s(Design.size.row) : 0)
                                                + (coAuthorInput.visible ? Design.s(Design.size.row) : 0)
                                        color: "transparent"

                                        Connections {
                                            target: GitBackend
                                            function onCommitted() {
                                                sumInput.text = "";
                                                descInput.text = "";
                                                coAuthorInput.text = "";
                                                window.coAuthorsOpen = false;
                                                window.amending = false;
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
                                            color: Design.glassBorder
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Design.s(Design.space.sm)
                                            spacing: Design.s(Design.space.xs)

                                            // The latest commit, while it can still be taken back.
                                            Rectangle {
                                                id: lastCommitBar
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Design.s(Design.size.md)
                                                visible: GitBackend.lastCommit.canUndo === true && !window.amending
                                                radius: Design.s(Design.radius.sm)
                                                color: Design.glassCard
                                                border.color: Design.glassBorder
                                                border.width: Design.border

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: Design.s(Design.space.sm)
                                                    anchors.rightMargin: Design.s(Design.space.xs)
                                                    spacing: Design.s(Design.space.sm)
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 0
                                                        Text {
                                                            text: I18n.tr("Committed %1", window.relTime(GitBackend.lastCommit.time))
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.caption)
                                                            color: Design.textDim
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: GitBackend.lastCommit.subject || ""
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.caption)
                                                            font.weight: Design.weight.semibold
                                                            color: Design.text
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                    Rectangle {
                                                        Layout.preferredWidth: undoText.implicitWidth + Design.s(Design.space.lg)
                                                        Layout.preferredHeight: Design.s(Design.size.mini)
                                                        radius: Design.s(Design.radius.sm)
                                                        opacity: window.busy ? Design.opacity.disabled : 1
                                                        color: undoArea.containsMouse ? Design.tint(Design.text, 0.12) : "transparent"
                                                        border.color: Design.glassBorder
                                                        border.width: Design.border
                                                        Text {
                                                            id: undoText
                                                            anchors.centerIn: parent
                                                            text: GitBackend.busy === "undo" ? I18n.tr("Undoing…") : I18n.tr("Undo")
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.caption)
                                                            font.weight: Design.weight.semibold
                                                            color: Design.text
                                                        }
                                                        Clickable {
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

                                            // Amending: what the button will do, and the way out.
                                            Rectangle {
                                                id: amendBar
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Design.s(Design.size.md)
                                                visible: window.amending
                                                radius: Design.s(Design.radius.sm)
                                                color: Design.tint(Design.accent, 0.12)
                                                border.color: Design.tint(Design.accent, 0.35)
                                                border.width: Design.border
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: Design.s(Design.space.sm)
                                                    anchors.rightMargin: Design.s(Design.space.xs)
                                                    spacing: Design.s(Design.space.sm)
                                                    Label {
                                                        Layout.fillWidth: true
                                                        role: "caption"
                                                        text: I18n.tr("Amending the last commit")
                                                        elide: Text.ElideRight
                                                    }
                                                    Button {
                                                        variant: "ghost"; size: "sm"
                                                        label: I18n.tr("Cancel")
                                                        onClicked: window.cancelAmend()
                                                    }
                                                }
                                            }

                                            Text {
                                                id: identityWarning
                                                Layout.fillWidth: true
                                                visible: window.hasRepo && (!GitBackend.identity.name || !GitBackend.identity.email)
                                                text: I18n.tr("Set your name and email for commits…")
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.underline: true
                                                color: Design.warn
                                                elide: Text.ElideRight
                                                Clickable {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: settingsDialog.show()
                                                }
                                            }

                                            // Summary (Required)
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: Design.s(Design.size.knob)
                                                radius: Design.s(Design.radius.ctl)
                                                color: Design.raised
                                                opacity: window.hasRepo ? 1.0 : 0.5
                                                border.color: sumInput.activeFocus ? Design.accent : Design.line
                                                border.width: Design.border

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
                                                    color: Design.text
                                                    selectByMouse: true
                                                    clip: true
                                                    Keys.onPressed: (e) => {
                                                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) {
                                                            window.commitNow();
                                                            e.accepted = true;
                                                        }
                                                    }

                                                    // How long the summary is, from 50
                                                    // characters on: git's convention,
                                                    // and GitHub cuts it at 72.
                                                    Text {
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: sumInput.text.length > 50
                                                        text: String(72 - sumInput.text.length)
                                                        font.family: Design.font.mono
                                                        font.pixelSize: Design.s(Design.font.caption)
                                                        color: sumInput.text.length > 72 ? Design.danger : Design.warn
                                                    }

                                                    Text {
                                                        text: I18n.tr("Summary (required)")
                                                        font.family: Design.font.sans
                                                        font.pixelSize: Design.s(Design.font.body)
                                                        color: Design.textDim
                                                        visible: !sumInput.text && !sumInput.activeFocus
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }

                                            // Description (Optional)
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                Layout.minimumHeight: Design.s(Design.size.tile)
                                                radius: Design.s(Design.radius.ctl)
                                                color: Design.raised
                                                opacity: window.hasRepo ? 1.0 : 0.5
                                                border.color: descInput.activeFocus ? Design.accent : Design.line
                                                border.width: Design.border

                                                // In a ScrollView: a bare TextArea grows past its
                                                // box and cannot be scrolled, so a long
                                                // description ran out of sight below the field.
                                                ScrollView {
                                                    id: descScroll
                                                    anchors.fill: parent
                                                    clip: true
                                                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                                    ScrollBar.vertical: OverflowBar { view: descScroll }
                                                    TextArea {
                                                        id: descInput
                                                        enabled: window.hasRepo
                                                        leftPadding: Design.s(Design.space.md)
                                                        rightPadding: Design.s(Design.space.md)
                                                        topPadding: Design.s(Design.space.sm)
                                                        bottomPadding: Design.s(Design.space.sm)
                                                        font.family: Design.font.sans
                                                        font.pixelSize: Design.s(Design.font.body)
                                                        color: Design.text
                                                        selectByMouse: true
                                                        background: null
                                                        wrapMode: TextEdit.Wrap

                                                        Text {
                                                            x: descInput.leftPadding
                                                            y: descInput.topPadding
                                                            text: I18n.tr("Description")
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.body)
                                                            color: Design.textDim
                                                            visible: !descInput.text && !descInput.activeFocus
                                                        }
                                                    }
                                                }
                                                Button {
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: Design.s(Design.space.xxs)
                                                    variant: "ghost"; size: "sm"; iconOnly: true
                                                    checked: window.coAuthorsOpen
                                                    icon: "\u{f0849}"
                                                    tip: window.coAuthorsOpen ? I18n.tr("Remove co-authors") : I18n.tr("Add co-authors")
                                                    enabled: window.hasRepo
                                                    onClicked: {
                                                        window.coAuthorsOpen = !window.coAuthorsOpen;
                                                        if (window.coAuthorsOpen) coAuthorInput.focusInput();
                                                    }
                                                }
                                            }

                                            // Co-authors, behind the toggle at the
                                            // description's corner.
                                            Field {
                                                id: coAuthorInput
                                                Layout.fillWidth: true
                                                visible: window.coAuthorsOpen
                                                mono: true
                                                placeholder: I18n.tr("Name <email>, Name <email>")
                                            }

                                            // Commit Action Button
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: Design.s(Design.size.knob)
                                                radius: height / 2
                                                readonly property bool committing: GitBackend.busy === "commit"
                                                readonly property bool ready: window.hasRepo && sumInput.text.trim().length > 0 && !window.busy
                                                    && (window.amending || GitBackend.changedFiles.length > 0)
                                                color: ready ? (commitArea.containsMouse ? Qt.lighter(Design.accent, 1.1) : Design.accent) : Design.raised
                                                enabled: ready

                                                Row {
                                                    id: commitSpin
                                                    anchors.centerIn: parent
                                                    spacing: Design.s(Design.space.xs)
                                                    visible: parent.committing
                                                    Text {
                                                        text: "󰝲"
                                                        font.family: Design.font.icon
                                                        font.pixelSize: Design.s(Design.font.footnote)
                                                        color: Design.text
                                                        RotationAnimator on rotation { running: commitSpin.visible; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                                                    }
                                                    Text {
                                                        text: I18n.tr("Committing…")
                                                        font.family: Design.font.sans
                                                        font.pixelSize: Design.s(Design.font.caption)
                                                        font.weight: Design.weight.semibold
                                                        color: Design.text
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
                                                          : window.amending ? I18n.tr("Amend last commit")
                                                          : window.stagedCount === 0 && GitBackend.changedFiles.length > 0
                                                            ? I18n.tr("Commit all to %1", GitBackend.branchName)
                                                            : I18n.tr("Commit to %1", GitBackend.branchName)
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(Design.font.body)
                                                    font.weight: Design.weight.semibold
                                                    color: parent.ready ? Design.accentText : Design.textDim
                                                }

                                                Clickable {
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
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: window.currentTab === 1
                                spacing: 0

                                // Search, and a branch to compare with — the
                                // commits it has that this one lacks, or the
                                // other way round, as GitHub Desktop's compare.
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.margins: Design.s(Design.space.sm)
                                    Layout.topMargin: 0
                                    spacing: Design.s(Design.space.xs)

                                    Field {
                                        id: historySearch
                                        Layout.fillWidth: true
                                        placeholder: I18n.tr("Filter by message, author or SHA")
                                        onTextChanged: historySearchDelay.restart()
                                        Timer {
                                            id: historySearchDelay
                                            interval: 250
                                            onTriggered: GitBackend.historyFilter = historySearch.text
                                        }
                                        Connections {
                                            target: GitBackend
                                            function onRepoChanged() { historySearch.text = ""; }
                                        }
                                    }
                                    Select {
                                        Layout.fillWidth: true
                                        placeholder: I18n.tr("Compare with a branch…")
                                        // Local branches, their remote copies, and branches
                                        // only on a remote: origin/main is the usual one to
                                        // compare with.
                                        model: {
                                            const names = GitBackend.branches.filter(b => b !== GitBackend.branchName);
                                            for (const b of GitBackend.branches) {
                                                const up = (GitBackend.branchInfo[b] || {}).upstream || "";
                                                if (up !== "" && names.indexOf(up) < 0) names.push(up);
                                            }
                                            for (const r of GitBackend.remoteBranches) if (names.indexOf(r) < 0) names.push(r);
                                            return [{ id: "", label: I18n.tr("No comparison") }].concat(names.map(b => ({ id: b, label: b })));
                                        }
                                        current: GitBackend.compareBranch
                                        onPicked: id => GitBackend.setCompare(id, GitBackend.compareMode)
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: GitBackend.compareBranch !== ""
                                        spacing: Design.s(Design.space.xs)
                                        SegmentedControl {
                                            Layout.fillWidth: true
                                            size: "sm"
                                            model: [
                                                { id: "behind", label: I18n.tr("Behind %1", GitBackend.compareBehind) },
                                                { id: "ahead", label: I18n.tr("Ahead %1", GitBackend.compareAhead) }
                                            ]
                                            current: GitBackend.compareMode
                                            onPicked: id => GitBackend.setCompare(GitBackend.compareBranch, id)
                                        }
                                    }
                                    Button {
                                        Layout.fillWidth: true
                                        visible: GitBackend.compareBranch !== "" && GitBackend.compareMode === "behind" && GitBackend.compareBehind > 0
                                        size: "sm"; variant: "primary"
                                        enabled: !window.busy && !GitBackend.mergeState.active
                                        label: I18n.trn("Merge %1 commit into %2", "Merge %1 commits into %2", GitBackend.compareBehind, GitBackend.branchName)
                                        onClicked: {
                                            const b = GitBackend.compareBranch;
                                            GitBackend.setCompare("", "behind");
                                            GitBackend.mergeBranch(b);
                                        }
                                    }
                                }

                                ListView {
                                    id: historyList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: GitBackend.history
                                    spacing: 1
                                    ScrollBar.vertical: OverflowBar {}

                                    EmptyState {
                                        parent: historyList
                                        anchors.centerIn: parent
                                        width: parent.width
                                        visible: window.hasRepo && GitBackend.history.count === 0
                                        icon: "\u{f02da}"
                                        title: GitBackend.historyFilter !== "" ? I18n.tr("No commits match")
                                             : GitBackend.compareBranch !== "" ? I18n.tr("Nothing to show")
                                             : I18n.tr("No commits yet")
                                        hint: GitBackend.historyFilter !== "" || GitBackend.compareBranch !== "" ? ""
                                            : I18n.tr("Make your first commit in Changes.")
                                    }

                                    // The rows were hover-only: nothing
                                    // happened on click, so a commit's files
                                    // and changes could not be seen at all.
                                    delegate: Rectangle {
                                        x: Design.s(Design.space.xs)
                                        width: historyList.width - Design.s(Design.space.xs) * 2
                                        radius: Design.s(Design.radius.ctl)
                                        height: Design.s(Design.size.rowTall)
                                        readonly property bool isSelected: GitBackend.selectedCommit === model.fullHash
                                        readonly property string subject: model.message || ""
                                        color: isSelected ? Design.selection
                                                          : (hArea.containsMouse ? Design.tint(Design.text, 0.05) : "transparent")

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Design.s(Design.space.sm)
                                            spacing: Design.s(Design.space.xxs)

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: model.message || I18n.tr("Commit")
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(Design.font.caption)
                                                    font.weight: Design.weight.semibold
                                                    color: Design.text
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
                                                    font.pixelSize: Design.s(Design.font.body)
                                                    color: model.sync === "local" ? Design.warn : Design.textDim
                                                    opacity: model.sync === "local" ? 1.0 : 0.6
                                                }
                                                Rectangle {
                                                    width: Design.s(Design.size.rowTall); height: Design.s(Design.size.micro); radius: Design.s(Design.radius.sm)
                                                    color: "transparent"
                                                    Text { anchors.centerIn: parent; text: model.hash || ""; font.family: Design.font.mono; font.pixelSize: Design.s(Design.font.caption); color: Design.textDim }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Design.s(Design.space.xs)
                                                // Tags on the commit, as labels.
                                                Repeater {
                                                    model: tags || []
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        Layout.preferredHeight: Design.s(Design.size.micro)
                                                        Layout.preferredWidth: tagText.implicitWidth + Design.s(Design.space.sm)
                                                        Layout.maximumWidth: Design.s(Design.size.thumb)
                                                        radius: Design.s(Design.radius.sm)
                                                        color: Design.tint(Design.yellow, 0.18)
                                                        border.color: Design.tint(Design.yellow, 0.45)
                                                        border.width: Design.border
                                                        Text {
                                                            id: tagText
                                                            anchors.centerIn: parent
                                                            width: Math.min(implicitWidth, parent.width - Design.s(Design.space.xs))
                                                            text: "\u{f04f9} " + modelData
                                                            font.family: Design.font.sans
                                                            font.pixelSize: Design.s(Design.font.caption)
                                                            color: Design.yellow
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }
                                                AuthorAvatar {
                                                    Layout.preferredWidth: Design.s(Design.size.micro)
                                                    Layout.preferredHeight: Design.s(Design.size.micro)
                                                    width: Design.s(Design.size.micro)
                                                    ring: 1
                                                    name: model.author || ""
                                                    email: model.email || ""
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: window.people(model.author || I18n.tr("User"), model.coAuthors) + " • " + window.relTime(model.time)
                                                          + (model.sync === "local" ? " • not pushed" : "")
                                                    font.family: Design.font.sans
                                                    font.pixelSize: Design.s(Design.font.caption)
                                                    color: Design.textDim
                                                }
                                            }
                                        }

                                        // Held and dragged onto another commit: moved
                                        // there or squashed into it (dropMenu), as
                                        // GitHub Desktop's history lets one drag.
                                        // Commits on no remote only.
                                        readonly property bool draggable: model.sync !== "pushed" && GitBackend.compareBranch === ""
                                        opacity: window.dragHash === model.fullHash ? 0.45 : 1
                                        border.width: window.dragHash !== "" && window.dragOver === model.index
                                                      && window.dragHash !== model.fullHash ? Design.s(Design.focusWidth) : 0
                                        border.color: Design.accent

                                        MouseArea {
                                            id: hArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: window.dragHash !== "" ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            pressAndHoldInterval: 350
                                            preventStealing: window.dragHash !== ""
                                            onPressAndHold: mouse => {
                                                if (mouse.button !== Qt.LeftButton || !parent.draggable || window.busy) return;
                                                window.dragHash = model.fullHash;
                                                window.dragOver = model.index;
                                            }
                                            onPositionChanged: mouse => {
                                                if (window.dragHash === "") return;
                                                const p = mapToItem(historyList.contentItem, mouse.x, mouse.y);
                                                window.dragOver = historyList.indexAt(p.x, p.y);
                                            }
                                            onReleased: {
                                                if (window.dragHash === "") return;
                                                const hash = window.dragHash, over = window.dragOver;
                                                window.dragHash = "";
                                                window.dragOver = -1;
                                                const target = GitBackend.history.hashAt(over);
                                                if (target === "" || target === hash) return;
                                                dropMenu.hash = hash;
                                                dropMenu.index = over;
                                                dropMenu.subject = historyList.itemAtIndex(over) ? historyList.itemAtIndex(over).subject : target.slice(0, 7);
                                                window.showMenu(dropMenu, target);
                                            }
                                            onClicked: (mouse) => {
                                                GitBackend.selectCommit(model.fullHash);
                                                if (mouse.button === Qt.RightButton) {
                                                    commitMenu.subject = model.message;
                                                    commitMenu.pushed = model.sync === "pushed";
                                                    commitMenu.tags = model.tags || [];
                                                    // Compared with another branch, only this branch's
                                                    // own commits (ahead) are its to rewrite.
                                                    commitMenu.local = model.sync !== "pushed"
                                                        && (GitBackend.compareBranch === "" || GitBackend.compareMode === "ahead");
                                                    commitMenu.isHead = model.index === 0 && GitBackend.compareBranch === "";
                                                    commitMenu.olderLocal = model.index + 1 < GitBackend.history.count
                                                        && GitBackend.history.syncAt(model.index + 1) !== "pushed"
                                                        && GitBackend.compareBranch === "";
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

                    // ── RIGHT: the toolbar, the diff, the status bar ─────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0

                        // The toolbar over the diff, as every app has it over its
                        // content: the one thing to do with the remote (publish,
                        // pull, push or fetch), and the accounts at its right.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(Design.size.rowTall)
                            color: "transparent"
                            z: 20

                            // AppToolbar's hairline: the bar is AppToolbar's size and look,
                            // but it also carries the progress line along its bottom edge.
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: Design.border
                                color: Design.separator
                            }

                            // Progress of the running operation: fills when git reports a
                            // percentage, slides back and forth when it doesn't.
                            Item {
                                id: progressLine
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: Design.s(Design.focusWidth)
                                visible: window.busy
                                clip: true
                                z: 2

                                Rectangle {
                                    visible: GitBackend.progress >= 0
                                    height: parent.height
                                    width: parent.width * Math.max(0, GitBackend.progress) / 100
                                    color: Design.accent
                                    Behavior on width { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutCubic } }
                                }
                                Rectangle {
                                    id: slider
                                    visible: GitBackend.progress < 0
                                    height: parent.height
                                    width: parent.width * 0.25
                                    radius: 1
                                    color: Design.accent
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
                                    id: syncBtn
                                    enabled: window.syncAction !== "none" && !window.busy
                                    spinning: window.syncBusy || GitBackend.fetching
                                    icon: window.syncAction === "publish" || window.syncAction === "publishRepo" ? "󰅧"
                                        : window.syncAction === "pull" ? "󰁅"
                                        : window.syncAction === "push" ? "󰁝" : "󰑐"
                                    title: window.syncAction === "publishRepo" ? I18n.tr("Publish repository")
                                         : window.syncAction === "publish" ? I18n.tr("Publish branch")
                                         : window.syncAction === "pull" ? I18n.tr("Pull %1", GitBackend.remoteName)
                                         : window.syncAction === "push" ? I18n.tr("Push %1", GitBackend.remoteName)
                                         : window.syncAction === "fetch" ? I18n.tr("Fetch %1", GitBackend.remoteName)
                                         : I18n.tr("Fetch origin")
                                    caption: window.syncBusy ? GitBackend.busyText
                                           : !window.hasRepo ? I18n.tr("No repository")
                                           : !GitBackend.hasRemote ? I18n.tr("Put this repository on GitHub")
                                           : GitBackend.fetching ? I18n.tr("Fetching…")
                                           : GitBackend.upstreamGone ? I18n.tr("Deleted on %1 — publish again?", GitBackend.remoteName)
                                           : window.syncAction === "publish" ? I18n.tr("Publish this branch to %1", GitBackend.remoteName)
                                           : window.lastFetchText
                                    // Counts beside the title, as the original draws them:
                                    // what is waiting in each direction.
                                    badge: (GitBackend.behindCount > 0 ? GitBackend.behindCount + "↓" : "")
                                         + (GitBackend.behindCount > 0 && GitBackend.aheadCount > 0 ? " " : "")
                                         + (GitBackend.aheadCount > 0 && window.syncAction !== "publish" ? GitBackend.aheadCount + "↑" : "")
                                    onRightClicked: if (window.hasRepo) window.showMenu(syncMenu, "")
                                    onClicked: {
                                        if (window.syncAction === "publishRepo") publishDialog.show();
                                        else if (window.syncAction === "pull") GitBackend.pull();
                                        else if (window.syncAction === "push" || window.syncAction === "publish") GitBackend.push();
                                        else GitBackend.fetch();
                                    }
                                }

                                // The branch's pull request and how its checks
                                // went, GitHub Desktop's badge on the branch.
                                ToolbarCell {
                                    readonly property var pr: GitBackend.currentPullRequest
                                    visible: pr.number !== undefined && pr.number > 0
                                    compact: true
                                    icon: pr.checks === "success" ? "\u{f012c}" : pr.checks === "failure" ? "\u{f0156}"
                                        : pr.checks === "pending" ? "\u{f0996}" : "\u{f041b}"
                                    title: "#" + (pr.number || "")
                                    caption: (pr.title || "") + (pr.checks === "success" ? " — " + I18n.tr("checks passed")
                                             : pr.checks === "failure" ? " — " + I18n.tr("checks failed")
                                             : pr.checks === "pending" ? " — " + I18n.tr("checks running") : "")
                                    onClicked: Qt.openUrlExternally(pr.url)
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

                        // ── File Diff Viewer
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "transparent"
                            clip: true

                            // One diff row, shared by the working-tree diff and a
                            // commit's: two copies of this delegate would drift.
                            Component {
                                id: diffRowDelegate

                                Rectangle {
                                    width: ListView.view ? ListView.view.width : 0
                                    height: Math.max(20, diffLineText.implicitHeight + 4)

                                    // A soft wash and a mark at the edge say added or
                                    // removed; the code itself stays in the text
                                    // colour, which green on green was not.
                                    color: {
                                        if (modelData.type === "add") return Design.tint(Design.ok, 0.10);
                                        if (modelData.type === "del") return Design.tint(Design.danger, 0.11);
                                        if (modelData.type === "header") return Design.tint(Design.accent, 0.08);
                                        return "transparent";
                                    }
                                    Rectangle {
                                        visible: modelData.type === "add" || modelData.type === "del"
                                        width: Design.s(Design.focusWidth)
                                        height: parent.height
                                        color: modelData.type === "add" ? Design.ok : Design.danger
                                    }

                                    // Lines of the working tree's diff are
                                    // staged one by one by their numbers, as in
                                    // GitHub Desktop: the numbers of a staged
                                    // line are filled in the accent colour, and
                                    // a click there (or on a hunk's header, for
                                    // the hunk) takes it in or out.
                                    readonly property bool stageable: ListView.view === diffList && modelData.canStage === true
                                    readonly property bool hunkStageable: ListView.view === diffList && modelData.type === "header"
                                                                          && window.hunkRows(index).length > 0
                                    Rectangle {
                                        visible: parent.stageable
                                        x: Design.s(Design.focusWidth)
                                        width: Design.s(Design.size.row) * 2 - Design.s(Design.focusWidth)
                                        height: parent.height
                                        color: modelData.staged ? Design.tint(Design.accent, gutterArea.containsMouse ? 0.55 : 0.4)
                                             : gutterArea.containsMouse ? Design.tint(Design.accent, 0.15) : "transparent"
                                    }
                                    MouseArea {
                                        id: gutterArea
                                        enabled: parent.stageable || parent.hunkStageable
                                        width: parent.hunkStageable ? parent.width : Design.s(Design.size.row) * 2
                                        height: parent.height
                                        hoverEnabled: true
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.RightButton) {
                                                lineMenu.rows = parent.hunkStageable ? window.hunkRows(index) : [index];
                                                window.showMenu(lineMenu, "");
                                                return;
                                            }
                                            if (parent.hunkStageable) {
                                                const rows = window.hunkRows(index);
                                                const all = rows.every(i => GitBackend.currentDiff[i].staged);
                                                GitBackend.setLinesStaged(rows, !all);
                                            } else {
                                                GitBackend.setLinesStaged([index], !modelData.staged);
                                            }
                                        }
                                    }
                                    // The words that changed, a shade deeper.
                                    // Where tabs are drawn as Text's own tab
                                    // stops (no colouring) the columns would
                                    // not line up, so there it is left out.
                                    Rectangle {
                                        readonly property var chg: modelData.chg
                                        visible: !!chg && (!!modelData.html || (modelData.text || "").indexOf("\t") < 0)
                                        x: Design.s(Design.size.row) * 2 + (chg ? window.colX(modelData.text, chg[0] + 1) : 0)
                                        width: chg ? window.colX(modelData.text, chg[1] + 1) - window.colX(modelData.text, chg[0] + 1) : 0
                                        height: parent.height
                                        color: modelData.type === "add" ? Design.tint(Design.ok, 0.28) : Design.tint(Design.danger, 0.30)
                                    }
                                    ToolTip.visible: gutterArea.containsMouse
                                    ToolTip.delay: 700
                                    ToolTip.text: hunkStageable ? I18n.tr("Stage or unstage this hunk")
                                                : modelData.staged ? I18n.tr("Staged — click to unstage this line")
                                                : I18n.tr("Click to stage this line")

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0

                                        // Old Line Num
                                        // Layout.preferredWidth, not width: a
                                        // RowLayout ignores width, so both number
                                        // columns shrank to their text and the
                                        // new-line number sat on top of the old.
                                        Text {
                                            Layout.preferredWidth: Design.s(Design.size.row)
                                            text: modelData.oldLine || ""
                                            horizontalAlignment: Text.AlignRight
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: Design.textDim
                                            rightPadding: 8
                                        }

                                        // New Line Num
                                        Text {
                                            Layout.preferredWidth: Design.s(Design.size.row)
                                            text: modelData.newLine || ""
                                            horizontalAlignment: Text.AlignRight
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: Design.textDim
                                            rightPadding: 8
                                        }

                                        // Line Content
                                        Text {
                                            id: diffLineText
                                            Layout.fillWidth: true
                                            // Coloured code where the language is
                                            // known: the line as StyledText after
                                            // its + or -.
                                            textFormat: modelData.html ? Text.StyledText : Text.PlainText
                                            text: modelData.html
                                                  ? (modelData.type === "add" ? "+" : modelData.type === "del" ? "-" : "&nbsp;") + modelData.html
                                                  : (modelData.text || "")
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: modelData.type === "header" ? Design.accent : Design.text
                                        }
                                    }
                                }
                            }

                            // One row of the side-by-side diff: a hunk's
                            // header across both halves, or a pair of lines.
                            Component {
                                id: splitRowDelegate

                                Rectangle {
                                    id: sRow
                                    readonly property bool working: ListView.view === diffList
                                    readonly property bool header: modelData.kind === "header"
                                    readonly property bool hunkStageable: working && header && window.hunkRows(modelData.i).length > 0
                                    width: ListView.view ? ListView.view.width : 0
                                    height: Math.max(20, (header ? headText.implicitHeight : Math.max(leftHalf.textHeight, rightHalf.textHeight)) + 4)
                                    color: header ? Design.tint(Design.accent, hunkArea.containsMouse ? 0.16 : 0.08) : "transparent"

                                    Text {
                                        id: headText
                                        visible: sRow.header
                                        x: Design.s(Design.size.row) * 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: sRow.header ? modelData.text : ""
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: Design.accent
                                    }
                                    MouseArea {
                                        id: hunkArea
                                        anchors.fill: parent
                                        enabled: sRow.hunkStageable
                                        hoverEnabled: true
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: mouse => {
                                            const rows = window.hunkRows(modelData.i);
                                            if (mouse.button === Qt.RightButton) {
                                                lineMenu.rows = rows;
                                                window.showMenu(lineMenu, "");
                                                return;
                                            }
                                            GitBackend.setLinesStaged(rows, !rows.every(i => GitBackend.currentDiff[i].staged));
                                        }
                                    }

                                    Row {
                                        visible: !sRow.header
                                        anchors.fill: parent
                                        SplitHalf { id: leftHalf; width: parent.width / 2; height: parent.height; side: sRow.header ? null : modelData.l; working: sRow.working }
                                        Rectangle { width: 1; height: parent.height; color: Design.glassBorder }
                                        SplitHalf { id: rightHalf; width: parent.width / 2 - 1; height: parent.height; side: sRow.header ? null : modelData.r; working: sRow.working }
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
                                    height: Design.s(Design.size.knob)
                                    visible: GitBackend.selectedFile !== ""
                                    color: "transparent"

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 1
                                        color: Design.glassBorder
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Design.s(Design.space.md)
                                        anchors.rightMargin: Design.s(Design.space.md)
                                        spacing: Design.s(Design.space.sm)

                                        Text {
                                            text: "󰈙"
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.body)
                                            color: Design.textDim
                                        }

                                        Text {
                                            text: GitBackend.selectedFile
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.body)
                                            font.weight: Design.weight.semibold
                                            color: Design.text
                                            Layout.fillWidth: true
                                            elide: Text.ElideMiddle
                                        }

                                        Text {
                                            text: GitBackend.statusSummary
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: Design.textDim
                                        }

                                        Button {
                                            variant: "ghost"; size: "sm"; iconOnly: true
                                            icon: "\u{f0bdd}"
                                            checked: GitBackend.ignoreWhitespace
                                            tip: GitBackend.ignoreWhitespace ? I18n.tr("Show whitespace changes")
                                                                             : I18n.tr("Hide whitespace changes (lines can't be staged one by one then)")
                                            onClicked: GitBackend.ignoreWhitespace = !GitBackend.ignoreWhitespace
                                        }
                                        Button {
                                            variant: "ghost"; size: "sm"; iconOnly: true
                                            icon: "\u{f0219}"
                                            checked: GitBackend.fullFile
                                            tip: GitBackend.fullFile ? I18n.tr("Show only the changes") : I18n.tr("Show the whole file")
                                            onClicked: GitBackend.fullFile = !GitBackend.fullFile
                                        }
                                        Button {
                                            variant: "ghost"; size: "sm"; iconOnly: true
                                            icon: "\u{f0db}"
                                            checked: window.splitDiff
                                            tip: window.splitDiff ? I18n.tr("Unified view") : I18n.tr("Side by side")
                                            onClicked: window.splitDiff = !window.splitDiff
                                        }
                                    }
                                }

                                ImageCompare {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    visible: window.isImage(GitBackend.selectedFile)
                                    pair: (GitBackend.currentDiff, visible ? GitBackend.imagePair(GitBackend.selectedFile, "") : ({}))
                                }

                                // Diff Lines ListView
                                ListView {
                                    id: diffList
                                    ScrollBar.vertical: OverflowBar {}
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    visible: !window.isImage(GitBackend.selectedFile)
                                    model: window.splitDiff ? window.splitRows(GitBackend.currentDiff) : GitBackend.currentDiff
                                    delegate: window.splitDiff ? splitRowDelegate : diffRowDelegate

                                    // Empty State when clean
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: Design.s(Design.space.md)
                                        visible: GitBackend.currentDiff.length === 0

                                        EmptyState {
                                            icon: "󰊢"
                                            title: GitBackend.isRepo ? I18n.tr("No changes to display") : I18n.tr("No Git Repository Open")
                                            hint: GitBackend.isRepo ? I18n.tr("Working directory is clean") : I18n.tr("Select a repository from the top menu or open a folder.")
                                        }

                                        // What to do next, as GitHub Desktop suggests it.
                                        ColumnLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.topMargin: Design.s(Design.space.sm)
                                            Layout.preferredWidth: Math.min(Design.s(Design.width.menuMax), diffList.width - Design.s(Design.size.row))
                                            spacing: Design.s(Design.space.sm)
                                            visible: GitBackend.isRepo && GitBackend.changedFiles.length === 0

                                            Repeater {
                                                model: {
                                                    const items = [];
                                                    const remote = GitBackend.remoteName || "origin";
                                                    if (window.syncAction === "publishRepo")
                                                        items.push({ title: I18n.tr("Publish your repository"), text: I18n.tr("It has no remote yet. Put it on GitHub."), button: I18n.tr("Publish repository"), run: "publishRepo" });
                                                    else if (window.syncAction === "publish")
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
                                                    Layout.preferredHeight: Design.s(Design.size.rowTall)
                                                    radius: Design.s(Design.radius.ctl)
                                                    color: Design.glassCard
                                                    border.color: Design.glassBorder
                                                    border.width: Design.border
                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: Design.s(Design.space.md)
                                                        anchors.rightMargin: Design.s(Design.space.sm)
                                                        spacing: Design.s(Design.space.sm)
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: Design.s(Design.space.xxs)
                                                            Text {
                                                                text: modelData.title
                                                                font.family: Design.font.sans
                                                                font.pixelSize: Design.s(Design.font.body)
                                                                font.weight: Design.weight.semibold
                                                                color: Design.text
                                                            }
                                                            Text {
                                                                Layout.fillWidth: true
                                                                text: modelData.text
                                                                font.family: Design.font.sans
                                                                font.pixelSize: Design.s(Design.font.caption)
                                                                color: Design.textDim
                                                                elide: Text.ElideMiddle
                                                            }
                                                        }
                                                        Rectangle {
                                                            readonly property bool primary: index === 0 && ["push", "pull", "publishRepo"].indexOf(modelData.run) >= 0
                                                            Layout.preferredWidth: sugText.implicitWidth + Design.s(Design.space.lg)
                                                            Layout.preferredHeight: Design.s(Design.size.xs)
                                                            radius: Design.s(Design.radius.sm)
                                                            opacity: window.busy ? Design.opacity.disabled : 1
                                                            color: primary ? (sugArea.containsMouse ? Qt.lighter(Design.accent, 1.1) : Design.accent)
                                                                           : (sugArea.containsMouse ? Design.tint(Design.text, 0.12) : "transparent")
                                                            border.color: primary ? "transparent" : Design.glassBorder
                                                            border.width: Design.border
                                                            Text {
                                                                id: sugText
                                                                anchors.centerIn: parent
                                                                text: modelData.button
                                                                font.family: Design.font.sans
                                                                font.pixelSize: Design.s(Design.font.caption)
                                                                font.weight: Design.weight.semibold
                                                                color: parent.primary ? Design.accentText : Design.text
                                                            }
                                                            Clickable {
                                                                id: sugArea
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                enabled: !window.busy
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    const r = modelData.run;
                                                                    if (r === "publishRepo") publishDialog.show();
                                                                    else if (r === "push") GitBackend.push();
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
                                    Layout.preferredHeight: commitHead.implicitHeight + Design.s(Design.space.lg)
                                    visible: GitBackend.selectedCommit !== ""
                                    color: "transparent"

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 1
                                        color: Design.glassBorder
                                    }

                                    ColumnLayout {
                                        id: commitHead
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: Design.s(Design.space.md)
                                        anchors.rightMargin: Design.s(Design.space.md)
                                        spacing: Design.s(Design.space.xs)

                                        // Wrapped, not cut: the header grows
                                        // with it (implicitHeight above), and a
                                        // long subject or a list of authors was
                                        // a line ending in "…" with no way to
                                        // read the rest.
                                        Text {
                                            Layout.fillWidth: true
                                            text: GitBackend.commitInfo.subject || ""
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.body)
                                            font.weight: Design.weight.semibold
                                            color: Design.text
                                            wrapMode: Text.Wrap
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Design.s(Design.space.sm)

                                            // One initial-disc per person, the
                                            // author first, overlapping as the
                                            // original stacks its avatars. The
                                            // full list is in the tooltip.
                                            Row {
                                                id: peopleRow
                                                spacing: -Design.s(Design.space.xs)
                                                readonly property var names: [GitBackend.commitInfo.author || ""]
                                                    .concat((GitBackend.commitInfo.coAuthors || [])
                                                            .filter(n => n !== GitBackend.commitInfo.author))
                                                Repeater {
                                                    model: peopleRow.names
                                                    delegate: AuthorAvatar {
                                                        required property string modelData
                                                        required property int index
                                                        z: peopleRow.names.length - index
                                                        name: modelData
                                                        email: index === 0 ? (GitBackend.commitInfo.email || "")
                                                             : ((GitBackend.commitInfo.coAuthorEmails || {})[modelData] || "")
                                                        tone: [Design.accent, Design.mauve, Design.ok, Design.warn, Design.sapphire][index % 5]
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
                                                color: Design.textDim
                                                wrapMode: Text.Wrap
                                            }
                                        }

                                        // Four lines, and all of it on request —
                                        // scrolling in its own box past a third
                                        // of the window, so the diff stays.
                                        ScrollView {
                                            id: commitBodyBox
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Math.min(commitBody.implicitHeight, window.height / 3)
                                            visible: commitBody.text !== ""
                                            clip: true
                                            contentWidth: availableWidth
                                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                            ScrollBar.vertical: OverflowBar { view: commitBodyBox }
                                            Text {
                                                id: commitBody
                                                property bool open: false
                                                width: commitBodyBox.availableWidth
                                                text: GitBackend.commitInfo.body || ""
                                                onTextChanged: open = false
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: Design.text
                                                wrapMode: Text.Wrap
                                                maximumLineCount: open ? 100000 : 4
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Text {
                                            visible: commitBodyBox.visible && (commitBody.truncated || commitBody.open)
                                            text: commitBody.open ? I18n.tr("Show less") : I18n.tr("Show more")
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: Design.textDim
                                            Clickable {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: commitBody.open = !commitBody.open
                                            }
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
                                        Layout.preferredWidth: Math.round(Math.max(Design.s(Design.width.label), Math.min(Design.s(Design.size.canvas), window.width * 0.2)))
                                        Layout.fillHeight: true
                                        clip: true
                                        model: GitBackend.commitFiles
                                        spacing: 1
                                        ScrollBar.vertical: OverflowBar {}

                                        delegate: Rectangle {
                                            id: commitFileRow
                                            x: Design.s(Design.space.xs)
                                            width: commitFileList.width - Design.s(Design.space.xs) * 2
                                            radius: Design.s(Design.radius.ctl)
                                            height: Design.s(Design.size.sm)
                                            readonly property bool isSelected: GitBackend.commitFile === modelData.path
                                            color: isSelected ? Design.selection
                                                              : (cfArea.containsMouse ? Design.tint(Design.text, 0.05) : "transparent")

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Design.s(Design.space.sm)
                                                anchors.rightMargin: Design.s(Design.space.sm)
                                                spacing: Design.s(Design.space.sm)

                                                Text {
                                                    text: window.statusIcon(modelData.status)
                                                    font.family: Design.font.mono
                                                    font.pixelSize: Design.s(Design.font.body)
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
                                                    color: Design.text
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.path.substring(0, modelData.path.length - modelData.name.length)
                                                    font.family: Design.font.mono
                                                    font.pixelSize: Design.s(Design.font.caption)
                                                    color: Design.textDim
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
                                        color: Design.glassBorder
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
                                            height: Design.s(Design.size.sm)
                                            visible: GitBackend.commitFile !== ""
                                            color: "transparent"

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                height: 1
                                                color: Design.glassBorder
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Design.s(Design.space.md)
                                                anchors.rightMargin: Design.s(Design.space.xs)
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: GitBackend.commitFile
                                                    font.family: Design.font.mono
                                                    font.pixelSize: Design.s(Design.font.caption)
                                                    font.weight: Design.weight.semibold
                                                    color: Design.text
                                                    elide: Text.ElideMiddle
                                                }
                                                Button {
                                                    variant: "ghost"; size: "sm"; iconOnly: true
                                                    icon: "\u{f0bdd}"
                                                    checked: GitBackend.ignoreWhitespace
                                                    tip: GitBackend.ignoreWhitespace ? I18n.tr("Show whitespace changes") : I18n.tr("Hide whitespace changes")
                                                    onClicked: GitBackend.ignoreWhitespace = !GitBackend.ignoreWhitespace
                                                }
                                                Button {
                                                    variant: "ghost"; size: "sm"; iconOnly: true
                                                    icon: "\u{f0219}"
                                                    checked: GitBackend.fullFile
                                                    tip: GitBackend.fullFile ? I18n.tr("Show only the changes") : I18n.tr("Show the whole file")
                                                    onClicked: GitBackend.fullFile = !GitBackend.fullFile
                                                }
                                                Button {
                                                    variant: "ghost"; size: "sm"; iconOnly: true
                                                    icon: "\u{f0db}"
                                                    checked: window.splitDiff
                                                    tip: window.splitDiff ? I18n.tr("Unified view") : I18n.tr("Side by side")
                                                    onClicked: window.splitDiff = !window.splitDiff
                                                }
                                            }
                                        }

                                        ImageCompare {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            visible: window.isImage(GitBackend.commitFile)
                                            pair: visible ? GitBackend.imagePair(GitBackend.commitFile, GitBackend.selectedCommit) : ({})
                                        }

                                        ListView {
                                            id: commitDiffList
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            visible: !window.isImage(GitBackend.commitFile)
                                            model: window.splitDiff ? window.splitRows(GitBackend.commitDiff) : GitBackend.commitDiff
                                            delegate: window.splitDiff ? splitRowDelegate : diffRowDelegate
                                            ScrollBar.vertical: OverflowBar {}

                                            EmptyState {
                                                parent: commitDiffList
                                                anchors.centerIn: parent
                                                width: parent.width
                                                visible: GitBackend.commitDiff.length === 0
                                                // A rename with identical content
                                                // has no hunks; say what happened
                                                // to it instead of "nothing".
                                                readonly property var shown: GitBackend.commitFiles.find(f => f.path === GitBackend.commitFile)
                                                icon: "\u{f0219}"
                                                title: GitBackend.commitFiles.length === 0
                                                      ? I18n.tr("This commit changes no files")
                                                      : (shown && shown.oldPath)
                                                        ? I18n.tr("Renamed from %1, content unchanged", shown.oldPath)
                                                        : I18n.tr("No textual changes in this file")
                                            }
                                        }
                                    }
                                }

                                // Nothing picked yet.
                                ColumnLayout {
                                    Layout.alignment: Qt.AlignCenter
                                    Layout.fillHeight: true
                                    spacing: Design.s(Design.space.md)
                                    visible: GitBackend.selectedCommit === ""

                                    Item { Layout.fillHeight: true }
                                    EmptyState {
                                        icon: "󰜘"
                                        title: GitBackend.isRepo ? I18n.tr("Select a commit") : I18n.tr("No Git Repository Open")
                                        hint: GitBackend.isRepo ? I18n.tr("Its files and changes appear here.")
                                                                : I18n.tr("Select a repository from the top menu or open a folder.")
                                    }
                                    Item { Layout.fillHeight: true }
                                }
                            }
                        }

                        // What state the repository is in, and what just happened: the
                        // standard status bar. The notices were a toast of Git's own that
                        // slid up over the diff.
                        AppStatusBar {
                            Layout.fillWidth: true
                            visible: window.hasRepo
                            Label {
                                role: "caption"
                                dim: true
                                text: GitBackend.branchName + (GitBackend.upstream ? "  →  " + GitBackend.upstream : "")
                                      + (GitBackend.aheadCount > 0 ? "   " + GitBackend.aheadCount + "↑" : "")
                                      + (GitBackend.behindCount > 0 ? "   " + GitBackend.behindCount + "↓" : "")
                            }
                            InlineStatus {
                                visible: notice.message !== ""
                                Layout.fillWidth: true
                                status: notice.isError ? "error" : "ok"
                                message: notice.message
                                showRetry: false
                            }
                            Item { Layout.fillWidth: !notice.message; visible: !notice.message }
                            Label {
                                role: "caption"
                                color: Design.textFaint
                                text: I18n.trn("%1 changed file", "%1 changed files", GitBackend.changedFiles.length)
                            }
                        }
                    }
                }



                // REPOSITORY SELECTOR DROPDOWN POPUP
                // ══════════════════════════════════════════════════════════════
                // Hangs from its cell, flush with its left edge, as the
                // original's does.
                Popover {
                    id: repoPop
                    anchorItem: repoBtn
                    width: Math.min(Design.s(Design.width.menuMax), window.width - Design.s(Design.space.lg))
                    height: Design.s(Design.width.text)
                    padding: Design.s(Design.space.md)
                    onClosed: window.closeDropdowns()

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Design.s(Design.space.sm)

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Repositories")
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(Design.font.body)
                                font.weight: Design.weight.semibold
                                color: Design.text
                            }
                            // No "rescan": the list is what has been opened
                            // here, on purpose. Searching the disk both missed
                            // the repository in use and filled the list with
                            // whatever else it found.
                            Text {
                                text: GitBackend.repos.length + (GitBackend.repos.length === 1 ? " repository" : " repositories")
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(Design.font.caption)
                                color: Design.textDim
                            }
                        }

                        // Open a folder the way every other application does,
                        // or clone or start one, as GitHub Desktop's File menu.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Design.s(Design.space.xs)
                            Button {
                                Layout.fillWidth: true
                                size: "sm"; icon: "󰉋"
                                label: I18n.tr("Open…")
                                tip: I18n.tr("Add a repository from this computer")
                                onClicked: { window.repoDropdownOpen = false; GitBackend.pickRepoFolder(); }
                            }
                            Button {
                                Layout.fillWidth: true
                                size: "sm"; icon: "\u{f01da}"
                                label: I18n.tr("Clone…")
                                tip: I18n.tr("Clone a repository from GitHub or a URL")
                                onClicked: { window.repoDropdownOpen = false; cloneDialog.show(); }
                            }
                            Button {
                                Layout.fillWidth: true
                                size: "sm"; icon: "\u{f0415}"
                                label: I18n.tr("New…")
                                tip: I18n.tr("Create a new repository")
                                onClicked: { window.repoDropdownOpen = false; newRepoDialog.show(); }
                            }
                        }

                        // Filter, which doubles as the old path field: a path
                        // typed in full still opens on Enter.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(Design.size.sm)
                            radius: Design.s(Design.radius.sm)
                            color: Design.well
                            border.color: Design.glassBorder
                            border.width: Design.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(Design.space.sm)
                                anchors.rightMargin: Design.s(Design.space.sm)
                                spacing: Design.s(Design.space.xs)

                                Text { text: "󰍉"; font.family: Design.font.mono; font.pixelSize: Design.s(Design.font.caption); color: Design.textDim }

                                TextInput {
                                    id: repoFilterInput
                                    Layout.fillWidth: true
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: Design.text
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
                                        color: Design.textDim
                                    }
                                }
                            }
                        }

                        ListView {
                            id: repoList
        ScrollBar.vertical: OverflowBar {}
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 1
                            model: window.filteredRepos

                            delegate: Rectangle {
                                id: repoRowItem
                                required property var modelData
                                width: repoList.width
                                height: Design.s(Design.size.md)
                                radius: Design.s(Design.radius.sm)
                                readonly property bool isCurrent: modelData.path === GitBackend.repoPath
                                color: repoItemArea.containsMouse ? Design.glassHover
                                     : (isCurrent ? Design.selection : "transparent")

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
                                    anchors.leftMargin: Design.s(Design.space.sm)
                                    anchors.rightMargin: Design.s(Design.space.xs)
                                    spacing: Design.s(Design.space.sm)

                                    Text { text: "󰊢"; font.family: Design.font.mono; font.pixelSize: Design.s(Design.font.footnote); color: Design.textDim }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            text: repoRowItem.modelData.name
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            font.weight: Design.weight.semibold
                                            color: Design.text
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: repoRowItem.modelData.path
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: Design.textDim
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    // Two different things, so two buttons:
                                    // take it off the list, or delete the
                                    // working tree. Only the first is one
                                    // click; the second asks below, by name.
                                    Rectangle {
                                        Layout.preferredWidth: Design.s(Design.size.mini)
                                        Layout.preferredHeight: Design.s(Design.size.mini)
                                        radius: Design.s(Design.radius.sm)
                                        visible: repoItemArea.containsMouse || trashArea.containsMouse || forgetArea.containsMouse
                                        color: trashArea.containsMouse ? Design.tint(Design.danger, 0.30) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰩹"
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: trashArea.containsMouse ? Design.danger : Design.textDim
                                        }
                                        Clickable {
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
                                        Layout.preferredWidth: Design.s(Design.size.mini)
                                        Layout.preferredHeight: Design.s(Design.size.mini)
                                        radius: Design.s(Design.radius.sm)
                                        visible: repoItemArea.containsMouse || trashArea.containsMouse || forgetArea.containsMouse
                                        color: forgetArea.containsMouse ? Design.tint(Design.warn, 0.30) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: forgetArea.containsMouse ? Design.text : Design.textDim
                                        }
                                        Clickable {
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

                        // The open repository's submodules, each a repository
                        // of its own to open, and the one way to bring them
                        // all to the commits recorded.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: GitBackend.submodules.length > 0
                            spacing: 1
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    role: "caption"; dim: true; weight: Design.weight.semibold
                                    text: I18n.tr("Submodules of %1", GitBackend.repoName)
                                }
                                Button {
                                    variant: "ghost"; size: "sm"
                                    label: I18n.tr("Update")
                                    tip: I18n.tr("Check every submodule out at the commit this repository records")
                                    enabled: !window.busy
                                    onClicked: GitBackend.updateSubmodules()
                                }
                            }
                            Repeater {
                                model: GitBackend.submodules
                                delegate: Rectangle {
                                    id: subRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Design.s(Design.size.sm)
                                    radius: Design.s(Design.radius.sm)
                                    color: subArea.containsMouse ? Design.glassHover : "transparent"
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Design.s(Design.space.sm)
                                        anchors.rightMargin: Design.s(Design.space.sm)
                                        spacing: Design.s(Design.space.sm)
                                        Text {
                                            text: "\u{f0b9c}"
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: subRow.modelData.state === "+" ? Design.warn
                                                 : subRow.modelData.state === "-" ? Design.textFaint
                                                 : subRow.modelData.state === "U" ? Design.danger : Design.textDim
                                        }
                                        Label { Layout.fillWidth: true; role: "caption"; text: subRow.modelData.path; elide: Text.ElideMiddle }
                                        Label {
                                            role: "caption"; dim: true
                                            text: subRow.modelData.state === "-" ? I18n.tr("not checked out")
                                                : subRow.modelData.state === "+" ? I18n.tr("at another commit")
                                                : subRow.modelData.state === "U" ? I18n.tr("conflicted") : subRow.modelData.commit
                                        }
                                    }
                                    MouseArea {
                                        id: subArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: subRow.modelData.state !== "-"
                                        onClicked: {
                                            window.repoDropdownOpen = false;
                                            GitBackend.openRepo(GitBackend.absolutePath(subRow.modelData.path));
                                        }
                                    }
                                }
                            }
                        }

                        EmptyState {
                            visible: window.filteredRepos.length === 0
                            icon: GitBackend.repos.length === 0 ? "\u{f02a2}" : "\u{f0349}"
                            title: GitBackend.repos.length === 0 ? I18n.tr("No repositories")
                                 : I18n.tr("Nothing matches “%1”", window.repoFilter.trim())
                            hint: GitBackend.repos.length === 0 ? I18n.tr("Open a repository with the button above.") : ""
                        }

                        // Deleting the working tree, asked for explicitly and
                        // by name. It goes to the trash rather than being
                        // removed: a repository is somebody's work, and the
                        // file manager beside it treats delete the same way.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(Design.size.tile)
                            visible: window.pendingTrashRepo !== ""
                            radius: Design.s(Design.radius.sm)
                            color: Design.tint(Design.danger, 0.15)
                            border.color: Design.danger
                            border.width: Design.border

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(Design.space.xs)
                                spacing: Design.s(Design.space.xs)

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Move %1 to the trash? This deletes the whole working tree.", window.pendingTrashRepo)
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: Design.text
                                    wrapMode: Text.WordWrap
                                }

                                RowLayout {
                                    spacing: Design.s(Design.space.xs)
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: I18n.tr("Cancel")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: Design.textDim
                                        Clickable {
                                            anchors.fill: parent
                                            anchors.margins: -Design.s(Design.space.xs)
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.pendingTrashRepo = ""
                                        }
                                    }
                                    Text {
                                        text: I18n.tr("Move to trash")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.weight: Design.weight.semibold
                                        color: Design.danger
                                        Clickable {
                                            anchors.fill: parent
                                            anchors.margins: -Design.s(Design.space.xs)
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
                Popover {
                    id: branchPop
                    anchorItem: branchBtn
                    width: Math.min(Design.s(Design.width.select), window.width - Design.s(Design.space.sm))
                    height: Math.min(window.height - Design.s(Design.size.rowTall) * 2,
                                     Design.s(Design.width.select)
                                     + (window.pendingSwitch !== "" ? Design.s(Design.size.thumb) : 0)
                                     + (window.pendingRemoveWorktree !== "" ? Design.s(Design.size.tile) : 0)
                                     + (GitBackend.worktrees.length > 1 ? Design.s(Design.size.island) * (1 + GitBackend.worktrees.length) : 0))
                    padding: Design.s(Design.space.md)
                    onClosed: window.closeDropdowns()

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Design.s(Design.space.sm)

                        Text {
                            visible: !window.onGithub
                            text: I18n.tr("Branches")
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(Design.font.body)
                            font.weight: Design.weight.semibold
                            color: Design.text
                        }
                        // On GitHub, its pull requests beside the branches, as
                        // GitHub Desktop's branch list has them.
                        SegmentedControl {
                            Layout.fillWidth: true
                            visible: window.onGithub
                            size: "sm"
                            model: [
                                { id: "branches", label: I18n.tr("Branches") },
                                { id: "prs", label: I18n.tr("Pull requests") + (GitBackend.pullRequests.length ? "  " + GitBackend.pullRequests.length : "") }
                            ]
                            current: window.branchView
                            onPicked: id => {
                                window.branchView = id;
                                if (id === "prs") GitBackend.refreshPullRequests();
                            }
                        }

                        // Creating a branch needed a terminal before this.
                        Rectangle {
                            visible: window.branchView === "branches" || !window.onGithub
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(Design.size.sm)
                            radius: Design.s(Design.radius.sm)
                            color: Design.well
                            border.color: Design.glassBorder
                            border.width: Design.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(Design.space.sm)
                                anchors.rightMargin: Design.s(Design.space.xs)
                                spacing: Design.s(Design.space.xs)

                                TextInput {
                                    id: newBranchInput
                                    Layout.fillWidth: true
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: Design.text
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
                                        color: Design.textDim
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: Design.s(Design.size.rowTall)
                                    Layout.preferredHeight: Design.s(Design.size.mini)
                                    radius: Design.s(Design.radius.sm)
                                    opacity: newBranchInput.text.trim() === "" ? Design.opacity.disabled : 1.0
                                    color: Design.well
                                    Text {
                                        anchors.centerIn: parent
                                        text: I18n.tr("New")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.weight: Design.weight.semibold
                                        color: Design.text
                                    }
                                    Clickable {
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

                        // Open pull requests: a click checks one out (gh pr
                        // checkout), the icon at its end opens it on GitHub.
                        ListView {
                            id: prList
                            visible: window.onGithub && window.branchView === "prs"
                            ScrollBar.vertical: OverflowBar {}
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 1
                            model: GitBackend.pullRequests

                            EmptyState {
                                parent: prList
                                anchors.centerIn: parent
                                width: parent.width
                                visible: prList.count === 0
                                icon: "\u{f041b}"
                                title: GitBackend.loadingPullRequests ? I18n.tr("Loading pull requests…") : I18n.tr("No open pull requests")
                                hint: GitBackend.loadingPullRequests ? "" : !window.githubAccount || !window.githubAccount.login
                                      ? I18n.tr("Sign in to GitHub under Accounts to see them.") : ""
                            }

                            delegate: Rectangle {
                                id: prRow
                                required property var modelData
                                width: prList.width
                                height: Design.s(Design.size.md)
                                radius: Design.s(Design.radius.sm)
                                readonly property bool isCurrent: modelData.branch === GitBackend.branchName
                                color: isCurrent ? Design.selection : (prArea.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")

                                MouseArea {
                                    id: prArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (prRow.isCurrent) return;
                                        window.branchDropdownOpen = false;
                                        GitBackend.checkoutPullRequest(prRow.modelData.number);
                                    }
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Design.s(Design.space.xs)
                                    anchors.rightMargin: Design.s(Design.space.xxs)
                                    spacing: Design.s(Design.space.xs)
                                    Text {
                                        text: "\u{f041b}"
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: prRow.modelData.draft ? Design.textDim : Design.ok
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            Layout.fillWidth: true
                                            text: prRow.modelData.title
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            font.weight: Design.weight.semibold
                                            color: Design.text
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "#" + prRow.modelData.number + " · " + prRow.modelData.author
                                                  + (prRow.modelData.draft ? " · " + I18n.tr("draft") : "")
                                                  + " · " + window.relTime(prRow.modelData.updated)
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: Design.textDim
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Button {
                                        variant: "ghost"; size: "sm"; iconOnly: true
                                        icon: "\u{f03cc}"
                                        tip: I18n.tr("Open on GitHub")
                                        onClicked: GitBackend.openPullRequestOnWeb(prRow.modelData.number)
                                    }
                                }
                            }
                        }

                        ListView {
                            id: branchList
                            visible: window.branchView === "branches" || !window.onGithub
                            ScrollBar.vertical: OverflowBar {}
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 1
                            // Local branches, then the ones only on a remote.
                            readonly property var locals: {
                                const q = newBranchInput.text.trim().toLowerCase();
                                return q === "" ? GitBackend.branches
                                                : GitBackend.branches.filter(b => b.toLowerCase().indexOf(q) >= 0);
                            }
                            readonly property var remotes: {
                                const q = newBranchInput.text.trim().toLowerCase();
                                return q === "" ? GitBackend.remoteBranches
                                                : GitBackend.remoteBranches.filter(b => b.toLowerCase().indexOf(q) >= 0);
                            }
                            model: locals.concat(remotes)

                            EmptyState {
                                parent: branchList
                                anchors.centerIn: parent
                                width: parent.width
                                visible: branchList.count === 0 && newBranchInput.text.trim() !== ""
                                title: I18n.tr("No branch matches")
                                hint: I18n.tr("Press Enter to create it.")
                            }

                            delegate: Rectangle {
                                id: branchRowItem
                                required property var modelData
                                required property int index
                                readonly property bool isRemote: index >= branchList.locals.length
                                // The first remote one carries the heading above it.
                                readonly property bool firstRemote: isRemote && index === branchList.locals.length
                                width: branchList.width
                                height: Design.s(Design.size.sm) + (firstRemote ? Design.s(Design.size.xs) : 0)
                                radius: Design.s(Design.radius.sm)
                                readonly property bool isCurrent: modelData === GitBackend.branchName
                                color: isCurrent ? Design.selection
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
                                            branchMenu.remote = branchRowItem.isRemote;
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

                                Label {
                                    visible: branchRowItem.firstRemote
                                    x: Design.s(Design.space.xs)
                                    height: Design.s(Design.size.xs)
                                    verticalAlignment: Text.AlignVCenter
                                    role: "caption"; dim: true; weight: Design.weight.semibold
                                    text: I18n.tr("Other branches")
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.topMargin: branchRowItem.firstRemote ? Design.s(Design.size.xs) : 0
                                    anchors.leftMargin: Design.s(Design.space.xs)
                                    anchors.rightMargin: Design.s(Design.space.xs)
                                    spacing: Design.s(Design.space.xs)

                                    Text { text: branchRowItem.isRemote ? "\u{f015f}" : ""; font.family: Design.font.mono; font.pixelSize: Design.s(Design.font.caption); color: Design.textDim }
                                    Text {
                                        Layout.fillWidth: true
                                        text: branchRowItem.modelData
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.bold: branchRowItem.isCurrent
                                        color: Design.text
                                        elide: Text.ElideMiddle
                                    }
                                    // Where it stands against its remote.
                                    Text {
                                        readonly property var info: GitBackend.branchInfo[branchRowItem.modelData] || ({})
                                        visible: text !== "" && !branchRowItem.isRemote
                                        text: info.worktree ? "in worktree"
                                            : info.gone ? "deleted on remote"
                                            : !info.upstream ? "local only"
                                            : (info.behind > 0 ? info.behind + "↓ " : "") + (info.ahead > 0 ? info.ahead + "↑" : "")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: info.gone ? Design.warn : Design.textDim
                                    }
                                    Text {
                                        text: "✓"
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.weight: Design.weight.semibold
                                        color: Design.accent
                                        visible: branchRowItem.isCurrent
                                    }

                                    // Not offered for the branch you are on:
                                    // git refuses that one, and a button whose
                                    // only outcome is an error message is worse
                                    // than no button.
                                    Rectangle {
                                        Layout.preferredWidth: Design.s(Design.size.mini)
                                        Layout.preferredHeight: Design.s(Design.size.mini)
                                        radius: Design.s(Design.radius.sm)
                                        visible: !branchRowItem.isCurrent && !branchRowItem.isRemote && (bArea.containsMouse || delArea.containsMouse)
                                        color: delArea.containsMouse ? Design.tint(Design.danger, 0.30) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: delArea.containsMouse ? Design.danger : Design.textDim
                                        }
                                        Clickable {
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
                            visible: GitBackend.worktrees.length > 1 && branchList.visible

                            Text {
                                text: I18n.tr("Worktrees")
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(Design.font.body)
                                font.weight: Design.weight.semibold
                                color: Design.text
                                bottomPadding: Design.s(Design.space.xs)
                            }

                            Repeater {
                                model: GitBackend.worktrees
                                delegate: Rectangle {
                                    id: wtRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Design.s(Design.size.sm)
                                    radius: Design.s(Design.radius.sm)
                                    color: modelData.current ? Design.selection
                                         : (wtArea.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Design.s(Design.space.xs)
                                        anchors.rightMargin: Design.s(Design.space.xs)
                                        spacing: Design.s(Design.space.xs)
                                        Text { text: "󰉋"; font.family: Design.font.mono; font.pixelSize: Design.s(Design.font.caption); color: Design.textDim }
                                        Text {
                                            text: wtRow.modelData.branch || ""
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(Design.font.caption)
                                            font.bold: wtRow.modelData.current
                                            color: Design.text
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: wtRow.modelData.path
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: Design.textDim
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
                            Layout.preferredHeight: Design.s(Design.size.rowTall)
                            visible: window.pendingRemoveWorktree !== ""
                            radius: Design.s(Design.radius.sm)
                            color: Design.tint(Design.danger, 0.15)
                            border.color: Design.danger
                            border.width: Design.border

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(Design.space.xs)
                                spacing: Design.s(Design.space.xs)
                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Remove the worktree at %1?", window.pendingRemoveWorktree)
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: Design.text
                                    elide: Text.ElideMiddle
                                }
                                RowLayout {
                                    spacing: Design.s(Design.space.sm)
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: I18n.tr("Cancel")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: Design.textDim
                                        Clickable { anchors.fill: parent; anchors.margins: -Design.s(Design.space.xs); cursorShape: Qt.PointingHandCursor; onClicked: window.pendingRemoveWorktree = "" }
                                    }
                                    Text {
                                        text: I18n.tr("Remove")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.weight: Design.weight.semibold
                                        color: Design.danger
                                        Clickable {
                                            anchors.fill: parent
                                            anchors.margins: -Design.s(Design.space.xs)
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
                            Layout.preferredHeight: switchCol.implicitHeight + Design.s(Design.space.md)
                            visible: window.pendingSwitch !== ""
                            radius: Design.s(Design.radius.sm)
                            color: Design.well
                            border.color: Design.accent
                            border.width: Design.border

                            ColumnLayout {
                                id: switchCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Design.s(Design.space.xs)
                                spacing: Design.s(Design.space.xs)

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.trn("You have %1 changed file on %2.", "You have %1 changed files on %2.",
                                                   GitBackend.changedFiles.length, GitBackend.branchName)
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.caption)
                                    font.weight: Design.weight.semibold
                                    color: Design.text
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
                                        Layout.preferredHeight: Design.s(Design.size.knob)
                                        radius: Design.s(Design.radius.sm)
                                        color: optArea.containsMouse ? Design.glassHover : Design.surface
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Design.s(Design.space.sm)
                                            anchors.rightMargin: Design.s(Design.space.sm)
                                            spacing: 0
                                            Text {
                                                Layout.fillWidth: true
                                                text: parent.parent.title
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                font.weight: Design.weight.semibold
                                                color: Design.text
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: parent.parent.detail
                                                font.family: Design.font.sans
                                                font.pixelSize: Design.s(Design.font.caption)
                                                color: Design.textDim
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Clickable {
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
                                    color: Design.textDim
                                    Clickable {
                                        anchors.fill: parent
                                        anchors.margins: -Design.s(Design.space.xs)
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: window.pendingSwitch = ""
                                    }
                                }
                            }
                        }

                        // The second question, asked only when git said no.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(Design.size.rowTall)
                            visible: window.pendingDeleteBranch !== ""
                            radius: Design.s(Design.radius.sm)
                            color: Design.tint(Design.danger, 0.15)
                            border.color: Design.danger
                            border.width: Design.border

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(Design.space.xs)
                                spacing: Design.s(Design.space.xs)

                                Text {
                                    Layout.fillWidth: true
                                    text: "\"" + window.pendingDeleteBranch + "\" is not merged anywhere. Deleting it loses its commits."
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: Design.text
                                    wrapMode: Text.WordWrap
                                }

                                RowLayout {
                                    spacing: Design.s(Design.space.xs)
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: I18n.tr("Cancel")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: Design.textDim
                                        Clickable {
                                            anchors.fill: parent
                                            anchors.margins: -Design.s(Design.space.xs)
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.pendingDeleteBranch = ""
                                        }
                                    }
                                    Text {
                                        text: I18n.tr("Delete anyway")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.weight: Design.weight.semibold
                                        color: Design.danger
                                        Clickable {
                                            anchors.fill: parent
                                            anchors.margins: -Design.s(Design.space.xs)
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
                Popover {
                    id: accountsPop
                    anchorItem: accountsBtn
                    width: Design.s(Design.width.select)
                    padding: Design.s(Design.space.sm)
                    onClosed: window.closeDropdowns()

                    ColumnLayout {
                        id: accCol
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.sm)

                        Text {
                            text: I18n.tr("Accounts")
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(Design.font.body)
                            font.weight: Design.weight.semibold
                            color: Design.text
                        }

                        Repeater {
                            model: GitBackend.accounts

                            delegate: Rectangle {
                                id: accItem
                                required property var modelData
                                readonly property bool signedIn: !!modelData.login
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(Design.size.art)
                                radius: Design.s(Design.radius.sm)
                                color: Design.glassCard
                                border.color: Design.glassBorder
                                border.width: Design.border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Design.s(Design.space.sm)
                                    anchors.rightMargin: Design.s(Design.space.sm)
                                    spacing: Design.s(Design.space.sm)

                                    Text {
                                        text: accItem.modelData.provider === "github" ? "" : ""
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(Design.font.glyph)
                                        color: accItem.modelData.provider === "gitlab" ? Design.warn : Design.text
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            text: accItem.modelData.name
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.body)
                                            font.weight: Design.weight.semibold
                                            color: Design.text
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: !accItem.modelData.installed ? I18n.tr("%1 is not installed", accItem.modelData.cli)
                                                : accItem.signedIn ? I18n.tr("Signed in as %1", accItem.modelData.login)
                                                : I18n.tr("Not signed in")
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: accItem.signedIn ? Design.ok : Design.textDim
                                        }
                                    }

                                    Rectangle {
                                        visible: accItem.modelData.installed
                                        Layout.preferredWidth: accBtnText.implicitWidth + Design.s(Design.space.lg)
                                        Layout.preferredHeight: Design.s(Design.size.xs)
                                        radius: Design.s(Design.radius.sm)
                                        color: accBtnArea.containsMouse
                                               ? (accItem.signedIn ? Design.tint(Design.danger, 0.25) : Qt.lighter(Design.accent, 1.1))
                                               : (accItem.signedIn ? "transparent" : Design.accent)
                                        border.color: accItem.signedIn ? Design.glassBorder : "transparent"
                                        border.width: Design.border
                                        Text {
                                            id: accBtnText
                                            anchors.centerIn: parent
                                            text: accItem.signedIn ? I18n.tr("Sign out") : I18n.tr("Sign in")
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            font.bold: !accItem.signedIn
                                            color: accItem.signedIn ? Design.text : Design.accentText
                                        }
                                        Clickable {
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

    // The dialog from window.ask(): Ui's AppDialog, as in every app. It was
    // a box of its own with hand-drawn buttons over a darker scrim.
    AppDialog {
        id: askDialog
        title: window.dialog ? window.dialog.title : ""
        destructive: window.dialog !== null && window.dialog.destructive === true
        standardButtons: Dialog.Cancel | Dialog.Ok
        buttonText: ({ [Dialog.Ok]: window.dialog ? (window.dialog.confirm || I18n.tr("OK")) : I18n.tr("OK") })
        onAccepted: window.closeDialog(true)
        onRejected: window.closeDialog(false)

        contentItem: ColumnLayout {
            implicitWidth: Design.s(Design.width.menuMax)
            spacing: Design.s(Design.space.sm)
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: window.dialog ? (window.dialog.text || "") : ""
                dim: true
                wrapMode: Text.Wrap
            }
            Field {
                id: dialogInput
                Layout.fillWidth: true
                mono: true
                visible: window.dialog !== null && window.dialog.input === true
                placeholder: window.dialog ? (window.dialog.placeholder || "") : ""
                onAccepted: askDialog.accept()
            }
        }
    }

    // ── A commit's message ────────────────────────────────────────────────
    AppDialog {
        id: rewordDialog
        property string hash: ""
        function show(h) {
            hash = h;
            const msg = GitBackend.commitMessage(h);
            const cut = msg.indexOf("\n");
            rewordSummary.text = cut < 0 ? msg : msg.slice(0, cut);
            rewordBody.text = cut < 0 ? "" : msg.slice(cut).replace(/^\n+/, "");
            open();
            rewordSummary.focusInput();
        }
        title: I18n.tr("Edit commit message")
        standardButtons: Dialog.Cancel | Dialog.Ok
        buttonText: ({ [Dialog.Ok]: I18n.tr("Save message") })
        onAccepted: {
            const summary = rewordSummary.text.trim();
            if (summary === "") { Qt.callLater(rewordDialog.open); return; }
            const body = rewordBody.text.trim();
            GitBackend.rewordCommit(rewordDialog.hash, summary + (body ? "\n\n" + body : ""));
        }
        contentItem: ColumnLayout {
            implicitWidth: Design.s(Design.width.menuMax)
            spacing: Design.s(Design.space.sm)
            Field { id: rewordSummary; Layout.fillWidth: true; placeholder: I18n.tr("Summary (required)") }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.width.label)
                radius: Design.s(Design.radius.ctl)
                color: Design.sunken
                border.color: rewordBody.activeFocus ? Design.accent : Design.line
                border.width: Design.border
                ScrollView {
                    id: rewordScroll
                    anchors.fill: parent
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical: OverflowBar { view: rewordScroll }
                    TextArea {
                        id: rewordBody
                        placeholderText: I18n.tr("Description")
                        wrapMode: TextEdit.Wrap
                        font.family: Design.font.sans
                        font.pixelSize: Design.s(Design.font.body)
                        color: Design.text
                        background: null
                        selectByMouse: true
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                role: "caption"; color: Design.textFaint
                wrapMode: Text.Wrap
                text: I18n.tr("The commits after it are rewritten too; they keep their changes.")
            }
        }
    }

    // ── Clone ─────────────────────────────────────────────────────────────
    // GitHub Desktop's: the account's repositories to pick from, or any URL,
    // and where on this machine it goes.
    AppDialog {
        id: cloneDialog
        property string mode: "github"
        property string picked: ""
        function show() {
            picked = "";
            cloneUrl.text = "";
            cloneFilter.text = "";
            if (cloneParent.text === "") cloneParent.text = GitBackend.defaultProjectsDir;
            mode = window.githubAccount && window.githubAccount.login ? "github" : "url";
            if (mode === "github") GitBackend.refreshRemoteRepos();
            open();
            if (mode === "url") cloneUrl.focusInput(); else cloneFilter.focusInput();
        }
        readonly property string url: mode === "github" ? picked : cloneUrl.text.trim()
        readonly property string repoName: {
            const u = cloneDialog.url.replace(/\/+$/, "").replace(/\.git$/, "");
            return u.split(/[\/:]/).pop();
        }
        title: I18n.tr("Clone a repository")
        standardButtons: Dialog.Cancel | Dialog.Ok
        buttonText: ({ [Dialog.Ok]: I18n.tr("Clone") })
        onAccepted: {
            if (cloneDialog.url === "") { Qt.callLater(cloneDialog.open); return; }
            GitBackend.cloneRepo(cloneDialog.url, cloneParent.text);
        }
        Connections {
            target: GitBackend
            function onFolderPicked(purpose, path) {
                if (purpose === "clone") cloneParent.text = path;
                else if (purpose === "new") newParent.text = path;
            }
            function onRepoCreated(ok, path) {
                if (ok) window.currentTab = 0;
            }
        }
        contentItem: ColumnLayout {
            implicitWidth: Design.s(Design.width.menuMax)
            spacing: Design.s(Design.space.sm)
            SegmentedControl {
                Layout.fillWidth: true
                size: "sm"
                model: [{ id: "github", label: "GitHub" }, { id: "url", label: I18n.tr("URL") }]
                current: cloneDialog.mode
                onPicked: id => {
                    cloneDialog.mode = id;
                    if (id === "github" && GitBackend.remoteRepos.length === 0) GitBackend.refreshRemoteRepos();
                }
            }
            Field {
                id: cloneFilter
                Layout.fillWidth: true
                visible: cloneDialog.mode === "github"
                placeholder: I18n.tr("Filter your repositories")
            }
            ListView {
                id: remoteRepoList
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.width.label) * 2
                visible: cloneDialog.mode === "github"
                clip: true
                spacing: 1
                ScrollBar.vertical: OverflowBar {}
                model: {
                    const q = cloneFilter.text.trim().toLowerCase();
                    return q === "" ? GitBackend.remoteRepos
                                    : GitBackend.remoteRepos.filter(r => r.name.toLowerCase().indexOf(q) >= 0);
                }
                EmptyState {
                    parent: remoteRepoList
                    anchors.centerIn: parent
                    width: parent.width
                    visible: remoteRepoList.count === 0
                    icon: "\u{f02a4}"
                    title: GitBackend.loadingRemoteRepos ? I18n.tr("Loading your repositories…")
                         : !window.githubAccount || !window.githubAccount.login ? I18n.tr("Not signed in to GitHub")
                         : I18n.tr("No repositories")
                    hint: !GitBackend.loadingRemoteRepos && (!window.githubAccount || !window.githubAccount.login)
                          ? I18n.tr("Sign in under Accounts, or clone by URL.") : ""
                }
                delegate: Rectangle {
                    id: rrRow
                    required property var modelData
                    width: remoteRepoList.width
                    height: Design.s(Design.size.md)
                    radius: Design.s(Design.radius.sm)
                    readonly property bool chosen: cloneDialog.picked === modelData.url
                    color: chosen ? Design.selection : (rrArea.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(Design.space.sm)
                        anchors.rightMargin: Design.s(Design.space.sm)
                        spacing: Design.s(Design.space.sm)
                        Text {
                            text: rrRow.modelData.private ? "\u{f033e}" : "\u{f02a4}"
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(Design.font.caption)
                            color: Design.textDim
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { Layout.fillWidth: true; role: "caption"; weight: Design.weight.semibold; text: rrRow.modelData.name; elide: Text.ElideRight }
                            Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                role: "caption"; dim: true
                                text: rrRow.modelData.description || ""
                                elide: Text.ElideRight
                            }
                        }
                    }
                    MouseArea {
                        id: rrArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cloneDialog.picked = rrRow.modelData.url
                        onDoubleClicked: { cloneDialog.picked = rrRow.modelData.url; cloneDialog.accept(); }
                    }
                }
            }
            Field {
                id: cloneUrl
                Layout.fillWidth: true
                visible: cloneDialog.mode === "url"
                mono: true
                placeholder: I18n.tr("https://github.com/owner/name, git@…, or owner/name")
            }
            Label { role: "caption"; dim: true; text: I18n.tr("Into the folder") }
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)
                Field { id: cloneParent; Layout.fillWidth: true; mono: true }
                Button { size: "sm"; label: I18n.tr("Choose…"); onClicked: GitBackend.pickFolder("clone", cloneParent.text) }
            }
            Label {
                Layout.fillWidth: true
                visible: cloneDialog.repoName !== ""
                role: "caption"; color: Design.textFaint
                text: I18n.tr("Clones to %1", cloneParent.text.replace(/\/+$/, "") + "/" + cloneDialog.repoName)
                elide: Text.ElideMiddle
            }
        }
    }

    // ── New repository ────────────────────────────────────────────────────
    AppDialog {
        id: newRepoDialog
        property bool readme: true
        property string gitignore: ""
        function show() {
            newName.text = "";
            newDesc.text = "";
            if (newParent.text === "") newParent.text = GitBackend.defaultProjectsDir;
            GitBackend.refreshGitignoreTemplates();
            open();
            newName.focusInput();
        }
        title: I18n.tr("Create a new repository")
        standardButtons: Dialog.Cancel | Dialog.Ok
        buttonText: ({ [Dialog.Ok]: I18n.tr("Create repository") })
        onAccepted: {
            if (newName.text.trim() === "") { Qt.callLater(newRepoDialog.open); return; }
            GitBackend.createRepo(newParent.text, newName.text, newDesc.text, newRepoDialog.readme, newRepoDialog.gitignore);
        }
        contentItem: ColumnLayout {
            implicitWidth: Design.s(Design.width.menuMax)
            spacing: Design.s(Design.space.sm)
            Label { role: "caption"; dim: true; text: I18n.tr("Name") }
            Field { id: newName; Layout.fillWidth: true; mono: true; placeholder: I18n.tr("my-project") }
            Label { role: "caption"; dim: true; text: I18n.tr("Description") }
            Field { id: newDesc; Layout.fillWidth: true; placeholder: I18n.tr("Optional") }
            Label { role: "caption"; dim: true; text: I18n.tr("Local path") }
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)
                Field { id: newParent; Layout.fillWidth: true; mono: true }
                Button { size: "sm"; label: I18n.tr("Choose…"); onClicked: GitBackend.pickFolder("new", newParent.text) }
            }
            CheckBox {
                text: I18n.tr("Start with a README")
                checked: newRepoDialog.readme
                onToggled: newRepoDialog.readme = !newRepoDialog.readme
            }
            Label { role: "caption"; dim: true; text: I18n.tr(".gitignore template") }
            Select {
                Layout.fillWidth: true
                model: [{ id: "", label: I18n.tr("None") }].concat(GitBackend.gitignoreTemplates.map(t => ({ id: t, label: t })))
                current: newRepoDialog.gitignore
                onPicked: id => newRepoDialog.gitignore = id
            }
            Label {
                Layout.fillWidth: true
                visible: newName.text.trim() !== ""
                role: "caption"; color: Design.textFaint
                text: I18n.tr("Creates %1", newParent.text.replace(/\/+$/, "") + "/" + newName.text.trim())
                elide: Text.ElideMiddle
            }
        }
    }

    // ── Publish to GitHub ─────────────────────────────────────────────────
    AppDialog {
        id: publishDialog
        property bool isPrivate: true
        function show() {
            if (!window.githubAccount || !window.githubAccount.login) {
                notice.show(I18n.tr("Sign in to GitHub under Accounts first"), true);
                window.accountsDropdownOpen = true;
                return;
            }
            pubName.text = GitBackend.repoName;
            pubDesc.text = "";
            open();
            pubName.focusInput();
        }
        title: I18n.tr("Publish repository")
        standardButtons: Dialog.Cancel | Dialog.Ok
        buttonText: ({ [Dialog.Ok]: I18n.tr("Publish") })
        onAccepted: GitBackend.publishRepo(pubName.text, pubDesc.text, publishDialog.isPrivate)
        contentItem: ColumnLayout {
            implicitWidth: Design.s(Design.width.menuMax)
            spacing: Design.s(Design.space.sm)
            Label {
                Layout.fillWidth: true
                dim: true
                wrapMode: Text.Wrap
                text: I18n.tr("A new repository on GitHub under %1, with this one's commits pushed to it.",
                              window.githubAccount ? window.githubAccount.login : "")
            }
            Label { role: "caption"; dim: true; text: I18n.tr("Name") }
            Field { id: pubName; Layout.fillWidth: true; mono: true }
            Label { role: "caption"; dim: true; text: I18n.tr("Description") }
            Field { id: pubDesc; Layout.fillWidth: true; placeholder: I18n.tr("Optional") }
            CheckBox {
                text: I18n.tr("Keep this code private")
                checked: publishDialog.isPrivate
                onToggled: publishDialog.isPrivate = !publishDialog.isPrivate
            }
        }
    }

    // ── Repository settings ───────────────────────────────────────────────
    // The remote, who commits, and what is ignored — GitHub Desktop's
    // Repository settings.
    AppDialog {
        id: settingsDialog
        property bool globalIdentity: false
        readonly property var firstRemote: GitBackend.remotes.length ? GitBackend.remotes[0] : null
        function show() {
            remoteName.text = firstRemote ? firstRemote.name : "origin";
            remoteUrl.text = firstRemote ? firstRemote.url : "";
            idName.text = GitBackend.identity.name || "";
            idEmail.text = GitBackend.identity.email || "";
            open();
        }
        title: I18n.tr("Repository settings")
        standardButtons: Dialog.Cancel | Dialog.Save
        onAccepted: {
            const r = settingsDialog.firstRemote;
            const url = remoteUrl.text.trim();
            if (url !== "" && (!r || r.name !== remoteName.text.trim() || r.url !== url))
                GitBackend.setRemote(remoteName.text.trim() || "origin", url);
            if (idName.text.trim() !== (GitBackend.identity.name || "") || idEmail.text.trim() !== (GitBackend.identity.email || "")
                    || settingsDialog.globalIdentity)
                GitBackend.setIdentity(idName.text, idEmail.text, settingsDialog.globalIdentity);
        }
        contentItem: ColumnLayout {
            implicitWidth: Design.s(Design.width.menuMax)
            spacing: Design.s(Design.space.sm)
            SectionLabel { text: I18n.tr("Remote") }
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)
                Field { id: remoteName; Layout.preferredWidth: Design.s(Design.size.thumb); mono: true; placeholder: "origin" }
                Field { id: remoteUrl; Layout.fillWidth: true; mono: true; placeholder: "https://github.com/owner/name.git" }
            }
            Repeater {
                // Any others, read-only here, with a way to drop them.
                model: GitBackend.remotes.slice(1)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { role: "caption"; text: modelData.name; weight: Design.weight.semibold }
                    Label { Layout.fillWidth: true; role: "caption"; dim: true; text: modelData.url; elide: Text.ElideMiddle }
                    Button {
                        variant: "ghost"; size: "sm"; label: I18n.tr("Remove")
                        destructive: true
                        onActivated: GitBackend.removeRemote(modelData.name)
                    }
                }
            }
            SectionLabel { text: I18n.tr("Author"); Layout.topMargin: Design.s(Design.space.sm) }
            Field { id: idName; Layout.fillWidth: true; placeholder: I18n.tr("Name") }
            Field { id: idEmail; Layout.fillWidth: true; mono: true; placeholder: I18n.tr("Email") }
            CheckBox {
                text: I18n.tr("Use for every repository")
                checked: settingsDialog.globalIdentity
                onToggled: settingsDialog.globalIdentity = !settingsDialog.globalIdentity
            }
            SectionLabel { text: I18n.tr("Pulling"); Layout.topMargin: Design.s(Design.space.sm) }
            CheckBox {
                text: I18n.tr("Rebase my commits on top when pulling")
                checked: GitBackend.pullRebase
                onToggled: GitBackend.setPullRebase(!GitBackend.pullRebase)
            }
            SectionLabel { text: I18n.tr("Ignored files"); Layout.topMargin: Design.s(Design.space.sm) }
            Button {
                size: "sm"; icon: "\u{f0219}"
                label: I18n.tr("Edit .gitignore")
                onClicked: { settingsDialog.close(); GitBackend.editGitignore(); }
            }
        }
    }

    // What just happened, or what went wrong. Errors stay until clicked.
    Connections {
        target: GitBackend
        function onNotice(message) { notice.show(message, false); }
        function onCommandFailed(message) { notice.show(message, true); }
    }

    // The last notice, shown in the status bar: a confirmation for a few
    // seconds, an error until the next action replaces it.
    QtObject {
        id: notice
        property bool isError: false
        property string message: ""
        function show(msg, err) {
            notice.message = msg;
            notice.isError = err;
            noticeTimer.interval = err ? 15000 : 4000;
            noticeTimer.restart();
        }
    }

    // A folder dragged in from Files — or any file inside a repository —
    // opens that repository (openRepo looks up for its .git).
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            // urls, or the list itself when the drag carried only that.
            const urls = (drop.hasUrls ? Array.from(drop.urls, u => String(u))
                              : String(drop.getDataAsString("text/uri-list") || "").split(/\r?\n/).filter(l => l && !l.startsWith("#")));
            const url = urls.length ? urls[0] : "";
            if (!url.startsWith("file://")) return;
            drop.accept(Qt.CopyAction);
            GitBackend.openRepo(decodeURIComponent(url.slice(7)));
        }
    }
    Timer { id: noticeTimer; onTriggered: notice.message = "" }
}
