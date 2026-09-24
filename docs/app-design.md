# App design

The design note for this app: what each command and query means, what the state
is, and why it stays deterministic. Keep it in step with `src/commands.rs`.
Every section below is filled in for the skeleton registry as a worked example.
Rewrite each one for your app, then delete its TODO marker line (the HTML comment under the heading).
WHAT-NEXT.md Step 4 walks you through it.

## 1. What the app does

<!-- TODO(app): one paragraph — what your app does, for whom, and why it needs to be replicated. -->

A registry: a replicated map from string keys to string values. Clients put a
value under a key, delete a key, and read a key back. Every write is applied on
all three replicas in the same order, so any replica can answer a read and the
registry survives the loss of any one node.

## 2. Commands

<!-- TODO(app): one row per Command variant, in enum order — name, fields, what it changes, response, max encoded size. -->

Commands change state. They go through consensus and are replayed for the life
of the cluster, so their order in the enum is their wire tag: append new ones at
the end, never reorder.

| # | name | fields | what it changes | response | max encoded size |
|---|---|---|---|---|---|
| 0 | `Put` | `key: String` (≤ 128 B), `value: String` (≤ 1024 B) | sets `key` to `value`, replacing any old value | `Put { previous: Option<String> }` | 1157 B (+16 B session envelope = 1173 B) |
| 1 | `Delete` | `key: String` (≤ 128 B) | removes `key` if present | `Delete { removed: Option<String> }` | 130 B (+16 = 146 B) |

`Command::validate()` enforces the key and value limits in the client, before
anything is sent.

## 3. Queries

<!-- TODO(app): one row per Query variant — name, fields, answer, max size, and whether the client reads linearizably or from a snapshot by default. -->

Queries only read. They are answered from one replica's state and never enter
the log.

| name | fields | answer | max encoded size | default read |
|---|---|---|---|---|
| `Get` | `key: String` (≤ 128 B) | `Value(Option<String>)` — the value, or none | query 130 B, answer 1029 B | snapshot (from whichever replica answers; may lag). `get --linearizable` goes through the read barrier and sees every acknowledged write |

## 4. State

<!-- TODO(app): the data structures in `State`, and why each one is deterministic. -->

`State { entries: BTreeMap<String, String> }`.

- `BTreeMap`, not `HashMap`: its iteration order is the key order, the same in
  every process. The snapshot image, the projection and any future "list" answer
  iterate it.
- No integers, so there is no overflow to handle. A counter would use
  `checked_add` or `wrapping_add`, never plain `+`.
- `last_applied: Option<u64>` holds the position of the last applied command.
  It is set in every `apply`, and restored from the snapshot image on install.

## 5. Determinism hazards considered

<!-- TODO(app): for each hazard, what your apply does instead — or why it does not arise. -->

| hazard | this app |
|---|---|
| clock | not used. If a command ever needs "now", it uses `ctx.time_ns` (the leader's stamp on the command), never `SystemTime::now()` |
| ids | none minted. If needed, `ctx.ids()` (`uc_service::IdGen`): derived from the position, so every replica mints the same ids |
| iteration order | `BTreeMap` only; `HashMap`/`HashSet` are banned by `clippy.toml` and `scripts/lint-determinism.sh` |
| floats | none. Amounts would be integers in the smallest unit (fixed point) |
| overflow | no arithmetic. Any would use `checked_*` or `wrapping_*` |
| I/O and environment | none in `apply`. Side effects would go in an output handler, which runs on the leader after commit |
| panics | none on any input: `validate()` bounds sizes at the client, and `apply` has no `unwrap` on user data |

## 6. Size bounds

<!-- TODO(app): your largest command and response, measured, against the payload ceiling. -->

One command must fit one datagram. At the baseline rung every cluster starts
from, the payload ceiling is **1344 B** with wire crypto off and **1312 B** with
it on. The `Sessioned` envelope (`client_id ‖ seq`) takes 16 B of that, leaving
1328 B / 1296 B for the encoded command.

| | encoded size | limit | headroom |
|---|---|---|---|
| largest command: `Put` with a 128 B key and a 1024 B value | 1157 B | 1296 B (crypto on) | 139 B |
| largest response: `Put`/`Delete` returning a 1024 B value | 1029 B (+1 B session tag) | not datagram-bounded, but bounded here by `MAX_VALUE_LEN` | — |
| largest query answer: `Value` of a 1024 B value | 1029 B | bounded by `MAX_VALUE_LEN` | — |

Measured with `app::encode` (bincode 2, standard config). A string of up to
250 B costs 1 length byte, and up to 65 535 B costs 3.

## 7. Snapshot

<!-- TODO(app): what the image contains, its version, and which changes need a new image version. -->

- **Contents:** the whole `State` plus its `last_applied` cursor, as
  `image_version: u32 LE ‖ len: u64 LE ‖ bincode(Image { cursor, state })`.
  UC puts its own 24-byte envelope in front of that.
- **Version:** `IMAGE_VERSION = 1` in `src/snapshot.rs`. An image with any other
  version is refused by name.
- **Needs a new image version:** any change to how `State` serializes — a field
  added, removed, renamed or reordered, a type changed. Bump `IMAGE_VERSION`,
  keep reading the old image, and bump `FSM_VERSION` (WHAT-NEXT.md Step 12).
  Changing behaviour without changing the state shape needs a new
  `FSM_VERSION`, not a new image version.
- **Freeze cost:** `freeze()` clones the whole state on the apply thread. That
  is fine at this size; a large state would use a persistent map for an O(1)
  freeze.

## 8. Open questions

<!-- TODO(app): what is still undecided, and who decides it. -->

- Should `Get` default to a linearizable read? It is slower, but never stale.
- Is a 1024 B value enough, or should large values live outside the cluster
  with a reference stored here?
