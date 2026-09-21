#!/usr/bin/env bash
# Wraps everything install.sh needs, plus the plugins in dist/, into one
# self-extracting installer with makeself. Run from the repository root after
# the plugins are in dist/:
#
#     ci/make-bundle.sh v1.2.3    # writes dist/toggle-windows.run
#
# The file name carries no version, so the latest one is always at
# releases/latest/download/toggle-windows.run; the version is in its label.
#
# The payload is only ever produced by makeself; never edit a .run by hand.
set -euo pipefail

version="$1"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

cp -r install.sh uninstall.sh script "$stage/"
cp dist/*.so "$stage/"
makeself --nox11 --sha256 --tar-quietly "$stage" "dist/toggle-windows.run" \
    "Toggle Windows $version" ./install.sh
