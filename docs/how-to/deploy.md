# Deploy to three machines

Run the app on three Linux machines under systemd: one UC node per machine,
with your service and a gateway beside it. Three processes on one host are a
majority of processes, not of machines; one power cut takes them all.

In this guide `<APP_NAME>`, `<APP_ID>` and `<BASE_PORT>` are the values in
your `uc-app.env`, and `ADDR0`, `ADDR1`, `ADDR2` are your three hosts' IPv4
addresses, in the order you pass them to `make package`.

## What you need

- Three Linux hosts (x86-64 or aarch64, the same architecture as the machine
  you package on), with systemd.
- A real disk for `/srv/uc2` on each. A node refuses to start on a RAM-backed
  filesystem, and it reserves roughly 78 MiB for its memory-mapped files at
  boot, before the journal grows.
- `openssl` on each host, to derive the wire-crypto public keys (step 3).
- A network path between the hosts that carries 1408-byte UDP payloads without
  fragmentation. Any standard 1500-byte-MTU network does; check overlays, VPNs
  and tunnels.

## 1. Build the bundle

On your development machine, with `make bins` done:

```bash
make package HOSTS=ADDR0,ADDR1,ADDR2
```

It refuses anything but three different addresses, and `0.0.0.0`: each node
binds exactly its own address. It builds your binaries and writes
`dist/<APP_NAME>-<version>-<arch>.tar.gz` (`<version>` is the one in
`Cargo.toml`):

```
<APP_NAME>-<version>-<arch>/
  bin/        uc2-node  uc2ctl  uc2-gateway  <APP_NAME>-service  <APP_NAME>
  systemd/    uc2-node.service  uc2-gateway.service  uc2-service@.service
  hosts/ADDR0/  node.toml  gateway.toml
  hosts/ADDR1/  node.toml  gateway.toml
  hosts/ADDR2/  node.toml  gateway.toml
  DEPLOY.md   (this file)
```

`<APP_NAME>` (the client) is not installed on the node hosts; it goes wherever
your clients run.

What the generated configs say:

- `node.toml`: node id `i` binds `ADDRi`; `[[members]]` lists all three
  (identical on every host); `instance_dir = "/srv/uc2/<APP_NAME>"`;
  `[services] names` is your FSM name; `[purge]` is on; `[metrics]` binds
  `ADDRi`; `[crypto] enabled = true` with `/etc/uc2/node.key` and
  `/etc/uc2/allowlist.toml`; `[admin] auth = "hmac"` with one key named
  `admin` at `/etc/uc2/admin/admin.key`.
- `gateway.toml`: listens on `ADDRi`, attaches to the local node's instance
  directory, lists all three gateways, and has the session envelope on.

## 2. Ports: each host has its own

Host `i` (the `i`-th address in `HOSTS`, counting from 0) uses:

| port | what | open it to |
|---|---|---|
| `<BASE_PORT> + i` UDP | node replication | the other two node hosts, both directions |
| `<BASE_PORT> + 100 + i` TCP | gateway | your clients |
| `<BASE_PORT> + 200 + i` TCP | metrics, `/healthz`, `/readyz` | your monitoring only (no authentication) |

So with `BASE_PORT=7000`, host 0's node is on UDP 7000, host 1's on 7001 and
host 2's on 7002. The ports differ per host by design: the same numbering
runs a local three-node cluster on one machine. Nothing else crosses the
network; your service and `uc2ctl` talk to their node through shared memory.

## 3. Make the keys

The node refuses to start until the files its `node.toml` names exist.

**Wire crypto (`[crypto]`).** Node-to-node traffic is authenticated and
encrypted. Each node has its own X25519 private key, and every node has the
same allowlist of all three public keys. On **each** host:

```bash
sudo install -d -m 0755 /etc/uc2
sudo sh -c 'umask 077; head -c 32 /dev/urandom > /etc/uc2/node.key'   # any 32 bytes; mode 0600
# print this node's public key (standard X25519, base64):
{ printf '\060\056\002\001\000\060\005\006\003\053\145\156\004\042\004\040'; sudo cat /etc/uc2/node.key; } \
  | openssl pkey -inform DER -pubout -outform DER | tail -c 32 | base64
```

The `printf` bytes wrap the raw key in the standard PKCS#8 header for an
X25519 key so `openssl` can read it; the result is the same public key UC
derives from the file. UC itself has no command yet that prints the public
half. Then write one allowlist from the three outputs, node id first:

```
0 <public key of ADDR0>
1 <public key of ADDR1>
2 <public key of ADDR2>
```

and install that same file on every host as `/etc/uc2/allowlist.toml`. Never
copy a private key between hosts. The node refuses a key file with any group
or world permission bit set.

**Admin key (`[admin]`).** Admin commands (membership changes, `uc2ctl
snapshot`, `uc2ctl upgrade pin`) must be signed. Generate one key, once, on
host 0:

```bash
sudo install -d -m 0700 /etc/uc2/admin
sudo /path/to/bundle/bin/uc2ctl gen-admin-key /etc/uc2/admin/admin.key
```

It writes 32 random bytes at mode 0600 and refuses to overwrite. Copy the
**same** file to `/etc/uc2/admin/admin.key` on the other two hosts, mode 0600.
The key's name is the file's stem, `admin`, which is what `node.toml` expects.
Whoever holds this file can change the cluster's membership and pin upgrades;
keep it with your operators, not your application.

## 4. Install on each host

On host `i`, from the unpacked bundle directory, with `ADDRi` its own address:

```bash
sudo install -m 0755 bin/uc2-node bin/uc2ctl bin/uc2-gateway bin/<APP_NAME>-service /usr/local/bin/
sudo install -m 0644 hosts/ADDRi/node.toml    /etc/uc2/node.toml
sudo install -m 0644 hosts/ADDRi/gateway.toml /etc/uc2/gateway.toml
sudo install -d -m 0750 /srv/uc2/<APP_NAME>
sudo install -m 0644 systemd/uc2-node.service systemd/uc2-gateway.service \
  systemd/uc2-service@.service /etc/systemd/system/
sudo systemctl daemon-reload
```

- The paths are fixed by the units: `uc2-node.service` runs
  `/usr/local/bin/uc2-node --config /etc/uc2/node.toml`, and
  `uc2-gateway.service` reads `/etc/uc2/gateway.toml`. Use the `node.toml`
  from *this* host's directory: each one binds its own address.
- The instance directory must exist before the node starts.
- `uc2-service@.service` is a template. `make package` set its command to
  `/usr/local/bin/%i --instance-dir /srv/uc2/<APP_NAME> --app-id <APP_ID>`,
  so the instance name is your service binary's name:
  `uc2-service@<APP_NAME>-service`.
- The service and gateway units are bound to the node (`BindsTo=`): they stop
  when it stops.

## 5. Start: nodes, then services, then gateways

1. On all three hosts: `sudo systemctl enable --now uc2-node`
2. Wait for a serving leader. On any host:
   `uc2ctl status --instance-dir /srv/uc2/<APP_NAME> --app-id <APP_ID>`.
   One node reports `leader=true can_serve=true`.
3. On all three hosts: `sudo systemctl enable --now uc2-service@<APP_NAME>-service`
4. On all three hosts: `sudo systemctl enable --now uc2-gateway`

A service started before its node has joined the cluster is refused
`NodeBooting`, waits 10 s, then exits, and systemd restarts it. The order
above avoids that churn.

## 6. Check it

- `uc2ctl status …` on each host: the same commit position, one leader, and
  your row attached.
- `curl -s http://ADDRi:<BASE_PORT+200+i>/readyz` answers 200 on every node.
- From a client machine, give the client all three gateways:

  ```bash
  <APP_NAME> --gateways ADDR0:<BASE_PORT+100>,ADDR1:<BASE_PORT+101>,ADDR2:<BASE_PORT+102> put hello world
  <APP_NAME> --gateways ADDR0:<BASE_PORT+100>,ADDR1:<BASE_PORT+101>,ADDR2:<BASE_PORT+102> get hello --linearizable
  ```

- The wire-crypto counters on the followers read 0 for `auth_failed`,
  `unknown_peer` and `cleartext_peer` (UC's *Encrypt traffic between nodes*
  has the full table).

Then, on your development machine: `make done STEP=deploy`.

## Running it

- **Snapshots.** The bundle's `node.toml` has no snapshot cadence unless
  `UC_SNAPSHOT_INTERVAL` was set when you ran `make package`. Take instants on
  demand, on the leader's host:
  `uc2ctl snapshot --instance-dir /srv/uc2/<APP_NAME> --app-id <APP_ID> --admin-key /etc/uc2/admin/admin.key`.
  Purge only moves once an instant completes on every row.
- **Backups.** `uc2ctl backup` works on a running node; copy the result off
  the host. It is also the only rollback from a pinned upgrade.
- **Monitoring.** Scrape each node's metrics port. The alert rules are in
  `.uc/packaging/prometheus/uc2-alerts.yml` on your development machine
  (`make bins` fetched them).
- **Membership.** `[[members]]` is only read on a node's first boot. To add,
  replace or remove a node later, use `uc2ctl` (and add a new node's public
  key to every allowlist first).
- **Upgrades.** A new `FSM_VERSION` goes through the pinned upgrade
  (`WHAT-NEXT.md` Step 12, and UC's *Upgrade an application*). A new UC
  release is a flag day: see [Upgrade ultima_cluster](upgrade-uc.md).

Upstream: [Run a cluster on real hosts](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/run-a-cluster.md),
[Encrypt traffic between nodes](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/encrypt-node-traffic.md),
[Monitor a cluster](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/monitor-a-cluster.md),
[Run a gateway](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/run-a-gateway.md),
[Back up a cluster](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/back-up-a-cluster.md),
[Change cluster membership](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/change-cluster-membership.md)
and [Configuration](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/configuration.md).
