// The one parser for kwinrc [Script-kwake] Entries, one application per line:
//     Name | resourceClass | caption | shortcut
// The KWin script, the settings form and the settings plugin all import it.

export function parseLine(line) {
    const fields = line.split("|").map((field) => field.trim());
    return {
        name: fields[0] ?? "",
        resourceClass: fields[1] ?? "",
        caption: fields[2] ?? "",
        // A shortcut on the | key contains the separator itself.
        shortcut: fields.slice(3).join("|"),
    };
}

export function parseLines(text) {
    return text.split("\n").map(parseLine);
}

export function formatLine(row) {
    return [row.name, row.resourceClass, row.caption, row.shortcut].join(" | ");
}

export const SHORTCUT_PREFIX = "kwake_";

// Anything else would break the kglobalshortcutsrc key.
export function shortcutId(name) {
    return SHORTCUT_PREFIX + name.replace(/[^A-Za-z0-9_-]/g, "_");
}

// The rows the script acts on, in order. A row needs a name and a class. A
// row whose id an earlier row took is ignored. A row whose shortcut an earlier
// row took is kept without one, since KGlobalAccel gives a key to one action.
export function parseEntries(text) {
    const entries = [];
    const ignored = [];
    const unbound = [];
    const byId = new Map();
    const byShortcut = new Map();
    for (const row of parseLines(text)) {
        if (!row.name || !row.resourceClass) continue;
        const id = shortcutId(row.name);
        const earlier = byId.get(id);
        if (earlier) {
            ignored.push({ name: row.name, takenBy: earlier.name });
            continue;
        }
        let shortcut = row.shortcut;
        const owner = shortcut ? byShortcut.get(shortcut) : undefined;
        if (owner) {
            unbound.push({ name: row.name, takenBy: owner.name });
            shortcut = "";
        }
        const entry = Object.assign({}, row, { id: id, shortcut: shortcut });
        byId.set(id, entry);
        if (shortcut) byShortcut.set(shortcut, entry);
        entries.push(entry);
    }
    return { entries, ignored, unbound };
}
