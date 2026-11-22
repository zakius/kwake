#!/usr/bin/env bash
# Debian 13 has the oldest Qt (6.8) and KDE Frameworks (6.13) among supported
# distributions. Qt refuses plugins built against a newer Qt than the one
# running, and KDE libraries do not version their symbols, so a plugin built
# here loads on every newer system, and not the other way round.
set -euo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential cmake extra-cmake-modules clazy qt6-base-dev qt6-declarative-dev \
    libkf6coreaddons-dev libkf6config-dev libkf6kcmutils-dev

# unused-result-check is left out: it crashes Debian 13's clazy 1.14.
export CLAZY_CHECKS="level2,qproperty-type-mismatch,qt-keywords,signal-with-return-value,thread-with-slots,detaching-member,assert-with-side-effects"
export CLAZY_IGNORE_DIRS=".*/build-release/.*|/usr/.*"

cmake -S kcm -B kcm/build-release -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER=clazy -DCMAKE_CXX_FLAGS=-Werror
cmake --build kcm/build-release --parallel --clean-first

mkdir -p dist
for plugin in kcm/build-release/bin/kwin/effects/configs/*.so; do
    cp "$plugin" "dist/$(basename "$plugin" .so)-$(uname -m).so"
done

# dpkg-shlibdeps insists on running next to a debian/control.
shlibs=$(mktemp -d)
mkdir "$shlibs/debian"
printf 'Source: x\n\nPackage: x\nArchitecture: any\n' > "$shlibs/debian/control"
for plugin in dist/*-"$(uname -m)".so; do
    (cd "$shlibs" && dpkg-shlibdeps -O "$OLDPWD/$plugin") |
        sed 's/^shlibs:Depends=//' > "${plugin%.so}.deb-depends"
done
ls -l dist
