#!/usr/bin/env bash
# check.sh — /readyz on every node (from itself, on its private metrics
# address) and one probe through the public gateways.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
need_inventory
for i in 0 1 2; do
  ok=0
  for _ in $(seq 1 30); do
    hssh "$i" "curl -fsS -o /dev/null http://$(priv "$i"):$(METRICS_PORT "$i")/readyz" 2>/dev/null && { ok=1; break; }
    sleep 2
  done
  [ $ok = 1 ] || die "node$i: /readyz not 200 after 60s — make cloud-logs HOST=$i PROC=node"
  echo "   node$i /readyz 200"
done
export UC_GATEWAYS; UC_GATEWAYS="$(public_members)"
export GW="$UC_GATEWAYS"
# shellcheck source=../../scripts/probe.sh
. "$PROJECT_DIR/scripts/probe.sh"
tok="check-$(date +%s)"
CLOUD_CLIENT_HOST=1 probe_write "$S/remote-client.sh" "$tok" || die "probe write through the public gateways failed — make cloud-logs HOST=1 PROC=gateway"
got="$(CLOUD_CLIENT_HOST=1 probe_read "$S/remote-client.sh" "$tok")"
[ "$got" = "$(probe_expect "$tok")" ] || die "probe read '$got', want '$(probe_expect "$tok")'"
echo "   probe through the public gateways: $got"
