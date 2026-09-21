#!/usr/bin/env bash
# Static checks for everything in the repository. CI runs exactly this.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Checks clazy runs on the C++. level2 includes levels 0 and 1, which cover
# lambdas connected without a context object, a use-after-free waiting to
# happen. The named extras are opt-in checks that matter for a class QML talks to.
CLAZY_CHECKS="level2,qproperty-type-mismatch,qt-keywords,signal-with-return-value,thread-with-slots,detaching-member,unused-result-check,assert-with-side-effects"

find_tool() {
    for candidate in "$@"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            echo "$candidate"
            return
        fi
    done
    echo "error: none of $* found" >&2
    exit 1
}

qtpaths=$(find_tool qtpaths6 qtpaths /usr/lib/qt6/bin/qtpaths)
qmllint=$(find_tool qmllint6 qmllint /usr/lib/qt6/bin/qmllint)

echo "==> KWin script"
node --check script/contents/code/main.js

echo "==> Metadata and config files"
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
python3 -c "import sys, xml.dom.minidom as m; [m.parse(f) for f in sys.argv[1:]]" \
    script/contents/config/main.xml script/contents/ui/config.ui

echo "==> Shell scripts"
shellcheck install.sh uninstall.sh check.sh

echo "==> QML (qmllint)"
# kcm and i18n are provided by the settings host at runtime, so qmllint cannot
# see them; unqualified access is reported but not fatal. Everything else is.
"$qmllint" -I "$("$qtpaths" --query QT_INSTALL_QML)" \
    --missing-property warning --unqualified info --max-warnings 0 \
    kcm/ui/main.qml

echo "==> C++ (clazy, warnings are errors)"
export CLAZY_CHECKS
export CLAZY_IGNORE_DIRS=".*/build-clazy/.*"
cmake -S kcm -B kcm/build-clazy -DCMAKE_CXX_COMPILER=clazy -DCMAKE_CXX_FLAGS=-Werror >/dev/null
cmake --build kcm/build-clazy --clean-first

echo "All checks passed."
