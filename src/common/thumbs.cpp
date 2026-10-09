#include "thumbs.hpp"

#include <QBuffer>
#include <QCryptographicHash>
#include <QHash>
#include <QMutex>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QMimeDatabase>
#include <QProcess>
#include <QRunnable>
#include <QStandardPaths>
#include <QThread>
#include <QUrl>
#include <algorithm>

#ifdef B1AIR_HAVE_LIBAV
#include <QTransform>
#include <cmath>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/display.h>
#include <libswscale/swscale.h>
}
#endif

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

#ifdef B1AIR_HAVE_LIBAV
// A frame of the film, decoded here through libavcodec: about a second in,
// past a black first frame, or the start of a shorter clip. Shown the way a
// player shows it — turned as the phone that filmed it was held, and with
// non-square pixels (DV, some DVDs) drawn at their real width.
QImage videoFrameLibav(const QString& path, int size) {
    AVFormatContext* fmt = nullptr;
    const QByteArray name = QFile::encodeName(path);
    if (avformat_open_input(&fmt, name.constData(), nullptr, nullptr) < 0) return {};
    QImage out;
    AVCodecContext* cc = nullptr;
    AVPacket* pkt = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();
    SwsContext* sws = nullptr;
    do {
        if (avformat_find_stream_info(fmt, nullptr) < 0) break;
        const AVCodec* codec = nullptr;
        const int vi = av_find_best_stream(fmt, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
        if (vi < 0 || !codec) break;
        AVStream* st = fmt->streams[vi];
        cc = avcodec_alloc_context3(codec);
        if (!cc || avcodec_parameters_to_context(cc, st->codecpar) < 0) break;
        cc->thread_count = 2;   // the provider already runs several of these at once
        if (avcodec_open2(cc, codec, nullptr) < 0) break;

        // A second in when the film is longer than two; seek to the key
        // frame before it, then decode up to it.
        const int64_t length = fmt->duration;   // AV_TIME_BASE units, or AV_NOPTS_VALUE
        const bool skipIn = length == AV_NOPTS_VALUE || length > 2 * AV_TIME_BASE;
        int64_t target = AV_NOPTS_VALUE;
        if (skipIn) {
            target = av_rescale_q(AV_TIME_BASE, AV_TIME_BASE_Q, st->time_base);
            if (st->start_time != AV_NOPTS_VALUE) target += st->start_time;
            if (av_seek_frame(fmt, vi, target, AVSEEK_FLAG_BACKWARD) < 0) target = AV_NOPTS_VALUE;
        }
        bool got = false;
        for (int packets = 0; !got && packets < 600; ++packets) {
            const int r = av_read_frame(fmt, pkt);
            if (r < 0) avcodec_send_packet(cc, nullptr);   // the end: drain what is held
            else if (pkt->stream_index != vi) { av_packet_unref(pkt); continue; }
            else { avcodec_send_packet(cc, pkt); av_packet_unref(pkt); }
            while (!got && avcodec_receive_frame(cc, frame) == 0) {
                const int64_t pts = frame->best_effort_timestamp;
                // The frame at the second, or the last one before the end.
                if (target == AV_NOPTS_VALUE || pts == AV_NOPTS_VALUE || pts >= target) got = true;
                else av_frame_unref(frame);
            }
            if (r < 0) {
                if (!got && avcodec_receive_frame(cc, frame) == 0) got = true;
                break;
            }
        }
        if (!got || frame->width <= 0 || frame->height <= 0) break;

        // Width as shown: the pixels' own aspect.
        double w = frame->width, h = frame->height;
        const AVRational sar = frame->sample_aspect_ratio.num ? frame->sample_aspect_ratio : st->sample_aspect_ratio;
        if (sar.num > 0 && sar.den > 0) w = w * sar.num / sar.den;
        const double k = std::min(1.0, double(size) / std::max(w, h));
        const int dw = std::max(1, int(w * k + 0.5)), dh = std::max(1, int(h * k + 0.5));
        sws = sws_getContext(frame->width, frame->height, AVPixelFormat(frame->format), dw, dh,
                             AV_PIX_FMT_BGRA, SWS_BILINEAR, nullptr, nullptr, nullptr);
        if (!sws) break;
        QImage img(dw, dh, QImage::Format_ARGB32);
        uint8_t* dst[4] = {img.bits(), nullptr, nullptr, nullptr};
        int dstStride[4] = {int(img.bytesPerLine()), 0, 0, 0};
        sws_scale(sws, frame->data, frame->linesize, 0, frame->height, dst, dstStride);
        img = img.convertToFormat(QImage::Format_RGB32);

        // Turned as it was filmed: a phone held upright stores its film on
        // its side with a display matrix saying so.
        const AVPacketSideData* sd = av_packet_side_data_get(st->codecpar->coded_side_data,
                                                            st->codecpar->nb_coded_side_data,
                                                            AV_PKT_DATA_DISPLAYMATRIX);
        if (sd && sd->size >= 9 * sizeof(int32_t)) {
            const double angle = av_display_rotation_get(reinterpret_cast<const int32_t*>(sd->data));
            if (!std::isnan(angle) && std::lround(angle) % 360 != 0)
                img = img.transformed(QTransform().rotate(-angle));
        }
        out = img;
    } while (false);
    sws_freeContext(sws);
    av_frame_free(&frame);
    av_packet_free(&pkt);
    avcodec_free_context(&cc);
    avformat_close_input(&fmt);
    return out;
}
#endif

QImage fromVideo(const QString& path, int size) {
#ifdef B1AIR_HAVE_LIBAV
    // In this process: it was an ffmpeg command per film, which also wrote
    // the frame out as a PNG for this to read back in.
    return videoFrameLibav(path, size);
#else
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
#endif
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

// The bytes of the picture tagged into a song — ID3 APIC, FLAC PICTURE,
// MP4 covr, Vorbis METADATA_BLOCK_PICTURE — still encoded, as the file holds
// it. Read here through libavformat when the suite was built with it: the
// demuxer finds the picture while reading the file's header, so this is a
// few small reads. It was an ffmpeg process per song, which decoded the
// picture, scaled it and wrote it out again as a PNG: a folder of 300 songs
// was 300 processes, one after the other, three at a time.
QByteArray embeddedCover(const QString& path) {
#ifdef B1AIR_HAVE_LIBAV
    AVFormatContext* ctx = nullptr;
    const QByteArray name = QFile::encodeName(path);
    if (avformat_open_input(&ctx, name.constData(), nullptr, nullptr) < 0) return {};
    QByteArray out;
    for (unsigned i = 0; i < ctx->nb_streams; ++i) {
        const AVStream* st = ctx->streams[i];
        if ((st->disposition & AV_DISPOSITION_ATTACHED_PIC) && st->attached_pic.size > 0) {
            out = QByteArray(reinterpret_cast<const char*>(st->attached_pic.data), st->attached_pic.size);
            break;
        }
    }
    avformat_close_input(&ctx);
    return out;
#else
    // Without the library, the ffmpeg command — copying the picture's bytes
    // out as they are, not decoding and encoding them again.
    const QString ffmpeg = QStandardPaths::findExecutable("ffmpeg");
    if (ffmpeg.isEmpty()) return {};
    QProcess p;
    p.start(ffmpeg, {"-nostdin", "-v", "error", "-i", path, "-an", "-map", "0:v:0", "-frames:v", "1",
                     "-c:v", "copy", "-f", "image2pipe", "-"});
    if (!p.waitForFinished(10000)) {
        p.kill();
        p.waitForFinished();
        return {};
    }
    return p.exitCode() == 0 ? p.readAllStandardOutput() : QByteArray();
#endif
}

// A picture from its bytes, decoded at the size wanted: an album's cover is
// often 1500 or 3000 px, and a JPEG read at a quarter of that is a quarter
// of the work.
QImage decodeScaled(const QByteArray& bytes, int size) {
    QBuffer buf;
    buf.setData(bytes);
    buf.open(QIODevice::ReadOnly);
    QImageReader r(&buf);
    const QSize s = r.size();
    if (s.isValid() && (s.width() > size || s.height() > size))
        r.setScaledSize(s.scaled(size, size, Qt::KeepAspectRatio));
    QImage img = r.read();
    if (!img.isNull() && (img.width() > size || img.height() > size))
        img = img.scaled(size, size, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    return img;
}

// The songs of an album carry the same cover, byte for byte: it is decoded
// and scaled once, and the rest of the album gets it from here by the
// bytes' hash. Bounded; cleared whole when full, it fills again in a folder.
QMutex g_coversLock;
QHash<QByteArray, QImage> g_covers;

QImage coverFromBytes(const QByteArray& bytes, int size) {
    QByteArray key = QCryptographicHash::hash(bytes, QCryptographicHash::Md5);
    key += QByteArray::number(size);
    {
        QMutexLocker lock(&g_coversLock);
        const auto it = g_covers.constFind(key);
        if (it != g_covers.cend()) return *it;
    }
    const QImage img = decodeScaled(bytes, size);
    if (!img.isNull()) {
        QMutexLocker lock(&g_coversLock);
        if (g_covers.size() >= 256) g_covers.clear();
        g_covers.insert(key, img);
    }
    return img;
}

// The cover.jpg or folder.jpg beside the songs, looked for once a folder:
// the folder was listed again for every song in it, and on a network share
// that is a round trip to the server each time. Looked for again when the
// folder changes.
struct FolderCover { qint64 mtime; QString file; };
QMutex g_folderLock;
QHash<QString, FolderCover> g_folderCovers;

QString folderCover(const QString& dirPath) {
    const qint64 mtime = QFileInfo(dirPath).lastModified().toMSecsSinceEpoch();
    {
        QMutexLocker lock(&g_folderLock);
        const auto it = g_folderCovers.constFind(dirPath);
        if (it != g_folderCovers.cend() && it->mtime == mtime) return it->file;
    }
    QString found;
    const QDir dir(dirPath);
    for (const QString& name : dir.entryList({"cover.*", "folder.*", "front.*", "albumart*.*"}, QDir::Files)) {
        const QString suffix = QFileInfo(name).suffix().toLower();
        if (suffix == "jpg" || suffix == "jpeg" || suffix == "png" || suffix == "webp") {
            found = dir.filePath(name);
            break;
        }
    }
    QMutexLocker lock(&g_folderLock);
    if (g_folderCovers.size() >= 1024) g_folderCovers.clear();
    g_folderCovers.insert(dirPath, {mtime, found});
    return found;
}

// An album's cover: the picture tagged into the song, else the one beside it.
QImage fromAudio(const QString& path, int size) {
    const QByteArray bytes = embeddedCover(path);
    if (!bytes.isEmpty()) {
        const QImage img = coverFromBytes(bytes, size);
        if (!img.isNull()) return img;
    }
    const QString cover = folderCover(QFileInfo(path).absolutePath());
    if (cover.isEmpty()) return {};
    QFile f(cover);
    return f.open(QIODevice::ReadOnly) ? coverFromBytes(f.readAll(), size) : QImage();
}

// Songs without a cover are many and stay without one: the try is
// remembered (freedesktop's fail/ directory) so ffmpeg is not run for each
// of them every time a folder of music is shown.
QString failPathFor(const QString& path) {
    const QByteArray md5 = QCryptographicHash::hash(QUrl::fromLocalFile(path).toEncoded(), QCryptographicHash::Md5).toHex();
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + "/thumbnails/fail/b1air/" + QString::fromLatin1(md5);
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
    const bool audio = mime.startsWith("audio/");
    const QString fail = audio ? failPathFor(fi.absoluteFilePath()) : QString();
    if (audio) {
        QFile f(fail);
        if (f.open(QIODevice::ReadOnly) && f.readAll() == mtime.toLatin1()) return {};
    }
    QImage img = mime.startsWith("video/") ? fromVideo(fi.absoluteFilePath(), size)
               : audio ? fromAudio(fi.absoluteFilePath(), size)
               : fromPicture(fi.absoluteFilePath(), size);
    if (img.isNull()) {
        if (audio) {
            QDir().mkpath(QFileInfo(fail).absolutePath());
            QFile f(fail);
            if (f.open(QIODevice::WriteOnly)) f.write(mtime.toLatin1());
        }
        return {};
    }
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
    Response(const QString& path, QSize want, QThreadPool& pool) : m_want(want), m_pool(&pool) {
        auto* job = new Job(path, sizeFor(want));
        m_job = job;
        connect(job, &Job::done, this, [this](const QImage& image) {
            m_job = nullptr;
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
    // A picture no longer wanted — its folder left, scrolled far past — is
    // taken out of the queue if it has not started. They used to be made
    // anyway, so leaving a folder of photos on a network share left a queue
    // of them reading the share behind the next folder's listing.
    void cancel() override {
        if (m_job && m_pool->tryTake(m_job)) {
            delete m_job;
            m_job = nullptr;
            emit finished();
        }
    }
private:
    QSize m_want;
    QImage m_image;
    QThreadPool* m_pool;
    QRunnable* m_job = nullptr;   // ours again only if taken back unstarted
};

} // namespace

ThumbProvider::ThumbProvider() {
    // Three at a time where the files are far — a network share, a phone over
    // USB — so the link is not asked for a hundred pictures at once. On this
    // machine's own disks, as many as there are cores.
    m_slow.setMaxThreadCount(3);
    m_pool.setMaxThreadCount(std::max(4, QThread::idealThreadCount()));
}

QQuickImageResponse* ThumbProvider::requestImageResponse(const QString& id, const QSize& requestedSize) {
    const QString path = QUrl::fromPercentEncoding(id.toUtf8());
    // gvfs (shares, MTP phones) and our own phone mounts live under the
    // runtime directory; removable drives under /run/media, /media and /mnt.
    static const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR", QStringLiteral("/run/user/"));
    const bool far = path.startsWith(runtime) || path.startsWith(u"/run/media/") || path.startsWith(u"/media/")
                  || path.startsWith(u"/mnt/");
    return new Response(path, requestedSize, far ? m_slow : m_pool);
}

} // namespace b1air

#include "thumbs.moc"
