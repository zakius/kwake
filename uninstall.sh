#!/usr/bin/env bash
# Remove the Kwake KWin script, its settings page and its shortcuts.
set -euo pipefail

SCRIPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/kwake"
have() { command -v "$1" >/dev/null 2>&1; }

qdbus_cmd=""
for candidate in qdbus6 qdbus-qt6 qdbus; do
    if have "$candidate"; then qdbus_cmd="$candidate"; break; fi
done

# Emptying the config first lets the running script put its windows back on the
# taskbar and drop its own shortcuts, which it cannot do once unloaded.
if [[ -n "$qdbus_cmd" ]]; then
    echo "==> Releasing windows and shortcuts"
    kwriteconfig6 --file kwinrc --group Script-kwake --key Entries ""
    "$qdbus_cmd" org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
    sleep 2
fi

if [[ -n "$qdbus_cmd" ]]; then
    echo "==> Unloading the script"
    "$qdbus_cmd" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript kwake >/dev/null 2>&1 || true

    # Anything the script could not clean up itself, for instance after a crash.
    names=$("$qdbus_cmd" org.kde.kglobalaccel /component/kwin \
        org.kde.kglobalaccel.Component.shortcutNames 2>/dev/null | grep '^kwake_' || true)
    for name in $names; do
        echo "    dropping shortcut $name"
        "$qdbus_cmd" org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.unregister \
            kwin "$name" >/dev/null 2>&1 || true
    done
fi

echo "==> Removing files"
rm -rf "$SCRIPT_DIR"
for dir in "/usr/lib/$(uname -m)-linux-gnu/qt6/plugins" /usr/lib64/qt6/plugins /usr/lib/qt6/plugins; do
    plugin="$dir/kwin/effects/configs/kwake.so"
    if [[ -e "$plugin" ]]; then
        sudo rm -f "$plugin"
        echo "    removed $plugin"
    fi
done

kwriteconfig6 --file kwinrc --group Plugins --key kwakeEnabled --delete
kwriteconfig6 --file kwinrc --group Script-kwake --key Entries --delete

echo "Done."
