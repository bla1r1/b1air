# stb_image (vendored)

`stb_image.h` from <https://github.com/nothings/stb>, copied here unmodified.

* Version: **2.30**
* Licence: public domain or MIT, at the user's choice (see the end of the file)

## Why it is vendored

`b1air-bg` decodes the wallpaper once per change and then lets the picture go.
Going through Qt for that pulled QtCore and QtGui into a process that otherwise
needs nothing of them, and their per-process start-up cost alone was several
times what swaybg uses in total. One header, compiled into one source file
(`bg/image.cpp`), decodes JPEG, PNG, BMP, GIF and TGA with no library to link.
