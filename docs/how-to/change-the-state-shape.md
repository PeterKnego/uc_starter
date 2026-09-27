# Change the state shape

You want to change what `State` holds: add a field, change a type, restructure
a map. On a cluster that has already run, this is an upgrade, and it touches
three things: the snapshot image, the FSM version, and the diff-replay
declaration.

Why the image matters: during a pinned upgrade every node installs the
snapshot at the origin instant, and that snapshot was written by the **old**
build. Your new build must be able to read it. So a new image format always
comes with a reader for the old one.

## Before you change any code

With the cluster running the old build:

```bash
make diffreplay     # once
make corpus         # snapshot + a span of log, and a copy of the running binary
```

The corpus is taken from the running cluster and the old binary is copied
from the running service process, so capture it *before* you edit. See
`TUTORIAL.md` Step 12.

## 1. Bump `IMAGE_VERSION` and keep reading the old image — `src/snapshot.rs`

The image layout is `image_version u32 LE ‖ len u64 LE ‖ bincode(Image)`.
Write the new version, and accept both on install. Keep the old types as
private, read-only copies:

```rust
const IMAGE_VERSION: u32 = 2;

/// The v1 image, exactly as the old build wrote it. Never change these.
#[derive(Deserialize)]
struct ImageV1 {
    cursor: Option<u64>,
    state: StateV1,
}
#[derive(Deserialize)]
struct StateV1 {
    entries: BTreeMap<String, String>,
}
```

In `install_snapshot`, replace the single-version check with a match on the
version word, and decode the body with the type that version names:

```rust
let v = u32::from_le_bytes(word);
if v != 1 && v != IMAGE_VERSION {
    return Err(codec(format!("unknown image version {v} (this build reads 1 and {IMAGE_VERSION})")));
}
// … read `len` and `body` exactly as today …
let img: Image = match v {
    1 => {
        let old: ImageV1 = decode_whole(&body)?;
        Image { cursor: old.cursor, state: State::from_v1(old.state) }
    }
    _ => decode_whole(&body)?,
};
```

where `decode_whole` is the existing bincode decode plus the trailing-bytes
check, and `State::from_v1` fills the new fields with values that are a pure
function of the old state (no clock, no randomness). Keep the cursor check and
"nothing changes unless the whole image decodes" as they are.

Before editing, save a v1 image from the old code as a test fixture (write
`image(&filled())` from `tests/snapshot.rs` to a file under `tests/fixtures/`)
and add a test that the new build installs it. UC's `examples/kv` does this
with `tests/fixtures/v1-golden.kvimage`, and its `install_snapshot` reads
image versions 1 and 2.

## 2. Bump `FSM_VERSION` — `src/identity.rs`

For example `pack_version(1, 1, 0)`. Any change to what `apply` stores or
returns is a new version.

## 3. Declare the migration — `upgrade/intent.toml`

```toml
[touched]
arms = ["put"]        # the arms whose behaviour changed, if any
migration = true      # the snapshot image format changed

[[expect]]
surface = "projection_origin"
note = "state at the origin now carries <your new field>"
```

Add `projection_origin` / `projection_end` entries only if your change shows
in `project()`'s text; `make upgrade-check` fails on a declared difference it
did not see, as well as on one you did not declare. Then:

```bash
make check upgrade-check
make upgrade-drill            # asks you to type PIN: a pin is a one-way door
```

## Keep `freeze()` cheap as the state grows

`freeze()` runs on the apply thread, and a freeze that runs long on a quorum
of nodes stalls the cluster's commit until it ends. The skeleton clones the whole `State`
there, which is O(state): fine while it is small, a cluster-wide pause when it
is large. The contract asks for an O(1) freeze.

Two shapes, with different costs:

- **`Arc<BTreeMap<…>>`** (what UC's `examples/kv` uses). `freeze` clones the
  `Arc`. Writes go through `Arc::make_mut`, so the first write after each
  instant pays one O(n) copy of the map, and every later write is an ordinary
  B-tree operation. Serde serializes an `Arc` as its contents (enable serde's
  `rc` feature), so the image bytes do not change.
- **A persistent map such as `im::OrdMap`.** `freeze` clones in O(1), and every
  write pays O(log n) path copying instead of one big copy per instant. UC's
  kv example used it and dropped it on 2026-09-20: the `im` crate is
  unmaintained (RUSTSEC-2026-0248) and has an open unsoundness advisory
  (RUSTSEC-2023-0126). If you take this route, pick a maintained crate.

Either way, the O(state) work (serializing) belongs in `stream_snapshot`,
which runs off the apply thread. To see what an instant costs, read
`uc2_snapshot_freeze_seconds_max` from a node's metrics
(`scripts/cluster.sh metrics 0 | grep freeze`).

Changing only the in-memory representation (for example `BTreeMap` to
`Arc<BTreeMap>`), with the same image bytes and the same answers, is not a
behaviour change and needs no `FSM_VERSION` bump. `make upgrade-check` with
nothing declared in `upgrade/intent.toml` is how you show that.

Upstream: [the state-machine contract § Snapshots](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md#snapshots-the-instant-the-envelope-and-the-exclusive-frontier),
[the kv example's design note](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/examples/kv/docs/DESIGN.md),
[Diff replay an FSM change](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/diff-replay.md)
and [Upgrade an application](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/upgrade-an-application.md).
