#!/usr/bin/env bash
# lint-determinism.sh [--all | FILE…] — grep-level determinism hazards in FSM
# files. Fast enough for an editor hook; `make lint` also runs clippy with
# clippy.toml's bans. Exempt one line with a `determinism: ok <why>` comment.
set -uo pipefail
cd "$(dirname "$0")/.."
is_fsm() { case "$1" in src/commands.rs|src/state.rs|src/snapshot.rs|src/fsm/*) return 0 ;; *) return 1 ;; esac; }
HAZARDS=(
  'SystemTime::now|wall clock — use ctx.time_ns'
  'Instant::now|clock — use ctx.time_ns'
  'rand::|thread_rng|randomness — use uc_service::IdGen'
  'HashMap|HashSet|hash iteration order differs per process — use BTreeMap/BTreeSet'
  '\bf32\b|\bf64\b|floating point — use integers (fixed-point)'
  'std::fs::|std::net::|tokio::|std::process::|I/O in apply — side effects belong in an OutputHandler'
  'std::env::|environment differs per host — pass it as a command'
)
files=()
if [ "${1:-}" = --all ]; then
  while IFS= read -r f; do files+=("$f"); done < <(ls src/commands.rs src/state.rs src/snapshot.rs 2>/dev/null; find src/fsm -name '*.rs' 2>/dev/null)
else
  for f in "$@"; do f="${f#./}"; f="${f#"$PWD"/}"; is_fsm "$f" && files+=("$f"); done
fi
[ "${#files[@]}" -eq 0 ] && exit 0
rc=0
for f in "${files[@]}"; do
  for h in "${HAZARDS[@]}"; do
    pat="${h%|*}"; why="${h##*|}"
    # `pat` may itself contain `|` alternations: everything before the LAST `|` is the regex.
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      case "$hit" in *"determinism: ok"*) continue ;; esac
      echo "$f:${hit%%:*}: ${why}"; rc=1
    done < <(grep -nE "$pat" "$f" | grep -vE '^[0-9]+:\s*//' || true)
  done
done
exit $rc
