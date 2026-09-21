// Self-check for script/contents/code/main.js against a fake KWin. Run: node test_main.js
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

let config = "";
let configChanged;
const shortcuts = {};
const unregistered = [];
const win = (resourceClass, caption = "") => ({ resourceClass, caption, internalId: resourceClass + caption, minimized: false, skipTaskbar: false });
const term = win("com.mitchellh.ghostty");
const chat = win("vesktop");
const panel = Object.assign(win("plasmashell"), { skipTaskbar: true });
const workspace = {
    stackingOrder: [panel, term, chat],
    activeWindow: null,
    windowAdded: { connect() {} },
    windowRemoved: { connect() {} },
};

vm.runInNewContext(fs.readFileSync(__dirname + "/script/contents/code/main.js", "utf8"), {
    workspace,
    print() {},
    readConfig: () => config,
    registerShortcut: (id, label, keys, callback) => { shortcuts[id] = { keys, callback }; },
    callDBus: (...args) => { if (args[3] === "unregister") unregistered.push(args[5]); },
    options: { configChanged: { connect(f) { configChanged = f; } } },
});
const reload = (text) => { config = text; configChanged(); };

reload("Term | ghostty |  | Ctrl+`\nChat | vesktop |  | Alt+1");
assert.deepStrictEqual(Object.keys(shortcuts).sort(), ["kwake_Chat", "kwake_Term"]);
assert.ok(term.skipTaskbar && chat.skipTaskbar);

// Toggling raises the target and minimises the other managed window...
shortcuts.kwake_Term.callback();
assert.strictEqual(workspace.activeWindow, term);
assert.ok(chat.minimized && !term.minimized);
// ...and toggling it again while focused minimises it.
shortcuts.kwake_Term.callback();
assert.ok(term.minimized);

// Removing an app unregisters its shortcut and gives its window back to the
// taskbar, without touching windows that skip the taskbar on their own.
reload("Term | ghostty |  | Ctrl+`");
assert.deepStrictEqual(unregistered, ["kwake_Chat"]);
assert.ok(!chat.skipTaskbar && term.skipTaskbar && panel.skipTaskbar);

// Changing a shortcut drops the old binding first so the new one sticks.
reload("Term | ghostty |  | Meta+T");
assert.deepStrictEqual(unregistered, ["kwake_Chat", "kwake_Term"]);
assert.strictEqual(shortcuts.kwake_Term.keys, "Meta+T");

// No matching window is not an error.
reload("Gone | no-such-app |  | ");
shortcuts.kwake_Gone.callback();

console.log("main.js self-check passed");
