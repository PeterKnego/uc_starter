#![allow(clippy::disallowed_methods)]
// Deadlines need `Instant::now`.

//! The remote client — talks to whichever `uc2-gateway` answers first over
//! `uc_remote`'s framed TCP protocol. The three things worth copying into
//! your own remote client are all in `run` below:
//!
//! 1. **Give it every gateway, not the leader's.** `--gateways` is the whole
//!    member list (or, left out, this app's local three-node default); the
//!    client dials them in order, follows the `REDIRECT` / `LEADER_CHANGED`
//!    the edge sends when it is not the leader, and re-sends across a
//!    failover on its own. There is no "point it at the leader" step here.
//! 2. **The payload is opaque bytes.** The edge never deserialises a command;
//!    it moves bytes between this process and the state machine. So the
//!    encoding is the application's contract with *itself*:
//!    `{{project-name}}-service` decodes with `app::decode`, so this encodes
//!    with `app::encode`.
//! 3. **One request, one resolution.** A ticket ends in the response or in a
//!    named error; `RETRY`, `REDIRECT` and connection loss never reach the
//!    caller. This binary waits with `Ticket::wait_timeout` rather than
//!    `Ticket::wait`, so `--timeout-secs` bounds the *process*, not just the
//!    request: a client that is stuck reconnecting-and-being-redirected (every
//!    edge answering "not me", e.g. a cluster with no leader) is still making
//!    progress from `RemoteClient`'s point of view, and a one-shot CLI must
//!    not wait for that forever.
//!
//! Exit codes: `0` success, `1` the request failed, `2` bad arguments
//! (`validate()` refusals included).

use std::process::ExitCode;
use std::time::{Duration, Instant};

use app::{Command, Query, QueryResponse, Response};
use clap::{Parser, Subcommand};
use uc_remote::{Consistency, RemoteClient, RemoteConfig, RemoteError};

#[derive(Parser)]
#[command(name = env!("CARGO_BIN_NAME"), about = "Drives the app's cluster through a uc2-gateway")]
struct Args {
    /// Every gateway's address, comma-separated: `host:port[,host:port…]`.
    /// List them all — the client dials in order and follows redirects, so
    /// this does not have to name the leader's. Defaults to this app's local
    /// three-node cluster (`app::identity::local_gateways`), offset by
    /// `$UC_PORT_OFFSET` (or 0).
    #[arg(long, value_delimiter = ',')]
    gateways: Option<Vec<String>>,
    /// Application identity. Must match the gateway's (and the node's).
    #[arg(long, default_value = app::identity::APP_ID)]
    app_id: String,
    /// Budget for the request, across re-sends and reconnects. Approximate:
    /// it is applied twice — once to the connect retry loop, once to the wait
    /// — so the worst case is ~2x this plus the one-second floor the wait
    /// keeps, and `uc_remote` itself enforces `request_timeout` only within
    /// about a sweep interval plus a connect attempt.
    #[arg(long, default_value_t = 10)]
    timeout_secs: u64,
    #[command(subcommand)]
    cmd: Sub,
}

// TODO(app): one subcommand per Command/Query in src/commands.rs.
#[derive(Subcommand)]
enum Sub {
    /// Set a key to a value; prints the previous value, if any.
    Put { key: String, value: String },
    /// Remove a key; prints the removed value, if any.
    Delete { key: String },
    /// Read a key's value.
    Get {
        key: String,
        /// Go through the cluster's read barrier — the answer reflects every
        /// write acknowledged before this call. Without it the read is served
        /// from whichever replica's gateway answered, and may be stale.
        #[arg(long)]
        linearizable: bool,
    },
}

/// Bad arguments (exit 2) vs. a failed request (exit 1). Keeping them apart
/// matters for scripting: exit 2 says "you typed it wrong", and no amount of
/// retrying will change it.
enum Fail {
    Args(String),
    Run(String),
}

fn dec<T: serde::de::DeserializeOwned>(b: &[u8]) -> Result<T, Fail> {
    app::decode(b).map_err(Fail::Run)
}

fn opt(o: &Option<String>) -> String {
    match o {
        Some(v) => format!("{v:?}"),
        None => "none".to_string(),
    }
}

fn gateways(args: &Args) -> Vec<String> {
    args.gateways.clone().unwrap_or_else(|| {
        let offset = std::env::var("UC_PORT_OFFSET")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        app::identity::local_gateways(offset)
    })
}

/// Connect, retrying while the deadline holds: a cluster that is still
/// electing, or gateways that have not bound their listener yet, are a
/// *timing* condition, not a configuration error. A `Config` refusal is not
/// retried — it can never start working.
fn connect(args: &Args, members: &[String], deadline: Instant) -> Result<RemoteClient, Fail> {
    let cfg = RemoteConfig {
        app_id: args.app_id.clone(),
        members: members.to_vec(),
        request_timeout: Duration::from_secs(args.timeout_secs),
        // Left at its default `true`: the service runs `Sessioned`, so a
        // re-send is answered `replayed`, never applied twice.
        ..Default::default()
    };
    loop {
        match RemoteClient::connect(cfg.clone()) {
            Ok(c) => return Ok(c),
            Err(RemoteError::Config(m)) => return Err(Fail::Args(m)),
            Err(e) => {
                if Instant::now() >= deadline {
                    return Err(Fail::Run(format!("cannot reach any gateway: {e}")));
                }
                std::thread::sleep(Duration::from_millis(100));
            }
        }
    }
}

/// What is left of the `--timeout-secs` budget, floored at a second so a
/// request that only just got a connection still gets a chance to resolve.
fn remaining(deadline: Instant) -> Duration {
    deadline
        .saturating_duration_since(Instant::now())
        .max(Duration::from_secs(1))
}

fn run(args: &Args) -> Result<(), Fail> {
    let members = gateways(args);
    for g in &members {
        if g.trim().is_empty() || !g.contains(':') {
            return Err(Fail::Args(format!(
                "--gateways entry {g:?} is not a host:port address"
            )));
        }
    }
    if args.timeout_secs == 0 {
        return Err(Fail::Args(
            "--timeout-secs must be greater than zero".into(),
        ));
    }

    // Build and validate the command BEFORE dialing anything: an oversize
    // key/value is a configuration error, not something a retry could fix,
    // and it must be refused without ever touching the network.
    let command = match &args.cmd {
        Sub::Put { key, value } => Some(Command::Put {
            key: key.clone(),
            value: value.clone(),
        }),
        Sub::Delete { key } => Some(Command::Delete { key: key.clone() }),
        Sub::Get { .. } => None,
    };
    if let Some(c) = &command {
        c.validate().map_err(|e| Fail::Args(e.to_string()))?;
    }

    let deadline = Instant::now() + Duration::from_secs(args.timeout_secs);
    let client = connect(args, &members, deadline)?;

    let result = match &args.cmd {
        Sub::Put { .. } | Sub::Delete { .. } => {
            submit(&client, command.as_ref().expect("built above"), deadline)
        }
        Sub::Get { key, linearizable } => query(&client, key, *linearizable, deadline),
    };
    // Shut the client's reader thread down before returning either way — the
    // process is about to exit, but a reference client should still show the
    // explicit close rather than relying on it.
    client.shutdown();
    result
}

fn submit(client: &RemoteClient, cmd: &Command, deadline: Instant) -> Result<(), Fail> {
    let ticket = client
        .submit(&app::encode(cmd))
        .map_err(|e| Fail::Run(e.to_string()))?;
    let resp = ticket
        .wait_timeout(remaining(deadline))
        .map_err(|e| Fail::Run(e.to_string()))?;
    let response: Response = dec(&resp.bytes)?;
    match response {
        Response::Put { previous } => {
            println!(
                "ok previous={} position={} replayed={}",
                opt(&previous),
                resp.position,
                resp.replayed
            )
        }
        Response::Delete { removed } => {
            println!(
                "ok removed={} position={} replayed={}",
                opt(&removed),
                resp.position,
                resp.replayed
            )
        }
    }
    Ok(())
}

fn query(
    client: &RemoteClient,
    key: &str,
    linearizable: bool,
    deadline: Instant,
) -> Result<(), Fail> {
    let consistency = if linearizable {
        Consistency::Linearizable
    } else {
        Consistency::Snapshot
    };
    let ticket = client
        .query(
            &app::encode(&Query::Get {
                key: key.to_string(),
            }),
            consistency,
        )
        .map_err(|e| Fail::Run(e.to_string()))?;
    let resp = ticket
        .wait_timeout(remaining(deadline))
        .map_err(|e| Fail::Run(e.to_string()))?;
    let answer: QueryResponse = dec(&resp.bytes)?;
    let QueryResponse::Value(v) = answer;
    println!("value={}", opt(&v));
    Ok(())
}

fn main() -> ExitCode {
    let args = Args::parse();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(Fail::Run(m)) => {
            eprintln!("{}: {m}", env!("CARGO_BIN_NAME"));
            ExitCode::from(1)
        }
        Err(Fail::Args(m)) => {
            eprintln!("{}: {m}", env!("CARGO_BIN_NAME"));
            ExitCode::from(2)
        }
    }
}
