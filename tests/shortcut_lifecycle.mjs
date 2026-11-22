// Exhaustive interleaving check of the shortcut lifecycle.
//
// Runs the real script/contents/code/main.js and the real host functions of
// script/contents/ui/main.qml against a model of their environment: KWin's
// event loop, the kglobalaccel daemon, D-Bus queues, and KwakeKCM::save() in
// kcm/src/kcm.cpp. Every order in which those actors can take their next step
// is tried. See .claude/skills/verify-shortcut-lifecycle/SKILL.md.
//
//     node tests/shortcut_lifecycle.mjs [source root, default: this checkout]

import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { parseEntries } from "../script/contents/code/entries.mjs";

const root = path.resolve(process.argv[2] ?? new URL("..", import.meta.url).pathname);
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const mainJs = read("script/contents/code/main.js");
const mainQml = read("script/contents/ui/main.qml");
const kcmCpp = read("kcm/src/kcm.cpp");
const entriesPath = path.join(root, "script/contents/code/entries.mjs");
const Entries = fs.existsSync(entriesPath) ? await import(entriesPath) : undefined;

// KwakeKCM::save() either waits for each unregister or only queues it.
const kcmBlocks = /sessionBus\(\)\.call\(unregister, QDBus::Block/.test(kcmCpp);
if (!kcmBlocks && !/sessionBus\(\)\.send\(unregister\)/.test(kcmCpp)) {
    throw new Error("kcm.cpp no longer calls unregister in a way this model knows; update kcmSave() here");
}

// The QML functions main.js gets as its host, cut out of main.qml unchanged.
function qmlFunction(name) {
    const start = mainQml.indexOf(`function ${name}(`);
    if (start < 0) return "";
    let depth = 0;
    for (let i = mainQml.indexOf("{", start); i < mainQml.length; ++i) {
        if (mainQml[i] === "{") depth++;
        if (mainQml[i] === "}" && --depth === 0) return mainQml.slice(start, i + 1);
    }
    throw new Error(`unbalanced braces in main.qml ${name}()`);
}
const hostSource = ["registerShortcut", "destroyShortcut", "callDBus"].map(qmlFunction).join("\n");

const signal = () => {
    const callbacks = [];
    return {
        connect(f) { callbacks.push(f); },
        disconnect(f) { const i = callbacks.indexOf(f); if (i >= 0) callbacks.splice(i, 1); },
        emit(...args) { callbacks.slice().forEach((f) => f(...args)); },
    };
};

// One run of the system, driven by a list of choices. Returns the actions
// enabled at the end, or the final state when none is.
function run(scenario, choices) {
    const trace = [];
    // The bus daemon delivers to each destination in the order it received
    // the messages, so each destination reads one queue. KWin's own posted
    // events form another queue that it interleaves with D-Bus freely.
    const kwinPosted = [];
    const kwinBus = [];
    const daemonBus = [];
    const daemon = new Map(scenario.saved);
    const handlers = [];
    let configFile = scenario.initial;
    let kwinConfig = configFile;
    const kcm = { save: 0, unregisters: null, waiting: false };

    const post = (label, fn) => kwinPosted.push({ label, fn });
    const Qt = { callLater: (fn) => post("Qt.callLater callback", fn) };
    const shortcutComponent = {
        createObject(_parent, props) {
            const handler = {
                id: props.name, keys: props.sequence, alive: true,
                activated: signal(),
                Component: { destruction: signal() },
                destroy() {
                    post(`deferred delete of handler ${handler.id} (${handler.keys})`, () => {
                        handler.Component.destruction.emit();
                        handler.alive = false;
                        daemonBus.push({ op: "setInactive", id: handler.id, from: "kwin" });
                    });
                },
            };
            handlers.push(handler);
            daemonBus.push({ op: "register", id: handler.id, keys: handler.keys, from: "kwin" });
            return handler;
        },
    };
    const dbusComponent = {
        createObject(_parent, props) {
            const call = { finished: signal(), failed: signal(), destroy() {} };
            call.call = () => daemonBus.push({
                op: props.method, id: props.arguments[1], from: "kwin", reply: (value) => call.finished.emit([value]),
            });
            return call;
        },
    };
    const qml = new Function("root", "shortcutComponent", "dbusComponent", "Qt",
        `${hostSource}\nreturn { registerShortcut, destroyShortcut: typeof destroyShortcut === "function" ? destroyShortcut : undefined, callDBus };`);
    const script = vm.runInNewContext(`${mainJs}\n({ start, stop });`, {});
    const options = { configChanged: signal() };
    const host = Object.assign({}, qml(null, shortcutComponent, dbusComponent, Qt), {
        entries: Entries,
        workspace: { stackingOrder: [], activeWindow: null, windowAdded: signal(), windowRemoved: signal() },
        options,
        readConfig: (_key, fallback) => kwinConfig || fallback,
        logMessage: () => {},
    });
    script.start(host);

    const daemonStep = (message) => {
        const binding = daemon.get(message.id);
        if (message.op === "register") {
            // A saved binding wins over the keys an action registers with.
            daemon.set(message.id, { keys: binding ? binding.keys : message.keys, active: true });
        } else if (message.op === "setInactive") {
            if (binding) daemon.set(message.id, { keys: binding.keys, active: false });
        } else if (message.op === "unregister") {
            daemon.delete(message.id);
        } else if (message.op === "shortcutNames") {
            const names = [...daemon.keys()];
            kwinBus.push({ label: "shortcutNames reply", fn: () => message.reply(names) });
            return;
        }
        if (!message.reply) return;
        if (message.from === "kcm") message.reply();
        else kwinBus.push({ label: `${message.op}(${message.id}) reply`, fn: () => message.reply(true) });
    };

    const actions = () => {
        const enabled = [];
        if (kwinPosted.length) enabled.push("kwin posted");
        if (kwinBus.length) enabled.push("kwin bus");
        if (daemonBus.length) enabled.push("daemon");
        if (!kcm.waiting && kcm.save < scenario.saves.length) enabled.push("kcm");
        return enabled;
    };

    // KwakeKCM::save(): write kwinrc, unregister every changed shortcut, then
    // ask KWin to reconfigure.
    const kcmStep = () => {
        if (kcm.unregisters === null) {
            const shortcuts = (text) => new Map(parseEntries(text).entries.map((e) => [e.id, e.shortcut]));
            const before = shortcuts(configFile);
            const after = shortcuts(scenario.saves[kcm.save]);
            configFile = scenario.saves[kcm.save];
            kcm.unregisters = [...before].filter(([id, keys]) => after.get(id) !== keys).map(([id]) => id);
            trace.push(`  KCM writes kwinrc: ${JSON.stringify(configFile)}`);
        }
        if (kcmBlocks && kcm.unregisters.length) {
            const id = kcm.unregisters.shift();
            kcm.waiting = true;
            daemonBus.push({ op: "unregister", id, from: "kcm", reply: () => { kcm.waiting = false; } });
            trace.push(`  KCM calls unregister(${id}) and waits`);
            return;
        }
        for (const id of kcm.unregisters) {
            daemonBus.push({ op: "unregister", id, from: "kcm" });
            trace.push(`  KCM sends unregister(${id})`);
        }
        kwinBus.push({ label: "reconfigure from the KCM", fn: () => { kwinConfig = configFile; options.configChanged.emit(); } });
        trace.push("  KCM sends reconfigure");
        kcm.save++;
        kcm.unregisters = null;
    };

    const kwinTasks = [];
    for (const choice of choices) {
        if (choice === "kcm") {
            kcmStep();
        } else if (choice === "daemon") {
            const message = daemonBus.shift();
            trace.push(`  kglobalaccel handles ${message.op}(${message.id ?? ""}${message.keys ? ", " + message.keys : ""}) from ${message.from}`);
            daemonStep(message);
        } else {
            const task = (choice === "kwin posted" ? kwinPosted : kwinBus).shift();
            kwinTasks.push(task.label);
            trace.push(`  KWin runs ${task.label}`);
            task.fn();
        }
    }

    const describe = (m) => `${m.from}:${m.op}:${m.id ?? ""}:${m.keys ?? ""}`;
    const key = JSON.stringify([
        kwinTasks, [...daemon], kcm, configFile,
        kwinPosted.map((t) => t.label), kwinBus.map((t) => t.label), daemonBus.map(describe),
    ]);
    return { enabled: actions(), key, trace, daemon, handlers, kwinConfig };
}

// Once every queue is empty: each configured shortcut is bound to its keys and
// active, with exactly one handler behind it, and nothing else is left over.
function violations(state, scenario) {
    const found = [];
    const final = parseEntries(scenario.saves[scenario.saves.length - 1]).entries;
    for (const entry of final) {
        const binding = state.daemon.get(entry.id);
        if (!binding) found.push(`${entry.id} has no binding in kglobalaccel`);
        else if (binding.keys !== entry.shortcut) found.push(`${entry.id} is bound to ${binding.keys}, not ${entry.shortcut}`);
        else if (!binding.active) found.push(`${entry.id} is bound to ${binding.keys} but inactive, so the key does nothing`);
        const live = state.handlers.filter((h) => h.alive && h.id === entry.id).length;
        if (live !== 1) found.push(`${entry.id} has ${live} live handlers, so one key press toggles ${live} times`);
    }
    const ids = new Set(final.map((e) => e.id));
    for (const id of state.daemon.keys()) {
        if (!ids.has(id)) found.push(`${id} is still bound after its row was removed`);
    }
    for (const handler of state.handlers) {
        if (handler.alive && !ids.has(handler.id)) found.push(`handler ${handler.id} outlives its row`);
    }
    return found;
}

// Every distinct violation reachable in the scenario, each with the shortest
// trace found for it.
function explore(scenario) {
    const seen = new Set();
    const found = new Map();
    let finals = 0;
    const queue = [[]];
    while (queue.length) {
        const choices = queue.shift();
        const state = run(scenario, choices);
        if (seen.has(state.key)) continue;
        seen.add(state.key);
        if (!state.enabled.length) {
            finals++;
            for (const violation of violations(state, scenario)) {
                if (!found.has(violation)) found.set(violation, state.trace);
            }
            continue;
        }
        for (const action of state.enabled) queue.push([...choices, action]);
    }
    return { states: seen.size, finals, found };
}

const SCENARIOS = [
    {
        name: "change one shortcut and remove a row",
        saved: [["kwake_A", { keys: "Meta+1", active: false }], ["kwake_B", { keys: "Meta+2", active: false }]],
        initial: "A | a | | Meta+1\nB | b | | Meta+2",
        saves: ["A | a | | Meta+3"],
    },
    {
        name: "add a row",
        saved: [["kwake_A", { keys: "Meta+1", active: false }]],
        initial: "A | a | | Meta+1",
        saves: ["A | a | | Meta+1\nB | b | | Meta+2"],
    },
    {
        name: "two saves in a row",
        saved: [["kwake_A", { keys: "Meta+1", active: false }]],
        initial: "A | a | | Meta+1",
        saves: ["A | a | | Meta+2", "A | a | | Meta+3"],
    },
    {
        name: "remove a row and add it back",
        saved: [["kwake_A", { keys: "Meta+1", active: false }]],
        initial: "A | a | | Meta+1",
        saves: ["", "A | a | | Meta+1"],
    },
    {
        name: "change a shortcut and change it back",
        saved: [["kwake_A", { keys: "Meta+1", active: false }]],
        initial: "A | a | | Meta+1",
        saves: ["A | a | | Meta+2", "A | a | | Meta+1"],
    },
];

// Violations the current code has, found by this check and not fixed yet.
// The check fails when one of them goes away as well as when a new one
// appears, so a fix must also delete its line here.
const KNOWN = {
    // A replacement registers before an earlier handler's deferred delete
    // sends setInactive, when KWin handles two reloads before that delete.
    "two saves in a row": [
        "kwake_A is bound to Meta+3 but inactive, so the key does nothing",
    ],
    "remove a row and add it back": [
        "kwake_A is bound to Meta+1 but inactive, so the key does nothing",
        // The KCM unregisters a shortcut that the script, which reads only
        // the newest kwinrc, never sees change, so nothing registers it again.
        "kwake_A has no binding in kglobalaccel",
    ],
    "change a shortcut and change it back": [
        "kwake_A is bound to Meta+1 but inactive, so the key does nothing",
        "kwake_A has no binding in kglobalaccel",
    ],
};

let failed = false;
for (const scenario of SCENARIOS) {
    const { states, finals, found } = explore(scenario);
    const known = KNOWN[scenario.name] ?? [];
    for (const [violation, trace] of found) {
        if (known.includes(violation)) {
            console.log(`known ${scenario.name}: ${violation}`);
            continue;
        }
        failed = true;
        console.log(`FAIL ${scenario.name}: ${violation}`);
        console.log(`  starting from ${JSON.stringify(scenario.initial)}, after start():`);
        console.log(trace.join("\n"));
    }
    for (const violation of known) {
        if (found.has(violation)) continue;
        failed = true;
        console.log(`FAIL ${scenario.name}: known violation no longer happens, delete it from KNOWN: ${violation}`);
    }
    if (!found.size) console.log(`ok   ${scenario.name}: ${states} states, ${finals} end states`);
}
if (failed) process.exit(1);
