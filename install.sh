#!/usr/bin/env bash
# Build and install the Toggle Windows KWin script and its settings page.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/toggle_windows"
# Qt only searches its own plugin directory, so /usr/local will not be found.
PREFIX="/usr"
BUILD_KCM=1

usage() {
    cat <<USAGE
Usage: $0 [options]

  --script-only   Install just the KWin script, skipping the settings page.
                  Useful if you have no build tools, or if the compiled page
                  cannot be built on your distribution.
  --prefix DIR    Install the settings page under DIR (default: /usr). Must be
                  a directory Qt searches for plugins, or set QT_PLUGIN_PATH.
  -h, --help      Show this message.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --script-only) BUILD_KCM=0; shift ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

have() { command -v "$1" >/dev/null 2>&1; }

qdbus_cmd=""
for candidate in qdbus6 qdbus-qt6 qdbus; do
    if have "$candidate"; then qdbus_cmd="$candidate"; break; fi
done

echo "==> Installing KWin script to $SCRIPT_DIR"
rm -rf "$SCRIPT_DIR"
mkdir -p "$SCRIPT_DIR"
cp -r "$SOURCE_DIR/script/." "$SCRIPT_DIR/"

if [[ $BUILD_KCM -eq 1 ]]; then
    echo "==> Building settings page"
    cmake -S "$SOURCE_DIR/kcm" -B "$SOURCE_DIR/kcm/build" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release
    cmake --build "$SOURCE_DIR/kcm/build" --parallel

    echo "==> Installing settings page to $PREFIX (needs root)"
    if [[ -w "$PREFIX/lib" ]]; then
        cmake --install "$SOURCE_DIR/kcm/build"
    else
        sudo cmake --install "$SOURCE_DIR/kcm/build"
    fi
else
    echo "==> Skipping settings page; falling back to the plain text editor"
    # Without the compiled page, KDE's generic editor renders contents/ui/config.ui.
    sed -i 's|"kwin/effects/configs/toggle_windows"|"kwin/effects/configs/kcm_kwin4_genericscripted"|' \
        "$SCRIPT_DIR/metadata.json"
fi

echo "==> Enabling the script"
if have kwriteconfig6; then
    kwriteconfig6 --file kwinrc --group Plugins --key toggle_windowsEnabled true
else
    echo "    kwriteconfig6 not found; enable Toggle Windows yourself in" >&2
    echo "    System Settings > Window Management > KWin Scripts." >&2
fi

if [[ -n "$qdbus_cmd" ]]; then
    echo "==> Loading the script"
    "$qdbus_cmd" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript toggle_windows >/dev/null 2>&1 || true
    "$qdbus_cmd" org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
        "$SCRIPT_DIR/contents/code/main.js" toggle_windows >/dev/null 2>&1 || true
    "$qdbus_cmd" org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1 || true
fi

cat <<DONE

Done. Add your applications in
System Settings > Window Management > KWin Scripts > the settings icon
next to Toggle Windows.

Nothing is configured out of the box, so no shortcuts are registered yet.
DONE
