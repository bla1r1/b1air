//! One request carried to the phone: a QR code to scan, a caBLE tunnel, the
//! request's CBOR sent through it as the browser wrote it, and the phone's
//! answer handed back the same way.

use std::time::Duration;

use libwebauthn::proto::ctap2::cbor::CborRequest;
use libwebauthn::proto::ctap2::Ctap2CommandCode;
use libwebauthn::transport::cable::channel::{CableUpdate, CableUxUpdate};
use libwebauthn::transport::cable::qr_code_device::{CableQrCodeDevice, CableTransports, QrCodeOperationHint};
use libwebauthn::transport::{Channel as _, ChannelSettings, Device as _};
use tokio::sync::oneshot;

use crate::ctap;
use crate::prompt::Prompt;

/// How long the person has to take the phone out and scan.
const SCAN_TIMEOUT: Duration = Duration::from_secs(180);

enum Outcome {
    Answer(Vec<u8>),
    Failed,
    TimedOut,
    BrowserCancelled,
    PersonCancelled,
}

/// Runs `cmd` (makeCredential or getAssertion) on the phone. The reply is a
/// CTAP response: status byte, then CBOR.
///
/// Whatever goes wrong is answered NOT_ALLOWED. Not OPERATION_DENIED, which
/// Firefox takes from a key with its own UV for "wrong finger" and asks
/// again at once — a new QR code each time, round and round.
pub async fn run(cmd: u8, payload: Vec<u8>, rp_id: String, mut cancel: oneshot::Receiver<()>) -> Vec<u8> {
    let create = cmd == ctap::MAKE_CREDENTIAL;
    tracing::debug!(cmd, rp_id, request = %hex(&payload), "to the phone");
    let Some(mut prompt) = Prompt::open(&rp_id, create).await else {
        eprintln!("b1air-passkey: the prompt did not open (is PasskeyPrompt.qml installed?)");
        return vec![ctap::ERR_NOT_ALLOWED];
    };

    if !libwebauthn::transport::cable::is_available().await {
        prompt.error("bluetooth").await;
        // Left up until the person reads it and closes it, or the browser
        // gives up: answering at once would only make the browser ask again.
        tokio::select! {
            _ = prompt.cancelled() => {}
            _ = &mut cancel => {}
        }
        prompt.close().await;
        return vec![ctap::ERR_NOT_ALLOWED];
    }

    let hint = if create { QrCodeOperationHint::MakeCredential } else { QrCodeOperationHint::GetAssertionRequest };
    // The cloud-assisted tunnel only: the QR then also reads on phones whose
    // Play services predate CTAP 2.3's direct BLE channel.
    let mut device = match CableQrCodeDevice::new_transient(hint, CableTransports::CloudAssistedOnly) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("b1air-passkey: {e}");
            prompt.error("failed").await;
            prompt.cancelled().await;
            prompt.close().await;
            return vec![ctap::ERR_NOT_ALLOWED];
        }
    };
    prompt.qr(&device.qr_code.to_string()).await;
    prompt.state("waiting").await;

    let mut channel = match device.channel(ChannelSettings::default()).await {
        Ok(c) => c,
        Err(e) => {
            eprintln!("b1air-passkey: {e}");
            prompt.error("failed").await;
            prompt.cancelled().await;
            prompt.close().await;
            return vec![ctap::ERR_NOT_ALLOWED];
        }
    };
    let mut updates = channel.get_ux_update_receiver();
    let command = if create { Ctap2CommandCode::AuthenticatorMakeCredential } else { Ctap2CommandCode::AuthenticatorGetAssertion };
    // As the phone will take it: see ctap::for_phone.
    let request = CborRequest { command, encoded_data: ctap::for_phone(cmd, &payload).unwrap_or(payload) };

    let outcome = {
        let work = async {
            // cbor_send waits for the phone to connect before its own timeout
            // starts; the scan is bounded here instead.
            channel.cbor_send(&request, Duration::from_secs(30)).await?;
            channel.cbor_recv(Duration::from_secs(300)).await
        };
        tokio::pin!(work);
        let deadline = tokio::time::sleep(SCAN_TIMEOUT);
        tokio::pin!(deadline);
        let mut connected = false;
        loop {
            tokio::select! {
                result = &mut work => break match result {
                    Ok(resp) => {
                        tracing::debug!(status = ?resp.status_code, len = resp.data.as_ref().map_or(0, Vec::len), "the phone answered");
                        let mut out = vec![u8::from(resp.status_code)];
                        out.extend(resp.data.unwrap_or_default());
                        Outcome::Answer(out)
                    }
                    Err(e) => {
                        eprintln!("b1air-passkey: {e}");
                        Outcome::Failed
                    }
                },
                _ = &mut deadline, if !connected => break Outcome::TimedOut,
                _ = &mut cancel => break Outcome::BrowserCancelled,
                _ = prompt.cancelled() => break Outcome::PersonCancelled,
                update = updates.recv() => match update {
                    Ok(CableUxUpdate::CableUpdate(CableUpdate::Connecting | CableUpdate::Authenticating)) => {
                        connected = true;
                        prompt.state("connecting").await;
                    }
                    Ok(CableUxUpdate::CableUpdate(CableUpdate::Connected)) => {
                        connected = true;
                        prompt.state("connected").await;
                    }
                    Ok(CableUxUpdate::CableUpdate(CableUpdate::Error(e))) => {
                        eprintln!("b1air-passkey: connecting to the phone: {e}");
                        break Outcome::Failed;
                    }
                    Ok(_) => {}
                    // Lagged or closed: the work future still finishes.
                    Err(_) => {}
                },
            }
        }
    };
    channel.close().await;

    match outcome {
        Outcome::Answer(out) => {
            prompt.close().await;
            out
        }
        Outcome::BrowserCancelled => {
            prompt.close().await;
            vec![ctap::ERR_KEEPALIVE_CANCEL]
        }
        Outcome::PersonCancelled => {
            prompt.close().await;
            vec![ctap::ERR_NOT_ALLOWED]
        }
        Outcome::TimedOut => {
            prompt.close().await;
            vec![ctap::ERR_USER_ACTION_TIMEOUT]
        }
        Outcome::Failed => {
            prompt.error("failed").await;
            tokio::select! {
                _ = prompt.cancelled() => {}
                _ = tokio::time::sleep(Duration::from_secs(8)) => {}
            }
            prompt.close().await;
            vec![ctap::ERR_NOT_ALLOWED]
        }
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
