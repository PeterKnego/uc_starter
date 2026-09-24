# What next?

**How to use this file.**
1. Run `make next`. It inspects the repo and tells you which step you are on. It never guesses from memory.
2. Or ask your agent "what next?". Agents run `scripts/next.sh --json` and read the step named in its output.
3. Every step has the same six parts: Goal, Why, Do it yourself, Ask the agent, Done when, Common mistakes.
4. Do a step yourself, or ask the agent and review what it did. Both end at the same check.
5. To skip a step on purpose, run `make skip STEP=<id>`. The step ids are in `scripts/next.sh --list`.

Part 1 gets your own app running on a local three-node cluster. Part 2 takes it
to production: snapshots, monitoring, a safe upgrade, and real machines.

## Part 1 — your first working app

Part 1 is finished on *this machine* once `make next` first reports a Part 2
step. It prints "Part 1 complete" and records that under `.uc/state/`, which is
not committed. A teammate's fresh clone re-proves the steps that only a machine
can show (the running cluster, the demo, the failover). After Part 1, editing
code never sends you back. `make next` adds a *note* that an earlier proof is
stale, and you re-run it when it suits you.

### Step 1 — Environment
<!-- step: env -->

**Goal.** Get a Linux shell with Rust and the verified ultima_cluster binaries in `.uc/bin`.

**Why.** An ultima_cluster (UC) node runs on Linux only, on x86-64 or aarch64.
The node, your service and local clients talk through file-backed shared memory
with futex wakeups. On macOS or Windows you work inside the devcontainer
(README.md § Devcontainer), which is a Linux box. You never build UC itself.
`make bins` downloads the release named in `UC_VERSION` and checks it against the
release's `SHA256SUMS` before installing anything. If `cosign` is installed, it
also checks the signature, pinned to the GitHub workflow that built the release.
A checksum only proves the download is complete. The signature proves where the
file came from. See
[the quickstart, § 1](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/QUICKSTART.md#1-download-it-and-verify-it)
and [Limits](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/limits.md).

**Do it yourself.**
1. On macOS or Windows, open this project in its devcontainer and run everything below inside it.
2. Check Rust: `cargo --version`. If it is missing, install rustup. `rust-toolchain.toml` picks the version for you.
3. Optional: install `cosign`, so `make bins` checks the signature as well as the checksum.
4. `make bins`. It ends by printing the `uc2-node` version, which must match `UC_VERSION`.

**Ask the agent.** > "What's next? Check my environment and fix anything that's missing."

**Done when.** `make next` sees three things. The host is Linux. `cargo` is on the
`PATH`. `.uc/bin/uc2-node --version` runs and names the version in `UC_VERSION`.

**Common mistakes.**
- Running on macOS outside the devcontainer. The scripts refuse by name and point you at the devcontainer.
- Putting the cluster root under `/tmp`. `/tmp` is often RAM-backed, where `fsync` does nothing, so the nodes refuse it. The default root is `~/.uc-starter/<your-app>`. If you set `UC_ROOT`, point it at a real disk.
- Editing `UC_VERSION` by hand. The exact crate pins in `Cargo.toml` must move with it, and every UC minor release so far has been a flag day. Use `make uc-upgrade VERSION=<x>`.

### Step 2 — Run the skeleton
<!-- step: skeleton -->

**Goal.** Start the skeleton app (a small key-value registry) on a local three-node cluster and drive it.

**Why.** `make up` then `make demo` runs ten processes in four roles. Three
`uc2-node` daemons do consensus, replication and durability, and elect a leader
among themselves. Three copies of your service (`<your-app>-service`) each attach
to one node over shared memory. Each runs its own replica of your state machine
and applies the same commands in the same order. Three `uc2-gateway`s give
clients that cannot use shared memory a TCP front door. With one gateway per
node, a gateway on a follower can redirect a client to the leader. The tenth
process is the client, which `make demo` runs once per request. The start order
is fixed: all nodes, then a serving leader, then services, then gateways. Since
2.13.0 a service can attach only after its node has *joined* the cluster: it
knows a leader, has learned the commit position, and has applied the cluster's
own records up to it. Until then the attach is refused `NodeBooting` and waits
up to 10 s. See
[the quickstart, § 3](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/QUICKSTART.md#3-what-just-happened)
and [the state-machine contract](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md)
(§ Attaching).

**Do it yourself.**
1. `make up`. It builds your binaries, starts the nodes, waits for a serving leader, then starts the services and gateways.
2. `make demo`. It runs put, get, delete and get again through the gateways, and prints `PASS`.
3. `make status`. It runs `uc2ctl status` on every node. Find the leader (`leader=true can_serve=true`) and the commit position.
4. Logs are in `~/.uc-starter/<your-app>/logs/`, one file per process.
5. `make down` stops the cluster and keeps its state. `make up FRESH=1` starts over from an empty log.

**Ask the agent.** > "Run the skeleton and walk me through what each of the ten processes is doing."

**Done when.** `make demo` has passed once on this machine. Its first pass
records the skeleton proof.

**Common mistakes.**
- Port in use. Another cluster or app already holds a port in the band. `make up` refuses and names the port. Run `make down` in the other project, or set `UC_PORT_OFFSET=10`, or change `BASE_PORT` in `uc-app.env`.
- Starting a service before a leader exists. It is refused `NodeBooting`, waits 10 s, then exits. Start services through `make up`, or after `scripts/cluster.sh wait-leader`, never before the nodes.
- Stopping nodes before their services and gateways. `make down` stops services and gateways first, then nodes. Do the same if you stop processes by hand.

### Step 3 — SMR in five minutes
<!-- step: concepts -->

**Goal.** Understand the model your code runs inside, well enough to answer three questions.

**Why.** State machine replication makes several machines behave as one reliable
machine. The nodes agree on one thing only: the *order* of the commands in a log.
Every replica then applies that log, in that order, to its own copy of your state
machine. Because `apply` is deterministic, every copy ends in the same state. So
`apply` must never read a clock, use randomness, do I/O, or depend on `HashMap`
order. Two replicas that differ by one bit have forked silently. UC gives you
replicated stand-ins instead: `ctx.time_ns` is the leader's timestamp carried on
the command, and `ctx.ids()` mints ids derived from the log. The log is addressed
by byte **position**, not by entry number. `ctx.position` is the same on every
replica, which makes it the natural idempotency key. **Sessions**
(`Sessioned<S>` in the service, plus the gateway's session envelope) tag every
write with `(client_id, seq)`. A write sent again after a failover is answered
from a cache with `replayed=true` and is not applied twice. A **snapshot** is
your state written out at one log position. It lets a node that fell behind
install the state instead of replaying the whole log, and it lets the log be
trimmed. See
[State machine replication, explained](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/state-machine-replication-explained.md).

**Do it yourself.**
1. Read the linked explainer. It takes about ten minutes.
2. Read `src/state.rs` and find each rule above in its comments.
3. Answer the three check questions below, then open the answers and compare.
4. `make done STEP=concepts`.

The three check questions:
1. "why can't apply read the clock?"
2. "what does `replayed=true` mean?"
3. "what is a position?"

<details><summary>Answers</summary>

1. Every replica runs `apply` at a different wall-clock moment, and a rebuild
   replays the same command days later. A clock reading would give each copy a
   different result. `ctx.time_ns` is read once, by the leader, and carried on
   the command, so every replica sees the same value.
2. The same `(client_id, seq)` was already applied. This is usually a re-send
   after a failover or an `UNKNOWN` answer. `Sessioned` returned the cached
   response, and your `apply` did not run a second time.
3. A position is the byte offset of a command in the log. It is the same on
   every replica and it only grows. The commit, durable and append counters in
   `make status` are positions, and so is the `position=` the demo prints.

</details>

**Ask the agent.** > "Teach me SMR in five minutes using this repo's code, then ask me the three check questions."

**Done when.** `make done STEP=concepts` has recorded the step in `.uc-progress`.
Nothing in the repo can show that you understood it, so you record it yourself.

**Common mistakes.**
- Treating a query as if it went through consensus. A query is answered from *one* replica's local state and never enters the log. A plain (snapshot) read can be behind. Only a `--linearizable` read goes through the cluster's read barrier.
- Thinking the nodes agree on *state*. They agree on the order of commands. Identical state follows only because `apply` is deterministic.
- Putting side effects (an email, an HTTP call) in `apply`. They would run on every replica, and again on every replay. Side effects belong after commit, on the leader only.

### Step 4 — Design your app
<!-- step: design -->

**Goal.** Write down your commands, queries, state and size limits in `docs/app-design.md` before you write code.

**Why.** A **command** changes state. It goes through consensus and is applied on
every replica, in log order, forever. A **query** only reads, from one replica,
and is never stored. Every command must fit in one UDP datagram. At the baseline
every cluster starts from, the payload ceiling is 1344 B with wire crypto off and
1312 B with it on. `Sessioned` takes 16 B of that for its envelope, which leaves
1328 B / 1296 B for your encoded command. There is no chunking: a command that
does not fit is refused. A response is not limited to one datagram, but design it
to be bounded anyway. An unbounded "list everything" answer grows with your state
until it hurts. Last, list the determinism hazards you considered: clocks, ids,
iteration order, floats, integer overflow and I/O. A mistake is cheapest to fix
at this step. See
[the state-machine contract § Payload ceiling](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md#payload-ceiling)
and [Limits](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/limits.md).

**Do it yourself.**
1. Open `docs/app-design.md`. Each section is filled in for the skeleton registry, as a worked example.
2. Rewrite each section for your app: commands, queries, state, hazards, size bounds, snapshot and open questions.
3. For each command, work out its largest encoded size. Check that it fits under 1296 B, the crypto-on figure less the session envelope.
4. Delete each section's `<!-- TODO … -->` marker line once the section is yours. `make todo` lists every marker left in the project.

**Ask the agent.** > "Interview me about my app, then draft docs/app-design.md. Flag anything that won't fit one datagram or isn't deterministic."

**Done when.** No TODO marker is left in `docs/app-design.md`. The check
cannot judge your design. It only sees that you finished the note.

**Common mistakes.**
- Unbounded responses, such as a "list" or "scan" query that returns everything. Page it (a start key and a limit), or cap the count.
- Putting wall-clock times in commands without saying whose clock. A client's timestamp is an *input*, which is fine, but name it (`client_sent_ns`). The cluster's own time inside `apply` is `ctx.time_ns`.
- Designing a command that carries a large blob. It will not fit one datagram. Store the blob elsewhere and put a reference in the command.

### Step 5 — Commands
<!-- step: commands -->

**Goal.** Replace the registry's wire types in `src/commands.rs` with yours, and check each command in `validate()`.

**Why.** The typed tier encodes your enums with bincode, which writes an enum
variant as its *index*. So a variant's position in the enum is its wire tag.
Commands are stored in the log and replayed for as long as the cluster lives. If
you insert or reorder a variant, old log entries decode as a different command,
with no error. That was measured: a stored `Put(11,22)` came back as
`Delete(11)`. So you only ever append new variants at the end, and never reorder
fields. Once a real cluster has run a version, even an appended variant or field
is a change that needs Step 12's upgrade. `Command::validate()` runs in the
client *before* anything is sent, so an oversize command is refused at the door
with a clear message. See
[the state-machine contract](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md)
and [the change taxonomy](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/application-sdlc.md#the-change-taxonomy).

**Do it yourself.**
1. In `src/commands.rs`, rewrite `Command`, `Response`, `Query` and `QueryResponse` from your design note.
2. Set the `MAX_*` limits so your largest command stays under the ceiling. Rewrite `validate()` to check every variable-length field.
3. `cargo check` compiles the whole crate, so `src/state.rs`, `src/snapshot.rs` and `src/bin/client.rs` must compile too. Give their match arms a minimal body for now. Steps 6 and 8 do them properly, so leave their TODO markers in place.
4. Delete the TODO marker line in `src/commands.rs`. Run `cargo check`.

**Ask the agent.** > "Do step 5 for me from docs/app-design.md and explain the diff."

**Done when.** No TODO marker is left in `src/commands.rs`, and `cargo check`
passes.

**Common mistakes.**
- Reordering variants, or inserting one in the middle. The index is the wire tag. Append at the end.
- Forgetting `validate` for a new field. An unchecked string can push a command past the ceiling. The cluster then refuses it with a worse message than `validate` would give.
- Restarting services on your existing local cluster after replacing the enum. Its log still holds the skeleton's commands, and your new build would read them as your new variants. The local cluster is disposable: `make up FRESH=1`.

### Step 6 — State, apply and query
<!-- step: state -->

**Goal.** Write your state, `apply`, `query` and the snapshot projection in `src/state.rs` and `src/snapshot.rs`.

**Why.** `apply` runs on every replica, for every committed command, in log
order. The same state plus the same command must give the same result
everywhere, forever. Time comes from `ctx.time_ns`: the leader's stamp on the
command, the same on every replica, and never going backwards. Ids come from
`ctx.ids()`. It derives each id from the command's position, your state
machine's name, and a counter that restarts at zero in every `apply` call. So a
replica rebuilt from a snapshot mints the same ids as one that replayed the
whole log. `last_applied()` tells the framework where to resume after a restart.
Set it to `ctx.position` on every path through `apply`; the skeleton does this
after the `match`. See
[FSM identity and deterministic IDs, explained](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/uc2-fsm-identity-and-deterministic-ids-explained.md).

**Do it yourself.**
1. In `src/state.rs`, replace `State` with your data. Use `BTreeMap`/`BTreeSet` and integers.
2. Write one `apply` arm per command and one `query` arm per query. Keep `self.last_applied = Some(ctx.position)`.
3. In `src/snapshot.rs`, rewrite `project()`: one line per record, in sorted order. Diff replay (Step 12) compares this text.
4. Delete the three TODO marker lines in `src/state.rs` and the one in `src/snapshot.rs`. Run `cargo test --lib` and `scripts/lint-determinism.sh --all`.

**Ask the agent.** > "Do step 6 for me and point out every determinism hazard you avoided."

**Done when.** No TODO marker is left in `src/state.rs` or `src/snapshot.rs`,
and `cargo test --lib` passes.

**Common mistakes.**
- Using `HashMap` or `HashSet`. Their iteration order differs from process to process, so anything that iterates them (a snapshot, a projection, a list answer) differs between replicas. `make lint` rejects them.
- Plain `+` on integers. It panics on overflow in a debug build and wraps in a release build, so two replicas built differently diverge. Use `checked_add` (and answer with an error response) or `wrapping_add`.
- Panicking in `apply`. A panic stops the apply thread and the service exits for a restart. When it replays the same command, it panics again. Answer bad input with an error *response*, never `unwrap()`.
- Reading the clock or an RNG "just for logging". Clippy and `scripts/lint-determinism.sh` reject both in `src/state.rs`, `src/commands.rs` and `src/snapshot.rs`.

### Step 7 — Tests that cover your commands
<!-- step: tests -->

**Goal.** Make the tests exercise every command, and pass `make check`.

**Why.** `tests/determinism.rs` is a property test. It generates random command
sequences from `arb_command`, applies them to two fresh state machines, and
asserts identical responses and identical projections. It also snapshots at a
random point, installs the image in a third machine, continues from there, and
asserts it ends where an uninterrupted run ends. That shows your `apply` behaves
as a pure function within one build, and that your snapshot round-trips. It
*cannot* show that your next version handles the log this version wrote. That is
a cross-version property, and Step 12's diff replay checks it. Nor can it catch
a hazard that only appears across two processes, such as hash order seeded per
process; `make lint`'s bans cover that. UC's own verification record says it
plainly: your state machine's determinism is your responsibility. See
[Verification, § 11](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/VERIFICATION.md#11-what-is-not-verified).

**Do it yourself.**
1. In `tests/determinism.rs`, give `arb_command` one strategy per command, with small key spaces so commands collide.
2. Rewrite `tests/state.rs` and `tests/snapshot.rs` for your commands: one test per command, plus the `validate` refusals.
3. Update `tests/cli.rs` if your client's subcommands changed.
4. Delete the TODO marker line in `tests/determinism.rs`.
5. `make check`. It runs `cargo test`, then `make lint`: fmt, clippy, clippy on the 1.89 toolchain (the minimum supported Rust), and the determinism grep. If 1.89 is missing: `rustup toolchain install 1.89.0 --component clippy`.

**Ask the agent.** > "Extend the tests to cover every command I added, then run make check and fix what fails."

**Done when.** No TODO marker is left under `tests/`, and `make check` has
passed against the current code. The proof hashes all of `src/`, `tests/`,
`Cargo.toml` and `Cargo.lock`. Any edit there after the last `make check` makes
this step **stale** until you run it again.

**Common mistakes.**
- Not extending `arb_command`. The property test then never runs your new arm, and passes without testing it.
- Using a key space so large that commands never touch the same record. Overwrites and deletes are where the bugs hide.
- Running `cargo test` and assuming the step is done. Only `make check` records the proof, and it also runs the lints.

### Step 8 — Client and demo for your commands
<!-- step: client -->

**Goal.** Give the remote client one subcommand per command and query, and make `make demo` prove each one on the cluster.

**Why.** The client never talks to a node directly. It connects to the gateways
over TCP, and you give it *every* gateway's address, not the leader's. A gateway
that is not on the leader answers `REDIRECT`, and the client reconnects and
re-sends on its own. When the leader changes, the gateways push
`LEADER_CHANGED`. Every request ends in exactly one answer or one named error. If
a request times out inside the cluster, the gateway answers `UNKNOWN`: it may or
may not have committed. With `resend_on_unknown` (on by default) the client sends
it again. The service runs `Sessioned` and the gateway's envelope is on, so a
re-sent write that already landed comes back `replayed=true` instead of applying
twice. The client exits `0` on success, `1` when the request failed, and `2` for
bad arguments, `validate()` refusals included. See
[Run a gateway](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/run-a-gateway.md)
and [the remote protocol](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/remote-protocol.md).

**Do it yourself.**
1. In `src/bin/client.rs`, write one `Sub` variant per command and query. Build the `Command` and call `validate()` before connecting. Print each response on one line.
2. Give read subcommands a `--linearizable` flag, like the skeleton's `get`.
3. In `scripts/demo.sh`, rewrite the `expect` lines for your commands. Keep the shape: a description, a substring the output must contain, then the arguments.
4. Delete the TODO marker lines in `src/bin/client.rs` and `scripts/demo.sh`.
5. `make check`. You edited `src/`, so Step 7's proof is stale until you re-run it.
6. If you changed `Command` since this cluster was started, start the local cluster fresh: `make up FRESH=1`.
7. `make restart-services`. It rebuilds, then restarts your service on every node.
8. `make demo`.

**Ask the agent.** > "Do step 8 for me: client subcommands and demo lines for every command, then run the cluster demo."

**Done when.** No TODO marker is left in `src/bin/client.rs` or
`scripts/demo.sh`, and `make demo` has passed against the current code. The proof
hashes `src/`, `Cargo.toml` and `Cargo.lock`, so a later code edit makes it stale.

**Common mistakes.**
- Forgetting `make restart-services` after a rebuild. The cluster keeps running the old service binary. The new client encodes commands the old service decodes differently, and fails with "client and service built from different code?".
- Giving the client only the leader's gateway. Leadership moves. Give it all three and let redirects do their job.
- Treating exit `1` like exit `2`. Retrying a bad argument never helps. Retrying a failed request (no leader yet, a timeout) might.

### Step 9 — Kill the leader
<!-- step: failover -->

**Goal.** Kill the leader node mid-run, and watch the cluster elect a new one and keep your data.

**Why.** A write is *committed* once a majority of nodes (two of three) has
written it to disk with `fsync`, and only then is it acknowledged. When the
leader dies, the followers stop hearing from it. After a randomized timeout
(150–300 ms by default) one of them asks for votes. A node votes only for a
candidate whose durable log is at least as up to date as its own. Every
acknowledged write is on a majority, so any winner already holds all of them.
The new leader first appends a "new term" marker, and serves nothing until that
marker commits. The client's next request finds the old leader's gateway gone
and moves to another gateway. A write that was in flight is sent again, and the
session answers it `replayed` or applies it once. See
[Architecture, § Control plane](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/ARCHITECTURE.md#control-plane).

**Do it yourself.**
1. `make up` if the cluster is not running, then `make status` to see who leads.
2. `make kill-leader`. It SIGKILLs the leader's node and service, waits for a new leader, runs the demo against it, then restarts the old node, service and gateway.
3. `make status`. The old leader is back as a follower, at the same commit position.
4. Read the old leader's node log in `~/.uc-starter/<your-app>/logs/` to see it rejoin.

**Ask the agent.** > "Run the failover drill and explain, from the logs, which node won the election and why the demo's writes survived."

**Done when.** `make kill-leader` has passed against the current code. The proof
hashes `src/`, `Cargo.toml` and `Cargo.lock`.

**Common mistakes.**
- Reading a follower's state with a snapshot read and calling it stale data. A plain read is served by whichever replica answers, and may be slightly behind. That is the documented trade. Use `--linearizable` when a read must see every acknowledged write.
- Killing two of the three nodes and expecting writes. With no majority there is no commit, so writes wait until a second node is back. That is the cluster being correct, not broken.
- Expecting the old leader to lead again when it returns. It rejoins as a follower. Leadership only moves by election.

## Part 2 — to production

Part 2's drills need the local cluster running (`make up`). If a step does not
apply to your app, `make skip STEP=<id>` records that.

### Step 10 — Snapshots and purge
<!-- step: snapshots -->

**Goal.** Take a coordinated snapshot, SIGKILL a service, and watch it rebuild to the same state.

**Why.** Your service does not decide when to snapshot. A snapshot is a
**coordinated instant**: the leader appends a `SNAPSHOT` command to the log, and
at the position **P** where it ends, every state machine on every node freezes,
having applied exactly everything below P. P is an **exclusive** frontier: the
image covers the commands strictly *below* P. That is why `install_snapshot`
returns P but restores the image's own `last_applied` cursor. Claiming P would
skip the next command. A node holds the *complete set* at P once every state
machine and the cluster's own state have written their files at P, and only then
may the journal below P be purged. **Purge is off by default.** This template
turns it on for the local cluster, in the `[purge]` section of the generated
`node.toml`. A node or service that has fallen below the purged part installs
the snapshot, then replays the log above it. While the journal still reaches
back far enough, a restarted service simply replays the journal. See
[The cluster FSM, explained § Instants](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/uc2-cluster-fsm-explained.md#instants-one-position-one-set)
and [Keep the journal from growing without bound](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/bound-journal-growth.md).

**Do it yourself.**
1. `make up` if needed.
2. `make snapshot-drill`. It writes a value, commands an instant (`uc2ctl snapshot`), waits until all three nodes hold the complete set at P, SIGKILLs one service, restarts it, and reads the value back linearizably.
3. `scripts/cluster.sh snapshot-show 0` shows each state machine's newest artifact and the complete `set=`.
4. For a cadence instead of on-demand instants: `UC_SNAPSHOT_INTERVAL=<bytes> make up FRESH=1`.

**Ask the agent.** > "Run the snapshot drill and show me, from the service log, whether the restarted service installed the snapshot or replayed the journal."

**Done when.** `make snapshot-drill` has passed on this machine.

**Common mistakes.**
- Expecting purge to show on a tiny write volume. Purge drops whole journal segments (4 MiB each here, keeping 1 MiB below the snapshot), so a few demo writes purge nothing. Write a few MiB after an instant, then watch the journal's first retained position rise: `scripts/cluster.sh metrics 0 | grep uc2_archive_first_base_bytes`.
- Reporting P from `last_applied()` after an install. P is exclusive, so the framework would skip the first command above it. Restore the cursor stored in the image, as `src/snapshot.rs` does.
- Changing the shape of `State` without bumping `IMAGE_VERSION` and keeping a reader for the old image. A node that installs an old artifact then fails. On a running cluster that is an upgrade (Step 12).
- Forgetting that `freeze()` runs on the apply thread. This starter clones the whole state there, which is fine while it is small. A large state stalls commit during every instant.

### Step 11 — Observe the cluster
<!-- step: observe -->

**Goal.** Read the health, readiness and key metrics of every node, and know where the alert rules are.

**Why.** Each node's `[metrics]` endpoint serves three paths. `/healthz` answers
"should this process be restarted?": every agent is alive and the node's
heartbeat is fresh. `/readyz` answers "should traffic be routed here?". It is
role-aware: a leader also needs `can_serve` (elected *and* its new-term marker
committed), and every node needs a fresh heartbeat from its service. So a node
whose service is down reads *not ready* while the cluster itself is healthy.
Readiness keys on `can_serve`, never on the leader flag. `/metrics` is
Prometheus text. The alert rules in `.uc/packaging/prometheus/`, copied from the
release by `make bins`, fire on conditions such as no leader, replication
stalled, a service absent or wedged, and snapshots that never complete. See
[Monitor a cluster](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/monitor-a-cluster.md#the-probe-endpoints).

**Do it yourself.**
1. `make up` if needed.
2. `make observe`. It checks `/healthz` and `/readyz` on every node, looks for the key series, and checks that exactly one node reports leader.
3. `scripts/cluster.sh metrics 0 | grep '^uc_service'`. These are your state machine's series: applied position, lag, attached.
4. Stop one service (`scripts/cluster.sh stop service 1`) and fetch node 1's `/readyz` (port `BASE_PORT + 201`). Within a few seconds it turns 503. Start the service again: `scripts/cluster.sh start service 1`.
5. Read the rule file: `.uc/packaging/prometheus/uc2-alerts.yml`.

**Ask the agent.** > "Run make observe, then tell me which three alerts should page me first for this app, and why."

**Done when.** `make observe` has passed on this machine.

**Common mistakes.**
- Alerting on the leader flag. Leadership moves by design, and a just-elected leader cannot serve yet. Page on `Uc2NoLeader` and `Uc2LeaderNotServing`, and route traffic on `/readyz`.
- Reading per-peer metrics on a follower. Only the leader receives follower reports, so a follower's per-peer series always read 0.
- Exposing `/metrics` on a public address. It has no authentication. Bind it to loopback or a private network.

### Step 12 — Your first FSM upgrade
<!-- step: upgrade -->

**Goal.** Change what a command does, prove the change is exactly what you meant, and roll it out with a pinned upgrade.

**Why.** **The pin is a one-way door: there is no unpin, and the only rollback is the backup taken before the pin, restored on every node.**
Your log is replayed for as long as the cluster lives, so a behaviour change
cannot simply be swapped in. First, bump `FSM_VERSION` in `src/identity.rs`: any
change to what `apply` does is a new version. Second, prove the change. Capture a
*corpus* (one snapshot plus a span of real log) with the old build. Declare in
`upgrade/intent.toml` which commands you changed and which outputs should differ.
`uc2-diffreplay` replays the corpus through both builds and fails on any
difference you did not declare, and on any declared one it did not see. Third,
roll out with the pin procedure. Take a coordinated instant P and back up every
node. Pin the row: from then on every node refuses the old binary by name, and
the new one installs the snapshot at P before it replays anything. Stop *every*
old service before starting any new one. A rolling swap is unsafe: a leader on
the new version can acknowledge a command an old replica cannot apply. See
[Upgrade an application](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/upgrade-an-application.md)
and [Diff replay an FSM change](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/diff-replay.md).

**Do it yourself.**
1. `make up`, then `make diffreplay`. It installs `uc2-diffreplay` into `.uc/cargo`.
2. `make corpus`, *before* you change any code. It takes an instant, writes a few commands, exports the corpus to `upgrade/corpus/`, and keeps the current service binary in `upgrade/old/`. `make next` asks you to bump `FSM_VERSION` first; capture the corpus before you do.
3. Make the behaviour change. Bump `FSM_VERSION` in `src/identity.rs`, for example to `pack_version(1, 1, 0)`. If the shape of `State` changed, bump `IMAGE_VERSION` in `src/snapshot.rs` and keep reading the old image.
4. Edit `upgrade/intent.toml`. Map each command's tag byte (its variant index, after the 16-byte session envelope) to an arm name. List the arms you touched. Add one `[[expect]]` per output you meant to change.
5. `make upgrade-check`, until it prints PASS. On FAIL, `upgrade/report.json` names each problem: `Undeclared`, `Unexplained` or `Absent`.
6. `make upgrade-drill`. It shows both versions and asks you to type `PIN`. Then it takes the instant, backs up every node, pins, stops every service, starts the new build everywhere, and checks that a value written before the upgrade still reads back.

**Ask the agent.** > "Walk me through my first upgrade: draft intent.toml from my diff, run upgrade-check, and stop before the pin so I can confirm it."

**Done when.** `FSM_VERSION` is no longer `pack_version(1, 0, 0)`, and both
`make upgrade-check` and `make upgrade-drill` have passed on this machine.

**Common mistakes.**
- Pinning before backing up. A backup taken after the pin carries the pin, so it cannot take you back. The drill backs up first. On a real cluster, also copy the backups off the nodes.
- Starting any new service before every old one is stopped. In a mixed row, a new leader can acknowledge a write that an old replica cannot apply. Stop them all, then start them all.
- Running `make restart-services` after bumping `FSM_VERSION` but before the pin. Nothing sanctions the new build yet. If the journal below the snapshot has been purged, the new build is refused by name, because the snapshot was built by the old version. If it has not, the new build quietly rebuilds from the whole log under the new code, which is exactly what the pin exists to prevent. Either way the drill no longer finds an old version to upgrade from. Use `make upgrade-drill`. If it already happened, check out the old code, run `make restart-services`, and start again from step 3.
- Skipping the corpus because "the change is small". Diff replay is how you learn that the change is *only* what you meant.

### Step 13 — Deploy to three machines
<!-- step: deploy -->

**Goal.** Package your app with the UC binaries and run it on three Linux machines under systemd.

**Why.** Three processes on one host are a majority of *processes*, not of
failure domains: one power cut takes all three. A real cluster runs one node per
machine, with its service and gateway beside it and its instance directory on a
real disk. Every `node.toml` must state two choices, or the node refuses to
start. `[crypto]` is cleartext or authenticated encryption between nodes, all or
nothing per cluster; turn it on for any network you do not own. `[admin]` says
how membership and upgrade commands are authorised; `hmac` signs them, but
covers the whole cluster only when crypto is on too. The packaged systemd units
encode the start order and bind each gateway and service to its node
(`BindsTo=`), so they stop when the node stops. `[[members]]` must be identical
on every host, and each node's `bind` must be exactly its own address in that
list. See
[Run a cluster on real hosts](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/run-a-cluster.md)
and [Encrypt traffic between nodes](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/encrypt-node-traffic.md).

**Do it yourself.**
1. `make package HOSTS=10.0.0.1,10.0.0.2,10.0.0.3`, with your three addresses. It writes `dist/<your-app>-<version>-<arch>.tar.gz`: the binaries, the systemd units, and a `node.toml` and `gateway.toml` per host.
2. Generate the admin key and the crypto key material as `docs/how-to/deploy.md` describes. UC has no command yet that derives the crypto allowlist, so read that part first.
3. On each host, following `docs/how-to/deploy.md`: install the binaries, that host's configs under `/etc/uc2/`, and the units. Start the node on every host, then the services, then the gateways.
4. On a node host, check `uc2ctl status` and `/readyz`. Point your client at all three gateways.
5. `make done STEP=deploy`.

**Ask the agent.** > "Package the app for these three hosts and give me the exact per-host install commands, in order."

**Done when.** A `dist/*.tar.gz` bundle exists, and you have recorded the
deployment with `make done STEP=deploy`.

**Common mistakes.**
- Running all three nodes on one host and calling it HA. It survives a process crash, not a machine failure.
- Setting a node's `bind` to `0.0.0.0`, or to anything but its own `[[members]]` address. The node refuses to start. Use the exact address its peers reach.
- Editing `[[members]]` to change membership on a running cluster. After the first boot it is only a seed. Add or remove members with `uc2ctl`.
- Leaving `[crypto] enabled = false` on a network you do not control. Node traffic, and forwarded admin requests, cross it in the clear.
