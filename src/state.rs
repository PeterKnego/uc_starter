//! The replicated state and the deterministic transition function.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use uc_service::{ApplyCtx, StateMachine};

use crate::commands::{Command, Query, QueryResponse, Response};
use crate::identity::{FSM_NAME, FSM_VERSION};

/// TODO(app): replace the registry with your state.
/// BTreeMap, not HashMap: a HashMap's iteration order differs between
/// processes, so anything that iterates it (a snapshot, a projection, a
/// "list" response) would differ between replicas.
#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct State {
    pub entries: BTreeMap<String, String>,
}

#[derive(Debug, Default)]
pub struct Fsm {
    pub(crate) state: State,
    pub(crate) last_applied: Option<u64>,
}

impl Fsm {
    pub fn state(&self) -> &State {
        &self.state
    }
}

impl StateMachine for Fsm {
    const NAME: &'static str = FSM_NAME;
    const VERSION: u32 = FSM_VERSION;

    type Command = Command;
    type Response = Response;
    type Query = Query;
    type QueryResponse = QueryResponse;

    /// Runs on EVERY replica for every committed command, in log order. Same
    /// state + same command must give the same result everywhere, forever:
    /// no clock (use `ctx.time_ns`), no randomness (use `uc_service::IdGen`),
    /// no I/O, no HashMap iteration, no floats you compare.
    fn apply(&mut self, ctx: &mut ApplyCtx, cmd: Command) -> Response {
        // TODO(app): one match arm per command in src/commands.rs.
        let out = match cmd {
            Command::Put { key, value } => Response::Put { previous: self.state.entries.insert(key, value) },
            Command::Delete { key } => Response::Delete { removed: self.state.entries.remove(&key) },
        };
        self.last_applied = Some(ctx.position);
        out
    }

    /// Answers a read from local state. Linearizable vs. snapshot is the
    /// client's choice, enforced by the framework; this method is the same.
    fn query(&self, q: Query) -> QueryResponse {
        // TODO(app): one match arm per query in src/commands.rs.
        match q {
            Query::Get { key } => QueryResponse::Value(self.state.entries.get(&key).cloned()),
        }
    }

    fn last_applied(&self) -> Option<u64> {
        self.last_applied
    }
}
