#![allow(clippy::disallowed_methods)]
// The service's supervision loop legitimately reads the clock; apply does not.

//! The service half: runs `Sessioned<Fsm>` against a local `uc2-node`.
//!
//! Shape copied from `docs/how-to/write-a-service-binary.md` and
//! `examples/counter/src/bin/counter-service.rs`: wait for the control page,
//! attach, supervise the apply agent with `is_alive`, stop on SIGTERM.
//!
//! Two things differ from the counter:
//! - the state machine is wrapped in `uc_service::Sessioned`, so the
//!   gateway's session envelope must be ON (`[session] envelope = true`,
//!   the default) — a re-sent write is then answered `replayed`, not applied
//!   twice;
//! - it starts with `start_with_snapshots()`, which is what lets
//!   `uc2ctl snapshot` and `[purge]` bound the journal.
//!
//! Exit codes: 0 clean stop, 1 attach failed or the apply agent fail-stopped
//! (restart it), 2 bad arguments.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use app::{
    Fsm,
    identity::{APP_ID, FSM_NAME},
};
use clap::Parser;
use uc_service::{ServiceBuilder, ServiceConfig, SessionConfig, Sessioned, StateMachine};

#[derive(Parser)]
#[command(
    name = env!("CARGO_BIN_NAME"),
    about = "Runs the app's state machine against a local uc2-node"
)]
struct Args {
    /// The instance directory of the node to attach to.
    #[arg(long)]
    instance_dir: Option<PathBuf>,
    /// Application identity; must match the node's and the gateway's.
    #[arg(long, default_value = APP_ID)]
    app_id: String,
    /// How long to wait for the node's control page to appear.
    #[arg(long, default_value_t = 30)]
    wait_secs: u64,
    #[command(subcommand)]
    cmd: Option<Sub>,
}

/// Diff replay (uc_diffreplay README): the app-binary contract.
#[derive(clap::Subcommand)]
enum Sub {
    /// Replay a corpus through this FSM in-process and write the trace.
    Replay {
        #[arg(long)]
        corpus: PathBuf,
        #[arg(long)]
        out: PathBuf,
        #[arg(long)]
        from_genesis: bool,
    },
    /// Install an artifact and print its canonical projection.
    Project {
        #[arg(long)]
        artifact: PathBuf,
        #[arg(long)]
        position: u64,
    },
}

fn uc_service_version_string() -> String {
    let (a, b, c) = uc_protocol::identity::unpack_version(<Fsm as StateMachine>::VERSION);
    format!("{a}.{b}.{c}")
}

fn main() -> anyhow::Result<()> {
    let args = Args::parse();
    // The same wrapper stack the live service runs — the envelope is part of
    // the behaviour being replayed.
    let sm = || Sessioned::new(Fsm::default(), SessionConfig::default());
    match args.cmd {
        Some(Sub::Replay {
            corpus,
            out,
            from_genesis,
        }) => {
            return uc_diffreplay::drive::run_replay_cli(sm(), &corpus, &out, from_genesis);
        }
        Some(Sub::Project { artifact, position }) => {
            print!(
                "{}",
                uc_diffreplay::drive::project_artifact(sm(), &artifact, position)?
            );
            return Ok(());
        }
        None => {}
    }
    anyhow::ensure!(
        args.instance_dir.is_some(),
        "--instance-dir is required to attach"
    );
    let instance_dir = args.instance_dir.unwrap();

    // The node creates the control page on startup; under a supervisor we
    // may be launched first.
    let cnc = instance_dir.join("cnc2.dat");
    let deadline = Instant::now() + Duration::from_secs(args.wait_secs);
    while !cnc.exists() {
        anyhow::ensure!(
            Instant::now() < deadline,
            "no node at {} after {}s (is uc2-node running?)",
            instance_dir.display(),
            args.wait_secs
        );
        std::thread::sleep(Duration::from_millis(20));
    }

    // SessionConfig is part of the replicated contract: every replica must
    // run the same values (state-machine-contract.md § Sessioned). Defaults
    // everywhere, deliberately.
    let sm = Sessioned::new(Fsm::default(), SessionConfig::default());
    let cfg = ServiceConfig::new(instance_dir.clone(), args.app_id.clone());
    let service = ServiceBuilder::new(cfg, sm).start_with_snapshots()?;
    eprintln!(
        "{}: attached fsm={FSM_NAME:?} version={} row={} epoch={} instance_dir={}",
        env!("CARGO_BIN_NAME"),
        uc_service_version_string(),
        service.service_id(),
        service.epoch(),
        instance_dir.display()
    );

    let stop = Arc::new(AtomicBool::new(false));
    for sig in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
        signal_hook::flag::register(sig, Arc::clone(&stop))?;
    }

    while !stop.load(Ordering::Relaxed) {
        // A fail-stopped apply thread must not look like a healthy service:
        // exit non-zero so a supervisor restarts us and we reconstruct.
        if !service.is_alive() {
            eprintln!(
                "{}: apply agent died; exiting for restart",
                env!("CARGO_BIN_NAME")
            );
            return Err(anyhow::anyhow!("apply agent fail-stopped"));
        }
        std::thread::sleep(Duration::from_millis(100));
    }

    eprintln!("{}: signalled, stopping", env!("CARGO_BIN_NAME"));
    service.stop();
    Ok(())
}
