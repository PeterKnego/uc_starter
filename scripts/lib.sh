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
gateways_csv() { echo "127.0.0.1:$(GW_PORT 0),127.0.0.1:$(GW_PORT 1),127.0.0.1:$(GW_PORT 2)"; }
# cargo may be configured with a shared target dir, so ask it where release
# binaries land rather than assuming ./target.
app_bin_dir() {
  local t; t="$(cargo metadata --format-version=1 --no-deps 2>/dev/null | sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p')"
  echo "${t:-$PROJECT_DIR/target}/release"
}
die() { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; exit 3; }
require_linux() {
  [ "$(uname -s)" = Linux ] || die "ultima_cluster nodes run on Linux only (this is $(uname -s)). Open this project in its devcontainer — see README.md § Devcontainer."
}
tree_hash() { # paths… → 16 hex chars over file names + contents
  local p; for p in "$@"; do [ -e "$p" ] && find "$p" -type f -not -path '*/target/*' -print0; done \
    | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -c1-16
}
code_hash()            { tree_hash src Cargo.toml Cargo.lock; }
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
