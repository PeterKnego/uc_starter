# shellcheck shell=bash
# common.sh — sourced by every cloud-infra script. bash 3.2-safe (macOS).
# shellcheck disable=SC2034  # variables here are used by the scripts that source it
# shellcheck source=../../scripts/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
OFF=0   # the cloud never uses the local cluster's port offset
CI_DIR="$PROJECT_DIR/cloud-infra"
S="$CI_DIR/scripts"
TFV="$CI_DIR/terraform.tfvars"
INV_YML="$CI_DIR/inventory/hosts.yml"
INV_ENV="$CI_DIR/inventory/hosts.env"
SECRETS="$CI_DIR/.secrets"
INSTANCE_DIR="/srv/uc2/$APP_NAME"

tfvar() { # NAME → its value in terraform.tfvars (quotes and comments stripped)
  [ -f "$TFV" ] || return 0
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"#]*)\"?.*/\1/p" "$TFV" | head -1 | sed -E 's/[[:space:]]+$//'
}
ssh_key_file() {
  local k; k="$(tfvar ssh_private_key_file)"; k="${k:-~/.ssh/id_ed25519}"
  # shellcheck disable=SC2088  # matching a literal leading "~/", not expanding one
  case "$k" in "~/"*) k="$HOME/${k#\~/}" ;; esac
  echo "$k"
}
ver_ge() { # A B → 0 when version A >= B
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$2" ]
}
need_inventory() {
  [ -f "$INV_ENV" ] || die "no cloud cluster here (cloud-infra/inventory/hosts.env is missing) — make cloud-up creates one"
  # shellcheck disable=SC1090
  . "$INV_ENV"
}
pub()  { eval "echo \"\$NODE$1_PUBLIC\""; }
priv() { eval "echo \"\$NODE$1_PRIVATE\""; }
public_csv()  { echo "$(pub 0),$(pub 1),$(pub 2)"; }
private_csv() { echo "$(priv 0),$(priv 1),$(priv 2)"; }
public_members() { echo "$(pub 0):$(GW_PORT 0),$(pub 1):$(GW_PORT 1),$(pub 2):$(GW_PORT 2)"; }
cidr_hint() {
  echo "cannot reach host $1 ($(pub "$1")) over SSH. If your public IP changed since cloud-up, set allow_ssh_cidr (and allow_client_cidr) in cloud-infra/terraform.tfvars to your new IP/32 (curl -s https://checkip.amazonaws.com) and re-run make cloud-up — it only updates the firewall."
}
hssh() { # N CMD… → run CMD on host N; SSH failure (exit 255) dies with the CIDR hint
  local n="$1" rc; shift
  mkdir -p "$SECRETS"
  ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$SECRETS/known_hosts" -o ConnectTimeout="${CLOUD_SSH_TIMEOUT:-10}" \
      -o LogLevel=ERROR "$SSH_USER@$(pub "$n")" "$@"
  rc=$?
  [ $rc = 255 ] && die "$(cidr_hint "$n")"
  return $rc
}
