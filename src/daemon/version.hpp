#pragma once

// One version for the whole suite — daemon, shell, and every b1air-* app —
// the same model KDE Plasma uses for its own components. Bump this by hand
// when it's warranted; nothing derives it automatically from git history,
// since commit count and version number are different things.
namespace b1air {
inline constexpr const char* kVersion = "0.3.0";
}
