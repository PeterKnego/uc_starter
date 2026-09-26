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

echo "cloud: PASS"
