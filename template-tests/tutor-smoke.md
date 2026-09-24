# Tutor smoke — "what next?" (Task 10, 2026-09-24)

Run in a freshly generated project (`template-tests/gen.sh`, then `git init`,
one commit, `make bins`), with Claude Code 2.1.281:

```bash
claude -p "what next?" --allowedTools "Bash(scripts/next.sh:*)" --output-format stream-json --verbose < /dev/null
```

`--allowedTools` is needed only because `claude -p` in a never-trusted
directory ignores the project's `permissions.allow` ("Ignoring 14
permissions.allow entries … this workspace has not been trusted"). A first
run without it invoked the `next` skill, was refused `scripts/next.sh`, and
declined to guess the step — the protocol's "never infer the step" held.

## Tool calls, in order

1. `{"skill": "next"}`
2. `{"command": "scripts/next.sh --json", "description": "Compute the current tutorial step"}`
3. `{"command": "awk '/^### Step 2/{p=1} /^### Step 3/{p=0} p' WHAT-NEXT.md", "description": "Show Step 2 section of WHAT-NEXT.md"}`
4. `{"command": "grep -n '^### Step' WHAT-NEXT.md", "description": "Find step headings in WHAT-NEXT.md"}`
5. `{"file_path": "~/scratch/uc_starter-gen/smoke/demo-app/WHAT-NEXT.md", "offset": 55, "limit": 39}`

(Call 1 is the `next` skill; call 3, an `awk` read, needed approval and was
replaced by a `grep` and a `Read`.)

## First reply (verbatim)

You're on **Step 2 of 13: Run the skeleton** (Part 1). I got that by running `scripts/next.sh --json`, which reports `"status":"todo"` and one thing still to do: `run: make up && make demo`.

**Why this step matters.** `make up` followed by `make demo` runs ten processes in four roles:
- **Nodes:** three `uc2-node` daemons pick a leader and handle agreement on command order, copying data to each other, and durable storage.
- **Services:** three copies of your service each attach to one node over shared memory. Each runs its own copy of your state machine and applies the same committed commands in the same order.
- **Gateways:** three `uc2-gateway`s give clients a TCP entry point. A gateway on a follower can redirect a client to the leader.
- **Client:** `make demo` runs the client once per request.

They must start in a fixed order: nodes, then a leader that is ready to serve, then services, then gateways. Since UC 2.13.0, a service can attach only after its node has joined the cluster. Until then the node refuses it with `NodeBooting`, and it waits up to 10 s before exiting. See [the quickstart, § 3](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/QUICKSTART.md#3-what-just-happened) and [the state-machine contract, § Attaching](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/reference/state-machine-contract.md).

The step is done when `make demo` prints `PASS` once on this machine; that first pass records the proof. Nothing has been run for this step yet.

Do you want to do this yourself (I'll guide and review), or shall I do it?

## Result

- Ran `scripts/next.sh --json` before anything else: yes (after loading the `next` skill).
- Taught the step's **Why** with its pinned `v2.13.0` links: yes.
- Asked the guide-or-do question verbatim: yes.

## Edit hook, live

Same project, `claude -p` asked to append
`fn _h() { let _t = std::time::SystemTime::now(); }` to `src/state.rs` with
`--allowedTools Edit Read`. The hook ran (hooks are not gated by workspace
trust), `rustfmt` reformatted the line, and the agent received, and quoted:

```
PostToolUse:Edit hook blocking error from command: ""$CLAUDE_PROJECT_DIR"/.claude/hooks/post-edit.sh": ["$CLAUDE_PROJECT_DIR"/.claude/hooks/post-edit.sh]: Determinism hazard in src/state.rs (apply must give the same result on every replica):
src/state.rs:73: wall clock — use ctx.time_ns
Fix it with the substitute named above. Exempt a line with `// determinism: ok <why>` only if the developer agrees.
```

The turn continued after the exit 2 (the agent went on to read the file and
answer), so the hazard reaches the agent at the edit.
