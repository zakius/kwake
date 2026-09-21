#!/usr/bin/env bash
# Checks that every library and symbol the built plugins need resolves, as the
# settings host would when loading them. Run from the repository root inside a
# Debian, Ubuntu or Fedora container, after build-plugin.sh has filled dist/.
set -euo pipefail

if command -v dnf >/dev/null; then
    dnf install -y kf6-kcmutils kf6-kconfig kf6-kcoreaddons qt6-qtdeclarative >/dev/null
else
    apt-get update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libkf6kcmutils-dev libkf6config-dev >/dev/null
fi

# shellcheck source=/dev/null
. /etc/os-release
plugins=(dist/*-"$(uname -m)".so)
[[ -e "${plugins[0]}" ]] || { echo "no plugins for $(uname -m) in dist/" >&2; exit 1; }
for plugin in "${plugins[@]}"; do
    # -r resolves every symbol; "not found" covers missing libraries and
    # symbol versions, such as a plugin built against a newer Qt.
    if ldd -r "$plugin" 2>&1 | grep -E "undefined symbol|not found"; then
        echo "$PRETTY_NAME ($(uname -m)): $(basename "$plugin") does NOT load" >&2
        exit 1
    fi
    echo "$PRETTY_NAME ($(uname -m)): $(basename "$plugin") loads"
done
