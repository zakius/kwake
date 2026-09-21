/*
    Config page for the Toggle Windows KWin script.

    The script stores its applications as one line per entry in
    kwinrc [Script-toggle_windows] Entries:

        Name | resourceClass | caption | shortcut

    The form lives in ui/main.qml, which parses and serialises that string.
    This class only loads and saves it, and runs the window picker, which QML
    cannot reach on its own because it needs D-Bus.
*/

#include <KConfigGroup>
#include <KPluginFactory>
#include <KQuickConfigModule>
#include <KSharedConfig>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QKeySequence>

using namespace Qt::StringLiterals;

namespace
{
constexpr auto kConfigFile = "kwinrc"_L1;
constexpr auto kConfigGroup = "Script-toggle_windows"_L1;
constexpr auto kConfigKey = "Entries"_L1;
}

class ToggleWindowsKCM : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QString entries READ entries WRITE setEntries NOTIFY entriesChanged)

public:
    ToggleWindowsKCM(QObject *parent, const KPluginMetaData &data)
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
        if (m_entries == entries) {
            return;
        }
        m_entries = entries;
        Q_EMIT entriesChanged();
        setNeedsSave(m_entries != m_saved);
        setRepresentsDefaults(m_entries.isEmpty());
    }

    void load() override
    {
        m_saved = KSharedConfig::openConfig(kConfigFile)->group(kConfigGroup).readEntry(kConfigKey, QString());
        setEntries(m_saved);
        setNeedsSave(false);
    }

    void save() override
    {
        auto config = KSharedConfig::openConfig(kConfigFile);
        config->group(kConfigGroup).writeEntry(kConfigKey, m_entries);
        config->sync();
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

K_PLUGIN_CLASS_WITH_JSON(ToggleWindowsKCM, "metadata.json")

#include "kcm.moc"
