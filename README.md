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

KDE Plasma 6. Nothing else is needed for the script itself.

Ubuntu 24.04 ships Plasma 5, which is not supported; Ubuntu releases with
Plasma 6 start at 25.04.

### 2. Settings page build tools (optional)

The settings page is a compiled plugin, so building it needs a compiler and
the Qt and KDE development packages. Skip this step if you are fine editing
the settings as plain text instead.

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

This builds the settings page and asks for root to place it in Qt's plugin
directory. Everything else is installed for your user only.

Without the settings page, install with:

```sh
./install.sh --script-only
```

The settings then open as a plain text editor instead of a form.

Either way, add your applications in **System Settings → Window Management →
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

The settings page is only an editor for that value, which is why
`--script-only` can offer the same settings as plain text.

## Compatibility

The script half is plain JavaScript and depends only on KWin's scripting API.
It targets KWin 6.

The settings page is a QML form in a small compiled plugin. The plugin links
against Qt 6 and KDE Frameworks 6 but no KWin library, so Plasma and KWin
updates cannot break it. Qt and KDE Frameworks both keep ABI stable across a
major version, so it keeps working through 6.x updates. A future Qt 7 and
Frameworks 7 transition would need a rebuild, and until then
`install.sh --script-only` gives you the text editor fallback.

## Checks

```sh
./check.sh
```

CI runs this same script. The C++ goes through
[clazy](https://invent.kde.org/sdk/clazy), KDE's Qt-aware static analyser,
with warnings as errors, which catches Qt lifetime mistakes such as a lambda
connected without a context object. The QML goes through `qmllint` with
unknown properties made fatal, and the shell scripts through ShellCheck.

Local runs need `clazy`, `shellcheck`, `nodejs`, `qt6-declarative-dev-tools`
and the QML modules the form imports, as listed in
the checks job in `.github/workflows/build.yml`.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
