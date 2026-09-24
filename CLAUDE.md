@AGENTS.md

## Claude Code specifics

- `/next` (skill `next`) runs the tutor protocol above.
- Skills: `add-command`, `determinism-review`, `upgrade-fsm`, `troubleshoot-cluster` — use them for those tasks.
- Subagent `determinism-reviewer`: run it on every diff that touches `src/commands.rs`, `src/state.rs` or `src/snapshot.rs` before calling the work done.
- A PostToolUse hook formats edited Rust files and reports determinism hazards at the edit; fix what it reports rather than suppressing it (`// determinism: ok <why>` only with the developer's agreement).
- `.claude/settings.json` asks before any command that mentions `upgrade-drill`, `UC_CONFIRM_PIN` or `upgrade pin`, or runs `.uc/bin/uc2ctl` — even in auto mode. A permission prompt is not the developer's go-ahead: get it in the conversation first (AGENTS.md, hard rule 5).
