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

[ "$(scripts/next.sh --list | tr '\n' ' ')" = "env skeleton concepts design commands state tests client failover snapshots observe upgrade deploy cloud " ] || fail "--list"
# the doc and the checker agree on ids and order
[ "$(grep -oE '<!-- step: [a-z-]+ -->' WHAT-NEXT.md | sed 's/<!-- step: \(.*\) -->/\1/' | tr '\n' ' ')" = "$(scripts/next.sh --list | tr '\n' ' ')" ] || fail "WHAT-NEXT.md step ids differ from next.sh --list"

# F3: bash 3.2 (macOS's stock /bin/bash) raises "unbound variable" expanding
# "${arr[@]}" on a declared-but-empty array under `set -u` — DETAIL/notes may
# only ever be expanded through the ${arr[@]+"${arr[@]}"} guard. Strip every
# correctly-guarded occurrence out of a copy of the source and fail if a bare
# ${DETAIL[@]} / ${notes[@]} is left over (cheap, deterministic, no need for
# an actual bash 3.2 to reproduce it on).
stripped="$(sed -E 's/\$\{(DETAIL|notes)\[@\]\+"\$\{(DETAIL|notes)\[@\]\}"\}//g' scripts/next.sh)"
echo "$stripped" | grep -qE '\$\{(DETAIL|notes)\[@\]' && fail "bash-3.2-unsafe bare \${DETAIL[@]}/\${notes[@]} expansion in next.sh"

mv .uc .uc.away 2>/dev/null || true
expect "env todo"
mv .uc.away .uc 2>/dev/null || make -s bins >/dev/null
expect "skeleton todo"
scripts/stamp.sh skeleton;                      expect "concepts todo"
# shellcheck disable=SC1010  # "done" is the verb argument to progress.sh, not the loop keyword
scripts/progress.sh done concepts;              expect "design todo"
unmark docs/app-design.md;                      expect "commands todo"
unmark src/commands.rs;                         expect "state todo"
mv docs/app-design.md "$BASE/app-design.md.away"; expect "design todo"  # M12: a missing note is not a finished one
mv "$BASE/app-design.md.away" docs/app-design.md; expect "state todo"
unmark src/state.rs src/snapshot.rs;            expect "state todo"   # I3: tests/state.rs is Step 6's proof
unmark tests/state.rs;                          expect "tests todo"
unmark tests/*.rs;                              expect "tests todo"   # no check stamp yet
scripts/stamp.sh check;                         expect "client todo"
# src/bin/client.rs is part of `src`, so this edit is covered by the "tests"
# step's whole-src hash too (WHAT-NEXT.md §5.2's "a hash of src/") — pin that
# whole-src staleness behaviour rather than stepping around it: the very next
# poll reports "tests" stale again, even though client/demo.sh are done.
unmark src/bin/client.rs scripts/demo.sh;       expect "tests stale"
scripts/stamp.sh check >/dev/null;             expect "client todo"  # C1: scripts/probe.sh is Step 8's too
unmark scripts/probe.sh
# a real developer re-runs `make check` after any src/ edit, so the drill
# does too, before moving on to the client's own demo stamp.
scripts/stamp.sh check >/dev/null
scripts/stamp.sh demo;                          expect "failover todo"
# 9. an edit after the stamp is STALE, not done
echo "// touched" >> src/state.rs;              expect "tests stale"
sed -i '$d' src/state.rs;                       expect "failover todo"
scripts/stamp.sh failover;                      expect "snapshots todo"
# part1_just_completed is DERIVED each call (not a one-shot flag consumed by
# whichever call — JSON or human — observes it first), so the brief's
# original order works: the --json `expect` above already saw the
# transition, and the banner still shows on this later plain call.
out="$(scripts/next.sh)"
echo "$out" | grep -q "Part 1 complete" || fail "no Part 1 banner"
# Part 1's completion is a MACHINE-LOCAL stamp now (never .uc-progress, which
# is committed) — R6.
[ -f .uc/state/part1.ok ] || fail "part1 completion not stamped machine-locally"
grep -q "part1" .uc-progress && fail "part1 must not be recorded in the committed .uc-progress"

# R6: check_env is blocking in EVERY mode, including once Part 1 is
# machine-locally complete — if the binaries later go missing, env is the
# reported step, not silently absorbed into the Part-1 "history" notes.
mv .uc/bin .uc/bin.away
expect "env todo"
mv .uc/bin.away .uc/bin
expect "snapshots todo"

# 11. after Part 1, code edits must not send the user back into Part 1
echo "// part 2 edit" >> src/state.rs;          expect "snapshots todo"
out="$(scripts/next.sh)"
echo "$out" | grep -q "stale" || fail "stale Part-1 stamps should still be mentioned as a note"

# F4: in history mode, only the checks that can go stale (tests/client/
# failover) run — commands/state's `cargo check`/`cargo test` must NOT run,
# since todo_in-only checks can never produce a note. Pin it by making
# `cargo` a shim that would fail loudly (and leave evidence) if invoked.
FAKE_BIN="$BASE/fake-bin"; mkdir -p "$FAKE_BIN"
CARGO_MARKER="$BASE/cargo-invoked-marker"; rm -f "$CARGO_MARKER"
cat > "$FAKE_BIN/cargo" <<SHIM
#!/usr/bin/env bash
touch "$CARGO_MARKER"
exit 99
SHIM
chmod +x "$FAKE_BIN/cargo"
out="$(PATH="$FAKE_BIN:$PATH" scripts/next.sh)"; rc=$?
[ $rc -eq 0 ] || fail "next.sh failed (exit $rc) with a broken cargo on PATH in history mode"
[ -f "$CARGO_MARKER" ] && fail "cargo was invoked in history mode — commands/state must be skipped there"
echo "$out" | grep -q "Snapshots and purge" || fail "next.sh reported the wrong step with a broken cargo on PATH"

# skips are recorded, and unknown ids refused
scripts/progress.sh skip snapshots;             expect "observe todo"
# shellcheck disable=SC1010  # "done" is the verb argument to progress.sh, not the loop keyword
if scripts/progress.sh done nonsense 2>/dev/null; then fail "unknown id accepted"; fi
# part1 is a machine-local stamp, not a step a person records (R6)
# shellcheck disable=SC1010  # "done" is the verb argument to progress.sh, not the loop keyword
if scripts/progress.sh done part1 2>/dev/null; then fail "'part1' accepted as a step id"; fi
# M6: `done` only for the steps the repo cannot show (concepts, deploy)
# shellcheck disable=SC1010  # "done" is the verb argument to progress.sh, not the loop keyword
if scripts/progress.sh done observe 2>/dev/null; then fail "'make done STEP=observe' accepted — only concepts and deploy may be recorded by hand"; fi
# shellcheck disable=SC1010  # "done" is the verb argument to progress.sh, not the loop keyword
scripts/progress.sh done deploy >/dev/null || fail "'make done STEP=deploy' refused"

# Step 14 (cloud): proven only by make cloud-test's stamp, never by hand
scripts/progress.sh skip observe >/dev/null
scripts/progress.sh skip upgrade >/dev/null
mkdir -p dist; : >dist/demo-app-0.1.0-x86_64.tar.gz
expect "cloud todo"
# shellcheck disable=SC1010  # "done" is the verb argument to progress.sh, not the loop keyword
if scripts/progress.sh done cloud 2>/dev/null; then fail "'make done STEP=cloud' accepted — cloud is proven by make cloud-test"; fi
scripts/stamp.sh cloud >/dev/null
expect "done complete"
[ "$(scripts/next.sh --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["of"])')" = 14 ] || fail '"of" is not 14'
echo "tutor: PASS"
