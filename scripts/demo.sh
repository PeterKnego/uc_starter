#!/usr/bin/env bash
# demo.sh — drive the running cluster through the gateways and check answers.
# TODO(app): rewrite these calls for your commands (keep the expect checks).
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
CLI="$(app_bin_dir)/$APP_NAME"
[ -x "$CLI" ] || die "$CLI missing — run make build"
GW="$(gateways_csv)"
fails=0
expect() { # description, expected-substring, command…
  local d="$1" want="$2"; shift 2
  local got rc; got="$("$CLI" --gateways "$GW" "$@" 2>&1)"; rc=$?
  if [ $rc -eq 0 ] && [[ "$got" == *"$want"* ]]; then printf '   %-28s -> %s\n' "$d" "$got"
  else printf '   %-28s -> FAILED (exit %s): %s\n' "$d" "$rc" "$got"; fails=$((fails+1)); fi
}
echo "demo against $GW"
expect "put greeting hello"      'ok previous='       put greeting hello
expect "get greeting"            'value="hello"'      get greeting --linearizable
expect "delete greeting"         'ok removed="hello"' delete greeting
expect "get greeting (deleted)"  'value=none'         get greeting --linearizable
[ $fails -eq 0 ] || { echo "FAIL ($fails)"; exit 1; }
"$PROJECT_DIR/scripts/stamp.sh" demo
[ "$(stamp_state skeleton any)" = fresh ] || "$PROJECT_DIR/scripts/stamp.sh" skeleton
echo PASS
