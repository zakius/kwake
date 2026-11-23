#include <KConfigGroup>
#include <KPluginFactory>
#include <KQuickConfigModule>
#include <KSharedConfig>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QHash>
#include <QJSEngine>
#include <QJSValue>
#include <QKeySequence>

using namespace Qt::StringLiterals;

namespace
{
constexpr auto kConfigFile = "kwinrc"_L1;
constexpr auto kConfigGroup = "Script-kwake"_L1;
constexpr auto kConfigKey = "Entries"_L1;
}

class KwakeKCM : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QString entries READ entries WRITE setEntries NOTIFY entriesChanged)
    Q_PROPERTY(bool detecting READ detecting NOTIFY detectingChanged)

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

    bool detecting() const
    {
        return m_detecting;
    }

    void setEntries(const QString &entries)
    {
        if (m_entries != entries) {
            m_entries = entries;
            Q_EMIT entriesChanged();
        }
        setNeedsSave(m_entries != m_saved);
        setRepresentsDefaults(m_entries.isEmpty());
    }

    void load() override
    {
        auto config = KSharedConfig::openConfig(kConfigFile);
        // System Settings already holds a cached KSharedConfig for kwinrc, so
        // reparse to pick up changes made outside this process.
        config->reparseConfiguration();
        m_saved = config->group(kConfigGroup).readEntry(kConfigKey, QString());
        setEntries(m_saved);
    }

    void save() override
    {
        auto config = KSharedConfig::openConfig(kConfigFile);
        config->group(kConfigGroup).writeEntry(kConfigKey, m_entries);
        config->sync();

        // KGlobalAccel prefers the binding it has saved over the one an action
        // registers with.
        const QHash<QString, QString> before = shortcutsById(m_saved);
        const QHash<QString, QString> after = shortcutsById(m_entries);
        for (auto it = before.cbegin(); it != before.cend(); ++it) {
            if (after.contains(it.key()) && after.value(it.key()) == it.value()) {
                continue;
            }
            auto unregister = QDBusMessage::createMethodCall(u"org.kde.kglobalaccel"_s, u"/kglobalaccel"_s, u"org.kde.KGlobalAccel"_s, u"unregister"_s);
            unregister.setArguments({u"kwin"_s, it.key()});
            QDBusConnection::sessionBus().call(unregister, QDBus::Block, 2000);
        }

        m_saved = m_entries;
        setNeedsSave(false);

        QDBusConnection::sessionBus().send(
            QDBusMessage::createMethodCall(u"org.kde.KWin"_s, u"/KWin"_s, u"org.kde.KWin"_s, u"reconfigure"_s));
    }

    void defaults() override
    {
        setEntries(QString());
    }

    Q_INVOKABLE QKeySequence toSequence(const QString &text) const
    {
        return QKeySequence::fromString(text, QKeySequence::PortableText);
    }

    Q_INVOKABLE QString toText(const QKeySequence &sequence) const
    {
        return sequence.toString(QKeySequence::PortableText);
    }

    // The same picker KWin Rules uses: KWin takes over the pointer until a
    // window is clicked.
    Q_INVOKABLE void detectWindow(const QString &requestId)
    {
        if (m_detecting) {
            return;
        }
        m_detecting = true;
        Q_EMIT detectingChanged();

        const auto message = QDBusMessage::createMethodCall(u"org.kde.KWin"_s, u"/KWin"_s, u"org.kde.KWin"_s, u"queryWindowInfo"_s);
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, requestId](QDBusPendingCallWatcher *call) {
            call->deleteLater();
            m_detecting = false;
            Q_EMIT detectingChanged();
            const QDBusPendingReply<QVariantMap> reply = *call;
            if (reply.isError()) {
                return;
            }
            const QString resourceClass = reply.value().value(u"resourceClass"_s).toString();
            if (!resourceClass.isEmpty()) {
                Q_EMIT windowDetected(requestId, resourceClass);
            }
        });
    }

private:
    QHash<QString, QString> shortcutsById(const QString &entries) const
    {
        const QString parser = u":/kcm/"_s + metaData().pluginId() + u"/entries.mjs"_s;
        QJSEngine js;
        const QJSValue parsed = js.importModule(parser).property(u"parseEntries"_s).call({entries});
        if (parsed.isError() || parsed.isUndefined()) {
            qWarning() << "Kwake: cannot parse entries with" << parser << parsed.toString();
        }
        const QJSValue list = parsed.property(u"entries"_s);
        const int length = list.property(u"length"_s).toInt();
        QHash<QString, QString> shortcuts;
        for (int i = 0; i < length; ++i) {
            const QJSValue entry = list.property(i);
            shortcuts.insert(entry.property(u"id"_s).toString(), entry.property(u"shortcut"_s).toString());
        }
        return shortcuts;
    }

Q_SIGNALS:
    void entriesChanged();
    void detectingChanged();
    void windowDetected(const QString &requestId, const QString &resourceClass);

private:
    QString m_entries;
    QString m_saved;
    bool m_detecting = false;
};

K_PLUGIN_CLASS_WITH_JSON(KwakeKCM, "metadata.json")

#include "kcm.moc"
