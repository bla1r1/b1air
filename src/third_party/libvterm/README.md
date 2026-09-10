# libvterm (vendored)

The terminal state machine behind `b1air-term`, copied here unmodified from
upstream's release tarball.

* Version: **0.3.3**
* Source: <https://launchpad.net/libvterm/trunk/v0.3/+download/libvterm-0.3.3.tar.gz>
* Licence: MIT (`LICENSE` in this directory)

`src/` and `include/` are upstream's own, with upstream's layout. The three
`.inc` files — `src/fullwidth.inc` and `src/encoding/*.inc` — are lookup tables
that upstream's Makefile can regenerate from `.tbl` files with a Perl script,
and which the release tarball ships already generated. They are used as
shipped, so building this needs no Perl.

## Why it is vendored

`b1air-term` is a real terminal emulator: it runs a shell on a pty and needs
something to turn that byte stream into a screen. libvterm is that something,
and it was the last distribution package the terminal could not start without.
It is 6,900 lines across nine C files, so carrying it costs about as much as
one of this project's own windows, and `libvterm` is out of the installer's
package list.

Only twelve of its functions are used, all from `apps/term/terminal_item.cpp`:
`vterm_new`, `vterm_free`, `vterm_set_size`, `vterm_set_utf8`,
`vterm_input_write`, `vterm_output_set_callback`, `vterm_obtain_screen`,
`vterm_screen_reset`, `vterm_screen_set_callbacks`,
`vterm_screen_enable_altscreen`, `vterm_screen_flush_damage` and
`vterm_screen_get_cell`.

## A note on updating it

Unlike the rest of what this project vendors, libvterm parses **untrusted
input**: everything a program running in the terminal prints goes through it,
including anything a remote host sends. A distribution package would get
security updates without anyone here noticing; a vendored copy will not. If
upstream publishes a fix, it has to be pulled in by hand.

## Build flags

Compiled as C, with `-w`: like the SQLite amalgamation beside it, upstream's
code is not warning-clean under the `-Wall -Wextra` this project holds its own
code to, and upstream's warnings are not ours to audit on every build. Built
once as an OBJECT library.

## Updating

Download a newer tarball, replace `src/`, `include/` and `LICENSE`, rebuild.
No patches are applied.
