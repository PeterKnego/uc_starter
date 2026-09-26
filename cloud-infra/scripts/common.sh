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
  mkdir -p "$SECRETS" && chmod 700 "$SECRETS"
  ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$SECRETS/known_hosts" -o ConnectTimeout="${CLOUD_SSH_TIMEOUT:-10}" \
      -o LogLevel=ERROR "$SSH_USER@$(pub "$n")" "$@"
  rc=$?
  [ $rc = 255 ] && die "$(cidr_hint "$n")"
  return $rc
}
# cloud-deploy restarts services one at a time onto the new build. That is
# only a rolling restart when row 0 already runs this FSM_VERSION; anything
# else is an FSM upgrade with no pin (AGENTS.md rule 4) — refuse.
fsm_guard_decide() { # RUNNING SOURCE
  [ -n "$1" ] || die "cannot read the FSM version row 0 runs (uc2ctl status on node0) — make cloud-status, make cloud-logs HOST=0 PROC=node"
  [ "$1" = "$2" ] && return 0
  die "the cluster runs FSM $1 and src/identity.rs says $2: a rolling restart onto a new state machine is an unpinned upgrade (AGENTS.md rule 4). Disposable cluster: make cloud-destroy, then make cloud-up. A cluster you keep: the pinned upgrade (WHAT-NEXT.md Step 12)."
}
# A new UC release is a whole-cluster stop and start (docs/how-to/upgrade-uc.md).
uc_guard_decide() { # "uc2-node <version>" UC_VERSION
  [ -n "$2" ] || die "UC_VERSION is empty — cannot compare against node0. make cloud-destroy, then make cloud-up once UC_VERSION is fixed."
  # Whitespace-padded substring match: $2 must appear as a whole word of $1,
  # never as a bare suffix (a naive *"$2" pattern would accept "12.13.0" for "2.13.0").
  case " $1 " in *" $2 "*) return 0 ;; esac
  die "node0 runs '$1' but UC_VERSION is $2: a UC upgrade is a whole-cluster stop and start — make cloud-destroy, then make cloud-up (or docs/how-to/upgrade-uc.md for a cluster you keep)."
}
# cloud-test proves the code the cluster runs; the stamp is keyed on the
# working tree's code. Record it only when they are the same.
stamp_decision() {
  local f="$SECRETS/deployed-code-hash"
  if [ ! -f "$f" ]; then echo "no record of what the cluster runs — make cloud-deploy, then make cloud-test"; return 1; fi
  if [ "$(cat "$f")" != "$(code_hash)" ]; then echo "your code changed since it was deployed — make cloud-deploy, then make cloud-test"; return 1; fi
}
ttl_note() { # UPTIME_H TTL_H
  [ "$1" -gt "$2" ] && echo "WARNING: up ${1}h, past ttl_hours=$2 — the hosts bill until make cloud-destroy"
  return 0
}
