pragma Singleton

import QtQuick
import "../Ui"
import Quickshell
import B1air.Daemon
import Quickshell.Io

// =============================================================================
// Cmd — run a command and tell the user when it fails
//
// Quickshell.execDetached() discards the exit code, so a failed action is
// indistinguishable from a successful one: the wallpaper simply does not
// change and nothing explains why. Use this for anything the user triggered
// on purpose and is waiting on. Background polling can stay silent.
//
//   Cmd.run(["b1air-daemon", "wallpaper", "set", path], "Set wallpaper")
// =============================================================================

Singleton {
    id: root

    // Queue of { argv, label } waiting for a free runner.
    property var _queue: []
    property var _current: null

    function run(argv, label) {
        if (!argv || argv.length === 0) return;
        root._queue = root._queue.concat([{ argv: argv, label: label || argv[0] }]);
        root._pump();
    }

    function _pump() {
        if (root._current !== null || root._queue.length === 0) return;
        root._current = root._queue[0];
        root._queue = root._queue.slice(1);
        runner.command = root._current.argv;
        runner.running = true;
    }

    function _report(exitCode, stderrText) {
        const label = root._current ? root._current.label : I18n.tr("Command");
        const detail = (stderrText || "").trim().split("\n").filter(l => l.trim() !== "").pop()
                    || I18n.tr("exited with code %1", exitCode);
        Sys.notify("b1air", label + " failed", detail, "", "critical");
    }

    Process {
        id: runner
        stderr: StdioCollector { }
        onExited: (exitCode) => {
            if (exitCode !== 0) root._report(exitCode, runner.stderr.text);
            root._current = null;
            root._pump();
        }
    }
}
