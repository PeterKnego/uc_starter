# Add a query

A query only reads. It is answered from one replica's state and never enters
the log. This guide adds a `Len` query (how many keys the registry holds) as
the example. Replace it with yours.

## 1. Append the variants — `src/commands.rs`

Add the query at the **end** of `Query`, and its answer at the end of
`QueryResponse`:

```rust
pub enum Query {
    Get { key: String },
    Len,                 // new
}

pub enum QueryResponse {
    Value(Option<String>),
    Len(u64),            // new
}
```

Queries are not stored, but the client and the service still have to agree
on the encoding, and the variant index is the tag. Append; never reorder.

## 2. Answer it — `query` in `src/state.rs`

```rust
Query::Len => QueryResponse::Len(self.state.entries.len() as u64),
```

`query` gets no `ApplyCtx`: there is no position, time or id generator in a
read. It must not change state, and it must not panic.

## 3. Give the client a subcommand — `src/bin/client.rs`

Model it on `get`: a `Sub` variant with a `--linearizable` flag.

```rust
/// How many keys the registry holds.
Len {
    /// Go through the cluster's read barrier (see `get`).
    #[arg(long)]
    linearizable: bool,
},
```

In `run`, the new subcommand builds no `Command` (`Sub::Len { .. } => None`)
and dispatches to a query. The skeleton's `query` function builds
`Query::Get` itself; generalise it to take the `Query`, and replace its
`let QueryResponse::Value(v) = answer;` with a `match`, which the new
`QueryResponse` variant now requires:

```rust
match answer {
    QueryResponse::Value(v) => println!("value={}", opt(&v)),
    QueryResponse::Len(n) => println!("len={n}"),
}
```

`--linearizable` maps to `Consistency::Linearizable` (the read barrier: sees
every write acknowledged before it); without it the client asks for
`Consistency::Snapshot`, served from whichever replica answered, possibly a
little behind. See [concepts § Commands and queries](../concepts.md#commands-and-queries).

## 4. Test it — `tests/state.rs`

Apply a few commands to an `Fsm`, then assert the query's answer, including
the empty case. If the answer iterates state, check it comes back in a stable
order (a `BTreeMap` iterates sorted; a `HashMap` does not).

Optionally add a demo line to `scripts/demo.sh`:

```bash
expect "len"   'len='   len --linearizable
```

## Run it

```bash
make check restart-services demo
```

**Restart the services before you use the new subcommand.** The old service
cannot decode a query variant it does not know. The typed tier treats that as
corruption: the apply agent fail-stops with `corrupt query frame (fail-stop)`
and the service exits for a restart. `make restart-services` rebuilds and
restarts every service first.

## Is a new query an upgrade?

A query changes no state and nothing in the log, so replaying the log is
unaffected. But every service must understand it before any client sends it:
on a cluster you care about, roll the new service out to every node before
you ship the client. If you change what an *existing* query returns, treat it
as a behaviour change: bump `FSM_VERSION` and follow `TUTORIAL.md` Step 12.

Upstream: [the state-machine contract](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md)
and [Linearizable read path](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/read-path.md).
