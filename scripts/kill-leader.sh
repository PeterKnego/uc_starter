#!/usr/bin/env bash
# kill-leader.sh — SIGKILL the leader node, watch the cluster elect another,
# prove writes still work, then bring the old leader back.
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
C="$PROJECT_DIR/scripts/cluster.sh"
old="$("$C" leader)" || die "no serving leader — run make up"
echo "leader is node $old; killing it (SIGKILL)"
"$C" kill service "$old"; "$C" kill node "$old"
new=""; for _ in $(seq 1 150); do n="$("$C" leader 2>/dev/null)" && [ "$n" != "$old" ] && { new="$n"; break; }; sleep 0.2; done
[ -n "$new" ] || die "no new leader within 30s"
echo "node $new is the new leader"
UC_NO_STAMP=1 "$PROJECT_DIR/scripts/demo.sh" || exit 1
"$PROJECT_DIR/scripts/stamp.sh" failover
echo "restarting node $old"
"$C" start node "$old"; sleep 1; "$C" start service "$old"; "$C" start gateway "$old"
echo PASS
