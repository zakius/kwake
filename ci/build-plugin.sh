#!/usr/bin/env bash
# Builds the release plugin. Run inside a debian:trixie container from the
# repository root; CI does this for each CPU architecture.
#
# Debian 13 has the oldest Qt (6.8) and KDE Frameworks (6.13) among supported
# distributions. Qt refuses plugins built against a newer Qt than the one
# running, and KDE libraries do not version their symbols, so a plugin built
# here loads on every newer system, and not the other way round.
set -euo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential cmake extra-cmake-modules qt6-base-dev qt6-declarative-dev \
    libkf6coreaddons-dev libkf6config-dev libkf6kcmutils-dev

cmake -S kcm -B kcm/build-release -DCMAKE_BUILD_TYPE=Release
cmake --build kcm/build-release --parallel

mkdir -p dist
for plugin in kcm/build-release/bin/kwin/effects/configs/*.so; do
    cp "$plugin" "dist/$(basename "$plugin" .so)-$(uname -m).so"
done
ls -l dist
