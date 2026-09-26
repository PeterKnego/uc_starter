#!/usr/bin/env bash
# remote-client.sh ARGS… — the app's client, run on host $CLOUD_CLIENT_HOST
# (default 0) over SSH: the client does not build for macOS, and on a host it
# reaches the gateways as a real client would. demo.sh uses it via UC_CLIENT.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
need_inventory
cmd="$(printf '%q ' "/usr/local/bin/$APP_NAME" "$@")"
hssh "${CLOUD_CLIENT_HOST:-0}" "$cmd"
