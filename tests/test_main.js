// Self-check for script/contents/code/main.js against a fake KWin. Run: node tests/test_main.js
// The scenarios run in order and share one set of windows.
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

let config = "";
let nextId = 0;
const messages = [];
const signal = () => {
    const callbacks = [];
    return {
        connect(f) { callbacks.push(f); },
        disconnect(f) { const index = callbacks.indexOf(f); assert.ok(index >= 0); callbacks.splice(index, 1); },
        emit(...args) { callbacks.slice().forEach(f => f(...args)); },
    };
};
const configSignal = signal();
const addedSignal = signal();
const removedSignal = signal();
const configChanged = () => configSignal.emit();
const windowAdded = win => addedSignal.emit(win);
const windowRemoved = win => removedSignal.emit(win);
const shortcuts = {};
const liveHandlers = new Set();
const shortcutEvents = [];
const unregistered = [];
let stackingReads = 0;
const win = (resourceClass, caption = "") => ({ resourceClass, caption, internalId: String(nextId++), normalWindow: true, dialog: false, minimizable: true, minimized: false, skipTaskbar: false, desktops: [], activities: [], captionChanged: signal(), windowClassChanged: signal() });
const term = win("com.mitchellh.ghostty");
const chat = win("vesktop");
const panel = Object.assign(win("plasmashell"), { skipTaskbar: true });
let stackingList = [panel, term, chat];
const workspace = {
    get stackingOrder() { stackingReads++; return stackingList; },
    set stackingOrder(list) { stackingList = list; },
    activeWindow: null,
    currentDesktop: "desktop 1",
    windowAdded: addedSignal,
    windowRemoved: removedSignal,
};

const runtime = vm.createContext({});
vm.runInContext(fs.readFileSync(__dirname + "/../script/contents/code/main.js", "utf8"), runtime);
let deferDestroy = false;
const deferred = [];
const flushDeferred = () => { while (deferred.length) deferred.shift()(); };
runtime.start({
    workspace,
    logMessage: message => messages.push(message),
    readConfig: () => config,
    registerShortcut: (id, label, keys, callback) => {
        const handler = { id, label, keys, callback, destroyed: false };
        liveHandlers.add(handler);
        shortcuts[id] = handler;
        shortcutEvents.push(`register:${id}:${keys}`);
        return handler;
    },
    destroyShortcut: (handler, done) => {
        const run = () => {
            if (handler) {
                assert.ok(!handler.destroyed, "handler destroyed twice");
                handler.destroyed = true;
                liveHandlers.delete(handler);
                shortcutEvents.push(`destroy:${handler.id}:${handler.keys}`);
            }
            if (done) done();
        };
        if (deferDestroy) deferred.push(run);
        else run();
    },
    callDBus: (...args) => {
        const callback = typeof args[args.length - 1] === "function" ? args.pop() : null;
        if (args[3] === "unregister") {
            unregistered.push(args[5]);
            shortcutEvents.push(`unregister:${args[5]}`);
            if (callback) callback(true);
        }
    },
    options: { configChanged: configSignal },
});
const reload = (text) => { config = text; configChanged(); };

reload("Term | com.mitchellh.ghostty |  | Ctrl+`\nChat | vesktop |  | Alt+1");
assert.deepStrictEqual(Object.keys(shortcuts).sort(), ["kwake_Chat", "kwake_Term"]);
assert.ok(term.skipTaskbar && chat.skipTaskbar);

// Toggling raises the target and minimises the other managed window...
shortcuts.kwake_Term.callback();
assert.strictEqual(workspace.activeWindow, term);
assert.ok(chat.minimized && !term.minimized);
// ...and toggling it again while focused minimises it. KWin chooses the next
// focused window. So that it cannot choose a managed one, a managed window
// that was brought back up by hand is minimised too.
chat.minimized = false;
shortcuts.kwake_Term.callback();
assert.ok(term.minimized && chat.minimized);
assert.strictEqual(workspace.activeWindow, term);

// Managed windows are kept on all virtual desktops and all activities.
term.desktops = ["desktop 2"];
term.activities = ["activity 2"];
workspace.activeWindow = null;
shortcuts.kwake_Term.callback();
assert.deepStrictEqual([...term.desktops], []);
assert.deepStrictEqual([...term.activities], []);
assert.deepStrictEqual(chat.desktops, []);
assert.deepStrictEqual(chat.activities, []);

// Switching from one focused managed window to another activates the target
// BEFORE minimising the previous one, so KWin never bounces focus elsewhere.
const switchLog = [];
const origActiveDesc = Object.getOwnPropertyDescriptor(workspace, "activeWindow");
let activeWinRef = chat;
Object.defineProperty(workspace, "activeWindow", {
    configurable: true,
    get() { return activeWinRef; },
    set(w) { activeWinRef = w; switchLog.push(`activate:${w.resourceClass}`); },
});
let chatMinimized = false;
Object.defineProperty(chat, "minimized", {
    configurable: true,
    get() { return chatMinimized; },
    set(v) { chatMinimized = v; if (v) switchLog.push("minimize:vesktop"); },
});
term.minimized = true;
shortcuts.kwake_Term.callback();
assert.deepStrictEqual(switchLog, ["activate:com.mitchellh.ghostty", "minimize:vesktop"]);
Object.defineProperty(workspace, "activeWindow", origActiveDesc);
workspace.activeWindow = term;
delete chat.minimized;
chat.minimized = true;
shortcuts.kwake_Term.callback();

// Removing an app unregisters its shortcut and gives its window back to the
// taskbar, without touching windows that skip the taskbar on their own.
reload("Term | com.mitchellh.ghostty |  | Ctrl+`");
assert.deepStrictEqual(unregistered, ["kwake_Chat"]);
assert.ok(!chat.skipTaskbar && term.skipTaskbar && panel.skipTaskbar);

// Changing a shortcut destroys the old handler and drops the old binding before
// registering the new one, leaving no leaked ShortcutHandlers behind.
shortcutEvents.length = 0;
reload("Term | com.mitchellh.ghostty |  | Meta+T");
assert.deepStrictEqual(unregistered, ["kwake_Chat", "kwake_Term"]);
assert.strictEqual(shortcuts.kwake_Term.keys, "Meta+T");
assert.deepStrictEqual(shortcutEvents, [
    "destroy:kwake_Term:Ctrl+`",
    "unregister:kwake_Term",
    "register:kwake_Term:Meta+T",
]);
assert.strictEqual(liveHandlers.size, 1);

// Rapid reloads while an async destroy is pending cancel the stale replacement.
deferDestroy = true;
shortcutEvents.length = 0;
reload("Term | com.mitchellh.ghostty |  | Meta+1");
reload("Term | com.mitchellh.ghostty |  | Meta+2");
flushDeferred();
deferDestroy = false;
assert.strictEqual(shortcuts.kwake_Term.keys, "Meta+2");
assert.strictEqual(liveHandlers.size, 1);
assert.strictEqual(shortcutEvents.filter(e => e.startsWith("register:")).length, 1);

// A shortcut whose application is not running does nothing and logs nothing.
reload("Gone | no-such-app |  | ");
const before = messages.length;
shortcuts.kwake_Gone.callback();
assert.strictEqual(messages.length, before);

// A row without a window class is ignored: no shortcut, no hidden windows.
reload("Incomplete | | | Meta+X");
assert.ok(!term.skipTaskbar && !chat.skipTaskbar);
assert.ok(!shortcuts.kwake_Incomplete);
// The class must match in full, not in part.
reload("Partial | ghostty | | Meta+X");
assert.ok(!term.skipTaskbar);
// A line starting with # is a row like any other, not a comment.
reload("#Term | com.mitchellh.ghostty | | Meta+X");
assert.ok(term.skipTaskbar);

// Of several matching windows, a row takes the focused one and leaves the
// others alone, also when another one has focus later.
const first = win("example", "Document A");
const second = win("example", "Document B");
workspace.stackingOrder.push(first, second);
windowAdded(first);
windowAdded(second);
workspace.activeWindow = first;
reload("Example | EXAMPLE | Document | Meta+E");
assert.ok(first.skipTaskbar && !second.skipTaskbar);
workspace.activeWindow = second;
workspace.stackingOrder = [panel, term, chat, second, first];
shortcuts.kwake_Example.callback();
assert.strictEqual(workspace.activeWindow, first);
assert.ok(!second.minimized && !second.skipTaskbar);

// The row keeps its window when the title stops matching the filter.
first.caption = "Unrelated title";
first.captionChanged.emit();
configChanged();
shortcuts.kwake_Example.callback();
assert.ok(first.minimized && first.skipTaskbar);
assert.ok(!second.skipTaskbar);

// When its window closes, the row picks the next match, or none.
workspace.stackingOrder = workspace.stackingOrder.filter(w => w !== first);
windowRemoved(first);
assert.ok(second.skipTaskbar);
workspace.activeWindow = null;
shortcuts.kwake_Example.callback();
assert.strictEqual(workspace.activeWindow, second);
workspace.stackingOrder = workspace.stackingOrder.filter(w => w !== second);
windowRemoved(second);
const emptyMessages = messages.length;
shortcuts.kwake_Example.callback();
assert.strictEqual(messages.length, emptyMessages);

// A new window is picked up once its title matches the filter.
const replacement = win("example", "Loading");
workspace.stackingOrder.push(replacement);
windowAdded(replacement);
assert.ok(!replacement.skipTaskbar);
replacement.caption = "Document C";
replacement.captionChanged.emit();
assert.ok(replacement.skipTaskbar);

// With no matching window focused, a row takes the topmost match. Changing
// the row's title filter makes it pick again.
reload("");
assert.ok(!replacement.skipTaskbar);
const topmost = win("example", "Document D");
workspace.stackingOrder.push(topmost);
windowAdded(topmost);
workspace.activeWindow = chat;
reload("Example | example | Document | Meta+E");
assert.ok(topmost.skipTaskbar && !replacement.skipTaskbar);
reload("Example | example | Document C | Meta+E");
assert.ok(replacement.skipTaskbar && !topmost.skipTaskbar);

// The | key in a shortcut is not a field separator.
reload("Pipe | vesktop |  | Ctrl+|");
assert.strictEqual(shortcuts.kwake_Pipe.keys, "Ctrl+|");

// Only the first row with a shortcut gets it. The second is registered without
// one, so its window stays on the taskbar.
reload("Term | com.mitchellh.ghostty | | Meta+D\nChat | vesktop | | Meta+D");
assert.strictEqual(shortcuts.kwake_Term.keys, "Meta+D");
assert.strictEqual(shortcuts.kwake_Chat.keys, "");
assert.ok(term.skipTaskbar && !chat.skipTaskbar);

// A window that skips the taskbar on its own is never given back to it.
const alreadyHidden = win("private");
alreadyHidden.skipTaskbar = true;
workspace.stackingOrder.push(alreadyHidden);
windowAdded(alreadyHidden);
reload("Private | private | | Meta+P");
reload("");
assert.ok(alreadyHidden.skipTaskbar && panel.skipTaskbar);

// An unbound row stays on the taskbar but remains toggleable if its action is
// assigned a shortcut in KDE's global shortcuts editor.
reload("Unbound | example | Document C | ");
assert.ok(!replacement.skipTaskbar);
workspace.activeWindow = null;
shortcuts.kwake_Unbound.callback();
assert.strictEqual(workspace.activeWindow, replacement);

reload("Unbound | example | Document C | \nBound | example | Document C | Meta+B");
assert.ok(replacement.skipTaskbar);
reload("Unbound | example | Document C | \nBound | example | Document C | ");
assert.ok(!replacement.skipTaskbar);

reload("Private | private | | Meta+P");
reload("Private | private | | ");
assert.ok(alreadyHidden.skipTaskbar);

// Two entries of the same class (generic + caption-filtered, or two generic)
// claim distinct windows instead of fighting over the same one.
const browserDocs = win("firefox", "Docs");
const browserMusic = win("firefox", "YouTube Music");
workspace.stackingOrder.push(browserDocs, browserMusic);
windowAdded(browserDocs);
windowAdded(browserMusic);
workspace.activeWindow = browserMusic;
reload("Browser | firefox | | Meta+1\nMusic | firefox | YouTube Music | Meta+2");
assert.ok(browserDocs.skipTaskbar && browserMusic.skipTaskbar);
shortcuts.kwake_Browser.callback();
assert.strictEqual(workspace.activeWindow, browserDocs);
shortcuts.kwake_Music.callback();
assert.strictEqual(workspace.activeWindow, browserMusic);

// A normal window is preferred over a focused transient dialog of the same class.
const appMain = win("editor", "main.cpp");
const appDialog = Object.assign(win("editor", "Save As"), { normalWindow: false, dialog: true, minimizable: false });
workspace.stackingOrder.push(appMain, appDialog);
windowAdded(appMain);
windowAdded(appDialog);
workspace.activeWindow = appDialog;
reload("Editor | editor | | Meta+3");
assert.ok(appMain.skipTaskbar && !appDialog.skipTaskbar);

// Unrelated title updates do not touch workspace.stackingOrder at all.
const readsBefore = stackingReads;
term.caption = "prompt 1";
term.captionChanged.emit();
browserDocs.caption = "Docs (modified)";
browserDocs.captionChanged.emit();
assert.strictEqual(stackingReads, readsBefore);

// Closing a window disconnects its listeners immediately, and stop() disconnects
// watched windows even if they are no longer in workspace.stackingOrder.
const orphanWin = win("orphan", "temp");
workspace.stackingOrder.push(orphanWin);
windowAdded(orphanWin);
workspace.stackingOrder = workspace.stackingOrder.filter(w => w !== orphanWin);
// orphanWin is still watched (not removed via windowRemoved) and not in stackingOrder.

// Stopping gives back the windows Kwake hid and disconnects every signal.
reload("Term | com.mitchellh.ghostty | | Meta+T\nPrivate | private | | Meta+P");
assert.ok(term.skipTaskbar && alreadyHidden.skipTaskbar);
runtime.stop();
assert.ok(!term.skipTaskbar && alreadyHidden.skipTaskbar && panel.skipTaskbar);
configChanged();
term.captionChanged.emit();
orphanWin.captionChanged.emit();
windowAdded(win("com.mitchellh.ghostty"));
assert.ok(!term.skipTaskbar);

console.log("main.js self-check passed");
