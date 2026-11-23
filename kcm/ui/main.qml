pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import "entries.mjs" as Entries

KCM.SimpleKCM {
    id: root

    property int nextUid: 0
    property string written: ""
    property string collision: ""

    ListModel {
        id: apps
    }

    function clean(text) {
        return text.replace(/[|\r\n]/g, "").trim()
    }

    function parse(text) {
        apps.clear()
        Entries.parseLines(text).forEach(row => {
            if (row.name) {
                apps.append(Object.assign({ uid: nextUid++ }, row))
            }
        })
        collision = findCollision(formText())
    }

    function formText() {
        const lines = []
        for (let i = 0; i < apps.count; ++i) {
            const app = apps.get(i)
            const row = { name: clean(app.name), resourceClass: clean(app.resourceClass), caption: clean(app.caption), shortcut: app.shortcut }
            if (row.name) {
                lines.push(Entries.formatLine(row))
            }
        }
        return lines.join("\n")
    }

    function findCollision(text) {
        const parsed = Entries.parseEntries(text)
        if (parsed.ignored.length) {
            const row = parsed.ignored[0]
            return i18n("“%1” and “%2” get the same shortcut id, so Kwake ignores “%2”. Names differing only in spaces or non-ASCII letters collide; rename one of them.", row.takenBy, row.name)
        }
        if (parsed.unbound.length) {
            const row = parsed.unbound[0]
            return i18n("“%1” and “%2” have the same shortcut, so it only works for “%1”. Give “%2” a different one.", row.takenBy, row.name)
        }
        for (let i = 0; i < apps.count; ++i) {
            const app = apps.get(i)
            if (!clean(app.name) && (clean(app.resourceClass) || clean(app.caption) || app.shortcut)) {
                return i18n("An application without a name will not be saved; fill in its name or remove it.")
            }
        }
        return ""
    }

    function commit() {
        written = formText()
        collision = findCollision(written)
        kcm.entries = written
    }

    function removeApplication(index) {
        apps.remove(index)
        commit()
    }

    function addApplication() {
        apps.append({ uid: nextUid++, name: "", resourceClass: "", caption: "", shortcut: "" })
    }

    Component.onCompleted: {
        written = kcm.entries
        parse(kcm.entries)
    }

    Connections {
        target: kcm

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
                apps.setProperty(i, "resourceClass", resourceClass)
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
                required property string resourceClass
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
                        validator: RegularExpressionValidator { regularExpression: /[^|\r\n]*/ }
                        onTextEdited: {
                            apps.setProperty(card.index, "name", text)
                            root.commit()
                        }
                    }
                    QQC2.Label {
                        text: i18n("Shortcut:")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        KQuickControls.KeySequenceItem {
                            id: recorder
                            // Do not let KeySequenceValidator steal global shortcuts
                            // immediately on "Reassign" before the user clicks Apply.
                            checkForConflictsAgainst: KQuickControls.ShortcutType.None
                            keySequence: kcm.toSequence(card.shortcut)
                            onKeySequenceModified: {
                                apps.setProperty(card.index, "shortcut", kcm.toText(recorder.keySequence))
                                root.commit()
                            }
                            Connections {
                                target: card
                                // KeySequenceItem's clear button assigns keySequence = "",
                                // breaking the declarative binding above; keep it in sync.
                                function onShortcutChanged() {
                                    recorder.keySequence = kcm.toSequence(card.shortcut)
                                }
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
                            text: card.resourceClass
                            placeholderText: i18n("Exact window class (required)")
                            validator: RegularExpressionValidator { regularExpression: /[^|\r\n]*/ }
                            onTextEdited: {
                                apps.setProperty(card.index, "resourceClass", text)
                                root.commit()
                            }
                        }
                        QQC2.Button {
                            icon.name: "edit-find"
                            text: i18n("Detect Window…")
                            enabled: !kcm.detecting
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
                        validator: RegularExpressionValidator { regularExpression: /[^|\r\n]*/ }
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
