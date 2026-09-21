cmake_minimum_required(VERSION 3.19)
project(kwake_kcm)

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

# The KWin Scripts page opens this plugin with the *script's* metadata, so the
# page's id is the script's id, and the form is looked up at
# qrc:/kcm/<script id>/main.qml. Naming the plugin after that id makes the
# path match both there and in kcmshell6, which takes the id from the filename.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../script/metadata.json" script_metadata)
string(JSON script_id GET "${script_metadata}" KPlugin Id)

# Installs into Qt's plugin directory under kwin/effects/configs, which is where
# the X-KDE-ConfigModule entry in the script's metadata.json points.
kcmutils_add_qml_kcm(${script_id}
    SOURCES src/kcm.cpp
    INSTALL_NAMESPACE "kwin/effects/configs"
    DISABLE_DESKTOP_FILE_GENERATION
)
target_link_libraries(${script_id}
    Qt6::Gui
    Qt6::DBus
    KF6::ConfigCore
    KF6::CoreAddons
    KF6::KCMUtilsQuick
)
