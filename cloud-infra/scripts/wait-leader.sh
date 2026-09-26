#!/usr/bin/env bash
# wait-leader.sh [secs=60] — print the index of the host whose node reports
# "leader=true can_serve=true" (the text scripts/cluster.sh leader matches).
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
need_inventory
hssh 0 true   # dies with the CIDR hint first if node0 is unreachable
secs="${1:-60}"; end=$(( $(date +%s) + secs ))
while [ "$(date +%s)" -lt "$end" ]; do
  for i in 0 1 2; do
    out="$(hssh "$i" "sudo uc2ctl status --instance-dir $INSTANCE_DIR --app-id $APP_ID 2>/dev/null")" || continue
    case "$out" in *"leader=true can_serve=true"*) echo "$i"; exit 0 ;; esac
  done
  sleep 2
done
for i in 0 1 2; do echo "--- node$i (uc2-node journal)" >&2; hssh "$i" "sudo journalctl -u uc2-node -n 20 --no-pager" >&2 || true; done
die "no serving leader after ${secs}s (journal tails above)"
