#!/usr/bin/env bash
# upgrade-check.sh — diff-replay the corpus through the old build
# (upgrade/old/) and the current one, judged against upgrade/intent.toml
# (WHAT-NEXT.md, Step 12).
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
DR="$PROJECT_DIR/.uc/cargo/bin/uc2-diffreplay"; [ -x "$DR" ] || die "uc2-diffreplay missing — run: make diffreplay"
[ -d upgrade/corpus ] || die "no corpus — run make corpus BEFORE changing the code"
OLD="upgrade/old/$APP_NAME-service"; [ -x "$OLD" ] || die "$OLD missing — run make corpus BEFORE changing the code"
[ -f upgrade/intent.toml ] || die "upgrade/intent.toml missing — copy upgrade/intent.toml.example and declare your change"
cargo build --release -q || exit 1
NEW="$(app_bin_dir)/$APP_NAME-service"
cmp -s "$OLD" "$NEW" && echo "note: the new build is byte-identical to the old one — nothing changed yet"
"$DR" upgrade --corpus upgrade/corpus --old "$OLD" --new "$NEW" \
  --declare upgrade/intent.toml --report upgrade/report.json
rc=$?
if [ $rc = 0 ]; then
  "$PROJECT_DIR/scripts/stamp.sh" upgrade-check
  # What upgrade-drill checks: this PASS was for exactly the code it will pin.
  write_stamp upgrade-check-code "$(upgrade_hash)"
  echo "PASS — every difference is declared and attributed"
else
  rm -f "$STATE_DIR/upgrade-check-code.ok"   # a later FAIL withdraws an earlier PASS
  echo "FAIL — read upgrade/report.json (Undeclared / Unexplained / Absent); the upgrade-fsm skill explains each"
fi
exit $rc
