//! CTAPHID framing (CTAP 2.1 §11.2): messages cut into 64-byte reports.
//!
//! An initialization packet is CID(4) CMD(1, high bit set) BCNT(2) DATA(57);
//! a continuation packet is CID(4) SEQ(1, 0..=0x7f) DATA(59).

pub const REPORT: usize = 64;
const INIT_DATA: usize = REPORT - 7;
const CONT_DATA: usize = REPORT - 5;
/// The largest message there can be: 57 + 128 × 59 bytes.
const MAX_MESSAGE: usize = INIT_DATA + 128 * CONT_DATA;

pub const BROADCAST: u32 = 0xffff_ffff;

pub const PING: u8 = 0x81;
pub const LOCK: u8 = 0x84;
pub const INIT: u8 = 0x86;
pub const WINK: u8 = 0x88;
pub const CBOR: u8 = 0x90;
pub const CANCEL: u8 = 0x91;
pub const KEEPALIVE: u8 = 0xbb;
pub const ERROR: u8 = 0xbf;

pub const ERR_INVALID_CMD: u8 = 0x01;
pub const ERR_INVALID_LEN: u8 = 0x03;
pub const ERR_INVALID_SEQ: u8 = 0x04;
pub const ERR_CHANNEL_BUSY: u8 = 0x06;
pub const ERR_INVALID_CHANNEL: u8 = 0x0b;

pub const STATUS_UPNEEDED: u8 = 2;

#[derive(Debug)]
pub enum Frame {
    /// A whole message.
    Message { cid: u32, cmd: u8, data: Vec<u8> },
    /// A packet that cannot be part of one: answered with an ERROR.
    Error { cid: u32, code: u8 },
    /// A packet taken in, the message not finished yet.
    Partial,
}

struct Pending {
    cid: u32,
    cmd: u8,
    total: usize,
    data: Vec<u8>,
    seq: u8,
}

/// Puts the reports of one message back together. One message is assembled
/// at a time, as a key with one transaction at a time does.
#[derive(Default)]
pub struct Assembler {
    pending: Option<Pending>,
}

impl Assembler {
    pub fn feed(&mut self, pkt: &[u8]) -> Frame {
        if pkt.len() != REPORT {
            return Frame::Partial;
        }
        let cid = u32::from_be_bytes([pkt[0], pkt[1], pkt[2], pkt[3]]);
        let byte = pkt[4];
        if byte & 0x80 != 0 {
            // An INIT always wins: it is how a host resynchronises a channel.
            if let Some(p) = &self.pending {
                if p.cid != cid && byte != INIT {
                    return Frame::Error { cid, code: ERR_CHANNEL_BUSY };
                }
            }
            let total = usize::from(u16::from_be_bytes([pkt[5], pkt[6]]));
            if total > MAX_MESSAGE {
                self.pending = None;
                return Frame::Error { cid, code: ERR_INVALID_LEN };
            }
            let take = total.min(INIT_DATA);
            let data = pkt[7..7 + take].to_vec();
            if data.len() == total {
                self.pending = None;
                return Frame::Message { cid, cmd: byte, data };
            }
            self.pending = Some(Pending { cid, cmd: byte, total, data, seq: 0 });
            Frame::Partial
        } else {
            let Some(p) = self.pending.as_mut() else {
                // A continuation of nothing is ignored, as the spec says.
                return Frame::Partial;
            };
            if p.cid != cid {
                return Frame::Error { cid, code: ERR_CHANNEL_BUSY };
            }
            if byte != p.seq {
                self.pending = None;
                return Frame::Error { cid, code: ERR_INVALID_SEQ };
            }
            p.seq += 1;
            let take = (p.total - p.data.len()).min(CONT_DATA);
            p.data.extend_from_slice(&pkt[5..5 + take]);
            if p.data.len() == p.total {
                let p = self.pending.take().unwrap();
                return Frame::Message { cid: p.cid, cmd: p.cmd, data: p.data };
            }
            Frame::Partial
        }
    }
}

/// One message as the reports that carry it.
pub fn fragment(cid: u32, cmd: u8, data: &[u8]) -> Vec<[u8; REPORT]> {
    let mut out = Vec::new();
    let mut first = [0u8; REPORT];
    first[..4].copy_from_slice(&cid.to_be_bytes());
    first[4] = cmd;
    first[5..7].copy_from_slice(&(data.len() as u16).to_be_bytes());
    let head = data.len().min(INIT_DATA);
    first[7..7 + head].copy_from_slice(&data[..head]);
    out.push(first);
    for (seq, chunk) in data[head..].chunks(CONT_DATA).enumerate() {
        let mut pkt = [0u8; REPORT];
        pkt[..4].copy_from_slice(&cid.to_be_bytes());
        pkt[4] = seq as u8;
        pkt[5..5 + chunk.len()].copy_from_slice(chunk);
        out.push(pkt);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        for len in [0usize, 1, 57, 58, 116, 117, 1000, MAX_MESSAGE] {
            let data: Vec<u8> = (0..len).map(|i| i as u8).collect();
            let mut a = Assembler::default();
            let mut got = None;
            for pkt in fragment(0x01020304, CBOR, &data) {
                if let Frame::Message { cid, cmd, data } = a.feed(&pkt) {
                    got = Some((cid, cmd, data));
                }
            }
            assert_eq!(got, Some((0x01020304, CBOR, data)), "length {len}");
        }
    }

    #[test]
    fn other_channel_is_busy() {
        let mut a = Assembler::default();
        let pkts = fragment(1, CBOR, &[0u8; 100]);
        assert!(matches!(a.feed(&pkts[0]), Frame::Partial));
        let other = fragment(2, CBOR, &[4]);
        assert!(matches!(a.feed(&other[0]), Frame::Error { cid: 2, code: ERR_CHANNEL_BUSY }));
        assert!(matches!(a.feed(&pkts[1]), Frame::Message { cid: 1, .. }));
    }

    #[test]
    fn wrong_sequence() {
        let mut a = Assembler::default();
        let pkts = fragment(1, CBOR, &[0u8; 200]);
        a.feed(&pkts[0]);
        assert!(matches!(a.feed(&pkts[2]), Frame::Error { code: ERR_INVALID_SEQ, .. }));
    }
}
