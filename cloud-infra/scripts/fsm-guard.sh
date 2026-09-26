#!/usr/bin/env bash
# fsm-guard.sh — before cloud-deploy: same FSM_VERSION and same UC, or refuse.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
need_inventory
running="$(hssh 0 "sudo uc2ctl status --instance-dir $INSTANCE_DIR --app-id $APP_ID" 2>/dev/null \
  | sed -nE 's/^ *row=0 .* version=([0-9]+\.[0-9]+\.[0-9]+) .*/\1/p' | head -1)"
fsm_guard_decide "$running" "$(source_version)"
uc_guard_decide "$(hssh 0 "uc2-node --version" 2>/dev/null)" "$UC_VERSION"
echo "fsm-guard: row 0 runs $running, UC $UC_VERSION — a rolling service restart is safe"
