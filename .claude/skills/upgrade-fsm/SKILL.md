---
name: upgrade-fsm
description: Use when a change alters what apply or query returns or stores (an FSM_VERSION bump), before and after `make upgrade-check` — to capture the corpus, draft upgrade/intent.toml, classify the change, explain an Unexplained/Undeclared/Absent finding in upgrade/report.json, judge a state diff at the origin, and prepare the pinned upgrade.
---

# upgrade-fsm

Adapted from UC's `diff-replay-judge` skill (pinned upstream:
`https://github.com/PeterKnego/ultima_cluster/blob/v<UC_VERSION>/.claude/skills/diff-replay-judge/SKILL.md`).
The harness is code and gives the verdict by its exit code; this skill decides
what to run and explains what broke. WHAT-NEXT.md Step 12 is the procedure.

## 0. Capture the corpus — BEFORE any code change

1. `make up`, `make diffreplay` (installs `.uc/cargo/bin/uc2-diffreplay`).
2. Check `scripts/demo.sh` sends the command you will change, with inputs
   where the change shows. A corpus proves only what it exercises.
3. `make corpus`. It runs the demo, takes an instant P, runs the demo again
   above P, and exports that span to `upgrade/corpus/`. The demo runs *below*
   P on purpose: an instant of a state machine that has applied nothing has no
   cursor, and diff replay refuses to install that image. The OLD binary is
   copied from the running service process to `upgrade/old/<app>-service` —
   never rebuilt from source. It refuses when `src/identity.rs` already names a
   different version from the running one: check out the running code first.

## 1. Draft the declaration

Out: `upgrade/intent.toml` (copied from `upgrade/intent.toml.example` by
`make corpus`). Hand it to the developer to review: you draft what the change
*does*; only they can say what it was *supposed* to do.

1. List every arm the diff touches and the surface it moves on:
   `response`, `sched` (timers), `ids`, `output`, `projection_origin`,
   `projection_end`. An arm the diff does not reach stays off every list.
2. `tag_offset = 16` (the `Sessioned` envelope, `client_id ‖ seq`). `[tags]`
   keys are hex of the bincode variant index: `"00" = "put"`,
   `"01" = "delete"`, a third variant `"02"`. Confirm against the corpus,
   not by eye:
   ```bash
   mkdir -p target/scratch
   upgrade/old/*-service replay --corpus upgrade/corpus --out target/scratch/trace.json
   python3 -c 'import json,sys; [print(e["pos"], e["kind"], bytes(e["tag"]).hex()) for e in json.load(open(sys.argv[1]))["entries"]]' target/scratch/trace.json
   ```
   Drop the first 16 bytes (32 hex chars); the next byte is the tag. Scratch
   files stay under `target/`, never outside the project.
3. `[timers]`: map each timer id to an arm name, the id as a decimal string
   (`"9" = "expire"`). A `TIMER` frame carries no application payload, so
   `[tags]` can never reach it: without this entry every timer divergence is
   permanently `Unexplained`. Skip it only if the app schedules no timers.
4. `[touched] arms = [...]`: exactly the arms the change may move.
   `migration = true` only if `IMAGE_VERSION` changed.
5. One `[[expect]]` per `(surface, arm)` pair, with a `note` in the
   developer's words. `projection_origin` / `projection_end` take no `arm`. An
   `[[expect]]` without `arm` on another surface is a wildcard over every arm.
   A second entry on the same pair reads `Absent`.
6. Check the file parses before handing it over — `upgrade` is the only mode
   that reads a declaration, so run it with the SAME binary on both sides:
   ```bash
   .uc/cargo/bin/uc2-diffreplay upgrade --corpus upgrade/corpus \
     --old upgrade/old/*-service --new upgrade/old/*-service \
     --declare upgrade/intent.toml --report target/scratch/parse.json
   ```
   A malformed declaration is refused by name. One binary means an empty
   profile, so every `[[expect]]` reads `Absent`: this checks the **file**, not
   the change.

## 2. Classify the change

1. First scan for the silent-misparse shapes: a variant inserted mid-enum, or
   two fields reordered. If present, stop and say so — the fix is to append
   instead, not to declare it.
2. Name each hunk's row in the change taxonomy
   (`https://github.com/PeterKnego/ultima_cluster/blob/v<UC_VERSION>/docs/reference/application-sdlc.md#the-change-taxonomy`):
   new variant (appended), snapshot image format, changed `apply` semantics of
   an existing command, …
3. Derive the `FSM_VERSION` digit: **major** if an un-upgraded replica could
   not apply the new log (a new variant, changed semantics), **minor** if
   additive and inert, **patch** if no replicated behaviour changes. Never
   change `FSM_NAME`: that is a different state machine.

## 3. Attribute the residue — after `make upgrade-check` fails

Read `upgrade/report.json`:
```bash
jq -r '.findings[] | "\(.verdict) \(.surface) arm=\(.arm) pos=\(.pos) \(.note)"' upgrade/report.json
```
- **Unexplained, `no touched arm explains this`**: on the `sched` surface
  from a `TIMER` frame, the timer id is missing from `[timers]` (a timer has
  no tag, so `[tags]` is not the fix). Otherwise, if the tag maps to no arm,
  `[tags]`/`tag_offset` is wrong — fix and re-run. If it maps to an arm not in
  `[touched]`, a command the change never claimed to touch moved: a shared
  helper, a field it reads, or a bug. Name the hunk (`git diff -- src/`) or
  write `cannot attribute` with the files read.
- **Unexplained, `dispatched by one build only`**: the builds disagree on
  which frames reached the FSM (a session `replayed` on one side); not a
  response bug despite the `response` label.
- **Undeclared**: attributed but not declared — a forgotten `[[expect]]` or a
  bug in that arm. Say which.
- **Absent**: declared but never observed — the corpus never exercised it, or
  the change does not do what the note says.
An intended difference goes back into `upgrade/intent.toml` and
`make upgrade-check` runs again. PASS counts only for exactly this code and
intent; any later edit withdraws it.

## 4. Judge the state at the origin

`profile.projection_origin` is the pure migration: both builds installed the
same old artifact and ran `project()` with no command applied.
```bash
jq -r '.profile.projection_origin.removed[] | "- " + .' upgrade/report.json
jq -r '.profile.projection_origin.added[]   | "+ " + .' upgrade/report.json
```
Say the delta in one sentence and check every line against the old-image
branch of `install_snapshot` in `src/snapshot.rs`. A line the reader does not
account for is a reader defect. Judge `projection_end` only after that.

## 5. Spot what a lint cannot

Per arm, old vs new: the count of `ctx.ids()` calls (duplicated id series)
and of `.next()` per generator (shifted ids); `HashMap`/`HashSet` iteration
reaching output; floats; mid-enum inserts; field reorders. Report
`file:line — hazard`, or "none found" plus the files read. The
`determinism-reviewer` subagent runs the full checklist.

## 6. The pin — a one-way door

`make upgrade-drill` builds, takes an instant, backs up every node, then
**pins**: there is no unpin, and the only rollback is those backups restored on
every node. **Ask the developer and wait for an explicit yes in this
conversation before running it.** It asks them to type `PIN`; never set
`UC_CONFIRM_PIN=yes` for them. If it stops after the pin committed, do not
start over (new backups would carry the pin): `make upgrade-drill RESUME=1`.
Until the drill has passed, no client may send a new command variant.
