---
name: determinism-review
description: Use when reviewing a diff to src/commands.rs, src/state.rs or src/snapshot.rs (or anything apply, on_timer, freeze or project calls) for replica divergence, before calling the work done.
---

# determinism-review

Every replica applies the same committed commands in the same order and must
reach bit-identical state, and a rebuilt replica replays the same log days
later. A divergence is silent: consensus agrees on order, never on state.

## Scope

1. Get the diff: `git diff HEAD -- src/ tests/` (or the range you were given).
2. Read every changed function in full, plus everything it calls that runs
   inside `apply`, `on_timer`, `freeze`, `stream_snapshot`, `install_snapshot`
   or `project`. A hazard in a helper counts.
3. Run `scripts/lint-determinism.sh --all`. It catches the grep-able hazards
   (clocks, RNG, hash collections, floats, I/O, env) and nothing else; the
   checklist below is the rest.

## Checklist

Apply every item to every hunk.

1. **Clock** — `SystemTime::now`, `Instant::now`, `chrono::Utc::now`, any
   time source → `ctx.time_ns`.
2. **Randomness** — `rand`, `Uuid::new_v4`, a thread id, a pointer address →
   `ctx.ids()`.
3. **Hash iteration** — a `HashMap`/`HashSet` (or a type holding one) whose
   order reaches state, a response, the image or the projection → `BTreeMap` /
   `BTreeSet`, or sort before emitting.
4. **Floats** — any `f32`/`f64` stored, compared, or in a response → integers
   (fixed-point).
5. **Overflow** — plain `+`, `-`, `*`, `as` narrowing on replicated values:
   panics in a debug build, wraps in release, so two builds diverge →
   `checked_*` with an error response, or `wrapping_*` / `saturating_*`
   deliberately.
6. **Panics in apply** — `unwrap`, `expect`, `[i]` indexing, `/` by a value
   that can be zero, on anything derived from a command. The panic recurs on
   every replay and fail-stops the service on every node → an error response.
7. **Id minting shape** — compare, per arm, old vs new: the number of
   `ctx.ids()` calls (a second generator in one `apply` restarts at ordinal 0
   and mints a *duplicate* series) and the number of `.next()` calls on each
   generator (an extra call *shifts* every later id in that apply). Either is
   a behaviour change → `FSM_VERSION` bump.
8. **Enum variants** — a variant inserted before the last one, or variants
   reordered, in `Command`, `Response`, `Query`, `QueryResponse` or any type
   inside them: bincode writes the variant *index*, so old log entries decode
   as a different command with no error → append at the end only.
9. **Struct fields** — fields reordered, renamed-and-retyped, removed, or a
   type widened (`u32` → `u64`) in a command or the image. A reorder of two
   same-typed fields is byte-identical and decodes silently wrong → never
   reorder; add new fields only in a new variant or a new `IMAGE_VERSION`.
10. **Image compatibility** — any change to `State`, `Image` or what `freeze`
    writes. `#[serde(default)]` does NOT make bincode read an old image (it
    fails with `UnexpectedEnd`) → bump `IMAGE_VERSION` in `src/snapshot.rs`
    and keep a reader for the old version (`docs/how-to/change-the-state-shape.md`),
    with a golden old-image fixture test.
11. **Ambient input** — file, network, environment, process, config read at
    apply time → put the value in the command, or act after commit on the
    leader.
12. **Cursor** — every path through `apply` ends with
    `self.last_applied = Some(ctx.position)`; `install_snapshot` restores the
    image's own cursor, never the position `P` it was called with.
13. **Behaviour change** — does the diff change what `apply` returns or stores,
    or what `query` returns, for an existing command? Then `FSM_VERSION` in
    `src/identity.rs` must be bumped and WHAT-NEXT.md Step 12 (the
    `upgrade-fsm` skill) is required before it reaches any cluster that ran
    the old version. A new command variant also counts: no client may send
    it until every service runs the new build.

## Output

One line per finding, most severe first:

```
src/state.rs:57 — HashMap iteration feeds the list response — use BTreeMap
```

Then the line `FSM_VERSION bump required: yes|no (<why>)`. If nothing is
found, write exactly `No determinism hazards found.` followed by the files
you read. "None found" over an unread file is worth nothing.
