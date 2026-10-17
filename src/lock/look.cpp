#include "look.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>

namespace look {

namespace {

// The desktop's: Design.qml's sans for words, its Nerd Font for icons.
constexpr const char* kFont = "Inter";
constexpr const char* kIconFont = "b1air Symbols";

struct Ink {
    double r, g, b, a;
};
Ink white(double a) { return {1, 1, 1, a}; }
Ink tint(const Colour& c, double a) { return {c.r, c.g, c.b, a}; }
void use(cairo_t* cr, const Ink& i) { cairo_set_source_rgba(cr, i.r, i.g, i.b, i.a); }

void rounded(cairo_t* cr, double x, double y, double w, double h, double r) {
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
    cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
}

// The path drawn as glass: a fill, white unless tinted, and its rim.
void glass(cairo_t* cr, double u, double fill, double rim, const Colour* c = nullptr) {
    use(cr, c ? tint(*c, fill) : white(fill));
    cairo_fill_preserve(cr);
    use(cr, c ? tint(*c, rim) : white(rim));
    cairo_set_line_width(cr, 1 * u);
    cairo_stroke(cr);
}

void font(cairo_t* cr, double size, bool bold, bool icon = false) {
    cairo_select_font_face(cr, icon ? kIconFont : kFont, CAIRO_FONT_SLANT_NORMAL,
                           bold ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, size);
}

double text_width(cairo_t* cr, const std::string& text) {
    cairo_text_extents_t e;
    cairo_text_extents(cr, text.c_str(), &e);
    return e.x_advance;
}

// Words straight on the picture: a shadow a hair below keeps white legible
// on a light wallpaper.
void show(cairo_t* cr, const std::string& text, double x, double y, double u, const Ink& ink) {
    cairo_set_source_rgba(cr, 0, 0, 0, 0.28 * ink.a);
    cairo_move_to(cr, x, y + 1.5 * u);
    cairo_show_text(cr, text.c_str());
    use(cr, ink);
    cairo_move_to(cr, x, y);
    cairo_show_text(cr, text.c_str());
    cairo_new_path(cr);   // or the next arc is joined to where the text ended
}

// Text centred on cx, its baseline at y.
void centred(cairo_t* cr, const std::string& text, double cx, double y, double size, bool bold, double u,
             const Ink& ink) {
    font(cr, size, bold);
    cairo_text_extents_t e;
    cairo_text_extents(cr, text.c_str(), &e);
    show(cr, text, cx - e.width / 2 - e.x_bearing, y, u, ink);
}

// An icon then words, centred on cx.
void centred_line(cairo_t* cr, const std::string& icon, const Ink& icon_ink, const std::string& text,
                  const Ink& text_ink, double cx, double y, double size, double u) {
    font(cr, size, false, true);
    const double iw = text_width(cr, icon), gap = size * 0.5;
    font(cr, size, false);
    const double x = cx - (iw + gap + text_width(cr, text)) / 2;
    font(cr, size, false, true);
    show(cr, icon, x, y, u, icon_ink);
    font(cr, size, false);
    show(cr, text, x + iw + gap, y, u, text_ink);
}

// Text centred in a box, both ways, in the current colour.
void boxed(cairo_t* cr, const std::string& text, const Rect& r) {
    cairo_font_extents_t fe;
    cairo_font_extents(cr, &fe);
    cairo_move_to(cr, r.x + (r.w - text_width(cr, text)) / 2, r.y + (r.h + fe.ascent - fe.descent) / 2);
    cairo_show_text(cr, text.c_str());
    cairo_new_path(cr);
}

// A glass pill of an icon and a word.
double pill_width(cairo_t* cr, double u, const std::string& icon, const std::string& text) {
    font(cr, 16 * u, false, true);
    const double iw = icon.empty() ? 0 : text_width(cr, icon);
    font(cr, 14 * u, false);
    const double tw = text.empty() ? 0 : text_width(cr, text);
    return 28 * u + iw + (icon.empty() || text.empty() ? 0 : 7 * u) + tw;
}

Rect pill(cairo_t* cr, double x, double y, double h, double u, const std::string& icon, const std::string& text,
          const Ink& icon_ink, double fill) {
    const Rect r{x, y, pill_width(cr, u, icon, text), h};
    cairo_new_path(cr);
    rounded(cr, r.x, r.y, r.w, r.h, h / 2);
    glass(cr, u, fill, 0.28);
    font(cr, 16 * u, false, true);
    cairo_font_extents_t fe;
    cairo_font_extents(cr, &fe);
    const double iw = icon.empty() ? 0 : text_width(cr, icon);
    use(cr, icon_ink);
    cairo_move_to(cr, x + 14 * u, y + (h + fe.ascent - fe.descent) / 2);
    cairo_show_text(cr, icon.c_str());
    font(cr, 14 * u, false);
    cairo_font_extents(cr, &fe);
    use(cr, white(0.95));
    cairo_move_to(cr, x + 14 * u + iw + (icon.empty() ? 0 : 7 * u), y + (h + fe.ascent - fe.descent) / 2);
    cairo_show_text(cr, text.c_str());
    cairo_new_path(cr);
    return r;
}

// A shade from `from` (alpha a0) to `to` (alpha a1), down the screen.
void shade(cairo_t* cr, double from, double a0, double to, double a1) {
    cairo_pattern_t* p = cairo_pattern_create_linear(0, from, 0, to);
    cairo_pattern_add_color_stop_rgba(p, 0, 0, 0, 0, a0);
    cairo_pattern_add_color_stop_rgba(p, 1, 0, 0, 0, a1);
    cairo_set_source(cr, p);
    cairo_paint(cr);
    cairo_pattern_destroy(p);
}

}  // namespace

void paint(cairo_t* cr, const View& v, Hits& hits) {
    const double W = v.width, H = v.height;
    const Palette& p = v.pal;
    const auto over = [&](const Rect& r) { return v.pointer && r.contains(v.px, v.py); };

    // The picture, blurred, under a light veil — a little deeper at the top,
    // behind the clock, and at the foot, behind the password.
    use(cr, tint(p.ground, 1));
    cairo_paint(cr);
    if (v.wallpaper) {
        cairo_save(cr);
        cairo_scale(cr, W / cairo_image_surface_get_width(v.wallpaper), H / cairo_image_surface_get_height(v.wallpaper));
        cairo_set_source_surface(cr, v.wallpaper, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
        cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_PAD);
        cairo_paint(cr);
        cairo_restore(cr);
    }
    cairo_set_source_rgba(cr, 0, 0, 0, 0.16);
    cairo_paint(cr);
    shade(cr, 0, 0.26, H * 0.45, 0);
    shade(cr, H * 0.55, 0, H, 0.22);

    const double u = std::min(W, H) / 1080.0;   // one unit at 1080p
    const double cx = W / 2, cy = H / 2;

    // The time and, under it, the date.
    centred(cr, v.clock, cx, 206 * u, 128 * u, true, u, white(0.98));
    centred(cr, v.date, cx, 250 * u, 22 * u, false, u, white(0.9));

    // The account: the picture in a fine white ring, or the initial on glass.
    const double ar = 42 * u, ay = cy + 96 * u;
    {
        cairo_pattern_t* halo = cairo_pattern_create_radial(cx, ay + 2 * u, ar, cx, ay + 2 * u, ar + 14 * u);
        cairo_pattern_add_color_stop_rgba(halo, 0, 0, 0, 0, 0.22);
        cairo_pattern_add_color_stop_rgba(halo, 1, 0, 0, 0, 0);
        cairo_set_source(cr, halo);
        cairo_arc(cr, cx, ay + 2 * u, ar + 14 * u, 0, 2 * M_PI);
        cairo_fill(cr);
        cairo_pattern_destroy(halo);
    }
    cairo_arc(cr, cx, ay, ar + 2 * u, 0, 2 * M_PI);
    use(cr, white(0.6));
    cairo_fill(cr);
    cairo_save(cr);
    cairo_arc(cr, cx, ay, ar, 0, 2 * M_PI);
    cairo_clip(cr);
    if (v.avatar) {
        const double side = cairo_image_surface_get_width(v.avatar);
        cairo_translate(cr, cx - ar, ay - ar);
        cairo_scale(cr, 2 * ar / side, 2 * ar / side);
        cairo_set_source_surface(cr, v.avatar, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
        cairo_paint(cr);
    } else {
        use(cr, tint(p.ground, 0.55));
        cairo_paint(cr);
        use(cr, white(0.16));
        cairo_paint(cr);
        std::string initial;
        if (!v.name.empty()) {   // the first code point, upper-cased if ASCII
            size_t n = 1;
            while (n < v.name.size() && (static_cast<unsigned char>(v.name[n]) & 0xC0) == 0x80) ++n;
            initial = v.name.substr(0, n);
            if (n == 1) initial[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(initial[0])));
        }
        font(cr, 36 * u, true);
        use(cr, white(0.95));
        boxed(cr, initial, {cx - ar, ay - ar, 2 * ar, 2 * ar});
    }
    cairo_restore(cr);
    centred(cr, v.name, cx, ay + ar + 34 * u, 20 * u, true, u, white(0.98));

    // The field, a glass pill: the placeholder, then a dot a character; the
    // eye at its left end once something is typed, the layout at its right.
    const double fw = 300 * u, fh = 44 * u, fx = cx - fw / 2, fy = ay + ar + 52 * u;
    const bool denied = v.status == Status::Denied || v.status == Status::Unavailable;
    cairo_new_path(cr);
    rounded(cr, fx, fy, fw, fh, fh / 2);
    if (denied) glass(cr, u, 0.30, 0.85, &p.error);
    else if (v.status == Status::Checking) glass(cr, u, 0.16, 0.7);
    else if (v.password.empty()) glass(cr, u, 0.16, 0.28);
    else glass(cr, u, 0.20, 0.42);

    double layout_w = 0;
    if (!v.layout.empty()) {
        const Rect lr{fx + fw - 50 * u, fy + 9 * u, 40 * u, fh - 18 * u};
        rounded(cr, lr.x, lr.y, lr.w, lr.h, lr.h / 2);
        use(cr, white(0.16));
        cairo_fill(cr);
        font(cr, 12 * u, true);
        use(cr, white(0.9));
        boxed(cr, v.layout, lr);
        layout_w = 46 * u;
    }

    // A click on the eye shows the password as text, another hides it: a
    // typo is seen, not found by being refused.
    double eye_w = 0;
    hits.eye = {};
    if (!v.password.empty()) {
        hits.eye = {fx + 6 * u, fy + 6 * u, fh - 12 * u, fh - 12 * u};
        eye_w = fh - 6 * u;
        if (over(hits.eye)) {
            cairo_arc(cr, hits.eye.x + hits.eye.w / 2, hits.eye.y + hits.eye.h / 2, hits.eye.w / 2, 0, 2 * M_PI);
            use(cr, white(0.16));
            cairo_fill(cr);
        }
        font(cr, 18 * u, false, true);
        use(cr, white(v.reveal ? 0.95 : 0.7));
        boxed(cr, v.reveal ? "\U000F0209" : "\U000F0208", hits.eye);   // eye-off / eye
    }

    const double inner_l = fx + 20 * u + eye_w, inner_r = fx + fw - 20 * u - layout_w;
    if (v.password.empty()) {
        font(cr, 15 * u, false);
        use(cr, white(0.62));
        boxed(cr, v.placeholder, {fx, fy, fw, fh});
    } else if (v.reveal) {
        // As text, its end in view when it is wider than the field.
        cairo_save(cr);
        cairo_rectangle(cr, inner_l, fy, inner_r - inner_l, fh);
        cairo_clip(cr);
        font(cr, 16 * u, false);
        cairo_font_extents_t fe;
        cairo_font_extents(cr, &fe);
        const double tw = text_width(cr, v.password);
        const double tx = tw <= inner_r - inner_l ? (inner_l + inner_r - tw) / 2 : inner_r - tw;
        use(cr, white(0.95));
        cairo_move_to(cr, tx, fy + (fh + fe.ascent - fe.descent) / 2);
        cairo_show_text(cr, v.password.c_str());
        cairo_new_path(cr);
        cairo_restore(cr);
    } else {
        // Counted as UTF-8 code points, as many as fit.
        size_t chars = 0;
        for (unsigned char c : v.password)
            if ((c & 0xC0) != 0x80) ++chars;
        const double gap = 14 * u, r = 4 * u;
        const size_t fit = static_cast<size_t>(std::max(1.0, (inner_r - inner_l) / gap));
        const size_t shown = std::min(chars, fit);
        double x = (inner_l + inner_r) / 2 - (static_cast<double>(shown) - 1) * gap / 2;
        use(cr, white(0.95));
        for (size_t i = 0; i < shown; ++i, x += gap) {
            cairo_arc(cr, x, fy + fh / 2, r, 0, 2 * M_PI);
            cairo_fill(cr);
        }
    }

    // Under it: what is happening, Caps Lock, the reader.
    double below = fy + fh + 30 * u;
    if (!v.message.empty()) {
        centred(cr, v.message, cx, below, 15 * u, false, u, white(0.92));
        below += 26 * u;
    }
    if (!v.caps.empty()) {
        centred_line(cr, "󰪛", tint(p.warn, 0.95), v.caps, white(0.85), cx, below, 14 * u, u);
        below += 24 * u;
    }
    if (!v.finger.empty())
        centred_line(cr, "󰈷", v.finger_miss ? tint(p.error, 0.95) : white(0.85), v.finger, white(0.85), cx, below,
                     14 * u, u);

    // The corners: weather at the top left, the battery at the top right.
    const double ph = 34 * u, m = 24 * u;
    if (!v.weather_temp.empty()) pill(cr, m, m, ph, u, v.weather_icon, v.weather_temp, white(0.95), 0.16);
    if (!v.battery.empty()) {
        const double bw = pill_width(cr, u, v.battery_icon, v.battery);
        pill(cr, W - m - bw, m, ph, u, v.battery_icon, v.battery, v.battery_low ? tint(p.error, 1) : white(0.95), 0.16);
    }

    // The power menu, bottom right: a glass button, and when it is open, the
    // three things it does to its left.
    const double bs = 44 * u;
    hits.power = {W - m - bs, H - m - bs, bs, bs};
    cairo_new_path(cr);
    cairo_arc(cr, hits.power.x + bs / 2, hits.power.y + bs / 2, bs / 2, 0, 2 * M_PI);
    glass(cr, u, v.menu_open || over(hits.power) ? 0.30 : 0.16, 0.28);
    font(cr, 20 * u, false, true);
    use(cr, white(0.95));
    boxed(cr, "󰐥", hits.power);
    for (auto& it : hits.items) it = {};
    if (v.menu_open) {
        const char* icons[3] = {"󰜉", "󰒲", "󰐥"};
        const Ink inks[3] = {white(0.95), white(0.95), tint(p.error, 1)};
        double right = hits.power.x - 10 * u;
        for (int i = 2; i >= 0; --i) {
            const double w = pill_width(cr, u, icons[i], v.items[i]);
            const Rect r{right - w, hits.power.y + 4 * u, w, bs - 8 * u};
            hits.items[i] = pill(cr, r.x, r.y, r.h, u, icons[i], v.items[i], inks[i], over(r) ? 0.30 : 0.16);
            right -= w + 8 * u;
        }
    }
}

}  // namespace look
