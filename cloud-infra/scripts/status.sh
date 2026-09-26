#!/usr/bin/env bash
# status.sh — the hosts, their uptime against ttl_hours, leadership, /readyz.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
need_inventory
hssh 0 true   # dies with the CIDR hint first if node0 is unreachable
echo "$CLOUD $REGION $INSTANCE_TYPE ×3 ($ARCH), ttl_hours=$TTL_HOURS"
for i in 0 1 2; do
  up_s="$(hssh "$i" "cut -d. -f1 /proc/uptime")" || exit 3   # hssh's die only leaves the \$(…) subshell
  up_h=$(( up_s / 3600 ))
  st="$(hssh "$i" "sudo uc2ctl status --instance-dir $INSTANCE_DIR --app-id $APP_ID 2>/dev/null" || true)"
  role=follower; case "$st" in *"leader=true can_serve=true"*) role=leader ;; esac
  [ -n "$st" ] || role="node down"
  rz="$(hssh "$i" "curl -s -o /dev/null -w '%{http_code}' http://$(priv "$i"):$(METRICS_PORT "$i")/readyz 2>/dev/null" || echo "---")"
  printf 'node%s  %-15s (%s)  up %sh  %-9s readyz=%s\n' "$i" "$(pub "$i")" "$(priv "$i")" "$up_h" "$role" "$rz"
  ttl_note "$up_h" "$TTL_HOURS"
done
