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

Kwake needs KDE Plasma 6 with Qt 6.8 and KDE Frameworks 6.13 or newer, such as
Debian 13 or Ubuntu 25.10 and later. Ubuntu 24.04 (Plasma 5) and 25.04
(Frameworks 6.12) are too old.

### Debian, Ubuntu and Fedora

```sh
# Debian and Ubuntu (kwake-arm64.deb on ARM64)
curl -LO https://github.com/zakius/kwake/releases/latest/download/kwake-amd64.deb
sudo apt install ./kwake-amd64.deb

# Fedora (kwake-aarch64.rpm on ARM64)
curl -LO https://github.com/zakius/kwake/releases/latest/download/kwake-x86_64.rpm
sudo dnf install ./kwake-x86_64.rpm
```

The package installs Kwake for every user on the machine. Each user turns it on
in **System Settings → Window Management → KWin Scripts** and adds applications
with the settings icon next to Kwake. The package replaces a copy that
`kwake.run` installed earlier; your list of applications is kept.

To update, install a newer package the same way. Sessions where Kwake is
running switch to the new version at once.

### Other distributions

Download the installer from the latest release and run it:

```sh
curl -LO https://github.com/zakius/kwake/releases/latest/download/kwake.run
sh kwake.run
```

`kwake.run` carries everything: the KWin script and the settings page for
x86_64 and ARM64. It checks its own SHA256 checksum before unpacking, then asks
for root to place the settings page next to KWin's own plugins. Everything else
is installed for your user only. It installs only what it carries and never
goes online. You can also download it from the project's Releases page.

Then add your applications in **System Settings → Window Management → KWin
Scripts**, using the settings icon next to Kwake. Restart System Settings first
if it was open during the install.

#### Updating

```sh
sh kwake.run -- --online
```

This downloads the latest release's installer, checks it against the release's
`SHA256SUMS` and runs it. Options for the installer go after `--`; the ones
before it belong to the `.run` wrapper itself. `sh kwake.run --info` shows
which release a file is.

## Uninstall

A package is removed with `sudo apt remove kwake` or `sudo dnf remove kwake`.
This puts any hidden windows back on the taskbar. Each user's list of
applications stays in their `kwinrc`.

For an install from `kwake.run`:

```sh
sh kwake.run -- --uninstall
```

or `./uninstall.sh` from a git checkout. This puts any hidden windows back on
the taskbar and unregisters the shortcuts, so nothing is left behind in the
shortcuts editor. It also deletes your list of applications.
The system-wide settings plugin stays installed for other users.

To also remove the shared settings plugin, run:

```sh
sh kwake.run -- --uninstall --remove-system-plugin
```

From a checkout, use `./uninstall.sh --remove-system-plugin`. This requires
root and removes the settings page for every user on the machine.

## How it behaves

- Press an application's shortcut and its window is raised and focused, while
  the windows of the other applications in your list are minimised. A window
  on another virtual desktop is moved to the current one.
- Press it again while that window has focus and it is minimised. Focus moves
  to the last application in your list whose window is not minimised.
- If the application is not running, the shortcut does nothing; Kwake does not
  start applications.
- Selected windows with a shortcut configured in Kwake stay off the taskbar.
  Removing an entry or clearing its shortcut restores windows that Kwake hid.

Each row requires an exact window class, ignoring case. Use **Detect Window**
to fill it in. The optional title filter is a case-insensitive substring.
Replace shortened class names from hand-written configurations with the full
class shown by the picker.

Kwake selects the focused matching window, or the topmost match if none has
focus. It retains that window by its KWin identifier until it closes, even if
the title changes. It then selects a replacement by the same rule. If nothing
matches, the shortcut silently does nothing.

For entries with a shortcut, only the selected window is hidden from the
taskbar. Other matching windows keep their taskbar state. Changing a row's class or title filter selects again.

Disabling Kwake in KWin Scripts restores the taskbar buttons it hid.
Windows that already hid their own taskbar buttons keep that state.
Your application entries remain available when you re-enable Kwake.

An entry with no shortcut in Kwake's settings keeps its taskbar button.
Assigning a shortcut only in KDE's shortcut editor lets you toggle the window
but leaves its taskbar button visible.

## Settings

Saving applies at once. The script re-reads its configuration and registers,
rebinds or drops shortcuts in place, so there is nothing to reload and no need
to log out.

Settings live in `kwinrc` under `[Script-kwake]`, as one line per application
in the key `Entries`:

```
Name | window class | title | shortcut
```

Each name becomes a shortcut id: `kwake_` followed by the name, with every
character other than ASCII letters, digits, `_` and `-` replaced by `_`. If two
names give the same id, Kwake uses only the first entry. The settings page
warns about this.

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

CI checks shared-library compatibility on Debian 13, Ubuntu 26.04 and Fedora 44.

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

The script uses a QML entry point with JavaScript window-management logic.
It targets KWin 6. The QML destruction handler restores taskbar state and
disconnects window callbacks when the script unloads.

The settings page links against Qt 6 and KDE Frameworks 6 without linking
against KWin. Release builds use Debian 13's Qt 6.8 and Frameworks 6.13.
CI installs the `.deb` or `.rpm` with the distribution's package manager and
checks the installed plugin's shared-library dependencies and symbols on
Debian 13, Ubuntu 26.04 and Fedora 44, for x86_64 and ARM64. These checks do not open
the settings page or test a live Plasma session.

Newer Qt 6 and Frameworks 6 versions are expected to work, subject to the
[Qt plugin compatibility rules](https://doc.qt.io/qt-6/deployment-plugins.html)
and [KDE Frameworks compatibility policy](https://community.kde.org/Frameworks/Policies).
Plasma integration still needs testing after updates. Other distributions are
not covered by the release checks. A Qt 7 or Frameworks 7 transition would
require a rebuild and compatibility testing.

## Development

### Checks

```sh
./check.sh
```

This runs the script against a fake KWin (`test_main.js`, covering toggling,
shortcut changes and taskbar restore), `qmllint` on the settings form with
unknown properties made fatal, ShellCheck on the shell scripts, isolated
uninstall tests, and a check that the metadata points the settings page at the right plugin. It needs
`node`, `shellcheck` and `qmllint`. CI runs it on Arch, whose current Qt gives
`qmllint` the type information it needs.

To test the script lifecycle in a separate headless KWin session:

```sh
python3 tests/test_lifecycle.py
```

This needs `kwin_wayland`, `kdialog`, `qdbus6`, `kwriteconfig6`, `dbus-run-session`
and Python 3. It uses temporary configuration and a private D-Bus session.
It checks real shortcut activation, disable/re-enable, direct unload, and
restoration of taskbar state without changing your desktop. CI runs this test
on Debian 13 before publishing a release.

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

CI builds the settings page on Debian 13 for x86_64 and ARM64, packages it with
[nfpm](https://nfpm.goreleaser.com/) (`ci/make-packages.sh`), and installs the
packages on Debian 13, Ubuntu 26.04 and Fedora 44 to check that their
dependencies resolve and the plugin loads. After all checks pass, CI publishes
a GitHub release with `kwake.run`, the `.deb` and `.rpm` packages, and
`SHA256SUMS`. Makeself builds the `.run` file from `ci/make-bundle.sh`.
Do not edit a `.run` file by hand. The `.deb` dependencies come from
`dpkg-shlibdeps` in `ci/build-plugin.sh`; the Qt floor is the Debian 13
build's.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
