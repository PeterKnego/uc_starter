#!/usr/bin/env bash
# Drives a generated project through every Part-1 transition by editing files
# and writing stamps directly — no cluster needed. Requires `make bins` to work
# (network) so step 1 can pass.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/scratch/uc_starter-gen/tutor"; rm -rf "$BASE"; "$HERE/gen.sh" "$BASE" >/dev/null
cd "$BASE/demo-app"
fail() { echo "FAIL: $*" >&2; scripts/next.sh >&2; exit 1; }
at() { scripts/next.sh --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'], d['status'])"; }
expect() { local got; got="$(at)"; [ "$got" = "$1" ] || fail "expected '$1', got '$got'"; }
unmark() { sed -i '/TODO(app)/d' "$@"; }

[ "$(scripts/next.sh --list | tr '\n' ' ')" = "env skeleton concepts design commands state tests client failover snapshots observe upgrade deploy " ] || fail "--list"
# the doc and the checker agree on ids and order
[ "$(grep -oE '<!-- step: [a-z-]+ -->' WHAT-NEXT.md | sed 's/<!-- step: \(.*\) -->/\1/' | tr '\n' ' ')" = "$(scripts/next.sh --list | tr '\n' ' ')" ] || fail "WHAT-NEXT.md step ids differ from next.sh --list"

mv .uc .uc.away 2>/dev/null || true
expect "env todo"
mv .uc.away .uc 2>/dev/null || make -s bins >/dev/null
expect "skeleton todo"
scripts/stamp.sh skeleton;                      expect "concepts todo"
# shellcheck disable=SC1010  # "done" is the verb argument to progress.sh, not the loop keyword
scripts/progress.sh done concepts;              expect "design todo"
unmark docs/app-design.md;                      expect "commands todo"
unmark src/commands.rs;                         expect "state todo"
unmark src/state.rs src/snapshot.rs;            expect "tests todo"
unmark tests/*.rs;                              expect "tests todo"   # no check stamp yet
scripts/stamp.sh check;                         expect "client todo"
unmark src/bin/client.rs scripts/demo.sh
# src/bin/client.rs is part of `src`, so this edit is covered by the "tests"
# step's whole-src hash too (WHAT-NEXT.md §5.2's "a hash of src/") — a real
# developer re-runs `make check` after any src/ edit, so the drill does too.
scripts/stamp.sh check
scripts/stamp.sh demo;                          expect "failover todo"
# 9. an edit after the stamp is STALE, not done
echo "// touched" >> src/state.rs;              expect "tests stale"
sed -i '$d' src/state.rs;                       expect "failover todo"
scripts/stamp.sh failover
# The part1-complete record is a one-time side effect of the FIRST next.sh
# call to observe it, and only a plain (non-JSON) call prints the banner —
# so check the plain call before `expect`'s --json call claims that "first".
# (Capture to a variable rather than `next.sh | grep -q`: under pipefail,
# grep -q can exit right after matching line 1 while next.sh is still
# writing, SIGPIPEing it — the pipeline then reads as failed even though
# grep matched.)
out="$(scripts/next.sh)"
echo "$out" | grep -q "Part 1 complete" || fail "no Part 1 banner"
grep -q "^done part1 " .uc-progress || fail "part1 completion not recorded"
expect "snapshots todo"
# 11. after Part 1, code edits must not send the user back into Part 1
echo "// part 2 edit" >> src/state.rs;          expect "snapshots todo"
out="$(scripts/next.sh)"
echo "$out" | grep -q "stale" || fail "stale Part-1 stamps should still be mentioned as a note"
# skips are recorded, and unknown ids refused
scripts/progress.sh skip snapshots;             expect "observe todo"
# shellcheck disable=SC1010  # "done" is the verb argument to progress.sh, not the loop keyword
if scripts/progress.sh done nonsense 2>/dev/null; then fail "unknown id accepted"; fi
echo "tutor: PASS"
