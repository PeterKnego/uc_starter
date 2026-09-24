#!/usr/bin/env bash
# corpus.sh — capture a diff-replay corpus from the running cluster with the
# CURRENT (old) code, and keep that binary as the "old" side (WHAT-NEXT.md,
# Step 12). Run it BEFORE you change the code.
#
# The traffic is scripts/demo.sh, run once below the instant (so the snapshot
# image holds real state) and once above it (the span both builds replay).
# A corpus only proves what it exercises: make sure demo.sh sends the command
# you are about to change, with inputs where the change shows.
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
DR="$PROJECT_DIR/.uc/cargo/bin/uc2-diffreplay"; [ -x "$DR" ] || die "uc2-diffreplay missing — run: make diffreplay"
C="$PROJECT_DIR/scripts/cluster.sh"
SVC="$(app_bin_dir)/$APP_NAME-service"; [ -x "$SVC" ] || die "$SVC missing — run make build"
"$C" leader >/dev/null || die "no serving leader — run make up"
# The old side must be the build the cluster runs. A source version that
# differs from the running one means the code was already bumped.
src="$(source_version)"; run="$(running_version 0)"
{ [ -n "$src" ] && [ -n "$run" ]; } || die "cannot read versions (running '$run', source '$src')"
[ "$src" = "$run" ] || die "src/identity.rs says $src but the cluster runs $run — capture the corpus BEFORE the change: check out the code the cluster runs, then make corpus"

traffic() { UC_NO_STAMP=1 "$PROJECT_DIR/scripts/demo.sh" >/dev/null || die "scripts/demo.sh failed — fix it (make demo) before capturing a corpus"; }
traffic
P="$("$C" snapshot | sed -n 's/^instant=//p')"; [ -n "$P" ] || die "uc2ctl snapshot gave no instant"
s=""; for _ in $(seq 1 150); do s="$("$C" snapshot-show 0 | sed -n 's/^set=//p')"; [ "$s" = "$P" ] && break; sleep 0.2; done
[ "$s" = "$P" ] || die "node 0 has no complete set at $P (set=${s:-?})"
echo "1. instant P=$P, complete on node 0"
traffic
# Export once node 0 has made the traffic durable, so the span ends after it.
commit="$("$C" ctl "$("$C" leader)" status | sed -nE 's/^log: commit=([0-9]+).*/\1/p')"
d=0; for _ in $(seq 1 150); do d="$("$C" ctl 0 status | sed -nE 's/^log: .*durable=([0-9]+).*/\1/p')"; [ "${d:-0}" -ge "${commit:-0}" ] && break; sleep 0.2; done
[ "${d:-0}" -ge "${commit:-1}" ] || die "node 0 did not reach commit $commit (durable=$d)"
echo "2. ran scripts/demo.sh above P; node 0 durable to $d"
rm -rf upgrade/corpus upgrade/old; mkdir -p upgrade/old
"$DR" corpus export --instance-dir "$ROOT/n0" --app-id "$APP_ID" --row 0 --from "$P" --out upgrade/corpus || die "corpus export failed"
cp "$SVC" upgrade/old/
[ -f upgrade/intent.toml ] || cp upgrade/intent.toml.example upgrade/intent.toml
echo "3. corpus at upgrade/corpus (from P=$P); old service binary at upgrade/old/"
echo "next: change the code, bump FSM_VERSION in src/identity.rs, declare the change in upgrade/intent.toml, run make upgrade-check"
