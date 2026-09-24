#include "image.hpp"

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO_FILE_LOCKS
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#define STBI_NO_PIC
#define STBI_NO_PNM
#define STBI_NO_PSD
#include <stb/stb_image.h>

#ifdef B1AIR_HAVE_WEBP
#include <webp/decode.h>
#include <iterator>
#endif

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <vector>

namespace {

// For each output pixel along one axis, which source pixels make it and in
// what proportion. Shrinking averages every source pixel the output pixel
// covers (a box filter: a 6000-pixel photograph comes out smooth, not
// aliased); enlarging interpolates between the two nearest.
struct Taps {
    std::vector<int> first;
    std::vector<int> count;
    std::vector<int> offset;
    std::vector<float> weight;
    int lo = 0;   // the source range any tap touches
    int hi = 0;
};

Taps make_taps(int out, int src, double scale, double origin) {
    Taps t;
    t.first.resize(out);
    t.count.resize(out);
    t.offset.resize(out);
    t.lo = src;
    t.hi = 0;
    for (int i = 0; i < out; ++i) {
        t.offset[i] = static_cast<int>(t.weight.size());
        if (scale < 1.0) {
            const double a = origin + i / scale, b = origin + (i + 1) / scale;
            const int j0 = std::clamp(static_cast<int>(std::floor(a)), 0, src - 1);
            const int j1 = std::clamp(static_cast<int>(std::ceil(b)), j0 + 1, src);
            double sum = 0;
            for (int j = j0; j < j1; ++j) {
                const double w = std::max(0.0, std::min(b, j + 1.0) - std::max(a, double(j)));
                t.weight.push_back(static_cast<float>(w));
                sum += w;
            }
            for (int k = t.offset[i]; k < static_cast<int>(t.weight.size()); ++k)
                t.weight[k] = sum > 0 ? static_cast<float>(t.weight[k] / sum) : 1.0f / (j1 - j0);
            t.first[i] = j0;
            t.count[i] = j1 - j0;
        } else {
            const double c = origin + (i + 0.5) / scale - 0.5;
            int j0 = static_cast<int>(std::floor(c));
            float f = static_cast<float>(c - j0);
            if (j0 < 0) { j0 = 0; f = 0; }
            if (j0 >= src - 1) { j0 = src - 1; f = 0; }
            t.first[i] = j0;
            t.count[i] = f > 0 ? 2 : 1;
            t.weight.push_back(1.0f - f);
            if (f > 0) t.weight.push_back(f);
        }
        t.lo = std::min(t.lo, t.first[i]);
        t.hi = std::max(t.hi, t.first[i] + t.count[i]);
    }
    return t;
}

struct Pixels {
    int width = 0, height = 0, channels = 0;
    unsigned char* data = nullptr;
    void (*release)(void*) = nullptr;
    ~Pixels() { if (data && release) release(data); }
};

// The EXIF orientation of a JPEG (1–8; 1 when there is none): cameras save
// the sensor's rows as they were and record how to turn them, and stb_image
// does not read that. Only the first APP1 segment is looked at, as every
// reader does.
int exif_orientation(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    unsigned char head[2];
    if (!f.read(reinterpret_cast<char*>(head), 2) || head[0] != 0xFF || head[1] != 0xD8) return 1;
    for (;;) {
        unsigned char m[4];
        if (!f.read(reinterpret_cast<char*>(m), 4) || m[0] != 0xFF) return 1;
        const int marker = m[1];
        const size_t len = (size_t(m[2]) << 8) | m[3];
        if (len < 2 || marker == 0xDA || marker == 0xD9) return 1;   // image data: no EXIF before it
        if (marker != 0xE1) { f.seekg(static_cast<std::streamoff>(len - 2), std::ios::cur); continue; }

        std::vector<unsigned char> seg(len - 2);
        if (!f.read(reinterpret_cast<char*>(seg.data()), static_cast<std::streamsize>(seg.size()))) return 1;
        if (seg.size() < 14 || std::memcmp(seg.data(), "Exif\0\0", 6) != 0) return 1;
        const unsigned char* t = seg.data() + 6;
        const size_t n = seg.size() - 6;
        const bool le = t[0] == 'I' && t[1] == 'I';
        if (!le && !(t[0] == 'M' && t[1] == 'M')) return 1;
        const auto u16 = [&](size_t o) -> unsigned { return le ? t[o] | (t[o + 1] << 8) : (t[o] << 8) | t[o + 1]; };
        const auto u32 = [&](size_t o) -> size_t {
            return le ? size_t(t[o]) | (size_t(t[o + 1]) << 8) | (size_t(t[o + 2]) << 16) | (size_t(t[o + 3]) << 24)
                      : (size_t(t[o]) << 24) | (size_t(t[o + 1]) << 16) | (size_t(t[o + 2]) << 8) | size_t(t[o + 3]);
        };
        if (u16(2) != 42) return 1;
        const size_t ifd = u32(4);
        if (ifd + 2 > n) return 1;
        const unsigned entries = u16(ifd);
        for (unsigned i = 0; i < entries; ++i) {
            const size_t e = ifd + 2 + size_t(i) * 12;
            if (e + 12 > n) return 1;
            if (u16(e) == 0x0112) {
                const unsigned v = u16(e + 8);
                return v >= 1 && v <= 8 ? static_cast<int>(v) : 1;
            }
        }
        return 1;
    }
}

bool load(const std::string& path, Pixels& px) {
#ifdef B1AIR_HAVE_WEBP
    {
        std::ifstream f(path, std::ios::binary);
        char magic[12] = {};
        if (f.read(magic, sizeof magic) && std::equal(magic, magic + 4, "RIFF")
                && std::equal(magic + 8, magic + 12, "WEBP")) {
            f.seekg(0);
            const std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(f)), {});
            int w = 0, h = 0;
            uint8_t* rgba = WebPDecodeRGBA(bytes.data(), bytes.size(), &w, &h);
            if (!rgba) return false;
            px = {};
            px.width = w; px.height = h; px.channels = 4;
            px.data = rgba;
            px.release = [](void* p) { WebPFree(p); };
            return true;
        }
    }
#endif
    int w = 0, h = 0, comp = 0;
    if (!stbi_info(path.c_str(), &w, &h, &comp)) return false;
    // Three channels when there is no alpha to keep: a quarter less to hold.
    const int want = (comp == 2 || comp == 4) ? 4 : 3;
    px.data = stbi_load(path.c_str(), &px.width, &px.height, &px.channels, want);
    px.channels = want;
    px.release = [](void* p) { stbi_image_free(p); };
    return px.data != nullptr;
}

} // namespace

bool decode_cover(const std::string& path, int width, int height, uint32_t ground,
                  uint32_t* dst, int stride) {
    if (width <= 0 || height <= 0) return false;
    Pixels px;
    if (!load(path, px) || px.width <= 0 || px.height <= 0) return false;

    // The picture as it is meant to be seen: pixel (u, v) of it is raw pixel
    // origin + u·du + v·dv. Turning it this way costs nothing — no second
    // full-size copy — the resampler below just walks the raw pixels in
    // the turned order.
    const long W = px.width, H = px.height;
    long origin = 0, du = 1, dv = W;
    int iw = px.width, ih = px.height;
    switch (exif_orientation(path)) {
    case 2: origin = W - 1;               du = -1; dv = W;  break;   // mirrored
    case 3: origin = (H - 1) * W + W - 1; du = -1; dv = -W; break;   // upside down
    case 4: origin = (H - 1) * W;         du = 1;  dv = -W; break;   // mirrored, upside down
    case 5: origin = 0;                   du = W;  dv = 1;  break;   // transposed
    case 6: origin = (H - 1) * W;         du = -W; dv = 1;  break;   // turned a quarter right
    case 7: origin = (H - 1) * W + W - 1; du = -W; dv = -1; break;   // transverse
    case 8: origin = W - 1;               du = W;  dv = -1; break;   // turned a quarter left
    default: break;
    }
    if (std::abs(du) != 1) std::swap(iw, ih);

    const double scale = std::max(double(width) / iw, double(height) / ih);
    const Taps cols = make_taps(width, iw, scale, (iw - width / scale) / 2.0);
    const Taps rows = make_taps(height, ih, scale, (ih - height / scale) / 2.0);

    const int C = px.channels;
    const int span = cols.hi - cols.lo;
    std::vector<float> line(static_cast<size_t>(span) * C);
    const float gr = (ground >> 16) & 0xff, gg = (ground >> 8) & 0xff, gb = ground & 0xff;

    for (int y = 0; y < height; ++y) {
        // The source rows behind this output row, folded into one.
        std::fill(line.begin(), line.end(), 0.0f);
        for (int k = 0; k < rows.count[y]; ++k) {
            const float w = rows.weight[rows.offset[y] + k];
            const long row = origin + (rows.first[y] + k) * dv + cols.lo * du;
            if (du == 1) {
                const unsigned char* src = px.data + static_cast<size_t>(row) * C;
                for (int i = 0; i < span * C; ++i) line[i] += w * src[i];
            } else {
                for (int i = 0; i < span; ++i) {
                    const unsigned char* src = px.data + static_cast<size_t>(row + i * du) * C;
                    for (int c = 0; c < C; ++c) line[i * C + c] += w * src[c];
                }
            }
        }
        uint32_t* out = reinterpret_cast<uint32_t*>(reinterpret_cast<unsigned char*>(dst)
                                                    + static_cast<size_t>(y) * stride);
        for (int x = 0; x < width; ++x) {
            float acc[4] = {0, 0, 0, 0};
            const float* base = line.data() + static_cast<size_t>(cols.first[x] - cols.lo) * C;
            for (int k = 0; k < cols.count[x]; ++k) {
                const float w = cols.weight[cols.offset[x] + k];
                for (int c = 0; c < C; ++c) acc[c] += w * base[k * C + c];
            }
            if (C == 4) {
                const float a = acc[3] / 255.0f;
                acc[0] = acc[0] * a + gr * (1 - a);
                acc[1] = acc[1] * a + gg * (1 - a);
                acc[2] = acc[2] * a + gb * (1 - a);
            }
            const auto ch = [](float v) {
                return static_cast<uint32_t>(std::clamp(v + 0.5f, 0.0f, 255.0f));
            };
            out[x] = 0xff000000u | (ch(acc[0]) << 16) | (ch(acc[1]) << 8) | ch(acc[2]);
        }
    }
    return true;
}
