// Kwake - applications are configured in the script's System Settings page.
// Storage is one line per application in kwinrc [Script-kwake] Entries:
//     Name | resourceClass | caption | shortcut
// resourceClass and caption are case-insensitive substring matches; both optional.

const SHORTCUT_PREFIX = "kwake_";
const KGA_SERVICE = "org.kde.kglobalaccel";

// id -> entry, for every application currently configured.
let entries = {};
// id -> the key sequence we last passed to registerShortcut.
let registered = {};
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
        if (!name) return;
        // Anything else would break the kglobalshortcutsrc key.
        const id = SHORTCUT_PREFIX + name.replace(/[^A-Za-z0-9_-]/g, "_");
        if (parsed[id]) return;

        parsed[id] = {
            name: name,
            id: id,
            resourceClass: f[1] || "",
            caption: f[2] || "",
            shortcut: f[3] || "",
        };
    });
    return parsed;
}

function unregisterShortcut(id) {
    callDBus(KGA_SERVICE, "/kglobalaccel", "org.kde.KGlobalAccel", "unregister", "kwin", id);
}

function windowMatches(win, entry) {
    const classOk =
        !entry.resourceClass ||
        win.resourceClass.toLowerCase().includes(entry.resourceClass.toLowerCase());
    const capOk =
        !entry.caption ||
        win.caption.toLowerCase().includes(entry.caption.toLowerCase());
    return classOk && capOk;
}

function isManaged(win) {
    return Object.values(entries).some((entry) => windowMatches(win, entry));
}

// KWin 6: stackingOrder replaces clientList
function findWindow(entry) {
    return workspace.stackingOrder.find((win) => windowMatches(win, entry));
}

function trackWindow(win) {
    if (!isManaged(win)) return;
    win.skipTaskbar = true;
    hidden[win.internalId] = win;
}

function forgetWindow(win) {
    delete hidden[win.internalId];
}

// Give back to the taskbar any window whose application is no longer configured.
function refreshTaskbarState() {
    for (const key in hidden) {
        const win = hidden[key];
        if (!isManaged(win)) {
            win.skipTaskbar = false;
            delete hidden[key];
        }
    }
    workspace.stackingOrder.forEach(trackWindow);
}

function getManagedWindows() {
    return Object.values(entries).map(findWindow).filter(Boolean);
}

// Toggle windows: bring target to top, minimize others
function toggleWindow(id) {
    const entry = entries[id];
    if (!entry) return; // removed from the config since this shortcut was bound

    let target = findWindow(entry);
    if (!target) {
        print(`No window found for ${entry.name}`);
        return;
    }

    let managed = getManagedWindows();
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
        target.minimized = false;
        workspace.activeWindow = target;
    }
}

function applyConfig() {
    entries = parseEntries(readConfig("Entries", "").toString());

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

applyConfig();
options.configChanged.connect(applyConfig);
workspace.windowAdded.connect(trackWindow);
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
