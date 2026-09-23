#!/usr/bin/env bash
set -euo pipefail

tmp=$(mktemp -d)
trap '/bin/rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/plugins/kwin/effects/configs" \
    "$tmp/data/kwin/scripts/kwake"
touch "$tmp/data/kwin/scripts/kwake/sentinel" \
    "$tmp/plugins/kwin/effects/configs/kwake.so"
sed "s|\"/usr/lib/\$(uname -m)-linux-gnu/qt6/plugins\" /usr/lib64/qt6/plugins /usr/lib/qt6/plugins|\"\$MOCK_PLUGIN_ROOT\"|g" \
    uninstall.sh >"$tmp/uninstall.sh"
chmod +x "$tmp/uninstall.sh"
cat >"$tmp/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == rm ]] || exit 1
shift
for arg in "$@"; do
    case "$arg" in
        -*) ;;
        "$MOCK_PLUGIN_ROOT"/*) ;;
        *) exit 1 ;;
    esac
done
exec /bin/rm "$@"
MOCK
cat >"$tmp/bin/rm" <<'MOCK'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        -*) ;;
        "$MOCK_ROOT"/*) ;;
        *) exit 0 ;;
    esac
done
exec /bin/rm "$@"
MOCK
for command in systemctl kwriteconfig6 qdbus6 sleep; do
    printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/$command"
done
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" XDG_DATA_HOME="$tmp/data" \
    MOCK_ROOT="$tmp" MOCK_PLUGIN_ROOT="$tmp/plugins"

if "$tmp/uninstall.sh" --unknown >/dev/null 2>&1; then exit 1; fi
test -e "$tmp/data/kwin/scripts/kwake/sentinel"
test -e "$tmp/plugins/kwin/effects/configs/kwake.so"
"$tmp/uninstall.sh" >/dev/null
test ! -e "$tmp/data/kwin/scripts/kwake/sentinel"
test -e "$tmp/plugins/kwin/effects/configs/kwake.so"
"$tmp/uninstall.sh" --remove-system-plugin >/dev/null
test ! -e "$tmp/plugins/kwin/effects/configs/kwake.so"
