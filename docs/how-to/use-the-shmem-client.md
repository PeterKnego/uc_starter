# Use the shared-memory client

This project's client talks to the cluster through the gateways, over TCP
(`uc_remote`). UC also has a local client, `uc_client`, that attaches to a
node's shared memory directly, with no gateway. This page says what that
gives you, what it costs, and how the two compare on measurements UC has
published.

## What it provides

- **Same-host submission straight into the node.** A `uc_client` process
  writes each command into the node's ingress ring (a lock-free
  multi-producer ring in the node's instance directory) and reads answers
  from the node's egress broadcast ring. There is no TCP connection and no
  gateway hop.
- **Three API tiers** over the same rings: `Engine` (non-blocking, bytes in
  and bytes out, you correlate requests yourself), `PipelinedClient` (a window
  of outstanding tickets over one engine), and `Client` (one blocking call per
  request). `Engine` is what UC's own gateway and throughput gates run on.
- **The same reads.** Snapshot reads from the local replica, and linearizable
  reads through the leader's read barrier.

## What it requires

- **A process on the node's host**, or in a container that shares the node's
  instance directory, running as a user that can read and write that
  directory's files. There is no network client: shared memory does not
  cross machines.
- **The `uc_client` crate** at the same exact version as the rest of UC
  (`uc_client = "=<UC_VERSION>"` in `Cargo.toml`).
- **Leader handling.** Writes and linearizable reads are served by the leader
  only. On a follower's node they fail with `ClientError::NotLeader { hint }`,
  where `hint` is the leader's node id when known. Either run one client
  process beside **every** node, keep all of them attached, and route your
  callers to the one whose node leads; or handle `NotLeader` by sending the
  caller elsewhere. Back off a few milliseconds in that path instead of
  retrying hot.
- **Its own lifecycle around node restarts.** A node restart gives the
  control page a new instance id; in-flight and later calls fail with
  `ClientError::InstanceRestart`, and the only recourse is to attach again.
  An attach before the node has joined its cluster waits up to 10 s
  (`NodeBooting`). Do not tear clients down when leadership moves: a client
  kept attached everywhere simply starts succeeding on the new leader's host.
- **The session envelope, by hand.** This project's service runs
  `Sessioned<Fsm>`, which expects every command to start with a 16-byte
  envelope: `client_id: u64` LE, then `seq: u64` LE. The gateway adds it for
  remote clients; a shared-memory client must add it itself, so use `Engine`
  (bytes in, bytes out), not the typed `Client::submit`, which would send a
  bare command. Pick a random `client_id` per process and count `seq` up from
  there. A write's answer starts with a one-byte tag (`0` fresh, `1` replayed,
  `2` expired, with nothing after it) before your encoded `Response`. Queries
  carry no envelope and no tag. Without the envelope the service misreads the
  command, so there is no "sessions optional" here unless you also remove
  `Sessioned` (see [Remove sessions or snapshots](remove-sessions-or-snapshots.md)).
- **The same codec.** Encode commands and queries with `app::encode` and decode
  answers with `app::decode`, exactly as the remote client does.

## Pros and cons

| | shared-memory client (`uc_client`) | remote client through a gateway (`uc_remote`) |
|---|---|---|
| where it runs | on a node's host only | anywhere with a TCP route to a gateway |
| hops | client → node | client → TCP → gateway → node |
| leader changes | you handle `NotLeader`, or run one per node | followed for you (`REDIRECT`, `LEADER_CHANGED`) |
| re-send after failover | yours to build | built in, deduplicated by the session envelope |
| flow control | the engine's in-flight window | credits granted by the gateway |
| node restart | you re-attach (`InstanceRestart`) | the client reconnects on its own |
| session envelope | you add it (this project's service requires it) | the gateway adds it |
| extra processes | none | one gateway per node host |

## What the difference measures

One head-to-head comparison on one rig exists, from UC's M13 gate
(`docs/benchmarks/uc2-m13-gate-2026-08-24.md`, run on 2026-08-25 on a fleet of
4 × AWS `c6id.2xlarge`, us-east-1). Against the same three-node cluster
generation and the same leader, with a raw state machine, the session
envelope **off**, 64-byte payloads and 1024 requests in flight:

- the direct shared-memory `Engine` on the leader's host: **1,751,213
  responses/s**;
- **one** remote client connection through the real gateway (from a separate
  client host): **1,079,930 responses/s**, 0.617× the direct arm (gate row a);
- the best aggregate over up to 16 remote connections (N = 16):
  **1,464,381 responses/s**, 0.836× (gate row b).

That is throughput under deep pipelining, not latency. Latency was not
measured head-to-head on one rig: UC's service-time measurement
(`docs/benchmarks/uc2-service-time-2026-09-16.md`) timed the shared-memory
client alone. For a client that sends one request and waits, the round trip,
not the transport, sets the rate; see UC's
`docs/benchmarks/uc2-remote-client-shapes-2026-09-18.md`.

Read those numbers as a platform ceiling. Your state machine's `apply`, the
session envelope and your client's own shape all change them.

## Where to start

- [`examples/counter/src/bin/counter-client.rs`](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/examples/counter/src/bin/counter-client.rs):
  a complete `uc_client::Client` program — attach, retry `NotLeader` and
  `Retry`, snapshot and linearizable reads. Its service does not run
  `Sessioned`, which is why it can use the typed `Client`.
- [Write a service binary](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/write-a-service-binary.md):
  the attach and lifecycle rules a same-host process follows.
- [Run a cluster on real hosts § Put a client next to every node](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/run-a-cluster.md#put-a-client-next-to-every-node):
  the one-client-per-node shape and its two classic mistakes.
- The measurements: [the M13 gate](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/benchmarks/uc2-m13-gate-2026-08-24.md)
  and [the M13 hop bench](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/benchmarks/uc2-m13-hop-bench-2026-08-24.md).
