#!/usr/bin/env bash
# uc-upgrade.sh VERSION — move this project's ultima_cluster pin to another
# release: UC_VERSION, the four exact Cargo.toml pins (uc_service, uc_remote,
# uc_protocol, uc_diffreplay), Cargo.lock, and every upstream doc link that
# names the old release (`blob/v<old>/…`, `releases/download/v<old>…`) in
# *.md files and .claude/**. Does NOT touch a doc's own historical prose
# (e.g. "written by UC 2.11 or 2.12", a quoted real error string) — those
# name a specific past release, not "whatever this project is pinned to",
# and rewriting them would make the doc quote something ultima_cluster never
# says. See docs/how-to/upgrade-uc.md.
#
# UC_UPGRADE_SKIP_INDEX=1 skips the crates.io existence check AND the
# `cargo update` step (both need the real registry, so a synthetic version
# used only to prove this script moves every pin — as
# template-tests/uc-upgrade.sh does — can't reach either).
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
NEW="${1:-}"
[ -n "$NEW" ] || die "usage: uc-upgrade.sh VERSION (e.g. make uc-upgrade VERSION=2.14.0)"
case "$NEW" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) die "'$NEW' doesn't look like a release version (X.Y.Z)" ;;
esac

OLD="$(cat UC_VERSION)"
if [ "$OLD" = "$NEW" ]; then
  echo "uc-upgrade: already pinned to $NEW — nothing to move (still checking doc links)"
fi

SKIP="${UC_UPGRADE_SKIP_INDEX:-0}"
if [ "$SKIP" != 1 ]; then
  echo "uc-upgrade: checking crates.io for uc_service $NEW ..."
  BODY="$(curl -fsA 'uc-starter (uc-upgrade.sh)' https://index.crates.io/uc/_s/uc_service 2>/dev/null)" \
    || die "could not reach crates.io's sparse index for uc_service — check network, or set UC_UPGRADE_SKIP_INDEX=1 to skip this check"
  echo "$BODY" | grep -q "\"vers\":\"$NEW\"" \
    || die "uc_service $NEW is not on crates.io — refusing to move UC_VERSION (typo? not published yet?)"
else
  echo "uc-upgrade: UC_UPGRADE_SKIP_INDEX=1 — skipping the crates.io check and cargo update"
fi

# sed pattern metacharacters in a version string are only ever literal dots.
esc() { printf '%s' "$1" | sed 's/\./\\./g'; }
OLD_RE="$(esc "$OLD")"

echo "$NEW" > UC_VERSION

# The four exact pins: `"=<old>"` appears nowhere else in Cargo.toml (every
# other dependency is a bare or caret version).
if [ -f Cargo.toml ]; then
  sed -i "s/\"=${OLD_RE}\"/\"=${NEW}\"/g" Cargo.toml
fi

# Doc links: *.md anywhere in the project, plus everything under .claude/,
# excluding build/scratch trees a generated project may already have.
mapfile -t DOC_FILES < <(
  find . \( -path './target' -o -path './.git' -o -path './.uc' -o -path './dist' \) -prune -o \
       \( -name '*.md' -o -path './.claude/*' \) -type f -print
)
CHANGED=0
for f in "${DOC_FILES[@]}"; do
  if grep -q "blob/v${OLD_RE}/\|releases/download/v${OLD_RE}" "$f" 2>/dev/null; then
    sed -i "s#blob/v${OLD_RE}/#blob/v${NEW}/#g; s#releases/download/v${OLD_RE}#releases/download/v${NEW}#g" "$f"
    CHANGED=$((CHANGED + 1))
  fi
done
echo "uc-upgrade: rewrote upstream links in $CHANGED file(s)"

if [ "$SKIP" != 1 ] && [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  echo "uc-upgrade: cargo update -p uc_service -p uc_remote -p uc_protocol -p uc_diffreplay"
  cargo update -p uc_service -p uc_remote -p uc_protocol -p uc_diffreplay 2>&1 \
    || die "cargo update failed — Cargo.toml and UC_VERSION now name $NEW but Cargo.lock does not match; fix and re-run, or revert with git"
fi

cat <<EOF

ultima_cluster: $OLD -> $NEW

Read before you rebuild:
  release notes  https://github.com/PeterKnego/ultima_cluster/blob/v${NEW}/RELEASES.md
  upgrade guide  https://github.com/PeterKnego/ultima_cluster/blob/v${NEW}/docs/how-to/upgrade-a-cluster.md
  this project's own steps  docs/how-to/upgrade-uc.md
EOF
