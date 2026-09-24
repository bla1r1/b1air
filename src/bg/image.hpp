#pragma once

#include <cstdint>
#include <string>

// Decodes the picture at `path` and writes it into `dst` — XRGB8888, `stride`
// bytes a row — scaled to cover `width`×`height`, centred and cropped (what
// sway calls `fill`). Transparent parts show `ground` (0xRRGGBB) through.
//
// The full-size picture exists only inside this call: it is resampled straight
// into `dst`, which is the buffer the compositor is given, and freed on the
// way out. Returns false when the file cannot be read as a picture.
bool decode_cover(const std::string& path, int width, int height, uint32_t ground,
                  uint32_t* dst, int stride);
