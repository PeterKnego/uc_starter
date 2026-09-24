//! Who this application is. Generated once by `cargo generate`; the only Rust
//! file with template substitution.

/// The state machine's identity (`StateMachine::NAME`). Changing it after a
/// cluster has run makes every node refuse this service by name.
pub const FSM_NAME: &str = "{{fsm_name}}";

/// The semantic version of what `apply` does. Bump it on ANY behaviour
/// change and run `make upgrade-check` (WHAT-NEXT.md, Step 12).
pub const FSM_VERSION: u32 = uc_protocol::identity::pack_version(1, 0, 0);

/// The cluster identity every process checks at attach.
pub const APP_ID: &str = "{{app_id}}";

/// Nodes UDP `BASE_PORT..+2`, gateways TCP `+100..+102`, metrics `+200..+202`.
pub const BASE_PORT: u16 = {{base_port}};

/// The local cluster's gateways, for the client's default `--gateways`.
pub fn local_gateways(offset: u16) -> Vec<String> {
    (0..3)
        .map(|i| format!("127.0.0.1:{}", BASE_PORT + offset + 100 + i))
        .collect()
}
