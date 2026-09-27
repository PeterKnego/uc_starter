---
name: add-command
description: Use when adding or changing a command or query — a Command/Query variant, its apply or query arm, or the client subcommand that sends it.
---

# add-command

The full worked example is `docs/how-to/add-a-command.md` (commands) and
`docs/how-to/add-a-query.md` (queries). Do the edits in this order; each one
compiles against the one before it.

## Before touching code

Ask the developer: has any cluster other than the disposable local one run
the current version? If yes, this is an upgrade: `make corpus` now, with the
cluster running the old build (the `upgrade-fsm` skill), and bump
`FSM_VERSION` in `src/identity.rs` as part of the change.

## The six edits

1. **Variant** — `src/commands.rs`, `enum Command` and `enum Response`
   (queries: `enum Query` and `enum QueryResponse`). Append at the END. Never
   insert, reorder, or rename fields: the variant index is the wire tag.
2. **Size check** — `src/commands.rs`, `Command::validate`. Every
   variable-length field gets a `MAX_*` limit; the largest encoded command
   stays under 1296 B. Record it in `docs/app-design.md`.
3. **Apply** — `src/state.rs`, `impl StateMachine for Fsm`, `fn apply` (queries:
   `fn query`). One arm. Keep `self.last_applied = Some(ctx.position)` after the
   match. Bad input gets an error `Response`, never a panic.
4. **Client** — `src/bin/client.rs`: a `Sub` variant; in `run`, build the
   `Command` so it is validated before connecting and route it to `submit`;
   in `submit`, print the response on one line. Read subcommands take
   `--linearizable`.
5. **Tests** — `tests/determinism.rs`, `arb_command`: one strategy for the new
   variant, small key space. `tests/state.rs`: one unit test for the arm, plus
   a `validate` refusal test for each new field.
6. **Demo** — `scripts/demo.sh`: `expect "<description>" '<substring>' <args…>`
   lines for the new subcommand. Keep the demo re-runnable (it runs more than
   once per drill).

Also: `docs/app-design.md` Commands table, and if `upgrade/intent.toml`
exists, map the new tag (`"02" = "<arm>"` for the third variant).

## Review and prove

1. Once the command, its arm and its tests are all in place, dispatch the
   `determinism-reviewer` subagent on the whole diff — one run for the
   change. Fix every line it reports.
2. Run `make check restart-services demo`. Done when `make check` passes and
   `make demo` prints `PASS`. Show the output.
3. If the local cluster's log holds commands from an enum you replaced (not
   appended to), `make up FRESH=1` first.

## The rollout order

A client that sends the new variant runs only after **every** service runs the
new build. On a real cluster that means after the pin has committed and every
service restarted (TUTORIAL.md Step 12). A new-variant command committed
earlier is decoded by every old service, which fail-stops with
`corrupt committed frame (fail-stop)`, on every node and on every restart,
and the dead services then cannot complete the instant the pin needs. Ship
the service first, the client last. Never run `make upgrade-drill` without
the developer's explicit go-ahead.
