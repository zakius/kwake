import QtQml
import org.kde.kwin 3.0
import "../code/entries.mjs" as Entries
import "../code/main.js" as Logic

QtObject {
    id: root

    readonly property var entries: Entries
    readonly property var workspace: Workspace
    readonly property var options: Options
    property Component shortcutComponent: ShortcutHandler {}
    property Component dbusComponent: DBusCall {}

    function readConfig(key, fallback) {
        return KWin.readConfig(key, fallback)
    }

    function registerShortcut(id, label, sequence, callback) {
        const handler = shortcutComponent.createObject(root, {
            name: id, text: label, sequence: sequence
        })
        handler.activated.connect(callback)
        return handler
    }

    function destroyShortcut(handler, onDestroyed) {
        if (!handler) {
            if (onDestroyed) onDestroyed()
            return
        }
        // Component.destruction fires before QObject::~QObject() deletes child
        // objects (ShortcutHandler's QAction). Deferring with Qt.callLater runs
        // onDestroyed after ~QAction() has removed the action from KGlobalAccel
        // and sent setInactive, so a replacement handler is never deactivated.
        if (onDestroyed) {
            handler.Component.destruction.connect(() => Qt.callLater(onDestroyed))
        }
        handler.destroy()
    }

    function callDBus(service, path, dbusInterface, method, ...args) {
        const callback = typeof args[args.length - 1] === "function" ? args.pop() : null
        const call = dbusComponent.createObject(root, {
            service: service, path: path, dbusInterface: dbusInterface,
            method: method, arguments: args
        })
        if (callback) call.finished.connect(values => callback(...values))
        call.finished.connect(() => call.destroy())
        call.failed.connect(() => call.destroy())
        call.call()
    }

    function logMessage(message) {
        console.log(message)
    }

    Component.onCompleted: Logic.start(root)
    Component.onDestruction: Logic.stop()
}
