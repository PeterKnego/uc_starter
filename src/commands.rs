//! The wire contract between your client and your state machine.
//!
//! Commands go through consensus and are applied on every replica in log
//! order; queries are answered from one replica's local state.
//! TODO(app): replace the registry's commands and queries with your own (keep them in docs/app-design.md in sync).

use serde::{Deserialize, Serialize};

/// Largest key and value this app accepts. One command must fit one datagram:
/// the payload ceiling is 1344 B (1312 B with wire crypto) at the baseline
/// rung, and the session envelope takes 16 B of it.
pub const MAX_KEY_LEN: usize = 128;
pub const MAX_VALUE_LEN: usize = 1024;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Command {
    // Append new variants at the END: the variant index is the wire tag, and
    // reordering changes what old log entries mean.
    Put { key: String, value: String },
    Delete { key: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Response {
    Put { previous: Option<String> },
    Delete { removed: Option<String> },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Query {
    Get { key: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum QueryResponse {
    Value(Option<String>),
}

#[derive(Debug, PartialEq, Eq)]
pub struct CommandError(pub String);

impl std::fmt::Display for CommandError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl Command {
    /// Checked by the client BEFORE submitting: a command that cannot fit one
    /// datagram is refused at the door, not half-way through the cluster.
    pub fn validate(&self) -> Result<(), CommandError> {
        let (key, value) = match self {
            Command::Put { key, value } => (key, Some(value)),
            Command::Delete { key } => (key, None),
        };
        if key.len() > MAX_KEY_LEN {
            return Err(CommandError(format!(
                "key is {} bytes; the limit is {MAX_KEY_LEN}",
                key.len()
            )));
        }
        if let Some(v) = value
            && v.len() > MAX_VALUE_LEN
        {
            return Err(CommandError(format!(
                "value is {} bytes; the limit is {MAX_VALUE_LEN}",
                v.len()
            )));
        }
        Ok(())
    }
}

/// The typed tier's codec (bincode 2, standard config). The client must
/// encode exactly as the service decodes.
pub fn encode<T: Serialize>(v: &T) -> Vec<u8> {
    bincode::serde::encode_to_vec(v, bincode::config::standard()).expect("encoding cannot fail")
}

pub fn decode<T: serde::de::DeserializeOwned>(b: &[u8]) -> Result<T, String> {
    bincode::serde::decode_from_slice(b, bincode::config::standard())
        .map(|(v, _)| v)
        .map_err(|e| format!("cannot decode ({e}) — client and service built from different code?"))
}
