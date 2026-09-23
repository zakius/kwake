# Kwake

Quake-style toggling for any application on KDE Plasma. Kwake is a KWin script
that gives chosen applications a global shortcut: press it to bring the
application's window up, press it again to put it away.

You manage applications on a settings page in System Settings, one row each.
A **Detect Window** button fills in a window's class when you click the window,
the way KWin Rules does. Kwake ships with no applications and registers no
shortcuts until you add one.

## Install

Kwake needs KDE Plasma 6 with Qt 6.8 and KDE Frameworks 6.13 or newer, such as
Debian 13, Ubuntu 25.10 or Fedora 44. Ubuntu 24.04 (Plasma 5) and 25.04
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
with the settings icon next to Kwake.

To update, install a newer package the same way. Running sessions switch to the
new version at once. The package also replaces an earlier install from
`kwake.run` and keeps its list of applications.

### Other distributions

```sh
curl -LO https://github.com/zakius/kwake/releases/latest/download/kwake.run
sh kwake.run
```

`kwake.run` contains the KWin script and the settings page for x86_64 and
ARM64. It verifies its own SHA256 checksum before it unpacks. It asks for root
to put the settings page next to KWin's own plugins and installs everything
else for your user only. It does not download anything.

Then add your applications in **System Settings → Window Management → KWin
Scripts**, using the settings icon next to Kwake. If System Settings was open
during the install, restart it first.

To update:

```sh
sh kwake.run -- --online
```

This downloads the latest release's installer, checks it against the release's
`SHA256SUMS` and runs it. Options after `--` go to the installer. Options
before it go to the `.run` wrapper. `sh kwake.run --info` shows the release of
a file.

## Uninstall

Remove a package with `sudo apt remove kwake` or `sudo dnf remove kwake`. This
puts hidden windows back on the taskbar. Each user's list of applications stays
in their `kwinrc`.

Remove an install from `kwake.run` with:

```sh
sh kwake.run -- --uninstall
```

From a git checkout, run `./uninstall.sh`. This puts hidden windows back on the
taskbar, unregisters the shortcuts and deletes your list of applications. The
settings page is shared by all users on the machine, so it stays installed. To
remove it as well, add `--remove-system-plugin`. This needs root.

## How it behaves

- Press an application's shortcut to raise and focus its window. Kwake
  minimises the windows of the other applications in your list. A window on
  another virtual desktop moves to the current one.
- Press the shortcut again while the window has focus to minimise it. Focus
  moves to the last application in your list with a window that is not
  minimised.
- If the application is not running, the shortcut does nothing. Kwake does not
  start applications.

Each row matches an exact window class, ignoring case. **Detect Window** fills
it in. The optional title filter is a case-insensitive substring.

When several windows match, Kwake picks the focused one, or else the topmost
one. It keeps that window, even if its title changes, until the window closes.
Then it picks again by the same rule. A change to a row's class or title filter
also makes it pick again.

### Taskbar

Kwake removes the window it manages from the taskbar, but only for rows with a
shortcut set in Kwake's settings. Other matching windows keep their taskbar
buttons. A shortcut set only in KDE's shortcut editor toggles the window but
leaves its taskbar button visible.

Kwake gives back the taskbar buttons it removed when you remove a row, clear
its shortcut, or disable Kwake in KWin Scripts. Windows that hid their own
taskbar button keep that state. Your rows stay saved while Kwake is disabled.

## Settings

Saving applies at once. The script re-reads its configuration and registers,
changes or drops shortcuts in place. You do not need to reload anything or log
out.

Settings live in `kwinrc` under `[Script-kwake]`, one line per application in
the key `Entries`:

```
Name | window class | title | shortcut
```

Each name becomes a shortcut id: `kwake_` followed by the name, with every
character other than ASCII letters, digits, `_` and `-` replaced by `_`. If two
names give the same id, Kwake uses only the first entry. The settings page
warns about this.

## Compatibility

Kwake targets KWin 6. The settings page links against Qt 6 and KDE Frameworks 6
but not against KWin. Release builds use Debian 13's Qt 6.8 and Frameworks
6.13.

Each release is tested on Debian 13, Ubuntu 26.04 and Fedora 44, for x86_64
and ARM64: the package installs and the settings page's libraries resolve.
The script's enable, disable and shortcut handling is tested in a headless
KWin on Debian 13. These tests do not open the settings page in a live Plasma
session.

Newer Qt 6 and Frameworks 6 versions are expected to work, subject to the
[Qt plugin compatibility rules](https://doc.qt.io/qt-6/deployment-plugins.html)
and the [KDE Frameworks compatibility policy](https://community.kde.org/Frameworks/Policies).
Qt 7 or Frameworks 7 will need a rebuild.

## Building from source

Build the settings page yourself for a CPU other than x86_64 and ARM64, or to
try unreleased changes.

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

Build from the repository root, then install the result:

```sh
cmake -S kcm -B kcm/build -DCMAKE_BUILD_TYPE=Release
cmake --build kcm/build
./install.sh --plugin kcm/build/bin/kwin/effects/configs/kwake.so
```

`./install.sh --online` from a checkout installs the latest release instead.
Without either option, `install.sh` in a checkout has no settings page to
install and stops before it changes anything.

## Development

### Checks

```sh
./check.sh
```

This needs `node`, `shellcheck` and `qmllint`, and runs:

- the script against a fake KWin (`test_main.js`): toggling, shortcut changes
  and taskbar restore
- `qmllint` on the settings form, with unknown properties as errors
- ShellCheck on the shell scripts, and isolated uninstall tests
- a check that the metadata points the settings page at the right plugin

CI runs it on Arch, whose current Qt gives `qmllint` the type information it
needs.

To test the script lifecycle in a separate headless KWin session:

```sh
python3 tests/test_lifecycle.py
```

This needs `kwin_wayland`, `kdialog`, `qdbus6`, `kwriteconfig6`,
`dbus-run-session` and Python 3. It uses temporary configuration and a private
D-Bus session, so your desktop is not affected. It tests real shortcut
activation, disable and re-enable, direct unload, and taskbar restore.

`ci/build-plugin.sh` compiles the settings page with
[clazy](https://invent.kde.org/sdk/clazy), KDE's Qt-aware static analyser, and
treats warnings as errors. This catches Qt lifetime mistakes such as a lambda
connected without a context object. The binaries from this build are the ones
that ship. To run it locally:

```sh
podman run --rm -v "$PWD":/src -w /src debian:trixie bash ci/build-plugin.sh
```

### Releases

```sh
git tag -a v1.2.3 -m "v1.2.3"
git push origin v1.2.3
```

For a tag, CI does the following:

1. Builds the settings page with `ci/build-plugin.sh` on Debian 13, for x86_64
   and ARM64. `dpkg-shlibdeps` records the `.deb` dependencies in the same step.
2. Packages it with [nfpm](https://nfpm.goreleaser.com/) in
   `ci/make-packages.sh`.
3. Installs the packages on Debian 13, Ubuntu 26.04 and Fedora 44 and checks
   that the plugin's libraries resolve (`ci/load-test.sh`).
4. Runs `check.sh` and the lifecycle test.
5. Builds `kwake.run` with makeself in `ci/make-bundle.sh`, and publishes it
   with the packages and `SHA256SUMS`.

Do not edit a `.run` file by hand.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
