# b1air Symbols

`b1air-symbols.ttf` is the desktop's icon font, built by `tools/build-symbols.py`
from JetBrainsMono Nerd Font Mono with its icons redrawn from
[Lucide](https://lucide.dev). Rebuild it after using a new icon codepoint in the
source; the script prints which ones it could not match.

Its glyphs are other people's, under free licences that go with the font
wherever it goes (`make install` puts them beside it):

| File | Covers |
| --- | --- |
| `LICENSE-OFL.txt` | JetBrains Mono and the font as a whole: SIL Open Font License 1.1. Being a modified version, it is named `b1air Symbols`, not after either font. |
| `LICENSE-nerd-fonts.md` | The Nerd Fonts icon sets the glyphs Lucide has no drawing for come from (Material Design Icons and the rest), each under its own free licence as listed there. |
| `LICENSE-lucide.txt` | The Lucide drawings: ISC (and MIT for those derived from Feather). |
