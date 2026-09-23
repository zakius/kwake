#!/bin/sh
# Package preremove: unloads Kwake in running sessions, which gives back the
# windows it hid. Upgrades keep it loaded; postinstall reloads it instead.
set -e
id=kwake

case "$1" in remove | 0) ;; *) exit 0 ;; esac
getent passwd | while IFS=: read -r user _ uid _ _ _ _; do
    [ "$uid" -ge 1000 ] 2>/dev/null && [ -S "/run/user/$uid/bus" ] || continue
    busctl --user -M "$user@.host" call org.kde.KWin /Scripting org.kde.kwin.Scripting \
        unloadScript s "$id" >/dev/null 2>&1 || true
done
