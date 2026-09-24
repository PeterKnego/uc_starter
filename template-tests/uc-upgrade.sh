#!/usr/bin/env bash
# uc-upgrade.sh: a generated project's `make uc-upgrade` moves UC_VERSION, the
# four exact Cargo.toml pins and every upstream doc link together, is a no-op
# when already at that version, and refuses a version that doesn't exist on
# crates.io.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HOME/scratch/uc_starter-gen/uc-upgrade"; rm -rf "$B"; "$HERE/gen.sh" "$B" >/dev/null; cd "$B/demo-app"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Hash of every tracked doc/pin file — never Cargo.lock, which `cargo update`
# creates fresh the first time it runs and would otherwise read as "changed"
# even when no pin moved.
snapshot() {
  find . \( -path ./target -o -path ./.git -o -path ./.uc -o -path ./dist \) -prune -o \
       \( -name '*.md' -o -path './.claude/*' -o -name Cargo.toml -o -name UC_VERSION \) -type f -print0 \
    | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16
}

[ -x scripts/uc-upgrade.sh ] || fail "scripts/uc-upgrade.sh missing or not executable"

# --- idempotent: same version, no tracked file changes ----------------------
before="$(snapshot)"
UC_UPGRADE_SKIP_INDEX=1 scripts/uc-upgrade.sh 2.13.0 || fail "run at the current version exited non-zero"
after="$(snapshot)"
[ "$before" = "$after" ] || fail "uc-upgrade.sh 2.13.0 changed a tracked file while already pinned to 2.13.0"

# --- moves every pin, with a synthetic version so no network is needed ------
UC_UPGRADE_SKIP_INDEX=1 scripts/uc-upgrade.sh 9.9.9 || fail "uc-upgrade.sh 9.9.9 (skip-index) exited non-zero"
[ "$(cat UC_VERSION)" = 9.9.9 ] || fail "UC_VERSION not moved to 9.9.9, is $(cat UC_VERSION)"
got="$(grep -c '"=9\.9\.9"' Cargo.toml || true)"
[ "$got" = 4 ] || fail "expected all 4 Cargo.toml pins (uc_service/uc_remote/uc_protocol/uc_diffreplay) at =9.9.9, found $got"
for f in README.md WHAT-NEXT.md docs/how-to/upgrade-uc.md docs/concepts.md docs/troubleshooting.md upgrade/intent.toml.example; do
  grep -q 'blob/v9\.9\.9/' "$f" || fail "$f: upstream doc link did not move to v9.9.9"
done

# Every other stray mention of the old version is gone. The one documented
# exception is docs/troubleshooting.md's `ULTSNAP1` entry: it names the real
# historical releases (UC 2.11, 2.12, 2.13.0) and quotes ultima_cluster's own
# permanent error string (`pre-2.13.0 artifact`) — that text is correct
# forever and does not track this project's pin (see scripts/uc-upgrade.sh's
# header comment and docs/how-to/upgrade-uc.md).
leftover="$(grep -rl '2\.13\.0' --include='*.md' --include='Cargo.toml' --include=UC_VERSION . 2>/dev/null \
  | grep -vx './docs/troubleshooting.md' || true)"
[ -z "$leftover" ] || fail "2.13.0 still present outside the documented historical exception: $leftover"
remaining="$(grep -c '2\.13\.0' docs/troubleshooting.md || true)"
[ "$remaining" = 3 ] || fail "docs/troubleshooting.md's historical 2.13.0 mentions changed count: expected 3, got $remaining"

# No blob/v2.13.0 or releases/download/v2.13.0 LINK survives ANYWHERE in the
# project (not just *.md/.claude/**) — unlike the bare-version check above,
# this one has no exception: every historical-prose spot that keeps naming
# 2.13.0 does so without a blob/v or releases/download/v prefix (see
# scripts/uc-upgrade.sh's header comment), so a real hit here is always a
# missed link, e.g. the historical upgrade/intent.toml.example regression.
stale_links="$(grep -rlI --exclude-dir=target --exclude-dir=.git --exclude-dir=.uc --exclude-dir=dist \
  'blob/v2\.13\.0\|releases/download/v2\.13\.0' . 2>/dev/null || true)"
[ -z "$stale_links" ] || fail "blob/v2.13.0 or releases/download/v2.13.0 link(s) not rewritten: $stale_links"

# --- refuses a YANKED version (no network: a local fixture sparse-index line)
# The fixture is test-only (template-tests/fixtures/, never ships — see
# cargo-generate.toml's ignore list) and documented in
# scripts/uc-upgrade.sh's header comment (UC_UPGRADE_INDEX_URL).
before_yank="$(cat UC_VERSION)"
set +e
out="$(UC_UPGRADE_INDEX_URL="file://$HERE/fixtures/uc_service-yanked-9.9.9.jsonl" scripts/uc-upgrade.sh 9.9.9 2>&1)"; rc=$?
set -e
[ "$rc" -ne 0 ] || fail "uc-upgrade.sh 9.9.9 against a fixture where 9.9.9 is yanked should refuse"
[[ "$out" == *9.9.9* && "$out" == *[Yy][Aa][Nn][Kk][Ee][Dd]* ]] || fail "failure message should name the version and say it's yanked: $out"
[ "$(cat UC_VERSION)" = "$before_yank" ] || fail "a refused (yanked) upgrade must not have moved UC_VERSION"

# --- refuses a version that isn't on crates.io (real network, real index) ---
set +e
out="$(scripts/uc-upgrade.sh 9.9.9 2>&1)"; rc=$?
set -e
[ "$rc" -ne 0 ] || fail "uc-upgrade.sh 9.9.9 without UC_UPGRADE_SKIP_INDEX should refuse — 9.9.9 is not a real ultima_cluster release"
[[ "$out" == *"9.9.9"* ]] || fail "failure message should name the missing version: $out"

echo "uc-upgrade: PASS"
