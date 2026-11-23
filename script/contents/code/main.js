const KGA_SERVICE = "org.kde.kglobalaccel";
let Entries;
let workspace;
let options;
let readConfig;
let registerShortcut;
let destroyShortcut;
let callDBus;
let log;

let stopped = false;
// id -> entry, for every application currently configured.
let entries = Object.create(null);
// id -> { shortcut, name } we last registered (or queued for registration).
let registered = Object.create(null);
// id -> live ShortcutHandler QML object, so replaced/removed handlers can be
// destroyed instead of leaking QActions inside KGlobalAccel.
let handlers = Object.create(null);
// id -> generation counter cancelling stale async unregister/re-register chains.
let pending = Object.create(null);
// id -> callbacks waiting for the handler being destroyed to send setInactive.
let dying = Object.create(null);
// Entry id -> window UUID. A selected window keeps its identity as its title changes.
let selected = Object.create(null);
// internalId -> window, for the windows this script took off the taskbar. Only
// these get restored, so windows that asked to skip the taskbar themselves
// (panels, splashes) are never dragged back into it.
let hidden = Object.create(null);
// Window -> { onCaption, onClass } for exact disconnect on close and stop().
let watched = new Map();

function readEntries() {
    const byId = Object.create(null);
    for (const entry of Entries.parseEntries(readConfig("Entries", "").toString()).entries) {
        byId[entry.id] = Object.assign({}, entry, {
            resourceClassLower: entry.resourceClass.toLowerCase(),
            captionLower: entry.caption.toLowerCase(),
        });
    }
    return byId;
}

function unregisterShortcut(id, done) {
    if (done) {
        callDBus(KGA_SERVICE, "/kglobalaccel", "org.kde.KGlobalAccel", "unregister", "kwin", id, () => done());
    } else {
        callDBus(KGA_SERVICE, "/kglobalaccel", "org.kde.KGlobalAccel", "unregister", "kwin", id);
    }
}

// Runs done once no handler of id is left to send setInactive, which would
// switch off a replacement registered before it.
function afterHandlerGone(id, done) {
    const handler = handlers[id];
    delete handlers[id];
    if (handler) {
        dying[id] = [done];
        destroyShortcut(handler, () => {
            const waiting = dying[id];
            delete dying[id];
            waiting.forEach((f) => f());
        });
    } else if (dying[id]) {
        dying[id].push(done);
    } else {
        done();
    }
}

function isManageableWindow(win) {
    return Boolean(win && !win.deleted && (win.normalWindow || win.dialog));
}

function windowMatches(win, entry) {
    if (!isManageableWindow(win)) return false;
    if (win.resourceClass.toLowerCase() !== entry.resourceClassLower) return false;
    return !entry.captionLower || win.caption.toLowerCase().includes(entry.captionLower);
}

function findWindow(entry, windows, claimed) {
    const matches = windows.filter((win) => windowMatches(win, entry));
    if (!matches.length) {
        delete selected[entry.id];
        return undefined;
    }
    // Prefer normal application windows over transient/helper dialogs, and
    // minimizable windows over non-minimizable ones.
    const normal = matches.filter((win) => win.normalWindow);
    const byType = normal.length ? normal : matches;
    const minimizable = byType.filter((win) => win.minimizable !== false);
    const preferred = minimizable.length ? minimizable : byType;
    // Avoid two entries latching onto the same window when distinct matches exist.
    const unclaimed = claimed
        ? preferred.filter((win) => !claimed.has(String(win.internalId)))
        : preferred;
    const pool = unclaimed.length ? unclaimed : preferred;
    const target = pool.find((win) => win === workspace.activeWindow) || pool[pool.length - 1];
    if (target) {
        const id = String(target.internalId);
        selected[entry.id] = id;
        if (claimed) claimed.add(id);
    } else {
        delete selected[entry.id];
    }
    return target;
}

function watchWindow(win) {
    if (stopped || !isManageableWindow(win) || watched.has(win)) return;
    const onCaption = () => windowCaptionChanged(win);
    const onClass = () => windowClassChanged(win);
    win.captionChanged.connect(onCaption);
    win.windowClassChanged.connect(onClass);
    watched.set(win, { onCaption, onClass });
}

function unwatchWindow(win) {
    const listeners = watched.get(win);
    if (!listeners) return;
    win.captionChanged.disconnect(listeners.onCaption);
    win.windowClassChanged.disconnect(listeners.onClass);
    watched.delete(win);
}

function forgetWindow(win) {
    unwatchWindow(win);
    delete hidden[win.internalId];
    refreshTaskbarState(win);
}

function refreshTaskbarState(removed) {
    if (stopped) return [];
    const windows = workspace.stackingOrder.filter((win) => win !== removed && !win.deleted);
    const windowsById = new Map();
    const liveWindows = new Set();
    for (const win of windows) {
        windowsById.set(String(win.internalId), win);
        liveWindows.add(win);
    }

    const claimed = new Set();
    const resolved = new Map();
    const unmatched = [];
    // Pass 1: retain still-living selections so their IDs are claimed first.
    for (const id in entries) {
        const retainedId = selected[id];
        const retained = retainedId ? windowsById.get(retainedId) : undefined;
        if (retained) {
            resolved.set(id, retained);
            claimed.add(retainedId);
        } else {
            unmatched.push(entries[id]);
        }
    }
    // Pass 2: match caption-filtered entries before generic class-only entries
    // so a specific row claims its window before a catch-all row of the same class.
    unmatched.sort((a, b) => (b.captionLower ? 1 : 0) - (a.captionLower ? 1 : 0));
    for (const entry of unmatched) {
        const win = findWindow(entry, windows, claimed);
        if (win) resolved.set(entry.id, win);
    }

    const taskbarWindows = new Set();
    const managed = [];
    for (const id in entries) {
        const win = resolved.get(id);
        if (!win) continue;
        // Quake windows should not be bound to any virtual desktop or activity.
        // Empty lists mean all desktops / all activities in KWin.
        if (win.desktops && win.desktops.length) win.desktops = [];
        if (win.activities && win.activities.length) win.activities = [];
        managed.push(win);
        if (entries[id].shortcut) taskbarWindows.add(win);
    }

    for (const key in hidden) {
        const win = hidden[key];
        if (!taskbarWindows.has(win)) {
            if (liveWindows.has(win)) win.skipTaskbar = false;
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

function windowCaptionChanged(win) {
    if (stopped || !isManageableWindow(win)) return;
    let winClassLower = null;
    let winCaptionLower = null;
    for (const id in entries) {
        if (selected[id]) continue;
        const entry = entries[id];
        if (!entry.captionLower) continue;
        if (winClassLower === null) winClassLower = win.resourceClass.toLowerCase();
        if (winClassLower !== entry.resourceClassLower) continue;
        if (winCaptionLower === null) winCaptionLower = win.caption.toLowerCase();
        if (winCaptionLower.includes(entry.captionLower)) {
            refreshTaskbarState();
            return;
        }
    }
}

function windowClassChanged(win) {
    if (stopped || !isManageableWindow(win)) return;
    let winClassLower = null;
    for (const id in entries) {
        if (selected[id]) continue;
        if (winClassLower === null) winClassLower = win.resourceClass.toLowerCase();
        if (entries[id].resourceClassLower === winClassLower) {
            refreshTaskbarState();
            return;
        }
    }
}

function windowAdded(win) {
    if (stopped || !isManageableWindow(win)) return;
    watchWindow(win);
    let winClassLower = null;
    for (const id in entries) {
        if (selected[id]) continue;
        if (winClassLower === null) winClassLower = win.resourceClass.toLowerCase();
        if (entries[id].resourceClassLower === winClassLower) {
            refreshTaskbarState();
            return;
        }
    }
}

// Minimise the target if it has focus; otherwise raise it. Either way the other
// managed windows are minimised, so at most one of them shows at a time.
function toggleWindow(id) {
    if (stopped) return;
    const entry = entries[id];
    if (!entry) return; // removed from the config since this shortcut was bound

    const managed = refreshTaskbarState();
    const target = managed.find((win) => String(win.internalId) === selected[id]);
    if (!target) return;

    if (workspace.activeWindow === target) {
        // Minimise other managed windows first so KWin gives focus to the most
        // recently used window outside the list when target minimises.
        managed.forEach((win) => {
            if (win !== target) win.minimized = true;
        });
        target.minimized = true;
    } else {
        // Activate target before minimising other managed windows so KWin does
        // not bounce focus through an unrelated background window in between.
        target.minimized = false;
        workspace.activeWindow = target;
        managed.forEach((win) => {
            if (win !== target) win.minimized = true;
        });
    }
}

function applyConfig() {
    if (stopped) return;
    const updated = readEntries();
    // Every id in selected is also in entries: findWindow only adds ids of
    // current entries, and this loop drops the ones that go away.
    for (const id in selected) {
        if (!updated[id] || updated[id].resourceClass !== entries[id].resourceClass || updated[id].caption !== entries[id].caption) {
            delete selected[id];
        }
    }
    entries = updated;

    for (const id in registered) {
        if (!entries[id]) {
            // Entry deleted: destroy the old ShortcutHandler so KGlobalAccel
            // drops its QAction, then free its key combo from the Shortcuts page.
            log(`Kwake: dropping shortcut ${id}`);
            const gen = (pending[id] = (pending[id] || 0) + 1);
            delete registered[id];
            afterHandlerGone(id, () => {
                if (!stopped && pending[id] === gen) {
                    unregisterShortcut(id);
                }
            });
        }
    }

    for (const id in entries) {
        const entry = entries[id];
        const shortcut = entry.shortcut;
        const label = `Toggle ${entry.name}`;
        const prev = registered[id];
        if (prev && prev.shortcut === shortcut && prev.name === entry.name) continue;

        if (prev === undefined && !handlers[id] && !pending[id]) {
            handlers[id] = registerShortcut(id, label, shortcut, () => toggleWindow(id));
            registered[id] = { shortcut, name: entry.name };
            continue;
        }

        // Destroy the old ShortcutHandler and wait for its QAction to be gone
        // and unregistered from KGlobalAccel before creating the replacement,
        // avoiding leaked QActions and setInactive/unregister races.
        const gen = (pending[id] = (pending[id] || 0) + 1);
        registered[id] = { shortcut, name: entry.name };
        afterHandlerGone(id, () => {
            if (stopped || pending[id] !== gen) return;
            unregisterShortcut(id, () => {
                if (stopped || pending[id] !== gen) return;
                handlers[id] = registerShortcut(id, label, shortcut, () => toggleWindow(id));
            });
        });
    }

    refreshTaskbarState();
    log(`Kwake: ${Object.keys(entries).length} applications configured`);
}

function stop() {
    if (stopped) return;
    stopped = true;
    // KWin shares the QML engine, so these signal callbacks outlive the root object.
    options.configChanged.disconnect(applyConfig);
    workspace.windowAdded.disconnect(windowAdded);
    workspace.windowRemoved.disconnect(forgetWindow);
    for (const win of Array.from(watched.keys())) {
        unwatchWindow(win);
    }
    for (const key in hidden) {
        const win = hidden[key];
        if (win && !win.deleted) win.skipTaskbar = false;
    }
    hidden = Object.create(null);
    entries = Object.create(null);
    registered = Object.create(null);
    handlers = Object.create(null);
    pending = Object.create(null);
    dying = Object.create(null);
    selected = Object.create(null);
}

function start(host) {
    stopped = false;
    Entries = host.entries;
    workspace = host.workspace;
    options = host.options;
    readConfig = host.readConfig;
    registerShortcut = host.registerShortcut;
    destroyShortcut = host.destroyShortcut;
    callDBus = host.callDBus;
    log = host.logMessage;

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
            if (stopped || !Array.isArray(names)) return;
            names.forEach((name) => {
                if (name.startsWith(Entries.SHORTCUT_PREFIX) && !entries[name]) {
                    log(`Kwake: dropping orphaned shortcut ${name}`);
                    unregisterShortcut(name);
                }
            });
        }
    );
}
