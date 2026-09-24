#!/usr/bin/env bash
# The Claude Code kit's edit hook: clean Rust passes, a determinism hazard in a
# state-machine file exits 2 naming the substitute, non-Rust files pass, and
# the settings wire the hook so exit 2 reaches the agent (continueOnBlock).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HOME/scratch/uc_starter-gen/hook"; rm -rf "$B"; "$HERE/gen.sh" "$B" >/dev/null; cd "$B/demo-app"
fail() { echo "FAIL: $*" >&2; exit 1; }
payload() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$PWD/$1"; }
[ -x .claude/hooks/post-edit.sh ] || fail ".claude/hooks/post-edit.sh missing or not executable"
payload src/state.rs | CLAUDE_PROJECT_DIR="$PWD" .claude/hooks/post-edit.sh || fail "clean file flagged"
echo 'fn _h() { let _t = std::time::SystemTime::now(); }' >> src/state.rs
set +e; out="$(payload src/state.rs | CLAUDE_PROJECT_DIR="$PWD" .claude/hooks/post-edit.sh 2>&1)"; rc=$?; set -e
[ $rc = 2 ] || fail "hazard should exit 2, got $rc"
[[ "$out" == *"ctx.time_ns"* ]] || fail "message should name the substitute: $out"
sed -i '$d' src/state.rs
payload README.md | CLAUDE_PROJECT_DIR="$PWD" .claude/hooks/post-edit.sh || fail "non-rust file must pass"
# a Rust file outside the state-machine files is formatted but never blocked
payload src/bin/client.rs | CLAUDE_PROJECT_DIR="$PWD" .claude/hooks/post-edit.sh || fail "client.rs must pass"
python3 -m json.tool .claude/settings.json >/dev/null || fail "settings.json is not JSON"
python3 - <<'EOF' || fail "settings.json: hook wiring or pin permissions wrong"
import json
s = json.load(open(".claude/settings.json"))
h = s["hooks"]["PostToolUse"][0]
assert "Edit" in h["matcher"] and "Write" in h["matcher"], h["matcher"]
cmd = h["hooks"][0]
assert cmd["command"].endswith("/.claude/hooks/post-edit.sh"), cmd
assert cmd.get("continueOnBlock") is True, "exit 2 must feed back to the agent"
ask = s["permissions"]["ask"]
for r in ("Bash(make upgrade-drill:*)", "Bash(scripts/upgrade-drill.sh:*)", "Bash(*upgrade pin*)", "Bash(.uc/bin/uc2ctl:*)"):
    assert r in ask, r
EOF
for f in AGENTS.md CLAUDE.md .claude/agents/determinism-reviewer.md \
         .claude/skills/{next,add-command,determinism-review,upgrade-fsm,troubleshoot-cluster}/SKILL.md; do
  [ -s "$f" ] || fail "$f missing"
done
echo "hook: PASS"
