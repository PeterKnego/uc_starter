# Upgrade ultima_cluster

Move this project to a newer UC release. This is a different thing from
upgrading *your* state machine (`WHAT-NEXT.md` Step 12): here the platform
changes under an unchanged app.

**Every UC minor release so far has been a flag day**: the node-to-node wire
format or the shared-memory control page changed, and old and new nodes must
never run together. Plan for a coordinated stop.

## 1. Move the pins

```bash
make uc-upgrade VERSION=<new>
```

This rewrites `UC_VERSION`, the exact `=<version>` pins of `uc_service`,
`uc_remote`, `uc_protocol` and `uc_diffreplay` in `Cargo.toml`, and every
upstream link in the docs and the agent kit (`blob/v<version>/`), updates
`Cargo.lock`, and prints the links to that release's notes and upgrade guide.
It refuses a version that is not on crates.io.

Do not edit `UC_VERSION` or the crate pins by hand: they must move together.

## 2. Read the release's upgrade section

Open the release notes it printed (`RELEASES.md` in the UC repository, at the
new tag) and the matching section of UC's *How to upgrade a cluster*
(`docs/how-to/upgrade-a-cluster.md`, one section per release). Look for:

- whether the wire protocol or the control page (`cnc`) version changed. If
  either did, it is a flag day.
- any change to the snapshot artifact envelope. When it changes, each node's
  `snapshots/<row>/` must be cleared once during the upgrade — the release
  notes name the old envelope tag, and an artifact carrying it is refused by
  name rather than guessed at.
- new required `node.toml` or `gateway.toml` keys, and keys that are now
  refused by name. `scripts/lib.sh` (`render_node_toml`,
  `render_gateway_toml`) is where this project writes both files.
- SDK changes that break your code: fix them in step 3.

## 3. Stop the local cluster, rebuild, re-prove

```bash
make down          # services and gateways first, then nodes
make bins          # fetch and verify the new release's binaries into .uc/bin
make check         # tests + lints against the new crates
```

Stop first. `make bins` replaces the binaries in `.uc/bin`, and any process
started after that (a `make kill-leader` restart, a `scripts/cluster.sh start`)
would be a new-version process joining old-version ones: exactly the
mixed-version state a flag day forbids. `make next` checks that
`.uc/bin/uc2-node --version` matches `UC_VERSION`.

## 4. Start the local cluster fresh

```bash
make up FRESH=1
make demo
```

`FRESH=1` discards the local cluster's log and state, which is the simple
answer for a disposable dev cluster. It also covers an artifact wipe: the
local cluster runs purge with an in-memory state machine, and that combination
cannot clear `snapshots/<row>/` and keep its data, because after a purge the
artifacts are the only copy of the state below the floor.

## 5. A deployed cluster

On real hosts, follow the release's section of *How to upgrade a cluster* to
the letter. In outline: stop every service and gateway, then every node, on
every host; install the new binaries everywhere; do the one-time steps the
release names (such as clearing `snapshots/<row>/` on every node, where the
release says that is safe for your setup); start every node, then every
service, then every gateway. **Stop every node before you start any node.**
Take an off-node backup first (`uc2ctl backup`), so there is a way back.

Rebuild the deploy bundle with `make package` so the bundle, the binaries and
your service all come from the same release.

Upstream: [How to upgrade a cluster](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/upgrade-a-cluster.md),
[Releases](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/RELEASES.md),
[the semver policy](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/semver-policy.md)
and [Back up a cluster](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/back-up-a-cluster.md).
