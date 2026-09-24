# Remove sessions or snapshots

This project turns on two things UC leaves optional: **sessions**
(`Sessioned<Fsm>` plus the gateway's envelope) and **snapshots**
(`SnapshotStateMachine`, `start_with_snapshots()`, and `[purge]` in
`node.toml`). You can remove either. Read what breaks first; in most apps you
want both.

Decide before a cluster you care about has run. Both change what is in the
log or in the snapshot artifacts, so switching on a running cluster is not a
restart: every command already in the log was written with the envelope, and
every artifact holds the session table. On your local cluster, start over with
`make up FRESH=1` afterwards.

## Sessions

**What they give you.** A client that loses its connection, or gets
`UNKNOWN` ("may or may not have committed"), sends the write again. With
sessions, a write that already landed comes back `replayed=true` from a cache
and `apply` does not run twice.

**What breaks without them.** A re-sent write applies again. For an
idempotent write (put the same value) that is harmless; for anything else (an
increment, an append, a compare-and-set, a debit) it is a duplicate. You then
choose: make every command idempotent yourself (for example with a
client-chosen request id your state remembers), or give up automatic re-sends
and handle `UNKNOWN` in your client.

**How to remove them.** All of these, together:

1. `src/bin/service.rs`: drop the wrapper in **both** places it is built, the
   `sm` closure (for `replay` / `project`) and the live attach:
   `Sessioned::new(Fsm::default(), SessionConfig::default())` becomes
   `Fsm::default()`. Remove the now-unused imports.
2. `scripts/lib.sh`, `render_gateway_toml`: set `[session] envelope = false`.
   The gateway then passes command bytes through untouched. This changes the
   local cluster (`make up`) and the deploy bundle (`make package`) together.
3. `src/bin/client.rs`, in `connect`: set `resend_on_unknown: false` in the
   `RemoteConfig`. The client then reports `UNKNOWN` as an error instead of
   re-sending. Its failover re-send of unanswered requests stays; without the
   envelope such a re-send is reported as possibly duplicated.
4. `upgrade/intent.toml`: remove `tag_offset = 16`. There is no envelope to
   skip, so the command tag is the first byte.
5. `src/commands.rs`: the payload ceiling you design against grows by the 16 B
   the envelope used (1344 B / 1312 B at the baseline, crypto off / on).

Then `make check`, `make up FRESH=1`, `make demo`. The `replayed=` field the
client prints is now always `false`.

## Snapshots

**What they give you.** A coordinated instant writes every replica's state at
one log position. A service or node that fell behind installs it instead of
replaying the whole log; the journal below it can be purged; and the pinned
upgrade (`WHAT-NEXT.md` Step 12) is built on it.

**What breaks without them.**

- **The journal grows without bound.** Purge only drops the journal below a
  complete snapshot set, so it never moves.
- **Catch-up is always a full replay.** A restarted service, and a new or
  rebuilt node, replays from position 0. That gets slower as the log grows.
- **`uc2ctl snapshot` refuses** with `48 snapshot_unsupported`, naming the
  row, so `make snapshot-drill`, `make corpus` and `make upgrade-drill` stop
  working.
- **No pinned upgrade.** A pinned row must install the origin artifact; a row
  started with plain `start()` is refused `PinRequiresSnapshots`. You would be
  left with a whole-cluster restart for every behaviour change.

**How to remove them.**

1. `src/bin/service.rs`: `ServiceBuilder::new(cfg, sm).start_with_snapshots()?`
   becomes `.start()?`. That clears the row's snapshot capability.
2. `scripts/lib.sh`, `render_node_toml`: remove the `[purge]` section, and
   leave `UC_SNAPSHOT_INTERVAL` unset (its default, `0`, means no cadence).
   Purge is off by default in UC.
3. Keep the `impl SnapshotStateMachine` in `src/snapshot.rs`. The service's
   `replay` and `project` subcommands (diff replay) require it, and it costs
   nothing when no instant is ever taken.

Then `make check` and `make up FRESH=1`. The tutor's snapshot and upgrade steps
no longer apply: `make skip STEP=snapshots` and `make skip STEP=upgrade`.

Upstream: [the state-machine contract](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md),
[When to use `envelope = false`](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/run-a-gateway.md#when-to-use-envelope--false),
[the remote protocol](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/remote-protocol.md)
and [Keep the journal from growing without bound](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/bound-journal-growth.md).
