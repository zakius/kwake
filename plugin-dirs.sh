# Sourced by install.sh and uninstall.sh: where distributions keep Qt 6
# plugins. Debian and Ubuntu come first, then Fedora and openSUSE, then Arch.
# shellcheck shell=bash disable=SC2034
PLUGIN_ROOTS=("/usr/lib/$(uname -m)-linux-gnu/qt6/plugins" /usr/lib64/qt6/plugins /usr/lib/qt6/plugins)
