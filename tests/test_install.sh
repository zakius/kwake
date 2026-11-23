#!/usr/bin/env bash
set -euo pipefail

tmp=$(mktemp -d)
trap '/bin/rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/plugins/kwin/effects/configs" "$tmp/source"
cp -r install.sh script "$tmp/source/"
echo "PLUGIN_ROOTS=(\"$tmp/plugins\")" >"$tmp/source/plugin-dirs.sh"
touch "$tmp/plugin.so"

cat >"$tmp/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == install && ${*: -1} == "$MOCK_ROOT"/* ]] || exit 1
exec "$@"
MOCK
cat >"$tmp/bin/kwriteconfig6" <<'MOCK'
#!/usr/bin/env bash
printf '%q ' "$@" >>"$MOCK_ROOT/kwriteconfig6.log"
echo >>"$MOCK_ROOT/kwriteconfig6.log"
MOCK
cat >"$tmp/bin/kreadconfig6" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$SAVED_ENTRIES"
MOCK
cat >"$tmp/bin/qdbus6" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
    *isScriptLoaded*) cat "$MOCK_ROOT/loaded" ;;
    *unloadScript*) echo false >"$MOCK_ROOT/loaded" ;;
    *Scripting.start*) echo true >"$MOCK_ROOT/loaded" ;;
esac
MOCK
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/sleep"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" XDG_DATA_HOME="$tmp/data" MOCK_ROOT="$tmp" \
    SAVED_ENTRIES="-Term | ghostty | | Meta+T"

# Installs over a loaded Kwake of the given version and prints every Entries
# value install.sh wrote, one per line.
install_over() {
    mkdir -p "$tmp/data/kwin/scripts/kwake"
    printf '{"KPlugin": {"Version": "%s"}}\n' "$1" >"$tmp/data/kwin/scripts/kwake/metadata.json"
    echo true >"$tmp/loaded"
    : >"$tmp/kwriteconfig6.log"
    "$tmp/source/install.sh" --plugin "$tmp/plugin.so" >/dev/null
    test "$(cat "$tmp/loaded")" = true
    grep -- '--key Entries' "$tmp/kwriteconfig6.log" | sed 's/.*--key Entries \(-- \)\{0,1\}//; s/ $//' || true
}

# An empty list makes Kwake 3.2 and later drop the shortcuts set in KDE's
# shortcut editor (0cd61b0), so only older versions get one.
test -z "$(install_over 3.2.0)"
test "$(install_over 3.1.0)" = "''
-Term\\ \\|\\ ghostty\\ \\|\\ \\|\\ Meta+T"
