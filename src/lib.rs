//! LITERAL-CHECK {{not_a_placeholder}} — this line proves the generator copies
//! Rust sources verbatim (template-tests/generator.sh). Leave it.
//!
//! Module map:
//! - `identity`  — FSM name/version, app id, ports (generated)
//! - `commands`  — the wire contract: Command / Response / Query / QueryResponse
//! - `state`     — the replicated state and `apply` / `query`
//! - `snapshot`  — snapshot image + projection
//!
//! The two binaries are `src/bin/service.rs` and `src/bin/client.rs`.

pub mod commands;
pub mod identity;
pub mod snapshot;
pub mod state;

pub use commands::{
    Command, CommandError, MAX_KEY_LEN, MAX_VALUE_LEN, Query, QueryResponse, Response, decode,
    encode,
};
pub use state::{Fsm, State};
