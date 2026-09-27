# Remove sessions

This project turns on **sessions** (`Sessioned<Fsm>` plus the gateway's
envelope), which UC leaves optional. You can remove them. Read what breaks
first; in most apps you want them.

Decide before a cluster you care about has run. Sessions change what is in the
log and in the snapshot artifacts, so switching on a running cluster is not a
restart: every command already in the log was written with the envelope, and
every artifact holds the session table. On your local cluster, start over with
`make up FRESH=1` afterwards.

Snapshots are not optional, so this page has no way to remove them. A cluster
without them cannot purge its journal, and a restarted service replays the
whole log: at a tenth of UC's measured ingest rate that is about 1.5 TB of
journal per node per day, and about 7.5 days of replay per month of history. UC is making `start_with_snapshots()` the only
way to start a service
([ultima_cluster#67](https://github.com/PeterKnego/ultima_cluster/issues/67)).

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

Upstream: [the state-machine contract](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md),
[When to use `envelope = false`](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/run-a-gateway.md#when-to-use-envelope--false)
and [the remote protocol](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/remote-protocol.md).
