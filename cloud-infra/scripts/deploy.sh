#!/usr/bin/env bash
# deploy.sh [--restart] — build the bundle for these hosts and deploy it:
# install + keys + nodes, wait for a serving leader, services, gateways, check.
# --restart (cloud-deploy): restart services one host at a time.
# Without --restart (cloud-up): a cluster that already answers is left alone —
# make cloud-up only re-applies infrastructure (the firewall); code changes
# go through make cloud-deploy (fsm-guard.sh first).
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
set -e
need_inventory
restart=false; [ "${1:-}" = --restart ] && restart=true

if ! $restart; then
  hssh 0 true   # dies with the CIDR hint first if node0 is unreachable
  if hssh 0 "sudo uc2ctl status --instance-dir $INSTANCE_DIR --app-id $APP_ID >/dev/null 2>&1"; then
    echo "the cluster is already running — infrastructure (firewall) is updated; code changes go through make cloud-deploy"
    exit 0
  fi
fi

# Captured before package.sh runs: an edit made to src/ while this script is
# building/installing must not be stamped as the code the cluster now runs.
hash="$(code_hash)"
echo "== bundle for $ARCH hosts"
bundle="$(HOSTS="$(private_csv)" GATEWAYS="$(public_csv)" ARCH="$ARCH" "$PROJECT_DIR/scripts/package.sh" | head -1)"
[ -f "$PROJECT_DIR/$bundle" ] || die "package.sh did not produce a bundle"
dir="$(basename "$bundle" .tar.gz)"
mkdir -p "$SECRETS" && chmod 700 "$SECRETS"
echo "== install, keys, nodes"
deploy_json="$(jq -nc --arg app_name "$APP_NAME" --arg app_id "$APP_ID" --arg bundle "$PROJECT_DIR/$bundle" \
  --arg bundle_dir "$dir" --arg bundle_arch "$ARCH" --arg secrets_dir "$SECRETS" \
  '{app_name:$app_name,app_id:$app_id,bundle:$bundle,bundle_dir:$bundle_dir,bundle_arch:$bundle_arch,secrets_dir:$secrets_dir}')"
(cd "$CI_DIR/ansible" && ANSIBLE_CONFIG="$CI_DIR/ansible/ansible.cfg" ansible-playbook -i "$INV_YML" deploy.yml -e "$deploy_json")
echo "== waiting for a serving leader"
l="$("$S/wait-leader.sh" 60)"; echo "   node$l is the serving leader"
echo "== services, then gateways"
serve_json="$(jq -nc --arg app_name "$APP_NAME" --argjson restart "$restart" '{app_name:$app_name,restart:$restart}')"
(cd "$CI_DIR/ansible" && ANSIBLE_CONFIG="$CI_DIR/ansible/ansible.cfg" ansible-playbook -i "$INV_YML" serve.yml -e "$serve_json")
echo "== check"
CLOUD_CLIENT_HOST=$(( (l + 1) % 3 )) "$S/check.sh"
echo "$hash" >"$SECRETS/deployed-code-hash"
echo
echo "deployed. From a machine in allow_client_cidr (Linux client):"
echo "  $APP_NAME --gateways $(public_members) <command>"
echo "The hosts bill until: make cloud-destroy"
