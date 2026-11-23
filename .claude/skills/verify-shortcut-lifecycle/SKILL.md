---
name: verify-shortcut-lifecycle
description: Check every order of events in Kwake's global shortcut lifecycle (register, replace, remove, KCM save) with tests/shortcut_lifecycle.mjs. Use before you change shortcut handling in script/contents/code/main.js, the host functions in script/contents/ui/main.qml, or KwakeKCM::save() in kcm/src/kcm.cpp, and when a shortcut stops working, works twice or survives its row.
---

# Verify the shortcut lifecycle

## What it promises

After the settings page saves and every message has been handled, each configured row's shortcut is bound in kglobalaccel to the row's keys and is active, exactly one ShortcutHandler serves it, and removed rows leave no binding or handler behind.

When this breaks, a user's key does nothing, toggles the window twice (it opens and closes at once), or stays taken by a row they deleted.

## Run it

```sh
node tests/shortcut_lifecycle.mjs            # this checkout
node tests/shortcut_lifecycle.mjs <dir>      # another source tree, such as a `git archive` of an old commit
```

It takes under a second. `check.sh`, and so CI, runs it.

## How it works

The check loads the real `main.js` and the real `registerShortcut`, `destroyShortcut` and `callDBus` functions from `main.qml`, and runs them against a model of everything around them. Then it tries every order in which the actors can take their next step and checks the promise at each end state.

The model, and the code each part stands for:

- KWin's event loop runs one task at a time. Posted events (`handler.destroy()` deferred deletes, `Qt.callLater`) and incoming D-Bus messages interleave in any order.
- A deferred delete emits `Component.destruction` first and then destroys the QAction, which sends `setInactive` (the order the comment in `destroyShortcut` relies on).
- Creating a ShortcutHandler sends `register`. kglobalaccel keeps a saved binding over the keys an action registers with. So the settings page sets edited keys in kglobalaccel itself, and the script only re-creates the handler. The script unregisters a shortcut only when its row is gone.
- D-Bus delivers to each destination in the order the bus daemon received the messages: one queue into kglobalaccel, one into KWin.
- `KwakeKCM::save()` writes kwinrc, waits for `setForeignShortcutKeys` on every row whose keys changed or that is new, then sends `reconfigure`. `setForeignShortcutKeys` changes only a shortcut kglobalaccel already has. The check reads `kcm.cpp` to find how save writes to kglobalaccel. It also knows the `unregister` that older trees call, so it can replay them. It stops with an error if nothing matches.
- KWin rereads kwinrc only when it handles `reconfigure`.

Scenarios start with the script running and saved bindings in kglobalaccel, then apply one or two saves.

## Reading a result

- `ok` means no reachable end state breaks the promise in that scenario.
- `FAIL <scenario>: <violation>` is followed by the shortest trace that reaches it, step by step in the code's terms. Replay the trace by hand against the code before you call it a bug.
- `known` lines are violations that head already has and nobody has fixed yet. They are listed in `KNOWN` in the check. A fix makes its known line disappear, and the check fails until you delete that line.

A modeling error usually shows as a trace step the real system cannot take. Compare each step with the code and with the list above. Fix the model only when a step contradicts the real behavior, and say which fact was wrong. Do not weaken the promise or add to `KNOWN` to make a run pass.

## Proven able to fail

- 75ae7ae (`node tests/shortcut_lifecycle.mjs <archive of 75ae7ae>`): "kwake_A has 2 live handlers", the leaked QAction that d14f6a9 fixed.
- `destroyShortcut` calling `onDestroyed()` at once instead of after `Component.destruction`: "kwake_A is bound to Meta+3 but inactive", the `setInactive` race that d14f6a9 fixed.
- `main.js` without its `pending[id]` generation checks: a stale binding and a second live handler.
- 8af9933, where the settings page unregisters edited shortcuts: "kwake_A has no binding in kglobalaccel" after a change and change back, or a remove and re-add, before KWin rereads kwinrc (issue #7).

## Coverage record

- `script/contents/code/main.js`: `applyConfig`, `afterHandlerGone`, `start`, `stop`, `unregisterShortcut`.
- `script/contents/ui/main.qml`: `registerShortcut`, `destroyShortcut`, `callDBus`.
- `kcm/src/kcm.cpp`: `KwakeKCM::save`.

Not covered: window matching and toggling, the KDE shortcut editor changing a binding, the script being disabled or reloaded while a save runs, and kglobalaccel behavior beyond `register`, `setInactive`, `setForeignShortcutKeys`, `unregister` and `shortcutNames`. A real kglobalaccel applies the keys from `setForeignShortcutKeys`: `tests/test_lifecycle.py` saves with Kwake disabled, then saves with it running, and waits for each new binding. The real KWin run in `tests/test_lifecycle.py` covers what this model leaves out.

Last confirmed to describe the code at commit 5063af8. When any covered function changes after that commit, check that the model list above still matches the code. Then rerun the check, and move this commit forward only once both agree.
