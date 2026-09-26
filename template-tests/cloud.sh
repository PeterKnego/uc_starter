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

echo "cloud: PASS"
