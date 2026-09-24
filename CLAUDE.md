@AGENTS.md

## Claude Code specifics

- `/next` (skill `next`) runs the tutor protocol above.
- Skills: `add-command`, `determinism-review`, `upgrade-fsm`, `troubleshoot-cluster` — use them for those tasks.
- Subagent `determinism-reviewer`: run it on every diff that touches `src/commands.rs`, `src/state.rs` or `src/snapshot.rs` before calling the work done.
- A PostToolUse hook formats edited Rust files and reports determinism hazards at the edit; fix what it reports rather than suppressing it (`// determinism: ok <why>` only with the developer's agreement).
- `.claude/settings.json` always asks before `make upgrade-drill`, `scripts/upgrade-drill.sh`, `.uc/bin/uc2ctl`, anything carrying `UC_CONFIRM_PIN=yes` and anything containing `upgrade pin`. A permission prompt is not the developer's go-ahead: get it in the conversation first (AGENTS.md, hard rule 5).
