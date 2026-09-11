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
#include <algorithm>
#include <cstring>
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

    // The platform's own rate, so it matches every other text field.
    const int flash = QGuiApplication::styleHints()->cursorFlashTime();
    m_blinkTimer.setInterval(flash > 0 ? flash / 2 : 530);
    connect(&m_blinkTimer, &QTimer::timeout, this, &TerminalItem::onBlink);
}

void TerminalItem::onBlink() {
    m_blinkOn = !m_blinkOn;
    update();
}

// Solid again at once after typing or output, and blinking only while the
// terminal has focus — a blinking cursor in a window you are not typing into
// is just motion in the corner of your eye.
void TerminalItem::restartBlink() {
    m_blinkOn = true;
    if (m_cursorBlinks && hasActiveFocus())
        m_blinkTimer.start();
    else
        m_blinkTimer.stop();
    update();
}

void TerminalItem::focusInEvent(QFocusEvent *event) {
    QQuickPaintedItem::focusInEvent(event);
    restartBlink();
}

void TerminalItem::focusOutEvent(QFocusEvent *event) {
    QQuickPaintedItem::focusOutEvent(event);
    restartBlink();
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
    // The reset reports a blinking block through settermprop; the default
    // here is the bar. A program that wants a block still gets one by asking.
    m_cursorShape = VTERM_PROP_CURSORSHAPE_BAR_LEFT;
    m_cursorBlinks = true;
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
            // The child has gone. This used to emit and leave the notifier
            // armed on a pty whose reads now fail at once, so it fired again
            // on every turn of the event loop — processFinished arrived over
            // and over, and TermWindow closed a tab for each one: typing
            // `exit` in one tab could take its neighbours with it, and the
            // emits could land on an item QML was already destroying.
            childExited();
            return;
        }
    }

    vterm_screen_flush_damage(m_vts);
    restartBlink();
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
                    // A line is as wide as the window was when it scrolled
                    // off. Widen the window since and this read past the end
                    // of it.
                    const auto &line = m_scrollback[static_cast<size_t>(sourceRow)];
                    if (col < static_cast<int>(line.size())) {
                        cell = line[static_cast<size_t>(col)];
                    } else {
                        std::memset(&cell, 0, sizeof(cell));
                        cell.width = 1;
                    }
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

    // Cursor. Not while scrolled back: it belongs to the live screen, and was
    // drawn at the same cell over whatever history was on show.
    const bool focused = hasActiveFocus();
    if (m_cursorVisible && m_viewOffset == 0 && !m_finished
            && m_cursorPos.row < m_rows && m_cursorPos.col < m_cols
            && (m_blinkOn || !focused)) {
        qreal cx = m_cursorPos.col * m_cellWidth;
        qreal cy = m_cursorPos.row * m_cellHeight;
        QRectF cursorRect(cx, cy, m_cellWidth, m_cellHeight);
        QColor cursorColor = m_foreground;

        if (!focused) {
            // An outline when the window is not focused, like every terminal.
            cursorColor.setAlpha(160);
            painter->setPen(QPen(cursorColor, 1));
            painter->setBrush(Qt::NoBrush);
            painter->drawRect(cursorRect.adjusted(0.5, 0.5, -0.5, -0.5));
            return;
        }
        if (m_cursorShape == VTERM_PROP_CURSORSHAPE_BAR_LEFT) {
            painter->fillRect(QRectF(cx, cy, std::max<qreal>(2.0, m_cellWidth / 6.0), m_cellHeight), cursorColor);
            return;
        }
        if (m_cursorShape == VTERM_PROP_CURSORSHAPE_UNDERLINE) {
            const qreal h = std::max<qreal>(2.0, m_cellHeight / 10.0);
            painter->fillRect(QRectF(cx, cy + m_cellHeight - h, m_cellWidth, h), cursorColor);
            return;
        }

        cursorColor.setAlpha(210);
        painter->fillRect(cursorRect, cursorColor);

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

void TerminalItem::childExited() {
    if (m_finished) return;
    m_finished = true;
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }
    if (m_masterFd >= 0) {
        close(m_masterFd);
        m_masterFd = -1;
    }
    int status = 0;
    if (m_childPid > 0 && waitpid(m_childPid, &status, WNOHANG) == m_childPid)
        m_childPid = -1;
    const int code = WIFEXITED(status) ? WEXITSTATUS(status) : 0;
    m_blinkTimer.stop();
    // Queued: whoever listens may delete this item, and must not do it
    // while onPtyRead is still on the stack.
    QMetaObject::invokeMethod(this, [this, code]() { emit processFinished(code); }, Qt::QueuedConnection);
}

void TerminalItem::keyPressEvent(QKeyEvent *event) {
    if (m_masterFd < 0) return;
    restartBlink();

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

    // Scrolling the terminal's own history from the keyboard, as every other
    // terminal does: Shift+PageUp/PageDown by a page, Shift+Home/End to the
    // ends. Not on the alternate screen, where these keys belong to the
    // program (less, an editor) and there is no history to show.
    if ((event->modifiers() & Qt::ShiftModifier) && !m_altScreen && !m_scrollback.empty()) {
        const int page = std::max(1, m_rows - 1);
        const int top = static_cast<int>(m_scrollback.size());
        int to = -1;
        if (event->key() == Qt::Key_PageUp)   to = std::min(top, m_viewOffset + page);
        if (event->key() == Qt::Key_PageDown) to = std::max(0, m_viewOffset - page);
        if (event->key() == Qt::Key_Home)     to = top;
        if (event->key() == Qt::Key_End)      to = 0;
        if (to >= 0) {
            m_viewOffset = to;
            update();
            return;
        }
    }

    // Everything else goes through libvterm's keyboard, which writes to the pty
    // through cbOutput.
    //
    // This was a hand-written table of escape sequences that ignored both the
    // modifiers and the modes the running program had switched on: Shift,
    // Ctrl and Alt with an arrow all sent the bare arrow, Shift+Tab sent Tab,
    // Alt+letter sent the letter without its ESC, and the arrows were always
    // the normal-mode ones even after vim or less asked for application mode.
    // libvterm encodes all of that from the state it is already tracking.
    VTermModifier mod = VTERM_MOD_NONE;
    if (event->modifiers() & Qt::ShiftModifier)   mod = static_cast<VTermModifier>(mod | VTERM_MOD_SHIFT);
    if (event->modifiers() & Qt::AltModifier)     mod = static_cast<VTermModifier>(mod | VTERM_MOD_ALT);
    if (event->modifiers() & Qt::ControlModifier) mod = static_cast<VTermModifier>(mod | VTERM_MOD_CTRL);
    const bool keypad = event->modifiers() & Qt::KeypadModifier;

    VTermKey key = VTERM_KEY_NONE;
    switch (event->key()) {
        case Qt::Key_Return:    key = VTERM_KEY_ENTER; break;
        case Qt::Key_Enter:     key = keypad ? VTERM_KEY_KP_ENTER : VTERM_KEY_ENTER; break;
        case Qt::Key_Backspace: key = VTERM_KEY_BACKSPACE; break;
        case Qt::Key_Tab:       key = VTERM_KEY_TAB; break;
        case Qt::Key_Backtab:   key = VTERM_KEY_TAB; mod = static_cast<VTermModifier>(mod | VTERM_MOD_SHIFT); break;
        case Qt::Key_Escape:    key = VTERM_KEY_ESCAPE; break;
        case Qt::Key_Up:        key = VTERM_KEY_UP; break;
        case Qt::Key_Down:      key = VTERM_KEY_DOWN; break;
        case Qt::Key_Left:      key = VTERM_KEY_LEFT; break;
        case Qt::Key_Right:     key = VTERM_KEY_RIGHT; break;
        case Qt::Key_Insert:    key = VTERM_KEY_INS; break;
        case Qt::Key_Delete:    key = VTERM_KEY_DEL; break;
        case Qt::Key_Home:      key = VTERM_KEY_HOME; break;
        case Qt::Key_End:       key = VTERM_KEY_END; break;
        case Qt::Key_PageUp:    key = VTERM_KEY_PAGEUP; break;
        case Qt::Key_PageDown:  key = VTERM_KEY_PAGEDOWN; break;
        default:
            if (event->key() >= Qt::Key_F1 && event->key() <= Qt::Key_F35)
                key = static_cast<VTermKey>(VTERM_KEY_FUNCTION(event->key() - Qt::Key_F1 + 1));
            break;
    }
    if (key != VTERM_KEY_NONE) {
        vterm_keyboard_key(m_vt, key, mod);
        return;
    }

    // Ctrl with a character: the key's own character, not event->text(),
    // which is already the control code (or nothing, for Ctrl+Space).
    if (mod & VTERM_MOD_CTRL) {
        const int k = event->key();
        uint32_t c = 0;
        if (k >= Qt::Key_A && k <= Qt::Key_Z) c = static_cast<uint32_t>('a' + (k - Qt::Key_A));
        else if (k == Qt::Key_Space) c = ' ';
        else if (k > 0x20 && k < 0x7f) c = static_cast<uint32_t>(k);
        if (c) {
            vterm_keyboard_unichar(m_vt, c, mod);
            return;
        }
    }

    // Text. Shift is already in the characters; Alt reaches libvterm, which
    // sends it as the ESC prefix.
    const QString text = event->text();
    if (text.isEmpty()) return;
    const VTermModifier textMod = static_cast<VTermModifier>(mod & VTERM_MOD_ALT);
    for (const uint cp : text.toUcs4()) {
        if (cp < 0x20 || cp == 0x7f) {
            const char byte = static_cast<char>(cp);
            write(m_masterFd, &byte, 1);
        } else {
            vterm_keyboard_unichar(m_vt, cp, textMod);
        }
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

// The wheel, three ways, the way other terminals do it:
//
//   - a program that turned mouse reporting on (htop, nvim, tmux) gets the
//     wheel as mouse buttons 4 and 5, at the cell under the pointer;
//   - a full-screen program without it (less, man) gets arrow keys, one per
//     line — the alternate screen has no scrollback to show;
//   - the shell's own screen scrolls through the history.
//
// This only did the third, and returned early whenever the history was
// empty, so the wheel did nothing at all in less, man, htop or an editor.
// It also moved three lines for every event however small: a touchpad sends
// a stream of tiny deltas, so the view lurched. Deltas are added up now, and
// a notch of a wheel (120) is three lines, as everywhere else.
void TerminalItem::wheelEvent(QWheelEvent *event) {
    event->accept();
    if (m_masterFd < 0 || !m_vt) return;

    int delta = event->angleDelta().y();
    if (delta == 0 && !event->pixelDelta().isNull())
        delta = event->pixelDelta().y() * 120 / std::max<int>(1, static_cast<int>(m_cellHeight * 3));
    m_wheelAccum += delta;
    const int lines = m_wheelAccum / 40;      // 120 per notch -> 3 lines
    if (lines == 0) return;
    m_wheelAccum -= lines * 40;

    if (m_mouseMode != VTERM_PROP_MOUSE_NONE) {
        const QPointF p = event->position();
        const int row = std::clamp(static_cast<int>(p.y() / m_cellHeight), 0, m_rows - 1);
        const int col = std::clamp(static_cast<int>(p.x() / m_cellWidth), 0, m_cols - 1);
        vterm_mouse_move(m_vt, row, col, VTERM_MOD_NONE);
        const int button = lines > 0 ? 4 : 5;
        for (int i = 0; i < std::abs(lines); ++i) {
            vterm_mouse_button(m_vt, button, true, VTERM_MOD_NONE);
            vterm_mouse_button(m_vt, button, false, VTERM_MOD_NONE);
        }
        return;
    }

    if (m_altScreen) {
        const VTermKey key = lines > 0 ? VTERM_KEY_UP : VTERM_KEY_DOWN;
        for (int i = 0; i < std::abs(lines); ++i)
            vterm_keyboard_key(m_vt, key, VTERM_MOD_NONE);
        return;
    }

    if (m_scrollback.empty()) return;
    m_viewOffset = std::clamp(m_viewOffset + lines, 0, static_cast<int>(m_scrollback.size()));
    update();
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
        // Bracketed, when the program asked for it (libvterm emits the markers
        // only then): a shell or an editor can tell a pasted block from typed
        // keys, and does not run each line as it arrives.
        vterm_keyboard_start_paste(m_vt);
        QByteArray data = text.toUtf8();
        write(m_masterFd, data.constData(), data.size());
        vterm_keyboard_end_paste(m_vt);
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
    } else if (prop == VTERM_PROP_CURSORVISIBLE) {
        term->m_cursorVisible = val->boolean;
        term->update();
    } else if (prop == VTERM_PROP_CURSORBLINK) {
        term->m_cursorBlinks = val->boolean;
        term->restartBlink();
    } else if (prop == VTERM_PROP_MOUSE) {
        term->m_mouseMode = val->number;
    } else if (prop == VTERM_PROP_ALTSCREEN) {
        term->m_altScreen = val->boolean;
        // Leaving history on show while a full-screen program draws over it
        // would show neither.
        term->m_viewOffset = 0;
        term->update();
    } else if (prop == VTERM_PROP_CURSORSHAPE) {
        term->m_cursorShape = val->number;
        term->update();
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
