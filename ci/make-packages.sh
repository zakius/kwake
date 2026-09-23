#!/usr/bin/env bash
# Packages the KWin script and the plugins in dist/ as a .deb and an .rpm per
# CPU. Run from the repository root with nfpm and jq on PATH, after
# build-plugin.sh has filled dist/, .deb-depends files included:
#
#     ci/make-packages.sh    # writes dist/kwake-amd64.deb, dist/kwake-x86_64.rpm, ...
#
# The file names carry no version, so the latest ones are always at
# releases/latest/download/; the version is in the package metadata.
#
# The plugin built on Debian 13 is the one both formats ship; load-test.sh
# installs each package on the distributions it claims to support.
set -euo pipefail

id=kwake
version=$(jq -r .KPlugin.Version script/metadata.json)

# One YAML list item per line of stdin.
yaml_list() { sed 's/^/      - "/; s/$/"/'; }

for plugin in dist/"$id"-*.so; do
    cpu=$(basename "$plugin" .so)
    cpu=${cpu#"$id"-}
    case "$cpu" in
        x86_64) arch=amd64 ;;
        aarch64) arch=arm64 ;;
        *) echo "error: no package architecture for $cpu" >&2; exit 1 ;;
    esac
    config=$(mktemp)
    cat > "$config" <<YAML
name: $id
arch: $arch
platform: linux
version: $version
maintainer: zakius <2071503+zakius@users.noreply.github.com>
homepage: https://github.com/zakius/kwake
license: GPL-3.0-or-later
description: |-
  KWin script that raises or minimises chosen applications by global shortcut.
  Includes its settings page for System Settings.
contents:
  - src: script/
    dst: /usr/share/kwin/scripts/$id
  - src: $plugin
    dst: /usr/lib/$cpu-linux-gnu/qt6/plugins/kwin/effects/configs/$id.so
    packager: deb
  - src: $plugin
    dst: /usr/lib64/qt6/plugins/kwin/effects/configs/$id.so
    packager: rpm
  - src: LICENSE
    dst: /usr/share/doc/$id/copyright
    packager: deb
  - src: LICENSE
    dst: /usr/share/licenses/$id/LICENSE
    type: license
    packager: rpm
scripts:
  postinstall: ci/postinstall.sh
  preremove: ci/preremove.sh
overrides:
  deb:
    depends:
$(tr ',' '\n' < "${plugin%.so}.deb-depends" | sed 's/^ *//' | yaml_list)
  rpm:
    depends:
$(readelf -d "$plugin" | sed -n 's/.*Shared library: \[\(.*\)\]/\1()(64bit)/p' | yaml_list)
YAML
    nfpm package --config "$config" --packager deb --target "dist/$id-$arch.deb"
    nfpm package --config "$config" --packager rpm --target "dist/$id-$cpu.rpm"
    rm -f "$config"
done
ls -l dist/*.deb dist/*.rpm
