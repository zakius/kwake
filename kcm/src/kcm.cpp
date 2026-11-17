/*
    Config page for the Kwake KWin script.

    The script stores its applications as one line per entry in
    kwinrc [Script-kwake] Entries:

        Name | resourceClass | caption | shortcut

    The form lives in ui/main.qml, which parses and serialises that string.
    This class loads and saves it, drops the saved binding of every shortcut a
    save changes, and runs the window picker. QML cannot reach the last two on
    its own because they need D-Bus.
*/

#include <KConfigGroup>
#include <KPluginFactory>
#include <KQuickConfigModule>
#include <KSharedConfig>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QHash>
#include <QKeySequence>

using namespace Qt::StringLiterals;

namespace
{
constexpr auto kConfigFile = "kwinrc"_L1;
constexpr auto kConfigGroup = "Script-kwake"_L1;
constexpr auto kConfigKey = "Entries"_L1;

// Shortcut id -> shortcut for every row the script acts on. This repeats the
// rules of parseEntries() in script/contents/code/main.js and must match them.
QHash<QString, QString> shortcutsById(const QString &entries)
{
    QHash<QString, QString> shortcuts;
    QStringList used;
    const QStringList lines = entries.split(u'\n');
    for (const QString &line : lines) {
        QStringList fields;
        const QStringList rawFields = line.split(u'|');
        for (const QString &field : rawFields) {
            fields.append(field.trimmed());
        }
        if (fields.size() < 2 || fields.at(0).isEmpty() || fields.at(1).isEmpty()) {
            continue;
        }

        QString id = u"kwake_"_s;
        const QString name = fields.at(0);
        for (const QChar ch : name) {
            const bool letter = (ch >= u'a' && ch <= u'z') || (ch >= u'A' && ch <= u'Z');
            const bool digit = ch >= u'0' && ch <= u'9';
            id.append(letter || digit || ch == u'_' || ch == u'-' ? ch : QChar(u'_'));
        }
        if (shortcuts.contains(id)) {
            continue;
        }

        QString shortcut = fields.mid(3).join(u'|');
        if (used.contains(shortcut)) {
            shortcut.clear();
        }
        if (!shortcut.isEmpty()) {
            used.append(shortcut);
        }
        shortcuts.insert(id, shortcut);
    }
    return shortcuts;
}
}

class KwakeKCM : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QString entries READ entries WRITE setEntries NOTIFY entriesChanged)

public:
    KwakeKCM(QObject *parent, const KPluginMetaData &data)
        : KQuickConfigModule(parent, data)
    {
        setButtons(Apply | Default);
    }

    QString entries() const
    {
        return m_entries;
    }

    void setEntries(const QString &entries)
    {
        if (m_entries != entries) {
            m_entries = entries;
            Q_EMIT entriesChanged();
        }
        // Not only on a change: load() must set these for an unchanged value too.
        setNeedsSave(m_entries != m_saved);
        setRepresentsDefaults(m_entries.isEmpty());
    }

    void load() override
    {
        m_saved = KSharedConfig::openConfig(kConfigFile)->group(kConfigGroup).readEntry(kConfigKey, QString());
        setEntries(m_saved);
    }

    void save() override
    {
        auto config = KSharedConfig::openConfig(kConfigFile);
        config->group(kConfigGroup).writeEntry(kConfigKey, m_entries);
        config->sync();

        // KGlobalAccel prefers the binding it has saved over the one an action
        // registers with. The script drops the saved one before it registers a
        // changed shortcut, but only while it runs, so a change saved while
        // Kwake is disabled would never take effect.
        const QHash<QString, QString> before = shortcutsById(m_saved);
        const QHash<QString, QString> after = shortcutsById(m_entries);
        for (auto it = before.cbegin(); it != before.cend(); ++it) {
            if (after.contains(it.key()) && after.value(it.key()) == it.value()) {
                continue;
            }
            auto unregister = QDBusMessage::createMethodCall(u"org.kde.kglobalaccel"_s, u"/kglobalaccel"_s, u"org.kde.KGlobalAccel"_s, u"unregister"_s);
            unregister.setArguments({u"kwin"_s, it.key()});
            QDBusConnection::sessionBus().send(unregister);
        }

        m_saved = m_entries;
        setNeedsSave(false);

        // The script listens for this and re-registers shortcuts in place.
        QDBusConnection::sessionBus().send(
            QDBusMessage::createMethodCall(u"org.kde.KWin"_s, u"/KWin"_s, u"org.kde.KWin"_s, u"reconfigure"_s));
    }

    void defaults() override
    {
        setEntries(QString());
    }

    // QML has no value type for QKeySequence, so the shortcut recorder can only
    // be fed and read through these.
    Q_INVOKABLE QKeySequence toSequence(const QString &text) const
    {
        return QKeySequence::fromString(text, QKeySequence::PortableText);
    }

    Q_INVOKABLE QString toText(const QKeySequence &sequence) const
    {
        return sequence.toString(QKeySequence::PortableText);
    }

    // The same picker KWin Rules uses: KWin takes over the pointer until a
    // window is clicked. The answer comes back tagged with requestId rather
    // than aimed at a QML object, because the row that asked may have been
    // removed by the time the user clicks.
    Q_INVOKABLE void detectWindow(const QString &requestId)
    {
        const auto message = QDBusMessage::createMethodCall(u"org.kde.KWin"_s, u"/KWin"_s, u"org.kde.KWin"_s, u"queryWindowInfo"_s);
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, requestId](QDBusPendingCallWatcher *call) {
            call->deleteLater();
            const QDBusPendingReply<QVariantMap> reply = *call;
            if (reply.isError()) {
                return; // the user pressed Escape
            }
            Q_EMIT windowDetected(requestId, reply.value().value(u"resourceClass"_s).toString());
        });
    }

Q_SIGNALS:
    void entriesChanged();
    void windowDetected(const QString &requestId, const QString &resourceClass);

private:
    QString m_entries;
    QString m_saved;
};

K_PLUGIN_CLASS_WITH_JSON(KwakeKCM, "metadata.json")

#include "kcm.moc"
