#pragma once

namespace b1air {

class SessionManager {
public:
    static int run_session();

    /**
     * The focus/screen-time tracker loop. Blocks until the sway IPC socket
     * closes.
     *
     * Exposed so `b1air-daemon focus-tracker` runs this very code rather than
     * its own copy. It used to be a second, near-identical implementation in
     * main.cpp, and the copies had already diverged in exactly the way that
     * costs: the fix for querying the tree on the socket the subscription is
     * parked on landed in one of them and not the other.
     */
    static void run_focus_tracker();
    static void run_autotiler();

};

} // namespace b1air
