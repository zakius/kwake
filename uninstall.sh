#!/usr/bin/env bash
# Remove the per-user Kwake KWin script and its shortcuts.
set -euo pipefail

SCRIPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/kwake"
have() { command -v "$1" >/dev/null 2>&1; }
REMOVE_SYSTEM_PLUGIN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove-system-plugin) REMOVE_SYSTEM_PLUGIN=1; shift ;;
        -h|--help) echo "Usage: $0 [--remove-system-plugin]"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

qdbus_cmd=""
for candidate in qdbus6 qdbus-qt6 qdbus; do
    if have "$candidate"; then qdbus_cmd="$candidate"; break; fi
done

# Kwake 3.1 and earlier need empty config to restore taskbar state before unload.
# Clearing entries also drops shortcut registrations before removing the script.
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

echo "==> Removing per-user files"
rm -rf "$SCRIPT_DIR"
if [[ $REMOVE_SYSTEM_PLUGIN -eq 1 ]]; then
    echo "==> Removing the shared settings page"
    for dir in "/usr/lib/$(uname -m)-linux-gnu/qt6/plugins" /usr/lib64/qt6/plugins /usr/lib/qt6/plugins; do
        plugin="$dir/kwin/effects/configs/kwake.so"
        if [[ -e "$plugin" ]]; then
            sudo rm -f "$plugin"
            echo "    removed $plugin"
        fi
    done
fi

kwriteconfig6 --file kwinrc --group Plugins --key kwakeEnabled --delete
kwriteconfig6 --file kwinrc --group Script-kwake --key Entries --delete

if [[ $REMOVE_SYSTEM_PLUGIN -eq 1 ]]; then
    echo "Done."
else
    echo "Done. The shared settings page remains installed; pass --remove-system-plugin to remove it."
fi
