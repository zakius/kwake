#!/usr/bin/env bash
set -euo pipefail

version="${1:?usage: ci/make-bundle.sh VERSION}"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

cp -r install.sh uninstall.sh plugin-dirs.sh LICENSE script "$stage/"
cp dist/*.so "$stage/"
makeself --nox11 --sha256 --tar-quietly "$stage" "dist/kwake.run" \
    "Kwake $version" ./install.sh
