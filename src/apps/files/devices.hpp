#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QList>
#include <QMap>
#include <QTimer>
#include <functional>

namespace b1air {

/**
 * Music players and phones, the way Finder shows them: not as a drive to
 * browse but as a device — its music and playlists, its photos, its backup.
 *
 *   iPod      podsync (third_party/podsync) through `b1air-podsync`, which
 *             answers in JSON. Its runs are queued, one at a time: two
 *             writes to one iTunesDB at once would be one too many.
 *   iPhone    libimobiledevice: idevice_id finds it, ideviceinfo describes
 *             it, idevicepair asks it to trust this computer, ifuse mounts
 *             its photos and the files apps share, idevicebackup2 backs it up.
 *   Android   MTP through gvfs (gio): found, mounted and browsed like a
 *             drive; adb adds the battery when USB debugging is on.
 *
 * Every device has an "id": the iPod's mount point, the iPhone's UDID, the
 * Android's mtp:// address.
 */
class DeviceManager : public QObject {
    Q_OBJECT

    // [{kind: "ipod" | "iphone" | "android", id, name, model, …}]
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    // b1air-podsync is installed.
    Q_PROPERTY(bool ipodSupport READ ipodSupport CONSTANT)
    // An iPod write or copy is running: on which, what, and how far.
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString busyPath READ busyPath NOTIFY busyChanged)
    Q_PROPERTY(QString busyOp READ busyOp NOTIFY busyChanged)
    Q_PROPERTY(int progressDone READ progressDone NOTIFY progressChanged)
    Q_PROPERTY(int progressTotal READ progressTotal NOTIFY progressChanged)
    Q_PROPERTY(QString progressFile READ progressFile NOTIFY progressChanged)
    // What a phone is doing — {id: {op, percent, text}} — an import or a backup.
    Q_PROPERTY(QVariantMap tasks READ tasks NOTIFY tasksChanged)

public:
    explicit DeviceManager(QObject* parent = nullptr);
    ~DeviceManager() override;

    QVariantList devices() const { return m_devices; }
    bool ipodSupport() const { return !m_podsync.isEmpty(); }
    bool busy() const { return m_running != nullptr && m_runningWrites; }
    QString busyPath() const { return busy() ? m_runningPath : QString(); }
    QString busyOp() const { return busy() ? m_runningOp : QString(); }
    int progressDone() const { return m_done; }
    int progressTotal() const { return m_total; }
    QString progressFile() const { return m_file; }
    QVariantMap tasks() const { return m_tasks; }

public slots:
    /** Look at what is mounted; called when FilesBackend's drives change. */
    void refresh();

    // ── iPod ────────────────────────────────────────────────────────────────
    /** Tracks and playlists: libraryLoaded, then coversReady. */
    void load(const QString& path);
    /** Where the covers of the device at `path` are cached, as a file URL. */
    QString coverUrl(const QString& path) const;
    /** Files and folders (searched for music) onto the iPod. */
    void addFiles(const QString& path, const QStringList& files, const QString& playlistId = QString());
    void removeTracks(const QString& path, const QStringList& ids);
    /** create NAME [ids…] | rename ID NAME | delete ID | add ID ids… | remove ID ids… */
    void playlist(const QString& path, const QString& action, const QStringList& args);
    void rename(const QString& path, const QString& name);

    // ── Phones ──────────────────────────────────────────────────────────────
    /** Ask the iPhone to trust this computer (the dialog on its screen). */
    void pair(const QString& id);
    /**
     * Mount and hand back a folder to browse (mounted): an iPhone's photos
     * ("media") or one app's shared files (its bundle id); an Android's
     * storage ("media").
     */
    void browse(const QString& id, const QString& what = QStringLiteral("media"));
    /** The iPhone apps that share files: appsListed(id, [{id, name}]). */
    void listApps(const QString& id);
    /** Copy the photos and videos not imported yet into ~/Pictures/<name>. */
    void importPhotos(const QString& id);
    /** An iPhone backup, in ~/Backups/<name> (idevicebackup2). */
    void backup(const QString& id);
    void cancelTask(const QString& id);

    // ── Both ────────────────────────────────────────────────────────────────
    void eject(const QString& id);
    /** Another Files window, on `path`: where music is dragged from. */
    void openWindow(const QString& path) const;

signals:
    void devicesChanged();
    void busyChanged();
    void progressChanged();
    void tasksChanged();
    void libraryLoaded(const QString& path, const QVariantMap& library);
    void coversReady(const QString& path);
    void mounted(const QString& id, const QString& path);
    void appsListed(const QString& id, const QVariantList& apps);
    /** After every change: ok, an error from the tool (the window words success), the answer. */
    void finished(const QString& path, const QString& op, bool ok, const QString& message, const QVariantMap& result);

private:
    // ── iPod: the podsync queue ─────────────────────────────────────────────
    struct Job {
        QString path;
        QString op;          // "library", "covers", "add", "remove", …
        QStringList args;    // after the command name
        bool writes = false;
    };
    void enqueue(const Job& job);
    void runNext();
    void onOutput();
    void onFinished(QProcess* proc, int code);
    QString cacheDir(const QString& path) const;
    void identify(const QStringList& paths);

    // ── Phones ──────────────────────────────────────────────────────────────
    using Done = std::function<void(int code, const QByteArray& out, const QByteArray& err)>;
    void run(const QString& program, const QStringList& args, Done done, int timeoutMs = 20000);
    void scanPhones();
    void scanIphones(const QStringList& udids);
    void describeIphone(const QString& udid);
    void scanAndroids(const QByteArray& gioList);
    void describeAndroid(const QString& id);
    void mountAndroid(const QString& id, std::function<void(const QString&)> then);
    void mountIphone(const QString& udid, const QString& what, std::function<void(const QString&)> then);
    void runTask(const QString& id, const QString& op, const QString& program, const QStringList& args,
                 const QString& doneText);
    void updatePhone(const QString& id, const QVariantMap& changes);
    QVariantMap phone(const QString& id) const { return m_phones.value(id); }
    QString mountRoot() const;
    QString safeName(const QString& id) const;
    void publish();

    QString m_podsync;
    QVariantList m_devices;
    QVariantList m_ipods;
    QStringList m_ipodPaths;
    QMap<QString, QVariantMap> m_phones;
    QTimer m_phoneTimer;
    bool m_scanning = false;
    QMap<QString, QProcess*> m_taskProcs;
    QVariantMap m_tasks;

    QList<Job> m_queue;
    QProcess* m_running = nullptr;
    QString m_runningPath, m_runningOp;
    bool m_runningWrites = false;
    QByteArray m_buffer;
    QVariantMap m_last;
    int m_done = 0, m_total = 0;
    QString m_file;
};

} // namespace b1air
