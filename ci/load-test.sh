#!/usr/bin/env bash
# Installs this CPU's package from dist/ with the distribution's own package
# manager, which proves its dependencies resolve, then checks that every
# library and symbol the installed plugin needs resolves, as the settings host
# would when loading it. Run from the repository root inside a Debian, Ubuntu
# or Fedora container, after make-packages.sh has filled dist/.
set -euo pipefail

if command -v dnf >/dev/null; then
    dnf install -y dist/*-"$(uname -m)".rpm >/dev/null
    rpm -ql "$(rpm -qp --qf '%{NAME}' dist/*-"$(uname -m)".rpm)" > /tmp/files
else
    arch=$(dpkg --print-architecture)
    apt-get update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ./dist/*-"$arch".deb >/dev/null
    dpkg -L "$(dpkg-deb -f dist/*-"$arch".deb Package)" > /tmp/files
fi

# shellcheck source=/dev/null
. /etc/os-release
mapfile -t plugins < <(grep '/kwin/effects/configs/.*\.so$' /tmp/files)
[[ ${#plugins[@]} -gt 0 ]] || { echo "the package installs no plugin" >&2; exit 1; }
for plugin in "${plugins[@]}"; do
    # -r resolves every symbol; "not found" covers missing libraries and
    # symbol versions, such as a plugin built against a newer Qt.
    if ldd -r "$plugin" 2>&1 | grep -E "undefined symbol|not found"; then
        echo "$PRETTY_NAME ($(uname -m)): $plugin does NOT load" >&2
        exit 1
    fi
    echo "$PRETTY_NAME ($(uname -m)): $plugin loads"
done
