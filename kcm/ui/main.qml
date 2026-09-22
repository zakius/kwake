/*
    The Kwake settings form. One row per application, kept in a
    ListModel and written back to kcm.entries as the line format the script
    reads: Name | resourceClass | caption | shortcut
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    id: root

    // Rows are matched to Detect Window answers by uid, never by index, since
    // rows can be added or removed while the picker is open.
    property int nextUid: 0
    // The last value this form wrote. Echoes of it are ignored, so typing never
    // rebuilds the model and steals focus from the field being edited.
    property string written: ""
    // Set when two names map to the same shortcut id; see findCollision().
    property string collision: ""

    ListModel {
        id: apps
    }

    // A separator or newline typed into a field would split it into bogus entries.
    function clean(text) {
        return text.replace(/[|\n]/g, "").trim()
    }

    function parse(text) {
        apps.clear()
        text.split("\n").forEach(line => {
            const fields = line.split("|").map(field => field.trim())
            if (!fields[0] || fields[0].startsWith("#")) {
                return
            }
            apps.append({
                uid: nextUid++,
                name: fields[0],
                windowClass: fields[1] ?? "",
                caption: fields[2] ?? "",
                // A shortcut on the | key contains the separator itself.
                shortcut: fields.slice(3).join("|"),
            })
        })
        collision = findCollision()
    }

    // The script builds each shortcut id from the name with this same rule and
    // ignores any later entry whose id is taken.
    function findCollision() {
        const seen = {}
        for (let i = 0; i < apps.count; ++i) {
            const app = apps.get(i)
            const name = clean(app.name)
            if (!name || !clean(app.windowClass)) {
                continue
            }
            const id = name.replace(/[^A-Za-z0-9_-]/g, "_")
            if (seen[id] !== undefined) {
                return i18n("“%1” and “%2” get the same shortcut, so Kwake ignores “%2”. Names differing only in spaces or non-ASCII letters collide; rename one of them.", seen[id], name)
            }
            seen[id] = name
        }
        return ""
    }

    function commit() {
        const lines = []
        for (let i = 0; i < apps.count; ++i) {
            const app = apps.get(i)
            if (clean(app.name)) {
                lines.push([clean(app.name), clean(app.windowClass), clean(app.caption), app.shortcut].join(" | "))
            }
        }
        collision = findCollision()
        written = lines.join("\n")
        kcm.entries = written
    }

    function removeApplication(index) {
        apps.remove(index)
        commit()
    }

    function addApplication() {
        apps.append({ uid: nextUid++, name: "", windowClass: "", caption: "", shortcut: "" })
    }

    Component.onCompleted: parse(kcm.entries)

    Connections {
        target: kcm

        // load() and defaults() replace the whole value; the form's own writes come back here too.
        function onEntriesChanged() {
            if (kcm.entries !== root.written) {
                root.written = kcm.entries
                root.parse(kcm.entries)
            }
        }

        function onWindowDetected(requestId, resourceClass) {
            for (let i = 0; i < apps.count; ++i) {
                if (String(apps.get(i).uid) !== requestId) {
                    continue
                }
                apps.setProperty(i, "windowClass", resourceClass)
                if (!clean(apps.get(i).name)) {
                    apps.setProperty(i, "name", resourceClass)
                }
                root.commit()
                return
            }
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18n("Each shortcut controls one window until it closes. Window class is an exact match, ignoring case; use Detect Window to fill it in. The optional title filter matches part of the title. Other matching windows stay on the taskbar.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.collision !== ""
            type: Kirigami.MessageType.Warning
            text: root.collision
        }

        Repeater {
            model: apps

            delegate: Kirigami.AbstractCard {
                id: card

                required property int index
                required property int uid
                required property string name
                required property string windowClass
                required property string caption
                required property string shortcut

                Layout.fillWidth: true

                contentItem: GridLayout {
                    columns: 4
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: i18n("Name:")
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: card.name
                        placeholderText: i18n("Shown in the shortcuts list")
                        onTextEdited: {
                            apps.setProperty(card.index, "name", text)
                            root.commit()
                        }
                    }
                    QQC2.Label {
                        text: i18n("Shortcut:")
                    }
                    // Remove sits at the end of the shortcut row, so the title
                    // field below can run the full width of this column.
                    RowLayout {
                        Layout.fillWidth: true
                        KQuickControls.KeySequenceItem {
                            id: recorder
                            keySequence: kcm.toSequence(card.shortcut)
                            onKeySequenceModified: {
                                apps.setProperty(card.index, "shortcut", kcm.toText(recorder.keySequence))
                                root.commit()
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        QQC2.Button {
                            icon.name: "edit-delete"
                            text: i18n("Remove")
                            onClicked: root.removeApplication(card.index)
                        }
                    }

                    QQC2.Label {
                        text: i18n("Window class:")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.TextField {
                            Layout.fillWidth: true
                            text: card.windowClass
                            placeholderText: i18n("Exact window class (required)")
                            onTextEdited: {
                                apps.setProperty(card.index, "windowClass", text)
                                root.commit()
                            }
                        }
                        QQC2.Button {
                            icon.name: "edit-find"
                            text: i18n("Detect Window…")
                            QQC2.ToolTip.text: i18n("Click a window to fill in its class")
                            QQC2.ToolTip.visible: hovered
                            onClicked: kcm.detectWindow(String(card.uid))
                        }
                    }
                    QQC2.Label {
                        text: i18n("Title contains:")
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: card.caption
                        placeholderText: i18n("Optional")
                        onTextEdited: {
                            apps.setProperty(card.index, "caption", text)
                            root.commit()
                        }
                    }
                }
            }
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            visible: apps.count === 0
            icon.name: "preferences-system-windows"
            text: i18n("No applications yet")
            explanation: i18n("Add one to give it a toggle shortcut.")
        }

        QQC2.Button {
            icon.name: "list-add"
            text: i18n("Add Application")
            onClicked: root.addApplication()
        }
    }
}
