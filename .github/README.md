# Start your own project on ultima_cluster

This is a starter project to help you write high-performance clustered
applications on [ultima_cluster (UC)](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/README.md).

[State Machine Replication (SMR)](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/state-machine-replication-explained.md)
is an architectural pattern used by the largest distributed systems in the
world: financial exchanges, distributed databases, etc. It's a complex
technology that requires a special approach to writing applications to achieve
high performance, correctness and resiliency. This is where
[ultima_cluster](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/README.md)
steps in: it makes this process much easier for developers and operators.

To make it even easier: this starter project comes preconfigured with all documentation and step-by-step AI tutor. 

## Start a project

You need `cargo-generate` 0.21 or newer (`cargo install cargo-generate`), and
either Linux (x86-64 or aarch64) with [rustup](https://rustup.rs) or Docker for
the devcontainer (the path on macOS and Windows: UC nodes run on Linux only).

```bash
cargo generate --git https://github.com/PeterKnego/uc_starter   # add --tag v2.13.0 to pin a UC release
cd <your-project>
make bins up demo
make next
```

This downloads and verifies the UC binaries, starts a local three-node cluster
running the skeleton app, drives it through the gateways until it prints
`PASS`, and names your first step of the tutor.

## What you get

- **A working skeleton**: a small key-value registry with its service, client,
  unit, property and three-node cluster tests.
- **A tutor**: [`WHAT-NEXT.md`](../WHAT-NEXT.md), fourteen steps, from running
  the skeleton to testing your own app on three cloud hosts. `make next` works
  out from the repo which step you are on.
- **An agent kit**: [`AGENTS.md`](../AGENTS.md) for any coding agent; Claude
  Code also gets skills, a reviewer subagent and an edit hook that flags
  determinism hazards.
- **The operational drills**: failover, snapshots, diff-replay upgrade checks,
  pinned upgrades and deployment packaging, all through `make`.
- **Cloud in one command**: `make cloud-oneshot` puts the app on three Hetzner, AWS or GCP hosts, tests a real host failover, and tears them down — or ask your agent, which asks before spending money.

The generated project's own README — prerequisites, make targets, ports, the
project map — is [`README.md`](../README.md) in this repository.

## License

The template itself is [MIT-0](../LICENSE): use it for anything, no attribution
required. A generated project carries no license file; choose your own.
