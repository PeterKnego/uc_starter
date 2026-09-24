---
name: troubleshoot-cluster
description: Use when the local cluster, a service, a gateway or the client fails — make up/demo/drill errors, a process that exits, NodeBooting, a fail-stop, a decode error, a refused start.
---

# troubleshoot-cluster

Diagnose from evidence: the process status, then the log of the process that
failed, then the named refusal in `docs/troubleshooting.md`.

## Procedure

1. `make status`. Note which processes are down, which node leads
   (`leader=true can_serve=true`), and the commit positions.
2. `scripts/cluster.sh root` prints ROOT. Read the tail of each failed
   process's log: `tail -n 40 "$ROOT/logs/<proc>N.log"`, where `<proc>` is
   `node`, `service` or `gateway` and N is 0, 1 or 2. For a service fail-stop,
   read further up for the first `panicked at` or `fail-stop` line.
3. Match the exact message against the sections of `docs/troubleshooting.md`:
   - `NodeBooting` / "has not joined its cluster yet"
   - "is RAM-backed" / `tmpfs` refusal
   - "port … is in use"
   - "Linux only"
   - checksum / cosign / 404 from `make bins`
   - `ULTSNAP1` / `MistaggedSnapshot`
   - "cnc protocol version mismatch", mixed versions after a UC upgrade
   - "apply agent fail-stopped", `corrupt committed frame (fail-stop)`,
     `corrupt query frame (fail-stop)`
   - "client and service built from different code"
   - "no serving leader after 30s"
4. Quote the matching section's **Fix** to the developer, with the log line
   that matched. If nothing matches, say so, show the log lines, and point to
   the upstream guide:
   `https://github.com/PeterKnego/ultima_cluster/blob/v<UC_VERSION>/docs/how-to/diagnose-a-node.md`.
5. Apply the fix, then re-run the command that failed and show its output.

## Guardrails

- Ask before anything that destroys cluster state: `make up FRESH=1`,
  deleting anything under ROOT, clearing `snapshots/`. Say what is lost.
- A service fail-stop on a committed command recurs on every replay and every
  node: fix the code or the build, never just restart and hope.
- A new command variant reached old services: follow the troubleshooting
  section "A newer client got ahead of the services". On anything but the
  local cluster the recovery is the pinned upgrade — never pin without the
  developer's explicit go-ahead in this conversation.
- Keep ROOT on a real disk; never move it under `/tmp`.
