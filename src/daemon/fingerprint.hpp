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

#include <string>

namespace b1air::fingerprint {

std::string status_json();
int enroll(const std::string& finger);
int remove(const std::string& finger);   // "all" for every one
int verify();

} // namespace b1air::fingerprint
