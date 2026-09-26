#!/usr/bin/env bash
# deploy.sh [--restart] — build the bundle for these hosts and deploy it:
# install + keys + nodes, wait for a serving leader, services, gateways, check.
# --restart (cloud-deploy): restart services one host at a time.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
set -e
need_inventory
restart=false; [ "${1:-}" = --restart ] && restart=true
echo "== bundle for $ARCH hosts"
bundle="$(HOSTS="$(private_csv)" GATEWAYS="$(public_csv)" ARCH="$ARCH" "$PROJECT_DIR/scripts/package.sh" | head -1)"
[ -f "$PROJECT_DIR/$bundle" ] || die "package.sh did not produce a bundle"
dir="$(basename "$bundle" .tar.gz)"
mkdir -p "$SECRETS" && chmod 700 "$SECRETS"
echo "== install, keys, nodes"
(cd "$CI_DIR/ansible" && ANSIBLE_CONFIG="$CI_DIR/ansible/ansible.cfg" ansible-playbook -i "$INV_YML" deploy.yml \
  -e "app_name=$APP_NAME app_id=$APP_ID bundle=$PROJECT_DIR/$bundle bundle_dir=$dir bundle_arch=$ARCH secrets_dir=$SECRETS")
echo "== waiting for a serving leader"
l="$("$S/wait-leader.sh" 60)"; echo "   node$l is the serving leader"
echo "== services, then gateways"
(cd "$CI_DIR/ansible" && ANSIBLE_CONFIG="$CI_DIR/ansible/ansible.cfg" ansible-playbook -i "$INV_YML" serve.yml \
  -e "app_name=$APP_NAME restart=$restart")
echo "== check"
"$S/check.sh"
code_hash >"$SECRETS/deployed-code-hash"
echo
echo "deployed. From a machine in allow_client_cidr (Linux client):"
echo "  $APP_NAME --gateways $(public_members) <command>"
echo "The hosts bill until: make cloud-destroy"
