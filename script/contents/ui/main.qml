import QtQml
import org.kde.kwin 3.0
import "../code/main.js" as Logic

QtObject {
    id: root

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
