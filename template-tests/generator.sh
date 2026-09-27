#!/usr/bin/env bash
# Generator contract: placeholders substituted in the four liquid files only,
# everything else verbatim, bad names refused by the pre-hook.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HOME/scratch/uc_starter-gen/generator"
rm -rf "$OUT"; mkdir -p "$OUT"
fail() { echo "FAIL: $*" >&2; exit 1; }

"$HERE/gen.sh" "$OUT/ok" my-app myfsm myid 7100 >/dev/null
P="$OUT/ok/my-app"
grep -q 'pub const FSM_NAME: &str = "myfsm";' "$P/src/identity.rs" || fail "fsm_name not substituted"
grep -q 'pub const APP_ID: &str = "myid";' "$P/src/identity.rs" || fail "app_id not substituted"
grep -q 'pub const BASE_PORT: u16 = 7100;' "$P/src/identity.rs" || fail "base_port not substituted"
grep -q '^APP_NAME=my-app$' "$P/uc-app.env" || fail "uc-app.env"
grep -q '^name = "my-app-service"$' "$P/Cargo.toml" || fail "service bin name"
grep -q 'LITERAL-CHECK {{not_a_placeholder}}' "$P/tests/cluster.rs" || fail "tests/cluster.rs was liquid-processed"
[ ! -e "$P/template-tests" ] || fail "template-tests leaked into the project"
[ ! -e "$P/hooks" ] || fail "hooks leaked into the project"
[ ! -e "$P/cargo-generate.toml" ] || fail "cargo-generate.toml leaked"
(cd "$P" && cargo metadata --format-version 1 --no-deps >/dev/null) || fail "generated Cargo.toml does not parse"
[ ! -e "$P/LICENSE" ] || fail "a LICENSE was generated — the license is the developer's choice"
[ ! -e "$P/.github/README.md" ] || fail ".github/README.md leaked — it would shadow the project's README on GitHub"
[ -f "$P/TUTORIAL.md" ] || fail "TUTORIAL.md missing from the project"
[ -f "$P/cloud-infra/Makefile" ] || fail "cloud-infra/ missing from the project"
[ ! -e "$P/.github/workflows/cloud-e2e.yml" ] || fail "cloud-e2e.yml leaked into the project"

# Snapshot cadence: a deployed cluster takes an instant every 1 GiB of log, so
# purge keeps the journal bounded; the local cluster stays on-demand so the
# tutor's snapshot drill shows the instant it commands. UC_SNAPSHOT_INTERVAL
# overrides both.
render() { (cd "$P" && . scripts/lib.sh && render_node_toml "$@" "$OUT/n0" "$OUT/admin.key" 10.0.0.1 10.0.0.2 10.0.0.3); }
grep -qx 'snapshot_interval_bytes = 1073741824' <<<"$(render deploy 0)" || fail "deploy node.toml: snapshot cadence is not 1 GiB"
grep -qx 'snapshot_interval_bytes = 0' <<<"$(render local 0)" || fail "local node.toml: snapshot cadence is not on-demand (0)"
grep -qx 'snapshot_interval_bytes = 4096' <<<"$(UC_SNAPSHOT_INTERVAL=4096 render deploy 0)" || fail "UC_SNAPSHOT_INTERVAL does not override the deploy cadence"
grep -qx 'snapshot_interval_bytes = 4096' <<<"$(UC_SNAPSHOT_INTERVAL=4096 render local 0)" || fail "UC_SNAPSHOT_INTERVAL does not override the local cadence"
grep -q '^\[purge\]' <<<"$(render deploy 0)" || fail "deploy node.toml lost [purge]"

for bad in uc_mine 9lives Upper; do
  if "$HERE/gen.sh" "$OUT/bad-$bad" bad-app "$bad" x 7000 >/dev/null 2>&1; then fail "fsm_name $bad accepted"; fi
done
if "$HERE/gen.sh" "$OUT/bad-app" app ok x 7000 >/dev/null 2>&1; then fail "project name app accepted"; fi
if "$HERE/gen.sh" "$OUT/bad-port" p2 ok x 65400 >/dev/null 2>&1; then fail "base_port 65400 accepted"; fi
echo "generator: PASS"
