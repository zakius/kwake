/*
    Config page for the Toggle Windows KWin script.

    The script stores its applications as one line per entry in
    kwinrc [Script-toggle_windows] Entries:

        Name | resourceClass | caption | shortcut

    This KCM is only an editor for that string. The script itself reacts to
    KWin's reconfigure signal, so saving here applies immediately: no reload,
    no logout.
*/

#include <KCModule>
#include <KConfigGroup>
#include <KKeySequenceWidget>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KSharedConfig>

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusMessage>
#include <QDBusPendingReply>
#include <QFrame>
#include <QGridLayout>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QScrollArea>
#include <QToolButton>
#include <QVBoxLayout>

namespace
{
const QString kConfigGroup = QStringLiteral("Script-toggle_windows");
const QString kConfigKey = QStringLiteral("Entries");
const QString kFieldSeparator = QStringLiteral(" | ");

// A separator or newline typed into a field would split it into bogus entries.
QString sanitised(const QString &field)
{
    QString clean = field;
    clean.remove(QLatin1Char('|'));
    clean.remove(QLatin1Char('\n'));
    return clean.trimmed();
}
}

// One application: the fields the script matches on, plus its shortcut.
class EntryRow : public QFrame
{
    Q_OBJECT

public:
    explicit EntryRow(QWidget *parent = nullptr)
        : QFrame(parent)
    {
        setFrameShape(QFrame::StyledPanel);

        m_name = new QLineEdit(this);
        m_name->setPlaceholderText(i18n("Shown in the shortcuts list"));
        m_windowClass = new QLineEdit(this);
        m_windowClass->setPlaceholderText(i18n("Matched as a case-insensitive substring"));
        m_caption = new QLineEdit(this);
        m_caption->setPlaceholderText(i18n("Optional, narrows the match by window title"));

        m_shortcut = new KKeySequenceWidget(this);
        m_shortcut->setCheckForConflictsAgainst(KKeySequenceWidget::GlobalShortcuts);

        auto *detect = new QPushButton(QIcon::fromTheme(QStringLiteral("edit-find")), i18n("Detect Window…"), this);
        detect->setToolTip(i18n("Click a window to fill in its class and title"));

        auto *remove = new QToolButton(this);
        remove->setIcon(QIcon::fromTheme(QStringLiteral("list-remove")));
        remove->setToolTip(i18n("Remove this application"));

        auto *layout = new QGridLayout(this);
        layout->addWidget(new QLabel(i18n("Name:"), this), 0, 0);
        layout->addWidget(m_name, 0, 1);
        layout->addWidget(new QLabel(i18n("Shortcut:"), this), 0, 2);
        layout->addWidget(m_shortcut, 0, 3);
        layout->addWidget(remove, 0, 4);
        layout->addWidget(new QLabel(i18n("Window class:"), this), 1, 0);
        layout->addWidget(m_windowClass, 1, 1);
        layout->addWidget(new QLabel(i18n("Title contains:"), this), 1, 2);
        layout->addWidget(m_caption, 1, 3);
        layout->addWidget(detect, 2, 1, 1, 1, Qt::AlignLeft);
        // The two text fields carry the width; the shortcut recorder only needs
        // enough room for a combination, not an equal share of the row.
        layout->setColumnStretch(1, 3);
        layout->setColumnStretch(3, 2);

        connect(remove, &QToolButton::clicked, this, [this] {
            Q_EMIT removeRequested(this);
        });
        connect(detect, &QPushButton::clicked, this, &EntryRow::detectWindow);
        connect(m_name, &QLineEdit::textChanged, this, &EntryRow::changed);
        connect(m_windowClass, &QLineEdit::textChanged, this, &EntryRow::changed);
        connect(m_caption, &QLineEdit::textChanged, this, &EntryRow::changed);
        connect(m_shortcut, &KKeySequenceWidget::keySequenceChanged, this, &EntryRow::changed);
    }

    void setEntry(const QStringList &fields)
    {
        m_name->setText(fields.value(0));
        m_windowClass->setText(fields.value(1));
        m_caption->setText(fields.value(2));
        // NoValidate: the stored sequence is already registered under this
        // entry's own name, so validating it here reports a conflict with itself.
        m_shortcut->setKeySequence(QKeySequence::fromString(fields.value(3)),
                                   KKeySequenceWidget::NoValidate);
    }

    // Empty means "no entry"; the script skips nameless lines anyway.
    bool isEmpty() const
    {
        return m_name->text().trimmed().isEmpty();
    }

    QString toLine() const
    {
        return QStringList{
            sanitised(m_name->text()),
            sanitised(m_windowClass->text()),
            sanitised(m_caption->text()),
            m_shortcut->keySequence().toString(QKeySequence::PortableText),
        }.join(kFieldSeparator);
    }

Q_SIGNALS:
    void changed();
    void removeRequested(EntryRow *row);

private:
    // The same picker KWin Rules uses: KWin takes over the pointer until a
    // window is clicked, then hands back that window's properties.
    void detectWindow()
    {
        QDBusInterface kwin(QStringLiteral("org.kde.KWin"),
                            QStringLiteral("/KWin"),
                            QStringLiteral("org.kde.KWin"),
                            QDBusConnection::sessionBus());
        auto *watcher = new QDBusPendingCallWatcher(kwin.asyncCall(QStringLiteral("queryWindowInfo")), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
            call->deleteLater();
            const QDBusPendingReply<QVariantMap> reply = *call;
            if (reply.isError()) {
                return; // the user pressed Escape
            }
            const QVariantMap info = reply.value();
            const QString resourceClass = info.value(QStringLiteral("resourceClass")).toString();
            m_windowClass->setText(resourceClass);
            if (m_name->text().trimmed().isEmpty()) {
                m_name->setText(resourceClass);
            }
        });
    }

    QLineEdit *m_name;
    QLineEdit *m_windowClass;
    QLineEdit *m_caption;
    KKeySequenceWidget *m_shortcut;
};

class ToggleWindowsKCM : public KCModule
{
    Q_OBJECT

public:
    ToggleWindowsKCM(QObject *parent, const KPluginMetaData &data)
        : KCModule(parent, data)
    {
        auto *outer = new QVBoxLayout(widget());

        auto *help = new QLabel(i18n("Each application gets a global shortcut that raises it, or minimises it "
                                     "again if it is already focused. Window class and title are matched as "
                                     "case-insensitive substrings; leave the title empty to match on class alone."),
                                widget());
        help->setWordWrap(true);
        outer->addWidget(help);

        m_rowContainer = new QWidget;
        m_rowLayout = new QVBoxLayout(m_rowContainer);
        m_rowLayout->setContentsMargins(0, 0, 0, 0);
        m_rowLayout->addStretch();

        auto *scroll = new QScrollArea(widget());
        scroll->setWidget(m_rowContainer);
        scroll->setWidgetResizable(true);
        scroll->setFrameShape(QFrame::NoFrame);
        outer->addWidget(scroll, 1);

        auto *add = new QPushButton(QIcon::fromTheme(QStringLiteral("list-add")), i18n("Add Application"), widget());
        connect(add, &QPushButton::clicked, this, [this] {
            addRow({});
            markAsChanged();
        });
        outer->addWidget(add, 0, Qt::AlignLeft);
    }

    void load() override
    {
        const QString stored = KSharedConfig::openConfig(QStringLiteral("kwinrc"))
                                   ->group(kConfigGroup)
                                   .readEntry(kConfigKey, QString());

        qDeleteAll(m_rows);
        m_rows.clear();

        const QStringList lines = stored.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            QStringList fields;
            const QStringList raw = line.split(QLatin1Char('|'));
            for (const QString &field : raw) {
                fields.append(field.trimmed());
            }
            if (fields.value(0).isEmpty()) {
                continue;
            }
            addRow(fields);
        }
        setNeedsSave(false);
    }

    void save() override
    {
        QStringList lines;
        for (EntryRow *row : std::as_const(m_rows)) {
            if (!row->isEmpty()) {
                lines.append(row->toLine());
            }
        }

        auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
        config->group(kConfigGroup).writeEntry(kConfigKey, lines.join(QLatin1Char('\n')));
        config->sync();

        // The script listens for this and re-registers shortcuts in place.
        QDBusConnection::sessionBus().call(
            QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
                                           QStringLiteral("/KWin"),
                                           QStringLiteral("org.kde.KWin"),
                                           QStringLiteral("reconfigure")),
            QDBus::NoBlock);

        setNeedsSave(false);
    }

    void defaults() override
    {
        qDeleteAll(m_rows);
        m_rows.clear();
        markAsChanged();
    }

private:
    void addRow(const QStringList &fields)
    {
        auto *row = new EntryRow(m_rowContainer);
        row->setEntry(fields);
        // Keep the trailing stretch last so rows stack from the top.
        m_rowLayout->insertWidget(m_rowLayout->count() - 1, row);
        m_rows.append(row);

        connect(row, &EntryRow::changed, this, &ToggleWindowsKCM::markAsChanged);
        connect(row, &EntryRow::removeRequested, this, [this](EntryRow *victim) {
            m_rows.removeOne(victim);
            victim->deleteLater();
            markAsChanged();
        });
    }

    QWidget *m_rowContainer;
    QVBoxLayout *m_rowLayout;
    QList<EntryRow *> m_rows;
};

K_PLUGIN_CLASS_WITH_JSON(ToggleWindowsKCM, "metadata.json")

#include "kcm.moc"
