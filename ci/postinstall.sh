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
    # As the owner, so a symlink in their home cannot point root's rm elsewhere.
    if [ -e "$home/.local/share/kwin/scripts/$id" ]; then
        runuser -u "$user" -- rm -rf "$home/.local/share/kwin/scripts/$id" || true
    fi
    [ -S "/run/user/$uid/bus" ] || continue
    kwin "$user" isScriptLoaded s "$id" | grep -q true || continue
    kwin "$user" unloadScript s "$id" >/dev/null || true
    # Unloading is deferred, and start skips a name that is still loaded.
    i=0
    while kwin "$user" isScriptLoaded s "$id" | grep -q true && [ "$i" -lt 50 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    kwin "$user" start >/dev/null || true
done
