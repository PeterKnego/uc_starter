#!/usr/bin/env bash
# env-show.sh — which credentials make will pass on (lengths, never values).
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
require_make
# One buffered printf at the end, not one echo per line: a caller that pipes
# straight into `grep -q` (no capture) can close its end after the first
# match, and a slow multi-write producer then dies to SIGPIPE under
# pipefail. Building the lines first and writing once avoids that race.
out=""
for v in HCLOUD_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE GOOGLE_PROJECT GOOGLE_APPLICATION_CREDENTIALS; do
  val="$(eval "echo \"\${$v:-}\"")"
  if [ -n "$val" ]; then out="$out$v: set (${#val} chars)
"
  else out="$out$v: not set
"
  fi
done
out="$out"'owner: '"${TF_VAR_owner:-}"'
cloud: '"$(tfvar cloud)"
printf '%s\n' "$out"
