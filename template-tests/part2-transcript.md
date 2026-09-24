# Part 2 transcript — Task 8 evidence (2026-09-24)

Every Part-2 drill, run once by hand in a freshly generated project
(`template-tests/gen.sh ~/scratch/uc_starter-gen/t8c p2-app p2 p2 7800`,
`UC_ROOT=~/scratch/t8c-root`, ultima_cluster 2.13.0 release binaries in
`.uc/bin`). Each `$` line is the command as run from the project root; `[exit N]`
is its exit status (a piped `| tail` shows tail's). Order: skeleton up →
snapshot drill → observe → diff-replay install → the user's demo edited to
exercise a padded `put` → corpus (old code) → code change (`put` trims the
value) + `FSM_VERSION` 1.1.0 + intent → the drill's guard refusals → an
undeclared-change FAIL → upgrade-check PASS → the pin guards (non-terminal,
`cluster.sh ctl … upgrade pin`, a typed answer that is not `PIN`, an intent
edited after the PASS) → the real pinned drill → the old binary refused by name
→ package + its HOSTS refusals → down.

Not in the log below, checked separately: a `deploy`-profile `node.toml`
(rendered by the same `render_node_toml` package.sh uses, hosts 127.0.0.1-3,
port offset 50) loads in `uc2-node` 2.13.0 (`config_loaded`), refuses by name
while the crypto key is absent ("crypto is enabled but its key material is
unusable … must never fall back to cleartext"), and with a key + allowlist
present starts, binds, and serves `/metrics`.

```text

$ make up
cargo build --release
    Updating crates.io index
     Locking 112 packages to latest Rust 1.89 compatible versions
      Adding bincode v2.0.1 (available: v3.0.0)
      Adding generic-array v0.14.7 (available: v0.14.9)
      Adding signal-hook v0.3.18 (available: v0.4.4)
   Compiling p2-app v0.1.0 (/home/claude/scratch/uc_starter-gen/t8c/p2-app)
    Finished `release` profile [optimized] target(s) in 2.28s
scripts/cluster.sh up 
p2-app cluster: root=/home/claude/scratch/t8c-root
1. nodes
   started node0 (pid 733803)
   started node1 (pid 733807)
   started node2 (pid 733811)
   waiting for a serving leader
   node 0 is the serving leader
2. services
   started service0 (pid 733877)
   started service1 (pid 733883)
   started service2 (pid 733889)
3. gateways
   started gateway0 (pid 733895)
   started gateway1 (pid 733901)
   started gateway2 (pid 733907)
   gateways: 127.0.0.1:7900,127.0.0.1:7901,127.0.0.1:7902
up. try: make demo
[exit 0]

$ make demo
scripts/demo.sh
demo against 127.0.0.1:7900,127.0.0.1:7901,127.0.0.1:7902
   put greeting hello           -> ok previous=none position=32 replayed=false
   get greeting                 -> value="hello"
   delete greeting              -> ok removed="hello" position=96 replayed=false
   get greeting (deleted)       -> value=none
PASS
[exit 0]

$ make snapshot-drill
scripts/snapshot-drill.sh
1. coordinated snapshot instant P=288 (every node freezes its state at log position 288)
2. all three nodes hold the complete set at P
3. SIGKILLed service 1 and restarted it — its in-memory state is gone
4. service 1 replayed the journal (it still reaches back past P, so no install was needed) and the value reads back
   log: p2-app-service: attached fsm="p2" version=1.0.0 row=0 epoch=2 instance_dir=/home/claude/scratch/t8c-root/n1
PASS
[exit 0]

$ make observe
scripts/observe.sh
node 0: healthz ok, readyz ok, 7 key series present, is_leader=1
node 1: healthz ok, readyz ok, 7 key series present, is_leader=0
node 2: healthz ok, readyz ok, 7 key series present, is_leader=0
alert rules to load into Prometheus: .uc/packaging/prometheus/uc2-alerts.yml
PASS
[exit 0]

$ make next
Step 3/13 · Part 1 · SMR in five minutes → WHAT-NEXT.md "Step 3"
  status: todo
  - read WHAT-NEXT.md Step 3, then: make done STEP=concepts
[exit 0]

$ make diffreplay
cargo install uc_diffreplay --version 2.13.0 --locked --root .uc/cargo
    Updating crates.io index
  Installing uc_diffreplay v2.13.0
warning: default toolchain implicitly overridden with `1.96.0-x86_64-unknown-linux-gnu` by rustup toolchain file
  |
  = help: use `cargo +stable install` if you meant to use the stable toolchain
  = note: rustup selects the toolchain based on the parent environment and not the environment of the package being installed
    Updating crates.io index
    Updating crates.io index
    Finished `release` profile [optimized] target(s) in 2.22s
  Installing /home/claude/scratch/uc_starter-gen/t8c/p2-app/.uc/cargo/bin/uc2-diffreplay
   Installed package `uc_diffreplay v2.13.0` (executable `uc2-diffreplay`)
warning: be sure to add `/home/claude/scratch/uc_starter-gen/t8c/p2-app/.uc/cargo/bin` to your PATH to be able to run the installed binaries
[exit 0]

$ sed -i '/^expect "get greeting (deleted)"/a expect "put padded (spaces)"     "ok previous="      put padded "  spaced  "\nexpect "put padded again"        "ok previous=\\"  spaced  \\"" put padded again' scripts/demo.sh && grep -n padded scripts/demo.sh && make demo | tail -3
21:expect "put padded (spaces)"     "ok previous="      put padded "  spaced  "
22:expect "put padded again"        "ok previous=\"  spaced  \"" put padded again
   put padded (spaces)          -> ok previous=none position=608 replayed=false
   put padded again             -> ok previous="  spaced  " position=704 replayed=false
PASS
[exit 0]

$ sed -i 's/^expect "put padded again" .*/expect "put padded again"        "ok previous="      put padded again/' scripts/demo.sh && sed -n 17,23p scripts/demo.sh && git commit -qam 'demo: exercise put with a padded value' && echo committed
expect "put greeting hello"      'ok previous='       put greeting hello
expect "get greeting"            'value="hello"'      get greeting --linearizable
expect "delete greeting"         'ok removed="hello"' delete greeting
expect "get greeting (deleted)"  'value=none'         get greeting --linearizable
expect "put padded (spaces)"     "ok previous="      put padded "  spaced  "
expect "put padded again"        "ok previous="      put padded again
[ $fails -eq 0 ] || { echo "FAIL ($fails)"; exit 1; }
committed
[exit 0]

$ make corpus
cargo build --release
    Finished `release` profile [optimized] target(s) in 0.03s
scripts/corpus.sh
1. instant P=1088, complete on node 0
2. ran scripts/demo.sh above P; node 0 durable to 1472
corpus at upgrade/corpus — row 0 origin 1088 end 18446744073709551615
3. corpus at upgrade/corpus (from P=1088); old service binary at upgrade/old/
next: change the code, bump FSM_VERSION in src/identity.rs, declare the change in upgrade/intent.toml, run make upgrade-check
[exit 0]

$ ls upgrade upgrade/old; cat upgrade/corpus/CORPUS
upgrade:
corpus
intent.toml
intent.toml.example
old

upgrade/old:
p2-app-service
format=uc2-corpus-v1
app_id=p2
row=0
origin=1088
end=18446744073709551615
version=0x0
[exit 0]

$ sed -i 's/previous: self.state.entries.insert(key, value),/previous: self.state.entries.insert(key, value.trim().to_string()),/' src/state.rs && sed -i 's/pack_version(1, 0, 0)/pack_version(1, 1, 0)/' src/identity.rs && git diff --stat src && git diff src | grep '^[-+] '
 src/identity.rs | 2 +-
 src/state.rs    | 2 +-
 2 files changed, 2 insertions(+), 2 deletions(-)
-                previous: self.state.entries.insert(key, value),
+                previous: self.state.entries.insert(key, value.trim().to_string()),
[exit 0]

$ cat > upgrade/intent.toml <<'EOF'
tag_offset = 16

[tags]
"00" = "put"
"01" = "delete"

[touched]
arms = ["put"]
migration = false

[[expect]]
surface = "response"
arm = "put"
note = "put trims the value, so a later put's previous differs"
EOF
cat upgrade/intent.toml
tag_offset = 16

[tags]
"00" = "put"
"01" = "delete"

[touched]
arms = ["put"]
migration = false

[[expect]]
surface = "response"
arm = "put"
note = "put trims the value, so a later put's previous differs"
[exit 0]

$ UC_CONFIRM_PIN=yes make upgrade-drill
scripts/upgrade-drill.sh
upgrade-drill.sh: run make upgrade-check first (diff-replay must PASS before a pin)
make: *** [Makefile:60: upgrade-drill] Error 3
[exit 2]

$ make upgrade-check
scripts/upgrade-check.sh
diff replay — upgrade — corpus upgrade/corpus
  divergences: 1 entries, 0 only in a, 0 only in b, origin projection 0−/0+, end projection 0−/0+
  Pass        response           arm=put        pos=1408     put trims the value, so a later put's previous differs
  1 pass, 0 undeclared, 0 unexplained, 0 absent → PASS
PASS — every difference is declared and attributed
[exit 0]

$ cp upgrade/intent.toml upgrade/intent.keep && cp upgrade/intent.toml.example upgrade/intent.toml && make upgrade-check; rc=$?; mv upgrade/intent.keep upgrade/intent.toml; exit $rc
scripts/upgrade-check.sh
diff replay — upgrade — corpus upgrade/corpus
  divergences: 1 entries, 0 only in a, 0 only in b, origin projection 0−/0+, end projection 0−/0+
  Unexplained response           arm=-          pos=1408     no touched arm explains this
  0 pass, 0 undeclared, 1 unexplained, 0 absent → FAIL
FAIL — read upgrade/report.json (Undeclared / Unexplained / Absent); the upgrade-fsm skill explains each
make: *** [Makefile:54: upgrade-check] Error 1
[exit 2]

$ make upgrade-check
scripts/upgrade-check.sh
diff replay — upgrade — corpus upgrade/corpus
  divergences: 1 entries, 0 only in a, 0 only in b, origin projection 0−/0+, end projection 0−/0+
  Pass        response           arm=put        pos=1408     put trims the value, so a later put's previous differs
  1 pass, 0 undeclared, 0 unexplained, 0 absent → PASS
PASS — every difference is declared and attributed
[exit 0]

$ make upgrade-drill </dev/null
scripts/upgrade-drill.sh
About to upgrade row 0 (p2) from 1.0.0 to 1.1.0 on the local cluster at /home/claude/scratch/t8c-root.
After the pin commits there is NO unpin: the old binary is refused by name,
and the only way back is restoring the backups this script takes first.
upgrade-drill.sh: not a terminal and UC_CONFIRM_PIN != yes — refusing to pin
make: *** [Makefile:60: upgrade-drill] Error 3
[exit 2]

$ scripts/upgrade-drill.sh </dev/null; echo script-exit=$?
About to upgrade row 0 (p2) from 1.0.0 to 1.1.0 on the local cluster at /home/claude/scratch/t8c-root.
After the pin commits there is NO unpin: the old binary is refused by name,
and the only way back is restoring the backups this script takes first.
upgrade-drill.sh: not a terminal and UC_CONFIRM_PIN != yes — refusing to pin
script-exit=3
[exit 0]

$ scripts/cluster.sh ctl 0 upgrade pin --row 0 --to 9.9.9 --origin 1; echo script-exit=$?
cluster.sh: refusing 'upgrade pin' without UC_CONFIRM_PIN=yes — a pin is a one-way door (WHAT-NEXT.md, Step 12)
script-exit=3
[exit 0]

$ echo nope | script -qec 'scripts/upgrade-drill.sh' /dev/null; echo
nope
About to upgrade row 0 (p2) from 1.0.0 to 1.1.0 on the local cluster at /home/claude/scratch/t8c-root.
After the pin commits there is NO unpin: the old binary is refused by name,
and the only way back is restoring the backups this script takes first.
Type PIN to continue: upgrade-drill.sh: not confirmed — nothing was changed

[exit 0]

$ scripts/cluster.sh status | grep -E 'row=0'
  row=0 name=p2 version=1.0.0 hash=0x08d59607b575e907 attached=true epoch=1 incarnation=1 applied=1472 lag=0 snapshot_pos=1088 heartbeat_age=0.000s timers_pending=0 upgrade_origin=0 pinned=unversioned pinned_from=unversioned artifact_hash=0x98aab443bdabb104
  row=0 name=p2 version=1.0.0 hash=0x08d59607b575e907 attached=true epoch=2 incarnation=2 applied=1472 lag=0 snapshot_pos=1088 heartbeat_age=0.000s timers_pending=0 upgrade_origin=0 pinned=unversioned pinned_from=unversioned artifact_hash=0x98aab443bdabb104
  row=0 name=p2 version=1.0.0 hash=0x08d59607b575e907 attached=true epoch=2 incarnation=2 applied=1472 lag=0 snapshot_pos=1088 heartbeat_age=0.000s timers_pending=0 upgrade_origin=0 pinned=unversioned pinned_from=unversioned artifact_hash=0x98aab443bdabb104
[exit 0]

$ cp upgrade/intent.toml upgrade/intent.keep && echo '# edited' >> upgrade/intent.toml && UC_CONFIRM_PIN=yes scripts/upgrade-drill.sh; echo script-exit=$?; mv upgrade/intent.keep upgrade/intent.toml
upgrade-drill.sh: the code or upgrade/intent.toml changed since make upgrade-check passed — run it again (diff-replay must PASS for the code you pin)
script-exit=3
[exit 0]

$ UC_CONFIRM_PIN=yes make upgrade-drill
scripts/upgrade-drill.sh
About to upgrade row 0 (p2) from 1.0.0 to 1.1.0 on the local cluster at /home/claude/scratch/t8c-root.
After the pin commits there is NO unpin: the old binary is refused by name,
and the only way back is restoring the backups this script takes first.
1. origin instant P=1600, complete on every node
2. backups in /home/claude/scratch/t8c-root/backups/n*-pre-1.1.0-20260924-162114 (your rollback point; a running node backs up fine)
3. pinned: row=0 from=1.0.0 to=1.1.0 origin=1600 position=1760
4. every node shows the pin (pinned=1.1.0 upgrade_origin=1600)
5. stopped every service (all of them, before starting any)
6. started the new build everywhere
7. every node runs 1.1.0, installed snap-1600, and the pre-upgrade write reads back
   log: uc_service: row 0 pinned install of snap-1600 (from 0x01000000 to 0x01010000, artifact built by 0x01000000)
   log: uc_service: row 0 pinned install of snap-1600 (from 0x01000000 to 0x01010000, artifact built by 0x01000000)
   log: uc_service: row 0 pinned install of snap-1600 (from 0x01000000 to 0x01010000, artifact built by 0x01000000)
PASS
[exit 0]

$ scripts/cluster.sh status | grep -E 'row=0'
  row=0 name=p2 version=1.1.0 hash=0x08d59607b575e907 attached=true epoch=2 incarnation=2 applied=1760 lag=0 snapshot_pos=1600 heartbeat_age=0.000s timers_pending=0 upgrade_origin=1600 pinned=1.1.0 pinned_from=1.0.0 artifact_hash=0x4cba9e5bd5a402c3
  row=0 name=p2 version=1.1.0 hash=0x08d59607b575e907 attached=true epoch=3 incarnation=3 applied=1760 lag=0 snapshot_pos=1600 heartbeat_age=0.000s timers_pending=0 upgrade_origin=1600 pinned=1.1.0 pinned_from=1.0.0 artifact_hash=0x4cba9e5bd5a402c3
  row=0 name=p2 version=1.1.0 hash=0x08d59607b575e907 attached=true epoch=3 incarnation=3 applied=1760 lag=0 snapshot_pos=1600 heartbeat_age=0.000s timers_pending=0 upgrade_origin=1600 pinned=1.1.0 pinned_from=1.0.0 artifact_hash=0x4cba9e5bd5a402c3
[exit 0]

$ timeout 20 upgrade/old/p2-app-service --instance-dir $UC_ROOT/n1 --app-id p2; echo old-binary-exit=$?
Error: another process already holds FSM "p2" at row 0 on this instance dir (service.0.lock)
old-binary-exit=1
[exit 0]

$ T=$(cargo metadata --format-version=1 --no-deps | sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p')/release; $T/p2-app put trimmed '  hi  ' && $T/p2-app get trimmed --linearizable
ok previous=none position=1760 replayed=false
value="hi"
[exit 0]

$ make demo
scripts/demo.sh
demo against 127.0.0.1:7900,127.0.0.1:7901,127.0.0.1:7902
   put greeting hello           -> ok previous=none position=1824 replayed=false
   get greeting                 -> value="hello"
   delete greeting              -> ok removed="hello" position=1888 replayed=false
   get greeting (deleted)       -> value=none
   put padded (spaces)          -> ok previous="again" position=1952 replayed=false
   put padded again             -> ok previous="spaced" position=2048 replayed=false
PASS
[exit 0]

$ make next
Step 3/13 · Part 1 · SMR in five minutes → WHAT-NEXT.md "Step 3"
  status: todo
  - read WHAT-NEXT.md Step 3, then: make done STEP=concepts
[exit 0]

$ scripts/cluster.sh stop service 1; timeout 20 upgrade/old/p2-app-service --instance-dir $UC_ROOT/n1 --app-id p2; echo old-binary-exit=$?; scripts/cluster.sh start service 1
   stopped service1 (pid 736615, SIGTERM)
Error: FSM "p2" at row 0 is pinned to version 0x01010000 from origin 1600, but this binary is 0x01000000; a stale binary cannot rejoin after `uc2ctl upgrade pin`
old-binary-exit=1
   started service1 (pid 737017)
[exit 0]

$ scripts/cluster.sh ctl 1 status | grep row=0
  row=0 name=p2 version=1.1.0 hash=0x08d59607b575e907 attached=true epoch=4 incarnation=4 applied=2112 lag=0 snapshot_pos=1600 heartbeat_age=0.000s timers_pending=0 upgrade_origin=1600 pinned=1.1.0 pinned_from=1.0.0 artifact_hash=0x4cba9e5bd5a402c3
[exit 0]

$ make package HOSTS=10.0.0.1,10.0.0.2,10.0.0.3
HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 scripts/package.sh
dist/p2-app-0.1.0-x86_64.tar.gz
before installing: create /etc/uc2/node.key, /etc/uc2/allowlist.toml ([crypto]) and /etc/uc2/admin/admin.key ([admin]) on each host — DEPLOY.md says how
[exit 0]

$ tar tzf dist/p2-app-0.1.0-$(uname -m).tar.gz
p2-app-0.1.0-x86_64/
p2-app-0.1.0-x86_64/DEPLOY.md
p2-app-0.1.0-x86_64/systemd/
p2-app-0.1.0-x86_64/systemd/uc2-service@.service
p2-app-0.1.0-x86_64/systemd/uc2-gateway.service
p2-app-0.1.0-x86_64/systemd/uc2-node.service
p2-app-0.1.0-x86_64/hosts/
p2-app-0.1.0-x86_64/hosts/10.0.0.2/
p2-app-0.1.0-x86_64/hosts/10.0.0.2/gateway.toml
p2-app-0.1.0-x86_64/hosts/10.0.0.2/node.toml
p2-app-0.1.0-x86_64/hosts/10.0.0.1/
p2-app-0.1.0-x86_64/hosts/10.0.0.1/gateway.toml
p2-app-0.1.0-x86_64/hosts/10.0.0.1/node.toml
p2-app-0.1.0-x86_64/hosts/10.0.0.3/
p2-app-0.1.0-x86_64/hosts/10.0.0.3/gateway.toml
p2-app-0.1.0-x86_64/hosts/10.0.0.3/node.toml
p2-app-0.1.0-x86_64/bin/
p2-app-0.1.0-x86_64/bin/p2-app-service
p2-app-0.1.0-x86_64/bin/p2-app
p2-app-0.1.0-x86_64/bin/uc2ctl
p2-app-0.1.0-x86_64/bin/uc2-node
p2-app-0.1.0-x86_64/bin/uc2-gateway
[exit 0]

$ cat dist/p2-app-0.1.0-$(uname -m)/hosts/10.0.0.2/node.toml dist/p2-app-0.1.0-$(uname -m)/hosts/10.0.0.2/gateway.toml; grep ExecStart dist/p2-app-0.1.0-$(uname -m)/systemd/*
id = 1
bind = "10.0.0.2:7801"
instance_dir = "/srv/uc2/p2-app"
app_id = "p2"

[[members]]
id = 0
addr = "10.0.0.1:7800"

[[members]]
id = 1
addr = "10.0.0.2:7801"

[[members]]
id = 2
addr = "10.0.0.3:7802"

# The state machine implements SnapshotStateMachine and the service starts
# with start_with_snapshots(); this is the other half of bounding the log.
[purge]
below_snapshot_slack_bytes = 1048576

[services]
names = ["p2"]

# Genesis seed only. snapshot_interval_bytes = 0 means instants are
# operator-commanded (uc2ctl snapshot); set UC_SNAPSHOT_INTERVAL for a cadence.
[settings]
snapshot_interval_bytes = 0
snapshot_target = "all"

[log]
level = "info"

# Unauthenticated: keep it on loopback or a private address.
[metrics]
bind = "10.0.0.2:8001"

[crypto]
enabled = true
key_path = "/etc/uc2/node.key"
allowlist_path = "/etc/uc2/allowlist.toml"

[admin]
auth = "hmac"
keys = [{ name = "admin", key_path = "/etc/uc2/admin/admin.key" }]
[local]
instance_dir = "/srv/uc2/p2-app"
app_id = "p2"
listen = "10.0.0.2:7901"

[[members]]
node_id = 0
gateway = "10.0.0.1:7900"

[[members]]
node_id = 1
gateway = "10.0.0.2:7901"

[[members]]
node_id = 2
gateway = "10.0.0.3:7902"

[limits]
# The client's exposure window to a node that died under this gateway.
request_timeout_ms = 2000

# The service runs Sessioned<Fsm>: the envelope is what makes a re-sent write
# answer "replayed" instead of applying twice.
[session]
envelope = true
dist/p2-app-0.1.0-x86_64/systemd/uc2-gateway.service:ExecStart=/usr/local/bin/uc2-gateway --config /etc/uc2/gateway.toml
dist/p2-app-0.1.0-x86_64/systemd/uc2-node.service:ExecStart=/usr/local/bin/uc2-node --config /etc/uc2/node.toml
dist/p2-app-0.1.0-x86_64/systemd/uc2-service@.service:ExecStart=/usr/local/bin/%i --instance-dir /srv/uc2/p2-app --app-id p2
[exit 0]

$ make package HOSTS=10.0.0.1,10.0.0.2; echo; make package HOSTS=10.0.0.1,0.0.0.0,10.0.0.3
HOSTS=10.0.0.1,10.0.0.2 scripts/package.sh
package.sh: HOSTS needs exactly three addresses: make package HOSTS=ip0,ip1,ip2
make: *** [Makefile:62: package] Error 3

HOSTS=10.0.0.1,0.0.0.0,10.0.0.3 scripts/package.sh
package.sh: '0.0.0.0' is not a host address (each node binds exactly its own address, never 0.0.0.0)
make: *** [Makefile:62: package] Error 3
[exit 2]

$ make down
scripts/cluster.sh down
   stopped service0 (pid 736592, SIGTERM)
   stopped gateway0 (pid 733895, SIGTERM)
   stopped service1 (pid 737017, SIGTERM)
   stopped gateway1 (pid 733901, SIGTERM)
   stopped service2 (pid 736638, SIGTERM)
   stopped gateway2 (pid 733907, SIGTERM)
   stopped node0 (pid 733803, SIGTERM)
   stopped node1 (pid 733807, SIGTERM)
   stopped node2 (pid 733811, SIGTERM)
[exit 0]
```
