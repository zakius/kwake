#!/usr/bin/env bash
# Loads the built plugins with every symbol resolved at once, the way the
# settings host would. Run from the repository root inside a Debian, Ubuntu or
# Fedora container, after build-plugin.sh has filled dist/.
set -euo pipefail

if command -v dnf >/dev/null; then
    dnf install -y python3 kf6-kcmutils kf6-kconfig kf6-kcoreaddons qt6-qtdeclarative >/dev/null
else
    apt-get update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3 libkf6kcmutils-dev libkf6config-dev >/dev/null
fi

# shellcheck source=/dev/null
. /etc/os-release
python3 - "$PRETTY_NAME" <<'PY'
import ctypes, glob, os, platform, sys
plugins = sorted(glob.glob(f"dist/*-{platform.machine()}.so"))
if not plugins:
    sys.exit(f"no plugins for {platform.machine()} in dist/")
for plugin in plugins:
    ctypes.CDLL(plugin, mode=os.RTLD_NOW)
    print(f"{sys.argv[1]} ({platform.machine()}): {os.path.basename(plugin)} loads")
PY
