// LITERAL-CHECK {{not_a_placeholder}} — proves the generator copies Rust
// sources verbatim (the template's generator test). Harmless; leave it.
//! Three nodes, three services, three gateways; the demo; a leader kill; the
//! demo again. `cargo test --release --features cluster-tests --test cluster`.
#![cfg(feature = "cluster-tests")]
use std::path::{Path, PathBuf};
use std::process::Command;

fn root() -> PathBuf {
    // CARGO_TARGET_TMPDIR is under target/, i.e. real disk, never /tmp.
    Path::new(env!("CARGO_TARGET_TMPDIR")).join("cluster-test")
}

fn sh(args: &[&str]) {
    let dir = env!("CARGO_MANIFEST_DIR");
    let status = Command::new(format!("{dir}/{}", args[0]))
        .args(&args[1..])
        .current_dir(dir)
        .env("UC_ROOT", root())
        .env("UC_PORT_OFFSET", "10") // never collide with the developer's own cluster
        .env("UC_NO_STAMP", "1") // tests must not move the tutor
        .status()
        .unwrap();
    assert!(status.success(), "{args:?} failed");
}

struct Down;
impl Drop for Down {
    fn drop(&mut self) {
        let _ = Command::new(format!("{}/scripts/cluster.sh", env!("CARGO_MANIFEST_DIR")))
            .arg("down")
            .env("UC_ROOT", root())
            .env("UC_PORT_OFFSET", "10")
            .status();
    }
}

#[test]
fn demo_survives_a_leader_kill() {
    let _down = Down;
    sh(&["scripts/cluster.sh", "up", "--fresh"]);
    sh(&["scripts/demo.sh"]);
    sh(&["scripts/kill-leader.sh"]);
    sh(&["scripts/demo.sh"]);
}

#[test]
fn snapshot_drill_and_observe() {
    let _down = Down;
    sh(&["scripts/cluster.sh", "up", "--fresh"]);
    sh(&["scripts/snapshot-drill.sh"]);
    sh(&["scripts/observe.sh"]);
}

#[test]
fn bench_reports_throughput() {
    let _down = Down;
    sh(&["scripts/cluster.sh", "up", "--fresh"]);
    // target/release/deps/cluster-<hash> → target/release/<client>
    let exe = std::env::current_exe().unwrap();
    let client = exe
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join(env!("CARGO_PKG_NAME"));
    let out = Command::new(client)
        .args(["bench", "--duration-secs", "2", "--inflight", "8"])
        .env("UC_PORT_OFFSET", "10")
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let text = String::from_utf8_lossy(&out.stdout);
    let field = |prefix: &str| -> u64 {
        text.split_whitespace()
            .find_map(|w| w.strip_prefix(prefix))
            .and_then(|v| v.parse().ok())
            .unwrap_or(0)
    };
    let ops = field("ops=");
    assert!(ops > 0, "{text}");
    let p50 = field("p50_us=");
    let p90 = field("p90_us=");
    let p99 = field("p99_us=");
    let max = field("max_us=");
    assert!(p50 <= p90 && p90 <= p99 && p99 <= max, "{text}");
    assert!(text.contains("inflight=8"), "{text}");
}
