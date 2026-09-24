# Add a command

A command changes state. It is stored in the log and applied on every replica,
in order, for as long as the cluster lives. This guide adds one, using a
`PutIfAbsent` for the skeleton registry as the example. Replace it with yours.

Do the edits in this order. Each one compiles against the one before it.

## 1. Append the variant — `src/commands.rs`

Add the new variant at the **end** of `Command`, and its answer at the end of
`Response`:

```rust
pub enum Command {
    Put { key: String, value: String },
    Delete { key: String },
    PutIfAbsent { key: String, value: String },   // new: index 2
}

pub enum Response {
    Put { previous: Option<String> },
    Delete { removed: Option<String> },
    PutIfAbsent { inserted: bool },               // new
}
```

The variant's index is its wire tag. Inserting it in the middle, or
reordering, makes every old command in the log decode as a different one, with
no error.

## 2. Check its size — `Command::validate` in `src/commands.rs`

Every variable-length field gets a limit. The registry's match already returns
`(key, Option<value>)`, so extend it:

```rust
Command::Put { key, value } | Command::PutIfAbsent { key, value } => (key, Some(value)),
```

Work out the largest encoded command and keep it under 1296 B (the 1312 B
crypto-on ceiling less the 16 B session envelope). Record it in
`docs/app-design.md`.

## 3. Apply it — `apply` in `src/state.rs`

Add one arm. Keep `self.last_applied = Some(ctx.position)` after the match.

```rust
Command::PutIfAbsent { key, value } => {
    let inserted = !self.state.entries.contains_key(&key);
    if inserted {
        self.state.entries.insert(key, value);
    }
    Response::PutIfAbsent { inserted }
}
```

No clock, no randomness, no I/O, no `unwrap` on input. See
[concepts § Deterministic apply](../concepts.md#deterministic-apply).

## 4. Give the client a subcommand — `src/bin/client.rs`

Three places:

- a `Sub` variant (clap names it `put-if-absent`):
  `PutIfAbsent { key: String, value: String },`
- in `run`, build the command so it is validated before connecting:
  `Sub::PutIfAbsent { key, value } => Some(Command::PutIfAbsent { key: key.clone(), value: value.clone() }),`
  and send it through `submit`:
  `Sub::Put { .. } | Sub::Delete { .. } | Sub::PutIfAbsent { .. } => submit(...)`
- in `submit`, print the answer on one line:

```rust
Response::PutIfAbsent { inserted } => println!(
    "ok inserted={inserted} position={} replayed={}",
    resp.position, resp.replayed
),
```

## 5. Test it — `tests/determinism.rs` and `tests/state.rs`

Add the command to `arb_command`, so the property test exercises the new arm:

```rust
(key.clone(), "[a-z]{0,8}").prop_map(|(key, value)| Command::PutIfAbsent { key, value }),
```

and add a unit test in `tests/state.rs`: inserting into an absent key answers
`inserted: true`, a second attempt answers `false` and leaves the value alone.
Add a `validate` refusal test if the command has a new field.

## 6. Prove it on the cluster — `scripts/demo.sh`

Add `expect` lines: a description, a substring the output must contain, then
the client arguments. Leave the demo re-runnable, because other drills run it
more than once:

```bash
expect "put-if-absent demo-pia 1"   'ok inserted=true'  put-if-absent demo-pia 1
expect "put-if-absent demo-pia 2"   'ok inserted=false' put-if-absent demo-pia 2
expect "delete demo-pia"            'ok removed="1"'    delete demo-pia
```

## Run it

```bash
make check restart-services demo
```

`make check` runs the tests and lints. `make restart-services` rebuilds and
restarts your service on every node; without it the cluster keeps running the
old binary. `make demo` must print `PASS`.

Also update `docs/app-design.md` (its Commands table) and, if you use diff
replay, map the new tag in `upgrade/intent.toml` (`"02" = "put-if-absent"`).

## If a cluster has already run the old version

Appending a variant is safe for the commands already in the log, but it is
still a behaviour change: an old replica cannot decode the new command, and
old and new builds must never run side by side. On any cluster you care about
(anything but your disposable local one), bump `FSM_VERSION` in
`src/identity.rs` and roll it out as an upgrade: capture a corpus with
`make corpus` *before* you change the code, then `make upgrade-check` and
`make upgrade-drill`. `WHAT-NEXT.md` Step 12 is the full procedure.

Upstream: [the state-machine contract](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md)
and [the change taxonomy](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/application-sdlc.md#the-change-taxonomy).
