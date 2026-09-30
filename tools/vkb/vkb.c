// vkb — press keys the way a physical keyboard does, for tests.
//
// wtype sends a keymap of its own, with made-up keycodes, so sway's
// `bindsym --to-code` bindings (all of ours) never match what it types. This
// sends a full xkb keymap for $XKB_LAYOUT (default "us,ua") and real evdev
// keycodes, as a USB keyboard would, so those bindings fire.
//
//   vkb <logo|shift|ctrl|alt[,...]|-> <evdev keycode>...
//   vkb logo 4        Mod4+3     (KEY_3 = 4)
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "vkb-protocol.h"

static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *mgr;
static void reg(void *d, struct wl_registry *r, uint32_t n, const char *i, uint32_t v) {
	(void)d; (void)v;
	if (!strcmp(i, wl_seat_interface.name)) seat = wl_registry_bind(r, n, &wl_seat_interface, 1);
	if (!strcmp(i, zwp_virtual_keyboard_manager_v1_interface.name))
		mgr = wl_registry_bind(r, n, &zwp_virtual_keyboard_manager_v1_interface, 1);
}
static void unreg(void *d, struct wl_registry *r, uint32_t n) { (void)d; (void)r; (void)n; }
static const struct wl_registry_listener rl = { reg, unreg };
static uint32_t ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000 + t.tv_nsec / 1000000; }

int main(int argc, char **argv) {
	if (argc < 3) return 2;
	struct wl_display *dpy = wl_display_connect(NULL);
	if (!dpy) { fprintf(stderr, "no display\n"); return 1; }
	wl_registry_add_listener(wl_display_get_registry(dpy), &rl, NULL);
	wl_display_roundtrip(dpy);
	if (!seat || !mgr) { fprintf(stderr, "no virtual keyboard manager\n"); return 1; }
	struct zwp_virtual_keyboard_v1 *kb = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(mgr, seat);

	struct xkb_context *ctx = xkb_context_new(0);
	const char *layout = getenv("XKB_LAYOUT") ? getenv("XKB_LAYOUT") : "us,ua";
	struct xkb_rule_names names = { .layout = layout };
	struct xkb_keymap *km = xkb_keymap_new_from_names(ctx, &names, 0);
	char *s = xkb_keymap_get_as_string(km, XKB_KEYMAP_FORMAT_TEXT_V1);
	size_t len = strlen(s) + 1;
	int fd = memfd_create("keymap", 0);
	if (write(fd, s, len) != (ssize_t)len) return 1;
	zwp_virtual_keyboard_v1_keymap(kb, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, len);
	struct xkb_state *st = xkb_state_new(km);
	// A new keyboard: let the focused client take in its keymap first.
	// Without this a Qt client dropped the first key it was sent (the lock
	// screen lost a password's first letter); sway's own bindings did not.
	wl_display_roundtrip(dpy);
	usleep(150000);

	uint32_t modcodes[4]; int nmods = 0;  // evdev codes of the modifiers held
	if (strcmp(argv[1], "-")) {
		char *m = strdup(argv[1]);
		for (char *t = strtok(m, ","); t; t = strtok(NULL, ",")) {
			uint32_t c = !strcmp(t, "logo") ? 125 : !strcmp(t, "shift") ? 42 : !strcmp(t, "ctrl") ? 29 : 56;
			modcodes[nmods++] = c;
		}
	}
	#define SEND(code, down) do { \
		zwp_virtual_keyboard_v1_key(kb, ms(), code, down); \
		xkb_state_update_key(st, (code) + 8, down ? XKB_KEY_DOWN : XKB_KEY_UP); \
		zwp_virtual_keyboard_v1_modifiers(kb, xkb_state_serialize_mods(st, XKB_STATE_MODS_DEPRESSED), \
			xkb_state_serialize_mods(st, XKB_STATE_MODS_LATCHED), xkb_state_serialize_mods(st, XKB_STATE_MODS_LOCKED), \
			xkb_state_serialize_layout(st, XKB_STATE_LAYOUT_EFFECTIVE)); \
		wl_display_roundtrip(dpy); usleep(20000); } while (0)
	for (int i = 0; i < nmods; i++) SEND(modcodes[i], 1);
	for (int i = 2; i < argc; i++) { uint32_t c = atoi(argv[i]); SEND(c, 1); SEND(c, 0); }
	for (int i = nmods - 1; i >= 0; i--) SEND(modcodes[i], 0);
	wl_display_roundtrip(dpy);
	return 0;
}
