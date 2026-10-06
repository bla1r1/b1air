#include "thumbs.hpp"

#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QImageReader>
#include <QMimeDatabase>
#include <QProcess>
#include <QRunnable>
#include <QStandardPaths>
#include <QUrl>

namespace b1air {

namespace {

// The freedesktop sizes: "large" for a file's tile, "x-large" for what is
// drawn bigger (a wallpaper's card, on a scaled screen).
int sizeFor(QSize want) { return want.width() > 256 || want.height() > 256 ? 512 : 256; }

QString cachePathFor(const QString& path, int size) {
    const QByteArray uri = QUrl::fromLocalFile(path).toEncoded();
    const QByteArray md5 = QCryptographicHash::hash(uri, QCryptographicHash::Md5).toHex();
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + (size > 256 ? "/thumbnails/x-large/" : "/thumbnails/large/") + QString::fromLatin1(md5) + ".png";
}

QImage fromVideo(const QString& path, int size) {
    const QString ffmpeg = QStandardPaths::findExecutable("ffmpeg");
    if (ffmpeg.isEmpty()) return {};
    QProcess p;
    // A second in, past a black first frame; the start for a shorter clip.
    for (const char* at : {"1", "0"}) {
        p.start(ffmpeg, {"-nostdin", "-v", "error", "-ss", at, "-i", path, "-frames:v", "1",
                         "-vf", QString("scale=%1:%1:force_original_aspect_ratio=decrease").arg(size),
                         "-f", "image2pipe", "-vcodec", "png", "-"});
        if (!p.waitForFinished(15000)) { p.kill(); p.waitForFinished(); continue; }
        QImage img;
        if (p.exitCode() == 0 && img.loadFromData(p.readAllStandardOutput(), "PNG")) return img;
    }
    return {};
}

QImage fromPicture(const QString& path, int size) {
    QImageReader r(path);
    r.setAutoTransform(true);   // as the camera held it
    const QSize s = r.size();
    if (s.isValid() && (s.width() > size || s.height() > size))
        r.setScaledSize(s.scaled(size, size, Qt::KeepAspectRatio));
    QImage img = r.read();
    if (!img.isNull() && (img.width() > size || img.height() > size))
        img = img.scaled(size, size, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    return img;
}

QImage make(const QString& path, int size) {
    const QFileInfo fi(path);
    if (!fi.isFile()) return {};
    const QString mtime = QString::number(fi.lastModified().toSecsSinceEpoch());
    const QString cached = cachePathFor(fi.absoluteFilePath(), size);
    {
        QImage c;
        if (c.load(cached, "PNG") && c.text("Thumb::MTime") == mtime) return c;
    }
    static const QMimeDatabase db;
    const QString mime = db.mimeTypeForFile(fi, QMimeDatabase::MatchExtension).name();
    QImage img = mime.startsWith("video/") ? fromVideo(fi.absoluteFilePath(), size) : fromPicture(fi.absoluteFilePath(), size);
    if (img.isNull()) return {};
    img.setText("Thumb::URI", QString::fromUtf8(QUrl::fromLocalFile(fi.absoluteFilePath()).toEncoded()));
    img.setText("Thumb::MTime", mtime);
    QDir().mkpath(QFileInfo(cached).absolutePath());
    // Written under a temporary name and renamed: another reader never sees
    // half a file.
    const QString tmp = cached + ".part";
    if (img.save(tmp, "PNG") && !QFile::rename(tmp, cached)) {
        QFile::remove(cached);
        if (!QFile::rename(tmp, cached)) QFile::remove(tmp);
    }
    return img;
}

// The work, apart from the response: the engine may delete a response it no
// longer wants while the work is still running, and a queued signal to a
// deleted receiver is simply dropped.
class Job : public QObject, public QRunnable {
    Q_OBJECT
public:
    Job(QString path, int size) : m_path(std::move(path)), m_size(size) {}
    void run() override { emit done(make(m_path, m_size)); }
signals:
    void done(const QImage& image);
private:
    QString m_path;
    int m_size;
};

class Response : public QQuickImageResponse {
public:
    Response(const QString& path, QSize want, QThreadPool& pool) : m_want(want) {
        auto* job = new Job(path, sizeFor(want));
        connect(job, &Job::done, this, [this](const QImage& image) {
            m_image = image;
            if (!m_image.isNull() && m_want.isValid() && m_want.width() > 0 && m_want.height() > 0
                && (m_image.width() > m_want.width() || m_image.height() > m_want.height()))
                m_image = m_image.scaled(m_want, Qt::KeepAspectRatio, Qt::SmoothTransformation);
            emit finished();
        }, Qt::QueuedConnection);
        pool.start(job);
    }
    QQuickTextureFactory* textureFactory() const override {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }
private:
    QSize m_want;
    QImage m_image;
};

} // namespace

ThumbProvider::ThumbProvider() {
    // Three at a time: enough to fill a screen quickly, few enough that a
    // phone's USB link is not asked for a hundred pictures at once.
    m_pool.setMaxThreadCount(3);
}

QQuickImageResponse* ThumbProvider::requestImageResponse(const QString& id, const QSize& requestedSize) {
    return new Response(QUrl::fromPercentEncoding(id.toUtf8()), requestedSize, m_pool);
}

} // namespace b1air

#include "thumbs.moc"
