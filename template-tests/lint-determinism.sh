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
for bad in 'let t = std::time::SystemTime::now();' 'let m: std::collections::HashMap<u8,u8> = Default::default();' \
           'let x: f64 = 0.1;' 'let r = rand::random::<u64>();' 'let _ = std::fs::read("x");' 'let i = std::time::Instant::now();'; do
  printf '%s\n' "fn _hazard() { $bad }" >> src/state.rs
  if scripts/lint-determinism.sh src/state.rs >/dev/null; then fail "not caught: $bad"; fi
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
echo "lint-determinism: PASS"
