#pragma once
// The font a native program (cairo) draws its words in.

#include <fontconfig/fontconfig.h>
#include <string>
#include <strings.h>

namespace b1air {

// `want` where it is installed, else the system's sans-serif. Asked of
// fontconfig by a family that is not installed, cairo gets whatever fontconfig
// ranks first in its place — here JetBrains Mono: with Inter missing (the
// inter-font package arrived in 0.3.0, and an update by `make install` does
// not install packages) the lock screen came up all in the terminal's font,
// the look of the old Tokyo Night desktop. sans-serif is what the desktop's
// own fonts.conf orders: Inter where there is one, then Fira Sans.
inline std::string installed_family(const char* want, const char* fallback = "sans-serif") {
    FcPattern* pattern = FcNameParse(reinterpret_cast<const FcChar8*>(want));
    if (!pattern) return fallback;
    FcConfigSubstitute(nullptr, pattern, FcMatchPattern);
    FcDefaultSubstitute(pattern);
    FcResult result;
    FcPattern* match = FcFontMatch(nullptr, pattern, &result);
    bool found = false;
    FcChar8* family = nullptr;
    if (match && FcPatternGetString(match, FC_FAMILY, 0, &family) == FcResultMatch)
        found = strcasecmp(reinterpret_cast<const char*>(family), want) == 0;
    if (match) FcPatternDestroy(match);
    FcPatternDestroy(pattern);
    return found ? want : fallback;
}

} // namespace b1air
