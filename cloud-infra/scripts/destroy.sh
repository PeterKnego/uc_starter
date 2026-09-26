#!/usr/bin/env bash
# destroy.sh — tear the hosts down (from terraform state, whatever the deploy
# got to) and clear this cluster's local files. No state, no terraform call.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
STATE="$CI_DIR/terraform/terraform.tfstate"
clear_local() { rm -f "$INV_YML" "$INV_ENV" "$SECRETS/admin.key" "$SECRETS/known_hosts" "$SECRETS/deployed-code-hash"; }
if [ ! -f "$STATE" ] || [ "$(jq '.resources | length' "$STATE" 2>/dev/null || echo 0)" = 0 ]; then
  clear_local; echo "nothing to destroy (no hosts in terraform state)"; exit 0
fi
[ -f "$TFV" ] || die "terraform state has hosts but cloud-infra/terraform.tfvars is gone — restore it, then make cloud-destroy"
terraform -chdir="$CI_DIR/terraform" destroy -auto-approve -input=false -var-file="$TFV" || exit 1
clear_local
echo "destroyed"
