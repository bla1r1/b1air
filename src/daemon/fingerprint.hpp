#pragma once
// Fingerprints, through fprintd (net.reactivated.Fprint on the system bus) —
// the service KDE and GNOME use, with whatever reader libfprint drives.
//
//   b1air-daemon fingerprint status            {"available", "device", ...}
//   b1air-daemon fingerprint enroll <finger>   one line per touch, then done
//   b1air-daemon fingerprint delete <finger>|all
//   b1air-daemon fingerprint verify            one line per touch, then done
//
// Fingers are fprintd's names: right-index-finger, left-thumb, and so on.
// Enrolling and verifying print a line for every event —
// "status enroll-stage-passed", "status verify-no-match" — and end with
// "done <result>"; the settings page reads them as they come. Closing stdin
// or SIGTERM stops a scan in progress and gives the reader back.
//
// The lock screens do not use this: they authenticate through PAM
// (pam_fprintd), alongside the password, with the PAM file the suite ships.
//
//   b1air-daemon fingerprint login status      {"supported", "enabled", ...}
//   b1air-daemon fingerprint login on|off      as root (pkexec)
//
// The login screen (SDDM) reads only /etc/pam.d/sddm, so that one file —
// and no other: not sudo, polkit or the console — gets a marked block
// before its first auth line: an empty password goes to the reader
// (pam_fprintd), a typed one on to the password check as before. The
// greeter learns it is on from /etc/b1air/fingerprint-login.qml.

#include <string>

namespace b1air::fingerprint {

std::string status_json();
int enroll(const std::string& finger);
int remove(const std::string& finger);   // "all" for every one
int verify();

std::string login_status_json();
int login_set(bool on);   // 0 done, 1 refused, 2 not possible here

} // namespace b1air::fingerprint
