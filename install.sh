#!/usr/bin/env bash
# Install the Toggle Windows KWin script and its settings page.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/toggle_windows"
REPO="zakius/kwin-toggle-windows"
# The settings host looks the plugin up by the script's id, so this must equal
# KPlugin.Id in script/metadata.json; check.sh fails if they differ.
PLUGIN_ID="toggle_windows"
# The self-contained installer attached to every release.
BUNDLE="toggle-windows.run"
# Empty means: the plugin for this CPU embedded next to this script.
PLUGIN_FILE=""
ONLINE=0

usage() {
    cat <<USAGE
Usage: $0 [options]

Without options, installs the settings page plugin for this CPU that ships next
to this script in a release's .run file. Nothing is downloaded.

  --plugin FILE   Install this settings page plugin instead, e.g. one built as
                  described in the README.
  --online        Download the latest release's installer, verify it and run
                  it, installing or updating everything to that release.
  --uninstall     Remove everything this installed.
  -h, --help      Show this message.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plugin) PLUGIN_FILE="$2"; shift 2 ;;
        --online) ONLINE=1; shift ;;
        --uninstall) exec "$SOURCE_DIR/uninstall.sh" ;;
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

# Fetches the latest release's installer and runs it; that installer then uses
# its own embedded payload.
install_latest() {
    # Global, not local: the EXIT trap runs after this function has returned.
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    echo "==> Downloading the latest release of $REPO"
    if have gh && gh auth status >/dev/null 2>&1; then
        gh release download --repo "$REPO" \
            --pattern "$BUNDLE" --pattern SHA256SUMS --dir "$tmp" || download_failed
    else
        curl -fsSL -o "$tmp/$BUNDLE" "https://github.com/$REPO/releases/latest/download/$BUNDLE" || download_failed
        curl -fsSL -o "$tmp/SHA256SUMS" "https://github.com/$REPO/releases/latest/download/SHA256SUMS" || download_failed
    fi
    # Verified before it runs anything, let alone anything as root.
    (cd "$tmp" && sha256sum --check --ignore-missing --quiet SHA256SUMS) || {
        echo "error: the downloaded installer does not match its checksum" >&2
        exit 1
    }
    sh "$tmp/$BUNDLE"
}

download_failed() {
    echo "error: could not download the latest release from $REPO." >&2
    echo "       For a private repository, install gh and run 'gh auth login'." >&2
    exit 1
}

if [[ $ONLINE -eq 1 ]]; then
    install_latest
    exit
fi

# A release's .run file carries the plugin for each CPU next to this script.
bundled="$SOURCE_DIR/$PLUGIN_ID-$(uname -m).so"
[[ -z "$PLUGIN_FILE" && -f "$bundled" ]] && PLUGIN_FILE="$bundled"
# Checked before anything is touched, so a mistake changes nothing.
if [[ -z "$PLUGIN_FILE" ]]; then
    echo "error: no settings page for $(uname -m) next to this script." >&2
    echo "       Pass --plugin FILE, or --online to install the latest release." >&2
    exit 1
fi
[[ -f "$PLUGIN_FILE" ]] || { echo "error: $PLUGIN_FILE does not exist" >&2; exit 1; }


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
