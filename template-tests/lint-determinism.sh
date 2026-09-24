#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P="$HOME/scratch/uc_starter-gen/lint/demo-app"
rm -rf "$(dirname "$P")"; "$HERE/gen.sh" "$(dirname "$P")" >/dev/null
cd "$P"
fail() { echo "FAIL: $*" >&2; exit 1; }
ORIG="$HOME/scratch/uc_starter-gen/lint-state-orig.rs"
cp src/state.rs "$ORIG"
scripts/lint-determinism.sh --all || fail "skeleton must be clean"
scripts/lint-determinism.sh src/state.rs || fail "clean single-file invocation must exit 0"

# F1: assert the exit code AND the reported reason + `path:line:` prefix, so a
# mutant that exits 1 unconditionally (for any reason, on any input) cannot
# pass by coincidence — only checking `if ...; then fail; fi` cannot tell
# "caught the right hazard" from "always fails".
HAZARD_CASES=(
  'let t = std::time::SystemTime::now();|wall clock'
  'let m: std::collections::HashMap<u8,u8> = Default::default();|hash iteration'
  'let x: f64 = 0.1;|floating point'
  'let r = rand::random::<u64>();|randomness'
  'let _ = std::fs::read("x");|I/O in apply'
  'let i = std::time::Instant::now();|clock — use ctx.time_ns'
)
for case in "${HAZARD_CASES[@]}"; do
  bad="${case%|*}"; want="${case#*|}"
  before_lines=$(wc -l < src/state.rs)
  line=$((before_lines + 1))
  printf '%s\n' "fn _hazard() { $bad }" >> src/state.rs
  if out="$(scripts/lint-determinism.sh src/state.rs)"; then
    fail "not caught: $bad"
  fi
  case "$out" in
    *"src/state.rs:$line:"*) ;;
    *) fail "missing 'src/state.rs:$line:' prefix for '$bad' — got: $out" ;;
  esac
  case "$out" in
    *"$want"*) ;;
    *) fail "missing reason '$want' for '$bad' — got: $out" ;;
  esac
  git checkout -q -- src/state.rs 2>/dev/null || sed -i '$d' src/state.rs
done
# Whichever restore path ran (git checkout on the cargo-generate'd repo, which
# has no commit yet so this always falls through to sed; or the sed fallback
# under --vcs none), src/state.rs must be byte-identical to the pre-loop copy.
cmp -s src/state.rs "$ORIG" || fail "src/state.rs not restored after the hazard loop"
printf '%s\n' 'fn _ok() { let _x: f64 = 0.0; } // determinism: ok — test fixture' >> src/state.rs
scripts/lint-determinism.sh src/state.rs || fail "exemption ignored"
sed -i '$d' src/state.rs
cmp -s src/state.rs "$ORIG" || fail "src/state.rs not restored after the exemption fixture"
scripts/lint-determinism.sh src/bin/client.rs || fail "non-FSM file must be skipped"

# F2: path-form robustness — Task 10's editor hook may pass a `./`-relative
# path, an absolute path built from $PWD, or invoke the script from a cwd
# other than the project root (an editor's cwd is not guaranteed to be it).
scripts/lint-determinism.sh ./src/state.rs || fail "./-prefixed path must be recognized (clean)"
scripts/lint-determinism.sh "$PWD/src/state.rs" || fail "absolute \$PWD-prefixed path must be recognized (clean)"
(cd / && "$P/scripts/lint-determinism.sh" "$P/src/state.rs") || fail "absolute path invoked from a different cwd must be recognized (clean)"

printf '%s\n' 'fn _hazard() { let t = std::time::SystemTime::now(); }' >> src/state.rs
if scripts/lint-determinism.sh ./src/state.rs >/dev/null; then fail "./-prefixed path did not catch a hazard"; fi
if scripts/lint-determinism.sh "$PWD/src/state.rs" >/dev/null; then fail "absolute \$PWD-prefixed path did not catch a hazard"; fi
if (cd / && "$P/scripts/lint-determinism.sh" "$P/src/state.rs") >/dev/null; then fail "absolute path from a different cwd did not catch a hazard"; fi
git checkout -q -- src/state.rs 2>/dev/null || sed -i '$d' src/state.rs
cmp -s src/state.rs "$ORIG" || fail "src/state.rs not restored after the path-form fixture"

echo "lint-determinism: PASS"
