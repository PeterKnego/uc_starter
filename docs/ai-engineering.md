# Working with an AI agent

This project is set up so an agent can help at every step without being
trusted blindly: the agent's position in the tutorial is computed, its work is
checked by the same commands you run, and the one irreversible operation
always needs you.

## The loop

1. **Tutor.** Ask "what next?". The agent runs `scripts/next.sh --json`, reads
   the step it names in `WHAT-NEXT.md`, explains the concept, and asks whether
   you want to do the step yourself (it guides and reviews) or have it done
   (it makes the change, then walks you through the diff).
2. **Design note as the spec.** Before code, the agent interviews you and
   drafts `docs/app-design.md`: commands, queries, state, size bounds, and the
   determinism hazards you considered. Review it. It is what the code is held
   to.
3. **Plan.** For anything larger than one command, have the agent write the
   steps first: which files, which tests, which checks.
4. **Implement**, in small diffs.
5. **Determinism review.** Grep-level hazards are flagged at each edit by
   the hook. Once per change, before it is committed, a diff that alters code
   `apply`, `query`, `on_timer`, `freeze` or the snapshot run goes past the
   `determinism-reviewer` subagent, which catches what a grep cannot
   (overflow, panics on input, id-series shifts, mid-enum inserts).
6. **`make check`.** Tests, fmt, clippy, the MSRV clippy and the determinism
   grep. A step is done when its check passes, not when the agent says so.
7. **Diff replay before any `VERSION` bump.** A behaviour change to a state
   machine that has run is an upgrade: `make corpus` before the change,
   `make upgrade-check` after it, then `make upgrade-drill`, which pins. The
   agent drafts `upgrade/intent.toml` from the diff; you review it, because it
   is the statement of what the change is allowed to do.

Throughout, `make next` is the source of truth for where you are. If the
agent and `make next` disagree, `make next` is right.

## The Claude Code kit

The project ships a Claude Code configuration under `.claude/` and a
`CLAUDE.md` that imports `AGENTS.md`.

**Skills** (`.claude/skills/<name>/SKILL.md`), each loaded when its task comes
up:

| skill | use |
|---|---|
| `next` | the tutor protocol: run `scripts/next.sh --json`, teach the step, ask "do it yourself, or shall I?", run the step's check |
| `add-command` | adding or changing a command or query: the six edits of [Add a command](how-to/add-a-command.md), then the reviewer, then `make check restart-services demo` |
| `determinism-review` | the checklist: clocks, RNG, hash iteration, floats, overflow, panics in `apply`, changed `ids()` call counts, enum and field order, image compatibility (a new `IMAGE_VERSION` with an old-image reader: `#[serde(default)]` does not let bincode read an old image) |
| `upgrade-fsm` | the diff-replay judgement: draft the intent declaration, classify the change, attribute the report's residue to a hunk, judge the state at the origin, spot what a lint cannot. Ends by asking before `make upgrade-drill` |
| `troubleshoot-cluster` | run `make status`, read the process logs, match the named refusal against [troubleshooting](troubleshooting.md), quote the fix; never delete cluster state without asking |
| `cloud-infra` | deploy, test, bench, check status, log or tear down the app on cloud hosts; states the cost and what will be created, changed or destroyed, and waits for a yes in the conversation before any `cloud-*` command (rule 9 — the agent states the cost and waits for your yes before any cloud command) |

**Subagent** `determinism-reviewer` (`.claude/agents/determinism-reviewer.md`):
a read-only reviewer that checks a state-machine diff against the
`determinism-review` checklist and whether the change needs an `FSM_VERSION`
bump. It reports `file:line — hazard — fix` lines, or that it found none.

**Hook** (`.claude/hooks/post-edit.sh`, on `PostToolUse` for edits): after the
agent edits a Rust file, it runs `rustfmt` on it and
`scripts/lint-determinism.sh` on it. A hazard (a clock read in `apply`, a
`HashMap`) is reported back to the agent at the edit, naming the replacement,
instead of surfacing later in `make lint`.

**Permissions** (`.claude/settings.json`): there is no `allow` list. In auto
mode the classifier approves routine work (`make`, `cargo`, `git`); in the
default mode Claude Code asks before anything that is not read-only. Add your
own allowances in `.claude/settings.local.json`, which is not committed.
Anything that can pin an upgrade **always asks you**:
any command that mentions `upgrade-drill`, `UC_CONFIRM_PIN` or
`upgrade pin`, or runs `.uc/bin/uc2ctl`, asks, even in auto mode. The rules
match the text anywhere in the command (`Bash(*upgrade-drill*)`,
`Bash(*UC_CONFIRM_PIN*)`, `Bash(*upgrade pin*)`), so reordered or quoted
`make` arguments cannot slip past them, and Claude Code checks `ask` rules
before `allow` rules and before the auto-mode classifier, so no allowance you
add can cover them. The scripts guard the pin as well: `make
upgrade-drill` asks you to type `PIN`, and `scripts/cluster.sh ctl … upgrade
pin` refuses without `UC_CONFIRM_PIN=yes`. A pin is a one-way door: there is
no unpin, and the only rollback is the backup taken before it. Any command
containing `FRESH=1` asks too (`Bash(*FRESH=1*)`): `make up FRESH=1` deletes
the local cluster's nodes, logs and pids.

## Other agents

`AGENTS.md` is the contract, and it is written for any agent: the project map,
the commands, the hard rules (determinism; append-only enums; `validate()` for
every size-bearing field; bump `FSM_VERSION` for any behaviour change once a
cluster you keep has run the code, `make up FRESH=1` before that; never
pin without the developer's explicit go-ahead; never put cluster state under
`/tmp`; never edit `.uc/`; scratch files under `target/`), the evidence rule (show the command and its
output, or say "not verified"), and the tutor protocol.

An agent without Claude Code's skills and hooks works from `AGENTS.md` alone.
Give it the same two tools the kit relies on: `scripts/next.sh --json` for
position, and `make check` / `scripts/lint-determinism.sh --all` for
evidence. `next.sh --json` prints one object: `step`, `of`, `part`, `id`,
`title`, `status` (`todo`, `stale` or `complete`), `part1_complete`,
`part1_just_completed` and `detail` (a list of what is missing).

## Add your own skill

A skill is a folder with one file, `.claude/skills/<name>/SKILL.md`: YAML
frontmatter with a `name` and a `description` that says **when** to use it,
then the instructions.

```markdown
---
name: add-endpoint-limit
description: Use when adding a new size-bearing field to a command or raising a MAX_* limit in src/commands.rs.
---
1. Work out the largest encoded command with the new limit …
2. …
```

Keep it short and concrete: the files, the order, the check that proves it.
Point it at the project's own commands (`make check`, `scripts/next.sh`)
rather than restating them. If a rule matters to every agent, not just Claude
Code, put it in `AGENTS.md` too.

For a larger example, UC's own
[`diff-replay-judge` skill](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/.claude/skills/diff-replay-judge/SKILL.md)
is what this project's `upgrade-fsm` skill is adapted from; the harness it
judges is described in
[Diff replay an FSM change](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/diff-replay.md).
