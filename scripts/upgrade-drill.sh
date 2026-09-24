#!/usr/bin/env bash
# upgrade-drill.sh — the per-row pinned upgrade on the local cluster
# (upstream docs/how-to/upgrade-an-application.md §1–§7; WHAT-NEXT.md, Step 12).
# THE PIN IS A ONE-WAY DOOR: after it commits the old binary is refused by
# name on every node, and the only way back is the backups taken in step 2.
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
C="$PROJECT_DIR/scripts/cluster.sh"; CLI="$(app_bin_dir)/$APP_NAME"; GW="$(gateways_csv)"
[ -x "$CLI" ] || die "$CLI missing — run make build"
"$C" leader >/dev/null || die "no serving leader — run make up"
new="$(source_version)"; old="$(running_version 0)"
{ [ -n "$old" ] && [ -n "$new" ]; } || die "cannot read versions (running '$old', source '$new')"
[ "$old" != "$new" ] || die "running version is already $new — bump FSM_VERSION in src/identity.rs first"
case "$(stamp_state upgrade-check-code "$(upgrade_hash)")" in
  fresh) ;;
  stale) die "the code or upgrade/intent.toml changed since make upgrade-check passed — run it again (diff-replay must PASS for the code you pin)" ;;
  *) die "run make upgrade-check first (diff-replay must PASS before a pin)" ;;
esac

row_line() { "$C" ctl "$1" status 2>/dev/null | grep -E '^ *row=0 '; }
field() { sed -nE "s/.* $1=([^ ]*).*/\1/p"; }
set_at() { "$C" snapshot-show "$1" 2>/dev/null | sed -n 's/^set=//p'; }

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

"$CLI" --gateways "$GW" put upgrade-canary before >/dev/null || die "canary write failed"
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
  || die "pin refused: $out"
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
got="$("$CLI" --gateways "$GW" get upgrade-canary --linearizable)"
[ "$got" = 'value="before"' ] || die "pre-upgrade value lost: read '$got'"
echo "7. every node runs $new, installed snap-$P, and the pre-upgrade write reads back"
grep -h "pinned install of snap-$P" "$ROOT"/logs/service[012].log | sed 's/^/   log: /'
"$PROJECT_DIR/scripts/stamp.sh" upgrade-drill
echo PASS
