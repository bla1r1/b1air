#pragma once

// =============================================================================
// Enough of Quickshell to host the shell's own QML in a plain Qt program.
//
// The settings panel, and most of what surrounds it, is ordinary QML: Ui/ for
// the look and Services/ for the values. What ties it to the `quickshell`
// binary is a small set of primitives — Process, FileView, a couple of stream
// readers and three functions on a `Quickshell` singleton. Counted across
// Services/, settings/ and Ui/, the whole surface is six types and three
// functions:
//
//     Quickshell.execDetached  74     FileView         13
//     Singleton                35     Quickshell.env   25
//     Process                  35     Quickshell.screens 4
//     StdioCollector           29     SplitParser       2
//
// So this provides them, with the same names and the same shapes, backed by
// QProcess and QFile. Nothing here reimplements Quickshell: it is a
// compatibility layer wide enough for one window, and it is registered under
// the same module names so the QML that uses it needs no edits at all — which
// is the whole point, because the moment those files are forked the two copies
// start to drift, and this repository has already learned what that costs.
//
// It is deliberately NOT installed anywhere the shell searches. The `quickshell`
// process must find the real module; only a standalone binary adds this
// directory to its import path, and only ever after the real one has been ruled
// out by the fact that it cannot be loaded outside that process at all.
// =============================================================================

#include <QFile>
#include <QFileSystemWatcher>
#include <QObject>
#include <QtQml/qqmlparserstatus.h>
#include <QProcess>
#include <QQmlEngine>
#include <QQmlListProperty>
#include <QScreen>
#include <QString>
#include <QStringList>
#include <QVariantList>

// <cstdio> arrives through the Qt headers above and defines `stdout` as a
// macro. The QML property has to be spelled exactly `stdout`, because that is
// what every `Process { stdout: ... }` in the shell says, so the macro has to
// go before the Q_PROPERTY below is parsed.
#ifdef stdout
#undef stdout
#endif
#ifdef stderr
#undef stderr
#endif

namespace qscompat {

// ── Quickshell.Io: the stream readers ────────────────────────────────────────

/**
 * Collects a stream and hands it over once, when the stream closes.
 *
 * The one thing to get right: `streamFinished` fires on close, not on every
 * chunk. Reading a process that never exits with this is the mistake that left
 * the clipboard recording nothing for months.
 */
class StdioCollector : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString text READ text NOTIFY textChanged)

public:
    explicit StdioCollector(QObject* parent = nullptr) : QObject(parent) {}

    QString text() const { return m_text; }
    void append(const QByteArray& chunk);
    void finish();
    void reset() { m_text.clear(); }

signals:
    void textChanged();
    void streamFinished();

private:
    QString m_text;
};

/** Splits a stream on a marker and emits each record as it arrives. */
class SplitParser : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString splitMarker READ splitMarker WRITE setSplitMarker NOTIFY splitMarkerChanged)

public:
    explicit SplitParser(QObject* parent = nullptr) : QObject(parent) {}

    QString splitMarker() const { return m_marker; }
    void setSplitMarker(const QString& m);
    void append(const QByteArray& chunk);
    void finish();

signals:
    void splitMarkerChanged();
    void read(const QString& data);

private:
    QString m_marker = "\n";
    QString m_buffer;
};

// ── Quickshell.Io: Process ───────────────────────────────────────────────────

// QQmlParserStatus so that `running: true` waits for the rest of the
// declaration. QML assigns properties in source order, and a Process written
// `running: true` before `command:` (Settings → About has one) used to start
// with an empty command, do nothing, and leave its page at "Loading..." —
// only in the standalone apps; real Quickshell defers the same way.
class Process : public QObject, public QQmlParserStatus {
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(QVariantList command READ command WRITE setCommand NOTIFY commandChanged)
    Q_PROPERTY(QObject* stdout READ stdoutSink WRITE setStdoutSink NOTIFY stdoutSinkChanged)
    Q_PROPERTY(QObject* stderr READ stderrSink WRITE setStderrSink NOTIFY stderrSinkChanged)
    Q_PROPERTY(bool stdinEnabled READ stdinEnabled WRITE setStdinEnabled NOTIFY stdinEnabledChanged)
    Q_PROPERTY(QString workingDirectory READ workingDirectory WRITE setWorkingDirectory
                   NOTIFY workingDirectoryChanged)

public:
    explicit Process(QObject* parent = nullptr);

    bool running() const { return m_running; }
    void setRunning(bool r);

    QVariantList command() const { return m_command; }
    void setCommand(const QVariantList& c);

    QObject* stdoutSink() const { return m_stdout; }
    void setStdoutSink(QObject* s);

    QObject* stderrSink() const { return m_stderr; }
    void setStderrSink(QObject* s);

    bool stdinEnabled() const { return m_stdinEnabled; }
    void setStdinEnabled(bool e);

    QString workingDirectory() const { return m_cwd; }
    void setWorkingDirectory(const QString& d);

    Q_INVOKABLE void write(const QString& data);
    Q_INVOKABLE void signal(int sig);

    void classBegin() override { m_complete = false; }
    void componentComplete() override;

signals:
    void runningChanged();
    void commandChanged();
    void stdoutSinkChanged();
    void stderrSinkChanged();
    void stdinEnabledChanged();
    void workingDirectoryChanged();
    void started();
    void exited(int exitCode, int exitStatus);

private:
    void start();
    void stop();

    QProcess* m_proc = nullptr;
    QVariantList m_command;
    QObject* m_stdout = nullptr;
    QObject* m_stderr = nullptr;
    QString m_cwd;
    bool m_running = false;
    bool m_stdinEnabled = true;
    // True for a Process made from C++; QML clears it in classBegin().
    bool m_complete = true;
    bool m_startWhenComplete = false;
};

// ── Quickshell.Io: FileView and its JSON adapter ─────────────────────────────

/**
 * A JSON document mapped onto declared properties.
 *
 * Services/Settings declares the desktop's whole schema inside one of these —
 * seventy-odd `property bool …` lines — and reads and writes it as ordinary QML
 * properties. QML-declared properties are real Qt properties on the generated
 * meta-object, so loading is "for each key in the file, set the property of
 * that name", and saving is the reverse. Keys the schema does not declare are
 * dropped on the way in, which is the behaviour Settings.set() already relies
 * on to refuse a typo.
 */
class JsonAdapter : public QObject {
    Q_OBJECT

public:
    explicit JsonAdapter(QObject* parent = nullptr) : QObject(parent) {}
};

class FileView : public QObject {
    Q_OBJECT
    Q_CLASSINFO("DefaultProperty", "adapter")
    Q_PROPERTY(QObject* adapter READ adapter WRITE setAdapter NOTIFY adapterChanged)
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(bool watchChanges READ watchChanges WRITE setWatchChanges NOTIFY watchChangesChanged)
    Q_PROPERTY(bool atomicWrites READ atomicWrites WRITE setAtomicWrites NOTIFY atomicWritesChanged)
    Q_PROPERTY(bool printErrors READ printErrors WRITE setPrintErrors NOTIFY printErrorsChanged)
    // Quickshell's switch between asynchronous and blocking loads. Loading here
    // is always synchronous, so the value is only stored — but it must exist:
    // Services/Theme sets it, and an unknown property made the whole Services
    // module fail to load, which took b1air-settings down with it.
    Q_PROPERTY(bool blockLoading READ blockLoading WRITE setBlockLoading NOTIFY blockLoadingChanged)

public:
    explicit FileView(QObject* parent = nullptr);

    bool blockLoading() const { return m_blockLoading; }
    void setBlockLoading(bool b) { if (b != m_blockLoading) { m_blockLoading = b; emit blockLoadingChanged(); } }

    QString path() const { return m_path; }
    void setPath(const QString& p);

    bool watchChanges() const { return m_watch; }
    void setWatchChanges(bool w);

    bool atomicWrites() const { return m_atomic; }
    void setAtomicWrites(bool a) { m_atomic = a; emit atomicWritesChanged(); }

    bool printErrors() const { return m_printErrors; }
    void setPrintErrors(bool p) { m_printErrors = p; emit printErrorsChanged(); }

    QObject* adapter() const { return m_adapter; }
    void setAdapter(QObject* a);

    Q_INVOKABLE QString text() const { return m_text; }
    Q_INVOKABLE void setText(const QString& t);
    Q_INVOKABLE void reload();
    /** Serialise the adapter's declared properties over the file. */
    Q_INVOKABLE void writeAdapter();

signals:
    void adapterChanged();
    void pathChanged();
    void watchChangesChanged();
    void atomicWritesChanged();
    void printErrorsChanged();
    void blockLoadingChanged();
    void loaded();
    void loadFailed();
    void fileChanged();

private:
    void rewatch();
    void applyToAdapter();

    QObject* m_adapter = nullptr;
    QString m_path;
    QString m_text;
    QFileSystemWatcher m_watcher;
    bool m_watch = false;
    bool m_atomic = false;
    bool m_printErrors = true;
    bool m_blockLoading = false;
    bool m_writing = false;
};

// ── Quickshell: the singleton ────────────────────────────────────────────────

class Quickshell : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList screens READ screens NOTIFY screensChanged)

public:
    explicit Quickshell(QObject* parent = nullptr);

    QVariantList screens() const;

    Q_INVOKABLE QString env(const QString& name) const;
    Q_INVOKABLE void execDetached(const QVariant& command) const;

signals:
    void screensChanged();
};

/**
 * `Singleton` is a marker in Quickshell — a root type for a file carrying
 * `pragma Singleton`. Here it is a plain QObject with the same name, so the
 * Services files keep parsing unchanged.
 */
class Singleton : public QObject {
    Q_OBJECT
    // Services files put Process, Timer and Connections objects straight inside
    // their root. A bare QObject has nowhere to hold them — "Cannot assign to
    // non-existent default property" — so it needs the same `data` list every
    // QML container has.
    Q_CLASSINFO("DefaultProperty", "data")
    Q_PROPERTY(QQmlListProperty<QObject> data READ data)

public:
    explicit Singleton(QObject* parent = nullptr) : QObject(parent) {}

    QQmlListProperty<QObject> data() {
        return QQmlListProperty<QObject>(this, &m_data);
    }

private:
    QList<QObject*> m_data;
};

/** Registers Process, FileView, the stream readers, Singleton and Quickshell. */
void registerCoreTypes();

/**
 * Where the plugin-free qmldir tree lives, to be added to an engine's import
 * path ahead of the default one. Installed beside the binaries rather than on
 * any path the shell searches: the `quickshell` process must keep finding the
 * real module.
 */
QString moduleDir();

} // namespace qscompat
