// Self-check for script/contents/code/main.js against a fake KWin. Run: node test_main.js
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
const unregistered = [];
const win = (resourceClass, caption = "") => ({ resourceClass, caption, internalId: String(nextId++), normalWindow: true, minimized: false, skipTaskbar: false, desktops: [], captionChanged: signal(), windowClassChanged: signal() });
const term = win("com.mitchellh.ghostty");
const chat = win("vesktop");
const panel = Object.assign(win("plasmashell"), { skipTaskbar: true });
const workspace = {
    stackingOrder: [panel, term, chat],
    activeWindow: null,
    currentDesktop: "desktop 1",
    windowAdded: addedSignal,
    windowRemoved: removedSignal,
};

const runtime = vm.createContext({});
vm.runInContext(fs.readFileSync(__dirname + "/script/contents/code/main.js", "utf8"), runtime);
runtime.start({
    workspace,
    logMessage: message => messages.push(message),
    readConfig: () => config,
    registerShortcut: (id, label, keys, callback) => { shortcuts[id] = { keys, callback }; },
    callDBus: (...args) => { if (args[3] === "unregister") unregistered.push(args[5]); },
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
// ...and toggling it again while focused minimises it.
shortcuts.kwake_Term.callback();
assert.ok(term.minimized);

// A window on another desktop is pulled to this one; all-desktop windows stay put.
term.desktops = ["desktop 2"];
workspace.activeWindow = null;
shortcuts.kwake_Term.callback();
assert.deepStrictEqual([...term.desktops], ["desktop 1"]);
assert.deepStrictEqual(chat.desktops, []);
shortcuts.kwake_Term.callback();

// Removing an app unregisters its shortcut and gives its window back to the
// taskbar, without touching windows that skip the taskbar on their own.
reload("Term | com.mitchellh.ghostty |  | Ctrl+`");
assert.deepStrictEqual(unregistered, ["kwake_Chat"]);
assert.ok(!chat.skipTaskbar && term.skipTaskbar && panel.skipTaskbar);

// Changing a shortcut drops the old binding first so the new one sticks.
reload("Term | com.mitchellh.ghostty |  | Meta+T");
assert.deepStrictEqual(unregistered, ["kwake_Chat", "kwake_Term"]);
assert.strictEqual(shortcuts.kwake_Term.keys, "Meta+T");

// No matching window is not an error.
reload("Gone | no-such-app |  | ");
shortcuts.kwake_Gone.callback();

const before = messages.length;
shortcuts.kwake_Gone.callback();
assert.strictEqual(messages.length, before);

reload("Incomplete | | | Meta+X");
assert.ok(!term.skipTaskbar && !chat.skipTaskbar);
assert.ok(!shortcuts.kwake_Incomplete);
reload("Partial | ghostty | | Meta+X");
assert.ok(!term.skipTaskbar);

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

first.caption = "Unrelated title";
first.captionChanged.emit();
configChanged();
shortcuts.kwake_Example.callback();
assert.ok(first.minimized && first.skipTaskbar);
assert.ok(!second.skipTaskbar);

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

const replacement = win("example", "Loading");
workspace.stackingOrder.push(replacement);
windowAdded(replacement);
assert.ok(!replacement.skipTaskbar);
replacement.caption = "Document C";
replacement.captionChanged.emit();
assert.ok(replacement.skipTaskbar);

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

reload("Term | com.mitchellh.ghostty | | Meta+T\nPrivate | private | | Meta+P");
assert.ok(term.skipTaskbar && alreadyHidden.skipTaskbar);
runtime.stop();
assert.ok(!term.skipTaskbar && alreadyHidden.skipTaskbar && panel.skipTaskbar);
configChanged();
term.captionChanged.emit();
windowAdded(win("com.mitchellh.ghostty"));
assert.ok(!term.skipTaskbar);

console.log("main.js self-check passed");
