# uc_starter

A [`cargo-generate`](https://github.com/cargo-generate/cargo-generate) template
for applications on [ultima_cluster](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/README.md)
(UC), with a step-by-step tutor that works with or without an AI agent.

UC is a state machine replication server: three or more nodes agree on the
order of the commands in one log, and every node applies that log to its own
copy of your state machine. Because your `apply` is deterministic, every copy
ends in the same state, so the application survives the loss of any minority of
its machines. You write the state machine and its client; UC supplies
consensus, replication, durability, snapshots and the network front door.

## Start a project

You need `cargo-generate` 0.21 or newer (`cargo install cargo-generate`), and
either Linux (x86-64 or aarch64) with [rustup](https://rustup.rs) or Docker for
the devcontainer (the path on macOS and Windows: UC nodes run on Linux only).

```bash
cargo generate --git https://github.com/PeterKnego/uc_starter
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
- **A tutor**: [`WHAT-NEXT.md`](../WHAT-NEXT.md), thirteen steps from running
  the skeleton to deploying your own app on three machines. `make next` works
  out from the repo which step you are on.
- **An agent kit**: [`AGENTS.md`](../AGENTS.md) for any coding agent; Claude
  Code also gets skills, a reviewer subagent and an edit hook that flags
  determinism hazards.
- **The operational drills**: failover, snapshots, diff-replay upgrade checks,
  pinned upgrades and deployment packaging, all through `make`.

The generated project's own README — prerequisites, make targets, ports, the
project map — is [`README.md`](../README.md) in this repository.

## License

The template itself is [MIT-0](../LICENSE): use it for anything, no attribution
required. A generated project carries no license file; choose your own.
