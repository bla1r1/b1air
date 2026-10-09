#include "devices.hpp"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QRegularExpression>
#include <QSet>
#include <QUrl>
#include <memory>

namespace b1air {

namespace {

// What an iPod plays, and what podsync converts with ffmpeg. A folder dropped
// on the iPod is searched for these; anything else in it is left alone.
const QStringList kMusic = {"mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "mp4", "m4v", "mov",
                            "flac", "ogg", "oga", "opus", "wma"};

// A folder something is mounted on. QStorageInfo names a missing folder as
// its own root, so the folder has to exist first.
bool isMountPoint(const QString& dir) {
    if (!QFileInfo(dir).isDir()) return false;
    const QStorageInfo s(dir);
    return s.isValid() && s.rootPath() == dir;
}

QVariantMap parseObject(const QByteArray& line) {
    const QJsonDocument doc = QJsonDocument::fromJson(line.trimmed());
    return doc.isObject() ? doc.object().toVariantMap() : QVariantMap();
}

} // namespace

DeviceManager::DeviceManager(QObject* parent) : QObject(parent) {
    // B1AIR_PODSYNC names another podsync, for running from a checkout.
    const QString over = qEnvironmentVariable("B1AIR_PODSYNC");
    m_podsync = !over.isEmpty() ? over : QStandardPaths::findExecutable("b1air-podsync");
    refresh();
    // Phones are not drives until mounted: the tools that know them
    // (idevice_id, gio) are asked. They were asked every three seconds for as
    // long as the window was open, phone or none — two processes started
    // every three seconds all day. Now a USB device coming or going asks
    // (its node appears in /dev/bus/usb), and the timer runs only while a
    // phone is here: quickly while it connects or waits to be trusted, now
    // and then for its battery once it is ready.
    m_phoneTimer.setSingleShot(true);
    connect(&m_phoneTimer, &QTimer::timeout, this, &DeviceManager::scanPhones);
    connect(&m_usbWatcher, &QFileSystemWatcher::directoryChanged, this, &DeviceManager::usbChanged);
    watchUsb();
    scanPhones();
}

void DeviceManager::watchUsb() {
    const QString root = QStringLiteral("/dev/bus/usb");
    QStringList dirs{root};
    for (const QString& bus : QDir(root).entryList(QDir::Dirs | QDir::NoDotAndDotDot))
        dirs << root + "/" + bus;
    const QStringList watched = m_usbWatcher.directories();
    for (const QString& d : std::as_const(dirs))
        if (!watched.contains(d)) m_usbWatcher.addPath(d);
}

void DeviceManager::usbChanged() {
    watchUsb();   // a new bus, after a hub or a dock
    // Asked at once and again a little later: usbmuxd and gvfs take a moment
    // to know a phone after its cable is in.
    scanPhones();
    QTimer::singleShot(2000, this, &DeviceManager::scanPhones);
    QTimer::singleShot(6000, this, &DeviceManager::scanPhones);
}

void DeviceManager::schedulePhoneScan() {
    bool waiting = false;
    for (const QVariantMap& p : std::as_const(m_phones))
        if (p.value("state") != "ready") waiting = true;
    if (m_usbWatcher.directories().isEmpty() || waiting) m_phoneTimer.start(3000);   // no USB events to wait for, or a phone on its way
    else if (!m_phones.isEmpty()) m_phoneTimer.start(30000);                         // the battery, now and then
    else m_phoneTimer.stop();                                                        // nothing to ask about until a cable goes in
}

DeviceManager::~DeviceManager() {
    // A write to an iPod is let finish: killed half way, it leaves copied
    // songs the database does not know (podsync cleans up after SIGTERM, not
    // after the SIGKILL QProcess sends). The window is gone by now; this only
    // keeps the process alive a little longer.
    if (m_running) {
        if (m_runningWrites) m_running->waitForFinished(10 * 60 * 1000);
        else m_running->kill();
        m_running->waitForFinished(3000);
    }
    // Our own FUSE mounts go with the window; a mount left behind outlives
    // the phone's cable.
    for (QProcess* p : std::as_const(m_taskProcs)) p->kill();
    const QDir root(mountRoot());
    for (const QString& dev : root.entryList(QDir::Dirs | QDir::NoDotAndDotDot))
        for (const QString& m : QDir(root.filePath(dev)).entryList(QDir::Dirs | QDir::NoDotAndDotDot))
            if (isMountPoint(root.filePath(dev) + "/" + m))
                QProcess::execute("fusermount3", {"-u", "-q", root.filePath(dev) + "/" + m});
}

void DeviceManager::publish() {
    QVariantList list = m_ipods;
    for (const QVariantMap& p : std::as_const(m_phones)) list << p;
    m_devices = list;
    emit devicesChanged();
}

// ── Which devices ───────────────────────────────────────────────────────────

void DeviceManager::refresh() {
    // An iPod is a drive with iPod_Control at its root (FAT or HFS+). What it
    // is exactly — a classic, a nano — podsync works out afterwards.
    QStringList paths;
    for (const QStorageInfo& s : QStorageInfo::mountedVolumes()) {
        if (!s.isValid() || !s.isReady()) continue;
        const QString root = s.rootPath();
        if (root == "/" || !QFileInfo(root + "/iPod_Control").isDir()) continue;
        paths << root;
    }
    // A virtual iPod made by podsync, for trying this without one.
    const QString extra = qEnvironmentVariable("B1AIR_PODSYNC_EXTRA");
    for (const QString& p : extra.split(':', Qt::SkipEmptyParts))
        if (QFileInfo(p + "/iPod_Control").isDir()) paths << p;
    if (paths == m_ipodPaths) return;
    m_ipodPaths = paths;

    // Shown at once by their volume name; the model follows.
    QVariantList list;
    for (const QString& p : paths) {
        QVariantMap known;
        for (const QVariant& v : m_ipods)
            if (v.toMap().value("path").toString() == p) known = v.toMap();
        if (known.isEmpty()) {
            known["kind"] = "ipod";
            known["id"] = p;
            known["path"] = p;
            known["name"] = QStorageInfo(p).displayName().isEmpty() ? QFileInfo(p).fileName()
                                                                    : QStorageInfo(p).displayName();
            known["model"] = "iPod";
        }
        list << known;
    }
    m_ipods = list;
    publish();
    if (!paths.isEmpty() && ipodSupport()) identify(paths);
}

void DeviceManager::identify(const QStringList& paths) {
    enqueue({QString(), "devices", paths, false});
}

// ── Reading ─────────────────────────────────────────────────────────────────

QString DeviceManager::cacheDir(const QString& path) const {
    // One folder per mount point: covers are numbered per iPod.
    const QByteArray key = QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Sha1).toHex().left(12);
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + "/b1air/podsync/" + QString::fromLatin1(key);
}

QString DeviceManager::coverUrl(const QString& path) const {
    return QUrl::fromLocalFile(cacheDir(path)).toString();
}

void DeviceManager::load(const QString& path) {
    if (!ipodSupport()) {
        emit finished(path, "library", false, "b1air-podsync is not installed", {});
        return;
    }
    enqueue({path, "library", {path}, false});
    enqueue({path, "covers", {path, cacheDir(path)}, false});
}

// ── Changing ────────────────────────────────────────────────────────────────

void DeviceManager::addFiles(const QString& path, const QStringList& files, const QString& playlistId) {
    QStringList music;
    for (const QString& f : files) {
        const QFileInfo fi(f);
        if (fi.isDir()) {
            QStringList found;
            QDirIterator it(fi.absoluteFilePath(), QDir::Files, QDirIterator::Subdirectories);
            while (it.hasNext()) {
                const QString p = it.next();
                if (kMusic.contains(QFileInfo(p).suffix().toLower())) found << p;
            }
            found.sort();   // an album in track order, as its files are named
            music << found;
        } else if (fi.isFile()) {
            music << fi.absoluteFilePath();
        }
    }
    if (music.isEmpty()) {
        emit finished(path, "add", false, "No music in what was dropped", {});
        return;
    }
    QStringList args{path};
    args << music;
    if (!playlistId.isEmpty()) args << "--playlist" << playlistId;
    enqueue({path, "add", args, true});
}

void DeviceManager::removeTracks(const QString& path, const QStringList& ids) {
    if (ids.isEmpty()) return;
    enqueue({path, "remove", QStringList{path} + ids, true});
}

void DeviceManager::playlist(const QString& path, const QString& action, const QStringList& args) {
    enqueue({path, "playlist-" + action, QStringList{path} + args, true});
}

void DeviceManager::rename(const QString& path, const QString& name) {
    enqueue({path, "rename", {path, name}, true});
}

void DeviceManager::eject(const QString& id) {
    if (m_phones.contains(id)) {
        const QVariantMap p = phone(id);
        if (p.value("kind") == "android") {
            run("gio", {"mount", "-u", id}, [this, id](int code, const QByteArray&, const QByteArray& err) {
                if (code == 0) updatePhone(id, {{"mountPath", QString()}});
                emit finished(id, "eject", code == 0, QString::fromUtf8(err).trimmed(), {});
            });
        } else {
            const QDir dir(mountRoot() + "/" + safeName(id));
            bool ok = true;
            for (const QString& m : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
                const QString mp = dir.filePath(m);
                if (isMountPoint(mp))
                    ok = QProcess::execute("fusermount3", {"-u", mp}) == 0 && ok;
            }
            emit finished(id, "eject", ok, ok ? QString() : QStringLiteral("Something is still using the iPhone's files"), {});
        }
        return;
    }
    enqueue({id, "eject", {id}, true});
}

void DeviceManager::openWindow(const QString& path) const {
    QProcess::startDetached(QCoreApplication::applicationFilePath(), {path});
}

// ── The queue ───────────────────────────────────────────────────────────────

void DeviceManager::enqueue(const Job& job) {
    m_queue << job;
    if (!m_running) runNext();
}

void DeviceManager::runNext() {
    if (m_queue.isEmpty()) return;
    const Job job = m_queue.takeFirst();
    m_running = new QProcess(this);
    m_runningPath = job.path;
    m_runningOp = job.op;
    m_runningWrites = job.writes;
    m_buffer.clear();
    m_last.clear();
    m_done = 0;
    m_total = 0;
    m_file.clear();
    m_running->setProcessChannelMode(QProcess::SeparateChannels);
    QProcess* proc = m_running;
    connect(proc, &QProcess::readyReadStandardOutput, this, &DeviceManager::onOutput);
    connect(proc, &QProcess::finished, this, [this, proc](int code, QProcess::ExitStatus status) {
        onFinished(proc, status == QProcess::NormalExit ? code : -2);
    });
    connect(proc, &QProcess::errorOccurred, this, [this, proc](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) onFinished(proc, -1);
    });
    m_running->start(m_podsync, QStringList{job.op} + job.args);
    emit busyChanged();
    emit progressChanged();
}

void DeviceManager::onOutput() {
    if (!m_running) return;
    m_buffer += m_running->readAllStandardOutput();
    // `add` reports a line per file; the others print one document.
    int nl;
    while ((nl = m_buffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_buffer.left(nl);
        m_buffer.remove(0, nl + 1);
        if (m_runningOp == "devices" || m_runningOp == "library") {
            m_last["_raw"] = m_last.value("_raw").toByteArray() + line;
            continue;
        }
        const QVariantMap doc = parseObject(line);
        if (doc.value("event").toString() == "progress") {
            m_done = doc.value("done").toInt();
            m_total = doc.value("total").toInt();
            m_file = QFileInfo(doc.value("file").toString()).fileName();
            emit progressChanged();
        } else if (!doc.isEmpty()) {
            m_last = doc;
        }
    }
}

void DeviceManager::onFinished(QProcess* proc, int code) {
    // Only the job that is running can finish. m_running stays set until the
    // end: what the signals below start (a write reloads, a loaded library
    // has the window add songs) waits in the queue rather than starting a
    // second process beside this one — which the next finish would then
    // have taken for its own, and killed mid-write.
    if (proc != m_running) return;
    onOutput();
    const QByteArray err = proc->readAllStandardError();
    const QString path = m_runningPath, op = m_runningOp;
    const bool wrote = m_runningWrites;

    QVariantMap result = m_last;
    QJsonDocument raw;
    if (result.contains("_raw")) {
        raw = QJsonDocument::fromJson(result.value("_raw").toByteArray());
        result = raw.isObject() ? raw.object().toVariantMap() : QVariantMap();
    }
    QString error = result.value("error").toString();
    if (code != 0 && error.isEmpty())
        error = code == -1 ? QStringLiteral("b1air-podsync did not start")
              : code == -2 ? QStringLiteral("b1air-podsync stopped unexpectedly")
              : QString::fromUtf8(err).trimmed().section('\n', -1);

    if (op == "devices") {
        // Fill in the model, the iPod's own name and its capacity.
        if (raw.isArray()) {
            for (QVariant& v : m_ipods) {
                QVariantMap d = v.toMap();
                for (const QJsonValue& j : raw.array()) {
                    const QVariantMap found = j.toObject().toVariantMap();
                    if (found.value("path").toString() != d.value("path").toString()) continue;
                    for (auto it = found.constBegin(); it != found.constEnd(); ++it) d[it.key()] = it.value();
                    d["kind"] = "ipod";
                    d["id"] = d.value("path");
                }
                v = d;
            }
            publish();
        }
    } else if (op == "library") {
        if (error.isEmpty()) {
            // The name iTunes gave it lives in the database, not on the drive.
            const QVariantMap device = result.value("device").toMap();
            for (QVariant& v : m_ipods) {
                QVariantMap d = v.toMap();
                if (d.value("path").toString() != path) continue;
                for (auto it = device.constBegin(); it != device.constEnd(); ++it) d[it.key()] = it.value();
                v = d;
            }
            publish();
            emit libraryLoaded(path, result);
        } else {
            emit finished(path, op, false, error, result);
        }
    } else if (op == "covers") {
        emit coversReady(path);
    } else {
        // The window words success itself, translated; an error is podsync's.
        emit finished(path, op, error.isEmpty(), error, result);
        if (wrote && op != "eject") {
            // Ids of covers change with a write: read them again from scratch.
            QDir(cacheDir(path)).removeRecursively();
            load(path);
        }
        if (op == "eject" && error.isEmpty()) {
            m_ipodPaths.removeAll(path);
            for (int i = m_ipods.size() - 1; i >= 0; --i)
                if (m_ipods[i].toMap().value("path").toString() == path) m_ipods.removeAt(i);
            publish();
        }
    }
    m_done = m_total = 0;
    m_file.clear();
    m_running = nullptr;
    proc->deleteLater();
    emit busyChanged();
    emit progressChanged();
    runNext();
}


// ═════════════════════════════════════════════════════════════════════════════
// Phones
// ═════════════════════════════════════════════════════════════════════════════

namespace {

// "Key: Value" lines, as ideviceinfo prints them.
QVariantMap keyValues(const QByteArray& text) {
    QVariantMap m;
    for (const QByteArray& raw : text.split('\n')) {
        const int colon = raw.indexOf(':');
        if (colon <= 0) continue;
        m[QString::fromUtf8(raw.left(colon)).trimmed()] = QString::fromUtf8(raw.mid(colon + 1)).trimmed();
    }
    return m;
}

// The last "NN%" in a tool's progress output (rsync, idevicebackup2).
int lastPercent(const QByteArray& text) {
    static const QRegularExpression re(QStringLiteral("(\\d{1,3})(?:\\.\\d+)?%"));
    int found = -1;
    auto it = re.globalMatch(QString::fromUtf8(text));
    while (it.hasNext()) found = it.next().captured(1).toInt();
    return found > 100 ? 100 : found;
}

// What Apple calls the model the phone reports as "iPhone14,5". Older and
// unknown ones show the class ("iPhone", "iPad") instead.
QString marketingName(const QString& productType) {
    static const QMap<QString, QString> names = {
        {"iPhone12,1", "iPhone 11"}, {"iPhone12,3", "iPhone 11 Pro"}, {"iPhone12,5", "iPhone 11 Pro Max"},
        {"iPhone12,8", "iPhone SE (2nd generation)"},
        {"iPhone13,1", "iPhone 12 mini"}, {"iPhone13,2", "iPhone 12"}, {"iPhone13,3", "iPhone 12 Pro"},
        {"iPhone13,4", "iPhone 12 Pro Max"},
        {"iPhone14,4", "iPhone 13 mini"}, {"iPhone14,5", "iPhone 13"}, {"iPhone14,2", "iPhone 13 Pro"},
        {"iPhone14,3", "iPhone 13 Pro Max"}, {"iPhone14,6", "iPhone SE (3rd generation)"},
        {"iPhone14,7", "iPhone 14"}, {"iPhone14,8", "iPhone 14 Plus"}, {"iPhone15,2", "iPhone 14 Pro"},
        {"iPhone15,3", "iPhone 14 Pro Max"},
        {"iPhone15,4", "iPhone 15"}, {"iPhone15,5", "iPhone 15 Plus"}, {"iPhone16,1", "iPhone 15 Pro"},
        {"iPhone16,2", "iPhone 15 Pro Max"},
        {"iPhone17,3", "iPhone 16"}, {"iPhone17,4", "iPhone 16 Plus"}, {"iPhone17,1", "iPhone 16 Pro"},
        {"iPhone17,2", "iPhone 16 Pro Max"}, {"iPhone17,5", "iPhone 16e"},
        {"iPhone18,3", "iPhone 17"}, {"iPhone18,1", "iPhone 17 Pro"}, {"iPhone18,2", "iPhone 17 Pro Max"},
        {"iPhone18,4", "iPhone Air"},
    };
    return names.value(productType);
}

bool has(const char* program) { return !QStandardPaths::findExecutable(QString::fromLatin1(program)).isEmpty(); }

} // namespace

void DeviceManager::run(const QString& program, const QStringList& args, Done done, int timeoutMs) {
    auto* p = new QProcess(this);
    auto* timer = new QTimer(p);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, p, [p] { p->kill(); });
    connect(p, &QProcess::finished, this, [p, done](int code, QProcess::ExitStatus status) {
        done(status == QProcess::NormalExit ? code : -1, p->readAllStandardOutput(), p->readAllStandardError());
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [p, done](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        done(-1, {}, QByteArray("not installed"));
        p->deleteLater();
    });
    p->start(program, args);
    timer->start(timeoutMs);
}

QString DeviceManager::mountRoot() const {
    const QString rt = qEnvironmentVariable("XDG_RUNTIME_DIR", QDir::tempPath());
    return rt + "/b1air-devices";
}

QString DeviceManager::safeName(const QString& id) const {
    QString s = id;
    s.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9._-]")), QStringLiteral("_"));
    return s;
}

void DeviceManager::updatePhone(const QString& id, const QVariantMap& changes) {
    if (!m_phones.contains(id)) return;
    QVariantMap& p = m_phones[id];
    bool changed = false;
    for (auto it = changes.constBegin(); it != changes.constEnd(); ++it) {
        if (p.value(it.key()) == it.value()) continue;
        p[it.key()] = it.value();
        changed = true;
    }
    if (changed) publish();
}

// ── Finding them ────────────────────────────────────────────────────────────

void DeviceManager::scanPhones() {
    if (m_scanning) return;
    const bool apple = has("idevice_id"), mtp = has("gio");
    if (!apple && !mtp) return;
    m_scanning = true;
    auto pending = std::make_shared<int>((apple ? 1 : 0) + (mtp ? 1 : 0));
    auto done = [this, pending] {
        if (--*pending > 0) return;
        m_scanning = false;
        schedulePhoneScan();
    };
    if (apple) {
        run("idevice_id", {"-l"}, [this, done](int code, const QByteArray& out, const QByteArray&) {
            QStringList udids;
            if (code == 0)
                for (const QByteArray& line : out.split('\n')) {
                    const QString u = QString::fromUtf8(line).trimmed().section(' ', 0, 0);
                    if (!u.isEmpty() && !udids.contains(u)) udids << u;
                }
            scanIphones(udids);
            done();
        }, 5000);
    }
    if (mtp) {
        run("gio", {"mount", "-li"}, [this, done](int code, const QByteArray& out, const QByteArray&) {
            if (code == 0) scanAndroids(out);
            done();
        }, 5000);
    }
}

// ── iPhone ──────────────────────────────────────────────────────────────────

void DeviceManager::scanIphones(const QStringList& udids) {
    bool changed = false;
    for (const QString& id : m_phones.keys()) {
        if (m_phones[id].value("kind") == "iphone" && !udids.contains(id)) {
            m_phones.remove(id);
            changed = true;
        }
    }
    for (const QString& u : udids) {
        const bool fresh = !m_phones.contains(u);
        if (fresh) {
            m_phones[u] = QVariantMap{{"kind", "iphone"}, {"id", u}, {"name", "iPhone"}, {"model", "iPhone"},
                                      {"state", "connecting"}, {"battery", -1}};
            changed = true;
        }
        // Until it trusts us, ask again each time; after that, now and then
        // for the battery.
        const QVariantMap p = m_phones[u];
        const int age = p.value("age").toInt() + 1;
        m_phones[u]["age"] = age;
        if (fresh || p.value("state") != "ready" || age % 2 == 0) describeIphone(u);
    }
    if (changed) publish();
}

void DeviceManager::describeIphone(const QString& udid) {
    run("idevicepair", {"-u", udid, "validate"}, [this, udid](int code, const QByteArray& out, const QByteArray& err) {
        const QString said = QString::fromUtf8(out + err);
        if (code != 0) {
            // Not trusted yet, or locked with a passcode: what it can say
            // without trust (its name and model) it still says.
            const bool locked = said.contains("passcode", Qt::CaseInsensitive) || said.contains("Password protected");
            const bool pending = said.contains("dialog", Qt::CaseInsensitive);
            updatePhone(udid, {{"state", locked ? "locked" : pending ? "pending" : "trust"}});
            run("ideviceinfo", {"-u", udid, "-s"}, [this, udid](int c, const QByteArray& o, const QByteArray&) {
                if (c != 0) return;
                const QVariantMap info = keyValues(o);
                const QString product = info.value("ProductType").toString();
                updatePhone(udid, {{"name", info.value("DeviceName", "iPhone")},
                                   {"model", marketingName(product).isEmpty() ? info.value("DeviceClass", "iPhone").toString()
                                                                              : marketingName(product)},
                                   {"productType", info.value("ProductType")},
                                   {"os", info.value("ProductVersion")}});
            }, 8000);
            return;
        }
        run("ideviceinfo", {"-u", udid}, [this, udid](int c, const QByteArray& o, const QByteArray&) {
            if (c != 0) return;
            const QVariantMap info = keyValues(o);
            updatePhone(udid, {{"state", "ready"},
                               {"name", info.value("DeviceName", "iPhone")},
                               {"model", marketingName(info.value("ProductType").toString()).isEmpty()
                                             ? info.value("DeviceClass", "iPhone").toString()
                                             : marketingName(info.value("ProductType").toString())},
                               {"productType", info.value("ProductType")},
                               {"os", info.value("ProductVersion")},
                               {"serial", info.value("SerialNumber")},
                               {"phoneNumber", info.value("PhoneNumber")}});
            const QString backupDir = QDir::homePath() + "/Backups/" + info.value("DeviceName", "iPhone").toString()
                                    + "/" + udid;
            const QFileInfo status(backupDir + "/Status.plist");
            updatePhone(udid, {{"backupDir", QFileInfo(backupDir).absolutePath()},
                               {"lastBackup", status.exists() ? status.lastModified() : QVariant()}});
        }, 8000);
        run("ideviceinfo", {"-u", udid, "-q", "com.apple.mobile.battery"},
            [this, udid](int c, const QByteArray& o, const QByteArray&) {
                if (c != 0) return;
                const QVariantMap b = keyValues(o);
                updatePhone(udid, {{"battery", b.value("BatteryCurrentCapacity", -1).toInt()},
                                   {"charging", b.value("BatteryIsCharging").toString() == "true"}});
            }, 8000);
        run("ideviceinfo", {"-u", udid, "-q", "com.apple.disk_usage"},
            [this, udid](int c, const QByteArray& o, const QByteArray&) {
                if (c != 0) return;
                const QVariantMap d = keyValues(o);
                const qlonglong total = d.value("TotalDiskCapacity").toLongLong();
                // TotalDataAvailable is what the phone's own Settings calls
                // available: AmountDataAvailable leaves out what iOS frees on
                // its own (caches, offloadable data), and read a 128 GB phone
                // with 83 GB to spare as 7 GB free.
                const qlonglong free = d.value("TotalDataAvailable", d.value("AmountDataAvailable")).toLongLong();
                if (total > 0) updatePhone(udid, {{"total_bytes", total}, {"free_bytes", free}});
            }, 8000);
    }, 8000);
}

void DeviceManager::pair(const QString& id) {
    run("idevicepair", {"-u", id, "pair"}, [this, id](int code, const QByteArray& out, const QByteArray& err) {
        const QString said = QString::fromUtf8(out + err).trimmed();
        // "Please accept the trust dialog on the screen": the answer comes on
        // the phone, and the next scan sees it.
        updatePhone(id, {{"state", code == 0 ? "connecting" : said.contains("dialog", Qt::CaseInsensitive) ? "pending" : "trust"}});
        if (code == 0) describeIphone(id);
        emit finished(id, "pair", code == 0 || said.contains("dialog", Qt::CaseInsensitive),
                      code == 0 ? QString() : said.section('\n', -1), {});
    }, 15000);
}

void DeviceManager::mountIphone(const QString& udid, const QString& what, std::function<void(const QString&)> then) {
    const QString dir = mountRoot() + "/" + safeName(udid) + "/" + (what == "media" ? QStringLiteral("media") : safeName(what));
    if (isMountPoint(dir)) { then(dir); return; }
    QDir().mkpath(dir);
    QStringList args{"-u", udid};
    if (what != "media") args << "--documents" << what;
    args << dir;
    run("ifuse", args, [this, udid, dir, then](int code, const QByteArray&, const QByteArray& err) {
        if (code == 0) then(dir);
        else emit finished(udid, "browse", false, code == -1 && err == "not installed"
                           ? QStringLiteral("ifuse is not installed") : QString::fromUtf8(err).trimmed(), {});
    });
}

void DeviceManager::listApps(const QString& id) {
    run("ifuse", {"-u", id, "--list-apps"}, [this, id](int code, const QByteArray& out, const QByteArray& err) {
        QVariantList apps;
        if (code == 0) {
            // "CFBundleIdentifier","CFBundleVersion","CFBundleDisplayName"
            bool header = true;
            for (const QByteArray& raw : out.split('\n')) {
                const QString line = QString::fromUtf8(raw).trimmed();
                if (line.isEmpty()) continue;
                if (header) { header = false; continue; }
                QStringList cols;
                for (const QString& c : line.split("\",\"")) cols << QString(c).remove('"');
                if (cols.size() >= 3) apps << QVariantMap{{"id", cols[0]}, {"version", cols[1]}, {"name", cols[2]}};
            }
            std::sort(apps.begin(), apps.end(), [](const QVariant& a, const QVariant& b) {
                return a.toMap().value("name").toString().localeAwareCompare(b.toMap().value("name").toString()) < 0;
            });
        } else {
            emit finished(id, "apps", false, QString::fromUtf8(err).trimmed(), {});
        }
        emit appsListed(id, apps);
    });
}

void DeviceManager::backup(const QString& id) {
    const QVariantMap p = phone(id);
    if (p.value("kind") != "iphone") return;
    const QString dir = QDir::homePath() + "/Backups/" + p.value("name").toString();
    QDir().mkpath(dir);
    runTask(id, "backup", "idevicebackup2", {"-u", id, "backup", dir}, dir);
}

// ── Android ─────────────────────────────────────────────────────────────────

void DeviceManager::scanAndroids(const QByteArray& gioList) {
    // gio mount -li: a "Volume(n): Name" block with activation_root=mtp://…/
    // per phone in file-transfer mode; a "Mount(n): Name -> mtp://…/" once
    // mounted.
    static const QRegularExpression volRe(QStringLiteral("^\\s*Volume\\(\\d+\\):\\s*(.*)$"));
    static const QRegularExpression rootRe(QStringLiteral("activation_root=(mtp://\\S+)"));
    static const QRegularExpression mountRe(QStringLiteral("^\\s*Mount\\(\\d+\\):\\s*(.*?)\\s*->\\s*(mtp://\\S+)"));
    QMap<QString, QString> found;   // uri -> name
    QSet<QString> mountedUris;
    QString volume;
    for (const QByteArray& raw : gioList.split('\n')) {
        const QString line = QString::fromUtf8(raw);
        auto v = volRe.match(line);
        if (v.hasMatch()) { volume = v.captured(1).trimmed(); continue; }
        auto r = rootRe.match(line);
        if (r.hasMatch()) { found[r.captured(1)] = volume; continue; }
        auto m = mountRe.match(line);
        if (m.hasMatch()) {
            if (!found.contains(m.captured(2))) found[m.captured(2)] = m.captured(1);
            mountedUris << m.captured(2);
        }
    }
    bool changed = false;
    for (const QString& id : m_phones.keys())
        if (m_phones[id].value("kind") == "android" && !found.contains(id)) { m_phones.remove(id); changed = true; }
    const QString gvfs = qEnvironmentVariable("XDG_RUNTIME_DIR", QDir::tempPath()) + "/gvfs";
    for (auto it = found.constBegin(); it != found.constEnd(); ++it) {
        const QString& uri = it.key();
        const QString host = QString(uri).remove("mtp://").remove(QRegularExpression("/$"));
        const QString mountPath = mountedUris.contains(uri) ? gvfs + "/mtp:host=" + host : QString();
        if (!m_phones.contains(uri)) {
            m_phones[uri] = QVariantMap{{"kind", "android"}, {"id", uri}, {"name", it.value().isEmpty() ? QStringLiteral("Android") : it.value()},
                                        {"model", "Android"}, {"host", host}, {"state", "ready"}, {"battery", -1},
                                        {"mountPath", mountPath}};
            changed = true;
            describeAndroid(uri);
        } else if (m_phones[uri].value("mountPath").toString() != mountPath) {
            m_phones[uri]["mountPath"] = mountPath;
            changed = true;
            if (!mountPath.isEmpty()) describeAndroid(uri);
        } else {
            const int age = m_phones[uri].value("age").toInt() + 1;
            m_phones[uri]["age"] = age;
            if (age % 2 == 0) describeAndroid(uri);
        }
    }
    if (changed) publish();
}

void DeviceManager::describeAndroid(const QString& id) {
    const QVariantMap p = phone(id);
    // Storage: the phone's, through gvfs, once it is mounted.
    const QString mp = p.value("mountPath").toString();
    if (!mp.isEmpty()) {
        const QStringList storages = QDir(mp).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        updatePhone(id, {{"storages", storages}});
        auto total = std::make_shared<qlonglong>(0), free = std::make_shared<qlonglong>(0);
        auto left = std::make_shared<int>(storages.size());
        for (const QString& s : storages) {
            const QString uri = id + QString::fromUtf8(QUrl::toPercentEncoding(s)) + "/";
            run("gio", {"info", "-f", "-a", "filesystem::size,filesystem::free", uri},
                [this, id, total, free, left](int code, const QByteArray& out, const QByteArray&) {
                    if (code == 0) {
                        const QVariantMap kv = keyValues(QByteArray(out).replace("filesystem::", ""));
                        *total += kv.value("size").toLongLong();
                        *free += kv.value("free").toLongLong();
                    }
                    if (--*left == 0 && *total > 0) updatePhone(id, {{"total_bytes", *total}, {"free_bytes", *free}});
                }, 8000);
        }
    }
    // Battery and model: adb, when the phone has USB debugging on. Its serial
    // ends the MTP host name (Google_Pixel_7_28041FDH2002ZQ).
    if (!has("adb")) return;
    const QString host = p.value("host").toString();
    run("adb", {"devices", "-l"}, [this, id, host](int code, const QByteArray& out, const QByteArray&) {
        if (code != 0) return;
        for (const QByteArray& raw : out.split('\n')) {
            const QStringList cols = QString::fromUtf8(raw).simplified().split(' ');
            if (cols.size() < 2 || cols[1] != "device" || !host.endsWith(cols[0])) continue;
            const QString serial = cols[0];
            run("adb", {"-s", serial, "shell", "dumpsys battery; getprop ro.product.model; getprop ro.build.version.release"},
                [this, id](int c, const QByteArray& o, const QByteArray&) {
                    if (c != 0) return;
                    const QVariantMap kv = keyValues(o);
                    const QList<QByteArray> lines = o.trimmed().split('\n');
                    QVariantMap ch{{"battery", kv.value("level", -1).toInt()},
                                   {"charging", kv.value("status").toInt() == 2}};
                    if (lines.size() >= 2) {
                        ch["model"] = QString::fromUtf8(lines[lines.size() - 2]).trimmed();
                        ch["os"] = QString::fromUtf8(lines.last()).trimmed();
                    }
                    updatePhone(id, ch);
                }, 8000);
            return;
        }
    }, 5000);
}

void DeviceManager::mountAndroid(const QString& id, std::function<void(const QString&)> then) {
    const QString mp = phone(id).value("mountPath").toString();
    if (!mp.isEmpty() && QFileInfo(mp).isDir()) { then(mp); return; }
    run("gio", {"mount", id}, [this, id, then](int code, const QByteArray&, const QByteArray& err) {
        const QString host = phone(id).value("host").toString();
        const QString path = qEnvironmentVariable("XDG_RUNTIME_DIR", QDir::tempPath()) + "/gvfs/mtp:host=" + host;
        if (code == 0 || QFileInfo(path).isDir()) {
            updatePhone(id, {{"mountPath", path}});
            describeAndroid(id);
            then(path);
        } else {
            // Most often: the phone is locked, or set to "charging only".
            emit finished(id, "browse", false, QString::fromUtf8(err).trimmed(), {});
        }
    }, 30000);
}

// ── Both ────────────────────────────────────────────────────────────────────

void DeviceManager::browse(const QString& id, const QString& what) {
    const QVariantMap p = phone(id);
    if (p.value("kind") == "iphone")
        mountIphone(id, what, [this, id](const QString& dir) { emit mounted(id, dir); });
    else if (p.value("kind") == "android")
        mountAndroid(id, [this, id, what](const QString& dir) {
            emit mounted(id, what == "media" ? dir : dir + "/" + what);
        });
}

void DeviceManager::importPhotos(const QString& id) {
    const QVariantMap p = phone(id);
    const QString dest = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + "/"
                       + p.value("name").toString();
    auto start = [this, id, dest](const QStringList& sources) {
        if (sources.isEmpty()) {
            emit finished(id, "import", false, QStringLiteral("No DCIM folder on the phone"), {});
            return;
        }
        QDir().mkpath(dest);
        // Only what is not here yet; the phone's folders (100APPLE, Camera)
        // are kept, so a second import adds the new ones beside them.
        QStringList args{"-rt", "--ignore-existing", "--info=progress2", "--no-inc-recursive"};
        args << sources << dest + "/";
        runTask(id, "import", "rsync", args, dest);
    };
    if (p.value("kind") == "iphone") {
        mountIphone(id, "media", [start](const QString& dir) {
            start(QFileInfo(dir + "/DCIM").isDir() ? QStringList{dir + "/DCIM/"} : QStringList{});
        });
    } else {
        mountAndroid(id, [start](const QString& dir) {
            QStringList sources;
            for (const QString& s : QDir(dir).entryList(QDir::Dirs | QDir::NoDotAndDotDot))
                if (QFileInfo(dir + "/" + s + "/DCIM").isDir()) sources << dir + "/" + s + "/DCIM/";
            start(sources);
        });
    }
}

void DeviceManager::runTask(const QString& id, const QString& op, const QString& program, const QStringList& args,
                            const QString& doneText) {
    if (m_taskProcs.contains(id)) return;
    auto* p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);
    m_taskProcs[id] = p;
    m_tasks[id] = QVariantMap{{"op", op}, {"percent", -1}, {"text", QString()}};
    emit tasksChanged();
    auto tail = std::make_shared<QByteArray>();
    connect(p, &QProcess::readyRead, this, [this, p, id, op, tail] {
        const QByteArray chunk = p->readAll();
        *tail = (*tail + chunk).right(4096);
        const int pct = lastPercent(chunk);
        if (pct >= 0) {
            QVariantMap t = m_tasks.value(id).toMap();
            t["percent"] = pct;
            m_tasks[id] = t;
            emit tasksChanged();
        }
    });
    connect(p, &QProcess::finished, this, [this, p, id, op, doneText, tail](int code, QProcess::ExitStatus status) {
        m_taskProcs.remove(id);
        m_tasks.remove(id);
        emit tasksChanged();
        const bool ok = status == QProcess::NormalExit && code == 0;
        QString err;
        if (!ok) {
            const QList<QByteArray> lines = tail->trimmed().split('\n');
            err = status != QProcess::NormalExit ? QStringLiteral("Stopped") : QString::fromUtf8(lines.last()).trimmed();
        }
        emit finished(id, op, ok, err, {{"dir", doneText}});
        if (op == "backup") describeIphone(id);
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, id, op, program](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        m_taskProcs.remove(id);
        m_tasks.remove(id);
        emit tasksChanged();
        emit finished(id, op, false, program + " is not installed", {});
        p->deleteLater();
    });
    p->start(program, args);
}

void DeviceManager::cancelTask(const QString& id) {
    if (QProcess* p = m_taskProcs.value(id)) p->terminate();
}

} // namespace b1air
