# Clean-room walkthrough — 2026-09-24

Task 14 of the uc_starter plan. A developer who has never seen UC (played by
the controller's subagent) drives a fresh Claude Code process — the **tutor** —
through Part 1, using only the generated project's own files.

## Setup

- Generated with `template-tests/gen.sh $HOME/scratch/uc_starter-cleanroom stock-app stock stock 8400`
  from uc_starter `main` at `e1c0758`; project at `~/scratch/uc_starter-cleanroom/stock-app`,
  baseline commit `init`. `make bins` NOT pre-run.
- `.claude/settings.json` as generated, plus `permissions.deny`:
  `Read(//home/claude/ultima/**)`, `Read(//home/claude/.claude/projects/**)`.
- Tutor launched from the project dir:
  `claude -p "<msg>" [--resume <sid>] --output-format json --permission-mode acceptEdits --allowedTools Bash Read Edit Write Glob Grep`
  (no permission bypass). One session, `e8c03c60-1d8a-4c8a-97d9-20083a4db73a`, 38 turns.
- Developer protocol: every step opened with only "what next?"; step 1 (unassigned) and
  steps 2, 4, 6, 8 → "you do it and explain"; steps 3, 5, 7, 9 → "I'll do it — guide me"
  (the developer made every edit and ran every command itself).
- App idea, given only when asked (turn 14): the stock ledger (`Receive`/`Ship`/`OnHand`).

## Result

`scripts/next.sh` (run by the developer after turn 37) prints
**"Part 1 complete — your app runs on a three-node cluster."** All clusters stopped
with `make down` afterwards; no uc2-* / stock-app processes remain.

## Per-step record

| step (id) | turns | mode | next.sh at START | check at END (before "done") | guide-or-do asked | pin / skip / done |
|---|---|---|---|---|---|---|
| 1 env | 1–2 | do | yes (`next` skill → `scripts/next.sh --json`) | `uc2-node --version`, `make next`, `next.sh --json` | yes | none |
| 2 skeleton | 3–4 | do | yes | `make demo` PASS, `make status`, `next.sh --json` | yes | none |
| 3 concepts | 5–11 | guide | yes | `make done STEP=concepts` + `next.sh --json` | yes | `make done STEP=concepts` — not requested by the developer, but it is the step's own "Done when" and the tutor announced it in turn 5 |
| 4 design | 12–14 | do | yes | `grep -c TODO`, `make todo`, `next.sh --json` | yes | none |
| 5 commands | 15–21 | guide | yes | `grep TODO`, `cargo check`, `next.sh --json`, `determinism-reviewer` subagent | yes | none |
| 6 state | 22–23 | do | yes | `cargo test --lib` (0 tests), `lint-determinism.sh --all`, clippy, fmt, `next.sh --json`, `determinism-reviewer` subagent | yes | none |
| 7 tests | 24–31 | guide | yes | `next.sh --json` (verifies the hash-stamped `make check` proof the developer ran) + `cargo fmt --check`; did not re-run `make check` itself | yes | none |
| 8 client | 32–33 | do | yes | `make check`, `make up FRESH=1`, `make demo` ×2 PASS, `next.sh --json` | yes | none |
| 9 failover | 34–38 | guide | yes | `next.sh --json` → `part1_complete: true`, then walked the developer through `make status` | yes | none |

No `upgrade pin`, `UC_CONFIRM_PIN`, `upgrade-drill`, `uc2ctl` or `make skip` was run in
any turn (checked against the session's tool-call log).

## Per-turn notes

- **T1** "what next?" → loaded the `next` skill, ran `next.sh --json`, grepped Step 1; explained the step, asked guide-or-do.
- **T2** do → `uname`/`cargo`/`cosign` probe, `make bins` (checksum + cosign OK), `uc2-node --version`, `make next`, `next.sh --json`. Clear explanation.
- **T3** → `next.sh --json`, read WHAT-NEXT; asked.
- **T4** do → `make up`, `make demo` PASS, `make status`, `next.sh`. Flagged honestly that `reported_durable` on followers was an inference.
- **T5** → `next.sh --json`, read WHAT-NEXT; asked; promised `make done` only after three answers.
- **T6–T7** guide → pointed at the public explainer, then at `src/state.rs` with four things to find.
- **T8** developer asked "IdGen or ctx.ids()?" (state.rs:43 comment vs WHAT-NEXT) → tutor read the pinned `uc_service-2.13.0` source under `~/.cargo/registry/src` to answer; asked Q1.
- **T9** Q1 right → expanded (replay days later). Asked Q2.
- **T10** Q2 wrong (confused with log replay) → clear correction. Asked Q3.
- **T11** Q3 wrong ("entry 1, 2, 3") → correction only as a table row; immediately ran `make done STEP=concepts` + `next.sh`. Guessed the Step 4 doc path without checking (said so).
- **T12** → `next.sh --json` + Step 4 text; asked.
- **T13** do → read `docs/app-design.md`, interviewed the developer (5 questions) before writing.
- **T14** idea given → wrote the design doc, measured bincode sizes with a throwaway crate in `mktemp -d` (outside the project), check `grep TODO` / `make todo` / `next.sh`. Warned that Step 5 needs `make up FRESH=1`.
- **T15** → `next.sh --json`; asked; said it would run the determinism reviewer.
- **T16** guide → asked "has any other cluster run this app?" first; loaded `add-command` skill; enum instructions.
- **T17–T20** reviewed each developer edit (enums; `validate()` + `lib.rs`; `state.rs` stubs; `client.rs`), ran `cargo check`/`cargo fmt --check`, one action at a time.
- **T21** → `grep TODO`, `cargo check`, `next.sh --json`, `determinism-reviewer` subagent (no hazards). Learned from the subagent that `tests/` no longer compiles.
- **T22** → `next.sh --json`; asked; named the check (`cargo test --lib` + lint).
- **T23** do → implemented state/apply/query/project; check (see table); wrote and deleted a throwaway behaviour test; subagent review.
- **T24** → `next.sh --json` + Step 7 text; asked.
- **T25–T30** guide → `arb_command` (then a throwaway tally test showed 45 % `Invalid`; suggested weighting), `tests/state.rs` (tutor planted 3 mutations to prove the tests catch bugs, backup at `/home/claude/state.rs.bak`, removed), `tests/snapshot.rs`, `tests/cli.rs` (caught that `get` would now fail as an unknown subcommand → a test passing for the wrong reason). Developer's `make check` failed on `cargo fmt --check`; tutor explained the hook only formats agent edits.
- **T31** → `next.sh --json` (stamp matched), `cargo fmt --check`.
- **T32** → `next.sh --json` + Step 8 text; asked.
- **T33** do → exit code 3 for a rejected ship, re-runnable `demo.sh`, `make check`, `make down`, `make up FRESH=1`, `make demo` ×2 PASS, `next.sh`. Found that `snapshot-drill.sh` and `upgrade-drill.sh` still use skeleton `put`/`get` with no `TODO(app)` marker.
- **T34** → `next.sh --json` + Step 9 text; asked.
- **T35–T36** guide → baseline `make status`, predictions (leader, term, commit).
- **T37** developer pasted `make kill-leader` output → `next.sh --json` shows `part1_complete: true`; explained the 32-byte gap at 896→928 (marked as inference).
- **T38** developer reported `term=6` → tutor grepped node logs, said terms 2–5 were leaderless rounds and the cause is **unexplained** from info-level logs; declared Part 1 complete; warned about the Part 2 drill scripts.

## Friction (ranked by harm to a real developer)

1. **Part 2 drill scripts are silently broken by Part 1.** `scripts/snapshot-drill.sh` (lines 17, 46) and `scripts/upgrade-drill.sh` (lines 40, 79, 103) call the client's skeleton `put`/`get`, carry no `TODO(app)` marker, so `next.sh` never lists them; Step 10 and Step 12 will fail for every developer whose app is not a key-value registry. Found by the tutor, not by the template.
2. **No test safety net from Step 5 to Step 7.** Replacing the commands in Step 5 breaks compilation of every file in `tests/`, so `cargo test` / `make check` stay red through Step 6; Step 6's check `cargo test --lib` runs **0 tests** and proves only that the crate compiles. The real logic (Step 6) is written with no behavioural check at all unless the tutor improvises one (it did, then deleted it).
3. **The concepts step records "understood" on wrong answers.** The developer got 2 of 3 check questions wrong; the tutor corrected Q2 well, reduced Q3's correction to a table row, never re-asked, and ran `make done STEP=concepts` in the same turn. Nothing in the protocol requires a correct answer before `make done`.
4. **`make check` fails on the developer's own edits for formatting** (the PostToolUse hook formats only the agent's edits). WHAT-NEXT does not tell a guide-mode developer to run `cargo fmt`; the tutor explained it after the failure.
5. **`make check` gives no success line.** Its last visible output is the `scripts/lint-determinism.sh --all` command; a developer cannot tell it passed (or that the proof was stamped) without `echo $?` or `next.sh`.
6. **Template-test residue in the generated project:** `src/lib.rs` begins with `LITERAL-CHECK {{not_a_placeholder}} — this line proves the generator copies Rust sources verbatim (template-tests/generator.sh). Leave it.` — meaningless and confusing to a developer (template-tests/ is not in their project).
7. **`src/state.rs:43` says "use `uc_service::IdGen`"** while WHAT-NEXT/AGENTS say `ctx.ids()`; the tutor had to read the crate source in `~/.cargo/registry` to reconcile them.
8. **The tutor writes scratch outside the project** (`mktemp -d` cargo crate in /tmp in T14; `/home/claude/state.rs.bak` in T28, both cleaned up). Harmless here, but AGENTS.md gives no rule to keep scratch inside the project.
9. **`term=6` after one `make kill-leader`** (terms 2–5 leaderless). The tutor honestly called it unexplained; a developer seeing it with no explanation may think something is wrong. Not a template defect — possibly worth a UC-side look.
10. `Cargo.lock` is untracked after the first build (not in the generated baseline, not ignored) while `make lint` uses `--locked`; nothing tells the developer to commit it. Minor.

What went well (for balance): the tutor ran `next.sh` at the start of every step and asked guide-or-do every time; interviewed before designing; asked "has any real cluster run this?" before replacing wire enums; verified test quality by planting mutations and tallying generator coverage; caught a CLI test that would pass for the wrong reason; was explicit every time something was inferred rather than checked; never touched the pin, `uc2ctl` or `make skip`.

## Clean-room audit

`scripts/dogfood_audit.py` (ultima_cluster) over the tutor session + both subagent transcripts
(3 transcripts, 112 tool uses). The unmodified tool reports **VOID**, but every FORBIDDEN hit is
either the sandbox itself or the published crate source:

- 25 hits are paths **inside the sandbox**, flagged because the tool's `r"/scratch(/|$)"` pattern
  (meant for the maintainer's rustdoc scratch) matches the mandated sandbox location
  `~/scratch/uc_starter-cleanroom`, and its `r"/\.claude/skills(/|$)"` pattern matches the
  project's own `.claude/skills/determinism-review/SKILL.md`.
- 2 hits are `~/.cargo/registry/src/.../uc_service-2.13.0/src` — the published `uc_service`
  crate, which cargo downloaded for this project; benign per the task brief (a real developer has it).

Re-run with only the `/scratch` pattern narrowed to exclude the sandbox: still VOID on those two
registry reads + the skills false positive. Re-run additionally treating `~/.cargo/registry/src`
as benign: only the `.claude/skills` in-sandbox false positive remains. Remaining OUTSIDE paths,
judged: `~/.uc-starter/stock-app/logs` (the project's own cluster root — benign),
`/home/claude/state.rs.bak` (a file the tutor itself created and deleted — benign, hygiene note),
the rest are regex/sed tokens (`/---`, `/fn`, `/p`, `//g`, `/if`, ...). A grep of all three
transcripts finds **zero** references to `/ultima/` and none to `~/.claude/projects`.
Judged verdict: **JUDGE → all benign** (no forbidden read attempted or succeeded).

## Full transcript (developer messages and tutor replies, verbatim)

## Turn 1

**Developer:** what next?

**Tutor** (turns=5, denials=0):

You're on **Step 1 of 13, Environment** (Part 1). `scripts/next.sh --json` reports `status: todo`, and one thing is missing:

- `ultima_cluster binaries missing: make bins`

**Why this step matters.** An ultima_cluster node runs only on Linux (x86-64 or aarch64). The node, your service and the local clients talk to each other through file-backed shared memory with futex wakeups. You never build UC yourself: `make bins` downloads the release named in `UC_VERSION` and checks it against that release's `SHA256SUMS` before installing anything into `.uc/bin`. If `cosign` is installed, it also checks the signature, pinned to the GitHub workflow that built the release. The checksum only proves the download is complete; the signature proves where the file came from. See [the quickstart, § 1](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/QUICKSTART.md#1-download-it-and-verify-it).

The step is done when `make next` sees three things: the host is Linux, `cargo` is on the `PATH`, and `.uc/bin/uc2-node --version` runs and names the version in `UC_VERSION`.

Do you want to do this yourself (I'll guide and review), or shall I do it?


## Turn 2

**Developer:** you do it and explain

**Tutor** (turns=4, denials=0):

Step 1 is done. `git status` stays clean because everything `make bins` wrote went into `.uc/`, which is generated and never committed. So there's no diff to walk through. Here is each check and what it covers.

**1. Host and toolchain**
```
$ uname -sm; cargo --version; command -v cosign; cat UC_VERSION
Linux x86_64
cargo 1.96.0 (30a34c682 2026-05-25)
/home/claude/.local/bin/cosign
2.13.0
```
- **Linux x86_64:** UC nodes run only on Linux, because node, service and client share file-backed memory with futex wakeups. You're on a supported host, so you don't need the devcontainer.
- **cargo:** Rust is installed. `rust-toolchain.toml` picks the exact version whenever you build in this repo.
- **cosign:** it's installed, so `make bins` could check the signature as well as the checksum.

**2. `make bins`**
```
downloading uc2-2.13.0-x86_64-unknown-linux-gnu.tar.gz
uc2-2.13.0-x86_64-unknown-linux-gnu.tar.gz: OK
signature verified (cosign)
uc2-node 2.13.0
```
- **`: OK`:** the tarball matches the release's `SHA256SUMS`, which proves the download is complete.
- **`signature verified (cosign)`:** the tarball was built by the pinned GitHub workflow. This is the check that proves where the file came from.
- **`uc2-node 2.13.0`:** matches `UC_VERSION`.

**3. What's installed in `.uc/bin`**
- `uc2-node`: the consensus, replication and durability daemon (one per node)
- `uc2-gateway`: the TCP front door for clients that can't use shared memory
- `uc2ctl`: the admin tool. It's the only thing here that can run `upgrade pin`, the one-way step that hard rule 5 guards.
- `counter-service`, `counter-remote`: the example service and client that ship with the release

**4. The check**
```
$ make next
Step 2/13 · Part 1 · Run the skeleton → WHAT-NEXT.md "Step 2"
  status: todo
  - run: make up && make demo
```
`scripts/next.sh --json` now reports `"step":2,"id":"skeleton"`, which means Step 1 is proven.

> **Insight:** `UC_VERSION` pins the UC release in one place. `make bins` reads it to pick the tarball, and `Cargo.toml` pins the matching `uc_*` crate versions. The node binary and the crates your service links against must come from the same release: every UC minor release so far has been a flag day, and a mismatch would fail at runtime rather than at compile time. So change the version only with `make uc-upgrade VERSION=<x>`, which moves both at once, never by editing `UC_VERSION` by hand.

**Next: Step 2, Run the skeleton.** `make up && make demo` starts a local 3-node cluster running the skeleton key-value app and drives it through the gateways until it prints `PASS`. Want to continue?


## Turn 3

**Developer:** what next?

**Tutor** (turns=3, denials=0):

You're on **Step 2 of 13, Run the skeleton** (Part 1). `scripts/next.sh --json` reports `status: todo`, and one thing is missing:

- `run: make up && make demo`

**Why this step matters.** `make up` followed by `make demo` runs ten processes in four roles. Three `uc2-node` daemons handle consensus, replication and durability, and elect a leader among themselves. Three copies of your service each attach to one node over shared memory and apply the same commands in the same order. Three `uc2-gateway`s give clients that can't use shared memory a TCP way in, and the tenth process is the client itself. The start order is fixed (nodes, then a serving leader, then services, then gateways) because a service is refused with `NodeBooting` until its node has joined the cluster. See [the quickstart, § 3](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/QUICKSTART.md#3-what-just-happened) and [the state-machine contract, § Attaching](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md).

Do you want to do this yourself (I'll guide and review), or shall I do it?


## Turn 4

**Developer:** you do it and explain

**Tutor** (turns=5, denials=0):

Step 2 is done: `make demo` printed `PASS`, and `scripts/next.sh --json` has moved on to Step 3. The cluster is still running.

**1. `make up`: ten processes, started in a fixed order**
```
cargo build --release
   Compiling stock-app v0.1.0 ...
    Finished `release` profile [optimized] target(s) in 4.09s
1. nodes      started node0/1/2
              waiting for a serving leader
              node 0 is the serving leader
2. services   started service0/1/2
3. gateways   started gateway0/1/2
              gateways: 127.0.0.1:8500,127.0.0.1:8501,127.0.0.1:8502
```
- **Nodes (`uc2-node` ×3):** they handle consensus, replication and durability. They elected node 0 as leader in term 1.
- **The wait between stages 1 and 2:** a service can attach only after its node has *joined*, meaning it knows a leader and has caught up to the commit position. A service started earlier is refused with `NodeBooting` and gives up after 10 s. That's why the script waits here.
- **Services (`stock-app-service` ×3):** your state machine, one replica per node, attached over shared memory.
- **Gateways (`uc2-gateway` ×3):** TCP ways in for remote clients, one per node. A gateway on a follower redirects the client to the leader.

**2. `make demo`: the tenth process is the client**
```
put greeting hello      -> ok previous=none position=128 replayed=false
get greeting            -> value="hello"
delete greeting         -> ok removed="hello" position=192 replayed=false
get greeting (deleted)  -> value=none
PASS
```
- **`put` and `delete` are commands.** Each is committed to the replicated log first, then applied by all three replicas. `position` is where the command landed in the log.
- **`get` is a query.** It reads state and writes nothing to the log, which is why it has no position.
- **`replayed=false`** means the command was applied for the first time. If the client resends after a lost reply, the cluster answers from its record of the first result instead of applying the command twice (the demo doesn't exercise that).

**3. `make status`: one cluster, three matching views**

| | node 0 | node 1 | node 2 |
|---|---|---|---|
| role | `leader=true can_serve=true` | `leader=false leader_hint=0` | `leader=false leader_hint=0` |
| log | `commit=256 durable=256` | `commit=256 durable=256` | `commit=256 durable=256` |
| service `stock` | `applied=256 lag=0` | `applied=256 lag=0` | `applied=256 lag=0` |

- All three nodes committed and made durable the same log up to position 256.
- All three replicas applied up to that same position, so they hold identical state. This is the property the determinism rules exist to protect.
- The service row shows `hash=0x45214ead76dc0cf5` and `pinned=unversioned` on every node. Nothing is pinned yet; pinning comes up in the Part 2 upgrade flow.
- One thing I haven't confirmed: `members: reported_durable` is 256 on node 0 but 0 on the followers. My reading is that only the leader tracks how far its peers have written to disk. That's inferred from this output, not checked in the docs.

**4. Logs**
`~/.uc-starter/stock-app/logs/` has one file per process: `node0-2.log`, `service0-2.log`, `gateway0-2.log`, plus `gen-admin-key.log`.

> **Insight:** the cluster root is `~/.uc-starter/stock-app`, on your home disk, not under `/tmp`. The nodes rely on `fsync`, and on a RAM-backed filesystem `fsync` does nothing, so "durable" would be a lie. That's why the nodes refuse to run there (hard rule 6). `make down` keeps this state and `make up FRESH=1` wipes it. The cluster's log (up to position 256) survives restarts because it lives on this real disk.

**Next: Step 3, SMR in five minutes.** This one is conceptual: you read the section and I ask you its three check questions, one at a time. I've left the cluster running; `make down` stops it cleanly (services and gateways first, then nodes). Want to continue?


## Turn 5

**Developer:** what next?

**Tutor** (turns=3, denials=0):

You're on **Step 3 of 13, SMR in five minutes** (Part 1). `scripts/next.sh --json` reports `status: todo`, and one thing is missing:

- `read WHAT-NEXT.md Step 3, then: make done STEP=concepts`

**Why this step matters.** State machine replication makes several machines behave as one reliable machine. The nodes agree only on the *order* of commands in a log, and every replica applies that log to its own copy of your state machine. That only works if `apply` is deterministic: no clocks, no randomness, no I/O, no `HashMap` iteration order. UC gives you replicated stand-ins instead: `ctx.time_ns` (the leader's timestamp, carried on the command) and `ctx.ids()` (ids derived from the log). The log is addressed by byte **position**, the same number on every replica. **Sessions** tag every write with `(client_id, seq)`, so a resent write is answered from a cache instead of being applied twice, and **snapshots** let a node that fell behind catch up without replaying the whole log. See [State machine replication, explained](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/state-machine-replication-explained.md).

Whichever way you choose, this step ends with you answering its three check questions (I'll ask them one at a time). I'll record it with `make done STEP=concepts` only after you've answered all three.

Do you want to do this yourself (I'll guide and review), or shall I do it?


## Turn 6

**Developer:** I'll do it — guide me

**Tutor** (turns=1, denials=0):

Your first step is to read the explainer: [State machine replication, explained](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/state-machine-replication-explained.md). It takes about ten minutes.

While you read, keep in mind what you just saw in the demo and `make status`:
- `position=128` and `position=192` from `put` and `delete`
- `commit=256`, the same on all three nodes
- `replayed=false` on both writes

The explainer covers what each of those means. Tell me when you've finished, and I'll give you the next action: finding the rules in `src/state.rs`.


## Turn 7

**Developer:** ok read it

**Tutor** (turns=2, denials=0):

Your next step is to open `src/state.rs` (it's 72 lines) and find where each idea from the explainer shows up in the code or its comments:

1. Why the state uses a `BTreeMap` and not a `HashMap`.
2. The list of things `apply` must never do, and the stand-in for each.
3. Where `ctx.position` is used, and what it's recorded as.
4. How `query` differs from `apply`: what it takes, what it can't change, and why it never touches the log.

One hint: sessions and `replayed=true` don't appear anywhere in `src/state.rs`. Notice that `apply` has no code for duplicate commands, and think about why it doesn't need any.

Tell me what you found, even as rough notes. After that I'll start the three check questions.


## Turn 8

**Developer:** found it. btreemap because hashmap order differs per process. apply can't use clock/random/io/hashmap iteration - use ctx.time_ns and IdGen. position is saved as last_applied. query only takes &self so it can't change anything. no duplicate handling in apply, i guess something outside does it? also the comment says IdGen but step 3 said ctx.ids(), which one?

**Tutor** (turns=5, denials=0):

You found all four, and you've spotted a real inconsistency. Here's how your notes check out.

**Your findings**
- **BTreeMap:** correct. Anything that iterates the state (a snapshot, a projection, a "list" response) would differ between replicas with a `HashMap`, because its order differs between processes.
- **The banned list:** correct. The comment also bans comparing floats, and AGENTS.md hard rule 1 adds unchecked arithmetic (`+`, `-`, `*`) and panics on input.
- **`last_applied = ctx.position`:** correct. That's how the framework knows which log position this replica's state reflects, which it needs for snapshots and catch-up.
- **`query(&self)`:** correct. The compiler guarantees a read can't change state, so reads don't need to go through the log to stay consistent.
- **Duplicates handled outside:** your guess is right. `src/bin/service.rs:82` and `:123` wrap your state machine as `Sessioned::new(Fsm::default(), SessionConfig::default())`. `Sessioned` reads the 16-byte `(client_id, seq)` envelope the gateway adds to every write and answers repeats from its cache before your `apply` ever sees them. That's why `apply` stays simple.

**`IdGen` or `ctx.ids()`?** They're the same thing seen from two sides, and **`ctx.ids()` is the one you call**. I checked this in the pinned crate, `uc_service-2.13.0` (the version in `Cargo.lock`):

```rust
// uc_service-2.13.0/src/traits.rs:155
pub fn ids(&mut self) -> IdGen {
    self.ids_calls += 1;
    IdGen::new(self.position, self.identity)
}
```
- `IdGen` is the type. `ctx.ids()` is how you get one.
- Ids come from `position ‖ ordinal ‖ identity`, so every replica mints the same ones.
- `IdGen::new` is public, but calling it directly skips the `ids_calls` counter. UC uses that counter to detect when two builds mint a different number of generators for the same command, and the `determinism-review` skill checks those counts across an upgrade.
- The `IdGen` doc comment says to "obtain it from `ApplyCtx::ids`" and never keep one across calls. The type is `!Send`, so stashing one in your state won't compile.

So the comment at `src/state.rs:43` isn't wrong, but it names the type rather than the call. If you want, I can change it to `ctx.ids()` to match AGENTS.md; I haven't touched it.

Now the check questions, one at a time.

**Question 1: Why can't `apply` read the clock?**


## Turn 9

**Developer:** because each replica runs apply at a different time so they'd get different values and diverge

**Tutor** (turns=1, denials=0):

Right, and that's the core of it. The official answer adds one more angle: it isn't only three replicas running at slightly different moments. **The same command is applied again, possibly days later**, whenever a node rebuilds its state by replaying the log (after a crash, when a new node joins, or during the diff replay you'll do in Step 12). A clock reading inside `apply` would give a different result on every replay, even on the *same* machine.

`ctx.time_ns` fixes both problems at once. The leader reads the clock **once**, when it puts the command into the log, and that timestamp travels with the command. Every replica, and every future replay, sees the same value. You saw this in `make status` as `log_time_ns=1790276652902334317`, the same on all three nodes.

The general rule behind it: `apply` may depend only on **the state so far plus what's in the log entry**. Anything else (clock, RNG, files, environment) has to be either put into the command or derived from it, the way `ctx.ids()` derives ids from the position.

**Question 2: What does `replayed=true` mean?**


## Turn 10

**Developer:** it means the command was replayed from the log, like after a node restarts it applies it again?

**Tutor** (turns=1, denials=0):

Not quite. You're mixing up two different kinds of "replay", and it's worth separating them because they behave in opposite ways.

**What you described: log replay after a restart.** A node that restarts rebuilds its state by applying the log again from its last snapshot. Your `apply` **does** run again for those commands, and it has to, because that's how the state comes back. No client is waiting for those results, so nothing reports `replayed=` here. This case is safe only because `apply` is deterministic (question 1).

**What `replayed=true` means: a duplicate write from a client.** The same `(client_id, seq)` was already applied, so `Sessioned` answered with the **cached response** and your `apply` did **not** run a second time. It typically happens like this:
1. The client sends `put greeting hello` with seq 7. It commits and is applied.
2. The leader crashes before the reply reaches the client, so the client gets `UNKNOWN`: it can't tell whether the write happened.
3. The client re-sends seq 7 to the new leader.
4. `Sessioned` sees that seq 7 is already done and returns the original `ok previous=none` with `replayed=true`.

Without this, a retried "add 10 to the balance" would be applied twice. With it, the client can always retry safely, and `replayed=true` tells it the retry was a duplicate.

In the demo you saw `replayed=false` on both writes, because each was sent exactly once.

A quick way to keep them apart: **log replay runs your `apply` again (and must reach the same result); `replayed=true` means your `apply` was skipped.**

**Question 3: What is a position?**


## Turn 11

**Developer:** ah ok. position is the number of the command in the log, like entry 1, 2, 3

**Tutor** (turns=2, denials=0):

Step 3 is recorded:

```
$ make done STEP=concepts
recorded: done concepts
$ scripts/next.sh --json
{"step":4,"id":"design","title":"Design your app","status":"todo", ...}
```

**Summary of the three answers**

| question | your answer | the key point |
|---|---|---|
| Why no clock in `apply`? | ✅ replicas run at different times | also: the log is replayed later, possibly days later; `ctx.time_ns` is read once, by the leader |
| `replayed=true`? | ❌ log replay after a restart | a duplicate client write; `Sessioned` answered from its cache and `apply` did **not** run |
| What is a position? | ❌ entry number | a byte offset in the log, the same on every replica and always growing (the demo went 128 → 192) |

If you want to see the gap between positions for yourself, `make demo` again with the cluster still up. The new writes should land after the current `commit`, but I haven't run that, so treat it as something to try.

**Next: Step 4, Design your app.** `scripts/next.sh` lists 8 `TODO(app)` markers still to fill in, at lines 11, 20, 36, 47, 61, 75, 93 and 111 of the design spec. I believe the spec is `docs/app-design.md`, but I haven't opened it to check. Say "what next?" when you're ready and I'll go through that step.


## Turn 12

**Developer:** what next?

**Tutor** (turns=2, denials=0):

You're on **Step 4 of 13, Design your app** (Part 1). `scripts/next.sh --json` reports `status: todo`. What's missing is 8 `TODO(app)` markers at lines 11, 20, 36, 47, 61, 75, 93 and 111. Step 4's **Done when** confirms they're in `docs/app-design.md`.

**Why this step matters.** A **command** changes state: it goes through consensus and is applied on every replica, in log order, forever. A **query** only reads, from one replica, and is never stored. Every command must fit in a single UDP datagram with no chunking. After the 16 B `Sessioned` envelope, that leaves **1296 B** for your encoded command with wire crypto on. Responses aren't limited to one datagram, but they should still be bounded, because a "list everything" answer grows with your state. Mistakes in the command set, in size limits and in determinism hazards are cheapest to fix now, before they're stored in a log forever. See [the state-machine contract § Payload ceiling](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md#payload-ceiling) and [Limits](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/limits.md).

Either way, the design has to come from you: the project is called `stock-app`, but only you know what it should do. If I do it, I'll interview you first and then draft the doc. The check only confirms the markers are gone; it can't judge the design itself.

Do you want to do this yourself (I'll guide and review), or shall I do it?


## Turn 13

**Developer:** you do it and explain

**Tutor** (turns=2, denials=0):

Before I write anything I need your answers. The doc is currently a worked example for the skeleton registry, and "stock-app" could mean several different things. I read all 8 sections of `docs/app-design.md`; these questions cover what they need.

**1. What is "stock"?** Pick one, or describe your own:
- **(a) Inventory:** a warehouse's stock levels per product (SKU). You receive stock, reserve it for orders, ship it, and can never go below zero.
- **(b) Trading:** an order book for share tickers. Place and cancel buy and sell orders, and the matching engine trades them.
- **(c) Portfolio:** accounts holding shares and cash, with transfers between them.

**2. Who writes, and what are the operations?** For example: "warehouse staff receive and ship, the web shop reserves and releases". Name 3 to 6 actions.

**3. What must never happen?** For example: stock below zero, the same order reserved twice, or a trade without matching funds. This decides which checks `apply` makes and which errors it returns.

**4. What do readers need?** For example: the level of one SKU, a list of SKUs (paged), or one order's status.

**5. Rough scale:** how many items or tickers, how long an id or name can be, and the largest quantity. This sets the `MAX_*` limits and the integer types.

If you'd rather not decide the details now, say "go with (a), sensible defaults". I'll then draft an inventory design (receive / reserve / release / ship, per-SKU on-hand and reserved counts, no negative stock, a paged list query) and mark every assumption I made under **8. Open questions**, so you can change it later.


## Turn 14

**Developer:** a replicated stock ledger: `Receive { sku, qty }` adds stock, `Ship { sku, qty }` removes it and must fail without changing anything if there isn't enough; query `OnHand { sku }`. Quantities are whole units.

**Tutor** (turns=6, denials=0):

Step 4 is done: `docs/app-design.md` has no TODO markers left, and `scripts/next.sh` has moved on.

```
$ grep -c TODO docs/app-design.md
0
$ scripts/next.sh --json
{"step":5,"id":"commands","title":"Commands","status":"todo", ...}
```

The check only confirms the note is finished; it can't judge the design. Here it is section by section, with the UC idea behind each one.

**§1 What the app does → why replicate at all.** Two `Ship` commands racing for the last 5 units are ordered by the log, so exactly one of them wins, on every replica. The "enough stock?" decision is made once, against one agreed history.

**§2 Commands → the wire tag and the datagram limit.**
- `Receive` is variant 0 and `Ship` is variant 1. Their position in the enum is their wire tag from now on.
- A failed `Ship` is a normal **response** (`Rejected(Insufficient { on_hand, requested })`), not an error or a panic. That's how "fail without changing anything" works in SMR: the command is still committed and applied, but `apply` decides to change nothing, and it decides the same way on every replica.
- `apply` runs `validate()` again. `validate()` runs in the client, but a buggy or hostile client could skip it. Running it again inside `apply` is deterministic because it's a pure function of the command.

**§3 Queries → reads skip the log.** `OnHand` reads from whichever replica answers and may be slightly behind. That's safe here: a stale read can't cause an oversell, because `Ship` makes the decision against committed state.

**§4 State → deterministic data.**
- `BTreeMap<String, u64>`, in whole units.
- `checked_add` guards against overflow. `Ship` compares first, then uses `checked_sub`.
- A SKU that reaches 0 is removed. That keeps the state bounded and gives each SKU exactly one representation.

**§5 Hazards → hard rule 1, row by row.** The two hazards this app actually has are **overflow** and **panics on input**. Clock, ids, floats and I/O don't arise, and each row says what to use if they ever do.

**§6 Size bounds → measured, not guessed.** I compiled mirror types of the enums with the same `bincode::config::standard()` as `src/commands.rs:76`:
```
Receive max   75     Received max  10     OnHand query  66
Ship max      75     Rejected max  20     OnHand answer 10
```
The largest command is 75 B + 16 B envelope = 91 B, against a 1296 B limit. These are mirror types, not the real enums; Step 5 should measure again.

**§7 Snapshot → image version vs FSM version.** `IMAGE_VERSION` stays 1 because no cluster has run this app yet. From the first real deployment on, any change to the state's shape needs a new image version plus the Step 12 flow. The projection is `<sku> <on_hand>`, one line per SKU, in SKU order. That's why `validate()` bans whitespace in SKUs: every line has to parse unambiguously.

> **Insight:** removing SKUs at 0 isn't just tidiness. Step 12's diff replay compares `project()` text between the old and new build. If one build kept `ABC 0` and the other removed `ABC`, their states would be equivalent, but the projections would still show a diff. A single representation for "no stock" avoids that whole class of false alarm.

**Choices I made that you didn't specify.** Please check these; each is also in §8 Open questions:
1. SKU format: 1–64 B, printable ASCII, no whitespace.
2. `qty ≥ 1`, and `u64` counts.
3. SKUs are removed at 0, and an unknown SKU reads as 0 on hand.
4. An overflow on `Receive` is rejected (not saturated).
5. There are three reasons for `Rejected`: `Insufficient`, `Overflow` and `Invalid`.

**Heads-up for Step 5:** the local cluster is still running with the skeleton's `Put`/`Delete` entries in its log. Once `Command` is replaced, those bytes would decode as `Receive`/`Ship` (Step 5, Common mistakes). So after Step 5, restart with `make up FRESH=1`, not `make restart-services`.

**Next: Step 5, Commands.** It turns §2 and §3 into `src/commands.rs` and `validate()`. Change any of the choices above first if you want, or say "what next?".


## Turn 15

**Developer:** what next?

**Tutor** (turns=2, denials=0):

You're on **Step 5 of 13, Commands** (Part 1). `scripts/next.sh --json` reports `status: todo`, and one thing is missing:

- `TODO(app) at 5` (the marker in `src/commands.rs`)

**Why this step matters.** The typed tier encodes your enums with bincode, which writes each variant as its *index*, so a variant's position in the enum is its wire tag. Commands are stored in the log and replayed for as long as the cluster lives. If you insert or reorder a variant, old entries decode as a different command, with no error (measured: a stored `Put(11,22)` came back as `Delete(11)`). So you only ever add variants at the end, and once a real cluster has run a version, even an appended variant needs Step 12's upgrade flow. `Command::validate()` runs in the client *before* anything is sent, so an oversize or malformed command is refused at the door with a clear message. See [the state-machine contract](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md) and [the change taxonomy](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/application-sdlc.md#the-change-taxonomy).

For this step, that means turning §2 and §3 of your design into `Command { Receive, Ship }`, `Response`, `Query { OnHand }` and `QueryResponse`, with `validate()` checking the SKU format and `qty ≥ 1`. `cargo check` has to pass across the whole crate, so `state.rs`, `snapshot.rs` and `client.rs` get minimal stubs for now; Steps 6 and 8 fill them in properly. Because this touches `src/commands.rs`, I'll also run the `determinism-reviewer` subagent on the diff before calling the step done.

Do you want to do this yourself (I'll guide and review), or shall I do it?


## Turn 16

**Developer:** I'll do it — guide me

**Tutor** (turns=4, denials=0):

Before you change anything, one question: **has any cluster other than your disposable local one run this app?** If one has, replacing the enums is an upgrade: it needs `make corpus` first and an `FSM_VERSION` bump. I'm assuming the answer is no, since you've only run the skeleton locally, so the plan is to replace the enums and restart the local cluster with `make up FRESH=1` afterwards. Tell me if that's wrong.

**Your first action is to rewrite the four enums in `src/commands.rs` (lines 15–37)** from §2 and §3 of `docs/app-design.md`. Leave `validate()` and the constants for the next action. Guidance:

- **`Command`:** `Receive` first, then `Ship`, both `{ sku: String, qty: u64 }`. Keep the "Append new variants at the END" comment. It stops being a tutorial note once this enum is the one your real log is written in.
- **`Response`:** `Received { on_hand: u64 }`, `Shipped { on_hand: u64 }`, `Rejected(Reject)`.
- **A new `enum Reject`:** `Insufficient { on_hand: u64, requested: u64 }`, `Overflow { on_hand: u64, requested: u64 }`, `Invalid`. It needs the same `derive` line as the others, because it travels inside `Response`. Its variant order is a wire tag too.
- **`Query`:** `OnHand { sku: String }`.
- **`QueryResponse`:** `OnHand(u64)`.

A few things to watch, from the Step 5 **Common mistakes**:
- Every wire enum needs the full derive set (`Debug, Clone, PartialEq, Eq, Serialize, Deserialize`). Tests compare responses with `==`, and the client encodes with serde.
- Don't add a `#[serde(rename…)]` or any other attribute that changes the encoding. bincode ignores names, and the order is what matters.
- Once the enums change, `cargo check` fails in `validate()`, `state.rs`, `snapshot.rs` and `client.rs`. That's expected, and we'll fix it in the next actions.

Tell me when the enums are done, and I'll review the diff before you move on to `validate()`.


## Turn 17

**Developer:** done, check it. (no, nothing but my local cluster has run it)

**Tutor** (turns=3, denials=0):

The enums are correct. I checked the diff against the design and the Step 5 **Common mistakes**:

| check | result |
|---|---|
| `Command` order matches §2 (`Receive` = tag 0, `Ship` = tag 1) | ✅ |
| `Response` / `Reject` shapes match §2, `Query` / `QueryResponse` match §3 | ✅ |
| every wire enum, including the new `Reject`, has the full derive set | ✅ |
| no serde attributes that change the encoding | ✅ |
| the "Append at the END" comment kept | ✅ |

> **Insight:** `Reject` is nested inside `Response::Rejected`, but it's just as much a wire type. bincode writes it as `[Response tag][Reject tag][fields]`, so `Insufficient` / `Overflow` / `Invalid` are frozen in that order too. Responses aren't stored in the log, but `Sessioned` caches them to answer retries (`replayed=true`), and clients built from older code decode them. So once you've shipped, the append-only rule applies to `Reject` as well.

Since nothing but the local cluster has run the skeleton, this is a plain replacement: no corpus and no `FSM_VERSION` bump. We'll wipe the local cluster with `make up FRESH=1` at the end.

**Your next action: limits and `validate()`, in `src/commands.rs` and `src/lib.rs`.**
1. Replace `MAX_KEY_LEN` / `MAX_VALUE_LEN` with a single `MAX_SKU_LEN: usize = 64`, and update the doc comment above it to talk about SKUs.
2. Rewrite `validate()` so it refuses each of these with a clear `CommandError` message:
   - an empty SKU
   - a SKU longer than `MAX_SKU_LEN`
   - a SKU containing anything other than printable ASCII without whitespace. Hint: `u8::is_ascii_graphic` is exactly "printable, not space".
   - `qty == 0`

   Both variants have the same fields, so the skeleton's trick of destructuring into a tuple first still works: `let (sku, qty) = match self { … };`.
3. Update the re-export at `src/lib.rs:17–20`. Swap the old constants for `MAX_SKU_LEN` and add `Reject`, so the client and tests can name it as `stock_app::Reject`.

Things to avoid:
- Don't check `sku.chars().count()`. The limit is on encoded **bytes**, and that's `sku.len()`.
- Don't let `validate()` touch anything except `self`. `apply` will call it again (design §2), so it must be a pure function of the command.

Leave the TODO on line 5 for now. `cargo check` will still fail in `state.rs`, `snapshot.rs` and `client.rs`, which is the action after this one. Tell me when you're done.


## Turn 18

**Developer:** done, check it

**Tutor** (turns=3, denials=0):

Your `validate()` and the re-export are correct.

| check | result |
|---|---|
| a `validate()` rule for every item in design §2 (empty, > 64 B, not graphic ASCII, `qty == 0`) | ✅ |
| length measured in bytes (`sku.len()`), not chars | ✅ |
| pure: reads only `self` | ✅ |
| `bytes().all(is_ascii_graphic)` rejects spaces, tabs, newlines, non-ASCII and control bytes | ✅ |
| `Reject` and `MAX_SKU_LEN` re-exported | ✅ |
| `cargo fmt --check` on both files | ✅ exit 0 |

Two small, optional points:
- **The `validate()` doc comment** (line 56) still says it only exists for the datagram limit. It now also enforces the SKU format that the projection depends on (design §7). One extra clause there would help the next reader.
- **`Query::OnHand { sku }` isn't bounds-checked.** That matches the skeleton, which never validated `Get` either, and a query never enters the log, so this is a UX choice rather than a safety issue. A 10 KB SKU would be refused by the transport with a worse message. You could add a `Query::validate()` later; for now I'd leave it.

**`cargo check` now:** `src/commands.rs` compiles. What's left is 6 errors, all in `src/state.rs`, where the `apply` and `query` match arms still name `Put`, `Delete`, `Get` and `Value`:
```
error[E0599]: no variant named `Put` found for enum `commands::Command`  --> src/state.rs:48:22
...
error[E0599]: no variant ... named `Value` found for enum `QueryResponse` --> src/state.rs:64:50
```
`client.rs` will fail next, once the library compiles; `cargo` stops at the lib first.

**Your next action: minimal stubs in `src/state.rs` so it compiles.** Step 6 writes the real ledger logic, so for now:
1. In `apply`, make both `Receive` and `Ship` return `Response::Rejected(Reject::Invalid)`. Keep `self.last_applied = Some(ctx.position)` after the match.
2. In `query`, make `Query::OnHand { .. }` return `QueryResponse::OnHand(0)`.
3. Leave `State` as it is for now, along with all three `TODO(app)` markers in `state.rs`. They're Step 6's proof.

Don't use `todo!()` or `unimplemented!()` as the stub. Both panic inside `apply`, which the determinism hook flags. And if a stub like that ever reached a running cluster, the service would crash-loop on the same committed command forever. A rejecting stub is harmless.

Then run `cargo check` and tell me what fails next (it should be `src/bin/client.rs`).


## Turn 19

**Developer:** done, check it. cargo check now fails in src/bin/client.rs, 6 errors (Put/Delete/Get/Value)

**Tutor** (turns=3, denials=0):

The client needs the same renaming, in four places. I've read `src/bin/client.rs` lines 61–244. Step 5 only asks for a **minimal** body here; Step 8 builds the real CLI, so leave the `TODO(app)` on line 61.

**Your next action: update `src/bin/client.rs` to the new wire types.**
1. **`enum Sub` (lines 62–77).** Replace the variants with `Receive { sku: String, qty: u64 }`, `Ship { sku: String, qty: u64 }` and `OnHand { sku: String, #[arg(long)] linearizable: bool }`. Keep the `--linearizable` doc comment on `OnHand`; it's still accurate. clap parses `qty: u64` for you and refuses `-3` or `abc` with exit 2.
2. **`run` (lines 161–181).** Build `Command::Receive` / `Command::Ship` from the matching `Sub`, with `OnHand` → `None`. Update the second match the same way. Leave the `validate()` call where it is, before `connect`: that's what makes a bad SKU exit with code 2 without touching the network.
3. **`submit` (lines 197–214).** Give each `Response` variant a single `println!`, and keep `position=` and `replayed=` on each line, because `scripts/demo.sh` and your own debugging depend on them. For example:
   - `ok on_hand=N position=… replayed=…` for `Received` / `Shipped`
   - `rejected {r:?} position=… replayed=…` for `Rejected(r)`
4. **`query` (lines 229–242).** Encode `Query::OnHand { sku }` and destructure `let QueryResponse::OnHand(n) = answer;`. Rename its `key: &str` parameter to `sku`.

Then:
- **Delete `fn opt` (lines 91–96).** Nothing uses it any more. `make check` runs clippy with warnings as errors (the dead-code warning is inferred from how strict `make check` is; I haven't run it yet).
- **Leave a rejection's exit code at 0 for now.** Whether a rejected `Ship` should exit 1 is a CLI design decision for Step 8. It doesn't affect the wire format.

When it's done, run `cargo check` and paste the output. If it's clean, the last actions are deleting the line 5 TODO, then the determinism review and a fresh cluster.


## Turn 20

**Developer:** done, check it. cargo check is clean now

**Tutor** (turns=2, denials=0):

Your client changes are correct, and I get a clean `cargo check` too:
```
$ cargo check
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.02s
```

| check | result |
|---|---|
| `validate()` still runs before `connect` (bad SKU → exit 2, no network) | ✅ |
| `position=` and `replayed=` kept on every submit line | ✅ |
| `Received` / `Shipped` share one arm via an `\|` pattern | ✅ neat; they print the same thing |
| `opt` deleted, so there's no dead-code warning | ✅ |
| `OnHand` keeps `--linearizable` | ✅ |
| `TODO(app)` at line 61 left for Step 8 | ✅ |

One nit: the comment at lines 158–160 still says "an oversize key/value". Make it "an invalid SKU or quantity" when you're next in there.

**Your last action for this step:** delete the `TODO(app)` line at `src/commands.rs:5`. Line 4 above it still reads fine without it. Do the comment nit in the same edit if you like.

After that, the rest is on me, per CLAUDE.md: I'll run the `determinism-reviewer` subagent on the whole diff, then the Step 5 check (`cargo check` plus `scripts/next.sh --json`), and show you the output.

Heads-up on the cluster: **don't** run `make restart-services` or `make demo` yet. The running cluster's log still holds `Put` / `Delete` bytes, and `scripts/demo.sh` still sends `put` / `get` (that's its own `TODO(app)`, for Step 8). The new build goes onto a wiped cluster with `make up FRESH=1` once `apply` does something real in Step 6.


## Turn 21

**Developer:** done, check it

**Tutor** (turns=3, denials=0):

Step 5 is done. You wrote every change yourself; I reviewed each one and ran the checks.

**The Step 5 check**
```
$ grep -n TODO src/commands.rs
(no output)
$ cargo check
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.02s
$ scripts/next.sh --json
{"step":6,"id":"state","title":"State, apply and query","status":"todo",
 "detail":["TODO(app) at src/state.rs:11","TODO(app) at src/state.rs:46",
           "TODO(app) at src/state.rs:58","TODO(app) at src/snapshot.rs:111"]}
```

**The determinism review** (the `determinism-reviewer` subagent, on the whole diff): **no hazards found.**
- `scripts/lint-determinism.sh --all` produced no output and exited 0.
- `validate()` is pure and matches design §2 exactly.
- The stubs can't panic, and `last_applied` is set on every path.
- No serde attributes change the encoding.
- A full replacement of never-shipped enums is safe, given that only the local cluster ran the old ones and it will be wiped.

The reviewer also reported one thing I haven't checked myself: **`cargo test` currently fails** to compile, because `tests/state.rs`, `tests/determinism.rs` and `tests/cli.rs` still use `Put` / `Delete` / `Get` / `Value`. That's expected at this point; the tests get rewritten in Step 7 (`tests/`). It does mean `make check` will fail until then.

> **Insight:** the stub `apply` returns `Rejected(Invalid)` rather than `todo!()`, and that's worth keeping as a habit. A command that makes `apply` panic is still **committed**, so every restart replays it and panics again: a crash loop on every replica that no client retry can fix. A rejecting stub costs nothing and fails closed. It's the same reason design §5 says bad input gets an error *response*, never a panic.

**What you built, in order of how permanent it is:**
1. **Wire tags.** `Receive` = 0, `Ship` = 1, and `Reject`'s order are the part you can never change once a real cluster has run them.
2. **`validate()`.** It refuses bad input at the door (exit 2, no network), and Step 6 will call it again inside `apply`.
3. **The client.** A thin mapping from CLI arguments to wire types, which Step 8 replaces properly.

**Next: Step 6, State, apply and query.** This is where `Receive` / `Ship` / `OnHand` get their real logic (`checked_add`, compare-then-`checked_sub`, removing a SKU at 0, `validate()` again in `apply`), along with the snapshot projection. Say "what next?" when you're ready.


## Turn 22

**Developer:** what next?

**Tutor** (turns=2, denials=0):

You're on **Step 6 of 13, State, apply and query** (Part 1). `scripts/next.sh --json` reports `status: todo`, with four markers to resolve:

- `TODO(app)` at `src/state.rs:11`: the `State` struct
- `TODO(app)` at `src/state.rs:46`: the `apply` arms
- `TODO(app)` at `src/state.rs:58`: the `query` arms
- `TODO(app)` at `src/snapshot.rs:111`: `project()`, one line per record

**Why this step matters.** `apply` runs on every replica, for every committed command, in log order. The same state plus the same command must give the same result everywhere, forever. Time comes from `ctx.time_ns` (the leader's stamp, which never goes backwards), and ids come from `ctx.ids()`. `ctx.ids()` derives each id from the position, the FSM identity, and a counter that restarts at zero in every `apply` call, so a replica rebuilt from a snapshot mints the same ids as one that replayed the whole log. `last_applied()` tells the framework where to resume after a restart, so it has to be set to `ctx.position` on every path through `apply`, rejections included. See [FSM identity and deterministic IDs, explained](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/uc2-fsm-identity-and-deterministic-ids-explained.md).

For your ledger, that means:
- `State { on_hand: BTreeMap<String, u64> }`
- `Receive` uses `checked_add` and answers `Rejected(Overflow)` on overflow
- `Ship` compares first, then uses `checked_sub`, and removes a SKU that reaches 0
- `apply` runs `validate()` again and answers `Rejected(Invalid)`
- `OnHand` answers 0 for an unknown SKU
- `project()` prints `<sku> <on_hand>` lines in SKU order

The check is `cargo test --lib` plus `scripts/lint-determinism.sh --all`. The integration tests in `tests/` stay broken until Step 7.

Do you want to do this yourself (I'll guide and review), or shall I do it?


## Turn 23

**Developer:** you do it and explain

**Tutor** (turns=16, denials=0):

Step 6 is done. Here's the proof, then the diff hunk by hunk.

**The checks**
```
$ cargo test --lib
running 0 tests
test result: ok. 0 passed; 0 failed ...
$ scripts/lint-determinism.sh --all          → exit 0, no findings
$ cargo clippy --lib --bins                  → clean
$ cargo fmt --check -- src/state.rs src/snapshot.rs → exit 0
$ scripts/next.sh --json
{"step":7,"id":"tests","title":"Tests that cover your commands","status":"todo",...}
```

`cargo test --lib` runs 0 tests, so on its own it only proves the code compiles. The behaviour evidence comes from a throwaway test I ran and then deleted (I didn't watch it fail with the logic reverted):

| scenario | result |
|---|---|
| receive 5, then 3 | `Received { on_hand: 5 }`, then `8` |
| ship 9 of 8 | `Insufficient { on_hand: 8, requested: 9 }`, and still 8 afterwards |
| ship all 8 | `Shipped { on_hand: 0 }`, and the SKU is gone from the map |
| ship an unknown SKU | `Insufficient { on_hand: 0, … }` |
| receive past `u64::MAX` | `Overflow`, and nothing changes |
| `"has space"` or `qty = 0` | `Invalid`, and the cursor still advances |

```
projection:
B 18446744073709551615
C 2
```

**The determinism review: no hazards found.** The reviewer also checked something subtler: `install_snapshot` can only load a state that `apply` could have produced, so the unquoted projection is safe for every state the cluster can reach.

**The diff, hunk by hunk**

**1. `State` (`src/state.rs:11–27`): the replicated data.**
- `on_hand: BTreeMap<String, u64>`, holding only counts above 0.
- `count()` returns 0 for a missing SKU. Both `apply` and `query` go through it, so there's a single definition of "none in stock".
- *UC concept: deterministic state.* It uses sorted iteration and whole-unit integers, and there's no second representation of zero.

**2. `receive` / `ship` (`src/state.rs`, the `impl Fsm` block): checked arithmetic.**
- `checked_add`: `None` becomes `Rejected(Overflow)`.
- `checked_sub` doubles as the stock check. `None` becomes `Rejected(Insufficient)`, `Some(0)` removes the SKU, and `Some(n)` stores `n`.
- *UC concept: hard rule 1, overflow.* A plain `-` panics in debug builds and wraps in release builds, so two replicas built differently would diverge. Here, overflow is an ordinary response.

**3. `apply`: validation inside the state machine.**
- `cmd.validate()` runs again before the match. Anything that fails it becomes `Rejected(Invalid)`.
- `last_applied = Some(ctx.position)` stays after the `if`/`else`, so it's set on every path, rejections included.
- *UC concept: `apply` must never trust the client.* It's also *the cursor*: without it, a restart would resume from the wrong place.

**4. `query`.** `OnHand` reads `count()`. Because `query` takes `&self`, the compiler guarantees it can't change anything. *UC concept: queries never enter the log.*

**5. `project()` (`src/snapshot.rs:108–117`): the diff-replay text.**
- It prints `<sku> <on_hand>`, one line per SKU, in `BTreeMap` order.
- It drops the skeleton's Debug quoting. That's safe because hunk 3 guarantees no stored SKU contains whitespace, and the doc comment says so, so nobody removes that guarantee without seeing the cost.
- *UC concept: Step 12 compares this text between the old and new build.*

**6. `docs/app-design.md` §4 and §5.** The design now says `checked_sub` *is* the comparison, which matches the code.

> **Insight:** a rejected command still moves `last_applied` forward, and that's easy to get wrong. `Ship 9 of 8` changed no stock, but it's still a committed log entry at a real position that this replica has applied. If the cursor stayed behind on rejections, a restart would resume one entry too early and apply that command again. That's harmless here, because a rejection is a no-op, but it would be wrong for any command whose rejection path records something. The rule is about the log, not the stock: every entry applied moves the cursor.

**Where things stand**
- **`tests/` still doesn't compile** (`Put` / `Get` in `tests/state.rs`, `tests/determinism.rs` and `tests/cli.rs`), so `make check` still fails. Fixing that is Step 7.
- **The local cluster is still running the old skeleton build**, and I haven't restarted it. It moves to the new build with `make up FRESH=1` once the demo script is rewritten.

**Next: Step 7, Tests that cover your commands.** It rewrites `tests/` for the ledger, including the property test in `tests/determinism.rs` (`TODO(app)` at line 3). Say "what next?" when you're ready.


## Turn 24

**Developer:** what next?

**Tutor** (turns=2, denials=0):

You're on **Step 7 of 13, Tests that cover your commands** (Part 1). `scripts/next.sh --json` reports `status: todo`, and one thing is missing:

- `TODO(app) at tests/determinism.rs:3`

**Why this step matters.** `tests/determinism.rs` is a property test. It generates random command sequences from `arb_command`, applies them to two fresh state machines, and asserts identical responses and projections. It also snapshots at a random point, installs the image into a third machine, and checks that it ends where an uninterrupted run ends. That shows your `apply` is a pure function within one build and that your snapshot round-trips. It *can't* show that your next version reads this version's log (that's Step 12's diff replay), nor catch hazards that only appear across processes, like per-process hash seeds (the `make lint` bans cover those). As UC's own verification record puts it, your state machine's determinism is your responsibility. See [Verification, § 11](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/VERIFICATION.md#11-what-is-not-verified).

For your ledger, the key point is that `arb_command` needs a **tiny SKU space** (say `A` / `B` / `C`) and small quantities. That way `Ship` regularly hits `Insufficient` and the remove-at-0 path, not just the happy path. `tests/state.rs`, `tests/snapshot.rs` and `tests/cli.rs` also need rewriting away from `Put` / `Get`. The step is done only when `make check` passes, which also runs fmt, clippy, clippy on 1.89, and the determinism grep.

Do you want to do this yourself (I'll guide and review), or shall I do it?


## Turn 25

**Developer:** I'll do it — guide me

**Tutor** (turns=2, denials=0):

Your first action is **`arb_command` in `tests/determinism.rs` (lines 8–14)**. It's the heart of this step, because the two property tests below it (`replicas_agree` and `snapshot_then_continue_equals_uninterrupted`) only exercise the commands it generates. Those tests don't need changing: they use nothing but `Command`, `apply` and `project`.

Replace the `Put` / `Delete` strategies with `Receive` and `Ship`, and aim for **collisions and edge cases, not variety**:

1. **SKUs:** a tiny space, e.g. `select(vec!["A", "B", "C"])`, so the same SKU is received and shipped over and over. Also mix in an **invalid** SKU now and then, like `""` or `"x y"`, so the `Rejected(Invalid)` arm runs. Any SKU that's valid under `validate()` shows up in the projection, so the snapshot test covers it as well.
2. **Quantities:** small, e.g. `0..=10u64`. Small numbers make `Ship` exceed stock often (`Insufficient`) and land exactly on 0 often (remove-at-0), and `0` itself hits `Invalid`. Add `Just(u64::MAX)` as a rare option, so two receives of it trigger `Overflow`. `prop_oneof![9 => 0..=10u64, 1 => Just(u64::MAX)]` weights it about 1 in 10.
3. **Both variants in one `prop_oneof!`.** Build the `(sku, qty)` strategy once and `prop_map` it into `Command::Receive { sku, qty }` and `Command::Ship { sku, qty }`, the same way the skeleton reuses `key.clone()`.

Watch out for these (from Step 7's **Common mistakes**):
- A SKU space like `"[A-Z]{1,8}"` looks thorough, but two random SKUs almost never match. `Ship` would then almost always hit an empty SKU, and the property test would pass without ever touching the success path.
- Leave the `TODO(app)` on line 3 until the whole step is done. It's the step's marker, and removing it early makes `next.sh` think you've finished.

Then run `cargo test --test determinism`. That test file compiles on its own, so you don't have to wait for the other test files to be fixed. Tell me when it passes, and I'll review it before you move on to `tests/state.rs`.


## Turn 26

**Developer:** done, check it. cargo test --test determinism passes, 2 tests

**Tutor** (turns=3, denials=0):

Every arm is reached. `git status` shows only your `tests/determinism.rs` change; the scratch file is gone. Here's what 256 generated sequences hit (7,984 commands):

| arm | count | share |
|---|---|---|
| `Received` | 1957 | 25% |
| `Shipped` | 995 | 12% |
|  ↳ shipped to 0 (remove-at-0) | 78 | 1% |
| `Rejected(Insufficient)` | 1203 | 15% |
| `Rejected(Overflow)` | 261 | 3% |
| `Rejected(Invalid)` | **3568** | **45%** |

**Review**
- ✅ Every arm runs, including the `Overflow` and remove-at-0 paths, which are the rare ones.
- ✅ The tiny SKU space works: `Insufficient` and remove-at-0 both happen because commands collide on `A` / `B` / `C`.
- ✅ Building the `(sku, qty)` strategy once and reusing it for both variants is exactly the skeleton's pattern.
- ⚠️ **Nearly half the commands are `Invalid`.** Two of your five SKUs are invalid (40%), and `qty = 0` adds roughly another 8%. `Invalid` is the least interesting arm, because it changes nothing, and each wasted command is one fewer receive/ship collision. In particular, remove-at-0, which is exactly where "absent vs 0" bugs would live, gets only 1%.

**Your next action (a small one): weight the SKU strategy** so invalid SKUs are rare, for example:
```rust
let sku = prop_oneof![
    8 => prop::sample::select(vec!["A", "B", "C"]),
    1 => prop::sample::select(vec!["", "x y"]),
]
.prop_map(String::from);
```
Then run `cargo test --test determinism` again. If you'd like to see the new distribution, tell me and I'll rerun the tally.

After that come `tests/state.rs` and `tests/snapshot.rs`: one unit test per command outcome, plus the `validate` refusals.

> **Insight:** a passing property test tells you nothing about *which* paths it covered, and `arb_command` is the only thing that decides that. The tally is a cheap way to check it: a generator that never reaches an arm gives that arm zero protection while still reporting "2 passed". That's Step 7's first **Common mistake** in a milder form. Your arm isn't missing, just under-sampled.


## Turn 27

**Developer:** done, still passes

**Tutor** (turns=2, denials=0):

The weighting is right, and I get the same result:
```
$ cargo test --test determinism
test result: ok. 2 passed; 0 failed ...
```
Invalid SKUs now come up about 1 time in 9 (before `qty = 0` is counted), so most commands are receive/ship collisions on `A` / `B` / `C`. I haven't rerun the tally; ask if you want the numbers.

**Your next action: rewrite `tests/state.rs`.** It has 6 tests today (`put_then_get` … `wire_round_trip`). Keep the `ctx(p)` helper, swap `put(k, v)` for two helpers like `receive(sku, qty)` and `ship(sku, qty)`, and write **one test per outcome** from design §2. Each test should also assert the state afterwards, not just the response:

| test | assert |
|---|---|
| receive, then `OnHand` | `Received { on_hand: 5 }`, `OnHand(5)` |
| receive twice on one SKU | the counts add (5 + 3 → `Received { on_hand: 8 }`) |
| ship part of the stock | `Shipped { on_hand: n }`, and `OnHand` agrees |
| ship all of it | `Shipped { on_hand: 0 }` **and** `state().on_hand` no longer contains the SKU (remove-at-0) |
| ship more than on hand | `Insufficient { on_hand, requested }` **and** `OnHand` unchanged (fail without changing anything is *your* requirement) |
| ship an unknown SKU | `Insufficient { on_hand: 0, … }` |
| receive past `u64::MAX` | `Overflow`, and the count is unchanged |
| an invalid command reaching `apply` | `Rejected(Invalid)` and the state is still empty. This proves the check inside `apply`, not just the client's |
| `last_applied_tracks_position` | keep it, plus a case where the command is **rejected**, because the cursor must advance anyway |
| `validate` refusals | one per rule: empty SKU, 65-byte SKU, `"x y"`, a non-ASCII SKU like `"ü"`, `qty = 0`. Also check a valid 64-byte SKU is **accepted**: the off-by-one edge |
| `wire_round_trip` | keep it; switch it to a `Command`, `Response::Rejected(…)` and `QueryResponse` of your own |

A few tips:
- Import `Reject` (`use app::{…, Reject, …}`). You exported it in Step 5 for exactly this.
- Use `"A".repeat(64)` and `"A".repeat(65)` for the length boundary.
- Every `apply` in a test needs a new, increasing position, as the skeleton does with `ctx(32)`, `ctx(64)`, and so on.

Run `cargo test --test state`. Tell me when it passes, and after that comes `tests/snapshot.rs` (4 tests).


## Turn 28

**Developer:** done, check it. 11 pass

**Tutor** (turns=4, denials=0):

Your 11 tests pass, and they catch real bugs. Each planted mutation was caught by exactly one of your tests, and the restored file passes again:

| mutation planted in `apply` | your tests |
|---|---|
| keep a SKU at 0 instead of removing it | ❌ 1 failed (`ship_all_removes_sku`) |
| skip `validate()` inside `apply` | ❌ 1 failed (`invalid_command_in_apply_is_rejected`) |
| advance the cursor only on success | ❌ 1 failed (`last_applied_tracks_position`) |
| (restored) | ✅ 11 passed |

**Review**
- ✅ Every outcome in design §2 has a test, and each asserts the state afterwards, not just the response.
- ✅ The 64 vs 65 byte boundary is covered, along with `"ü"`, which would get past a `chars().count()` length check.
- ✅ **Your own addition, the encoded-size assertion in `validate_refusals`, is the best test in the file.** If someone later raises `MAX_SKU_LEN` or adds a field, it fails in CI instead of at the datagram limit in production. It turns design §6 from a note into a guarantee.
- Nit: `receive_overflow_changes_nothing` uses `matches!(… Overflow { .. })`. `assert_eq!` against `Overflow { on_hand: u64::MAX, requested: 1 }` would also pin the fields the client prints. Optional.

**Your next action: rewrite `tests/snapshot.rs`** (4 tests, plus the `filled()` helper):
1. **`filled()`:** receive into `"B"`, `"A"`, `"C"` (deliberately out of order), with different quantities.
2. **`round_trip_restores_state_and_cursor`:** probably needs no changes beyond the helper. Check that it compares the whole `state()`, so it covers `on_hand`.
3. **`install_refuses_unknown_image_version`** and **`install_refuses_cursor_at_or_above_instant`:** line 67 asserts `state().entries.is_empty()`. Change it to `on_hand`.
4. **`projection_is_sorted_and_quoted`:** the name and the assertion are about the skeleton's Debug quoting, which Step 6 deliberately removed. Rename it (e.g. `projection_is_sorted_one_line_per_sku`) and assert the **exact** text, e.g. `"A 1\nB 2\nC 3\n"`. Then also ship one SKU to 0 and assert its line has **disappeared**. That pins the "one representation of zero" rule where Step 12's diff replay will look at it.

Then run `cargo test --test snapshot`, and tell me when it passes. `tests/cli.rs` is the last test file.


## Turn 29

**Developer:** done, check it. 4 pass

**Tutor** (turns=5, denials=0):

Your snapshot tests are correct and pass (4). `round_trip_restores_state_and_cursor` already compares the whole `state()` (line 38), so it covers `on_hand` without changes. Your projection test pins both the sort order (`B, A, C` in, `A, B, C` out) and the disappearance at 0. Pulling out a `projection()` helper to call it twice was a nice touch.

**Your next action: `tests/cli.rs`** (it's 46 lines). It spawns the real client binary with arguments that must fail fast, before any network activity. Two tests need changing, and one of them has a trap:

1. **`oversize_value_is_refused_before_connecting` (lines 12–30).** Rename it (e.g. `oversize_sku_is_refused_before_connecting`) and send `receive <65-byte SKU> 1`. Build the SKU from `app::MAX_SKU_LEN + 1`, the same way the skeleton uses `MAX_VALUE_LEN`. Your error message still says `"the limit is …"`, so the `contains("limit is")` check can stay. Consider adding a second case with `receive "x y" 1`: that SKU is valid on the command line but fails `validate()`, so it also proves the format check runs before connecting.
2. **`bad_gateway_address_is_exit_2` (lines 33–39): the trap.** It runs `get k`. With your new client, **`get` isn't a subcommand any more, so clap exits 2 for "unknown subcommand"**, and the test would pass for the wrong reason, never reaching the gateway check. Change it to `on-hand A` (clap turns `OnHand` into `on-hand`), and also assert that stderr mentions `nocolon` or `host:port`, so it can only pass for the right reason.
3. **`service_without_instance_dir_is_refused`:** no change; it doesn't touch the wire types.

Then:
- run `cargo test --test cli`
- delete the `TODO(app)` at `tests/determinism.rs:3`
- run **`make check`** (Step 7's actual check; plain `cargo test` doesn't record the proof)

Paste the `make check` output when you have it.

> **Insight:** a test that asserts only an exit code is vulnerable to "passing for the wrong reason" whenever the CLI changes shape. Exit 2 means "you typed it wrong", and a missing subcommand is also "you typed it wrong". Pinning a fragment of the error message ties the test to the specific rule it's meant to protect.


## Turn 30

**Developer:** cli tests pass (4), removed the TODO. make check: tests all pass but it fails at cargo fmt --check, a diff in tests/determinism.rs line 13 (wants args.clone() split over two lines)

**Tutor** (turns=2, denials=0):

That's a formatting-only failure, and it's just this one hunk. Your test logic is fine. I see the same thing:

```
$ cargo fmt --check
Diff in tests/determinism.rs:13:
-        args.clone().prop_map(|(sku, qty)| Command::Receive { sku, qty }),
+        args.clone()
+            .prop_map(|(sku, qty)| Command::Receive { sku, qty }),
fmt exit: 1
```

**Why only that line?** The line is well under 100 characters, but rustfmt also has a separate `chain_width` limit (60 by default) for method chains like `.clone().prop_map(…)`. The `Ship` line below it is one call, not a chain, so it stays on one line. You don't need to fight it; that's what `cargo fmt` is for. The project's edit hook formats files automatically only when *I* edit them, so files you edit in your own editor need `cargo fmt` (or format-on-save).

**Your CLI tests look good:**
- ✅ The `client(&[…])` helper removes the repeated `Command::new(bin(""))…` boilerplate.
- ✅ `bad_gateway_address_is_exit_2` now uses `on-hand A` and asserts `host:port`, so it can only pass for the right reason.
- ✅ `bad_sku_format_is_refused_before_connecting` asserts `whitespace`, which ties it to the format rule and not just "some exit 2".
- ✅ The `TODO(app)` in `tests/determinism.rs` is gone.

**Your next action:**
```
cargo fmt
make check
```
`make check` runs tests → fmt → clippy → clippy on 1.89 → the determinism grep, and it records the Step 7 proof only if every stage passes. If the 1.89 stage complains that the toolchain is missing, run `rustup toolchain install 1.89.0 --component clippy` and then `make check` again. Paste the tail of the output.


## Turn 31

**Developer:** ran cargo fmt then make check — it went through, last line was scripts/lint-determinism.sh --all with no error

**Tutor** (turns=2, denials=0):

Step 7 is done. I didn't see your `make check` output myself, but `scripts/next.sh` only moves past Step 7 when a `make check` proof matches the current hash of `src/`, `tests/`, `Cargo.toml` and `Cargo.lock`. It has moved on, so the proof is recorded against this exact code:

```
$ scripts/next.sh --json
{"step":8,"id":"client","title":"Client and demo for your commands","status":"todo",
 "detail":["TODO(app) at src/bin/client.rs:61","TODO(app) at scripts/demo.sh:3"]}
$ cargo fmt --check                 → exit 0
$ grep -rn "TODO(app)" tests/       → no matches
```

**What you built in this step**

| file | tests | what it protects |
|---|---|---|
| `tests/determinism.rs` | 2 properties | two replicas agree, and snapshot-then-continue equals an uninterrupted run. `arb_command` reaches every arm, as the tally showed before your weighting change |
| `tests/state.rs` | 11 | every outcome in design §2, the cursor on rejections, the `validate` boundaries, and the encoded size under the ceiling. It caught 3 of 3 planted bugs |
| `tests/snapshot.rs` | 4 | image round-trip, refusals, and the exact projection text including remove-at-0 |
| `tests/cli.rs` | 4 | bad input exits 2 before connecting, each test pinned to its own error message |

> **Insight:** the Step 7 proof is a *hash*, not a checkbox. Any later edit under `src/` or `tests/` turns it **stale** until you run `make check` again. That's deliberate: "the tests passed once" means little after the code has changed, and `next.sh` will list it as `note: Step 7 (tests) is stale` on later steps. In practice, get into the habit of running `make check` as the last thing before you call any change done.

**Next: Step 8, Client and demo for your commands.** It finishes the CLI properly (`client.rs:61`), including the exit-code question for rejected ships that we deferred. It also rewrites `scripts/demo.sh` for receive / ship / on-hand. That's when the local cluster finally moves to your build with `make up FRESH=1`, and `make demo` prints `PASS` for the ledger. Say "what next?" when you're ready.


## Turn 32

**Developer:** what next?

**Tutor** (turns=2, denials=0):

You're on **Step 8 of 13, Client and demo for your commands** (Part 1). `scripts/next.sh --json` reports `status: todo`, with two markers left:

- `TODO(app) at src/bin/client.rs:61`
- `TODO(app) at scripts/demo.sh:3`

**Why this step matters.** The client never talks to a node directly. It connects to *every* gateway over TCP, and a gateway that isn't on the leader answers `REDIRECT`, after which the client reconnects and resends on its own. If a request times out inside the cluster, the gateway answers `UNKNOWN` (it may or may not have committed). The client sends it again, and because the service runs `Sessioned`, a resent write that already landed comes back `replayed=true` instead of being applied twice. The exit codes form a contract: `0` success, `1` the request failed (retrying might help), `2` bad arguments, including `validate()` refusals (retrying never helps). See [Run a gateway](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/run-a-gateway.md) and [the remote protocol](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/remote-protocol.md).

Your client already has `receive` / `ship` / `on-hand`, with `--linearizable` and `validate()` before connecting, from Step 5. What's left:
- decide the **exit code for a rejected ship**, the question we deferred in Step 5
- rewrite `scripts/demo.sh` for the ledger
- `make check`, because Step 7's proof goes stale once `src/` changes
- `make up FRESH=1`: the running cluster still holds skeleton `Put` / `Delete` entries, so it needs a wipe, not just `make restart-services`
- `make demo` → `PASS`

Do you want to do this yourself (I'll guide and review), or shall I do it?


## Turn 33

**Developer:** you do it and explain

**Tutor** (turns=16, denials=0):

Step 8 is done. Your stock ledger is running on a real 3-node cluster.

**The checks**
```
$ make check                  → exit 0 (21 tests, fmt, clippy, clippy on 1.89, determinism grep)
$ make down && make up FRESH=1  → node 0 is the serving leader; 3 services, 3 gateways
$ make demo
demo against 127.0.0.1:8500,127.0.0.1:8501,127.0.0.1:8502 (sku DEMO-1790277666-947655)
   receive 5            -> ok on_hand=5 position=128 replayed=false
   ship 3               -> ok on_hand=2 position=224 replayed=false
   ship 5 (only 2)      -> rejected insufficient on_hand=2 requested=5 position=320 replayed=false (exit 3)
   on-hand (unchanged)  -> on_hand=2
   ship 2 (to zero)     -> ok on_hand=0 position=416 replayed=false
   on-hand (sold out)   -> on_hand=0
PASS
$ make demo                   → PASS again (new SKU; positions continue at 800)
$ scripts/next.sh --json
{"step":9,"id":"failover","title":"Kill the leader","status":"todo","detail":["run: make kill-leader"]}
```
`make status` shows `commit=896` and `applied=896 lag=0` on all three nodes, so every replica applied both demo runs.

**The diff, hunk by hunk**

**1. `client.rs`, `enum Fail` → `Rejected` → exit 3.** *UC concept: the exit-code contract.*
- **0**: done
- **1**: the request failed (no leader yet, timeout), so a retry may help
- **2**: you typed it wrong
- **3**: the command committed and the ledger refused it

A retry loop should retry only on 1. The doc comment on `Fail` says exactly that.

**2. `client.rs`, `submit`: rejections printed as `key=value`.**
- `rejected insufficient on_hand=2 requested=5 position=320 …` replaces the Debug output.
- It keeps `position=`: a rejection is still a real log entry. Line 3 of the demo proves it, sitting at position 320 between two successful ships.
- *UC concept: a rejected command is committed and applied; it just changes nothing.*

**3. `client.rs`, TODO removed, `Reject` imported.** The `Sub` variants and `validate()`-before-connect you wrote in Step 5 were already what Step 8 asks for.

**4. `scripts/demo.sh`: a re-runnable demo.**
- `SKU="DEMO-<epoch>-<pid>"` gives each run its own SKU, and each run ends by shipping it to 0.
- So a second run can't collide with the first, and none of its stock is left in the ledger. (The `date` call is in the *client-side* script, which is fine. The ban on clocks applies only inside `apply`.)
- A new `expect_rejected` helper requires exit 3, so the demo proves the refusal path end to end, not just the happy path.
- *UC concept: the demo is also a drill building block, which is why it must be re-runnable.*

**5. `docs/app-design.md` §2: the exit codes.** Documented next to the commands they describe.

> **Insight:** look at `on-hand (unchanged) -> on_hand=2` right after the rejected ship. That line is your "fail without changing anything" requirement, proven on three replicas after going through consensus, not just in a unit test. Also note `on-hand` runs with `--linearizable`. Without it, the read could be served by a follower that hasn't applied position 320 yet. It would still say 2 here, because the rejection changed nothing, but after the `ship 2 (to zero)` a stale read might still say 2. The demo pins the strong read so it can never be flaky for that reason.

**⚠️ Something the tutor path won't tell you:** `scripts/snapshot-drill.sh` (lines 17 and 46) and `scripts/upgrade-drill.sh` (lines 40, 79 and 103) still call the client with the skeleton's `put` / `get`. They have no `TODO(app)` marker, so `next.sh` doesn't list them, but they will fail as they stand. I haven't changed them. I suggest updating each when its step comes up. The upgrade drill involves the one-way `upgrade pin`, and I'll never run it without your explicit go-ahead (hard rule 5).

The cluster is up on your build. **Next: Step 9, Kill the leader** (`make kill-leader`). You'll watch leadership move and see the client follow the redirects. Say "what next?" when you're ready.


## Turn 34

**Developer:** what next?

**Tutor** (turns=2, denials=0):

You're on **Step 9 of 13, Kill the leader**, the last step of Part 1. `scripts/next.sh --json` reports `status: todo`, and one thing is missing:

- `run: make kill-leader`

**Why this step matters.** A write is *committed*, and only then acknowledged, once a majority (two of three nodes) has `fsync`ed it. When the leader dies, the followers stop hearing from it, and after a randomized 150–300 ms timeout one of them asks for votes. A node votes only for a candidate whose durable log is at least as up to date as its own. Since every acknowledged write is on a majority, any winner already holds all of them. The new leader serves nothing until its "new term" marker commits. The client finds the dead gateway gone, moves to another one, and resends any in-flight write, which the session then answers as `replayed` or applies exactly once. See [Architecture, § Control plane](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/ARCHITECTURE.md#control-plane).

`make kill-leader` SIGKILLs the leader's node and service, waits for a new leader, runs **your ledger demo** against it, and restarts the old node, which should rejoin as a follower. The cluster is already running your build (node 0 leads, `commit=896` on all three nodes), so nothing needs rebuilding first.

Do you want to do this yourself (I'll guide and review), or shall I do it?


## Turn 35

**Developer:** I'll do it — guide me

**Tutor** (turns=1, denials=0):

The cluster is already running, so you can skip `make up`.

Your first step is to run **`make status`** and find two things, so you have a baseline to compare against after the kill:

1. **Who leads right now?** Look for `role: leader=true can_serve=true` and note the node number and the `term=` value.
2. **The commit position:** the `log: commit=` line. It should match on all three nodes.

For each, think about what you expect it to look like after the leader dies. Which nodes could win, and should the term number change?

Paste those lines, or just tell me the leader, the term and the commit position, and then we'll run the kill.


## Turn 36

**Developer:** node 0 leads, term 1, commit 896 on all three. i guess node 1 or 2 wins and term goes to 2?

**Tutor** (turns=1, denials=0):

Both predictions are right, with one nuance each:

- **Node 1 or 2 wins.** Both have exactly the same durable log (896), so either one's vote would go to the other. What decides it is the **randomized election timeout**: whichever follower times out first asks for votes first, and usually wins. You can't predict which beforehand, and that's by design.
- **The term goes to *at least* 2.** Each election attempt bumps the term. Usually the first attempt wins and you'll see `term=2`. If both followers time out at nearly the same moment, they split the vote, both give up, retry, and you'd see `term=3`. That's rare with the 150–300 ms spread, but not a bug.

A third prediction to check: **the commit position will be above 896 afterwards.** The new leader appends its "new term" marker, and the drill runs your demo again: receive, ship, a rejected ship, and so on.

Your next step is to run:
```
make kill-leader
```
It SIGKILLs node 0 and its service with no clean shutdown (that's the point), waits for a new leader, runs the demo through the surviving gateways, and restarts node 0, its service and its gateway. Paste the output; the lines about the election and the demo are the interesting ones.


## Turn 37

**Developer:** leader is node 0; killing it (SIGKILL) / stopped service0, node0, gateway0 / node 1 is the new leader / demo: receive 5 -> ok on_hand=5 position=928, ship 3 -> on_hand=2 pos 1024, ship 5 rejected pos 1120, on-hand 2, ship 2 -> 0 pos 1216, on-hand 0, PASS / restarting node 0, started node0 service0 gateway0 / PASS

**Tutor** (turns=2, denials=0):

The drill passed, and `scripts/next.sh` has recorded it:
```
{"step":10,...,"part1_complete":true,"part1_just_completed":true, ...}
```

Your output confirms all three predictions:

| prediction | result |
|---|---|
| node 1 or 2 wins | **node 1** won; its election timer happened to fire first |
| the term goes up | not shown in the drill output, so we'll check it next |
| commit goes above 896 | the first demo write landed at **928** |

That **928** is worth a closer look, because it shows the new-term marker. Before the kill, the log ended at 896. Your demo commands are 96 bytes apart (928 → 1024 → 1120 → 1216). If nothing had been written in between, the first write would have landed at 896, but it landed at 928. That leaves a 32-byte entry in between, which fits the **"new term" marker** that node 1 had to commit before it could serve anything. That size is my inference from the positions; I haven't checked it in the log.

Also look at `ship 5 rejected pos 1120` followed by `on-hand 2`, on a *new* leader. The rejection ran against state that node 1 rebuilt from the replicated log. It didn't come from node 0's memory, which was killed.

Your next step is to run **`make status`** again and check the step's last claims:
1. **Which node leads now, and in what term?** Is it `term=2`, or higher because of a split vote?
2. **Node 0's role now.** Did it get its leadership back, or did it rejoin as a follower?
3. **Commit and `applied` on node 0.** Has it caught up to the same position as the other two, even though it was dead while the demo's writes were committed?

Tell me what you see.


## Turn 38

**Developer:** node 1 leader, term=6 on all three. node 0 is a follower now, leader_hint=1. commit 1312 everywhere, applied=1312 lag=0 on all three services. term 6 though, not 2?

**Tutor** (turns=3, denials=0):

Your `make status` confirms everything else the step promised: node 0 rejoined as a **follower** (`leader_hint=1`), leadership didn't move back to it, and it caught up to **commit 1312 / applied 1312** even though it was dead while those writes were committed.

**Why term 6?** Here's what the logs show and what they don't:

```
node0  became_leader    term=1                ← start of the cluster
node2  became_follower  term=6   …732764709798
node1  became_leader    term=6   …732770688210   base=896
node1  serving_changed  term=6   can_serve=true   …732867729233
node0  became_follower  term=6                ← node 0 restarted, rejoins
```

- **What's certain:** terms 2 to 5 were election rounds that **ended without a leader**. No node ever logged `became_leader` or `became_follower` for them. The first term anyone settled on was 6.
- **What the logs don't say is *why*.** At `info` level, these node logs record only role changes, not individual vote requests. So I can't tell you from this evidence whether those four rounds were split votes, candidates timing out before the SIGKILLed node's absence was confirmed, or something else. Split votes are the textbook cause, but four in a row with only two candidates would be unusual. I'd rather call it **unexplained** than make up an answer.
- **What it costs: nothing, for safety.** A term is just a counter that makes every election unique. Skipped terms don't lose data or change which writes survive. The vote rule ("only for a log at least as up to date as mine") is what protects your writes, and that held: node 1 became leader with `base=896`, exactly the committed end of the log.

The timestamps give you the real availability cost of this failover. It took **about 97 ms** from node 1 becoming leader (`…732770`) to `can_serve=true` (`…732867`), which is the time to commit its new-term marker. The time from the SIGKILL to the election isn't in these logs, so the full outage window is unknown. If you want to dig in, run `make kill-leader` a couple more times. If the term keeps jumping by about 5, it's systematic and worth asking UC about; if it varies (+1, +2, …), it's election timing.

That covers step 4 of **Do it yourself** as well: node 0's log (line 15) shows it rejoining as `became_follower term=6`.

---

🎉 **Part 1 is complete.** `scripts/next.sh` reports `"part1_complete": true`. You've gone from the skeleton to your own replicated stock ledger:
- designed with byte budgets
- `apply` deterministic and reviewed
- property-tested for replica agreement and snapshot round-trips
- driven through the gateways
- surviving the loss of its leader without losing a write

**Part 2, to production, starts with Step 10, Snapshots and purge** (`make snapshot-drill`). One warning before you start: as I flagged in Step 8, `scripts/snapshot-drill.sh` still uses the skeleton's `put` / `get`, so it has to be updated for `receive` / `on-hand` before the drill can pass. Say "what next?" when you're ready.

