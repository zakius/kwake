#!/usr/bin/env bash
# Install the Toggle Windows KWin script and its settings page.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/toggle_windows"
REPO="zakius/kwin-toggle-windows"
# Must match KPlugin.Id in script/metadata.json; the settings host looks the
# plugin up by that name.
PLUGIN_ID="toggle_windows"
# Only used with --build. Qt only searches its own plugin directory, so
# /usr/local will not be found.
PREFIX="/usr"
SETTINGS_PAGE="prebuilt"

usage() {
    cat <<USAGE
Usage: $0 [options]

By default the settings page is downloaded, prebuilt for this CPU (x86_64 or
ARM64), from the project's GitHub releases.

  --build         Build the settings page from this checkout instead. Needs
                  the build tools listed in the README.
  --script-only   Skip the settings page; the settings open as a plain text
                  editor instead.
  --prefix DIR    With --build, install the settings page under DIR
                  (default: /usr). Must be a directory Qt searches for plugins.
  -h, --help      Show this message.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build) SETTINGS_PAGE="build"; shift ;;
        --script-only) SETTINGS_PAGE="none"; shift ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

have() { command -v "$1" >/dev/null 2>&1; }

# The directory KWin keeps its own config plugins in. It exists wherever KWin
# is installed, unlike qtpaths, which Ubuntu only ships with its dev tools.
kwin_plugin_dir() {
    local dir
    for dir in "/usr/lib/$(uname -m)-linux-gnu/qt6/plugins" /usr/lib64/qt6/plugins /usr/lib/qt6/plugins; do
        if [[ -d "$dir/kwin/effects/configs" ]]; then
            echo "$dir/kwin/effects/configs"
            return
        fi
    done
    echo "error: cannot find KWin's plugin directory; is Plasma 6 installed?" >&2
    exit 1
}

install_prebuilt() {
    local arch asset tag tmp base dest
    arch=$(uname -m)
    case "$arch" in
        x86_64|aarch64) ;;
        *) echo "error: no prebuilt settings page for $arch; use --build or --script-only" >&2; exit 1 ;;
    esac
    asset="$PLUGIN_ID-$arch.so"
    # A checkout sitting on a release tag gets that release's plugin; anything
    # else gets the latest release.
    tag=$(git -C "$SOURCE_DIR" describe --tags --exact-match 2>/dev/null || true)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    echo "==> Downloading settings page (${tag:-latest release}, $arch)"
    if have gh && gh auth status >/dev/null 2>&1; then
        gh release download ${tag:+"$tag"} --repo "$REPO" \
            --pattern "$asset" --pattern SHA256SUMS --dir "$tmp" || download_failed
    else
        base="https://github.com/$REPO/releases/latest/download"
        [[ -n "$tag" ]] && base="https://github.com/$REPO/releases/download/$tag"
        curl -fsSL -o "$tmp/$asset" "$base/$asset" || download_failed
        curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" || download_failed
    fi
    # Verified before the file goes anywhere near root.
    (cd "$tmp" && sha256sum --check --ignore-missing --quiet SHA256SUMS) || {
        echo "error: the downloaded settings page does not match its checksum" >&2
        exit 1
    }

    dest=$(kwin_plugin_dir)
    echo "==> Installing settings page to $dest (needs root)"
    if [[ -w "$dest" ]]; then
        install -m 644 "$tmp/$asset" "$dest/$PLUGIN_ID.so"
    else
        sudo install -m 644 "$tmp/$asset" "$dest/$PLUGIN_ID.so"
    fi
}

download_failed() {
    echo "error: could not download the settings page from $REPO." >&2
    echo "       For a private repository, install gh and run 'gh auth login'." >&2
    echo "       Or build it here with --build, or skip it with --script-only." >&2
    exit 1
}

install_built() {
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
}

qdbus_cmd=""
for candidate in qdbus6 qdbus-qt6 qdbus; do
    if have "$candidate"; then qdbus_cmd="$candidate"; break; fi
done

echo "==> Installing KWin script to $SCRIPT_DIR"
rm -rf "$SCRIPT_DIR"
mkdir -p "$SCRIPT_DIR"
cp -r "$SOURCE_DIR/script/." "$SCRIPT_DIR/"

case "$SETTINGS_PAGE" in
    prebuilt) install_prebuilt ;;
    build) install_built ;;
    none)
        echo "==> Skipping settings page; falling back to the plain text editor"
        # Without the compiled page, KDE's generic editor renders contents/ui/config.ui.
        sed -i "s|\"kwin/effects/configs/$PLUGIN_ID\"|\"kwin/effects/configs/kcm_kwin4_genericscripted\"|" \
            "$SCRIPT_DIR/metadata.json"
        ;;
esac

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
next to Toggle Windows. Restart System Settings first if it is open.

Nothing is configured out of the box, so no shortcuts are registered yet.
DONE
