// Kwake - applications are configured in the script's System Settings page.
// Storage is one line per application in kwinrc [Script-kwake] Entries:
//     Name | resourceClass | caption | shortcut
// Class is an exact, case-insensitive match; caption is an optional substring.

const SHORTCUT_PREFIX = "kwake_";
const KGA_SERVICE = "org.kde.kglobalaccel";
let workspace;
let options;
let readConfig;
let registerShortcut;
let callDBus;
let print;

// id -> entry, for every application currently configured.
let entries = {};
// id -> the key sequence we last passed to registerShortcut.
let registered = {};
// Entry id -> window UUID. A selected window keeps its identity as its title changes.
let selected = {};
// internalId -> window, for the windows this script took off the taskbar. Only
// these get restored, so windows that asked to skip the taskbar themselves
// (panels, splashes) are never dragged back into it.
let hidden = {};

function parseEntries(text) {
    const parsed = {};
    text.split("\n").forEach((line) => {
        line = line.trim();
        if (!line || line.charAt(0) === "#") return;

        const f = line.split("|").map((s) => s.trim());
        const name = f[0];
        if (!name || !f[1]) return;
        // Anything else would break the kglobalshortcutsrc key.
        const id = SHORTCUT_PREFIX + name.replace(/[^A-Za-z0-9_-]/g, "_");
        if (parsed[id]) return;

        parsed[id] = {
            name: name,
            id: id,
            resourceClass: f[1] || "",
            caption: f[2] || "",
            // A shortcut on the | key contains the separator itself.
            shortcut: f.slice(3).join("|"),
        };
    });
    return parsed;
}

function unregisterShortcut(id) {
    callDBus(KGA_SERVICE, "/kglobalaccel", "org.kde.KGlobalAccel", "unregister", "kwin", id);
}

function windowMatches(win, entry) {
    const classOk = win.resourceClass.toLowerCase() === entry.resourceClass.toLowerCase();
    const capOk =
        !entry.caption ||
        win.caption.toLowerCase().includes(entry.caption.toLowerCase());
    return (win.normalWindow || win.dialog) && classOk && capOk;
}

function findWindow(entry, windows) {
    const retained = windows.find((win) => String(win.internalId) === selected[entry.id]);
    if (retained) return retained;
    const matches = windows.filter((win) => windowMatches(win, entry));
    const target = matches.find((win) => win === workspace.activeWindow) || matches[matches.length - 1];
    if (target) selected[entry.id] = String(target.internalId);
    else delete selected[entry.id];
    return target;
}

function forgetWindow(win) {
    delete hidden[win.internalId];
    refreshTaskbarState(win);
}

function refreshTaskbarState(removed) {
    const windows = workspace.stackingOrder.filter((win) => win !== removed && !win.deleted);
    const taskbarWindows = [];
    const managed = Object.values(entries).map((entry) => {
        const win = findWindow(entry, windows);
        if (win && entry.shortcut) taskbarWindows.push(win);
        return win;
    }).filter(Boolean);
    for (const key in hidden) {
        const win = hidden[key];
        if (!taskbarWindows.includes(win)) {
            if (windows.includes(win)) win.skipTaskbar = false;
            delete hidden[key];
        }
    }
    taskbarWindows.forEach((win) => {
        if (!win.skipTaskbar) {
            hidden[win.internalId] = win;
            win.skipTaskbar = true;
        }
    });
    return managed;
}

function watchWindow(win) {
    win.captionChanged.connect(windowChanged);
    win.windowClassChanged.connect(windowChanged);
}

function windowChanged() {
    refreshTaskbarState();
}

function windowAdded(win) {
    watchWindow(win);
    refreshTaskbarState();
}

// Toggle windows: bring target to top, minimize others
function toggleWindow(id) {
    const entry = entries[id];
    if (!entry) return; // removed from the config since this shortcut was bound

    const managed = refreshTaskbarState();
    const target = managed.find((win) => String(win.internalId) === selected[id]);
    if (!target) return;
    let isTopMost = workspace.activeWindow === target;

    if (isTopMost) {
        // Target is on top: minimize it, activate next in stack
        target.minimized = true;
        let others = managed.filter((c) => c !== target && !c.minimized);
        if (others.length > 0) {
            workspace.activeWindow = others[others.length - 1];
        }
    } else {
        // Target not on top: minimize all others, bring target to front
        managed.forEach((client) => {
            if (client !== target) client.minimized = true;
        });
        // Pull the window to this desktop instead of switching to its own.
        // An empty list means the window is on all desktops.
        if (target.desktops.length && !target.desktops.includes(workspace.currentDesktop)) {
            target.desktops = [workspace.currentDesktop];
        }
        target.minimized = false;
        workspace.activeWindow = target;
    }
}

function applyConfig() {
    const updated = parseEntries(readConfig("Entries", "").toString());
    for (const id in selected) {
        if (!updated[id] || updated[id].resourceClass !== entries[id].resourceClass || updated[id].caption !== entries[id].caption) {
            delete selected[id];
        }
    }
    entries = updated;

    for (const id in registered) {
        if (!entries[id]) {
            // Entry deleted: free its key combo and drop it from the
            // Shortcuts page instead of leaving a dead binding behind.
            print(`Kwake: dropping shortcut ${id}`);
            unregisterShortcut(id);
            delete registered[id];
        }
    }

    for (const id in entries) {
        const shortcut = entries[id].shortcut;
        if (registered[id] === shortcut) continue;
        if (registered[id] !== undefined) {
            // Re-registering alone cannot change a live binding; dropping it
            // first makes the new sequence stick.
            unregisterShortcut(id);
        }
        registerShortcut(id, `Toggle ${entries[id].name}`, shortcut, () => toggleWindow(id));
        registered[id] = shortcut;
    }

    refreshTaskbarState();
    print(`Kwake: ${Object.keys(entries).length} applications configured`);
}

function stop() {
    // KWin shares the QML engine, so these signal callbacks outlive the root object.
    options.configChanged.disconnect(applyConfig);
    workspace.windowAdded.disconnect(windowAdded);
    workspace.windowRemoved.disconnect(forgetWindow);
    workspace.stackingOrder.forEach((win) => {
        win.captionChanged.disconnect(windowChanged);
        win.windowClassChanged.disconnect(windowChanged);
    });
    for (const key in hidden) {
        const win = hidden[key];
        if (win && !win.deleted) win.skipTaskbar = false;
    }
    hidden = {};
}

function start(host) {
    workspace = host.workspace;
    options = host.options;
    readConfig = host.readConfig;
    registerShortcut = host.registerShortcut;
    callDBus = host.callDBus;
    print = host.logMessage;

    applyConfig();
    workspace.stackingOrder.forEach(watchWindow);
    options.configChanged.connect(applyConfig);
    workspace.windowAdded.connect(windowAdded);
    workspace.windowRemoved.connect(forgetWindow);

    // Shortcuts orphaned by an earlier session (config edited while KWin was not
    // running, or a crash before applyConfig got to them).
    callDBus(
        KGA_SERVICE,
        "/component/kwin",
        "org.kde.kglobalaccel.Component",
        "shortcutNames",
        (names) => {
            names.forEach((name) => {
                if (name.startsWith(SHORTCUT_PREFIX) && !entries[name]) {
                    print(`Kwake: dropping orphaned shortcut ${name}`);
                    unregisterShortcut(name);
                }
            });
        }
    );
}
