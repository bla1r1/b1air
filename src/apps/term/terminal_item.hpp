#pragma once

#include <QQuickPaintedItem>
#include <QUrl>
#include <QFont>
#include <QFontMetricsF>
#include <QSocketNotifier>
#include <QByteArray>
#include <QColor>
#include <QVariantList>
#include <QTimer>
#include <vterm.h>
#include <sys/types.h>
#include <deque>
#include <vector>

namespace b1air {

class TerminalItem : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(int fontSize READ fontSize WRITE setFontSize NOTIFY fontSizeChanged)
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY fontFamilyChanged)
    Q_PROPERTY(int cols READ cols NOTIFY sizeChanged)
    Q_PROPERTY(int rows READ rows NOTIFY sizeChanged)

    // The terminal's own two colours, so it follows the desktop theme:
    // TermWindow binds these to Ui/Design, which reads the active theme in
    // every process.
    Q_PROPERTY(QColor backgroundColor READ backgroundColor WRITE setBackgroundColor NOTIFY paletteChanged)
    Q_PROPERTY(QColor foregroundColor READ foregroundColor WRITE setForegroundColor NOTIFY paletteChanged)
    // The sixteen ANSI colours, black to bright white, from the desktop
    // theme (TermWindow builds them from Ui/Design). Empty: the built-in
    // sets below, one for a dark background and one for a light.
    Q_PROPERTY(QVariantList ansiColors READ ansiColors WRITE setAnsiColors NOTIFY paletteChanged)

public:
    explicit TerminalItem(QQuickItem *parent = nullptr);
    ~TerminalItem() override;

    QString title() const { return m_title; }
    int fontSize() const { return m_fontSize; }
    void setFontSize(int size);

    QString fontFamily() const { return m_fontFamily; }
    void setFontFamily(const QString &family);

    int cols() const { return m_cols; }
    int rows() const { return m_rows; }

    QColor backgroundColor() const { return m_background; }
    void setBackgroundColor(const QColor &c);
    QColor foregroundColor() const { return m_foreground; }
    QVariantList ansiColors() const;
    void setAnsiColors(const QVariantList &colors);
    void setForegroundColor(const QColor &c);

    Q_INVOKABLE void sendText(const QString &text);
    Q_INVOKABLE void copySelection();
    Q_INVOKABLE void pasteClipboard();
    /** Text as if pasted (bracketed when the program asked for it). */
    Q_INVOKABLE void pasteText(const QString& text);
    /** Files dropped on the terminal: their paths, quoted, typed in. */
    Q_INVOKABLE void dropUrls(const QStringList& urls);
    Q_INVOKABLE void zoomIn();
    Q_INVOKABLE void zoomOut();
    Q_INVOKABLE void resetZoom();
    Q_INVOKABLE void clear();
    Q_INVOKABLE void launch(const QString &command = QString(), const QString &workingDir = QString());
    /** Where the shell is now (after its cd's), or "" when that cannot be read. */
    Q_INVOKABLE QString currentDirectory() const;
    // A line drawn on the screen as if the program had printed it, for
    // after it has gone (b1air-term --hold).
    Q_INVOKABLE void showNotice(const QString &text);

signals:
    void titleChanged();
    void fontSizeChanged();
    void fontFamilyChanged();
    void sizeChanged();
    void paletteChanged();
    void processFinished(int exitCode);
    // A key pressed once the program has ended.
    void keyAfterExit();

protected:
    void paint(QPainter *painter) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void keyPressEvent(QKeyEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void keyReleaseEvent(QKeyEvent *event) override;
    void hoverMoveEvent(QHoverEvent *event) override;
    void hoverLeaveEvent(QHoverEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;

private slots:
    void onPtyRead();
    void onBlink();

private:
    void initTerminal(int rows, int cols);
    void childExited();
    void restartBlink();
    void updateRows(int from, int to);   // rows [from, to) of the live screen
    void updateFontMetrics();
    void updatePtySize();
    QColor toQColor(const VTermColor &color, const QColor &defaultColor) const;

    // Defaults match the constants these replaced, so a build that never binds
    // them looks exactly as it did.
    QColor m_background{0x20, 0x23, 0x26};   // Breeze Dark, until bound
    QColor m_foreground{0xfc, 0xfc, 0xfc};
    QColor m_ansi[16];
    bool m_hasAnsi = false;

    // libvterm callbacks
    static int cbDamage(VTermRect rect, void *user);
    static int cbMoverect(VTermRect dest, VTermRect src, void *user);
    static int cbMovecursor(VTermPos pos, VTermPos oldpos, int visible, void *user);
    static int cbSettermprop(VTermProp prop, VTermValue *val, void *user);
    static int cbBell(void *user);
    static int cbResize(int rows, int cols, void *user);
    static int cbSbPushline(int cols, const VTermScreenCell *cells, void *user);
    static int cbSbPopline(int cols, VTermScreenCell *cells, void *user);
    static void cbOutput(const char *s, size_t len, void *user);

    VTermScreenCallbacks m_screenCallbacks = {};

    int m_masterFd = -1;
    pid_t m_childPid = -1;

    VTerm *m_vt = nullptr;
    VTermScreen *m_vts = nullptr;
    QSocketNotifier *m_notifier = nullptr;
    // Output read from the pty but not yet parsed — see onPtyRead().
    QByteArray m_pending;
    QTimer m_drainTimer;

    QFont m_font;
    qreal m_cellWidth = 10.0;
    qreal m_cellHeight = 20.0;
    qreal m_fontAscent = 15.0;

    int m_cols = 80;
    int m_rows = 24;
    int m_fontSize = 11;
    QString m_fontFamily = "JetBrainsMono Nerd Font Mono";
    QString m_title = "Terminal";

    VTermPos m_cursorPos = {0, 0};
    bool m_cursorVisible = true;

    // A thin bar that blinks, until the program asks for something else with
    // DECSCUSR (vi modes ask for a block). It was always a solid block.
    int m_cursorShape = VTERM_PROP_CURSORSHAPE_BAR_LEFT;
    bool m_cursorBlinks = true;
    bool m_blinkOn = true;
    QTimer m_blinkTimer;
    bool m_finished = false;

    bool m_selecting = false;
    VTermPos m_selStart = {0, 0};
    VTermPos m_selEnd = {0, 0};
    bool m_hasSelection = false;

    // Click-count tracking for double-click (word) / triple-click (line)
    // selection — Qt only auto-delivers one mouseDoubleClickEvent per pair,
    // so a third click in the same spot is counted here by hand.
    int m_clickCount = 0;
    qint64 m_lastClickMs = 0;
    VTermPos m_lastClickPos = {-1, -1};
    void selectWordAt(VTermPos pos);
    void selectLineAt(int row);

    std::deque<std::vector<VTermScreenCell>> m_scrollback;
    int m_viewOffset = 0;

    // The cell shown at (row, col) of the window: the live screen, or the
    // history when scrolled back. What paint draws and what links are read
    // from, so the two agree.
    void viewCell(int row, int col, VTermScreenCell *cell) const;

    // Links: an address in the text (http, https, ftp, file, www.), across
    // the rows it wraps over. Ctrl shows the one under the pointer, underlined,
    // and Ctrl+click opens it, as in Konsole and GNOME Terminal.
    struct Link {
        QString url;
        VTermPos start = {-1, -1};
        VTermPos end = {-1, -1};     // the last cell, inclusive
        bool valid() const { return !url.isEmpty(); }
    };
    Link linkAt(VTermPos pos) const;
    void updateHoverLink(Qt::KeyboardModifiers mods);
    Link m_hoverLink;
    QPointF m_hoverPoint{-1, -1};

    // What the running program asked for, so the wheel can do what it expects.
    int m_mouseMode = 0;        // VTERM_PROP_MOUSE_*: nonzero = it wants mouse events
    // Clicks and drags go to such a program, as in xterm; Shift held makes
    // them select here instead. True from a forwarded press to its release.
    bool m_mouseForwarding = false;
    bool forwardMouse(QMouseEvent *event, bool pressed);
    bool m_altScreen = false;   // less, man, htop, an editor
    int m_wheelAccum = 0;       // eighths of a degree not yet turned into lines

    // OSC 52: a program putting text on the clipboard (Claude Code, nvim,
    // tmux — over ssh too). libvterm decodes the base64 into fragments.
    static int cbSelectionSet(VTermSelectionMask mask, VTermStringFragment frag, void *user);
    VTermSelectionCallbacks m_selectionCallbacks{};
    char m_selectionBuf[4096];
    QByteArray m_osc52;
};

} // namespace b1air
