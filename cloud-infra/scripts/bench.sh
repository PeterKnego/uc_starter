#!/usr/bin/env bash
# bench.sh [DURATION=10] [INFLIGHT=32] — the client's bench on a follower
# host, through the public gateways (in-cloud latency).
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
need_inventory
hssh 0 true   # dies with the CIDR hint first if node0 is unreachable
d="${1:-10}"; n="${2:-32}"
case "$d$n" in *[!0-9]*|'') die "usage: make cloud-bench DURATION=<secs> INFLIGHT=<n>" ;; esac
leader="$("$S/wait-leader.sh" 30)"; f=$(( (leader + 1) % 3 ))
echo "bench: ${d}s, $n in flight, client on node$f, gateways $(public_members) ($CLOUD $REGION $INSTANCE_TYPE ×3)"
CLOUD_CLIENT_HOST="$f" "$S/remote-client.sh" --gateways "$(public_members)" bench --duration-secs "$d" --inflight "$n"
echo "The hosts bill until: make cloud-destroy"
