# Toggle Windows

A KWin script that gives chosen applications a global shortcut which raises
them, or minimises them again when they already have focus, so one key brings a
terminal or chat window up and the same key puts it away.

Applications are managed from a settings page in System Settings: one row each,
with a **Detect Window** button that fills in a window's class by clicking it,
the way KWin Rules does.

Nothing is configured out of the box. No shortcuts exist until you add an
application.

## Install

### 1. Requirements

KDE Plasma 6. Nothing else is needed.

Ubuntu 24.04 ships Plasma 5, which is not supported; Ubuntu releases with
Plasma 6 start at 25.04.

### 2. Build tools (only for `--build`)

The installer downloads the settings page prebuilt for x86_64 and ARM64, so
most installs skip this step. It is only needed to build the settings page
yourself with `./install.sh --build`, for another CPU type or to try changes
that are not released yet.

Debian and Ubuntu:

```sh
sudo apt install build-essential cmake extra-cmake-modules \
    qt6-base-dev qt6-declarative-dev \
    libkf6coreaddons-dev libkf6config-dev libkf6kcmutils-dev
```

Fedora:

```sh
sudo dnf install gcc-c++ cmake extra-cmake-modules \
    qt6-qtbase-devel qt6-qtdeclarative-devel \
    kf6-kcoreaddons-devel kf6-kconfig-devel kf6-kcmutils-devel
```

Tested on Debian 13, Ubuntu 26.04 and Fedora 44. Debian and Ubuntu use the
same package names.

### 3. Install

```sh
git clone https://github.com/zakius/kwin-toggle-windows.git
cd kwin-toggle-windows
./install.sh
```

This downloads the settings page for your CPU from the latest GitHub release,
checks it against the release's `SHA256SUMS`, and asks for root to place it
next to KWin's own plugins. Everything else is installed for your user only.
A checkout of a release tag gets that release's settings page instead of the
latest. Downloads go through `gh` when it is installed and logged in, which a
private repository needs, and through `curl` otherwise.

To build the settings page from this checkout instead:

```sh
./install.sh --build
```

Then add your applications in **System Settings → Window Management →
KWin Scripts**, using the settings icon next to Toggle Windows.

## Uninstall

```sh
./uninstall.sh
```

This puts any hidden windows back on the taskbar and unregisters the shortcuts
before removing the files, so nothing is left behind in the shortcuts editor.

## How it behaves

Press the shortcut for an application and its window is raised and focused,
while the other managed windows are minimised. Press it again while that window
has focus and it is minimised, handing focus to whichever managed window is next
in the stack. Managed windows are kept off the taskbar, since the shortcut is
how you reach them; they go back on the taskbar as soon as you remove them.

Each row matches a window by class and, optionally, by title. Both are
case-insensitive substring matches, so `ghostty` matches
`com.mitchellh.ghostty`. The shortcut is set in the same row, and changing it
takes effect on save.

## Settings

Saving applies at once. The script re-reads its configuration and registers,
rebinds or drops shortcuts in place, so there is nothing to reload and no need
to log out.

Settings live in `kwinrc` under `[Script-toggle_windows]`, as one line per
application in the key `Entries`:

```
Name | window class | title | shortcut
```

## Compatibility

The script half is plain JavaScript and depends only on KWin's scripting API.
It targets KWin 6.

The settings page is a QML form in a small compiled plugin. The plugin links
against Qt 6 and KDE Frameworks 6 but no KWin library, so Plasma and KWin
updates cannot break it. Qt and KDE Frameworks both keep ABI stable across a
major version, so it keeps working through 6.x updates. Release builds load on
any system with Qt 6.8 and KDE Frameworks 6.13 or newer. A future Qt 7 and
Frameworks 7 transition would need a rebuild.

## Checks

```sh
./check.sh
```

It lints everything except the C++: `qmllint` on the QML with unknown
properties made fatal, ShellCheck on the scripts, and the metadata the settings
page depends on. CI runs this same script on Arch, whose current Qt gives
`qmllint` the type information it needs; the tools are listed in the lint job
in `.github/workflows/build.yml`.

The C++ is checked while it compiles. `ci/build-plugin.sh` builds the settings
page with [clazy](https://invent.kde.org/sdk/clazy), KDE's Qt-aware static
analyser, as the compiler and warnings as errors, which catches Qt lifetime
mistakes such as a lambda connected without a context object. Those are the
binaries that ship. To run it locally:

```sh
podman run --rm -v "$PWD":/src -w /src debian:trixie bash ci/build-plugin.sh
```

## Releases

```sh
git tag -a v1.2.3 -m "v1.2.3"
git push origin v1.2.3
```

CI builds the settings page on Debian 13 for x86_64 and ARM64, loads each
build on Debian 13, Ubuntu 26.04 and Fedora 44, and publishes a GitHub release
with both plugins and `SHA256SUMS` only if every check and load test passes.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
