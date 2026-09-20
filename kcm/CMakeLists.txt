cmake_minimum_required(VERSION 3.16)
project(kcm_toggle_windows VERSION 1.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_AUTOMOC ON)
include(GNUInstallDirs)

find_package(Qt6 REQUIRED COMPONENTS Core Widgets DBus)
# Debian ships the KF6 modules split, with no umbrella KF6Config.cmake.
foreach(component CoreAddons Config ConfigWidgets I18n KCMUtils XmlGui)
    find_package(KF6${component} REQUIRED)
endforeach()

add_library(kcm_toggle_windows MODULE src/kcm.cpp)
target_link_libraries(kcm_toggle_windows
    Qt6::Widgets
    Qt6::DBus
    KF6::CoreAddons
    KF6::ConfigCore
    KF6::ConfigWidgets
    KF6::I18n
    KF6::KCMUtils
    KF6::XmlGui
)

# Must land in a Qt plugin search path under kwin/effects/configs, so the
# X-KDE-ConfigModule entry in the script's metadata.json resolves to it.
install(TARGETS kcm_toggle_windows
        DESTINATION ${CMAKE_INSTALL_FULL_LIBDIR}/qt6/plugins/kwin/effects/configs)
