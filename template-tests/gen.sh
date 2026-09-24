#!/usr/bin/env bash
# gen.sh DEST [name fsm_name app_id base_port] — generate a project from this checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$1"; NAME="${2:-demo-app}"; FSM="${3:-demo}"; APPID="${4:-demo}"; PORT="${5:-7000}"
mkdir -p "$DEST"
cargo generate --path "$ROOT" --name "$NAME" --destination "$DEST" --silent \
  --define fsm_name="$FSM" --define app_id="$APPID" --define base_port="$PORT"
