#!/usr/bin/env bash
# next.sh — where am I on WHAT-NEXT.md? Computed from the repo, never remembered.
#   scripts/next.sh          human
#   scripts/next.sh --json   for agents
#   scripts/next.sh --list   step ids in order
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
STEPS=(
  "env|1|Environment"
  "skeleton|1|Run the skeleton"
  "concepts|1|SMR in five minutes"
  "design|1|Design your app"
  "commands|1|Commands"
  "state|1|State, apply and query"
  "tests|1|Tests that cover your commands"
  "client|1|Client and demo for your commands"
  "failover|1|Kill the leader"
  "snapshots|2|Snapshots and purge"
  "observe|2|Observe the cluster"
  "upgrade|2|Your first FSM upgrade"
  "deploy|2|Deploy to three machines"
)
if [ "${1:-}" = --list ]; then for s in "${STEPS[@]}"; do echo "${s%%|*}"; done; exit 0; fi
JSON=0; [ "${1:-}" = --json ] && JSON=1

DETAIL=()
todo_in() { # 0 when no marker remains in the given paths
  local hits; hits="$(grep -rn 'TODO(app)' "$@" 2>/dev/null | cut -d: -f1,2)" || true
  [ -z "$hits" ] && return 0
  while IFS= read -r h; do DETAIL+=("TODO(app) at $h"); done <<<"$hits"
  return 1
}
stamp_check() { # id hash hint → 0 fresh, 1 missing, 2 stale
  case "$(stamp_state "$1" "$2")" in
    fresh) return 0 ;;
    missing) DETAIL+=("$3"); return 1 ;;
    stale) DETAIL+=("code changed since this was proven — $3"); return 2 ;;
  esac
}
check_env() {
  [ "$(uname -s)" = Linux ] || { DETAIL+=("not Linux ($(uname -s)): open the devcontainer — README.md § Devcontainer"); return 1; }
  command -v cargo >/dev/null || { DETAIL+=("cargo not found: install rustup (README.md § Prerequisites)"); return 1; }
  local v; v="$("$UC_BIN/uc2-node" --version 2>/dev/null)" || { DETAIL+=("ultima_cluster binaries missing: make bins"); return 1; }
  [[ "$v" == *"$UC_VERSION"* ]] || { DETAIL+=(".uc/bin has '$v' but UC_VERSION is $UC_VERSION: make bins"); return 1; }
}
check_skeleton() { stamp_check skeleton any "run: make up && make demo"; }
check_concepts() { progress_has concepts || { DETAIL+=("read WHAT-NEXT.md Step 3, then: make done STEP=concepts"); return 1; }; }
check_design()   { todo_in docs/app-design.md; }
check_commands() { todo_in src/commands.rs || return 1; cargo check -q 2>/dev/null || { DETAIL+=("cargo check fails — run it to see why"); return 1; }; }
check_state()    { todo_in src/state.rs src/snapshot.rs || return 1; cargo test -q --lib >/dev/null 2>&1 || { DETAIL+=("cargo test --lib fails"); return 1; }; }
check_tests()    { todo_in tests || return 1; stamp_check check "$(code_hash_with_tests)" "run: make check (tests + lint)"; }
check_client()   { todo_in src/bin/client.rs scripts/demo.sh || return 1; stamp_check demo "$(code_hash)" "run: make restart-services && make demo"; }
check_failover() { stamp_check failover "$(code_hash)" "run: make kill-leader"; }
check_snapshots(){ stamp_check snapshots any "run: make snapshot-drill"; }
check_observe()  { stamp_check observe any "run: make observe"; }
check_upgrade()  {
  grep -qE 'pack_version\(1, 0, 0\)' src/identity.rs && { DETAIL+=("FSM_VERSION is still 1.0.0: bump it in src/identity.rs for your v2 behaviour"); return 1; }
  stamp_check upgrade-check any "run: make corpus (before the change), then make upgrade-check" || return 1
  stamp_check upgrade-drill any "run: make upgrade-drill (asks before the one-way pin)"
}
check_deploy()   {
  ls dist/*.tar.gz >/dev/null 2>&1 || { DETAIL+=("run: make package HOSTS=ip0,ip1,ip2"); return 1; }
  progress_has deploy || { DETAIL+=("deploy it (docs/how-to/deploy.md), then: make done STEP=deploy"); return 1; }
}

json_str() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }
emit() { # n part id title status part1
  if [ $JSON = 1 ]; then
    printf '{"step":%s,"of":13,"part":%s,"id":"%s","title":%s,"status":"%s","part1_complete":%s,"detail":[' "$1" "$2" "$3" "$(json_str "$4")" "$5" "$6"
    local first=1 d; for d in "${DETAIL[@]}"; do [ $first = 1 ] || printf ','; json_str "$d"; first=0; done; printf ']}\n'
  else
    [ "$5" = complete ] && { echo "All steps complete."; return; }
    echo "Step $1/13 · Part $2 · $4 → WHAT-NEXT.md \"Step $1\""
    echo "  status: $5"
    local d; for d in "${DETAIL[@]}"; do echo "  - $d"; done
  fi
}

part1_done=0; progress_has part1 && part1_done=1
notes=()
n=0
for s in "${STEPS[@]}"; do
  n=$((n+1)); IFS='|' read -r id part title <<<"$s"
  progress_skipped "$id" && continue
  if [ "$part" = 1 ] && [ $part1_done = 1 ]; then
    # Part 1 is history once completed: report staleness as a note only.
    DETAIL=(); "check_$id" >/dev/null; [ $? = 2 ] && notes+=("note: Step $n ($title) is stale — ${DETAIL[*]}")
    continue
  fi
  DETAIL=(); "check_$id"; rc=$?
  if [ $rc != 0 ]; then
    status=todo; [ $rc = 2 ] && status=stale
    if [ "$part" = 2 ] && [ $part1_done = 0 ]; then
      echo "done part1 $(date +%F)" >> "$PROGRESS"; part1_done=1
      [ $JSON = 0 ] && echo "Part 1 complete — your app runs on a three-node cluster."
    fi
    DETAIL+=("${notes[@]}")
    emit "$n" "$part" "$id" "$title" "$status" "$([ $part1_done = 1 ] && echo true || echo false)"
    exit 0
  fi
done
DETAIL=("${notes[@]}")
# shellcheck disable=SC1010  # "done" here is the emit() id argument, not the loop keyword
emit 13 2 done "All steps complete" complete true
