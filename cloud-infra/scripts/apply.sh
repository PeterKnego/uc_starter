#!/usr/bin/env bash
# apply.sh [--plan] — cloud-up's terraform step: plan, then apply exactly that
# plan. A plan that destroys or replaces any resource (a region, arch or
# ssh_public_key change; a replaced host loses its data and its SSH host key)
# is refused unless REPLACE=1. --plan (make cloud-plan): print the plan and
# what it would destroy; change nothing.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
require_make
set -e
TFDIR="$CI_DIR/terraform"
PLAN="$TFDIR/cloud-up.tfplan"
tf() { terraform -chdir="$TFDIR" "$@"; }
trap 'rm -f "$PLAN"' EXIT
tf init -input=false >/dev/null
tf plan -input=false -out="$PLAN" -var-file="$TFV"
gone="$(tf show -json "$PLAN" | jq -r '.resource_changes[]? | select(.change.actions | index("delete")) | .address')"

if [ "${1:-}" = --plan ]; then
  if [ -n "$gone" ]; then
    printf '\nmake cloud-up would DESTROY or REPLACE (it refuses without REPLACE=1):\n%s\n' "$gone"
  else
    printf '\nmake cloud-up would destroy nothing.\n'
  fi
  exit 0
fi

if [ -n "$gone" ]; then
  [ "${REPLACE:-}" = 1 ] || die "this terraform.tfvars change destroys or replaces:
$gone
A replaced host comes back empty: its log, keys and data are gone. Undo the change (region, arch, instance_type, ssh_public_key), or, if you mean it, make cloud-up REPLACE=1 (for a clean cluster: make cloud-destroy, then make cloud-up)."
  # Replaced hosts get new SSH host keys (Hetzner and GCP keep their IPs), and
  # nothing is deployed on them yet: forget both, so deploy.sh runs in full.
  if [ -f "$INV_ENV" ]; then
    need_inventory
    for i in $(printf '%s\n' "$gone" | sed -nE 's/.*\.node\[([0-9])\]$/\1/p' | sort -u); do
      ssh-keygen -R "$(pub "$i")" -f "$SECRETS/known_hosts" >/dev/null 2>&1 || true
    done
  else
    rm -f "$SECRETS/known_hosts"
  fi
  rm -f "$SECRETS/known_hosts.old" "$SECRETS/deployed-code-hash"
fi
tf apply -input=false "$PLAN"
