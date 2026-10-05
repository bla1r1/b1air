// pam-try — authenticate once through a PAM service, as a login screen
// does, for tests: answers every password prompt with the given password and
// prints what the modules say.
//
//   pam-try <confdir> <service> <user> <password>     exit 0 when accepted
#define _GNU_SOURCE
#include <security/pam_appl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int conv(int n, const struct pam_message **msg, struct pam_response **resp, void *data) {
	struct pam_response *r = calloc((size_t)n, sizeof(*r));
	if (!r) return PAM_BUF_ERR;
	for (int i = 0; i < n; ++i) {
		if (msg[i]->msg_style == PAM_PROMPT_ECHO_OFF || msg[i]->msg_style == PAM_PROMPT_ECHO_ON)
			r[i].resp = strdup((const char *)data);
		else
			fprintf(stderr, "pam: %s\n", msg[i]->msg);
	}
	*resp = r;
	return PAM_SUCCESS;
}

int main(int argc, char **argv) {
	if (argc != 5) { fprintf(stderr, "usage: pam-try <confdir> <service> <user> <password>\n"); return 2; }
	struct pam_conv c = { conv, argv[4] };
	pam_handle_t *h = NULL;
	if (pam_start_confdir(argv[2], argv[3], &c, argv[1], &h) != PAM_SUCCESS) return 2;
	const int r = pam_authenticate(h, 0);
	pam_end(h, r);
	printf("%s\n", r == PAM_SUCCESS ? "accepted" : pam_strerror(NULL, r));
	return r == PAM_SUCCESS ? 0 : 1;
}
