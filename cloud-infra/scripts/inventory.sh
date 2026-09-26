#!/usr/bin/env bash
# inventory.sh — terraform output → inventory/hosts.yml (ansible) + hosts.env (scripts).
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
require_make
set -e
json="$(terraform -chdir="$CI_DIR/terraform" output -json)"
user="$(echo "$json" | jq -r .ssh_user.value)"
key="$(ssh_key_file)"
{
  echo "all:"
  echo "  vars:"
  echo "    ansible_user: $user"
  echo "    ansible_ssh_private_key_file: $key"
  echo "    ansible_ssh_common_args: '-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$SECRETS/known_hosts'"
  echo "  children:"
  echo "    cluster:"
  echo "      hosts:"
  echo "$json" | jq -r '.nodes.value | to_entries[] |
    "        \(.value.name):\n          ansible_host: \(.value.public_ip)\n          private_ip: \(.value.private_ip)\n          node_id: \"\(.key)\""'
} >"$INV_YML"
{
  echo "CLOUD=$(echo "$json" | jq -r .cloud.value)"
  echo "REGION=$(echo "$json" | jq -r .region.value)"
  echo "INSTANCE_TYPE=$(echo "$json" | jq -r .instance_type.value)"
  echo "ARCH=$(echo "$json" | jq -r .arch.value)"
  echo "TTL_HOURS=$(echo "$json" | jq -r .ttl_hours.value)"
  echo "SSH_USER=$user"
  echo "SSH_KEY=$key"
  echo "$json" | jq -r '.nodes.value | to_entries[] | "NODE\(.key)_PUBLIC=\(.value.public_ip)\nNODE\(.key)_PRIVATE=\(.value.private_ip)"'
} >"$INV_ENV"
echo "wrote cloud-infra/inventory/hosts.yml and hosts.env"
