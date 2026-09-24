#!/usr/bin/env bash
# progress.sh (done|skip) ID — record a step the repo cannot show, or a skip.
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
verb="${1:-}"; id="${2:-}"
case "$verb" in done|skip) ;; *) die "usage: progress.sh (done|skip) STEP" ;; esac
[ -n "$id" ] || die "which step? e.g. make $verb STEP=concepts ('scripts/next.sh --list' lists ids)"
scripts/next.sh --list | grep -qx "$id" || [ "$id" = part1 ] || die "unknown step '$id' — ids: $(scripts/next.sh --list | tr '\n' ' ')"
echo "$verb $id $(date +%F)" >> "$PROGRESS"
echo "recorded: $verb $id"
