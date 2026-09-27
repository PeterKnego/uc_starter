#!/usr/bin/env bash
# Cloud-path contract, no cloud account needed: portable hashing, gateway
# rendering, package GATEWAYS/ARCH, cloud-infra preflight and guards, agent
# permissions. CLOUD_REQUIRE_CROSS=1 (CI) fails instead of skipping when
# cargo-zigbuild is missing. CLOUD_REQUIRE_TOOLS=1 (CI) fails instead of
# skipping when terraform or ansible-playbook is missing.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HOME/scratch/uc_starter-gen/cloud"
rm -rf "$OUT"; mkdir -p "$OUT"
fail() { echo "FAIL: $*" >&2; exit 1; }
"$HERE/gen.sh" "$OUT" >/dev/null
P="$OUT/demo-app"; cd "$P"
lib() { bash -c ". scripts/lib.sh; $1"; }

# --- Task 1: portable hashing, target dir, overrides
mkdir -p "$OUT/nosha"
for t in shasum dirname cat cut; do ln -sf "$(command -v "$t")" "$OUT/nosha/$t"; done
want="$(printf abc | sha256sum | cut -c1-64)"
got="$(printf abc | PATH="$OUT/nosha" /bin/bash -c '. scripts/lib.sh; sha256_stdin' | cut -c1-64)"
[ "$got" = "$want" ] || fail "sha256_stdin without sha256sum: got '$got'"
ref="$(for p in src Cargo.toml Cargo.lock; do if [ -e "$p" ]; then find "$p" -type f -not -path '*/target/*' -not -name '.*.sw?' -not -name '*~' -not -name '.#*' -print0; fi; done | LC_ALL=C sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -c1-16)"
[ "$(lib code_hash)" = "$ref" ] || fail "tree_hash output changed (stamps would go stale across machines)"
printf 'deadbeef  x.tar.gz\n' >"$OUT/SUMS"; printf 'x' >"$OUT/x.tar.gz"
if lib "verify_sha256 '$OUT/SUMS' '$OUT/x.tar.gz'"; then fail "verify_sha256 accepted a wrong checksum"; fi
printf '%s  x.tar.gz\n' "$(printf x | sha256sum | cut -c1-64)" >"$OUT/SUMS"
lib "verify_sha256 '$OUT/SUMS' '$OUT/x.tar.gz'" || fail "verify_sha256 refused a right checksum"
[ "$(UC_GATEWAYS=a:1,b:2,c:3 lib gateways_csv)" = "a:1,b:2,c:3" ] || fail "gateways_csv ignores UC_GATEWAYS"
[ "$(lib gateways_csv)" = "127.0.0.1:7100,127.0.0.1:7101,127.0.0.1:7102" ] || fail "gateways_csv default changed"
[ "$(lib app_bin_dir)" = "$(lib app_target_dir)/release" ] || fail "app_bin_dir is not app_target_dir/release"
grep -q 'UC_CLIENT' scripts/demo.sh || fail "demo.sh has no UC_CLIENT override"

# --- Task 2: public gateway addresses
diff <(lib 'render_gateway_toml 0 /srv/uc2/demo-app 10.0.0.1 10.0.0.2 10.0.0.3') "$HERE/fixtures/gateway-0.toml" \
  || fail "gateway.toml without GATEWAYS is not byte-identical to before"
g="$(lib 'render_gateway_toml 1 /srv/uc2/demo-app 10.0.0.1 10.0.0.2 10.0.0.3 203.0.113.1 203.0.113.2 203.0.113.3')"
echo "$g" | grep -qx 'listen = "0.0.0.0:7101"' || fail "with public addresses the gateway must listen on 0.0.0.0"
for i in 0 1 2; do echo "$g" | grep -qx "gateway = \"203.0.113.$((i+1)):710$i\"" || fail "member $i is not its public address"; done
echo "$g" | grep -q '10.0.0' && fail "a private address leaked into gateway.toml members"
out="$(HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 GATEWAYS=1.2.3.4,1.2.3.4,5.6.7.8 scripts/package.sh 2>&1)" && fail "duplicate GATEWAYS accepted"
echo "$out" | grep -q 'GATEWAYS must be three different' || fail "duplicate GATEWAYS: wrong message: $out"
out="$(HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 GATEWAYS=0.0.0.0,1.2.3.4,5.6.7.8 scripts/package.sh 2>&1)" && fail "GATEWAYS 0.0.0.0 accepted"
make -s bins >/dev/null
b="$(HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 GATEWAYS=203.0.113.1,203.0.113.2,203.0.113.3 scripts/package.sh | sed -n 1p)"
tar xzf "$b" -O "$(basename "$b" .tar.gz)/hosts/10.0.0.1/gateway.toml" | grep -qx 'gateway = "203.0.113.1:7100"' || fail "bundle gateway.toml lacks the public member"
tar xzf "$b" -O "$(basename "$b" .tar.gz)/hosts/10.0.0.1/node.toml" | grep -qx 'bind = "10.0.0.1:7000"' || fail "bundle node.toml must bind the private address"

# --- Task 3: target architecture
out="$(HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 ARCH=sparc scripts/package.sh 2>&1)" && fail "ARCH=sparc accepted"
echo "$out" | grep -q 'ARCH must be x86_64 or aarch64' || fail "ARCH=sparc: wrong message: $out"
out="$(scripts/fetch-uc.sh --arch sparc 2>&1)" && fail "fetch-uc --arch sparc accepted"
mach="$(uname -m)"; [ "$mach" = arm64 ] && mach=aarch64
other=aarch64; [ "$mach" = aarch64 ] && other=x86_64
scripts/fetch-uc.sh --arch "$other" >/dev/null
file -b .uc/dist/$other/bin/uc2-node | grep -q "ELF 64-bit" || fail ".uc/dist/$other/bin/uc2-node is not an ELF"
[ "$(cat .uc/dist/$other/VERSION)" = "$(cat UC_VERSION)" ] || fail ".uc/dist/$other/VERSION"
scripts/fetch-uc.sh --arch "$other" | grep -q already || fail "second fetch-uc --arch re-downloaded"
[ -x .uc/bin/uc2-node ] || fail "fetch-uc --arch touched .uc/bin"
if command -v cargo-zigbuild >/dev/null; then
  b="$(HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 ARCH=$other scripts/package.sh | sed -n 1p)"
  case "$b" in *"-$other.tar.gz") ;; *) fail "bundle name does not carry ARCH: $b" ;; esac
  x="$OUT/x-$other"; rm -rf "$x"; mkdir -p "$x"; tar xzf "$b" -C "$x"
  want='x86-64'; [ "$other" = aarch64 ] && want='aarch64'
  for f in "$x"/*/bin/*; do file -b "$f" | grep -q "ELF 64-bit.*$want" || fail "$(basename "$f") in the $other bundle: $(file -b "$f")"; done
  tar tzf "$b" | grep -q '/\._' && fail "AppleDouble ._ files in the bundle"
elif [ "${CLOUD_REQUIRE_CROSS:-0}" = 1 ]; then fail "cargo-zigbuild missing and CLOUD_REQUIRE_CROSS=1"
else echo "note: cargo-zigbuild not installed — cross build not checked"; fi
b="$(HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 scripts/package.sh | sed -n 1p)"
case "$b" in *"-$mach.tar.gz") ;; *) fail "default ARCH is not this machine's: $b" ;; esac

# --- Task 5: terraform
if command -v terraform >/dev/null; then
  (cd cloud-infra/terraform && terraform init -backend=false -input=false >/dev/null \
    && terraform fmt -check -recursive && terraform validate >/dev/null && terraform test) \
    || fail "terraform init/fmt/validate/test"
  rm -rf cloud-infra/terraform/.terraform cloud-infra/terraform/.terraform.lock.hcl
elif [ "${CLOUD_REQUIRE_TOOLS:-0}" = 1 ]; then fail "terraform missing and CLOUD_REQUIRE_TOOLS=1"
else echo "note: terraform not installed — terraform checks skipped"; fi

# --- Task 6: control surface (no cloud: fake terraform that must not run)
FAKE="$OUT/fakebin"; mkdir -p "$FAKE"
printf '#!/bin/sh\necho "terraform must not run here" >&2; exit 1\n' >"$FAKE/terraform"
for t in ansible-playbook ansible; do printf '#!/bin/sh\nexit 0\n' >"$FAKE/$t"; done
chmod +x "$FAKE"/*
cmk() { env -u HCLOUD_TOKEN PATH="$FAKE:$PATH" make -s -C cloud-infra "$@"; }
out="$(cmk cloud-preflight 2>&1)" && fail "preflight passed without terraform.tfvars"
echo "$out" | grep -q 'cp cloud-infra/example.tfvars' || fail "preflight without tfvars: $out"
cp cloud-infra/example.tfvars cloud-infra/terraform.tfvars
printf '#!/bin/sh\necho '"'"'{"terraform_version":"1.6.0"}'"'"'\n' >"$FAKE/terraform"; chmod +x "$FAKE/terraform"
out="$(cmk cloud-preflight 2>&1)" && fail "preflight accepted terraform 1.6"
echo "$out" | grep -q 'need 1.7' || fail "old terraform: $out"
printf '#!/bin/sh\necho '"'"'{"terraform_version":"1.9.8"}'"'"'\n' >"$FAKE/terraform"; chmod +x "$FAKE/terraform"
out="$(cmk cloud-preflight 2>&1)" && fail "preflight passed without HCLOUD_TOKEN"
echo "$out" | grep -q 'HCLOUD_TOKEN' || fail "missing token: $out"
printf 'HCLOUD_TOKEN="abc"\n' >cloud-infra/.env
cmk cloud-env-show | grep -qx 'HCLOUD_TOKEN: set (3 chars)' || fail ".env quotes not stripped: $(cmk cloud-env-show)"
cmk cloud-env-show | grep -q 'abc' && fail "env-show printed a secret"
cmk cloud-env-show | grep -qE "^owner: demo-app-[a-z0-9-]+$" || fail "owner: $(cmk cloud-env-show)"
rm cloud-infra/.env
# destroy with no state: nothing to destroy, terraform not called, local files cleared
printf '#!/bin/sh\necho "terraform must not run here" >&2; exit 1\n' >"$FAKE/terraform"; chmod +x "$FAKE/terraform"
mkdir -p cloud-infra/.secrets; : >cloud-infra/.secrets/admin.key; : >cloud-infra/inventory/hosts.yml; : >cloud-infra/inventory/hosts.env
out="$(cmk cloud-destroy 2>&1)" || fail "destroy with no state failed: $out"
echo "$out" | grep -q 'nothing to destroy' || fail "destroy with no state: $out"
[ ! -e cloud-infra/.secrets/admin.key ] && [ ! -e cloud-infra/inventory/hosts.yml ] || fail "destroy left local cluster files"
mkdir -p cloud-infra/terraform; printf '{"version":4,"resources":[]}\n' >cloud-infra/terraform/terraform.tfstate
out="$(cmk cloud-destroy 2>&1)"; echo "$out" | grep -q 'nothing to destroy' || fail "destroy with an empty state: $out"
# destroy with a corrupt state: refuses, terraform never called, local files kept
mkdir -p cloud-infra/.secrets; : >cloud-infra/.secrets/admin.key; : >cloud-infra/inventory/hosts.env
printf 'not json' >cloud-infra/terraform/terraform.tfstate
out="$(cmk cloud-destroy 2>&1)" && fail "destroy accepted an unreadable terraform.tfstate"
echo "$out" | grep -q 'nothing was destroyed' || fail "corrupt state: $out"
[ -e cloud-infra/inventory/hosts.env ] || fail "destroy removed hosts.env for a state it could not read"
[ -e cloud-infra/.secrets/admin.key ] || fail "destroy removed admin.key for a state it could not read"
rm -f cloud-infra/terraform/terraform.tfstate cloud-infra/.secrets/admin.key cloud-infra/inventory/hosts.env cloud-infra/terraform.tfvars

# cloud-up refuses and builds before anything bills (spec §9): preflight wants
# this UC release in .uc/bin on a native build, and the build runs before apply.
TV="$OUT/fake-tfv"; mkdir -p "$TV"
printf '#!/bin/sh\necho '"'"'{"terraform_version":"1.9.8"}'"'"'\n' >"$TV/terraform"; chmod +x "$TV/terraform"
: >"$OUT/idkey"
{ grep -vE '^(arch|ssh_private_key_file)[[:space:]]' cloud-infra/example.tfvars
  echo "arch = \"$mach\""; echo "ssh_private_key_file = \"$OUT/idkey\""; } >cloud-infra/terraform.tfvars
printf 'HCLOUD_TOKEN=abc\n' >cloud-infra/.env
pmk() { PATH="$TV:$PATH" make -s -C cloud-infra "$@"; }
pmk cloud-preflight >/dev/null || fail "preflight refused a complete native setup: $(pmk cloud-preflight 2>&1)"
mv .uc/bin/uc2-node "$OUT/uc2-node.real"
out="$(pmk cloud-preflight 2>&1)" && fail "preflight passed without .uc/bin/uc2-node"
echo "$out" | grep -q 'run make bins' || fail "preflight without bins: $out"
printf '#!/bin/sh\necho "uc2-node 2.12.0"\n' >.uc/bin/uc2-node; chmod +x .uc/bin/uc2-node
out="$(pmk cloud-preflight 2>&1)" && fail "preflight accepted .uc/bin from another UC release"
echo "$out" | grep -q 'run make bins' || fail "preflight with another UC: $out"
mv "$OUT/uc2-node.real" .uc/bin/uc2-node
order="$(make -n -C cloud-infra cloud-up 2>/dev/null | sed -nE 's|.*scripts/([a-z]+)\.sh.*|\1|p' | tr '\n' ' ')"
[ "$order" = "preflight build apply inventory deploy " ] || fail "cloud-up order (build must come before apply): $order"
make -n -C cloud-infra cloud-plan 2>/dev/null | grep -q 'scripts/apply.sh --plan' || fail "no make cloud-plan"
CLOUD_INFRA_MAKE=1 cloud-infra/scripts/build.sh >/dev/null 2>&1 || fail "build.sh failed on the skeleton"
cp src/lib.rs "$OUT/lib.rs.orig"; echo 'this does not compile' >>src/lib.rs
out="$(CLOUD_INFRA_MAKE=1 cloud-infra/scripts/build.sh 2>&1)" && fail "build.sh passed a compile error"
cp "$OUT/lib.rs.orig" src/lib.rs
rm -f cloud-infra/.env cloud-infra/terraform.tfvars

# apply.sh: plan first; a plan that destroys or replaces hosts is refused
# unless REPLACE=1, which also forgets the replaced hosts' SSH host keys.
TP="$OUT/fake-tfplan"; mkdir -p "$TP"
cat >"$TP/terraform" <<EOF
#!/bin/sh
for a; do case "\$a" in -chdir=*) ;; *) sub="\$a"; break ;; esac; done
echo "\$sub" >>"$OUT/tf.log"
[ "\$sub" = show ] && cat "$OUT/plan.json"
exit 0
EOF
chmod +x "$TP/terraform"
printf 'CLOUD=hetzner\nSSH_USER=root\nSSH_KEY=/nonexistent\nNODE0_PUBLIC=192.0.2.1\nNODE1_PUBLIC=192.0.2.2\nNODE2_PUBLIC=192.0.2.3\n' >cloud-infra/inventory/hosts.env
rm -f "$OUT/hk" "$OUT/hk.pub"; ssh-keygen -q -t ed25519 -N '' -f "$OUT/hk"
hkeys() { mkdir -p cloud-infra/.secrets; for i in 1 2 3; do echo "192.0.2.$i $(cut -d' ' -f1,2 "$OUT/hk.pub")"; done >cloud-infra/.secrets/known_hosts; echo x >cloud-infra/.secrets/deployed-code-hash; }
ap() { : >"$OUT/tf.log"; env CLOUD_INFRA_MAKE=1 PATH="$TP:$PATH" "$@" cloud-infra/scripts/apply.sh ${APPLY_ARG:-} 2>&1; }
echo '{"resource_changes":[{"address":"module.hetzner[0].hcloud_firewall.this","change":{"actions":["update"]}},{"address":"module.hetzner[0].hcloud_server.node[1]","change":{"actions":["delete","create"]}}]}' >"$OUT/plan.json"
hkeys
out="$(ap)" && fail "apply.sh accepted a plan that replaces a host"
echo "$out" | grep -q 'REPLACE=1' || fail "replace refused without naming REPLACE=1: $out"
echo "$out" | grep -q 'hcloud_server.node\[1\]' || fail "replace refusal does not name the resource: $out"
grep -qx apply "$OUT/tf.log" && fail "apply.sh ran terraform apply on a refused plan"
grep -q '^192.0.2.2 ' cloud-infra/.secrets/known_hosts || fail "a refused plan changed known_hosts"
[ ! -e cloud-infra/terraform/cloud-up.tfplan ] || fail "apply.sh left its plan file"
out="$(APPLY_ARG=--plan ap)" || fail "cloud-plan failed: $out"
echo "$out" | grep -q 'would DESTROY or REPLACE' || fail "cloud-plan does not name the replacement: $out"
grep -qx apply "$OUT/tf.log" && fail "cloud-plan ran terraform apply"
out="$(ap REPLACE=1)" || fail "apply.sh REPLACE=1 refused: $out"
grep -qx apply "$OUT/tf.log" || fail "apply.sh REPLACE=1 did not apply"
grep -q '^192.0.2.2 ' cloud-infra/.secrets/known_hosts && fail "REPLACE=1 kept the replaced host's key"
grep -q '^192.0.2.1 ' cloud-infra/.secrets/known_hosts || fail "REPLACE=1 dropped a kept host's key"
[ ! -e cloud-infra/.secrets/deployed-code-hash ] || fail "REPLACE=1 kept deployed-code-hash (deploy.sh would skip the new hosts)"
echo '{"resource_changes":[{"address":"module.hetzner[0].hcloud_firewall.this","change":{"actions":["update"]}}]}' >"$OUT/plan.json"
hkeys
out="$(ap)" || fail "apply.sh refused an in-place update: $out"
grep -qx apply "$OUT/tf.log" || fail "apply.sh did not apply an in-place update"
[ -e cloud-infra/.secrets/deployed-code-hash ] || fail "an in-place update dropped deployed-code-hash"
rm -f cloud-infra/inventory/hosts.env cloud-infra/.secrets/known_hosts cloud-infra/.secrets/deployed-code-hash

# cloud-oneshot destroys even when it is killed part-way (TERM here; INT/HUP alike).
cat >"$OUT/fakemake" <<EOF
#!/bin/sh
echo "\$1" >>"$OUT/oneshot.log"
[ "\$1" = cloud-up ] && [ -n "\${ONESHOT_HANG:-}" ] && exec sleep 30
exit 0
EOF
chmod +x "$OUT/fakemake"
: >"$OUT/oneshot.log"; make -s -C cloud-infra cloud-oneshot MAKE="$OUT/fakemake" >/dev/null 2>&1 || fail "oneshot with passing steps failed"
[ "$(tr '\n' ' ' <"$OUT/oneshot.log")" = "cloud-up cloud-test cloud-destroy " ] || fail "oneshot steps: $(cat "$OUT/oneshot.log")"
if command -v setsid >/dev/null; then
  : >"$OUT/oneshot.log"
  ONESHOT_HANG=1 setsid make -s -C cloud-infra cloud-oneshot MAKE="$OUT/fakemake" >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 100); do grep -q cloud-up "$OUT/oneshot.log" && break; sleep 0.1; done
  kill -TERM -- "-$pid"; wait "$pid" || true
  grep -qx cloud-destroy "$OUT/oneshot.log" || fail "a killed cloud-oneshot did not destroy: $(tr '\n' ' ' <"$OUT/oneshot.log")"
  grep -qx cloud-test "$OUT/oneshot.log" && fail "a killed cloud-oneshot went on to cloud-test"
else echo "note: setsid not installed — interrupted oneshot not checked"; fi

# --- Task 7: deploy — guards and playbook syntax
g() { bash -c ". cloud-infra/scripts/common.sh; $1" 2>&1; }
g 'fsm_guard_decide 1.0.0 1.0.0' >/dev/null || fail "fsm guard refused the same version"
out="$(g 'fsm_guard_decide 1.0.0 1.1.0')" && fail "fsm guard accepted 1.0.0 → 1.1.0"
echo "$out" | grep -q 'make cloud-destroy' || fail "fsm guard message: $out"
out="$(g 'fsm_guard_decide "" 1.0.0')" && fail "fsm guard accepted an unreadable running version"
g 'uc_guard_decide "uc2-node 2.13.0" 2.13.0' >/dev/null || fail "uc guard refused the same UC"
out="$(g 'uc_guard_decide "uc2-node 2.12.0" 2.13.0')" && fail "uc guard accepted a UC change"
out="$(g 'uc_guard_decide "uc2-node 12.13.0" 2.13.0')" && fail "uc guard accepted 2.13.0 as a bare suffix of 12.13.0"
echo "$out" | grep -q 'make cloud-destroy' || fail "uc guard suffix-match message: $out"
out="$(g 'uc_guard_decide "uc2-node 2.13.0" ""')" && fail "uc guard accepted an empty UC_VERSION"
if command -v ansible-playbook >/dev/null; then
  printf 'all:\n  children:\n    cluster:\n      hosts:\n        n0: {node_id: "0", private_ip: 10.10.1.10}\n' >"$OUT/inv.yml"
  for pb in deploy serve; do
    ANSIBLE_CONFIG=cloud-infra/ansible/ansible.cfg ansible-playbook -i "$OUT/inv.yml" --syntax-check cloud-infra/ansible/$pb.yml >/dev/null \
      || fail "ansible syntax: $pb.yml"
  done
elif [ "${CLOUD_REQUIRE_TOOLS:-0}" = 1 ]; then fail "ansible-playbook missing and CLOUD_REQUIRE_TOOLS=1"
else echo "note: ansible not installed — playbook syntax not checked"; fi

# --- Task 8: test/status decisions, unreachable hosts
mkdir -p cloud-infra/.secrets
out="$(g stamp_decision)" && fail "stamp_decision accepted a missing deployed-code-hash"
echo "$out" | grep -q 'make cloud-deploy' || fail "stamp_decision message: $out"
echo stale >cloud-infra/.secrets/deployed-code-hash
g stamp_decision >/dev/null && fail "stamp_decision accepted a stale deployed hash"
bash -c '. scripts/lib.sh; code_hash' >cloud-infra/.secrets/deployed-code-hash
g stamp_decision >/dev/null || fail "stamp_decision refused the current code"
out="$(g 'ttl_note 3600 4')"; [ -z "$out" ] || fail "ttl_note warned inside the TTL"
out="$(g 'ttl_note 14401 4')"; echo "$out" | grep -q 'past ttl_hours=4' || fail "ttl_note did not warn past the TTL"
cat >cloud-infra/inventory/hosts.env <<'EOF'
CLOUD=hetzner
REGION=nbg1
INSTANCE_TYPE=cpx21
ARCH=x86_64
TTL_HOURS=4
SSH_USER=root
SSH_KEY=/nonexistent
NODE0_PUBLIC=192.0.2.1
NODE0_PRIVATE=10.10.1.10
NODE1_PUBLIC=192.0.2.2
NODE1_PRIVATE=10.10.1.11
NODE2_PUBLIC=192.0.2.3
NODE2_PRIVATE=10.10.1.12
EOF
out="$(CLOUD_INFRA_MAKE=1 CLOUD_SSH_TIMEOUT=2 cloud-infra/scripts/status.sh 2>&1)" && fail "status passed against unreachable hosts"
echo "$out" | grep -q 'allow_ssh_cidr' || fail "unreachable host: no CIDR hint: $out"
# deploy.sh runs under set -e: an unreachable node0 must still get the hint.
FS="$OUT/fake-ssh"; mkdir -p "$FS"
printf '#!/bin/sh\necho "ssh: connect to host x port 22: Connection timed out" >&2; exit 255\n' >"$FS/ssh"; chmod +x "$FS/ssh"
out="$(CLOUD_INFRA_MAKE=1 PATH="$FS:$PATH" cloud-infra/scripts/deploy.sh 2>&1)" && fail "deploy.sh passed against unreachable hosts"
echo "$out" | grep -q 'allow_ssh_cidr' || fail "deploy.sh, unreachable host: no CIDR hint: $out"
# A cloud-up that failed after node0 first started resumes (spec §10): a stopped
# node's control page still reads, so only a completed deploy (deployed-code-hash)
# plus a running node0 counts as "already running".
cat >"$FS/ssh" <<'EOF'
#!/bin/sh
for a; do last="$a"; done
case "$last" in
  true) exit 0 ;;
  *"systemctl is-active"*) exit "${FAKE_NODE0_ACTIVE:-3}" ;;
  *"uc2ctl status"*) exit 0 ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\necho "ansible-playbook ran"; exit 1\n' >"$FS/ansible-playbook"; chmod +x "$FS/ssh" "$FS/ansible-playbook"
sed "s/^ARCH=.*/ARCH=$mach/" cloud-infra/inventory/hosts.env >"$OUT/hosts.env" && cp "$OUT/hosts.env" cloud-infra/inventory/hosts.env
dep() { env CLOUD_INFRA_MAKE=1 PATH="$FS:$PATH" "$@" cloud-infra/scripts/deploy.sh 2>&1; }
rm -f cloud-infra/.secrets/deployed-code-hash
out="$(dep FAKE_NODE0_ACTIVE=0)" && fail "deploy.sh (fake ansible fails) exited 0 after a partial deploy"
echo "$out" | grep -q 'already running' && fail "deploy.sh skipped a deploy that never completed: $out"
echo "$out" | grep -q 'ansible-playbook ran' || fail "deploy.sh did not redeploy after a partial deploy: $out"
echo x >cloud-infra/.secrets/deployed-code-hash
out="$(dep FAKE_NODE0_ACTIVE=3)" && fail "deploy.sh (fake ansible fails) exited 0 with node0 stopped"
echo "$out" | grep -q 'ansible-playbook ran' || fail "deploy.sh did not redeploy with node0 stopped: $out"
out="$(dep FAKE_NODE0_ACTIVE=0)" || fail "deploy.sh on a complete, running cluster failed: $out"
echo "$out" | grep -q 'already running' || fail "deploy.sh redeployed a complete, running cluster: $out"
out="$(CLOUD_INFRA_MAKE=1 cloud-infra/scripts/logs.sh 7 node 10 2>&1)" && fail "logs accepted HOST=7"
out="$(CLOUD_INFRA_MAKE=1 cloud-infra/scripts/logs.sh 0 disk 10 2>&1)" && fail "logs accepted PROC=disk"
rm -f cloud-infra/inventory/hosts.env cloud-infra/.secrets/deployed-code-hash

# --- Task 9: agent permissions and ignores
python3 - <<'PY' || fail "settings.json ask rules do not correctly gate cloud/terraform/ansible commands"
import json, fnmatch
ask = [r[len("Bash("):-1] for r in json.load(open(".claude/settings.json"))["permissions"]["ask"]]
must = [
    "make cloud-up", "make cloud-destroy",
    "make -C cloud-infra cloud-destroy", "make -C cloud-infra cloud-env-show",
    "cd cloud-infra && make cloud-destroy",
    "terraform apply", "terraform -chdir=cloud-infra/terraform destroy",
    "ansible-playbook deploy.yml", "ansible cluster -m ping",
    "CLOUD_INFRA_MAKE=1 cloud-infra/scripts/destroy.sh",
    "CLOUD_INFRA_MAKE=1 bash cloud-infra/scripts/deploy.sh --restart",
    "TF_LOG=1 terraform -chdir=cloud-infra/terraform destroy -auto-approve",
    "/usr/local/bin/terraform destroy", "env terraform apply",
    "make cloud-plan", "make cloud-up REPLACE=1", "REPLACE=1 make -C cloud-infra cloud-up",
]
must_not = [
    "cat cloud-infra/README.md", "grep -rn foo cloud-infra/",
    "sed -n 1p cloud-infra/scripts/common.sh", "shellcheck -x cloud-infra/scripts/test.sh",
    "git diff main -- cloud-infra/", "cd /x/.superpowers/sdd/2026-09-26-cloud-infra && ls",
    "make check", "make up", "cat cloud-infra/terraform/main.tf",
    "shellcheck -x -S warning cloud-infra/scripts/apply.sh", "bash template-tests/cloud.sh",
]
missing = [c for c in must if not any(fnmatch.fnmatch(c, a) for a in ask)]
assert not missing, ("should ask but does not", missing)
over = [c for c in must_not if any(fnmatch.fnmatch(c, a) for a in ask)]
assert not over, ("asks but should not", over)
PY
for p in cloud-infra/.env cloud-infra/.secrets/admin.key cloud-infra/terraform.tfvars cloud-infra/terraform/terraform.tfstate cloud-infra/terraform/cloud-up.tfplan cloud-infra/inventory/hosts.yml cloud-infra/inventory/hosts.env; do
  git check-ignore -q "$p" || fail "$p is not gitignored"   # cargo-generate made the project a git repo
done
[ -f .claude/skills/cloud-infra/SKILL.md ] || fail "no cloud-infra skill"
grep -q '^9\. \*\*Cloud commands' AGENTS.md || fail "AGENTS.md has no hard rule 9"

# Rule-9 bypass: a cloud script run directly (not through make cloud-*) refuses.
out="$(cloud-infra/scripts/status.sh 2>&1)" && fail "status.sh ran directly without CLOUD_INFRA_MAKE"
echo "$out" | grep -q 'run this through make cloud-' || fail "direct script run: wrong message: $out"

# package.sh prints two lines under set -e; piped into head it can die of
# SIGPIPE, and under pipefail that fails the caller (after the hosts exist).
hits="$(grep -nE 'package\.sh[^|]*\|[[:space:]]*head' cloud-infra/scripts/*.sh "$HERE/../.github/workflows/"*.yml "$HERE/cloud.sh" || true)"
[ -z "$hits" ] || fail "package.sh piped into head (SIGPIPE under pipefail):
$hits"

# --- Task 11: the cloud path runs on macOS's stock bash 3.2
hits="$(grep -nE 'mapfile|readarray|declare -A|\$\{[A-Za-z_]+(,,|\^\^)\}|sed -i|^[^#]*[^_]sha256sum' \
  cloud-infra/scripts/*.sh scripts/package.sh scripts/fetch-uc.sh scripts/lib.sh | grep -v 'command -v sha256sum' || true)"
[ -z "$hits" ] || fail "bash-3.2/BSD-unsafe constructs on the cloud path:
$hits"
if [ -x /bin/bash ] && /bin/bash -c '[ "${BASH_VERSINFO[0]}" -lt 4 ]'; then
  HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 GATEWAYS=203.0.113.1,203.0.113.2,203.0.113.3 /bin/bash scripts/package.sh >/dev/null || fail "package.sh under /bin/bash 3.2"
fi

echo "cloud: PASS"
