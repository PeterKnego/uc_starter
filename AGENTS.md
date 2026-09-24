# AGENTS.md

Instructions for any coding agent working in this repository.

## 1. What this is

An application on ultima_cluster (UC), a State Machine Replication server,
generated from the `uc_starter` template. The UC release it builds against is
in `UC_VERSION`; the exact crate pins in `Cargo.toml` match it. UC runs your
state machine as one replica per node: every replica applies the same
committed commands in the same order, so `apply` must be deterministic.

## 2. Map

| path | what it is |
|---|---|
| `UC_VERSION`, `uc-app.env` | the one UC pin; the app name, `APP_ID`, FSM name and base port the scripts read |
| `Cargo.toml`, `rust-toolchain.toml`, `clippy.toml` | the build, the toolchain pin, the determinism bans clippy enforces |
| `src/identity.rs` | `FSM_NAME`, `FSM_VERSION`, `APP_ID`, `BASE_PORT` |
| `src/commands.rs` | wire types (`Command`, `Response`, `Query`, `QueryResponse`) and `Command::validate` |
| `src/state.rs` | `State`, `Fsm`, `apply` / `query` |
| `src/snapshot.rs` | the snapshot image (`IMAGE_VERSION`) and `project()`, the text diff replay compares |
| `src/lib.rs` | the module map |
| `src/bin/service.rs` | `<app>-service`: attaches to a node; `replay` / `project` for diff replay |
| `src/bin/client.rs` | `<app>`: the remote client, through the gateways |
| `tests/` | `state.rs`, `snapshot.rs` (unit), `determinism.rs` (property), `cli.rs`, `cluster.rs` (3-node smoke) |
| `scripts/` | cluster, tutor, drills, packaging; reach them through `make` |
| `Makefile` | the one entry point |
| `upgrade/intent.toml.example` | the diff-replay declaration starter |
| `WHAT-NEXT.md` | the tutor path: 13 steps, each with Goal, Why, Do it yourself, Ask the agent, Done when, Common mistakes |
| `docs/` | `app-design.md` (the spec the code is held to), `concepts.md`, `how-to/`, `troubleshooting.md`, `ai-engineering.md` |
| `.uc/` | downloaded UC binaries, tools and machine-local proof stamps — generated, never edited |

## 3. Commands

`make help` lists every target. The ones you use most:

| command | does |
|---|---|
| `scripts/next.sh --json` | which step the developer is on, computed from the repo |
| `make check` | tests + fmt + clippy + MSRV clippy + determinism grep; records the proof |
| `make up` / `make down` | start / stop the local 3-node cluster (`make up FRESH=1` wipes its state) |
| `make restart-services` | rebuild and restart only the service on every node |
| `make demo` | drive the cluster through the gateways; prints `PASS` |
| `make status` | `uc2ctl status` on every node |
| `make corpus` / `make upgrade-check` | diff-replay corpus (before a change) / replay it through old vs new |
| `make done STEP=<id>` / `make skip STEP=<id>` | record a step the repo cannot show / a deliberate skip (ids: `scripts/next.sh --list`) |

Start and stop cluster processes only through `make up`, `make down` and
`make restart-services` (or `scripts/cluster.sh`); they enforce the start
order (nodes, then a serving leader, then services, then gateways).

## 4. Hard rules

1. **Determinism.** `apply`, `on_timer`, `freeze` and the snapshot code give
   the same result on every replica, forever. Use the substitutes:
   - wall clock or `Instant::now` → `ctx.time_ns`
   - RNG, random UUIDs → `ctx.ids()` (`uc_service::IdGen`)
   - `HashMap` / `HashSet` → `BTreeMap` / `BTreeSet`
   - floats → integers (fixed-point)
   - plain `+`, `-`, `*` → `checked_*` (answer an error response) or `wrapping_*`
   - `unwrap`, indexing, panics on input → an error response
   - file, network, environment, process access → put the value in the command, or do the side effect after commit on the leader
2. **Append-only enums.** New `Command`, `Response`, `Query`, `QueryResponse`
   variants go at the END; fields are never reordered or renamed. The variant
   index is the wire tag, and a mid-enum insert makes old log entries decode
   as a different command with no error.
3. **`validate()` for every size-bearing field.** Every string, byte vector or
   collection in a `Command` has a `MAX_*` limit checked in
   `Command::validate`; the largest encoded command stays under 1296 B.
4. **Any change to what `apply` or `query` returns or stores → bump
   `FSM_VERSION` in `src/identity.rs` and run the Step-12 flow**
   (`make corpus` before the change, `make upgrade-check` after it). A new
   command variant is never sent by any client until every service runs the
   new build; an earlier commit fail-stops every old service
   (`corrupt committed frame (fail-stop)`).
5. **Never run `uc2ctl upgrade pin`, `make upgrade-drill`, or any command with
   `UC_CONFIRM_PIN=yes` without the developer's explicit go-ahead in this
   conversation. A pin is a one-way door:** there is no unpin, and the only
   rollback is the backup taken before it, restored on every node.
6. **Cluster state lives on a real disk**, never under `/tmp` or `/dev/shm`
   (RAM-backed: `fsync` does nothing and the nodes refuse it).
7. **`.uc/` is generated.** Change it only through `make bins`,
   `make diffreplay` and the scripts.

## 5. Evidence

A step or task is done only when its check passes. Show the command you ran
and its output. When you have not run the check, say "not verified".
If `scripts/next.sh` and your memory of the conversation disagree,
`scripts/next.sh` is right.

## 6. The tutor protocol

When the developer asks "what next?", "where am I?", "help me continue" or
similar:

1. Run `scripts/next.sh --json`. Never infer the step from memory or chat.
2. Read that step (`"step": N`) in `WHAT-NEXT.md`. Teach its **Why** in at
   most 6 sentences, with its link. If `part1_just_completed` is true, first
   congratulate: Part 1 is complete. Mention every `detail` line, including
   `note: … is stale` lines about earlier steps.
3. Ask exactly: "Do you want to do this yourself (I'll guide and review), or shall I do it?"
4. a. *Guide*: give the next single action from **Do it yourself**, wait for
      the developer, review their diff against the step's **Common mistakes**,
      repeat.
   b. *Do it*: make the change, then walk the diff hunk by hunk, naming the UC
      concept each hunk serves.
5. Run the step's check (the command in **Done when**, then
   `scripts/next.sh --json`) and show its output. Only then say the step is
   done and offer the next one.

Step 3 (`concepts`): ask the three check questions from `WHAT-NEXT.md`
Step 3, one at a time, and discuss each answer. Run
`make done STEP=concepts` only after the developer has answered all three.

Run `make skip STEP=<id>` only when the developer asked to skip that step.
`status` is `todo`, `stale` (proven once, but the code changed since: re-run
the check) or `complete` (id `done`: every step is finished).

## 7. Upstream docs

Link UC documentation only through the pinned
`https://github.com/PeterKnego/ultima_cluster/blob/v<UC_VERSION>/…` URLs, as
`docs/concepts.md` and `WHAT-NEXT.md` do. Never link `main`: it describes a
different release.
