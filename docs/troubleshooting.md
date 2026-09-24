# Troubleshooting

Named failures, each as symptom → cause → fix. Logs for the local cluster are
in `$(scripts/cluster.sh root)/logs/`, one file per process (`node0.log`,
`service0.log`, `gateway0.log`, …). `make status` shows which processes are
running and what each node reports.

Upstream, for anything not here: [Diagnose a node](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/diagnose-a-node.md).

## `NodeBooting`

**Symptom.** A service exits about 10 s after it starts, and its log ends
with:

```
Error: the node has not joined its cluster yet (FSM names published, declared set not yet) — it is booting; retry the attach
```

**Cause.** Since UC 2.13.0 a service may attach only after its node has
*joined*: it knows a leader, has learned the commit position, and has applied
the cluster's own records up to it. The service waits up to 10 s, then gives
up. Usually the service was started before the nodes, or too few nodes are
running to elect a leader (two of three must be up).

**Fix.** Start nodes first, then services: `make up` does this for you. By
hand: `scripts/cluster.sh start node N` for the missing nodes,
`scripts/cluster.sh wait-leader`, then `scripts/cluster.sh start service N`.
Under systemd the unit restarts the service on its own; start the nodes on
every host first ([deploy](how-to/deploy.md) step 5).

## RAM-backed cluster root

**Symptom.** `make up` stops with

```
cluster.sh: UC_ROOT=/tmp/… is RAM-backed; nodes refuse it
```

or it prints `no serving leader after 30s`, and `node0.log` says

```
uc2-node: refusing to start: instance_dir … is on a RAM-backed filesystem (tmpfs) — every fsync there is a silent no-op, …
```

**Cause.** On a RAM-backed filesystem (`/tmp` and `/dev/shm` on many
systems, and some container mounts) `fsync` does nothing, so a node would
appear to work and lose committed data on power loss. `uc2-node` refuses to
start there. The script only recognises `/tmp` and `/dev/shm` by name; the
node checks the real filesystem.

**Fix.** Put the cluster on a real disk: unset `UC_ROOT` (the default is
`~/.uc-starter/<APP_NAME>`) or point it at a disk-backed directory, then
`make up`. `findmnt -T <dir>` shows what backs a directory. If your home
directory itself is RAM-backed (some containers), mount a volume and set
`UC_ROOT` to it. Do not reach for the node's test-only override.

## Port in use

**Symptom.**

```
cluster.sh: port 7001 is in use — another cluster? set UC_PORT_OFFSET or run make down
```

**Cause.** Something that is not this cluster's own live process holds a port
in this app's band: another generated app with the same `BASE_PORT`, another
UC cluster, or a process left over from a crash.

**Fix.** One of:

- `make down` in the other project;
- find the holder: `ss -ulnp | grep :7001` (UDP, nodes) or `ss -tlnp | grep :7101`
  (TCP, gateways and metrics), and stop it;
- run this cluster shifted: `export UC_PORT_OFFSET=20`, then `make up`. Keep
  the variable set for every later command in that shell: the scripts and the
  client both read it.

## Not a Linux host

**Symptom.**

```
fetch-uc.sh: ultima_cluster nodes run on Linux only (this is Darwin). Open this project in its devcontainer — see README.md § Devcontainer.
```

(the same from `cluster.sh` or `next.sh`), or `make next` reports
`not Linux (Darwin): open the devcontainer`.

**Cause.** UC nodes run on Linux (x86-64 or aarch64) only. The release has no
macOS or Windows binaries.

**Fix.** Open the project in its devcontainer (README § Devcontainer) and run
everything inside it. On Linux on another CPU, `make bins` says
`no ultima_cluster release for <arch>`.

## Checksum or signature failure

**Symptom.** `make bins` stops with one of:

```
fetch-uc.sh: checksum mismatch for uc2-<version>-<arch>-unknown-linux-gnu.tar.gz — refusing to install
fetch-uc.sh: cosign signature verification failed for uc2-<version>-<arch>-unknown-linux-gnu.tar.gz
```

or with a `curl: (22) … 404` error.

**Cause.** The checksum does not match the release's `SHA256SUMS`: a
truncated download, a proxy that rewrote it, or a file that is not what the
release published. A cosign failure means the signature does not come from
UC's release workflow for a `v*` tag. A 404 means `UC_VERSION` names a
release (or an architecture) that does not exist.

**Fix.** Run `make bins` again; it starts from an empty `.uc/download`. If it
fails again, stop: do not install the binaries by hand around the check.
Try another network, compare the file with the checksum on the UC releases
page, and report it if they disagree. For a 404, check `UC_VERSION`; move it
only with `make uc-upgrade`.

## `ULTSNAP1` refused

**Symptom.** A service fails to install a snapshot, and its log says:

```
MistaggedSnapshot: …/snapshots/0/snap-<P>.ultsnap: pre-2.13.0 artifact (ULTSNAP1): carries no version stamp — clear snapshots/<row>/ once and take a new instant
```

**Cause.** The artifact was written by UC 2.11 or 2.12. Since 2.13.0 every
artifact carries the version of the state machine that built it, and an older
artifact without one is refused by name rather than guessed at.

**Fix.** On the local cluster: `make down`, then `make up FRESH=1`. On a
deployed cluster, follow the 2.13.0 section of UC's
[How to upgrade a cluster](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/upgrade-a-cluster.md):
with every node stopped, clear `snapshots/<row>/` once on every node, start
the cluster, and take a fresh instant (`uc2ctl snapshot`) before any
`uc2ctl upgrade pin`. That wipe is safe only if the journal still reaches
position 0, or your state machine is durable. **With purge on and an
in-memory state machine (this project's defaults) you cannot wipe**; read the
upstream section before you act.

## Mixed versions after `make uc-upgrade`

**Symptom.** One of:

- `make next`: `.uc/bin has '<old version>' but UC_VERSION is <new>: make bins`;
- a service log: `cnc attach error: cnc protocol version mismatch: local 0x…, peer 0x…`
  (a service built against the new crates attaching to a node still running
  the old binary, or the reverse);
- nodes that stop agreeing after one of them was restarted.

**Cause.** `make uc-upgrade` moves the pins and the build; the processes
already running keep the old binaries until they stop. Every UC minor release
so far has been a flag day: old and new nodes, and old and new services and
nodes, must never run together. Some combinations stall; some diverge
silently.

**Fix.** `make down`, `make bins`, `make check`, then `make up FRESH=1`.
Never restart one process at a time across a UC upgrade. Details:
[Upgrade ultima_cluster](how-to/upgrade-uc.md).

## Service exits: "apply agent fail-stopped"

**Symptom.** A service stops; `make status` shows it `down`, and its log ends
with:

```
<APP_NAME>-service: apply agent died; exiting for restart
Error: apply agent fail-stopped
```

**Cause.** The apply thread stopped. Look a few lines up the log for why:

- a line starting `thread '…' panicked at src/state.rs:…`: a panic in your
  `apply`, `query` or `on_timer` (an `unwrap`, an index out of range, an
  overflow check);
- `corrupt committed frame (fail-stop)`: a committed command does not decode
  as this build's `Command`. Typically the enum was reordered or replaced
  while the log still holds commands written by the old one, or a newer
  client sent a variant this older service does not know;
- `corrupt query frame (fail-stop)`: a newer client sent a query this service
  does not know.

The command that caused it is committed, so every replica meets it, and a
restarted service replays it and fails the same way.

**Fix.** Read the log, fix the code so the command is handled (answer bad
input with an error response; never panic on it), `make check`, then
`make restart-services`. If the log holds commands from an enum you replaced
on your disposable local cluster, start over: `make up FRESH=1`.

**A newer client got ahead of the services** (it sent a new command variant):

- *Prevention.* Never run a client that sends a new variant until every
  service runs the new build; on a real cluster, after the pin has committed
  ([Add a command](how-to/add-a-command.md), "The rollout order").
- *Local cluster.* `make up FRESH=1`, or `make restart-services` with the new
  build, which can decode the frame.
- *Real cluster.* An ordinary restart with the new build is refused, because
  it carries a different `FSM_VERSION` (see
  [concepts § Identity](concepts.md#identity-name-and-version)). The recovery
  is the pinned upgrade (`WHAT-NEXT.md` Step 12), if its origin instant can
  still complete; if the dead services cannot complete it, restore the backup
  taken before the change on every node.

## Client: "client and service built from different code"

**Symptom.** A client command exits `1` with:

```
<APP_NAME>: cannot decode (…) — client and service built from different code?
```

**Cause.** The answer did not decode as the client's `Response` or
`QueryResponse`: the service running on the cluster was built from different
code than the client. Most often you rebuilt and ran the new client without
`make restart-services`. The write itself may have been applied: only the
answer failed to decode.

**Fix.** `make restart-services` (it rebuilds and restarts your service on
every node), then run the client from the same build. If the client sent a
command or query the running service does not know, check the service logs
too: see the previous section.

## `no serving leader after 30s`

**Symptom.** `make up` prints this and the tail of each node log.

**Cause.** The nodes did not elect a leader: usually a node refused to start
(read the first lines of each `node*.log`: a RAM-backed root, a bad config),
or fewer than two nodes are running.

**Fix.** Fix what the node log names, then `make up` again. `make status`
shows which nodes are running.
