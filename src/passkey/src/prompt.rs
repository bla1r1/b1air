//! The window with the QR code: PasskeyPrompt.qml, run by quickshell as the
//! polkit dialog is, and spoken to over a socket of its own in
//! $XDG_RUNTIME_DIR/b1air. It sits at the top of the shell's QML tree, beside
//! Main.qml: `quickshell -p` on a file in a subdirectory does not load the Ui
//! components it imports.
//!
//! To the window, one line each:
//!   qr <width> <bits>     the code, row by row, 1 for a dark module
//!   state <name>          waiting | connecting | connected
//!   error <name>          bluetooth | failed | timeout
//! From it:
//!   cancel                the person closed it

use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::unix::OwnedWriteHalf;
use tokio::net::UnixListener;
use tokio::process::{Child, Command};
use tokio::sync::watch;

pub struct Prompt {
    child: Child,
    writer: OwnedWriteHalf,
    cancelled: watch::Receiver<bool>,
}

fn runtime_dir() -> PathBuf {
    let base = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", current_uid())));
    base.join("b1air")
}

fn current_uid() -> u32 {
    // The owner of /proc/self is this process's uid; no libc needed.
    use std::os::unix::fs::MetadataExt;
    std::fs::metadata("/proc/self").map(|m| m.uid()).unwrap_or(0)
}

/// Where the window's QML is: the system install first, as the polkit
/// dialog looks, then a per-user `make install`.
fn qml_path() -> Option<PathBuf> {
    let mut candidates = vec![
        PathBuf::from("/usr/local/share/b1air-shell/qml/PasskeyPrompt.qml"),
        PathBuf::from("/usr/share/b1air-shell/qml/PasskeyPrompt.qml"),
    ];
    if let Some(home) = std::env::var_os("HOME") {
        candidates.push(Path::new(&home).join(".config/b1air-shell/PasskeyPrompt.qml"));
    }
    candidates.into_iter().find(|p| p.is_file())
}

impl Prompt {
    /// Put the window up for `rp_id`; `create` when a passkey is being made.
    pub async fn open(rp_id: &str, create: bool) -> Option<Prompt> {
        let qml = qml_path()?;
        let dir = runtime_dir();
        std::fs::create_dir_all(&dir).ok()?;
        let sock = dir.join("passkey-prompt.sock");
        let _ = std::fs::remove_file(&sock);
        let listener = UnixListener::bind(&sock).ok()?;
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&sock, std::fs::Permissions::from_mode(0o600)).ok()?;
        }
        let child = Command::new("quickshell")
            .arg("-p")
            .arg(&qml)
            .env("PASSKEY_SOCKET", &sock)
            .env("PASSKEY_RP", rp_id)
            .env("PASSKEY_OP", if create { "create" } else { "get" })
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .ok()?;
        let accepted = tokio::time::timeout(Duration::from_secs(10), listener.accept()).await;
        let _ = std::fs::remove_file(&sock);
        let (stream, _) = accepted.ok()?.ok()?;
        let (reader, writer) = stream.into_split();
        let (tx, cancelled) = watch::channel(false);
        tokio::spawn(async move {
            let mut lines = BufReader::new(reader).lines();
            // A closed window is a cancel too.
            while let Ok(Some(line)) = lines.next_line().await {
                if line.trim() == "cancel" {
                    break;
                }
            }
            let _ = tx.send(true);
        });
        Some(Prompt { child, writer, cancelled })
    }

    async fn line(&mut self, text: &str) {
        let _ = self.writer.write_all(format!("{text}\n").as_bytes()).await;
    }

    pub async fn qr(&mut self, payload: &str) {
        let Ok(code) = qrcode::QrCode::new(payload.as_bytes()) else {
            self.error("failed").await;
            return;
        };
        let bits: String = code
            .to_colors()
            .iter()
            .map(|c| if *c == qrcode::Color::Dark { '1' } else { '0' })
            .collect();
        self.line(&format!("qr {} {bits}", code.width())).await;
    }

    pub async fn state(&mut self, name: &str) {
        self.line(&format!("state {name}")).await;
    }

    pub async fn error(&mut self, name: &str) {
        self.line(&format!("error {name}")).await;
    }

    /// Resolves when the person closes the window.
    pub async fn cancelled(&mut self) {
        let _ = self.cancelled.wait_for(|c| *c).await;
    }

    pub async fn close(mut self) {
        let _ = self.child.kill().await;
    }
}
