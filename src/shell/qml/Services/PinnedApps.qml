pragma Singleton

import QtQuick
import Quickshell
import B1air.Daemon
import Quickshell.Io

Singleton {
    id: root

    property var pinnedList: [
        { id: "b1air-files", name: "Files", icon: "b1air-files", cmd: "b1air-files" },
        { id: "b1air-term", name: "Terminal", icon: "b1air-term", cmd: "b1air-term" },
        { id: "firefox", name: "Browser", icon: "firefox", cmd: "firefox" }
    ]

    function isPinned(appIdOrName) {
        let key = (appIdOrName || "").toLowerCase();
        for (let item of root.pinnedList) {
            if (item.id.toLowerCase() === key || item.name.toLowerCase() === key || (item.cmd && item.cmd.toLowerCase().includes(key))) {
                return true;
            }
        }
        return false;
    }

    function togglePin(app) {
        let key = (app.name || app.id || "").toLowerCase();
        let idx = -1;
        for (let i = 0; i < root.pinnedList.length; i++) {
            if (root.pinnedList[i].id.toLowerCase() === key || root.pinnedList[i].name.toLowerCase() === key) {
                idx = i;
                break;
            }
        }
        let copy = Array.from(root.pinnedList);
        if (idx !== -1) {
            copy.splice(idx, 1);
        } else {
            copy.push({
                // The desktop id when there is one, so the bar can find the
                // app's real icon by it; the name was all this stored.
                id: String(app.desktopFile || "").replace(/\.desktop$/, "") || app.name || "app",
                name: app.name || "App",
                icon: app.icon || "󰀻",
                cmd: app.cmd || ""
            });
        }
        root.pinnedList = copy;
        save();
    }

    function save() {
        Sys.writeFile("~/.config/b1air/pinned_apps.json", JSON.stringify(root.pinnedList));
    }

    Component.onCompleted: {
        const t = Sys.readFile("~/.config/b1air/pinned_apps.json").trim();
        if (!t.startsWith("["))
            return;
        try {
            const parsed = JSON.parse(t);
            if (Array.isArray(parsed) && parsed.length > 0)
                root.pinnedList = parsed;
        } catch (e) {}
    }
}
