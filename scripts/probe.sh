# shellcheck shell=bash
# probe.sh — the one write and the one read the Part-2 drills make against
# YOUR app: scripts/snapshot-drill.sh (Step 10) writes a value, kills a
# service and reads it back; scripts/upgrade-drill.sh (Step 12) writes one
# with the OLD client before the pin and reads it back with the new one after.
# Sourced by both drills (after lib.sh); never run on its own.
# TODO(app): rewrite the three functions below for your commands (keep their names and arguments).
#
#   probe_write CLIENT TOKEN   make one write through CLIENT (a path to a build
#                              of your client binary); exit non-zero on failure
#   probe_read CLIENT TOKEN    read it back linearizably and print the one line
#                              the client prints
#   probe_expect TOKEN         print the line probe_read must print after
#                              probe_write of the same TOKEN
#
# TOKEN is a fresh short string ([a-z0-9-], at most 24 characters) that no
# earlier probe used, so pick a write whose read-back depends on TOKEN alone —
# a new key, a new account, a new item — never on what was there before.
# The gateways to use are in $GW (lib.sh's gateways_csv by default).
: "${GW:=$(gateways_csv)}"

probe_write() { "$1" --gateways "$GW" put "probe-$2" "v-$2" >/dev/null; }
probe_read() { "$1" --gateways "$GW" get "probe-$2" --linearizable; }
probe_expect() { printf 'value="v-%s"\n' "$1"; }
