#!/usr/bin/env bash
# upgrade-drill.sh — the per-row pinned upgrade on the local cluster
# (upstream docs/how-to/upgrade-an-application.md §1–§7; WHAT-NEXT.md, Step 12).
# THE PIN IS A ONE-WAY DOOR: after it commits the old binary is refused by
# name on every node, and the only way back is the backups taken in step 2.
#
#   scripts/upgrade-drill.sh            the whole procedure (asks you to type PIN)
#   scripts/upgrade-drill.sh --resume   steps 5-7 only, for an upgrade whose pin
#                                       committed but whose services never restarted
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
C="$PROJECT_DIR/scripts/cluster.sh"; CLI="$(app_bin_dir)/$APP_NAME"; GW="$(gateways_csv)"
# The canary write and read are YOUR app's: scripts/probe.sh (Step 8). The
# write goes through the OLD client make corpus saved beside the old service
# (upgrade/old/): a new client must never talk to old services.
# shellcheck source=scripts/probe.sh
. "$PROJECT_DIR/scripts/probe.sh"
OLD_CLI="$PROJECT_DIR/upgrade/old/$APP_NAME"
CANARY="$ROOT/upgrade-canary"   # the canary's token, kept for --resume
RESUME=0; [ "${1:-}" = --resume ] && RESUME=1
[ -x "$CLI" ] || die "$CLI missing — run make build"
"$C" leader >/dev/null || die "no serving leader — run make up"

row_line() { "$C" ctl "$1" status 2>/dev/null | grep -E '^ *row=0 '; }
field() { sed -nE "s/.* $1=([^ ]*).*/\1/p"; }
set_at() { "$C" snapshot-show "$1" 2>/dev/null | sed -n 's/^set=//p'; }
metric() { "$C" metrics "$1" 2>/dev/null | awk -v m="$2" '$1 == m {print $2; exit}'; }

# Steps 5-7: stop every service, start the new build everywhere, verify.
# restart_all ORIGIN
restart_all() {
  local P="$1" n ok line got want tok P2 s v L a a0
  for n in 0 1 2; do "$C" stop service "$n" >/dev/null; done
  echo "5. stopped every service (all of them, before starting any)"
  for n in 0 1 2; do "$C" start service "$n" >/dev/null; done
  echo "6. started the new build everywhere"
  for n in 0 1 2; do
    ok=0
    for _ in $(seq 1 150); do
      line="$(row_line "$n")"
      [ "$(field version <<<"$line")" = "$new" ] && [ "$(field attached <<<"$line")" = true ] && [ "$(field lag <<<"$line")" = 0 ] && { ok=1; break; }
      sleep 0.2
    done
    [ $ok = 1 ] || die "node $n row 0 is not attached at $new and caught up: $line (log: $ROOT/logs/service$n.log)"
    grep -q "pinned install of snap-$P" "$ROOT/logs/service$n.log" \
      || die "service $n logged no 'pinned install of snap-$P' — the pinned install did not happen"
  done
  tok="$(cat "$CANARY" 2>/dev/null)"
  if [ -n "$tok" ]; then
    got="$(probe_read "$CLI" "$tok")"; want="$(probe_expect "$tok")"
    [ "$got" = "$want" ] || die "pre-upgrade value lost: read '$got', want '$want' (scripts/probe.sh)"
    echo "7. every node runs $new, installed snap-$P, and the pre-upgrade write reads back ($got)"
  else
    echo "7. every node runs $new and installed snap-$P (no canary recorded in $CANARY, so no read-back check)"
  fi
  grep -h "pinned install of snap-$P" "$ROOT"/logs/service[012].log | sed 's/^/   log: /'
  # All replicas agree (upstream upgrade-an-application.md §7): a coordinated
  # instant under the new build, then the live uc2_snapshot_hash_mismatch
  # gauge — the number of replicas off the majority's hash — is 0 everywhere.
  # The gauge also reads 0 while no report has committed ("no majority to
  # differ from"), so first wait for the leader to append this instant's
  # SnapshotReport (uc2_snapshot_reports_appended_total moves).
  L="$("$C" leader)" || die "no serving leader after the upgrade"
  a0="$(metric "$L" uc2_snapshot_reports_appended_total)"
  P2="$("$C" snapshot | sed -n 's/^instant=//p')"; [ -n "$P2" ] || die "uc2ctl snapshot gave no instant after the upgrade"
  for n in 0 1 2; do
    s=""; for _ in $(seq 1 150); do s="$(set_at "$n")"; [ -n "$s" ] && [ "$s" != none ] && [ "$s" -ge "$P2" ] && break; sleep 0.2; done
    { [ -n "$s" ] && [ "$s" != none ] && [ "$s" -ge "$P2" ]; } || die "node $n has no complete set at $P2 after the upgrade (set=${s:-?})"
  done
  a=""; for _ in $(seq 1 150); do a="$(metric "$L" uc2_snapshot_reports_appended_total)"; [ -n "$a" ] && [ "$a" -gt "${a0:-0}" ] && break; sleep 0.2; done
  { [ -n "$a" ] && [ "$a" -gt "${a0:-0}" ]; } || die "leader $L appended no SnapshotReport for instant $P2 within 30s (uc2_snapshot_reports_appended_total stayed at ${a0:-?})"
  for n in 0 1 2; do
    v=""
    for _ in $(seq 1 50); do
      v="$("$C" metrics "$n" 2>/dev/null | grep -E '^uc2_snapshot_hash_mismatch\{[^}]*row="0"' | awk '{print $2}' | head -1)"
      [ "$v" = 0 ] && break; sleep 0.2
    done
    [ "$v" = 0 ] || die "node $n: uc2_snapshot_hash_mismatch{row=\"0\"} is '${v:-absent}', want 0 — the replicas disagree on row 0's state after the upgrade"
  done
  echo "8. instant P=$P2 under $new: uc2_snapshot_hash_mismatch{row=\"0\"} = 0 on every node (all replicas agree)"
  "$PROJECT_DIR/scripts/stamp.sh" upgrade-drill
  echo PASS
}

new="$(source_version)"; [ -n "$new" ] || die "cannot read FSM_VERSION from src/identity.rs"

# An upgrade already in flight: some node's row is pinned to a version it is
# not running (a pin committed, then a later step died — or the pin call
# timed out client-side after it committed). Never take backups then: a
# backup taken after the pin carries the pin, so it is no rollback point.
pinned=""; origin=""
for n in 0 1 2; do
  line="$(row_line "$n")"; p="$(field pinned <<<"$line")"; v="$(field version <<<"$line")"
  if [ -n "$p" ] && [ "$p" != unversioned ] && [ "$p" != "$v" ]; then
    pinned="$p"; origin="$(field upgrade_origin <<<"$line")"; break
  fi
done

if [ $RESUME = 0 ]; then
  [ -z "$pinned" ] || die "an upgrade of row 0 to $pinned is already in flight (pinned at origin ${origin:-?}, not yet running everywhere). Do NOT start over: new backups would carry the pin and could not take you back. Finish it with: make upgrade-drill RESUME=1 (scripts/upgrade-drill.sh --resume)"
fi
case "$(stamp_state upgrade-check-code "$(upgrade_hash)")" in
  fresh) ;;
  stale) die "the code, upgrade/intent.toml, the corpus or upgrade/old changed since make upgrade-check passed — run it again (diff-replay must PASS for the code you pin)" ;;
  *) die "run make upgrade-check first (diff-replay must PASS before a pin)" ;;
esac

if [ $RESUME = 1 ]; then
  [ -n "$pinned" ] || die "--resume: no node's row 0 is pinned to a version it is not running — there is no upgrade in flight to resume (run make upgrade-drill)"
  [ "$pinned" = "$new" ] || die "--resume: row 0 is pinned to $pinned but src/identity.rs says $new — check out the code for $pinned, make upgrade-check, then resume"
  { [ -n "$origin" ] && [ "$origin" != 0 ]; } || die "--resume: cannot read the pin's origin"
  P="$origin"
  echo "resuming the upgrade of row 0 ($FSM_NAME) to $new, pinned at origin P=$P (no new backups: your rollback point is the one taken before the pin)"
  export UC_CONFIRM_PIN=yes
  cargo build --release -q || die "cargo build failed — the pin stands; fix the build and resume"
  restart_all "$P"
  exit 0
fi

[ -x "$OLD_CLI" ] || die "$OLD_CLI missing — run make corpus (it saves the old client beside the old service) before changing the code"
old="$(running_version 0)"
[ -n "$old" ] || die "cannot read the running version of row 0 (is every service up? make status)"
[ "$old" != "$new" ] || die "running version is already $new — bump FSM_VERSION in src/identity.rs first"

cat <<EOT
About to upgrade row 0 ($FSM_NAME) from $old to $new on the local cluster at $ROOT.
After the pin commits there is NO unpin: the old binary is refused by name,
and the only way back is restoring the backups this script takes first.
EOT
if [ "${UC_CONFIRM_PIN:-}" != yes ]; then
  [ -t 0 ] || die "not a terminal and UC_CONFIRM_PIN != yes — refusing to pin"
  read -r -p "Type PIN to continue: " ans; [ "$ans" = PIN ] || die "not confirmed — nothing was changed"
fi
export UC_CONFIRM_PIN=yes

# The new build must exist before anything is pinned: a build failure after
# the pin would leave the row with no binary allowed to attach.
cargo build --release -q || die "cargo build failed — nothing was changed"
# The PASS must still be for exactly what is about to be pinned: the code,
# the declaration, the corpus and the old binaries, after the prompt and the
# build (an edit made while the prompt waited withdraws it).
[ "$(stamp_state upgrade-check-code "$(upgrade_hash)")" = fresh ] \
  || die "the code, upgrade/intent.toml, the corpus or upgrade/old changed since make upgrade-check passed — nothing was pinned; run make upgrade-check again"

tok="canary-$(date +%s)-$$"
probe_write "$OLD_CLI" "$tok" || die "canary write with the old client failed (scripts/probe.sh) — nothing was pinned"
echo "$tok" >"$CANARY"
P="$("$C" snapshot | sed -n 's/^instant=//p')"; [ -n "$P" ] || die "uc2ctl snapshot gave no instant"
# The pin's origin must be every node's NEWEST complete set (refusal 54
# pin_no_set on the leader; PinnedArtifactMissing at attach elsewhere).
for n in 0 1 2; do
  s=""; for _ in $(seq 1 150); do s="$(set_at "$n")"; [ "$s" = "$P" ] && break; sleep 0.2; done
  [ "$s" = "$P" ] || die "node $n: complete set is '${s:-?}', not $P — nothing was pinned; re-run"
done
echo "1. origin instant P=$P, complete on every node"

stamp="$(date +%Y%m%d-%H%M%S)"; mkdir -p "$ROOT/backups"
for n in 0 1 2; do
  "$UC_BIN/uc2ctl" backup --instance-dir "$ROOT/n$n" --out "$ROOT/backups/n$n-pre-$new-$stamp" >"$ROOT/logs/backup-n$n.log" 2>&1 \
    || die "backup of node $n failed (see $ROOT/logs/backup-n$n.log) — nothing was pinned"
done
echo "2. backups in $ROOT/backups/n*-pre-$new-$stamp (your rollback point; a running node backs up fine)"

l="$("$C" leader)" || die "no serving leader — nothing was pinned"
out="$("$C" ctl "$l" upgrade pin --row 0 --to "$new" --origin "$P" --admin-key "$ROOT/admin.key" 2>&1)" \
  || die "pin failed or timed out: $out — check 'scripts/cluster.sh status | grep pinned=' before re-running (a pin that committed is resumed with make upgrade-drill RESUME=1, never re-run from the start)"
echo "3. $out"

for n in 0 1 2; do
  ok=0
  for _ in $(seq 1 150); do
    line="$(row_line "$n")"
    [ "$(field pinned <<<"$line")" = "$new" ] && [ "$(field upgrade_origin <<<"$line")" = "$P" ] && { ok=1; break; }
    sleep 0.2
  done
  [ $ok = 1 ] || die "node $n does not show pinned=$new upgrade_origin=$P: $line"
done
echo "4. every node shows the pin (pinned=$new upgrade_origin=$P)"

restart_all "$P"
