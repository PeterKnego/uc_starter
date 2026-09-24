#!/usr/bin/env bash
# cluster.sh — a three-node cluster of this app on this host, from the
# ultima_cluster release binaries in .uc/bin (make bins) plus this project's
# <app>-service. Modelled on the release's packaging/quickstart-local.sh (via
# ultima_cluster's examples/kv/scripts/kvcluster.sh), but it leaves the
# cluster running and lets you stop/start/kill individual processes.
#
#   scripts/cluster.sh up [--fresh]        start 3 nodes + 3 services + 3 gateways
#   scripts/cluster.sh down                stop everything (services, gateways, then nodes)
#   scripts/cluster.sh status              uc2ctl status on every node
#   scripts/cluster.sh leader              print the serving leader's id
#   scripts/cluster.sh wait-leader [secs]  wait for (and print) a serving leader
#   scripts/cluster.sh stop|kill|start <node|service|gateway> N
#   scripts/cluster.sh restart-services    restart every service (after a rebuild)
#   scripts/cluster.sh snapshot            uc2ctl snapshot against the leader (prints instant=<P>)
#   scripts/cluster.sh snapshot-show N     uc2ctl snapshot show on node N
#   scripts/cluster.sh ctl N <args...>     uc2ctl <args> against node N
#   scripts/cluster.sh metrics N           node N's /metrics
#   scripts/cluster.sh gateways            the gateway list for --gateways
#   scripts/cluster.sh root                the cluster's state directory
#
# Environment:
#   UC_ROOT         cluster state (default $HOME/.uc-starter/<app>). NOT /tmp:
#                   nodes refuse RAM-backed filesystems.
#   UC_PORT_OFFSET  added to every port below (default 0; the smoke test uses 10)
#   UC_SNAPSHOT_INTERVAL  genesis snapshot_interval_bytes (default 0 = on demand)
#   UC_CONFIRM_PIN  must be "yes" for `ctl N upgrade pin …` — a one-way door
#
# Ports (BASE_PORT from uc-app.env): nodes UDP BASE..BASE+2, gateways TCP
# BASE+100..+102, metrics TCP BASE+200..+202.

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
set -euo pipefail

APP="$APP_ID"
SERVICE_BIN="$(app_bin_dir)/$APP_NAME-service"
LOGS="$ROOT/logs"
PIDS="$ROOT/pids"

say() { printf '%s\n' "$*"; }
tcp_open() { (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null; }
udp_bound() { # port → is some socket bound to it (any address)?
    if command -v ss >/dev/null 2>&1; then
        ss -Huln | awk '{print $4}' | grep -qE ":$1\$"
    else
        # No ss (a slim container): /proc/net/udp{,6} list the local port in hex.
        local hex; hex="$(printf '%04X' "$1")"
        cat /proc/net/udp /proc/net/udp6 2>/dev/null | awk 'NR>1 {print $2}' | grep -qi ":$hex\$"
    fi
}

need_bins() {
    for b in uc2-node uc2ctl uc2-gateway; do
        [ -x "$UC_BIN/$b" ] || die "$UC_BIN/$b is missing — run make bins"
    done
    [ -x "$SERVICE_BIN" ] || die "$SERVICE_BIN missing — run make build"
}

# ---------------------------------------------------------------- process bookkeeping

pidfile() { echo "$PIDS/$1$2.pid"; }   # kind, index

alive() { # kind N
    local f; f="$(pidfile "$1" "$2")"
    [ -f "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null
}

spawn() { # kind N cmd...
    local kind="$1" n="$2"; shift 2
    if alive "$kind" "$n"; then say "   $kind$n already running (pid $(cat "$(pidfile "$kind" "$n")"))"; return 0; fi
    mkdir -p "$LOGS" "$PIDS"
    # Append to the log: a restarted process's history stays in one file.
    setsid "$@" >>"$LOGS/$kind$n.log" 2>&1 </dev/null &
    echo $! >"$(pidfile "$kind" "$n")"
    say "   started $kind$n (pid $!)"
}

stop_one() { # kind N [signal]
    local kind="$1" n="$2" sig="${3:-TERM}" f pid
    f="$(pidfile "$kind" "$n")"
    [ -f "$f" ] || return 0
    pid="$(cat "$f")"
    if kill -0 "$pid" 2>/dev/null; then
        kill "-$sig" "$pid" 2>/dev/null || true
        for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
        if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; sleep 0.2; fi
    fi
    rm -f "$f"
    say "   stopped $kind$n (pid $pid, SIG$sig)"
}

start_node()    { spawn node "$1" "$UC_BIN/uc2-node" --config "$ROOT/n$1/node.toml"; }
start_service() { spawn service "$1" "$SERVICE_BIN" --instance-dir "$ROOT/n$1" --app-id "$APP"; }
start_gateway() { spawn gateway "$1" "$UC_BIN/uc2-gateway" --config "$ROOT/gw$1.toml"; }

ctl() { local n="$1"; shift; "$UC_BIN/uc2ctl" "$@" --instance-dir "$ROOT/n$n" --app-id "$APP"; }

leader() {
    # A SIGKILLed node leaves its control page frozen with the leader and
    # CAN_SERVE bits still set (run-a-gateway.md, "When the node underneath
    # dies"), and `uc2ctl status` reads that page verbatim — so check the
    # process is alive before believing the page.
    local i out
    for i in 0 1 2; do
        alive node "$i" || continue
        if out=$(ctl "$i" status 2>/dev/null); then
            case "$out" in *"leader=true can_serve=true"*) echo "$i"; return 0 ;; esac
        fi
    done
    return 1
}

wait_leader() {
    local deadline=$(( $(date +%s) + ${1:-30} )) l
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if l=$(leader); then echo "$l"; return 0; fi
        sleep 0.2
    done
    return 1
}

# ---------------------------------------------------------------- config

write_config() {
    mkdir -p "$ROOT" "$LOGS" "$PIDS"
    : >"$ROOT/.uc-starter"
    for i in 0 1 2; do mkdir -p "$ROOT/n$i"; done
    if [ ! -f "$ROOT/admin.key" ]; then
        "$UC_BIN/uc2ctl" gen-admin-key "$ROOT/admin.key" >"$LOGS/gen-admin-key.log" 2>&1 || die "gen-admin-key failed: see $LOGS/gen-admin-key.log"
    fi
    local i
    for i in 0 1 2; do
        render_node_toml local "$i" "$ROOT/n$i" "$ROOT/admin.key" 127.0.0.1 127.0.0.1 127.0.0.1 >"$ROOT/n$i/node.toml"
        render_gateway_toml "$i" "$ROOT/n$i" 127.0.0.1 127.0.0.1 127.0.0.1 >"$ROOT/gw$i.toml"
    done
}

# ---------------------------------------------------------------- commands

port_guard() {
    # Every band, before anything is written or started: a port held by
    # something that is not this cluster's own live process is a collision
    # (another cluster, another app, a stale process).
    local i p
    for i in 0 1 2; do
        p="$(NODE_PORT "$i")"
        if udp_bound "$p" && ! alive node "$i"; then die "port $p is in use — another cluster? set UC_PORT_OFFSET or run make down"; fi
        p="$(GW_PORT "$i")"
        if tcp_open 127.0.0.1 "$p" && ! alive gateway "$i"; then die "port $p is in use — another cluster? set UC_PORT_OFFSET or run make down"; fi
        p="$(METRICS_PORT "$i")"
        if tcp_open 127.0.0.1 "$p" && ! alive node "$i"; then die "port $p is in use — another cluster? set UC_PORT_OFFSET or run make down"; fi
    done
}

cmd_up() {
    local fresh=0
    [ "${1:-}" = "--fresh" ] && fresh=1
    require_linux
    need_bins
    case "$ROOT" in /tmp|/tmp/*|/dev/shm|/dev/shm/*) die "UC_ROOT=$ROOT is RAM-backed; nodes refuse it" ;; esac
    if [ -d "$ROOT" ] && [ -n "$(ls -A "$ROOT" 2>/dev/null)" ] && [ ! -e "$ROOT/.uc-starter" ]; then
        die "$ROOT is not empty and was not created by this script"
    fi
    if [ "$fresh" = 1 ]; then
        cmd_down >/dev/null 2>&1 || true
        rm -rf "$ROOT/n0" "$ROOT/n1" "$ROOT/n2" "$LOGS" "$PIDS"
    fi
    port_guard
    write_config
    say "$APP_NAME cluster: root=$ROOT"
    say "1. nodes"
    for i in 0 1 2; do start_node "$i"; done
    say "   waiting for a serving leader"
    local l; l=$(wait_leader 30) || { say "no serving leader after 30s"; tail -n 20 "$LOGS"/node*.log; exit 1; }
    say "   node $l is the serving leader"
    say "2. services"
    for i in 0 1 2; do start_service "$i"; done
    say "3. gateways"
    for i in 0 1 2; do start_gateway "$i"; done
    local deadline=$(( $(date +%s) + 30 ))
    for i in 0 1 2; do
        until tcp_open 127.0.0.1 "$(GW_PORT "$i")"; do
            [ "$(date +%s)" -lt "$deadline" ] || { say "gateway $i not listening"; tail -n 20 "$LOGS/gateway$i.log"; exit 1; }
            sleep 0.2
        done
    done
    say "   gateways: $(gateways_csv)"
    say "up. try: make demo"
}

cmd_down() {
    # Reader before writer: services and gateways first, then nodes.
    for i in 0 1 2; do stop_one service "$i"; stop_one gateway "$i"; done
    for i in 0 1 2; do stop_one node "$i"; done
}

cmd_status() {
    local i
    for i in 0 1 2; do
        say "--- node $i ($(alive node "$i" && echo running || echo down); service $(alive service "$i" && echo running || echo down); gateway $(alive gateway "$i" && echo running || echo down))"
        ctl "$i" status 2>&1 || true
    done
}

cmd_ctl() {
    local n="$1"; shift
    case " $* " in
        *" upgrade pin "*|*" upgrade "*" pin "*)
            [ "${UC_CONFIRM_PIN:-}" = yes ] || die "refusing 'upgrade pin' without UC_CONFIRM_PIN=yes — a pin is a one-way door (WHAT-NEXT.md, Step 12)" ;;
    esac
    ctl "$n" "$@"
}

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }

case "${1:-}" in
    up) shift; cmd_up "$@" ;;
    down) cmd_down ;;
    status) cmd_status ;;
    leader) leader ;;
    wait-leader) wait_leader "${2:-30}" ;;
    # Stopping or killing a node also takes its gateway down, emulating the
    # packaged units' BindsTo=uc2-node.service: a gateway left running over a
    # dead node keeps accepting writes into a ring nobody drains and answers
    # UNKNOWN after request_timeout (documented residual window). Pass
    # UC_NO_BINDSTO=1 to reproduce that window deliberately.
    stop|kill)
        [ $# -eq 3 ] || usage
        sig=TERM; [ "$1" = kill ] && sig=KILL
        stop_one "$2" "$3" "$sig"
        if [ "$2" = node ] && [ -z "${UC_NO_BINDSTO:-}" ]; then stop_one gateway "$3" "$sig"; fi ;;
    start)
        [ $# -eq 3 ] || usage
        need_bins
        case "$2" in node) start_node "$3" ;; service) start_service "$3" ;; gateway) start_gateway "$3" ;; *) die "start what? node|service|gateway" ;; esac ;;
    restart-services) need_bins; for i in 0 1 2; do stop_one service "$i"; start_service "$i"; done ;;
    snapshot) l=$(leader) || die "no serving leader — run make up"; ctl "$l" snapshot --admin-key "$ROOT/admin.key" ;;
    snapshot-show) [ $# -eq 2 ] || usage; ctl "$2" snapshot show ;;
    ctl) [ $# -ge 3 ] || usage; shift; cmd_ctl "$@" ;;
    metrics) [ $# -eq 2 ] || usage; curl -sf "http://127.0.0.1:$(METRICS_PORT "$2")/metrics" ;;
    gateways) gateways_csv ;;
    root) echo "$ROOT" ;;
    *) usage ;;
esac
