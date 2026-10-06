#pragma once

#include <QQuickAsyncImageProvider>
#include <QThreadPool>

namespace b1air {

/**
 * Thumbnails for the views, as image://thumb/<percent-encoded path>.
 *
 * The grid loaded every picture whole and scaled it in QML — a 12-megapixel
 * HEIC from an iPhone over USB a quarter of a second each, a folder of them
 * all at once, every time the folder was opened; and a video had no picture
 * at all. Here: made off the GUI thread, three at a time, kept in the
 * freedesktop thumbnail cache (~/.cache/thumbnails/large, the file's mtime in
 * it) so a folder opened again is there at once and other file managers share
 * them. Pictures through QImageReader (turned the way the camera held them),
 * videos as a frame from ffmpeg when it is installed.
 *
 * Registered by b1air-files on its engine and by the B1air.Daemon plugin on
 * every engine that imports it (the shell, Settings): the wallpaper picker
 * and Spotlight use the same cache.
 */
class ThumbProvider : public QQuickAsyncImageProvider {
public:
    ThumbProvider();
    QQuickImageResponse* requestImageResponse(const QString& id, const QSize& requestedSize) override;

private:
    QThreadPool m_pool;
};

} // namespace b1air
