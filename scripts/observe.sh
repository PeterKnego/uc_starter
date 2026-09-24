#!/usr/bin/env bash
# observe.sh — what an operator watches: health, readiness, the key series
# (WHAT-NEXT.md, Step 11).
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
# Names checked against a live 2.13.0 /metrics scrape. uc_service_* is your
# state machine's own family (applied, lag, attached, …).
SERIES=(uc2_agent_alive uc2_is_leader uc2_commit_bytes uc2_fsm_lag_bytes uc2_service_version uc_service_attached uc_service_lag_bytes)
leaders=0
for n in 0 1 2; do
  m="http://127.0.0.1:$(METRICS_PORT "$n")"
  curl -fs -o /dev/null "$m/healthz" || die "node $n /healthz is not 200"
  curl -fs -o /dev/null "$m/readyz"  || die "node $n /readyz is not 200 (can_serve false, or its service is not heartbeating?)"
  body="$(curl -fs "$m/metrics")" || die "node $n /metrics unreachable"
  for s in "${SERIES[@]}"; do grep -qE "^$s(\{| )" <<<"$body" || die "node $n exports no $s"; done
  l="$(grep -E '^uc2_is_leader(\{[^}]*\})? ' <<<"$body" | awk '{print $2}' | head -1)"
  [ "${l%%.*}" = 1 ] && leaders=$((leaders+1))
  echo "node $n: healthz ok, readyz ok, ${#SERIES[@]} key series present, is_leader=${l:-?}"
done
[ $leaders = 1 ] || die "expected exactly one uc2_is_leader=1, saw $leaders"
echo "alert rules to load into Prometheus: .uc/packaging/prometheus/uc2-alerts.yml"
"$PROJECT_DIR/scripts/stamp.sh" observe
echo PASS
