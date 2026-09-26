#!/usr/bin/env bash
# Cloud-path contract, no cloud account needed: portable hashing, gateway
# rendering, package GATEWAYS/ARCH, cloud-infra preflight and guards, agent
# permissions. CLOUD_REQUIRE_CROSS=1 (CI) fails instead of skipping when
# cargo-zigbuild is missing.
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
b="$(HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 GATEWAYS=203.0.113.1,203.0.113.2,203.0.113.3 scripts/package.sh | head -1)"
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
  b="$(HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 ARCH=$other scripts/package.sh | head -1)"
  case "$b" in *"-$other.tar.gz") ;; *) fail "bundle name does not carry ARCH: $b" ;; esac
  x="$OUT/x-$other"; rm -rf "$x"; mkdir -p "$x"; tar xzf "$b" -C "$x"
  want='x86-64'; [ "$other" = aarch64 ] && want='aarch64'
  for f in "$x"/*/bin/*; do file -b "$f" | grep -q "ELF 64-bit.*$want" || fail "$(basename "$f") in the $other bundle: $(file -b "$f")"; done
  tar tzf "$b" | grep -q '/\._' && fail "AppleDouble ._ files in the bundle"
elif [ "${CLOUD_REQUIRE_CROSS:-0}" = 1 ]; then fail "cargo-zigbuild missing and CLOUD_REQUIRE_CROSS=1"
else echo "note: cargo-zigbuild not installed — cross build not checked"; fi
b="$(HOSTS=10.0.0.1,10.0.0.2,10.0.0.3 scripts/package.sh | head -1)"
case "$b" in *"-$mach.tar.gz") ;; *) fail "default ARCH is not this machine's: $b" ;; esac

# --- Task 5: terraform
if command -v terraform >/dev/null; then
  (cd cloud-infra/terraform && terraform init -backend=false -input=false >/dev/null \
    && terraform fmt -check -recursive && terraform validate >/dev/null && terraform test) \
    || fail "terraform init/fmt/validate/test"
  rm -rf cloud-infra/terraform/.terraform cloud-infra/terraform/.terraform.lock.hcl
else echo "note: terraform not installed — terraform checks skipped"; fi

# --- Task 6: control surface (no cloud: fake terraform that must not run)
FAKE="$OUT/fakebin"; mkdir -p "$FAKE"
printf '#!/bin/sh\necho "terraform must not run here" >&2; exit 1\n' >"$FAKE/terraform"
for t in ansible-playbook ansible; do printf '#!/bin/sh\nexit 0\n' >"$FAKE/$t"; done
chmod +x "$FAKE"/*
cmk() { env -u HCLOUD_TOKEN PATH="$FAKE:$PATH" make -s -C cloud-infra "$@"; }
out="$(cmk preflight 2>&1)" && fail "preflight passed without terraform.tfvars"
echo "$out" | grep -q 'cp cloud-infra/example.tfvars' || fail "preflight without tfvars: $out"
cp cloud-infra/example.tfvars cloud-infra/terraform.tfvars
printf '#!/bin/sh\necho '"'"'{"terraform_version":"1.6.0"}'"'"'\n' >"$FAKE/terraform"; chmod +x "$FAKE/terraform"
out="$(cmk preflight 2>&1)" && fail "preflight accepted terraform 1.6"
echo "$out" | grep -q 'need 1.7' || fail "old terraform: $out"
printf '#!/bin/sh\necho '"'"'{"terraform_version":"1.9.8"}'"'"'\n' >"$FAKE/terraform"; chmod +x "$FAKE/terraform"
out="$(cmk preflight 2>&1)" && fail "preflight passed without HCLOUD_TOKEN"
echo "$out" | grep -q 'HCLOUD_TOKEN' || fail "missing token: $out"
printf 'HCLOUD_TOKEN="abc"\n' >cloud-infra/.env
cmk env-show | grep -qx 'HCLOUD_TOKEN: set (3 chars)' || fail ".env quotes not stripped: $(cmk env-show)"
cmk env-show | grep -q 'abc' && fail "env-show printed a secret"
cmk env-show | grep -qE "^owner: demo-app-[a-z0-9-]+$" || fail "owner: $(cmk env-show)"
rm cloud-infra/.env
# destroy with no state: nothing to destroy, terraform not called, local files cleared
printf '#!/bin/sh\necho "terraform must not run here" >&2; exit 1\n' >"$FAKE/terraform"; chmod +x "$FAKE/terraform"
mkdir -p cloud-infra/.secrets; : >cloud-infra/.secrets/admin.key; : >cloud-infra/inventory/hosts.yml; : >cloud-infra/inventory/hosts.env
out="$(cmk destroy 2>&1)" || fail "destroy with no state failed: $out"
echo "$out" | grep -q 'nothing to destroy' || fail "destroy with no state: $out"
[ ! -e cloud-infra/.secrets/admin.key ] && [ ! -e cloud-infra/inventory/hosts.yml ] || fail "destroy left local cluster files"
mkdir -p cloud-infra/terraform; printf '{"version":4,"resources":[]}\n' >cloud-infra/terraform/terraform.tfstate
out="$(cmk destroy 2>&1)"; echo "$out" | grep -q 'nothing to destroy' || fail "destroy with an empty state: $out"
# destroy with a corrupt state: refuses, terraform never called, local files kept
mkdir -p cloud-infra/.secrets; : >cloud-infra/.secrets/admin.key; : >cloud-infra/inventory/hosts.env
printf 'not json' >cloud-infra/terraform/terraform.tfstate
out="$(cmk destroy 2>&1)" && fail "destroy accepted an unreadable terraform.tfstate"
echo "$out" | grep -q 'nothing was destroyed' || fail "corrupt state: $out"
[ -e cloud-infra/inventory/hosts.env ] || fail "destroy removed hosts.env for a state it could not read"
[ -e cloud-infra/.secrets/admin.key ] || fail "destroy removed admin.key for a state it could not read"
rm -f cloud-infra/terraform/terraform.tfstate cloud-infra/.secrets/admin.key cloud-infra/inventory/hosts.env cloud-infra/terraform.tfvars

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
else echo "note: ansible not installed — playbook syntax not checked"; fi

echo "cloud: PASS"
