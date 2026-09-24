#!/usr/bin/env bash
# next.sh — where am I on WHAT-NEXT.md? Computed from the repo, never remembered.
#   scripts/next.sh          human
#   scripts/next.sh --json   for agents
#   scripts/next.sh --list   step ids in order
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
# The very first thing, before any array is touched: a friendly refusal beats
# an old-bash (macOS's stock /bin/bash 3.2) crash reaching an empty-array
# expansion further down and losing this message entirely.
require_linux
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
emit() { # n part id title status part1_complete part1_just_completed
  if [ $JSON = 1 ]; then
    printf '{"step":%s,"of":13,"part":%s,"id":"%s","title":%s,"status":"%s","part1_complete":%s,"part1_just_completed":%s,"detail":[' \
      "$1" "$2" "$3" "$(json_str "$4")" "$5" "$6" "$7"
    local first=1 d; for d in ${DETAIL[@]+"${DETAIL[@]}"}; do [ $first = 1 ] || printf ','; json_str "$d"; first=0; done; printf ']}\n'
  else
    [ "$5" = complete ] && { echo "All steps complete."; return; }
    [ "$7" = true ] && echo "Part 1 complete — your app runs on a three-node cluster."
    echo "Step $1/13 · Part $2 · $4 → WHAT-NEXT.md \"Step $1\""
    echo "  status: $5"
    local d; for d in ${DETAIL[@]+"${DETAIL[@]}"}; do echo "  - $d"; done
  fi
}

# Part 1's completion is a MACHINE-LOCAL fact (a stamp, like every other proof
# this script can't see from files alone) — never recorded in the committed
# .uc-progress, so a fresh clone with no local stamps re-walks it for real
# instead of trusting another machine's history.
part1_done=0; [ "$(stamp_state part1 any)" = fresh ] && part1_done=1
notes=()
n=0
for s in "${STEPS[@]}"; do
  n=$((n+1)); IFS='|' read -r id part title <<<"$s"
  progress_skipped "$id" && continue
  if [ "$id" != env ] && [ "$part" = 1 ] && [ $part1_done = 1 ]; then
    # Part 1 is history once completed — but only re-check the steps that can
    # actually go STALE (tests/client/failover carry a real content hash via
    # stamp_check). skeleton/concepts/design/commands/state can only ever
    # report missing/fresh, never stale, so they'd never produce a note here;
    # skipping them also keeps `cargo check`/`cargo test` off this hot poll
    # path entirely.
    case "$id" in
      tests|client|failover)
        DETAIL=(); "check_$id" >/dev/null
        [ $? = 2 ] && notes+=("note: Step $n ($title) is stale — ${DETAIL[*]}")
        ;;
    esac
    continue
  fi
  DETAIL=(); "check_$id"; rc=$?
  if [ $rc != 0 ]; then
    status=todo; [ $rc = 2 ] && status=stale
    # part1_just_completed is DERIVED every call, not a one-shot flag: true
    # whenever the reported step is the first non-skipped Part-2 step and its
    # own proof hasn't started yet (stamp missing, not stale — stale means
    # some work on it already happened). That makes the banner reproducible
    # on every call that lands here, JSON or human, in any order.
    part1_just_completed=false
    if [ "$part" = 2 ]; then
      [ $part1_done = 1 ] || write_stamp part1 any
      part1_done=1
      [ $rc = 1 ] && part1_just_completed=true
    fi
    DETAIL+=(${notes[@]+"${notes[@]}"})
    emit "$n" "$part" "$id" "$title" "$status" "$([ $part1_done = 1 ] && echo true || echo false)" "$part1_just_completed"
    exit 0
  fi
done
DETAIL=(${notes[@]+"${notes[@]}"})
# shellcheck disable=SC1010  # "done" here is the emit() id argument, not the loop keyword
emit 13 2 done "All steps complete" complete true false
