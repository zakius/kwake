#!/usr/bin/env bash
# Lints everything except the C++, which clazy checks while compiling in
# ci/build-plugin.sh. CI runs exactly this.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Arch keeps qmllint out of PATH.
qmllint=$(command -v qmllint6 || command -v qmllint || echo /usr/lib/qt6/bin/qmllint)

echo "==> KWin script"
node test_main.js

echo "==> Metadata"
python3 -m json.tool script/metadata.json >/dev/null
python3 -m json.tool kcm/src/metadata.json >/dev/null
# The settings page only opens if the script points at a plugin named after the
# script itself; see kcm/CMakeLists.txt.
python3 - <<'PY'
import json
meta = json.load(open("script/metadata.json"))
expected = "kwin/effects/configs/" + meta["KPlugin"]["Id"]
actual = meta.get("X-KDE-ConfigModule")
if actual != expected:
    raise SystemExit(f"script/metadata.json: X-KDE-ConfigModule is {actual!r}, must be {expected!r}")
PY

echo "==> Shell scripts"
shellcheck install.sh uninstall.sh check.sh ci/*.sh

echo "==> QML (qmllint)"
# kcm and i18n are provided by the settings host at runtime, so qmllint cannot
# see them; unqualified access is reported but not fatal. Everything else is.
"$qmllint" --missing-property warning --unqualified info --max-warnings 0 kcm/ui/main.qml

echo "All checks passed."
