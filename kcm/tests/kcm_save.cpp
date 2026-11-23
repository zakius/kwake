#include <KPluginMetaData>
#include <KQuickConfigModule>
#include <KQuickConfigModuleLoader>
#include <QGuiApplication>
#include <QQmlEngine>

#include <cstdio>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    const QStringList args = app.arguments();
    if (args.size() != 3) {
        std::fputs("usage: kcm_save <plugin .so> <Entries>\n", stderr);
        return 2;
    }
    const auto result = KQuickConfigModuleLoader::loadModule(KPluginMetaData(args.at(1)), nullptr, {}, std::make_shared<QQmlEngine>());
    if (!result.plugin) {
        std::fprintf(stderr, "cannot load %s: %s\n", qPrintable(args.at(1)), qPrintable(result.errorText));
        return 1;
    }
    result.plugin->load();
    result.plugin->setProperty("entries", args.at(2));
    result.plugin->save();
    return 0;
}
