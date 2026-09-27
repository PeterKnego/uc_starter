#!/usr/bin/env bash
# test.sh — the cloud proof: your demo through the public gateways, 1408-byte
# payloads across the private network, and a real host failover. Records the
# `cloud` stamp (TUTORIAL.md Step 14) when the cluster runs your current code.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
require_make
need_inventory
hssh 0 true   # dies with the CIDR hint first if node0 is unreachable
record=1; why="$(stamp_decision)" || record=0
leader="$("$S/wait-leader.sh" 30)" || exit 3
f=$(( (leader + 1) % 3 ))
export UC_GATEWAYS; UC_GATEWAYS="$(public_members)"
export GW="$UC_GATEWAYS" UC_CLIENT="$S/remote-client.sh" CLOUD_CLIENT_HOST="$f" UC_NO_STAMP=1
echo "== demo: your scripts/demo.sh, client on node$f, through the public gateways"
"$PROJECT_DIR/scripts/demo.sh" || die "demo failed on the cloud cluster — make cloud-logs HOST=$f PROC=gateway"
echo "== 1408-byte payloads between private addresses, don't-fragment"
for i in 0 1 2; do for j in 0 1 2; do
  [ "$i" = "$j" ] && continue
  hssh "$i" "ping -M do -s 1408 -c 2 -W 2 $(priv "$j") >/dev/null" \
    || die "node$i → node$j: a 1408-byte payload does not cross the private network unfragmented (docs/how-to/deploy.md § What you need)"
done; done
echo "   ok"
# shellcheck source=../../scripts/probe.sh
. "$PROJECT_DIR/scripts/probe.sh"
tok="cloud-$(date +%s)"
echo "== failover: stop node$leader's node (the leader)"
hssh "$leader" "sudo systemctl stop uc2-node" || die "could not stop uc2-node on node$leader — nothing was tested"
# From here the leader's node is stopped on a cluster that bills by the hour:
# every path below — success, a failed write, or Ctrl-C — must bring it back.
restart_leader() { hssh "$leader" "sudo systemctl start uc2-node && sleep 2 && sudo systemctl start uc2-service@$APP_NAME-service uc2-gateway"; }
trap 'restart_leader || true' EXIT INT TERM
ok=0; for _ in 1 2 3; do probe_write "$UC_CLIENT" "$tok" && { ok=1; break; }; sleep 2; done
if [ $ok = 0 ]; then
  restart_leader || true
  die "no write succeeded with node$leader down — make cloud-status"
fi
echo "   a write succeeded with node$leader down"
echo "== bring node$leader back"
restart_leader || die "could not restart node$leader — make cloud-status, make cloud-logs HOST=$leader PROC=node"
ok=0; for _ in $(seq 1 30); do
  hssh "$leader" "curl -fsS -o /dev/null http://$(priv "$leader"):$(METRICS_PORT "$leader")/readyz 2>/dev/null" && { ok=1; break; }
  sleep 2
done
[ $ok = 1 ] || die "node$leader is not ready 60s after restart — make cloud-logs HOST=$leader PROC=node"
got="$(probe_read "$UC_CLIENT" "$tok")"
[ "$got" = "$(probe_expect "$tok")" ] || die "after the failover the probe reads '$got', want '$(probe_expect "$tok")'"
echo "   node$leader is back; the write made while it was down reads back"
trap - EXIT INT TERM
# The code may have changed while this test ran; the stamp is for the code
# the cluster is proven to run right now, not the code at the start.
if [ $record = 1 ]; then why="$(stamp_decision)" || record=0; fi
if [ $record = 1 ]; then UC_NO_STAMP=0 "$PROJECT_DIR/scripts/stamp.sh" cloud
else echo "PASS — not recorded for make next: $why"; fi
echo "The hosts bill until: make cloud-destroy"
