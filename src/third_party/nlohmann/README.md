# nlohmann/json — vendored single header

`json.hpp` is the official single-header amalgamation of
[nlohmann/json](https://github.com/nlohmann/json), taken verbatim from the
release asset.

* Version: **3.12.0**
* Source: <https://github.com/nlohmann/json/releases/download/v3.12.0/json.hpp>
* Licence: MIT (the text is at the top of the file)

It is unmodified.

## Why it is here

The daemon parsed the sway tree and the weather reply with it, and got the
header from the distribution's `nlohmann-json` package. That made a header-only
library — one file, no code to link — into something the desktop refused to
build without, and tied it to whichever version the distribution had settled
on. Carrying the header means the build depends on the compiler and nothing
else for this.

Same reasoning as `third_party/sqlite`, and the same trade: the repository
carries 950 KB so that installing does not have to reach out for it.

## Updating

Download the `json.hpp` asset of the desired release over this file, put the
new version number in this README, and rebuild. There is nothing else to do —
no build file mentions the version.
