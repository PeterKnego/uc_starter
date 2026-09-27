# Concepts

The model your code runs inside, in the order you meet it. Each section ends
with the upstream document that covers it in full. For the guided version, see
`TUTORIAL.md` Step 3.

## The log and positions

Three nodes elect a leader. The leader appends every command to one log and
replicates it; a command is **committed** once a majority of nodes has written
it to disk. Committed commands never change and never move.

The log is addressed by byte **position**, the absolute offset of a command in
the log, not by entry number. A position is the same on every replica and only
grows. `ctx.position` in `apply` is that value, which makes it a natural
idempotency key and a stable id for "the command that did this". The
`commit=`, `durable=` and `position=` numbers that `make status` and the client
print are positions.

Upstream: [State machine replication, explained](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/state-machine-replication-explained.md).

## Deterministic apply

Every replica applies the committed log, in order, to its own copy of your
state machine, and a restarted service replays it again later. The nodes agree
on the *order* of commands, not on state: identical state follows only
because `apply` gives the same result for the same state and command, on every
machine, forever. A replica that differs by one bit has forked, and nothing in
the consensus layer can see it.

So `apply` (and `on_timer`, `freeze`, `stream_snapshot`) must not use:

| hazard | why | use instead |
|---|---|---|
| `SystemTime::now`, `Instant::now` | every replica runs at a different moment | `ctx.time_ns`, the leader's stamp carried on the command |
| an RNG, UUIDs from an RNG | different on every replica | `ctx.ids()`, ids derived from the position |
| `HashMap` / `HashSet` iteration | order differs per process | `BTreeMap` / `BTreeSet` |
| floats you compare or store | results can differ by build and platform | integers, fixed-point |
| plain `+` on integers | panics in debug, wraps in release | `checked_add` (answer with an error) or `wrapping_add` |
| a panic or `unwrap` on bad input | the service fail-stops, and panics again on replay | an error response |
| file, network or environment access | differs per host; side effects repeat on replay | put it in the command, or do it after commit on the leader |
| inserting or reordering enum variants or fields | the variant index is the wire tag; old log entries change meaning | append at the end |

`clippy.toml` bans the clock calls and the hash collections in this crate,
and `scripts/lint-determinism.sh` (part of `make lint`) greps the
state-machine files for clocks, RNGs, hash collections, floats, I/O and
environment reads. Neither can see overflow, panics or a reordered enum; the
`determinism-review` checklist in the agent kit covers those.

Upstream: [the state-machine contract](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md)
and [FSM identity and deterministic ids, explained](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/uc2-fsm-identity-and-deterministic-ids-explained.md).

## Commands and queries

A **command** changes state. It goes through consensus, is stored in the log
and is applied on every replica. A **query** only reads. It is answered from
*one* replica's local state and never enters the log.

A query comes in two strengths, chosen by the caller (`get --linearizable` in
this project's client):

- **snapshot read** (the default here): answered by whichever replica you
  reached, from its own state. Fast, and may lag the leader slightly.
- **linearizable read**: passes the cluster's read barrier, a quorum round
  trip, and waits for the replica to catch up, so it reflects every write
  acknowledged before the read began.

`query` itself is the same method either way; the framework does the routing.

Upstream: [Linearizable read path](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/read-path.md).

## Sessions and `replayed`

A client that loses its connection, or gets `UNKNOWN` ("may or may not have
committed") back, sends the write again. Without help, a write that already
landed would apply twice.

This project runs `Sessioned<Fsm>` in the service, and its gateways add a
16-byte session envelope (`client_id`, `seq`) to every write. `Sessioned`
remembers recent answers per client. A write seen before comes back from that
cache with `replayed=true`, and your `apply` does not run again. The client
prints `replayed=` on every write.

The session table is replicated state, so its settings (`SessionConfig`)
must be identical on every replica.

Upstream: [the state-machine contract](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md)
(§ `Sessioned<S>` wraps either tier) and [the remote protocol](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/remote-protocol.md).

## Snapshots

A snapshot is your state written out at one log position. It lets a node that
fell behind install state instead of replaying the whole log, and it lets the
journal below it be purged.

- **Instants.** Your service does not decide when to snapshot. The leader
  appends a `SNAPSHOT` command (`uc2ctl snapshot`, or a byte cadence); at the
  position **P** where it ends, every state machine on every node freezes
  together. A node holds the *complete set* at P once every row and the
  cluster's own state have written their artifacts.
- **Exclusive frontier.** The image at P covers commands strictly *below* P.
  `install_snapshot` returns P but restores the image's own `last_applied`
  cursor; reporting P would skip the next command.
- **Purge is off by default** in UC. This project turns it on for the local
  cluster and the deploy bundle (`[purge]` in `node.toml`), so the journal is
  bounded once an instant completes.
- `freeze()` runs on the apply thread and stalls commit while it runs. Keep it
  cheap; `docs/how-to/change-the-state-shape.md` shows how.

Upstream: [the state-machine contract § Snapshots](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md#snapshots-the-instant-the-envelope-and-the-exclusive-frontier)
and [The cluster FSM, explained § Instants](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/uc2-cluster-fsm-explained.md#instants-one-position-one-set).

## The payload ceiling

One command must fit in one UDP datagram. At the baseline every cluster starts
from, the payload ceiling is **1344 B** with wire crypto off and **1312 B**
with it on. The session envelope takes 16 B of that. A cluster whose network
paths all carry jumbo frames can discover a higher ceiling, but design for
the baseline. There is no chunking: a command that does not fit is refused.
`Command::validate()` checks your limits in the client, before anything is
sent. Responses are not limited to one datagram, but keep them bounded.

Upstream: [the state-machine contract § Payload ceiling](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md#payload-ceiling)
and [Limits](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/limits.md#hard-limits).

## Identity: `NAME` and `VERSION`

Your state machine's identity is in code, in `src/identity.rs`:

- **`FSM_NAME`** (`StateMachine::NAME`). The node's `node.toml` lists the same
  name under `[services] names`, and the service attaches by it. Change it
  after a cluster has run and the node refuses the service by name.
- **`FSM_VERSION`** (`StateMachine::VERSION`). The version of what `apply`
  *does*. Every snapshot artifact is stamped with the version that built it,
  and an ordinary install refuses an artifact built by a different version.

Why a behaviour change needs an upgrade: the log is replayed for as long as
the cluster lives. A new `apply` replaying old commands would compute a
history the cluster never had, and a mix of old and new replicas would
diverge. So any change to what `apply` or `query` returns or stores is a new
`FSM_VERSION`, proven with diff replay and rolled out with a **pinned
upgrade**: every node installs the snapshot at one origin instant and replays
only what comes after, and the old binary is refused by name from then on. A
pin is a one-way door. `TUTORIAL.md` Step 12 walks through it.

Upstream: [Upgrade an application](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/upgrade-an-application.md)
and [the change taxonomy](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/application-sdlc.md#the-change-taxonomy).
