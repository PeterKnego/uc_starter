//! Argument handling that must fail fast without a cluster.
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
