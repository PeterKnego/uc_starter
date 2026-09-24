# Schedule work

Your state machine needs to act later: expire an entry, retry something, sweep
a table. `apply` cannot read a clock or sleep, so it asks the cluster to wake
it: `ctx.schedule` in `apply`, and the wake-up arrives in `on_timer`, as a
command on the log like any other.

## 1. Ask to be woken — `apply` in `src/state.rs`

```rust
Command::PutWithTtl { key, value, ttl_ms } => {
    let id = self.next_timer_id();                 // your own counter, kept in State
    self.expiries.insert(id, key.clone());         // the timer carries no payload
    ctx.schedule(id, ctx.time_ns + ttl_ms * 1_000_000);
    // …
}
```

- `ctx.time_ns` is "now": the leader's stamp on this command, the same on
  every replica and never going backwards. Compute deadlines from it only.
- `ctx.schedule(id, at_ns)` asks for a wake-up; `ctx.cancel(id)` withdraws it.
  Both are outputs of `apply`, replayed identically on every replica.
- One pending timer per id: scheduling an id that is already pending replaces
  its deadline.
- A timer carries only its id and deadline. Keep its context in your state,
  keyed by the id, as `expiries` does above. The id counter is state too, so it
  goes in the snapshot image.
- Use `checked_mul` / `checked_add` on client-supplied durations: plain
  arithmetic overflows.

## 2. Handle the wake-up — `on_timer` in `impl StateMachine for Fsm`

`on_timer` is a provided method with a no-op default. Implement it:

```rust
fn on_timer(&mut self, ctx: &mut ApplyCtx, ev: TimerEvent) {
    if let Some(key) = self.expiries.remove(&ev.id) {
        self.state.entries.remove(&key);
    }
    // ev.late(ctx): fired after its deadline, e.g. across a leader change.
    self.last_applied = Some(ctx.position);        // exactly as in apply
}
```

`on_timer` follows the same rules as `apply`: deterministic, no I/O, no
panics. It may schedule again through the same `ctx`, so a periodic sweep is a
timer that re-arms itself.

## 3. Decide on `Timed<S>` — `src/bin/service.rs`

The node delivers a timer **at least once**: one in flight during a leader
change can fire twice. `uc_service::Timed<S>` makes delivery exactly once by
keeping the pending set your `schedule` / `cancel` calls implied and dropping
a firing that is no longer pending. It composes with the session wrapper:

```rust
Timed::new(Sessioned::new(Fsm::default(), SessionConfig::default()))
```

`service.rs` builds the wrapper stack in **two** places: the `sm` closure used
by the `replay` / `project` subcommands, and the live attach. Change both, so
diff replay runs the same stack the cluster does.

Take `Timed` unless your `on_timer` is idempotent. Decide early: `Timed`
writes its pending set into the snapshot artifact ahead of your state, and its
`install_snapshot` has no path for an artifact written without it. Adding or
removing it on a cluster that already has snapshots changes the artifact
format, which needs the same care as
[changing the state shape](change-the-state-shape.md).

## 4. Test and prove it

- Unit tests: build a context with `ApplyCtx::for_sm::<Fsm>(position).with_time(ns)`,
  apply the command, then call `on_timer` directly with a `TimerEvent` and
  check the state.
- Diff replay sees timers as their own surface (`sched`), and a `TIMER` frame
  has no payload to tag: map its id to an arm under `[timers]` in
  `upgrade/intent.toml`.
- An operator can also fire your `on_timer` on a wall-clock schedule through
  the replicated schedule table (`uc2ctl schedule apply`); those arrive with
  `ev.table` set. Keep the two id ranges apart.

Upstream: [Schedule work inside a state machine](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/schedule-work-in-a-service.md),
[Run work on a schedule](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/run-work-on-a-schedule.md)
and [Log time and timers, explained](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/notes/uc2-log-time-and-timers-explained.md).
