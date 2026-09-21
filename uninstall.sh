#!/usr/bin/env bash
# Remove the Toggle Windows KWin script, its settings page and its shortcuts.
set -euo pipefail

SCRIPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/toggle_windows"
PREFIX="/usr"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        -h|--help) echo "Usage: $0 [--prefix DIR]"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

have() { command -v "$1" >/dev/null 2>&1; }

qdbus_cmd=""
for candidate in qdbus6 qdbus-qt6 qdbus; do
    if have "$candidate"; then qdbus_cmd="$candidate"; break; fi
done

# Emptying the config first lets the running script put its windows back on the
# taskbar and drop its own shortcuts, which it cannot do once unloaded.
if have kwriteconfig6 && [[ -n "$qdbus_cmd" ]]; then
    echo "==> Releasing windows and shortcuts"
    kwriteconfig6 --file kwinrc --group Script-toggle_windows --key Entries ""
    "$qdbus_cmd" org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
    sleep 2
fi

if [[ -n "$qdbus_cmd" ]]; then
    echo "==> Unloading the script"
    "$qdbus_cmd" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript toggle_windows >/dev/null 2>&1 || true

    # Anything the script could not clean up itself, for instance after a crash.
    names=$("$qdbus_cmd" org.kde.kglobalaccel /component/kwin \
        org.kde.kglobalaccel.Component.shortcutNames 2>/dev/null | grep '^toggle_windows_' || true)
    for name in $names; do
        echo "    dropping shortcut $name"
        "$qdbus_cmd" org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.unregister \
            kwin "$name" >/dev/null 2>&1 || true
    done
fi

echo "==> Removing files"
rm -rf "$SCRIPT_DIR"
plugin_dirs=("$PREFIX/lib/$(uname -m)-linux-gnu/qt6/plugins" "$PREFIX/lib64/qt6/plugins" "$PREFIX/lib/qt6/plugins")
for qtpaths in qtpaths6 qtpaths; do
    if have "$qtpaths"; then plugin_dirs=("$("$qtpaths" --query QT_INSTALL_PLUGINS)" "${plugin_dirs[@]}"); break; fi
done
for dir in "${plugin_dirs[@]}"; do
    plugin="$dir/kwin/effects/configs/toggle_windows.so"
    [[ -e "$plugin" ]] || continue
    if [[ -w "$(dirname "$plugin")" ]]; then rm -f "$plugin"; else sudo rm -f "$plugin"; fi
    echo "    removed $plugin"
    break
done

if have kwriteconfig6; then
    kwriteconfig6 --file kwinrc --group Plugins --key toggle_windowsEnabled --delete
    kwriteconfig6 --file kwinrc --group Script-toggle_windows --key Entries --delete
fi

echo "Done."
