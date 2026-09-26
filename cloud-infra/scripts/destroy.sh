#!/usr/bin/env bash
# destroy.sh — tear the hosts down (from terraform state, whatever the deploy
# got to) and clear this cluster's local files. No state, no terraform call.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
require_make
STATE="$CI_DIR/terraform/terraform.tfstate"
clear_local() { rm -f "$INV_YML" "$INV_ENV" "$SECRETS/admin.key" "$SECRETS/known_hosts" "$SECRETS/deployed-code-hash"; }
if [ -f "$STATE" ]; then
  command -v jq >/dev/null || die "jq not found — cloud-infra/README.md § Control machine has the install lines (nothing was destroyed and nothing was removed)"
  n="$(jq '.resources | length' "$STATE")" || die "cannot read cloud-infra/terraform/terraform.tfstate — nothing was destroyed and nothing was removed; fix the file or run terraform -chdir=cloud-infra/terraform destroy yourself"
else
  n=0
fi
if [ "$n" = 0 ]; then
  clear_local; echo "nothing to destroy (no hosts in terraform state)"; exit 0
fi
[ -f "$TFV" ] || die "terraform state has hosts but cloud-infra/terraform.tfvars is gone — restore it, then make cloud-destroy"
terraform -chdir="$CI_DIR/terraform" init -input=false >/dev/null
terraform -chdir="$CI_DIR/terraform" destroy -auto-approve -input=false -var-file="$TFV" || exit 1
clear_local
echo "destroyed"
