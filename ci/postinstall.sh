#!/bin/sh
# Package postinstall: takes over from a per-user install.sh copy, which would
# otherwise shadow this one, and reloads Kwake in running sessions that use it.
# Each user still turns Kwake on in System Settings > KWin Scripts.
set -e
id=kwake

# Calls a method of KWin's scripting interface in the given user's session.
kwin() {
    session_user=$1
    shift
    busctl --user -M "$session_user@.host" call org.kde.KWin /Scripting org.kde.kwin.Scripting "$@" 2>/dev/null
}

# ponytail: only default XDG_DATA_HOME locations are cleaned up.
getent passwd | while IFS=: read -r user _ uid _ _ home _; do
    [ "$uid" -ge 1000 ] 2>/dev/null || continue
    user_script="$home/.local/share/kwin/scripts/$id"
    old_version=""
    if [ -f "$user_script/metadata.json" ]; then
        old_version=$(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' "$user_script/metadata.json" 2>/dev/null || true)
    fi
    # As the owner, so a symlink in their home cannot point root's rm elsewhere.
    if [ -e "$user_script" ] || [ -L "$user_script" ]; then
        runuser -u "$user" -- rm -rf "$user_script" || true
    fi
    [ -S "/run/user/$uid/bus" ] || continue
    kwin "$user" isScriptLoaded s "$id" | grep -q true || continue
    # Kwake 3.1 and earlier only restore taskbar buttons when their list is emptied.
    if [ -n "$old_version" ] \
        && [ "$(printf '%s\n' "$old_version" 3.2.0 | sort -V | head -n 1)" != "3.2.0" ] \
        && command -v kreadconfig6 >/dev/null 2>&1 \
        && command -v kwriteconfig6 >/dev/null 2>&1; then
        saved_entries=$(runuser -u "$user" -- kreadconfig6 --file kwinrc --group Script-kwake --key Entries 2>/dev/null || true)
        runuser -u "$user" -- kwriteconfig6 --file kwinrc --group Script-kwake --key Entries "" 2>/dev/null || true
        busctl --user -M "$user@.host" call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true
        sleep 2
        runuser -u "$user" -- kwriteconfig6 --file kwinrc --group Script-kwake --key Entries -- "$saved_entries" 2>/dev/null || true
    fi
    kwin "$user" unloadScript s "$id" >/dev/null || true
    # Unloading is deferred, and start skips a name that is still loaded.
    i=0
    while kwin "$user" isScriptLoaded s "$id" | grep -q true && [ "$i" -lt 50 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    kwin "$user" start >/dev/null || true
done
