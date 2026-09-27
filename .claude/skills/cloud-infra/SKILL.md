---
name: cloud-infra
description: Use when the developer asks to deploy, test, bench, check, log, redeploy or tear down the app on cloud hosts — "put it on the cloud", "test my app on infra", "bench it", "check infra status", "why did node 2 fail", "destroy the cluster".
---

# cloud-infra

Every command here costs money or touches a live cluster. AGENTS.md hard rule 9:
say what you will run and its effect, wait for a yes in the conversation, then
run it. A permission prompt is not the yes.

## Map the request

| they say | run | pre-flight to state |
|---|---|---|
| deploy / put it on the cloud (no cluster yet) | `make cloud-up` | cloud, region, instance type ×3, ttl_hours (from `cloud-infra/terraform.tfvars`); "creates 3 billable hosts" |
| what would cloud-up change? / after editing `terraform.tfvars` | `make cloud-plan` | "read-only: shows what `cloud-up` would create, change or destroy" |
| deploy my change (cluster up) | `make cloud-deploy` | cloud, region, instance type ×3, ttl_hours (from `cloud-infra/terraform.tfvars`); "rebuilds and restarts the service one host at a time; refuses an FSM_VERSION or UC change" |
| test it on the cloud / on infra | `make cloud-test` (none yet: `make cloud-oneshot`) | "demo, MTU check, stops the leader's node briefly" |
| bench / load it | `make cloud-bench DURATION=10 INFLIGHT=32` | "10 s of writes from a follower host" |
| status / is it up / what's it costing | `make cloud-status` | "read-only" |
| logs / why did X fail | `make cloud-logs HOST=<0-2> PROC=node\|service\|gateway` | "read-only" |
| tear down / destroy | `make cloud-destroy` | "destroys the 3 hosts and their disks; the cluster's data is gone" |

`make cloud-up` on a cluster that already exists: first `make cloud-plan`
(after a yes) and quote its summary in the pre-flight — "changes the firewall"
or "destroys and replaces node1". `cloud-up` refuses a plan that destroys or
replaces a host unless `REPLACE=1`; offer `make cloud-up REPLACE=1` only after
saying the replaced hosts come back empty (a clean cluster: `cloud-destroy`,
then `cloud-up`). On a completely deployed, running cluster `cloud-up` leaves
the code alone ("the cluster is already running — … code changes go through
make cloud-deploy"); offer `make cloud-deploy` for their latest change. A
`cloud-up` that failed part-way resumes when run again, once its cause is fixed.

No `cloud-infra/terraform.tfvars` yet: walk them through `cloud-infra/README.md`
(credentials in `.env`, `cp example.tfvars terraform.tfvars`) before offering
`cloud-up`. `make -C cloud-infra cloud-env-show` checks credentials without
printing them (it asks too: it matches `*make*cloud-*`).

## Long runs

`cloud-up`, `cloud-oneshot`, `cloud-deploy`, `cloud-test` and `cloud-bench`
take minutes (a cold build, then Terraform and Ansible). Run them in the
background and follow the output, or with the longest command timeout — never
the default short one. If a run was interrupted or timed out, say so plainly,
then offer `make cloud-status` (after a yes) to see what exists, and offer
`make cloud-destroy`: hosts may be up and billing, and it works from Terraform
state even where `cloud-status` finds no inventory yet. `cloud-oneshot`
destroys on Ctrl-C, TERM or HUP, but not when it is killed outright.

## After

- After `cloud-test` or `cloud-bench`: offer `make cloud-destroy`.
- If `cloud-status` shows `WARNING: up <h>h, past ttl_hours=<n> — the hosts
  bill until make cloud-destroy`, lead with it.
- `cloud-test` printing `PASS — not recorded for make next: <reason>` means
  the cluster runs older code: offer `make cloud-deploy` (after a yes), then
  `make cloud-test` again.

## When something fails

1. Read the refusal: preflight, Terraform guards and the scripts name their fix.
   An unreachable host says to update `allow_ssh_cidr`/`allow_client_cidr` in
   `cloud-infra/terraform.tfvars` and re-run `make cloud-up` — the developer's
   public IP likely changed.
2. `make cloud-status` (after a yes): which node is down, who leads.
3. `make cloud-logs HOST=<n> PROC=<proc>` for the failed process; match the
   message against `docs/troubleshooting.md`.
4. Never retry `cloud-up` blindly and never edit `.secrets/` or the inventory by
   hand. An "FSM" refusal from `cloud-deploy` means destroy + up (disposable) or
   the pinned upgrade (Step 12) — never a pin without rule 5's go-ahead.
