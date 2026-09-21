cmake_minimum_required(VERSION 3.16)
project(kcm_toggle_windows)

# ECM only sets up plugin output directories when a version is requested.
find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
# Strict KDE defaults: -Wall and friends, no implicit const char* to QString.
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 REQUIRED COMPONENTS Gui DBus Quick)
# Debian ships the KF6 modules split, with no umbrella KF6Config.cmake.
foreach(component CoreAddons Config KCMUtils)
    find_package(KF6${component} REQUIRED)
endforeach()

# Installs into Qt's plugin directory under kwin/effects/configs, which is where
# the X-KDE-ConfigModule entry in the script's metadata.json points. The form
# itself is ui/main.qml, compiled into the plugin.
kcmutils_add_qml_kcm(kcm_toggle_windows
    SOURCES src/kcm.cpp
    INSTALL_NAMESPACE "kwin/effects/configs"
    DISABLE_DESKTOP_FILE_GENERATION
)
target_link_libraries(kcm_toggle_windows
    Qt6::Gui
    Qt6::DBus
    KF6::ConfigCore
    KF6::CoreAddons
    KF6::KCMUtilsQuick
)
