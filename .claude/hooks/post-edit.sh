#!/usr/bin/env bash
# PostToolUse (Edit|Write): format the edited Rust file, then flag determinism
# hazards at the edit. Exit 2 sends stderr back to the agent (the hook entry in
# .claude/settings.json sets continueOnBlock, so the turn continues).
set -uo pipefail
input="$(cat)"
if command -v jq >/dev/null; then
  f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
else
  f="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
case "$f" in *.rs) ;; *) exit 0 ;; esac
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
rel="${f#"$PWD"/}"
[ -f "$rel" ] || exit 0
rustfmt --edition 2024 "$rel" 2>/dev/null || true
if ! out="$(scripts/lint-determinism.sh "$rel")"; then
  printf 'Determinism hazard in %s (apply must give the same result on every replica):\n%s\nFix it with the substitute named above. Exempt a line with `// determinism: ok <why>` only if the developer agrees.\n' "$rel" "$out" >&2
  exit 2
fi
exit 0
