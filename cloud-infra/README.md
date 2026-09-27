# cloud-infra — your app on three cloud hosts

This directory stands up three hosts on a real cloud (Hetzner, AWS or GCP),
deploys this app's cluster onto them, and can test, benchmark, inspect and
tear it down again. From the project root:

| command | effect |
|---|---|
| `make cloud-plan` | read-only: what `cloud-up` would create, change or destroy |
| `make cloud-up` | builds the app, creates or updates the three hosts (Terraform) and deploys the app onto them (Ansible); run again after a failure, it resumes |
| `make cloud-deploy` | rebuilds and restarts the app on the existing hosts; no infrastructure change |
| `make cloud-test` | demo, probe, a host failover and an MTU check through the gateways; records the `cloud` stamp |
| `make cloud-bench` | runs the client's `bench` subcommand, load from a follower host |
| `make cloud-status` | hosts, uptime vs `ttl_hours`, `uc2ctl status`, `/readyz` on every node |
| `make cloud-logs` | tails one host's journal for one process (`HOST=… PROC=…`) |
| `make cloud-destroy` | destroys the hosts (Terraform) and clears the local inventory and secrets |
| `make cloud-oneshot` | `cloud-up`, then `cloud-test`, then always `cloud-destroy` — also on Ctrl-C |

The hosts bill until `make cloud-destroy` runs, whether or not anything else
in this list ever did.

## Control machine

Works from Linux or macOS.

Homebrew (macOS or Linux):

```
brew install terraform ansible jq zig && cargo install cargo-zigbuild --locked
```

Debian/Ubuntu:

```
# terraform: see https://releases.hashicorp.com/terraform/1.9.8/
pip3 install --user ansible-core ziglang
apt-get install jq
cargo install cargo-zigbuild --locked
```

`make cloud-up` refuses to start without `make bins` (the UC binaries in
`.uc/bin` it bundles for same-CPU Linux hosts), and it builds the app before
it creates anything, so a compile error costs nothing.

The devcontainer already has all of these. Note: `make up` — the *local*
cluster — still needs Linux or the devcontainer; the `cloud-*` targets above
do not.

## Credentials

Copy `cloud-infra/.env.example` to `cloud-infra/.env` (gitignored) and fill in
the chosen cloud's variables, as bare `KEY=value` — no quotes needed, and any
quotes present are stripped before Terraform sees them. Only one cloud's
credentials are needed at a time.

`make -C cloud-infra cloud-env-show` prints which variables are set and their
length, never their value, so you can check credentials are wired up
without ever printing a secret.

## terraform.tfvars

Copy `cloud-infra/example.tfvars` to `cloud-infra/terraform.tfvars`
(gitignored) and edit it. Its variables:

| variable | meaning |
|---|---|
| `cloud` | `hetzner`, `aws` or `gcp` |
| `arch` | `x86_64` or `aarch64` — the hosts' CPU; the bundle is cross-built for it |
| `region` | empty picks a default: `nbg1` (hetzner), `us-east-1` (aws), `us-central1` (gcp) |
| `instance_type` | empty picks a small default for `arch`: `cpx21`/`cax11` (hetzner), `c7i.large`/`c7g.large` (aws), `e2-standard-2`/`t2a-standard-2` (gcp) |
| `ssh_public_key` | contents of your SSH public key, installed on the hosts |
| `ssh_private_key_file` | the matching private key path, read by the scripts (not by Terraform) |
| `allow_ssh_cidr` | who may SSH to the hosts — your IP as `/32` |
| `allow_client_cidr` | who may reach the gateways; empty defaults to `allow_ssh_cidr` |
| `ttl_hours` | advisory; `make cloud-status` warns once the hosts have run past it |

`0.0.0.0/0` in `allow_ssh_cidr` or `allow_client_cidr` is refused unless you
also set `allow_open_cidr = true` — that opens SSH or the gateways to the
whole internet, so it takes a deliberate opt-in.

### Editing it after `cloud-up`

`make cloud-up` applies exactly the plan it shows. A change that only updates
resources in place (the CIDRs, `ttl_hours`) goes straight through. A change
that destroys or replaces a host — `region`, `arch`, an `instance_type` the
cloud cannot resize, or a new `ssh_public_key` on Hetzner — is refused, because
a replaced host comes back empty: its log, keys and data are gone. `make
cloud-plan` shows which kind a change is. If you mean it, `make cloud-up
REPLACE=1`; for a clean cluster, `make cloud-destroy` then `make cloud-up`.

## SSH key

- **Native** (running directly on your machine): the file named in
  `ssh_private_key_file` just needs to be readable.
- **Devcontainer via VS Code**: VS Code forwards your host machine's
  `ssh-agent`; run `ssh-add ~/.ssh/id_ed25519` on the host (not inside the
  container) before `make cloud-up`.
- **Devcontainer via the CLI**: add a bind mount so the container can read
  the key file directly, in `.devcontainer/devcontainer.json`:

  ```json
  "mounts": ["source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,readonly"]
  ```

## Where things run

Each node binds its **private** IP address; the gateway listens on
`0.0.0.0` and advertises the **public** IPs in its member list, so a
redirect or leader-changed response always points a client somewhere it can
actually reach. `make cloud-test` and `make cloud-bench` run the demo/probe
and the client's `bench` subcommand on one of the follower hosts over SSH —
the client does not build for macOS — so the latency `cloud-bench` reports
is in-cloud, host to host, not from your laptop.

## When your IP changes

If SSH or the gateways start timing out after working before, your public IP
most likely changed. Update `allow_ssh_cidr` (and `allow_client_cidr` if it
was set separately) in `cloud-infra/terraform.tfvars` to your new address —
`curl -s https://checkip.amazonaws.com` prints it — then run `make cloud-up`
again; a CIDR change only updates the firewall (`make cloud-plan` shows it).

## Costs

`make cloud-status` shows each host's uptime against `ttl_hours` and flags
hosts that have run past it. `make cloud-oneshot` destroys the hosts itself
once it is done, and also when you press Ctrl-C, it is sent TERM, or its
terminal closes. A second Ctrl-C stops that destroy too, and a process killed
outright (`kill -9`, an agent's command timeout) cannot clean up: in both
cases run `make cloud-status`, then `make cloud-destroy`. Everything else in
the command table above leaves the hosts running (and billing) until you run
`make cloud-destroy`.
