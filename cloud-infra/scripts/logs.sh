#!/usr/bin/env bash
# logs.sh HOST PROC [LINES=40] — journal tail of node|service|gateway on host 0-2.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
require_make
h="${1:-}"; p="${2:-}"; n="${3:-40}"
case "$h" in 0|1|2) ;; *) die "usage: make cloud-logs HOST=0|1|2 PROC=node|service|gateway [LINES=40]" ;; esac
case "$p" in
  node) u=uc2-node ;; service) u="uc2-service@$APP_NAME-service" ;; gateway) u=uc2-gateway ;;
  *) die "usage: make cloud-logs HOST=0|1|2 PROC=node|service|gateway [LINES=40]" ;;
esac
case "$n" in *[!0-9]*|'') die "LINES must be a number" ;; esac
need_inventory
hssh "$h" "sudo journalctl -u $u -n $n --no-pager"
