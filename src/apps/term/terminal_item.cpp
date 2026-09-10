#include "terminal_item.hpp"

#include <QPainter>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QClipboard>
#include <QGuiApplication>
#include <QDateTime>
#include <QStyleHints>
#include <pty.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <cmath>
#include <utility>
#include <iostream>

namespace b1air {

// Default Catppuccin Mocha Palette
static const QColor MochaBase(30, 30, 46);         // #1e1e2e
static const QColor MochaText(205, 214, 244);       // #cdd6f4
static const QColor MochaSubtext0(166, 173, 200);   // #a6adc8
static const QColor MochaSurface0(49, 50, 68);      // #313244
static const QColor MochaSurface2(88, 91, 112);     // #585b70
static const QColor MochaBlue(137, 180, 250);       // #89b4fa
static const QColor MochaRed(243, 139, 168);        // #f38ba8
static const QColor MochaGreen(166, 227, 161);      // #a6e3a1
static const QColor MochaYellow(249, 226, 175);     // #f9e2af
static const QColor MochaPeach(250, 179, 135);      // #fab387
static const QColor MochaTeal(148, 226, 213);       // #94e2d5
static const QColor MochaSapphire(116, 199, 236);   // #74c7ec
static const QColor MochaLavender(180, 190, 254);   // #b4befe

TerminalItem::TerminalItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setFlag(ItemHasContents, true);
    setFlag(ItemIsFocusScope, true);
    setAcceptedMouseButtons(Qt::AllButtons);
    setAcceptHoverEvents(true);

    updateFontMetrics();
    initTerminal(m_rows, m_cols);
}

TerminalItem::~TerminalItem() {
    if (m_notifier) {
        delete m_notifier;
        m_notifier = nullptr;
    }
    if (m_masterFd >= 0) {
        close(m_masterFd);
        m_masterFd = -1;
    }
    if (m_childPid > 0) {
        kill(m_childPid, SIGHUP);
        waitpid(m_childPid, nullptr, WNOHANG);
    }
    if (m_vt) {
        vterm_free(m_vt);
        m_vt = nullptr;
    }
}

void TerminalItem::initTerminal(int rows, int cols) {
    if (m_vt) {
        vterm_free(m_vt);
    }

    m_vt = vterm_new(rows, cols);
    vterm_set_utf8(m_vt, 1);
    m_vts = vterm_obtain_screen(m_vt);
    vterm_screen_enable_altscreen(m_vts, 1);

    memset(&m_screenCallbacks, 0, sizeof(m_screenCallbacks));
    m_screenCallbacks.damage = cbDamage;
    m_screenCallbacks.moverect = cbMoverect;
    m_screenCallbacks.movecursor = cbMovecursor;
    m_screenCallbacks.settermprop = cbSettermprop;
    m_screenCallbacks.bell = cbBell;
    m_screenCallbacks.resize = cbResize;
    m_screenCallbacks.sb_pushline = cbSbPushline;
    m_screenCallbacks.sb_popline = cbSbPopline;

    vterm_screen_set_callbacks(m_vts, &m_screenCallbacks, this);
    vterm_screen_reset(m_vts, 1);
    vterm_output_set_callback(m_vt, cbOutput, this);
}

void TerminalItem::updateFontMetrics() {
    m_font = QFont(m_fontFamily, m_fontSize);
    m_font.setStyleHint(QFont::Monospace);
    m_font.setFixedPitch(true);

    QFontMetricsF fm(m_font);
    m_cellWidth = fm.horizontalAdvance('M');
    if (m_cellWidth <= 0) m_cellWidth = 8.5;
    m_cellHeight = std::ceil(fm.lineSpacing());
    if (m_cellHeight <= 0) m_cellHeight = 18.0;
    m_fontAscent = fm.ascent();
}

void TerminalItem::setFontSize(int size) {
    if (size < 8 || size > 32 || size == m_fontSize) return;
    m_fontSize = size;
    updateFontMetrics();
    updatePtySize();
    emit fontSizeChanged();
    update();
}

void TerminalItem::setFontFamily(const QString &family) {
    if (family.isEmpty() || family == m_fontFamily) return;
    m_fontFamily = family;
    updateFontMetrics();
    updatePtySize();
    emit fontFamilyChanged();
    update();
}

void TerminalItem::launch(const QString &command, const QString &workingDir) {
    if (m_masterFd >= 0) return; // already launched

    int slaveFd = -1;
    if (openpty(&m_masterFd, &slaveFd, nullptr, nullptr, nullptr) < 0) {
        std::cerr << "[b1air-term] openpty failed\n";
        return;
    }

    // Set master non-blocking
    int flags = fcntl(m_masterFd, F_GETFL, 0);
    fcntl(m_masterFd, F_SETFL, flags | O_NONBLOCK);

    m_childPid = fork();
    if (m_childPid < 0) {
        std::cerr << "[b1air-term] fork failed\n";
        close(m_masterFd);
        close(slaveFd);
        m_masterFd = -1;
        return;
    }

    if (m_childPid == 0) {
        // Child
        close(m_masterFd);

        if (!workingDir.isEmpty()) {
            chdir(workingDir.toUtf8().constData());
        } else {
            const char *home = getenv("HOME");
            if (home) chdir(home);
        }

        setsid();
        ioctl(slaveFd, TIOCSCTTY, 0);

        dup2(slaveFd, 0);
        dup2(slaveFd, 1);
        dup2(slaveFd, 2);
        if (slaveFd > 2) close(slaveFd);

        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);

        const char *currPath = getenv("PATH");
        QString newPath = QString("%1/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin").arg(getenv("HOME") ? getenv("HOME") : "/home/dev");
        if (currPath && strlen(currPath) > 0) newPath += ":" + QString(currPath);
        setenv("PATH", newPath.toUtf8().constData(), 1);

        if (!command.isEmpty()) {
            const char *shell = access("/usr/bin/fish", X_OK) == 0 ? "/usr/bin/fish" : "/bin/sh";
            execlp(shell, shell, "-l", "-c", command.toUtf8().constData(), (char*)nullptr);
        } else {
            const char *shell = getenv("SHELL");
            if (!shell || strcmp(shell, "/bin/sh") == 0) {
                if (access("/usr/bin/fish", X_OK) == 0) shell = "/usr/bin/fish";
                else if (access("/bin/bash", X_OK) == 0) shell = "/bin/bash";
                else shell = "/bin/sh";
            }
            execlp(shell, shell, "-l", (char*)nullptr);
        }
        _exit(127);
    }

    // Parent
    close(slaveFd);

    m_notifier = new QSocketNotifier(m_masterFd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &TerminalItem::onPtyRead);

    updatePtySize();
}

void TerminalItem::onPtyRead() {
    if (m_masterFd < 0) return;

    char buf[8192];
    while (true) {
        ssize_t n = read(m_masterFd, buf, sizeof(buf));
        if (n > 0) {
            vterm_input_write(m_vt, buf, n);
        } else {
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                break; // read all currently available bytes
            }
            // Child closed PTY
            emit processFinished(0);
            break;
        }
    }

    vterm_screen_flush_damage(m_vts);
    update();
}

void TerminalItem::updatePtySize() {
    if (m_cellWidth <= 0 || m_cellHeight <= 0 || width() <= 0 || height() <= 0) return;

    int newCols = std::max(10, (int)(width() / m_cellWidth));
    int newRows = std::max(4, (int)(height() / m_cellHeight));

    if (newCols != m_cols || newRows != m_rows) {
        m_cols = newCols;
        m_rows = newRows;
        if (m_vt) {
            vterm_set_size(m_vt, m_rows, m_cols);
            vterm_screen_flush_damage(m_vts);
        }

        if (m_masterFd >= 0) {
            struct winsize ws;
            ws.ws_col = m_cols;
            ws.ws_row = m_rows;
            ws.ws_xpixel = width();
            ws.ws_ypixel = height();
            ioctl(m_masterFd, TIOCSWINSZ, &ws);
        }

        emit sizeChanged();
        update();
    }
}

void TerminalItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) {
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    updatePtySize();
}

void TerminalItem::setBackgroundColor(const QColor &c) {
    if (!c.isValid() || c == m_background) return;
    m_background = c;
    emit paletteChanged();
    update();
}

void TerminalItem::setForegroundColor(const QColor &c) {
    if (!c.isValid() || c == m_foreground) return;
    m_foreground = c;
    emit paletteChanged();
    update();
}

QColor TerminalItem::toQColor(const VTermColor &color, const QColor &defaultColor) const {
    if (VTERM_COLOR_IS_RGB(&color)) {
        return QColor(color.rgb.red, color.rgb.green, color.rgb.blue);
    }
    if (VTERM_COLOR_IS_INDEXED(&color)) {
        // Basic 16 colors mapping to Catppuccin Mocha
        static const QColor ansi16[16] = {
            QColor(69, 71, 90),    // 0: Black (Surface1)
            MochaRed,              // 1: Red
            MochaGreen,            // 2: Green
            MochaYellow,           // 3: Yellow
            MochaBlue,             // 4: Blue
            QColor(245, 194, 231), // 5: Magenta (Pink)
            MochaTeal,             // 6: Cyan (Teal)
            QColor(186, 194, 222), // 7: White (Subtext1)
            QColor(88, 91, 112),   // 8: Bright Black (Surface2)
            MochaRed,              // 9: Bright Red
            MochaGreen,            // 10: Bright Green
            MochaYellow,           // 11: Bright Yellow
            MochaSapphire,         // 12: Bright Blue
            MochaLavender,         // 13: Bright Magenta
            MochaTeal,             // 14: Bright Cyan
            MochaText              // 15: Bright White
        };
        if (color.indexed.idx < 16) {
            return ansi16[color.indexed.idx];
        }
    }
    return defaultColor;
}

void TerminalItem::paint(QPainter *painter) {
    if (!m_vts || width() <= 0 || height() <= 0) return;

    painter->setFont(m_font);
    painter->setRenderHint(QPainter::TextAntialiasing, true);

    // Background fill
    painter->fillRect(boundingRect(), m_background);

    // Draw cells
    for (int row = 0; row < m_rows; ++row) {
        int col = 0;
        while (col < m_cols) {
            VTermPos pos = { row, col };
            VTermScreenCell cell;
            if (m_viewOffset == 0) {
                vterm_screen_get_cell(m_vts, pos, &cell);
            } else {
                const int total = static_cast<int>(m_scrollback.size()) + m_rows;
                const int sourceRow = total - m_rows - m_viewOffset + row;
                if (sourceRow < 0 || sourceRow >= total) {
                    std::memset(&cell, 0, sizeof(cell));
                    cell.width = 1;
                } else if (sourceRow < static_cast<int>(m_scrollback.size())) {
                    cell = m_scrollback[static_cast<size_t>(sourceRow)][static_cast<size_t>(col)];
                } else {
                    vterm_screen_get_cell(m_vts, {sourceRow - static_cast<int>(m_scrollback.size()), col}, &cell);
                }
            }

            int widthInCells = cell.width > 0 ? cell.width : 1;

            qreal x = col * m_cellWidth;
            qreal y = row * m_cellHeight;
            QRectF cellRect(x, y, m_cellWidth * widthInCells, m_cellHeight);

            // Selection check
            bool isSelected = false;
            if (m_hasSelection) {
                int r1 = std::min(m_selStart.row, m_selEnd.row);
                int r2 = std::max(m_selStart.row, m_selEnd.row);
                if (row >= r1 && row <= r2) {
                    int c1 = (row == r1) ? ((m_selStart.row <= m_selEnd.row) ? m_selStart.col : m_selEnd.col) : 0;
                    int c2 = (row == r2) ? ((m_selStart.row <= m_selEnd.row) ? m_selEnd.col : m_selStart.col) : m_cols;
                    if (col >= std::min(c1, c2) && col <= std::max(c1, c2)) {
                        isSelected = true;
                    }
                }
            }

            // Colours, with reverse video applied before anything is drawn.
            //
            // Only `bold` was ever read off the cell. libvterm hands over
            // reverse, underline, italic and strike as well, and all four were
            // dropped on the floor — so a man page's highlighted heading, the
            // status line of `less`, vim's visual selection and htop's column
            // header all came out as ordinary text. Reverse is the one that
            // matters: it is how a terminal program says "this part", and
            // without it there was no difference between selected and not.
            QColor fg = toQColor(cell.fg, m_foreground);
            QColor bg = VTERM_COLOR_IS_DEFAULT_BG(&cell.bg) ? m_background
                                                            : toQColor(cell.bg, m_background);
            if (cell.attrs.reverse)
                std::swap(fg, bg);

            // Cell background
            if (isSelected) {
                painter->fillRect(cellRect, QColor(137, 180, 250, 80));
            } else if (bg != m_background) {
                painter->fillRect(cellRect, bg);
            }

            // Cell character
            if (cell.chars[0] != 0 && cell.chars[0] != ' ') {
                QString text;
                for (int i = 0; i < VTERM_MAX_CHARS_PER_CELL && cell.chars[i]; ++i) {
                    char32_t cp = static_cast<char32_t>(cell.chars[i]);
                    text += QString::fromUcs4(&cp, 1);
                }

                const bool styled = cell.attrs.bold || cell.attrs.underline
                                 || cell.attrs.italic || cell.attrs.strike;
                if (styled) {
                    QFont f = m_font;
                    if (cell.attrs.bold)      f.setBold(true);
                    if (cell.attrs.italic)    f.setItalic(true);
                    // libvterm reports the underline *style* — single, double,
                    // curly — as a small integer, not a flag. Anything non-zero
                    // is a line under the cell; Qt draws one kind, so that is
                    // what all of them get.
                    if (cell.attrs.underline) f.setUnderline(true);
                    if (cell.attrs.strike)    f.setStrikeOut(true);
                    painter->setFont(f);
                }

                painter->setPen(fg);
                painter->drawText(QPointF(x, y + m_fontAscent), text);

                if (styled)
                    painter->setFont(m_font);
            }

            col += widthInCells;
        }
    }

    // Cursor
    if (m_cursorVisible && m_cursorPos.row < m_rows && m_cursorPos.col < m_cols) {
        qreal cx = m_cursorPos.col * m_cellWidth;
        qreal cy = m_cursorPos.row * m_cellHeight;
        QRectF cursorRect(cx, cy, m_cellWidth, m_cellHeight);

        painter->fillRect(cursorRect, QColor(205, 214, 244, 210));

        // Invert character inside cursor
        VTermScreenCell cell;
        vterm_screen_get_cell(m_vts, m_cursorPos, &cell);
        if (cell.chars[0] != 0 && cell.chars[0] != ' ') {
            QString text;
            for (int i = 0; i < VTERM_MAX_CHARS_PER_CELL && cell.chars[i]; ++i) {
                char32_t cp = static_cast<char32_t>(cell.chars[i]);
                text += QString::fromUcs4(&cp, 1);
            }
            painter->setPen(m_background);
            painter->drawText(QPointF(cx, cy + m_fontAscent), text);
        }
    }
}

void TerminalItem::keyPressEvent(QKeyEvent *event) {
    if (m_masterFd < 0) return;

    if (m_viewOffset > 0) {
        m_viewOffset = 0;
        update();
    }

    // Shortcuts: Copy & Paste
    if ((event->modifiers() & Qt::ControlModifier) && (event->modifiers() & Qt::ShiftModifier)) {
        if (event->key() == Qt::Key_C) {
            copySelection();
            return;
        } else if (event->key() == Qt::Key_V) {
            pasteClipboard();
            return;
        }
    }

    // Shortcuts: Zoom
    if (event->modifiers() & Qt::ControlModifier) {
        if (event->key() == Qt::Key_Plus || event->key() == Qt::Key_Equal) {
            zoomIn();
            return;
        } else if (event->key() == Qt::Key_Minus) {
            zoomOut();
            return;
        } else if (event->key() == Qt::Key_0) {
            resetZoom();
            return;
        }
    }

    // Special Keys
    const char *seq = nullptr;
    switch (event->key()) {
        case Qt::Key_Return:
        case Qt::Key_Enter:
            seq = "\r"; break;
        case Qt::Key_Backspace:
            seq = "\x7f"; break;
        case Qt::Key_Tab:
            seq = "\t"; break;
        case Qt::Key_Escape:
            seq = "\x1b"; break;
        case Qt::Key_Up:
            seq = "\x1b[A"; break;
        case Qt::Key_Down:
            seq = "\x1b[B"; break;
        case Qt::Key_Right:
            seq = "\x1b[C"; break;
        case Qt::Key_Left:
            seq = "\x1b[D"; break;
        case Qt::Key_Home:
            seq = "\x1b[H"; break;
        case Qt::Key_End:
            seq = "\x1b[F"; break;
        case Qt::Key_Insert:
            seq = "\x1b[2~"; break;
        case Qt::Key_Delete:
            seq = "\x1b[3~"; break;
        case Qt::Key_PageUp:
            seq = "\x1b[5~"; break;
        case Qt::Key_PageDown:
            seq = "\x1b[6~"; break;
        case Qt::Key_F1: seq = "\x1bOP"; break;
        case Qt::Key_F2: seq = "\x1bOQ"; break;
        case Qt::Key_F3: seq = "\x1bOR"; break;
        case Qt::Key_F4: seq = "\x1bOS"; break;
        case Qt::Key_F5: seq = "\x1b[15~"; break;
        case Qt::Key_F6: seq = "\x1b[17~"; break;
        case Qt::Key_F7: seq = "\x1b[18~"; break;
        case Qt::Key_F8: seq = "\x1b[19~"; break;
        case Qt::Key_F9: seq = "\x1b[20~"; break;
        case Qt::Key_F10: seq = "\x1b[21~"; break;
        case Qt::Key_F11: seq = "\x1b[23~"; break;
        case Qt::Key_F12: seq = "\x1b[24~"; break;
        default:
            break;
    }

    if (seq) {
        write(m_masterFd, seq, strlen(seq));
        return;
    }

    // Ctrl + Key
    if (event->modifiers() & Qt::ControlModifier) {
        int k = event->key();
        if (k >= Qt::Key_A && k <= Qt::Key_Z) {
            char ctrlByte = (char)(k - Qt::Key_A + 1);
            write(m_masterFd, &ctrlByte, 1);
            return;
        }
    }

    // Text Input
    QByteArray utf8 = event->text().toUtf8();
    if (!utf8.isEmpty()) {
        write(m_masterFd, utf8.constData(), utf8.size());
    }
}

void TerminalItem::mousePressEvent(QMouseEvent *event) {
    forceActiveFocus();
    if (event->button() == Qt::LeftButton) {
        int col = (int)(event->pos().x() / m_cellWidth);
        int row = (int)(event->pos().y() / m_cellHeight);

        qint64 now = QDateTime::currentMSecsSinceEpoch();
        bool samePos = (row == m_lastClickPos.row && col == m_lastClickPos.col);
        if (samePos && (now - m_lastClickMs) <= QGuiApplication::styleHints()->mouseDoubleClickInterval()) {
            m_clickCount = (m_clickCount % 3) + 1;
        } else {
            m_clickCount = 1;
        }
        m_lastClickMs = now;
        m_lastClickPos = { row, col };

        if (m_clickCount == 2) {
            selectWordAt({ row, col });
            m_selecting = false;
            return;
        }
        if (m_clickCount == 3) {
            selectLineAt(row);
            m_selecting = false;
            return;
        }

        m_selStart = { row, col };
        m_selEnd = m_selStart;
        m_selecting = true;
        m_hasSelection = false;
        update();
    }
}

void TerminalItem::selectWordAt(VTermPos pos) {
    if (!m_vts || pos.row < 0 || pos.row >= m_rows) return;

    auto isWordChar = [this](int row, int col) {
        VTermScreenCell cell;
        vterm_screen_get_cell(m_vts, { row, col }, &cell);
        if (!cell.chars[0]) return false;
        char32_t cp = static_cast<char32_t>(cell.chars[0]);
        return cp != ' ' && cp != '\t';
    };

    if (!isWordChar(pos.row, pos.col)) return;

    int left = pos.col;
    while (left > 0 && isWordChar(pos.row, left - 1)) left--;
    int right = pos.col;
    while (right < m_cols - 1 && isWordChar(pos.row, right + 1)) right++;

    m_selStart = { pos.row, left };
    m_selEnd = { pos.row, right };
    m_hasSelection = true;
    update();
}

void TerminalItem::selectLineAt(int row) {
    if (row < 0 || row >= m_rows) return;
    m_selStart = { row, 0 };
    m_selEnd = { row, m_cols - 1 };
    m_hasSelection = true;
    update();
}

void TerminalItem::mouseMoveEvent(QMouseEvent *event) {
    if (m_selecting) {
        int col = std::max(0, std::min(m_cols - 1, (int)(event->pos().x() / m_cellWidth)));
        int row = std::max(0, std::min(m_rows - 1, (int)(event->pos().y() / m_cellHeight)));
        m_selEnd = { row, col };
        m_hasSelection = (m_selStart.row != m_selEnd.row || m_selStart.col != m_selEnd.col);
        update();
    }
}

void TerminalItem::mouseReleaseEvent(QMouseEvent *event) {
    if (event->button() == Qt::LeftButton && m_selecting) {
        m_selecting = false;
    }
}

void TerminalItem::wheelEvent(QWheelEvent *event) {
    if (m_masterFd < 0 || m_scrollback.empty()) return;
    int delta = event->angleDelta().y();
    if (delta > 0) {
        m_viewOffset = std::min(static_cast<int>(m_scrollback.size()), m_viewOffset + 3);
    } else if (delta < 0) {
        m_viewOffset = std::max(0, m_viewOffset - 3);
    }
    update();
    event->accept();
}

void TerminalItem::copySelection() {
    if (!m_hasSelection || !m_vts) return;

    QString text;
    int r1 = std::min(m_selStart.row, m_selEnd.row);
    int r2 = std::max(m_selStart.row, m_selEnd.row);

    for (int r = r1; r <= r2; ++r) {
        int c1 = (r == r1) ? ((m_selStart.row <= m_selEnd.row) ? m_selStart.col : m_selEnd.col) : 0;
        int c2 = (r == r2) ? ((m_selStart.row <= m_selEnd.row) ? m_selEnd.col : m_selStart.col) : m_cols - 1;

        QString line;
        for (int c = c1; c <= c2 && c < m_cols; ++c) {
            VTermScreenCell cell;
            vterm_screen_get_cell(m_vts, { r, c }, &cell);
            if (cell.chars[0]) {
                for (int i = 0; i < VTERM_MAX_CHARS_PER_CELL && cell.chars[i]; ++i) {
                    char32_t cp = static_cast<char32_t>(cell.chars[i]);
                    line += QString::fromUcs4(&cp, 1);
                }
            } else {
                line += ' ';
            }
        }
        text += line.trimmed() + (r < r2 ? "\n" : "");
    }

    if (!text.isEmpty()) {
        QGuiApplication::clipboard()->setText(text);
    }
}

void TerminalItem::pasteClipboard() {
    if (m_masterFd < 0) return;
    QString text = QGuiApplication::clipboard()->text();
    if (!text.isEmpty()) {
        QByteArray data = text.toUtf8();
        write(m_masterFd, data.constData(), data.size());
    }
}

void TerminalItem::zoomIn() {
    setFontSize(m_fontSize + 1);
}

void TerminalItem::zoomOut() {
    setFontSize(m_fontSize - 1);
}

void TerminalItem::resetZoom() {
    setFontSize(11);
}

void TerminalItem::clear() {
    if (m_masterFd >= 0) {
        write(m_masterFd, "clear\n", 6);
    }
}

void TerminalItem::sendText(const QString &text) {
    if (m_masterFd >= 0) {
        QByteArray data = text.toUtf8();
        write(m_masterFd, data.constData(), data.size());
    }
}

// ── libvterm callbacks ───────────────────────────────────────────────────────
int TerminalItem::cbDamage(VTermRect rect, void *user) {
    Q_UNUSED(rect);
    auto *term = static_cast<TerminalItem*>(user);
    term->update();
    return 1;
}

int TerminalItem::cbMoverect(VTermRect dest, VTermRect src, void *user) {
    Q_UNUSED(dest);
    Q_UNUSED(src);
    auto *term = static_cast<TerminalItem*>(user);
    term->update();
    return 1;
}

int TerminalItem::cbMovecursor(VTermPos pos, VTermPos oldpos, int visible, void *user) {
    Q_UNUSED(oldpos);
    auto *term = static_cast<TerminalItem*>(user);
    term->m_cursorPos = pos;
    term->m_cursorVisible = (visible != 0);
    term->update();
    return 1;
}

int TerminalItem::cbSettermprop(VTermProp prop, VTermValue *val, void *user) {
    auto *term = static_cast<TerminalItem*>(user);
    if (prop == VTERM_PROP_TITLE) {
        term->m_title = QString::fromUtf8(val->string.str, val->string.len);
        emit term->titleChanged();
    }
    return 1;
}

int TerminalItem::cbBell(void *user) {
    Q_UNUSED(user);
    return 1;
}

int TerminalItem::cbResize(int rows, int cols, void *user) {
    Q_UNUSED(rows);
    Q_UNUSED(cols);
    auto *term = static_cast<TerminalItem*>(user);
    term->update();
    return 1;
}

int TerminalItem::cbSbPushline(int cols, const VTermScreenCell *cells, void *user) {
    auto *term = static_cast<TerminalItem *>(user);
    if (!term || !cells || cols <= 0) return 0;
    term->m_scrollback.emplace_back(cells, cells + cols);
    while (term->m_scrollback.size() > 2000) term->m_scrollback.pop_front();
    return 1;
}

int TerminalItem::cbSbPopline(int cols, VTermScreenCell *cells, void *user) {
    auto *term = static_cast<TerminalItem *>(user);
    if (!term || !cells || cols <= 0 || term->m_scrollback.empty()) return 0;
    auto line = std::move(term->m_scrollback.back());
    term->m_scrollback.pop_back();
    const int count = std::min(cols, static_cast<int>(line.size()));
    std::copy_n(line.begin(), count, cells);
    return 1;
}

void TerminalItem::cbOutput(const char *s, size_t len, void *user) {
    auto *term = static_cast<TerminalItem*>(user);
    if (term && term->m_masterFd >= 0 && s && len > 0) {
        write(term->m_masterFd, s, len);
    }
}

} // namespace b1air
