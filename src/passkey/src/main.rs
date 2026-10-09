//! b1air-passkey — the phone as a security key.
//!
//! Signing in to a website with a passkey kept on a phone is, on Windows and
//! macOS, a QR code on the screen, the phone's camera, and Bluetooth to show
//! the phone is in the room (CTAP 2.2 "hybrid", caBLE). Chromium does this on
//! Linux by itself; Firefox does not. So this program is a security key: a
//! FIDO HID device (made by b1air-fido-uhid, the root half) that every
//! browser already knows how to talk to. When a site asks it for a passkey it
//! puts up a QR code, and the phone that scans it answers — the request goes
//! to the phone as the browser wrote it, and the phone's answer comes back
//! as the key's.
//!
//! What a browser checks of a security key still holds: it checks the site
//! before the request reaches this key, the phone shows which site it signs
//! in to and asks for its own fingerprint or face, and the tunnel to the
//! phone is encrypted end to end with keys that are only in the QR code.
//!
//! On by default where there is a Bluetooth adapter; Settings → Lock & Login
//! turns it off ("passkeyPhone" in ~/.config/sway/settings.json). While off,
//! it holds no device and browsers see no key.

mod ctap;
mod ctaphid;
mod hybrid;
mod prompt;

use std::path::PathBuf;
use std::time::Duration;

use tokio::sync::{mpsc, oneshot};
use tokio_seqpacket::UnixSeqpacket;

use ctaphid::{Assembler, Frame, BROADCAST};

const FIDO_SOCKET: &str = "/run/b1air-fido/fido.sock";

/// B1AIR_FIDO_SOCKET stands in for the helper's socket in tests
/// (tools/test-passkey.sh), which play the browser without root.
fn fido_socket() -> String {
    std::env::var("B1AIR_FIDO_SOCKET").unwrap_or_else(|_| FIDO_SOCKET.to_owned())
}

fn settings_path() -> PathBuf {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/tmp"));
    home.join(".config/sway/settings.json")
}

/// On unless Settings turned it off, as on other desktops — but only with a
/// Bluetooth adapter: without one no phone can show it is nearby, and a key
/// that can only fail would sit in every browser's way.
fn enabled() -> bool {
    let setting = std::fs::read(settings_path())
        .ok()
        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
        .and_then(|v| v.get("passkeyPhone").and_then(serde_json::Value::as_bool))
        .unwrap_or(true);
    setting && has_bluetooth()
}

fn has_bluetooth() -> bool {
    std::fs::read_dir("/sys/class/bluetooth")
        .map(|mut d| d.any(|e| e.is_ok_and(|e| e.file_name().to_string_lossy().starts_with("hci"))))
        .unwrap_or(false)
}

#[tokio::main]
async fn main() {
    if std::env::args().nth(1).as_deref() == Some("--version") {
        println!("b1air-passkey {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    // RUST_LOG=libwebauthn=debug shows each step of a connection to the phone.
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .with_writer(std::io::stderr)
        .init();
    let mut said_waiting = false;
    loop {
        if !enabled() {
            tokio::time::sleep(Duration::from_secs(2)).await;
            continue;
        }
        let path = fido_socket();
        match UnixSeqpacket::connect(&path).await {
            Ok(sock) => {
                said_waiting = false;
                eprintln!("b1air-passkey: the key is up");
                serve(sock).await;
                eprintln!("b1air-passkey: the key is down");
            }
            Err(e) => {
                if !said_waiting {
                    eprintln!("b1air-passkey: {path}: {e} (is b1air-fido-uhid.service running?)");
                    said_waiting = true;
                }
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        }
    }
}

/// The credentials a silent check is being answered with, for the
/// getNextAssertion calls that fetch the rest.
#[derive(Default)]
struct Silent {
    rp_id: String,
    credentials: Vec<ciborium::value::Value>,
    next: usize,
}

struct Busy {
    cid: u32,
    cancel: Option<oneshot::Sender<()>>,
    status: u8,
}

/// Answers as the key until the socket closes or the setting goes off.
async fn serve(sock: UnixSeqpacket) {
    let mut asm = Assembler::default();
    let mut next_cid: u32 = 1;
    let mut busy: Option<Busy> = None;
    let mut silent = Silent::default();
    let (done_tx, mut done_rx) = mpsc::channel::<(u32, Vec<u8>)>(4);
    let mut keepalive = tokio::time::interval(Duration::from_millis(100));
    let mut settings = tokio::time::interval(Duration::from_secs(2));
    let mut buf = [0u8; ctaphid::REPORT + 1];

    let send = |cid: u32, cmd: u8, data: Vec<u8>| {
        let sock = &sock;
        async move {
            for pkt in ctaphid::fragment(cid, cmd, &data) {
                if sock.send(&pkt).await.is_err() {
                    return false;
                }
            }
            true
        }
    };

    loop {
        tokio::select! {
            got = sock.recv(&mut buf) => {
                let Ok(n) = got else { return };
                if n == 0 { return; }
                match asm.feed(&buf[..n]) {
                    Frame::Partial => {}
                    Frame::Error { cid, code } => { send(cid, ctaphid::ERROR, vec![code]).await; }
                    Frame::Message { cid, cmd, data } => {
                        let reply = handle(cid, cmd, data, &mut next_cid, &mut busy, &mut silent, &done_tx);
                        if let Some((rcid, rcmd, rdata)) = reply {
                            if !send(rcid, rcmd, rdata).await { return; }
                        }
                    }
                }
            }
            Some((cid, response)) = done_rx.recv() => {
                tracing::debug!(cid, status = response.first().copied().unwrap_or(0), len = response.len(), "answer to the browser");
                if busy.as_ref().map(|b| b.cid) == Some(cid) {
                    busy = None;
                    if !send(cid, ctaphid::CBOR, response).await { return; }
                }
            }
            _ = keepalive.tick() => {
                if let Some(b) = &busy {
                    if !send(b.cid, ctaphid::KEEPALIVE, vec![b.status]).await { return; }
                }
            }
            _ = settings.tick() => {
                if !enabled() {
                    if let Some(b) = busy.as_mut() {
                        if let Some(c) = b.cancel.take() { let _ = c.send(()); }
                    }
                    return;
                }
            }
        }
    }
}

/// One whole CTAPHID message. A reply now, or None when the answer comes
/// later through `done` (the phone) or not at all (CANCEL).
fn handle(
    cid: u32,
    cmd: u8,
    data: Vec<u8>,
    next_cid: &mut u32,
    busy: &mut Option<Busy>,
    silent: &mut Silent,
    done: &mpsc::Sender<(u32, Vec<u8>)>,
) -> Option<(u32, u8, Vec<u8>)> {
    if cmd == ctaphid::INIT {
        if data.len() != 8 {
            return Some((cid, ctaphid::ERROR, vec![ctaphid::ERR_INVALID_LEN]));
        }
        // An INIT on a channel that is waiting on the phone abandons it.
        if let Some(b) = busy.as_mut().filter(|b| b.cid == cid) {
            if let Some(c) = b.cancel.take() {
                let _ = c.send(());
            }
            *busy = None;
        }
        let new_cid = if cid == BROADCAST {
            let c = *next_cid;
            *next_cid = next_cid.wrapping_add(1).max(1);
            if *next_cid == BROADCAST {
                *next_cid = 1;
            }
            c
        } else {
            cid
        };
        let mut reply = data;
        reply.extend_from_slice(&new_cid.to_be_bytes());
        // Protocol 2, device version 0.3.0; capabilities WINK | CBOR | NMSG
        // (no U2F: there is nothing to answer it with).
        reply.extend_from_slice(&[2, 0, 3, 0, 0x01 | 0x04 | 0x08]);
        return Some((cid, ctaphid::INIT, reply));
    }
    if cid == BROADCAST || cid == 0 {
        return Some((cid, ctaphid::ERROR, vec![ctaphid::ERR_INVALID_CHANNEL]));
    }
    match cmd {
        ctaphid::PING => Some((cid, ctaphid::PING, data)),
        ctaphid::WINK | ctaphid::LOCK => Some((cid, cmd, Vec::new())),
        ctaphid::CANCEL => {
            tracing::debug!(cid, "CANCEL from the browser");
            if let Some(b) = busy.as_mut().filter(|b| b.cid == cid) {
                if let Some(c) = b.cancel.take() {
                    let _ = c.send(());
                }
            }
            None
        }
        ctaphid::CBOR => {
            tracing::debug!(cid, op = data.first().copied().unwrap_or(0), len = data.len(), busy = busy.is_some(), "CBOR from the browser");
            if busy.is_some() {
                return Some((cid, ctaphid::ERROR, vec![ctaphid::ERR_CHANNEL_BUSY]));
            }
            let Some((&op, payload)) = data.split_first() else {
                return Some((cid, ctaphid::ERROR, vec![ctaphid::ERR_INVALID_LEN]));
            };
            cbor(cid, op, payload.to_vec(), busy, silent, done).map(|r| (cid, ctaphid::CBOR, r))
        }
        _ => Some((cid, ctaphid::ERROR, vec![ctaphid::ERR_INVALID_CMD])),
    }
}

fn cbor(
    cid: u32,
    op: u8,
    payload: Vec<u8>,
    busy: &mut Option<Busy>,
    silent: &mut Silent,
    done: &mpsc::Sender<(u32, Vec<u8>)>,
) -> Option<Vec<u8>> {
    let (cancel_tx, cancel_rx) = oneshot::channel();
    if op != ctap::GET_NEXT_ASSERTION {
        *silent = Silent::default();
    }
    let done = done.clone();
    match op {
        ctap::GET_INFO => Some(ctap::get_info()),
        ctap::MAKE_CREDENTIAL | ctap::GET_ASSERTION => {
            let Some(req) = ctap::parse(op, &payload) else {
                return Some(vec![ctap::ERR_INVALID_CBOR]);
            };
            // A silent check ("is one of these credentials on this key?",
            // asked before signing in and before making a passkey): yes,
            // all of them — ctap::silent_yes says why.
            if req.silent {
                if req.credentials.is_empty() {
                    return Some(vec![ctap::ERR_NO_CREDENTIALS]);
                }
                let answer = ctap::silent_yes(&req.rp_id, &req.credentials, 0);
                *silent = Silent { rp_id: req.rp_id, credentials: req.credentials, next: 1 };
                return Some(answer);
            }
            // Firefox's "blink so they touch you", sent when it believes no
            // credential is on this key: not a site, never a QR code.
            if op == ctap::MAKE_CREDENTIAL && req.rp_id == "make.me.blink" {
                return Some(vec![ctap::ERR_NOT_ALLOWED]);
            }
            // With more than one key plugged in, a browser asks each to
            // flash and waits for a touch with a throwaway request for
            // ".dummy". Not a site: no QR for it. The browser cancels when
            // another key is touched.
            if op == ctap::MAKE_CREDENTIAL && req.rp_id == ".dummy" {
                return wait_for_cancel(cid, cancel_tx, cancel_rx, busy, done);
            }
            *busy = Some(Busy { cid, cancel: Some(cancel_tx), status: ctaphid::STATUS_UPNEEDED });
            tokio::spawn(async move {
                let response = hybrid::run(op, payload, req.rp_id, cancel_rx).await;
                let _ = done.send((cid, response)).await;
            });
            None
        }
        // CTAP 2.1's way of the same "touch the one you mean".
        ctap::SELECTION => wait_for_cancel(cid, cancel_tx, cancel_rx, busy, done),
        // The rest of a silent check's answer. A real assertion is one: the
        // phone shows its own account picker.
        ctap::GET_NEXT_ASSERTION => {
            if silent.next < silent.credentials.len() {
                let answer = ctap::silent_yes(&silent.rp_id, &silent.credentials, silent.next);
                silent.next += 1;
                Some(answer)
            } else {
                Some(vec![ctap::ERR_NOT_ALLOWED])
            }
        }
        _ => Some(vec![ctap::ERR_INVALID_COMMAND]),
    }
}

fn wait_for_cancel(
    cid: u32,
    cancel_tx: oneshot::Sender<()>,
    cancel_rx: oneshot::Receiver<()>,
    busy: &mut Option<Busy>,
    done: mpsc::Sender<(u32, Vec<u8>)>,
) -> Option<Vec<u8>> {
    *busy = Some(Busy { cid, cancel: Some(cancel_tx), status: ctaphid::STATUS_UPNEEDED });
    tokio::spawn(async move {
        let _ = cancel_rx.await;
        let _ = done.send((cid, vec![ctap::ERR_KEEPALIVE_CANCEL])).await;
    });
    None
}
