#!/usr/bin/env python3
"""Exercise enable/disable in a private, headless KWin session."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]


def run_session(root):
    qdbus = shutil.which('qdbus6') or shutil.which('qdbus') or '/usr/lib/qt6/bin/qdbus'
    processes = []
    log_path = root / 'kwin.log'
    log = log_path.open('w')

    def command(*args):
        return subprocess.check_output(args, text=True, stderr=subprocess.PIPE, timeout=10).strip()

    def bus(path, method, *args):
        return command(qdbus, 'org.kde.KWin', path, method, *args)

    def wait_for(predicate):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if predicate():
                return
            if processes[0].poll() is not None:
                raise AssertionError('KWin exited')
            time.sleep(.05)
        raise AssertionError('Timed out waiting for KWin')

    counter = 0

    def inspect(setup=''):
        nonlocal counter
        counter += 1
        name = f'inspect-{counter}'
        marker = f'KWAKE_STATE_{counter} '
        script = root / f'{name}.js'
        script.write_text(setup + '\nprint(' + json.dumps(marker) + '+ JSON.stringify(workspace.stackingOrder.map(w => ({caption:w.caption, hidden:w.skipTaskbar, minimized:w.minimized}))));')
        script_id = bus('/Scripting', 'org.kde.kwin.Scripting.loadScript', str(script), name)
        bus('/Scripting/Script' + script_id, 'org.kde.kwin.Script.run')
        wait_for(lambda: marker in log_path.read_text())
        line = next(line.split(marker, 1)[1] for line in log_path.read_text().splitlines() if marker in line)
        bus('/Scripting', 'org.kde.kwin.Scripting.unloadScript', name)
        return json.loads(line)

    def enabled(value):
        command('kwriteconfig6', '--file', 'kwinrc', '--group', 'Plugins', '--key', 'kwakeEnabled', str(value).lower())
        bus('/KWin', 'org.kde.KWin.reconfigure')
        wait_for(lambda: bus('/Scripting', 'org.kde.kwin.Scripting.isScriptLoaded', 'kwake') == str(value).lower())

    try:
        command('kwriteconfig6', '--file', 'kwinrc', '--group', 'Plugins', '--key', 'kwakeEnabled', 'false')
        command('kwriteconfig6', '--file', 'kwinrc', '--group', 'Script-kwake', '--key', 'Entries',
                'Managed | org.kde.kdialog | Kwake managed | Meta+F10\nHidden | org.kde.kdialog | Kwake prehidden | Meta+F11')
        processes.append(subprocess.Popen(['kwin_wayland', '--virtual', '--no-lockscreen', '--no-kactivities', '--socket', 'kwake-test'], stdout=log, stderr=log))
        wait_for(lambda: subprocess.run([qdbus, 'org.kde.KWin', '/Scripting'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2).returncode == 0)
        for title in ('Kwake managed', 'Kwake untouched', 'Kwake prehidden'):
            processes.append(subprocess.Popen(['kdialog', '--title', title, '--msgbox', 'Disposable lifecycle test'],
                env=dict(os.environ, QT_QPA_PLATFORM='wayland', WAYLAND_DISPLAY='kwake-test'), stdout=log, stderr=log))
        wait_for(lambda: len(inspect()) == 3)
        state = inspect('for (const w of workspace.stackingOrder) if (w.caption.includes("Kwake prehidden")) w.skipTaskbar = true;')
        assert sum(w['hidden'] for w in state) == 1, state
        for cycle in range(3):
            enabled(True)
            wait_for(lambda: any(w['hidden'] and 'Kwake managed' in w['caption'] for w in inspect()))
            inspect('for (const w of workspace.stackingOrder) if (w.caption === "Kwake managed") w.minimized = true;')
            command(qdbus, 'org.kde.kglobalaccel', '/component/kwin', 'org.kde.kglobalaccel.Component.invokeShortcut', 'kwake_Managed')
            wait_for(lambda: not next(w['minimized'] for w in inspect() if w['caption'] == 'Kwake managed'))
            command(qdbus, 'org.kde.kglobalaccel', '/component/kwin', 'org.kde.kglobalaccel.Component.invokeShortcut', 'kwake_Managed')
            wait_for(lambda: next(w['minimized'] for w in inspect() if w['caption'] == 'Kwake managed'))
            if cycle == 2:
                bus('/Scripting', 'org.kde.kwin.Scripting.unloadScript', 'kwake')
                wait_for(lambda: bus('/Scripting', 'org.kde.kwin.Scripting.isScriptLoaded', 'kwake') == 'false')
            else:
                enabled(False)
            state = inspect()
            assert not next(w['hidden'] for w in state if 'Kwake managed' in w['caption']), state
            assert not next(w['hidden'] for w in state if 'Kwake untouched' in w['caption']), state
            assert next(w['hidden'] for w in state if 'Kwake prehidden' in w['caption']), state
            late = subprocess.Popen(['kdialog', '--title', 'Kwake managed late', '--msgbox', 'Disposable lifecycle test'],
                env=dict(os.environ, QT_QPA_PLATFORM='wayland', WAYLAND_DISPLAY='kwake-test'), stdout=log, stderr=log)
            processes.append(late)
            wait_for(lambda: len(inspect()) == 4)
            assert all(not w['hidden'] for w in inspect() if 'prehidden' not in w['caption'])
            late.terminate()
            late.wait(timeout=5)
            processes.remove(late)
            wait_for(lambda: len(inspect()) == 3)
        output = log_path.read_text()
        assert not any(error in output for error in ('TypeError:', 'ReferenceError:', 'Component failed to load')), output
        print('KWin lifecycle passed: shortcuts, disable/re-enable, direct unload, and owned taskbar restoration.')
    finally:
        for process in reversed(processes):
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        log.close()
        if sys.exc_info()[0]:
            print(log_path.read_text(), file=sys.stderr)


if len(sys.argv) == 2:
    run_session(Path(sys.argv[1]))
else:
    with tempfile.TemporaryDirectory(prefix='kwake-lifecycle-') as directory:
        root = Path(directory)
        for name in ('runtime', 'config', 'data', 'cache'):
            (root / name).mkdir(mode=0o700)
        shutil.copytree(REPO / 'script', root / 'data/kwin/scripts/kwake')
        env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), XDG_CONFIG_HOME=str(root / 'config'),
                   XDG_DATA_HOME=str(root / 'data'), XDG_CACHE_HOME=str(root / 'cache'),
                   QT_QPA_PLATFORM='offscreen', QT_NO_XDG_DESKTOP_PORTAL='1', QT_ACCESSIBILITY='0',
                   LIBGL_ALWAYS_SOFTWARE='1', KWIN_COMPOSE='Q')
        for name in ('DISPLAY', 'WAYLAND_DISPLAY', 'SESSION_MANAGER'):
            env.pop(name, None)
        result = subprocess.run(['dbus-run-session', '--', sys.executable, __file__, str(root)], env=env, capture_output=True, text=True, timeout=90)
        print(result.stdout, end='')
        if result.returncode:
            print(result.stderr, end='', file=sys.stderr)
        sys.exit(result.returncode)
