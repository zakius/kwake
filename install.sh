#!/usr/bin/env bash
# Install the Toggle Windows KWin script and its settings page.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/toggle_windows"
REPO="zakius/kwin-toggle-windows"
# The settings host looks the plugin up by the script's id, so this must equal
# KPlugin.Id in script/metadata.json; check.sh fails if they differ.
PLUGIN_ID="toggle_windows"
# Empty means: download the release build for this CPU.
PLUGIN_FILE=""

usage() {
    cat <<USAGE
Usage: $0 [options]

By default the settings page is downloaded, prebuilt for this CPU (x86_64 or
ARM64), from the project's GitHub releases.

  --plugin FILE   Install this settings page plugin instead of downloading
                  one, e.g. one built as described in the README.
  -h, --help      Show this message.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plugin) PLUGIN_FILE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done
# Checked before anything is touched, so a mistyped path changes nothing.
[[ -z "$PLUGIN_FILE" || -f "$PLUGIN_FILE" ]] || { echo "error: $PLUGIN_FILE does not exist" >&2; exit 1; }

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

download_plugin() {
    local arch asset tag base
    arch=$(uname -m)
    case "$arch" in
        x86_64|aarch64) ;;
        *) echo "error: no prebuilt settings page for $arch; build one and pass it with --plugin" >&2; exit 1 ;;
    esac
    asset="$PLUGIN_ID-$arch.so"
    # A checkout sitting on a release tag gets that release's plugin; anything
    # else gets the latest release.
    tag=$(git -C "$SOURCE_DIR" describe --tags --exact-match 2>/dev/null || true)
    # Global, not local: the EXIT trap runs after this function has returned.
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

    PLUGIN_FILE="$tmp/$asset"
}

download_failed() {
    echo "error: could not download the settings page from $REPO." >&2
    echo "       For a private repository, install gh and run 'gh auth login'." >&2
    echo "       Or build it yourself and pass it with --plugin; see the README." >&2
    exit 1
}

install_plugin() {
    local dest
    dest=$(kwin_plugin_dir)
    echo "==> Installing settings page to $dest (needs root)"
    sudo install -m 644 "$PLUGIN_FILE" "$dest/$PLUGIN_ID.so"
}

qdbus_cmd=""
for candidate in qdbus6 qdbus-qt6 qdbus; do
    if have "$candidate"; then qdbus_cmd="$candidate"; break; fi
done

echo "==> Installing KWin script to $SCRIPT_DIR"
rm -rf "$SCRIPT_DIR"
mkdir -p "$SCRIPT_DIR"
cp -r "$SOURCE_DIR/script/." "$SCRIPT_DIR/"

[[ -n "$PLUGIN_FILE" ]] || download_plugin
install_plugin

echo "==> Enabling the script"
kwriteconfig6 --file kwinrc --group Plugins --key "${PLUGIN_ID}Enabled" true

if [[ -n "$qdbus_cmd" ]]; then
    echo "==> Loading the script"
    "$qdbus_cmd" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$PLUGIN_ID" >/dev/null 2>&1 || true
    "$qdbus_cmd" org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
        "$SCRIPT_DIR/contents/code/main.js" "$PLUGIN_ID" >/dev/null 2>&1 || true
    "$qdbus_cmd" org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1 || true
fi

cat <<DONE

Done. Add your applications in
System Settings > Window Management > KWin Scripts > the settings icon
next to Toggle Windows. Restart System Settings first if it is open.

Nothing is configured out of the box, so no shortcuts are registered yet.
DONE
