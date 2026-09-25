//! Argument handling that must fail fast without a cluster.
// TODO(app): rewrite these for your client's subcommands; each must fail for the reason it names (WHAT-NEXT.md, Step 7).
use std::path::PathBuf;
use std::process::Command;

fn bin(suffix: &str) -> PathBuf {
    let exe = std::env::current_exe().unwrap(); // target/<profile>/deps/cli-<hash>
    let dir = exe.parent().unwrap().parent().unwrap();
    dir.join(format!("{}{suffix}", env!("CARGO_PKG_NAME")))
}

#[test]
fn oversize_value_is_refused_before_connecting() {
    let out = Command::new(bin(""))
        .args([
            "--gateways",
            "127.0.0.1:1",
            "put",
            "k",
            &"v".repeat(app::MAX_VALUE_LEN + 1),
        ])
        .output()
        .unwrap();
    assert_eq!(
        out.status.code(),
        Some(2),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(String::from_utf8_lossy(&out.stderr).contains("limit is"));
}

#[test]
fn bad_gateway_address_is_exit_2() {
    let out = Command::new(bin(""))
        .args(["--gateways", "nocolon", "get", "k"])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(2));
}

#[test]
fn service_without_instance_dir_is_refused() {
    let out = Command::new(bin("-service")).output().unwrap();
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("--instance-dir"));
}

#[test]
// The 5 s deadline is test harness timing, not state-machine code.
#[allow(clippy::disallowed_methods)]
fn service_exits_cleanly_on_sigterm_before_attach() {
    // No node is running, so the service is waiting for one when the signal
    // lands. The stop flag must already be registered: without it the default
    // disposition kills the process (exit by signal 15), never a clean exit.
    let dir = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("sigterm-before-attach");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let mut svc = Command::new(bin("-service"))
        .args(["--wait-secs", "30", "--instance-dir"])
        .arg(&dir)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .unwrap();
    std::thread::sleep(std::time::Duration::from_millis(300));
    let sent = Command::new("kill")
        .args(["-TERM", &svc.id().to_string()])
        .status()
        .unwrap();
    assert!(sent.success(), "could not send SIGTERM");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let status = loop {
        if let Some(s) = svc.try_wait().unwrap() {
            break s;
        }
        if std::time::Instant::now() >= deadline {
            let _ = svc.kill();
            panic!("service did not exit within 5 s of SIGTERM while waiting for its node");
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    };
    assert!(
        status.success(),
        "SIGTERM before attach must exit 0, got {status:?}"
    );
}
