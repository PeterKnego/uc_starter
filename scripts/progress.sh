#!/usr/bin/env bash
# progress.sh (done|skip) ID — record a step the repo cannot show, or a skip.
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
verb="${1:-}"; id="${2:-}"
case "$verb" in done|skip) ;; *) die "usage: progress.sh (done|skip) STEP" ;; esac
[ -n "$id" ] || die "which step? e.g. make $verb STEP=concepts ('scripts/next.sh --list' lists ids)"
# part1 is a machine-local stamp (write_stamp part1, scripts/next.sh), never
# a step a person records — only real step ids are accepted here.
# Captured, not piped: under pipefail, `next.sh --list | grep -q` fails at
# random when grep exits on its match before next.sh has written the rest.
ids="$(scripts/next.sh --list)"
grep -qx -- "$id" <<<"$ids" || die "unknown step '$id' — ids: $(tr '\n' ' ' <<<"$ids")"
# `done` is only for the two steps the repo cannot show; every other step is
# proven by its own check (TUTORIAL.md, "Done when"), so recording it by hand
# would be a claim nothing checked. A deliberate skip is fine for any step.
if [ "$verb" = "done" ]; then
  case "$id" in concepts|deploy) ;; *) die "'$id' is proven by its own check, not recorded by hand — see its \"Done when\" in TUTORIAL.md (make done takes only concepts or deploy; make skip STEP=$id skips it deliberately)" ;; esac
fi
echo "$verb $id $(date +%F)" >> "$PROGRESS"
echo "recorded: $verb $id"
