#include "qs_compat.hpp"

#include <QDir>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaProperty>
#include <QSaveFile>
#include <QScreen>
#include <QTextStream>
#include <QTimer>

#include <csignal>

namespace qscompat {

// ── StdioCollector ───────────────────────────────────────────────────────────

void StdioCollector::append(const QByteArray& chunk) {
    m_text += QString::fromUtf8(chunk);
    emit textChanged();
}

void StdioCollector::finish() {
    emit streamFinished();
}

// ── SplitParser ──────────────────────────────────────────────────────────────

void SplitParser::setSplitMarker(const QString& m) {
    if (m == m_marker)
        return;
    m_marker = m;
    emit splitMarkerChanged();
}

void SplitParser::append(const QByteArray& chunk) {
    m_buffer += QString::fromUtf8(chunk);
    if (m_marker.isEmpty())
        return;

    int idx;
    while ((idx = m_buffer.indexOf(m_marker)) >= 0) {
        const QString record = m_buffer.left(idx);
        m_buffer.remove(0, idx + m_marker.size());
        emit read(record);
    }
}

void SplitParser::finish() {
    // A trailing fragment with no marker after it is not a record. Emitting it
    // anyway is how a half-written line becomes a clipboard entry.
    m_buffer.clear();
}

// ── Process ──────────────────────────────────────────────────────────────────

Process::Process(QObject* parent) : QObject(parent) {}

void Process::setCommand(const QVariantList& c) {
    if (c == m_command)
        return;
    m_command = c;
    emit commandChanged();
}

void Process::setStdoutSink(QObject* s) {
    if (s == m_stdout)
        return;
    m_stdout = s;
    emit stdoutSinkChanged();
}

void Process::setStderrSink(QObject* s) {
    if (s == m_stderr)
        return;
    m_stderr = s;
    emit stderrSinkChanged();
}

void Process::setStdinEnabled(bool e) {
    if (e == m_stdinEnabled)
        return;
    m_stdinEnabled = e;
    // Closing stdin is how a caller says "that is all the input there is", and
    // the reader on the other end is waiting for exactly that.
    if (!e && m_proc && m_proc->state() != QProcess::NotRunning)
        m_proc->closeWriteChannel();
    emit stdinEnabledChanged();
}

void Process::setWorkingDirectory(const QString& d) {
    if (d == m_cwd)
        return;
    m_cwd = d;
    emit workingDirectoryChanged();
}

void Process::componentComplete() {
    m_complete = true;
    if (m_startWhenComplete) {
        m_startWhenComplete = false;
        start();
    }
}

void Process::setRunning(bool r) {
    if (!m_complete) {
        m_startWhenComplete = r;
        return;
    }
    if (r == m_running)
        return;
    if (r)
        start();
    else
        stop();
}

void Process::start() {
    if (m_command.isEmpty())
        return;

    QStringList argv;
    for (const QVariant& v : m_command)
        argv << v.toString();
    if (argv.isEmpty())
        return;

    const QString program = argv.takeFirst();

    delete m_proc;
    m_proc = new QProcess(this);
    if (!m_cwd.isEmpty())
        m_proc->setWorkingDirectory(m_cwd);

    const auto feed = [](QObject* sink, const QByteArray& chunk) {
        if (auto* c = qobject_cast<StdioCollector*>(sink))
            c->append(chunk);
        else if (auto* p = qobject_cast<SplitParser*>(sink))
            p->append(chunk);
    };

    connect(m_proc, &QProcess::readyReadStandardOutput, this, [this, feed]() {
        feed(m_stdout, m_proc->readAllStandardOutput());
    });
    connect(m_proc, &QProcess::readyReadStandardError, this, [this, feed]() {
        feed(m_stderr, m_proc->readAllStandardError());
    });

    connect(m_proc, &QProcess::finished, this,
            [this](int code, QProcess::ExitStatus status) {
        // The collector hands its text over on close, so this has to happen
        // before `running` drops: a handler reacting to exited() and reading
        // the text would otherwise see the previous run's.
        for (QObject* sink : {m_stdout, m_stderr}) {
            if (auto* c = qobject_cast<StdioCollector*>(sink))
                c->finish();
            else if (auto* p = qobject_cast<SplitParser*>(sink))
                p->finish();
        }

        m_running = false;
        emit runningChanged();
        emit exited(code, static_cast<int>(status));
    });

    connect(m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        if (m_running) {
            m_running = false;
            emit runningChanged();
        }
    });

    for (QObject* sink : {m_stdout, m_stderr})
        if (auto* c = qobject_cast<StdioCollector*>(sink))
            c->reset();

    m_proc->start(program, argv);
    m_running = true;
    emit runningChanged();

    // started() has to reach QML after the binding that set `running` has
    // finished, or an onStarted handler calling write() runs before the
    // process exists.
    QTimer::singleShot(0, this, [this]() {
        if (m_running)
            emit started();
    });
}

void Process::stop() {
    if (m_proc && m_proc->state() != QProcess::NotRunning) {
        m_proc->terminate();
        if (!m_proc->waitForFinished(200))
            m_proc->kill();
    }
    if (m_running) {
        m_running = false;
        emit runningChanged();
    }
}

void Process::write(const QString& data) {
    if (m_proc && m_proc->state() != QProcess::NotRunning)
        m_proc->write(data.toUtf8());
}

void Process::signal(int sig) {
    if (m_proc && m_proc->processId() > 0)
        ::kill(static_cast<pid_t>(m_proc->processId()), sig);
}

// ── FileView ─────────────────────────────────────────────────────────────────

FileView::FileView(QObject* parent) : QObject(parent) {
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this]() {
        if (m_writing)
            return;
        emit fileChanged();
        rewatch();
    });
}

void FileView::setPath(const QString& p) {
    if (p == m_path)
        return;
    m_path = p;
    emit pathChanged();
    rewatch();
    reload();
}

void FileView::setWatchChanges(bool w) {
    if (w == m_watch)
        return;
    m_watch = w;
    emit watchChangesChanged();
    rewatch();
}

void FileView::rewatch() {
    if (!m_watcher.files().isEmpty())
        m_watcher.removePaths(m_watcher.files());
    if (m_watch && !m_path.isEmpty() && QFile::exists(m_path))
        m_watcher.addPath(m_path);
}

void FileView::reload() {
    if (m_path.isEmpty()) {
        emit loadFailed();
        return;
    }

    QFile f(m_path);
    if (!f.open(QIODevice::ReadOnly)) {
        if (m_printErrors)
            QTextStream(stderr) << "[qs-compat] cannot read " << m_path << "\n";
        emit loadFailed();
        return;
    }

    m_text = QString::fromUtf8(f.readAll());
    f.close();
    applyToAdapter();
    emit loaded();
}

void FileView::setAdapter(QObject* a) {
    if (a == m_adapter)
        return;
    m_adapter = a;
    emit adapterChanged();
    // The adapter is usually declared after `path`, so whatever was already
    // read has to be pushed into it now or the schema starts on its defaults.
    if (!m_text.isEmpty())
        applyToAdapter();
}

void FileView::applyToAdapter() {
    if (!m_adapter || m_text.isEmpty())
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(m_text.toUtf8());
    if (!doc.isObject())
        return;
    const QJsonObject obj = doc.object();

    const QMetaObject* mo = m_adapter->metaObject();
    // From offset 1: index 0 is QObject::objectName, which is not schema.
    for (int i = 1; i < mo->propertyCount(); ++i) {
        const QMetaProperty prop = mo->property(i);
        const auto it = obj.constFind(QString::fromUtf8(prop.name()));
        if (it == obj.constEnd())
            continue;
        m_adapter->setProperty(prop.name(), it->toVariant());
    }
}

void FileView::writeAdapter() {
    if (!m_adapter)
        return;

    QJsonObject obj;
    const QMetaObject* mo = m_adapter->metaObject();
    for (int i = 1; i < mo->propertyCount(); ++i) {
        const QMetaProperty prop = mo->property(i);
        obj.insert(QString::fromUtf8(prop.name()),
                   QJsonValue::fromVariant(m_adapter->property(prop.name())));
    }
    setText(QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Indented)));
}

void FileView::setText(const QString& t) {
    if (m_path.isEmpty())
        return;

    m_text = t;
    m_writing = true;

    bool ok = false;
    if (m_atomic) {
        QSaveFile f(m_path);
        ok = f.open(QIODevice::WriteOnly) && f.write(t.toUtf8()) != -1 && f.commit();
    } else {
        QFile f(m_path);
        ok = f.open(QIODevice::WriteOnly) && f.write(t.toUtf8()) != -1;
        f.close();
    }

    m_writing = false;
    rewatch();

    if (!ok && m_printErrors)
        QTextStream(stderr) << "[qs-compat] cannot write " << m_path << "\n";
}

// ── Quickshell ───────────────────────────────────────────────────────────────

Quickshell::Quickshell(QObject* parent) : QObject(parent) {
    if (auto* app = qGuiApp) {
        connect(app, &QGuiApplication::screenAdded, this, &Quickshell::screensChanged);
        connect(app, &QGuiApplication::screenRemoved, this, &Quickshell::screensChanged);
    }
}

QVariantList Quickshell::screens() const {
    QVariantList out;
    for (QScreen* s : QGuiApplication::screens()) {
        QVariantMap m;
        m["name"] = s->name();
        m["width"] = s->geometry().width();
        m["height"] = s->geometry().height();
        m["x"] = s->geometry().x();
        m["y"] = s->geometry().y();
        out.append(m);
    }
    return out;
}

QString Quickshell::env(const QString& name) const {
    return qEnvironmentVariable(name.toUtf8().constData());
}

void Quickshell::execDetached(const QVariant& command) const {
    QStringList argv;
    if (command.canConvert<QVariantList>()) {
        for (const QVariant& v : command.toList())
            argv << v.toString();
    } else {
        argv << command.toString();
    }
    if (argv.isEmpty())
        return;

    const QString program = argv.takeFirst();
    QProcess::startDetached(program, argv);
}

void registerCoreTypes() {
    qmlRegisterType<Process>("Quickshell.Io", 1, 0, "Process");
    qmlRegisterType<FileView>("Quickshell.Io", 1, 0, "FileView");
    qmlRegisterType<StdioCollector>("Quickshell.Io", 1, 0, "StdioCollector");
    qmlRegisterType<SplitParser>("Quickshell.Io", 1, 0, "SplitParser");
    qmlRegisterType<JsonAdapter>("Quickshell.Io", 1, 0, "JsonAdapter");

    qmlRegisterType<Singleton>("Quickshell", 1, 0, "Singleton");
    qmlRegisterSingletonType<Quickshell>(
        "Quickshell", 1, 0, "Quickshell",
        [](QQmlEngine*, QJSEngine*) -> QObject* { return new Quickshell(); });
}

QString moduleDir() {
    // A checkout first when one is being worked in, then the installed copy.
    const QString home = QDir::homePath();
    const QStringList candidates = {
        home + "/.local/share/b1air-qs-compat",
        "/usr/share/b1air-shell/qs-compat",
        "/usr/local/share/b1air-shell/qs-compat",
    };
    for (const QString& c : candidates)
        if (QFile::exists(c + "/Quickshell/qmldir"))
            return c;
    return candidates.first();
}

} // namespace qscompat
