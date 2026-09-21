# Kwake

Quake-style toggling for any application on KDE Plasma. Kwake is a KWin script
that gives chosen applications a global shortcut: press it to bring the
application's window up, press it again to put it away.

Applications are managed from a settings page in System Settings: one row each,
with a **Detect Window** button that fills in a window's class when you click
the window, the way KWin Rules does.

Nothing is configured out of the box. No shortcuts exist until you add an
application.

## Install

Kwake needs KDE Plasma 6. Ubuntu 24.04 ships Plasma 5, which is not supported;
Ubuntu releases with Plasma 6 start at 25.04.

Download the installer from the latest release and run it:

```sh
gh release download --repo zakius/kwake --pattern kwake.run
sh kwake.run
```

`kwake.run` carries everything: the KWin script and the settings page for
x86_64 and ARM64. It checks its own SHA256 checksum before unpacking, then asks
for root to place the settings page next to KWin's own plugins. Everything else
is installed for your user only. It installs only what it carries and never
goes online. While the repository is private, download it with `gh` as above or
from the release page while logged in.

Then add your applications in **System Settings → Window Management → KWin
Scripts**, using the settings icon next to Kwake. Restart System Settings first
if it was open during the install.

### Updating

```sh
sh kwake.run -- --online
```

This downloads the latest release's installer, checks it against the release's
`SHA256SUMS` and runs it. Options for the installer go after `--`; the ones
before it belong to the `.run` wrapper itself. `sh kwake.run --info` shows
which release a file is.

## Uninstall

```sh
sh kwake.run -- --uninstall
```

or `./uninstall.sh` from a git checkout. This puts any hidden windows back on
the taskbar and unregisters the shortcuts, so nothing is left behind in the
shortcuts editor. It also deletes your list of applications.

## How it behaves

- Press an application's shortcut and its window is raised and focused, while
  the windows of the other applications in your list are minimised.
- Press it again while that window has focus and it is minimised. Focus moves
  to the last application in your list whose window is not minimised.
- If the application is not running, the shortcut does nothing; Kwake does not
  start applications.
- Windows of applications in your list are kept off the taskbar, since the
  shortcut is how you reach them. They go back on the taskbar as soon as you
  remove the application.

Each row matches windows by class and, optionally, by title. Both are
case-insensitive substring matches, so `ghostty` matches
`com.mitchellh.ghostty`. If several windows match a row, Kwake toggles only one
of them.

## Settings

Saving applies at once. The script re-reads its configuration and registers,
rebinds or drops shortcuts in place, so there is nothing to reload and no need
to log out.

Settings live in `kwinrc` under `[Script-kwake]`, as one line per application
in the key `Entries`:

```
Name | window class | title | shortcut
```

## Building from source

The release installer covers x86_64 and ARM64. Build the settings page yourself
for another CPU type or to try changes that are not released yet.

Build tools on Debian and Ubuntu:

```sh
sudo apt install build-essential cmake extra-cmake-modules \
    qt6-base-dev qt6-declarative-dev \
    libkf6coreaddons-dev libkf6config-dev libkf6kcmutils-dev
```

On Fedora:

```sh
sudo dnf install gcc-c++ cmake extra-cmake-modules \
    qt6-qtbase-devel qt6-qtdeclarative-devel \
    kf6-kcoreaddons-devel kf6-kconfig-devel kf6-kcmutils-devel
```

Tested on Debian 13, Ubuntu 26.04 and Fedora 44.

Build from the repository root, then install the result:

```sh
cmake -S kcm -B kcm/build -DCMAKE_BUILD_TYPE=Release
cmake --build kcm/build
./install.sh --plugin kcm/build/bin/kwin/effects/configs/kwake.so
```

`./install.sh --online` from a checkout installs the latest release instead.
Without either option, a checkout has no settings page to install and stops
before changing anything.

## Compatibility

The script is plain JavaScript and depends only on KWin's scripting API. It
targets KWin 6.

The settings page is a QML form in a small compiled plugin. The plugin links
against Qt 6 and KDE Frameworks 6 but no KWin library, so Plasma and KWin
updates cannot break it. Qt and KDE Frameworks both keep ABI stable across a
major version, so it keeps working through 6.x updates. Release builds load on
any system with Qt 6.8 and KDE Frameworks 6.13 or newer. A future Qt 7 and
Frameworks 7 transition would need a rebuild.

## Development

### Checks

```sh
./check.sh
```

This runs the script against a fake KWin (`test_main.js`, covering toggling,
shortcut changes and taskbar restore), `qmllint` on the settings form with
unknown properties made fatal, ShellCheck on the shell scripts, and a check
that the metadata points the settings page at the right plugin. It needs
`node`, `shellcheck` and `qmllint`. CI runs it on Arch, whose current Qt gives
`qmllint` the type information it needs.

The C++ is checked while it compiles. `ci/build-plugin.sh` builds the settings
page with [clazy](https://invent.kde.org/sdk/clazy), KDE's Qt-aware static
analyser, as the compiler and warnings as errors, which catches Qt lifetime
mistakes such as a lambda connected without a context object. Those are the
binaries that ship. To run it locally:

```sh
podman run --rm -v "$PWD":/src -w /src debian:trixie bash ci/build-plugin.sh
```

### Releases

```sh
git tag -a v1.2.3 -m "v1.2.3"
git push origin v1.2.3
```

CI builds the settings page on Debian 13 for x86_64 and ARM64, loads each build
on Debian 13, Ubuntu 26.04 and Fedora 44, and only if every check and load test
passes publishes a GitHub release with `kwake.run` and `SHA256SUMS`. The `.run`
file is built by makeself from `ci/make-bundle.sh`; never edit one by hand.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
