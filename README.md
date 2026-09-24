# {{project-name}}

Choose a license for your project before you publish it — this template presumes none.

An application on [ultima_cluster](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/README.md)
(UC), generated from `uc_starter`. UC is a state machine replication server:
three or more nodes agree on the order of the commands in one log, and every
node applies that log to its own copy of your state machine. Because your
`apply` is deterministic, every copy ends in the same state, so the application
survives the loss of any minority of its machines. You write the state machine
and its client; UC supplies consensus, replication, durability, snapshots and
the network front door.

The UC version this project builds against is in `UC_VERSION`. Every upstream
link in this project is pinned to that release.

## Prerequisites

Either:

- **Linux** (x86-64 or aarch64) with [rustup](https://rustup.rs). The
  toolchain in `rust-toolchain.toml` installs itself on first build. `make lint`
  also needs the 1.89 toolchain:
  `rustup toolchain install 1.89.0 --profile minimal --component clippy`.
  Optional: `cosign`, so `make bins` checks the release signature as well as
  its checksum.
- **Or Docker** plus VS Code (with the Dev Containers extension) or the
  [devcontainer CLI](https://github.com/devcontainers/cli). This is the path
  on macOS and Windows, because UC nodes run on Linux only. See § Devcontainer.

To generate a project you also need `cargo-generate` 0.21 or newer
(`cargo install cargo-generate`). It runs anywhere Rust does.

## The fifteen-minute path

```bash
cargo generate --git https://github.com/PeterKnego/uc_starter   # add --tag v<UC version> to pin one
cd <your-project>
make bins up demo
make next
```

- `make bins` downloads the UC release named in `UC_VERSION` into `.uc/bin`
  and checks it against the release's `SHA256SUMS` (and its cosign signature,
  if `cosign` is installed).
- `make up` builds your service and client, starts three nodes, waits for a
  serving leader, then starts three services and three gateways.
- `make demo` drives the skeleton app (a small key-value registry) through
  the gateways and prints `PASS`.
- `make next` tells you which step of [`WHAT-NEXT.md`](WHAT-NEXT.md) you are
  on. It works that out from the repo, so it is right after a break too.

`make down` stops the cluster and keeps its state. `make up FRESH=1` starts
over with an empty log.

## Devcontainer

The project ships a devcontainer: a Debian image with the pinned Rust
toolchain, the 1.89 toolchain for the MSRV lint, `cosign`, `cargo-generate`
and Claude Code. When the container is created it runs `make bins`.

- VS Code: open the project folder and choose **Reopen in Container**.
- CLI: `devcontainer up --workspace-folder .`, then
  `devcontainer exec --workspace-folder . make up demo`.

The whole loop runs inside it: editing, building, the three-node cluster, the
client and the agent. On macOS and Windows, use it for everything. The scripts
refuse to start a node on a non-Linux host and point you here.

## Containers (optional)

`compose.yml` and the root `Dockerfile` run the same three-node-plus-gateways
topology as `make up`, but as containers instead of local processes — a demo
you can throw away with one command, not a deployment shape (see the file's
own header comment for why: shared kernel, disk and power supply, so its
"quorum" is a majority of processes, not of machines). It builds your service
and client from the root `Dockerfile` and runs three
`ghcr.io/peterknego/uc2` node and gateway containers alongside them:

```bash
set -a; . ./uc-app.env; set +a
UC_VERSION=$(cat UC_VERSION) docker compose up -d --build
docker run --rm --network "${APP_NAME}-demo_uc2" \
    --entrypoint /usr/local/bin/app-client "${APP_NAME}-demo-svc0" \
    --gateways gw0:9200,gw1:9201,gw2:9202 --app-id "$APP_ID" put greeting hello
docker run --rm --network "${APP_NAME}-demo_uc2" \
    --entrypoint /usr/local/bin/app-client "${APP_NAME}-demo-svc0" \
    --gateways gw0:9200,gw1:9201,gw2:9202 --app-id "$APP_ID" get greeting --linearizable
docker compose down -v
```

(`docker run` against the already-built `svc0` image, not `docker compose run
svc0`: `run` re-evaluates `depends_on` and restarts the one-shot `init`/
`init-key` containers — harmless, but they also regenerate `admin.key` every
time, needless churn once the cluster is live. See `compose.yml`'s own header
for the full reasoning.)

This is separate from the devcontainer above: the devcontainer is where you
edit and run `make up` (real processes, real `~/.uc-starter` state); compose
is a self-contained, disposable cluster in its own containers — useful for
trying the project without a Rust toolchain at all, or as a CI smoke test.
Its ports (9100 nodes, 9200-9202 gateways) are fixed, independent of this
project's `BASE_PORT`.

## With an agent, or without one

The tutor is [`WHAT-NEXT.md`](WHAT-NEXT.md): thirteen steps, from running the
skeleton to deploying your own app on three machines. Each step says what to
do yourself and what to ask an agent, and ends in a check that `make next`
runs.

- **Without an agent:** run `make next`, read the step it names, do it, and
  run `make next` again.
- **With an agent:** ask "what next?". The agent runs `scripts/next.sh --json`
  rather than guessing, teaches the step, and asks whether you want to do it
  yourself or have it done. `AGENTS.md` is the contract every agent follows;
  Claude Code also gets skills, a reviewer subagent and an edit hook. See
  [docs/ai-engineering.md](docs/ai-engineering.md).

## Make targets

`make help` prints this list.

| target | what it does |
|---|---|
| `help` | this list |
| `next` | where am I on WHAT-NEXT.md? (agents: `scripts/next.sh --json`) |
| `bins` | download + verify the ultima_cluster binaries for `UC_VERSION` |
| `build` | build the service and client (release) |
| `up` | start 3 nodes + 3 services + 3 gateways (`FRESH=1` wipes state) |
| `down` | stop the local cluster |
| `status` | `uc2ctl status` on every node |
| `restart-services` | restart only your service after a rebuild |
| `demo` | run `scripts/demo.sh` against the gateways |
| `kill-leader` | the failover exercise |
| `test` | unit + determinism + snapshot tests |
| `test-cluster` | the 3-node smoke (spawns processes) |
| `lint` | fmt + clippy + MSRV clippy + determinism grep |
| `check` | test + lint, and record it for the tutor |
| `todo` | the `TODO(app)` markers left |
| `done` | record a step the repo cannot show: `make done STEP=concepts` |
| `skip` | deliberately skip a step: `make skip STEP=snapshots` |
| `diffreplay` | install `uc2-diffreplay` for `UC_VERSION` into `.uc/cargo` |
| `corpus` | capture a diff-replay corpus + keep the old binary (before changing code) |
| `upgrade-check` | diff-replay the corpus through old vs new builds |
| `snapshot-drill` | snapshot, kill a service, watch it rebuild |
| `observe` | health, readiness and key metrics on every node |
| `upgrade-drill` | the pinned upgrade on the local cluster (asks first: one-way door) |
| `package` | deploy bundle: `make package HOSTS=ip0,ip1,ip2` |
| `uc-upgrade` | move to another UC release: `make uc-upgrade VERSION=x` |

`scripts/cluster.sh` does the finer work (run it with no arguments for its
usage): stop, kill or start one process, print the leader, run `uc2ctl`
against one node, fetch one node's metrics, print the cluster's directory.

## Project map

| path | what it is |
|---|---|
| `UC_VERSION`, `uc-app.env` | the one UC pin; the app name, `APP_ID`, FSM name and base port the scripts read |
| `Cargo.toml`, `rust-toolchain.toml`, `clippy.toml` | the build, the toolchain pin, and the determinism bans clippy enforces |
| `src/identity.rs` | `FSM_NAME`, `FSM_VERSION`, `APP_ID`, `BASE_PORT` |
| `src/commands.rs` | the wire types (`Command`, `Response`, `Query`, `QueryResponse`) and `Command::validate` |
| `src/state.rs` | `State`, `Fsm`, and `apply` / `query` |
| `src/snapshot.rs` | the snapshot image, and the projection diff replay compares |
| `src/lib.rs` | the module map |
| `src/bin/service.rs` | `{{project-name}}-service`: attaches to a node; `replay` / `project` for diff replay |
| `src/bin/client.rs` | `{{project-name}}`: the remote client, through the gateways |
| `tests/` | unit (`state.rs`, `snapshot.rs`), property (`determinism.rs`), CLI (`cli.rs`) and the cluster smoke (`cluster.rs`) |
| `scripts/` | the cluster, the tutor, the drills and packaging, all reached through `make` |
| `Makefile` | the one entry point |
| `upgrade/intent.toml.example` | the starting point for a diff-replay declaration |
| `WHAT-NEXT.md` | the tutor path |
| `docs/` | the design note, concepts, how-tos, AI engineering, troubleshooting |
| `AGENTS.md`, `CLAUDE.md`, `.claude/` | the agent kit |
| `.devcontainer/` | the container path for macOS and Windows |
| `compose.yml`, `Dockerfile` | the optional, disposable containerized demo cluster |

## Ports and where state lives

`BASE_PORT` is set in `uc-app.env` when the project is generated.

| what | port | protocol |
|---|---|---|
| node `i` (0–2), replication between nodes | `BASE_PORT + i` | UDP |
| gateway `i`, where clients connect | `BASE_PORT + 100 + i` | TCP |
| node `i` metrics (`/metrics`, `/healthz`, `/readyz`) | `BASE_PORT + 200 + i` | HTTP |

`UC_PORT_OFFSET=<n>` adds `n` to every port, so two clusters can run side by
side. The cluster smoke (`make test-cluster`) uses an offset of 10, so it never
collides with your own cluster.

The local cluster lives in `~/.uc-starter/{{project-name}}/`. Override it with
`UC_ROOT`, but never under `/tmp` or `/dev/shm`: those are RAM-backed, and
nodes refuse them. Inside it: `n0`–`n2` are the node instance directories
(each with its `node.toml`), `gw0.toml`–`gw2.toml` are the gateway configs,
`admin.key` signs admin commands, `logs/` has one log per process, and
`backups/` holds the upgrade drill's backups. `scripts/cluster.sh root`
prints the path.

In the project directory, `.uc/` holds the downloaded binaries (`.uc/bin`),
the release's systemd units and alert rules (`.uc/packaging`), the tutor's
proof stamps (`.uc/state`) and `uc2-diffreplay` (`.uc/cargo`); it is not
committed. `.uc-progress` is committed: it records the steps you marked done
or skipped. `upgrade/corpus/`, `upgrade/old/` and `dist/` are generated.

## Read next

- [`WHAT-NEXT.md`](WHAT-NEXT.md) — the tutor path, step by step
- [`docs/app-design.md`](docs/app-design.md) — your app's design note
- [`docs/concepts.md`](docs/concepts.md) — the model your code runs inside
- How-tos: [add a command](docs/how-to/add-a-command.md) ·
  [add a query](docs/how-to/add-a-query.md) ·
  [change the state shape](docs/how-to/change-the-state-shape.md) ·
  [schedule work](docs/how-to/schedule-work.md) ·
  [remove sessions or snapshots](docs/how-to/remove-sessions-or-snapshots.md) ·
  [upgrade UC](docs/how-to/upgrade-uc.md) ·
  [deploy](docs/how-to/deploy.md) ·
  [use the shared-memory client](docs/how-to/use-the-shmem-client.md)
- [`docs/ai-engineering.md`](docs/ai-engineering.md) — working with an agent
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — named failures and their fixes
- Upstream: [the ultima_cluster how-to guides](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/README.md)
  and [reference](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/README.md)
