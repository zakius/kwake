#!/usr/bin/env bash
# Wraps everything install.sh needs, plus the plugins in dist/, into one
# self-extracting installer with makeself. Run from the repository root after
# the plugins are in dist/:
#
#     ci/make-bundle.sh v1.2.3    # writes dist/toggle-windows-v1.2.3.run
#
# The payload is only ever produced by makeself; never edit a .run by hand.
set -euo pipefail

version="$1"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

cp -r install.sh uninstall.sh script "$stage/"
cp dist/*.so "$stage/"
makeself --nox11 --sha256 --tar-quietly "$stage" "dist/toggle-windows-$version.run" \
    "Toggle Windows $version" ./install.sh
