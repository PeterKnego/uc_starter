#!/usr/bin/env bash
# kill-leader.sh — SIGKILL the leader node, watch the cluster elect another,
# prove writes still work, then bring the old leader back.
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
C="$PROJECT_DIR/scripts/cluster.sh"
row_line() { "$C" ctl "$1" status 2>/dev/null | grep -E '^ *row=0 '; }
field() { sed -nE "s/.* $1=([^ ]*).*/\1/p"; }
old="$("$C" leader)" || die "no serving leader — run make up"
echo "leader is node $old; killing it (SIGKILL)"
"$C" kill service "$old"; "$C" kill node "$old"
new=""; for _ in $(seq 1 150); do n="$("$C" leader 2>/dev/null)" && [ "$n" != "$old" ] && { new="$n"; break; }; sleep 0.2; done
[ -n "$new" ] || die "no new leader within 30s"
echo "node $new is the new leader"
UC_NO_STAMP=1 "$PROJECT_DIR/scripts/demo.sh" || exit 1
echo "restarting node $old"
commit="$("$C" ctl "$new" status 2>/dev/null | sed -nE 's/^log: commit=([0-9]+).*/\1/p')"
[ -n "$commit" ] || die "cannot read the new leader's commit position"
"$C" start node "$old"
# Only a node that has JOINED (knows the leader, has learned the commit
# position) lets a service attach; before that the attach is refused
# NodeBooting. A follower never reads can_serve=true, so wait for exactly
# that: leader_hint names the new leader and commit has caught up.
ok=0
for _ in $(seq 1 150); do
  st="$("$C" ctl "$old" status 2>/dev/null)"
  h="$(sed -nE 's/^role: .* leader_hint=([0-9]+).*/\1/p' <<<"$st")"
  c="$(sed -nE 's/^log: commit=([0-9]+).*/\1/p' <<<"$st")"
  [ "$h" = "$new" ] && [ -n "$c" ] && [ "$c" -ge "$commit" ] && { ok=1; break; }
  sleep 0.2
done
[ $ok = 1 ] || die "node $old did not rejoin within 30s (leader_hint=${h:-?}, commit=${c:-?}, want leader $new and commit >= $commit) — see $ROOT/logs/node$old.log"
echo "node $old rejoined as a follower (leader $new, commit $c)"
"$C" start service "$old"; "$C" start gateway "$old"
# The restarted node wrote a fresh control page, so attached=true is the new
# service's: wait for it attached and caught up, with all three processes alive.
ok=0
for _ in $(seq 1 150); do
  line="$(row_line "$old")"
  if [ "$(field attached <<<"$line")" = true ] && [ "$(field lag <<<"$line")" = 0 ] \
     && grep -q -- "^--- node $old (running; service running; gateway running)" <<<"$("$C" status 2>/dev/null)"; then
    ok=1; break
  fi
  sleep 0.2
done
[ $ok = 1 ] || die "node $old's node, service and gateway are not all back (row: ${line:-none}) — see $ROOT/logs/"
echo "node $old: node, service and gateway running; service re-attached and caught up"
"$PROJECT_DIR/scripts/stamp.sh" failover
echo PASS
