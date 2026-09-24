#!/usr/bin/env bash
# stamp.sh ID — record that ID's proof ran, against the current code.
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
[ $# -eq 1 ] || die "usage: stamp.sh ID"
case "$1" in
  check) write_stamp check "$(code_hash_with_tests)" ;;
  skeleton|snapshots|observe|upgrade-check|upgrade-drill) write_stamp "$1" any ;;
  *) write_stamp "$1" "$(code_hash)" ;;
esac
