#!/usr/bin/env bash
# snapshot-drill.sh — take a coordinated snapshot, SIGKILL one service, and
# watch it come back to the same state (TUTORIAL.md, Step 10).
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
C="$PROJECT_DIR/scripts/cluster.sh"; CLI="$(app_bin_dir)/$APP_NAME"; GW="$(gateways_csv)"
# The write and the read are YOUR app's: scripts/probe.sh (Step 8).
# shellcheck source=scripts/probe.sh
. "$PROJECT_DIR/scripts/probe.sh"
[ -x "$CLI" ] || die "$CLI missing — run make build"
l="$("$C" leader)" || die "no serving leader — run make up"

# `uc2ctl status`'s row line, e.g.
#   row=0 name=… version=1.0.0 hash=0x… attached=true epoch=1 incarnation=1 applied=448 lag=0 snapshot_pos=160 …
row_line() { "$C" ctl "$1" status 2>/dev/null | grep -E '^ *row=0 '; }
field() { sed -nE "s/.* $1=([^ ]*).*/\1/p"; }
set_at() { "$C" snapshot-show "$1" 2>/dev/null | sed -n 's/^set=//p'; }

tok="snap-$(date +%s)-$$"
probe_write "$CLI" "$tok" || die "probe_write failed (scripts/probe.sh) — does make demo pass?"
P="$("$C" snapshot | sed -n 's/^instant=//p')"; [ -n "$P" ] || die "uc2ctl snapshot gave no instant"
echo "1. coordinated snapshot instant P=$P (every node freezes its state at log position $P)"
for n in 0 1 2; do
  s=""
  for _ in $(seq 1 150); do
    s="$(set_at "$n")"
    [ -n "$s" ] && [ "$s" != none ] && [ "$s" -ge "$P" ] && break
    sleep 0.2
  done
  { [ -n "$s" ] && [ "$s" != none ] && [ "$s" -ge "$P" ]; } || die "node $n has no complete set at $P (set=${s:-?})"
done
echo "2. all three nodes hold the complete set at P"

victim=$(( (l + 1) % 3 ))
# A SIGKILLed service leaves its slot reading attached=true until something
# rewrites it, so "attached=true lag=0" alone could be the dead process's
# line. The restarted service attaches with a new incarnation: wait for that.
inc="$(row_line "$victim" | field incarnation)"; [ -n "$inc" ] || die "cannot read service $victim's incarnation"
LOG="$ROOT/logs/service$victim.log"; before="$(wc -l <"$LOG" 2>/dev/null || echo 0)"
"$C" kill service "$victim" >/dev/null; "$C" start service "$victim" >/dev/null
echo "3. SIGKILLed service $victim and restarted it — its in-memory state is gone"
ok=0
for _ in $(seq 1 150); do
  line="$(row_line "$victim")"
  if [ "$(field incarnation <<<"$line")" != "$inc" ] && [ "$(field attached <<<"$line")" = true ] && [ "$(field lag <<<"$line")" = 0 ]; then ok=1; break; fi
  sleep 0.2
done
[ $ok = 1 ] || die "service $victim did not re-attach and catch up within 30s: $(row_line "$victim")"
got="$(probe_read "$CLI" "$tok")"; want="$(probe_expect "$tok")"
[ "$got" = "$want" ] || die "read back '$got', want '$want' (scripts/probe.sh)"
# The SDK logs "installed snap-<P>" only when it had to install the snapshot
# (the journal no longer reaches back far enough); otherwise it replayed the
# journal, silently.
since="$(tail -n +"$((before + 1))" "$LOG")"
if inst="$(grep -m1 'installed snap-' <<<"$since")"; then
  echo "4. service $victim installed the snapshot, replayed the tail, and the value reads back"
  echo "   log: $inst"
else
  echo "4. service $victim replayed the journal (it still reaches back past P, so no install was needed) and the value reads back"
fi
grep -m1 'attached' <<<"$since" | sed 's/^/   log: /' || true
"$PROJECT_DIR/scripts/stamp.sh" snapshots
echo PASS
