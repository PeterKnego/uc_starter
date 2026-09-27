# shellcheck shell=bash
# shellcheck disable=SC2034  # variables here are used by the scripts that source it
# Sourced by every script. Paths, ports, stamps, progress.
set -uo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR" || exit 3
# shellcheck disable=SC1091
. ./uc-app.env
UC_VERSION="$(cat UC_VERSION)"
UC_BIN="$PROJECT_DIR/.uc/bin"
ROOT="${UC_ROOT:-$HOME/.uc-starter/$APP_NAME}"
OFF="${UC_PORT_OFFSET:-0}"
NODE_PORT()    { echo $((BASE_PORT + OFF + $1)); }
GW_PORT()      { echo $((BASE_PORT + OFF + 100 + $1)); }
METRICS_PORT() { echo $((BASE_PORT + OFF + 200 + $1)); }
# UC_GATEWAYS overrides the local three (cloud-infra points the demo at the
# cloud's public members with it).
gateways_csv() { echo "${UC_GATEWAYS:-127.0.0.1:$(GW_PORT 0),127.0.0.1:$(GW_PORT 1),127.0.0.1:$(GW_PORT 2)}"; }
# cargo may be configured with a shared target dir, so ask it where binaries
# land rather than assuming ./target.
app_target_dir() {
  local t; t="$(cargo metadata --format-version=1 --no-deps 2>/dev/null | sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p')"
  echo "${t:-$PROJECT_DIR/target}"
}
app_bin_dir() { echo "$(app_target_dir)/release"; }
die() { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; exit 3; }
# macOS has shasum, not sha256sum; both print "<hex>  <name>".
sha256_stdin() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }
verify_sha256() { # SUMS FILE → 0 when FILE's line in SUMS matches its content
  local want got
  want="$(awk -v f="$(basename "$2")" '$2==f || $2=="*"f {print $1}' "$1")"
  got="$(sha256_stdin <"$2" | cut -c1-64)"
  [ -n "$want" ] && [ "$want" = "$got" ]
}
# The oldest glibc a cross-built bundle runs on (Ubuntu 22.04 ships 2.35;
# cloud-infra's hosts run 24.04).
GLIBC_FLOOR=2.35
require_linux() {
  [ "$(uname -s)" = Linux ] || die "ultima_cluster nodes run on Linux only (this is $(uname -s)). Open this project in its devcontainer — see README.md § Devcontainer."
}
# Byte order (LC_ALL=C), so a stamp written in a UTF-8 terminal reads fresh
# from a POSIX-locale shell; editor droppings (vim .*.sw?, emacs *~ and .#*)
# are not code; a missing path (no Cargo.lock yet) is skipped, not an error.
tree_hash() { # paths… → 16 hex chars over file names + contents
  local p f; for p in "$@"; do
    if [ -e "$p" ]; then
      find "$p" -type f -not -path '*/target/*' -not -name '.*.sw?' -not -name '*~' -not -name '.#*' -print0
    fi
  done | LC_ALL=C sort -z | while IFS= read -r -d '' f; do
    printf '%s  %s\n' "$(sha256_stdin <"$f" | cut -c1-64)" "$f"
  done | sha256_stdin | cut -c1-16
}
code_hash()            { tree_hash src Cargo.toml Cargo.lock; }
# What an upgrade-check PASS vouches for: the code, the declaration, the
# corpus it replayed and the old binaries it replayed it through.
upgrade_hash()         { tree_hash src Cargo.toml Cargo.lock upgrade/intent.toml upgrade/corpus upgrade/old; }
code_hash_with_tests() { tree_hash src tests Cargo.toml Cargo.lock; }
STATE_DIR="$PROJECT_DIR/.uc/state"
write_stamp() { [ "${UC_NO_STAMP:-0}" = 1 ] && return 0; mkdir -p "$STATE_DIR"; echo "$2" >"$STATE_DIR/$1.ok"; }
stamp_state() { # id hash → missing|stale|fresh ; hash "any" accepts any content
  local f="$STATE_DIR/$1.ok"
  [ -f "$f" ] || { echo missing; return; }
  [ "$2" = any ] && { echo fresh; return; }
  if [ "$(cat "$f")" = "$2" ]; then echo fresh; else echo stale; fi
}
PROGRESS="$PROJECT_DIR/.uc-progress"
progress_has() { [ -f "$PROGRESS" ] && grep -qE "^(done|skip) $1( |$)" "$PROGRESS"; }
progress_skipped() { [ -f "$PROGRESS" ] && grep -qE "^skip $1( |$)" "$PROGRESS"; }

# ---------------------------------------------------------------- config shape
# One source of truth for node.toml and gateway.toml: scripts/cluster.sh
# renders the local cluster from these, scripts/package.sh the deploy bundle.
#
#   render_node_toml PROFILE ID INSTANCE_DIR ADMIN_KEY HOST0 HOST1 HOST2
#   render_gateway_toml ID INSTANCE_DIR HOST0 HOST1 HOST2 [PUB0 PUB1 PUB2]
#
# With PUB0..2 (a cloud: clients reach the gateways on public addresses that
# are not on the interface on every cloud) the gateway listens on 0.0.0.0 and
# [[members]] names the public addresses — REDIRECT and LEADER_CHANGED send
# clients to them, so they must be the ones clients can reach.
#
# PROFILE is `local` (one host, small journal geometry so purge is visible,
# crypto off, instants on demand) or `deploy` (one node per host, default
# geometry, crypto ON with the key paths docs/how-to/deploy.md sets up, an
# instant every 1 GiB of log). Node ID binds, serves metrics
# and listens (gateway) on HOST<ID>; every [[members]] list names all three.
# Ports come from NODE_PORT / GW_PORT / METRICS_PORT above. Reads APP_ID,
# FSM_NAME and UC_SNAPSHOT_INTERVAL (genesis snapshot_interval_bytes; overrides
# the profile's default).
render_node_toml() {
  local profile="$1" id="$2" dir="$3" admin_key="$4"; shift 4
  local hosts=("$@") i geometry crypto interval
  [ "${#hosts[@]}" = 3 ] || die "render_node_toml: need three hosts"
  case "$profile" in
    local)
      geometry='
# Small geometry so journal purge is observable on a laptop-sized write
# volume: purge drops whole non-active segments, so with 4 MiB segments a few
# MiB of writes after a snapshot is enough to see archive_first_base move.
# (Top-level keys MUST precede [[members]]: after it they parse as a member'"'"'s.)
buffer_bytes = 16777216
journal_segment_bytes = 4194304
'
      crypto='enabled = false'
      interval=0 ;;
    deploy)
      geometry=''
      # Crypto is ON: node traffic crosses a network this file cannot vouch
      # for. The node refuses to start until both files exist, mode 0600 —
      # docs/how-to/deploy.md says how to make them.
      crypto='enabled = true
key_path = "/etc/uc2/node.key"
allowlist_path = "/etc/uc2/allowlist.toml"'
      # A cadence, not on-demand: purge drops the journal only below a
      # complete instant, so without one the log grows until the disk fills.
      interval=1073741824 ;;
    *) die "render_node_toml: profile must be local or deploy" ;;
  esac
  cat <<EOT
id = $id
bind = "${hosts[$id]}:$(NODE_PORT "$id")"
instance_dir = "$dir"
app_id = "$APP_ID"
$geometry
EOT
  for i in 0 1 2; do
    printf '[[members]]\nid = %s\naddr = "%s:%s"\n\n' "$i" "${hosts[$i]}" "$(NODE_PORT "$i")"
  done
  cat <<EOT
# The state machine implements SnapshotStateMachine and the service starts
# with start_with_snapshots(); this is the other half of bounding the log.
[purge]
below_snapshot_slack_bytes = 1048576

[services]
names = ["$FSM_NAME"]

# Genesis seed only: a running cluster changes it with uc2ctl settings apply.
# The leader takes an instant every snapshot_interval_bytes of log; 0 means
# only when an operator commands one (uc2ctl snapshot).
[settings]
snapshot_interval_bytes = ${UC_SNAPSHOT_INTERVAL:-$interval}
snapshot_target = "all"

[log]
level = "info"

# Unauthenticated: keep it on loopback or a private address.
[metrics]
bind = "${hosts[$id]}:$(METRICS_PORT "$id")"

[crypto]
$crypto

[admin]
auth = "hmac"
keys = [{ name = "$(basename "$admin_key" .key)", key_path = "$admin_key" }]
EOT
}

render_gateway_toml() {
  local id="$1" dir="$2"; shift 2
  local hosts=("$@") i listen
  local -a reach
  case "${#hosts[@]}" in
    3) reach=("${hosts[0]}" "${hosts[1]}" "${hosts[2]}"); listen="${hosts[$id]}" ;;
    6) reach=("${hosts[3]}" "${hosts[4]}" "${hosts[5]}"); listen=0.0.0.0 ;;
    *) die "render_gateway_toml: need three hosts, or three hosts and three public addresses" ;;
  esac
  cat <<EOT
[local]
instance_dir = "$dir"
app_id = "$APP_ID"
listen = "$listen:$(GW_PORT "$id")"

EOT
  for i in 0 1 2; do
    printf '[[members]]\nnode_id = %s\ngateway = "%s:%s"\n\n' "$i" "${reach[$i]}" "$(GW_PORT "$i")"
  done
  cat <<'EOT'
[limits]
# The client's exposure window to a node that died under this gateway.
request_timeout_ms = 2000

# The service runs Sessioned<Fsm>: the envelope is what makes a re-sent write
# answer "replayed" instead of applying twice.
[session]
envelope = true
EOT
}

# The FSM version in the source (src/identity.rs) and the one row 0 is
# attached at on node N (`uc2ctl status`'s row line: `row=0 name=… version=1.0.0 …`).
source_version() { sed -nE 's/.*pack_version\(([0-9]+), *([0-9]+), *([0-9]+)\).*/\1.\2.\3/p' src/identity.rs | head -1; }
running_version() { "$PROJECT_DIR/scripts/cluster.sh" ctl "$1" status 2>/dev/null | sed -nE 's/^ *row=0 .* version=([0-9]+\.[0-9]+\.[0-9]+) .*/\1/p' | head -1; }
