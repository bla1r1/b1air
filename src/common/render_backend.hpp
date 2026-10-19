#pragma once

// =============================================================================
// Which renderer an app's window draws with: the GPU where there is one.
//
// The apps used to take Qt's software renderer whatever the machine: on an
// Intel GPU it measured 15-30 MB less per window, and nothing in them needed
// the GPU. What it cost showed on screen: it draws a Rectangle that has both
// a radius and a gradient with stair-stepped edges, and shader effects
// (blur, masks, the glass the shell draws) not at all. Now OpenGL, as the
// shell and the camera use, wherever there is a render node; Qt's software
// renderer only without one.
//
// A choice already made is left alone: b1air-session sets software in a VM
// with no GPU (llvmpipe repaints whole windows), and QT_QUICK_BACKEND or
// QSG_RHI_BACKEND set by hand win. Not Vulkan: Qt's video node crashed in it
// here, and the shell draws with OpenGL too.
//
// Set on the process, not in the environment: the terminal used to export
// QT_QUICK_BACKEND=software for itself, and every program started from it
// inherited it as if it were the session's choice.
//
// Called before the first window is made.
// =============================================================================

#include <QDir>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QStringList>
#include <QtGlobal>

namespace b1air {
namespace app {

inline bool has_gpu() {
    return !QDir(QStringLiteral("/dev/dri"))
                .entryList({QStringLiteral("renderD*")}, QDir::System)
                .isEmpty();
}

inline void choose_renderer() {
    if (qEnvironmentVariableIsSet("QT_QUICK_BACKEND") || qEnvironmentVariableIsSet("QSG_RHI_BACKEND"))
        return;
    if (has_gpu())
        QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    else
        QQuickWindow::setSceneGraphBackend(QStringLiteral("software"));
}

} // namespace app
} // namespace b1air
