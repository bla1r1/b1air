#pragma once

#include <QObject>
#include <QString>
#include <QHash>
#include <QVariantList>
#include <QVariantMap>
#include <QTimer>
#include <QAbstractListModel>
#include <vector>

namespace b1air {

struct ProcessInfo {
    int pid = 0;
    float cpu = 0.0f;
    float mem = 0.0f;
    QString user;
    QString name;
};

class ProcessModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum ProcessRoles {
        PidRole = Qt::UserRole + 1,
        CpuRole,
        MemRole,
        UserRole,
        NameRole
    };

    explicit ProcessModel(QObject* parent = nullptr);
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void updateProcesses(const std::vector<ProcessInfo>& procs);
    void setFilter(const QString& filter);
    void setSort(const QString& field);

private:
    std::vector<ProcessInfo> m_all;
    std::vector<ProcessInfo> m_filtered;
    QString m_filter;
    QString m_sortField = "cpu";
    void applyFilterAndSort();
};

class MonitorBackend : public QObject {
    Q_OBJECT
    // Every process on the system, before the filter.
    Q_PROPERTY(int taskCount READ taskCount NOTIFY tasksChanged)

    Q_PROPERTY(qreal cpuPercent READ cpuPercent NOTIFY cpuChanged)
    Q_PROPERTY(QString cpuModel READ cpuModel NOTIFY sysInfoChanged)
    Q_PROPERTY(int cores READ cores NOTIFY sysInfoChanged)

    Q_PROPERTY(qreal ramUsedMb READ ramUsedMb NOTIFY ramChanged)
    Q_PROPERTY(qreal ramTotalMb READ ramTotalMb NOTIFY ramChanged)
    Q_PROPERTY(qreal ramPercent READ ramPercent NOTIFY ramChanged)

    Q_PROPERTY(qreal swapUsedMb READ swapUsedMb NOTIFY swapChanged)
    Q_PROPERTY(qreal swapTotalMb READ swapTotalMb NOTIFY swapChanged)

    Q_PROPERTY(qreal diskTotalGb READ diskTotalGb NOTIFY diskChanged)
    Q_PROPERTY(qreal diskFreeGb READ diskFreeGb NOTIFY diskChanged)
    Q_PROPERTY(qreal diskPercent READ diskPercent NOTIFY diskChanged)

    Q_PROPERTY(QString uptime READ uptime NOTIFY uptimeChanged)
    Q_PROPERTY(QString loadAvg READ loadAvg NOTIFY loadAvgChanged)

    Q_PROPERTY(QVariantList cpuHistory READ cpuHistory NOTIFY historyChanged)
    Q_PROPERTY(QVariantList ramHistory READ ramHistory NOTIFY historyChanged)

    Q_PROPERTY(ProcessModel* processes READ processes CONSTANT)

public:
    explicit MonitorBackend(QObject* parent = nullptr);
    virtual ~MonitorBackend() = default;

    qreal cpuPercent() const { return m_cpuPercent; }
    QString cpuModel() const { return m_cpuModel; }
    int cores() const { return m_cores; }

    qreal ramUsedMb() const { return m_ramUsedMb; }
    qreal ramTotalMb() const { return m_ramTotalMb; }
    qreal ramPercent() const { return m_ramPercent; }

    qreal swapUsedMb() const { return m_swapUsedMb; }
    qreal swapTotalMb() const { return m_swapTotalMb; }

    qreal diskTotalGb() const { return m_diskTotalGb; }
    qreal diskFreeGb() const { return m_diskFreeGb; }
    qreal diskPercent() const { return m_diskPercent; }

    QString uptime() const { return m_uptime; }
    QString loadAvg() const { return m_loadAvg; }

    QVariantList cpuHistory() const { return m_cpuHistory; }
    QVariantList ramHistory() const { return m_ramHistory; }

    ProcessModel* processes() const { return m_procModel; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool killProcess(int pid, bool force = false);
    int taskCount() const { return m_taskCount; }
    Q_INVOKABLE void setProcessFilter(const QString& query);
    Q_INVOKABLE void setProcessSort(const QString& sortBy);

signals:
    void cpuChanged();
    void sysInfoChanged();
    void ramChanged();
    void swapChanged();
    void diskChanged();
    void uptimeChanged();
    void loadAvgChanged();
    void historyChanged();
    void tasksChanged();
    /** A kill that failed, in words (not permitted, already gone). */
    void killFailed(const QString& message);

private slots:
    void poll();

private:
    void updateCpu();
    void updateMemory();
    void updateDisk();
    void updateLoadAndUptime();
    void updateProcesses();

    qreal m_cpuPercent = 0.0;
    QString m_cpuModel = "CPU";
    int m_cores = 4;

    qreal m_ramUsedMb = 0.0;
    qreal m_ramTotalMb = 0.0;
    qreal m_ramPercent = 0.0;

    qreal m_swapUsedMb = 0.0;
    qreal m_swapTotalMb = 0.0;

    qreal m_diskTotalGb = 0.0;
    qreal m_diskFreeGb = 0.0;
    qreal m_diskPercent = 0.0;

    QString m_uptime;
    QString m_loadAvg;

    QVariantList m_cpuHistory;
    QVariantList m_ramHistory;

    ProcessModel* m_procModel = nullptr;
    QTimer* m_timer = nullptr;

    unsigned long long m_prevIdle = 0;
    unsigned long long m_prevTotal = 0;

    // Per-process CPU time at the previous sample, for current usage.
    QHash<int, unsigned long long> m_prevProcTicks;
    qint64 m_prevProcSampleMs = 0;
    QHash<uint, QString> m_userNames;
    int m_taskCount = 0;
};

} // namespace b1air
