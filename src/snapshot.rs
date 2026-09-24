//! Snapshots: lets a node that fell behind install state instead of replaying
//! the whole log, and lets the journal be purged. The payload format is yours;
//! UC wraps it in its own envelope. This whole-state serde image is correct
//! for any `State`; replace it when state gets large (docs/how-to/change-the-state-shape.md).

use std::io::{Read, Write};

use serde::{Deserialize, Serialize};
use uc_service::{SnapshotError, SnapshotStateMachine};

use crate::state::{Fsm, State};

/// Bump when `State`'s serialized shape changes, and keep reading the old one.
const IMAGE_VERSION: u32 = 1;
/// A refusal, not an allocation: an image this large is corrupt.
const MAX_IMAGE_BYTES: u64 = 1 << 30;

#[derive(Serialize, Deserialize)]
struct Image {
    cursor: Option<u64>,
    state: State,
}

pub struct Frozen {
    cursor: Option<u64>,
    state: State,
}

fn codec(e: impl std::fmt::Display) -> SnapshotError {
    SnapshotError::Codec(e.to_string())
}

impl SnapshotStateMachine for Fsm {
    type SnapshotHandle = Frozen;

    /// Clones the state on the apply thread: O(state). Fine for a starter;
    /// see the how-to for an O(1) persistent-map freeze.
    fn freeze(&self) -> Result<(Frozen, u64), SnapshotError> {
        let h = Frozen { cursor: self.last_applied, state: self.state.clone() };
        Ok((h, self.last_applied.unwrap_or(0)))
    }

    /// Layout: `image_version u32 LE ‖ len u64 LE ‖ bincode(Image)`.
    fn stream_snapshot(h: Frozen, dst: &mut dyn Write) -> Result<(), SnapshotError> {
        let body = bincode::serde::encode_to_vec(&Image { cursor: h.cursor, state: h.state }, bincode::config::standard())
            .map_err(codec)?;
        dst.write_all(&IMAGE_VERSION.to_le_bytes())?;
        dst.write_all(&(body.len() as u64).to_le_bytes())?;
        dst.write_all(&body)?;
        Ok(())
    }

    /// `position` is the instant P, an EXCLUSIVE frontier: the image covers
    /// frames strictly below P. Restore the image's own cursor, return P.
    /// Nothing changes unless the whole image decodes.
    fn install_snapshot(&mut self, position: u64, src: &mut dyn Read) -> Result<u64, SnapshotError> {
        let mut word = [0u8; 4];
        src.read_exact(&mut word)?;
        let v = u32::from_le_bytes(word);
        if v != IMAGE_VERSION {
            return Err(codec(format!("unknown image version {v} (this build reads {IMAGE_VERSION})")));
        }
        let mut len = [0u8; 8];
        src.read_exact(&mut len)?;
        let len = u64::from_le_bytes(len);
        if len > MAX_IMAGE_BYTES {
            return Err(codec(format!("image body of {len} bytes exceeds {MAX_IMAGE_BYTES}")));
        }
        let mut body = vec![0u8; len as usize];
        src.read_exact(&mut body)?;
        let (img, used): (Image, usize) =
            bincode::serde::decode_from_slice(&body, bincode::config::standard()).map_err(codec)?;
        if used != body.len() {
            return Err(codec(format!("image has {} trailing bytes", body.len() - used)));
        }
        if let Some(c) = img.cursor
            && c >= position
        {
            return Err(codec(format!("image cursor {c} is not below the instant {position}")));
        }
        self.state = img.state;
        self.last_applied = img.cursor;
        Ok(position)
    }

    /// Canonical text for diff replay: one line per entry, sorted (BTreeMap
    /// order), Debug-quoted so a newline in a value cannot forge a line.
    fn project(&self, out: &mut dyn Write) -> Result<(), SnapshotError> {
        // TODO(app): one line per record of your state, in a stable sorted order.
        for (k, v) in &self.state.entries {
            writeln!(out, "entry {k:?}={v:?}")?;
        }
        Ok(())
    }
}
