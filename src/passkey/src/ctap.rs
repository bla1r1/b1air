//! What this key says about itself, and what it reads of a request before
//! handing the request to the phone unchanged.

use ciborium::value::Value;

pub const MAKE_CREDENTIAL: u8 = 0x01;
pub const GET_ASSERTION: u8 = 0x02;
pub const GET_INFO: u8 = 0x04;
pub const GET_NEXT_ASSERTION: u8 = 0x08;
pub const SELECTION: u8 = 0x0b;

pub const OK: u8 = 0x00;
pub const ERR_INVALID_COMMAND: u8 = 0x01;
pub const ERR_INVALID_CBOR: u8 = 0x12;
pub const ERR_KEEPALIVE_CANCEL: u8 = 0x2d;
pub const ERR_NO_CREDENTIALS: u8 = 0x2e;
pub const ERR_USER_ACTION_TIMEOUT: u8 = 0x2f;
pub const ERR_NOT_ALLOWED: u8 = 0x30;

/// authenticatorGetInfo. The phone does the user verification, so `uv` is
/// on and there is no clientPin: a browser never asks for a PIN for this key.
/// Transports say "hybrid", so a site that stores them knows the passkey
/// lives on a phone and not on a USB stick.
///
/// Canonical CBOR (CTAP 2.1 §8): map keys in order, shorter text keys first.
pub fn get_info() -> Vec<u8> {
    let text = |s: &str| Value::Text(s.into());
    let int = |i: i64| Value::Integer(i.into());
    let alg = |a: i64| Value::Map(vec![(text("alg"), int(a)), (text("type"), text("public-key"))]);
    let info = Value::Map(vec![
        (int(0x01), Value::Array(vec![text("FIDO_2_0"), text("FIDO_2_1")])),
        (int(0x03), Value::Bytes(AAGUID.to_vec())),
        (
            int(0x04),
            Value::Map(vec![
                (text("rk"), Value::Bool(true)),
                (text("up"), Value::Bool(true)),
                (text("uv"), Value::Bool(true)),
                (text("plat"), Value::Bool(false)),
            ]),
        ),
        (int(0x05), int(7609)),
        (int(0x09), Value::Array(vec![text("hybrid")])),
        (int(0x0a), Value::Array(vec![alg(-7), alg(-8), alg(-257)])),
    ]);
    let mut out = vec![OK];
    ciborium::into_writer(&info, &mut out).expect("CBOR into a Vec");
    out
}

/// All zeroes: "no attestation of the model", which is what a phone answering
/// through a browser's hybrid flow gives too.
const AAGUID: [u8; 16] = [0; 16];

/// The request as a phone takes it. Browsers write it for a USB key, and an
/// iPhone drops the whole connection over what a key would ignore:
///
///   - `hmac-secret`, which Firefox sends (as `false`) to any key that lists
///     no extensions. A phone does PRF its own way, and an iPhone does not
///     list hmac-secret.
///   - a site without `name`, or a user without `displayName`. WebAuthn
///     requires both and CTAP does not; Firefox sends neither, and an iPhone
///     answers "cannot complete the operation" to their absence. The site's
///     id and the user's name stand in, as browsers show them.
///
/// None when the request is not CBOR this can read: it then goes as it came.
pub fn for_phone(cmd: u8, payload: &[u8]) -> Option<Vec<u8>> {
    let mut value: Value = ciborium::from_reader(payload).ok()?;
    let map = match &mut value {
        Value::Map(m) => m,
        _ => return None,
    };
    let ext_key = match cmd {
        MAKE_CREDENTIAL => 0x06,
        GET_ASSERTION => 0x04,
        _ => return None,
    };
    let is = |k: &Value, n: i64| k.as_integer().map(i128::from) == Some(n.into());
    if let Some((_, Value::Map(ext))) = map.iter_mut().find(|(k, _)| is(k, ext_key)) {
        ext.retain(|(k, _)| k.as_text() != Some("hmac-secret"));
    }
    map.retain(|(k, v)| !(is(k, ext_key) && matches!(v, Value::Map(m) if m.is_empty())));
    if cmd == MAKE_CREDENTIAL {
        if let Some((_, Value::Map(rp))) = map.iter_mut().find(|(k, _)| is(k, 0x02)) {
            if get_text(rp, "name").is_none() {
                if let Some(id) = get_text(rp, "id").cloned() {
                    // Canonical order: "id", then "name".
                    rp.push((Value::Text("name".into()), id));
                }
            }
        }
        if let Some((_, Value::Map(user))) = map.iter_mut().find(|(k, _)| is(k, 0x03)) {
            if get_text(user, "displayName").is_none() {
                let name = get_text(user, "name").cloned().unwrap_or(Value::Text(String::new()));
                // Canonical order: shorter keys first, so after "name".
                user.push((Value::Text("displayName".into()), name));
            }
        }
    }
    let mut out = Vec::new();
    ciborium::into_writer(&value, &mut out).ok()?;
    Some(out)
}

/// The answer to a silent check — "is one of these credentials on you?" —
/// for credential `index` of `all`: yes, each of them.
///
/// A phone cannot be asked without a QR code, so this key cannot know. "None
/// here" was the first answer, and it was wrong both ways: before signing in
/// Firefox then took the allowList to be empty and, instead of asking for an
/// assertion, made the key blink with a throwaway passkey for
/// "make.me.blink" — which went to the phone as a QR code and was saved
/// there; before making a passkey it dropped the site's excludeList, so the
/// phone could not refuse a second passkey for the same account. Saying yes
/// sends the whole list on with the real request, and the phone, which
/// knows, answers it.
///
/// The browser reads only which credentials came back (the authenticator
/// data must parse; nothing is signed — the signature is not checked here
/// and never reaches a site).
pub fn silent_yes(rp_id: &str, all: &[Value], index: usize) -> Vec<u8> {
    use sha2::{Digest, Sha256};
    let mut auth_data = Sha256::digest(rp_id.as_bytes()).to_vec();
    auth_data.extend_from_slice(&[0x00, 0, 0, 0, 0]); // no flags, counter 0
    let mut map = vec![
        (Value::Integer(1.into()), all[index].clone()),
        (Value::Integer(2.into()), Value::Bytes(auth_data)),
        (Value::Integer(3.into()), Value::Bytes(vec![0])),
    ];
    if index == 0 && all.len() > 1 {
        map.push((Value::Integer(5.into()), Value::Integer((all.len() as i64).into())));
    }
    let mut out = vec![OK];
    ciborium::into_writer(&Value::Map(map), &mut out).expect("CBOR into a Vec");
    out
}

/// What the prompt and the dispatch need from a request.
#[derive(Debug, Default)]
pub struct Request {
    pub rp_id: String,
    /// `up: false` — a silent check ("is one of these credentials here?").
    pub silent: bool,
    /// getAssertion's allowList, or makeCredential's excludeList.
    pub credentials: Vec<Value>,
}

fn get<'a>(map: &'a [(Value, Value)], key: i64) -> Option<&'a Value> {
    map.iter().find(|(k, _)| k.as_integer().map(i128::from) == Some(key.into())).map(|(_, v)| v)
}

fn get_text<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a Value> {
    map.iter().find(|(k, _)| k.as_text() == Some(key)).map(|(_, v)| v)
}

pub fn parse(cmd: u8, payload: &[u8]) -> Option<Request> {
    let value: Value = ciborium::from_reader(payload).ok()?;
    let map = value.as_map()?;
    let mut req = Request::default();
    let options = match cmd {
        MAKE_CREDENTIAL => {
            req.rp_id = get(map, 0x02)?.as_map().and_then(|rp| get_text(rp, "id"))?.as_text()?.to_owned();
            req.credentials = get(map, 0x05).and_then(Value::as_array).cloned().unwrap_or_default();
            get(map, 0x07)
        }
        GET_ASSERTION => {
            req.rp_id = get(map, 0x01)?.as_text()?.to_owned();
            req.credentials = get(map, 0x03).and_then(Value::as_array).cloned().unwrap_or_default();
            get(map, 0x05)
        }
        _ => return None,
    };
    if let Some(opts) = options.and_then(Value::as_map) {
        req.silent = get_text(opts, "up").and_then(Value::as_bool) == Some(false);
    }
    Some(req)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    fn encode(v: &Value) -> Vec<u8> {
        let mut out = Vec::new();
        ciborium::into_writer(v, &mut out).unwrap();
        out
    }

    #[test]
    fn get_assertion_rp_and_silence() {
        let text = |s: &str| Value::Text(s.into());
        let req = Value::Map(vec![
            (Value::Integer(1.into()), text("github.com")),
            (Value::Integer(2.into()), Value::Bytes(vec![0; 32])),
            (Value::Integer(5.into()), Value::Map(vec![(text("up"), Value::Bool(false))])),
        ]);
        let r = parse(GET_ASSERTION, &encode(&req)).unwrap();
        assert_eq!(r.rp_id, "github.com");
        assert!(r.silent);
    }

    #[test]
    fn make_credential_rp() {
        let text = |s: &str| Value::Text(s.into());
        let req = Value::Map(vec![
            (Value::Integer(1.into()), Value::Bytes(vec![0; 32])),
            (Value::Integer(2.into()), Value::Map(vec![(text("id"), text("example.org"))])),
        ]);
        let r = parse(MAKE_CREDENTIAL, &encode(&req)).unwrap();
        assert_eq!(r.rp_id, "example.org");
        assert!(!r.silent);
    }

    #[test]
    fn firefox_request_for_the_phone() {
        // What Firefox sent webauthn.io's Register, as logged.
        let hexed = "a6015820ae70e415177913d3545561d306a35aaf3281d3286f3d3b52e18463e4cb24fc0102a16269646b776562617574686e2e696f03a262696453776562617574686e696f2d3132333334343434646e616d656831323333343434340483a263616c672764747970656a7075626c69632d6b6579a263616c672664747970656a7075626c69632d6b6579a263616c6739010064747970656a7075626c69632d6b657906a16b686d61632d736563726574f407a262726bf5627576f5";
        let bytes: Vec<u8> = (0..hexed.len()).step_by(2).map(|i| u8::from_str_radix(&hexed[i..i + 2], 16).unwrap()).collect();
        let out = for_phone(MAKE_CREDENTIAL, &bytes).unwrap();
        let v: Value = ciborium::from_reader(&out[..]).unwrap();
        let map = v.as_map().unwrap();
        assert!(get(map, 0x06).is_none(), "the extensions went with hmac-secret");
        let user = get(map, 0x03).unwrap().as_map().unwrap();
        assert_eq!(get_text(user, "displayName").and_then(Value::as_text), Some("12334444"));
        assert_eq!(get(map, 0x07).unwrap().as_map().unwrap().len(), 2);
        let rp = get(map, 0x02).unwrap().as_map().unwrap();
        assert_eq!(get_text(rp, "name").and_then(Value::as_text), Some("webauthn.io"));
        // Byte for byte what the iPhone accepted, sent by hand while
        // finding this out.
        let accepted = "a5015820ae70e415177913d3545561d306a35aaf3281d3286f3d3b52e18463e4cb24fc0102a26269646b776562617574686e2e696f646e616d656b776562617574686e2e696f03a362696453776562617574686e696f2d3132333334343434646e616d656831323333343434346b646973706c61794e616d656831323333343434340483a263616c672764747970656a7075626c69632d6b6579a263616c672664747970656a7075626c69632d6b6579a263616c6739010064747970656a7075626c69632d6b657907a262726bf5627576f5";
        assert_eq!(hex(&out), accepted);
    }

    #[test]
    fn info_is_ok_and_decodes() {
        let info = get_info();
        assert_eq!(info[0], OK);
        let v: Value = ciborium::from_reader(&info[1..]).unwrap();
        assert!(v.as_map().unwrap().len() >= 5);
    }
}
