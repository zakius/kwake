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
# Parsing both files also validates them. The settings page only opens if the
# script points at a plugin named after the script itself (see
# kcm/CMakeLists.txt), and install.sh installs the plugin under that name.
node -e '
const fs = require("fs");
const meta = JSON.parse(fs.readFileSync("script/metadata.json", "utf8"));
JSON.parse(fs.readFileSync("kcm/src/metadata.json", "utf8"));
const id = meta.KPlugin.Id;
const fail = (message) => { console.error(message); process.exit(1); };
if (meta["X-KDE-ConfigModule"] !== "kwin/effects/configs/" + id)
    fail("script/metadata.json: X-KDE-ConfigModule must be kwin/effects/configs/" + id);
const found = fs.readFileSync("install.sh", "utf8").match(/^PLUGIN_ID="([^"]+)"/m);
if (!found || found[1] !== id)
    fail("install.sh: PLUGIN_ID must be " + id);
'

echo "==> Shell scripts"
shellcheck install.sh uninstall.sh check.sh ci/*.sh

echo "==> QML (qmllint)"
# kcm and i18n are provided by the settings host at runtime, so qmllint cannot
# see them; unqualified access is reported but not fatal. Everything else is.
"$qmllint" --missing-property warning --unqualified info --max-warnings 0 kcm/ui/main.qml

echo "All checks passed."
