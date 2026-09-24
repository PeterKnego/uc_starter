#!/usr/bin/env bash
# uc-upgrade.sh VERSION — move this project's ultima_cluster pin to another
# release: UC_VERSION, the four exact Cargo.toml pins (uc_service, uc_remote,
# uc_protocol, uc_diffreplay), Cargo.lock, and every upstream doc link that
# names the old release (`blob/v<old>/…`, `releases/download/v<old>…`),
# anywhere in the project. Does NOT touch a doc's own historical prose (e.g.
# "written by UC 2.11 or 2.12", a quoted real error string) — those name a
# specific past release, not "whatever this project is pinned to", and
# rewriting them would make the doc quote something ultima_cluster never
# says. See docs/how-to/upgrade-uc.md.
#
# In the raw template repo (Cargo.toml still has liquid placeholders) the
# `cargo update` step is skipped; the crates.io check still runs. A failure
# at any step restores every file this run touched.
#
# UC_UPGRADE_SKIP_INDEX=1 skips the crates.io existence/yanked check AND the
# `cargo update` step (both need the real registry, so a synthetic version
# used only to prove this script moves every pin — as
# template-tests/uc-upgrade.sh does — can't reach either).
#
# UC_UPGRADE_INDEX_URL overrides the sparse-index URL this script reads for
# the existence/yanked check (default:
# https://index.crates.io/uc/_s/uc_service). TEST-ONLY: lets
# template-tests/uc-upgrade.sh point at a local fixture file (a `file://…`
# URL) to prove the yanked-version refusal without the network or a real
# yanked ultima_cluster release.
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
INDEX_URL="${UC_UPGRADE_INDEX_URL:-https://index.crates.io/uc/_s/uc_service}"
if [ "$SKIP" != 1 ]; then
  echo "uc-upgrade: checking crates.io for uc_service $NEW ..."
  BODY="$(curl -fsA 'uc-starter (uc-upgrade.sh)' "$INDEX_URL" 2>/dev/null)" \
    || die "could not reach the crates.io sparse index for uc_service ($INDEX_URL) — check network, or set UC_UPGRADE_SKIP_INDEX=1 to skip this check"
  # The sparse index keeps yanked releases (one JSON object per line), so a
  # plain substring match on "vers" would happily accept a yanked one.
  FOUND=""
  if command -v jq >/dev/null 2>&1; then
    FOUND="$(printf '%s\n' "$BODY" | jq -r --arg v "$NEW" 'select(.vers == $v and .yanked == false) | .vers' | head -1)"
  elif command -v python3 >/dev/null 2>&1; then
    FOUND="$(printf '%s\n' "$BODY" | python3 -c '
import json, sys
v = sys.argv[1]
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("vers") == v and d.get("yanked") is False:
        print(v)
        break
' "$NEW")"
  else
    # Last resort: the line naming this version, checked for "yanked":false
    # on that SAME line (each index entry is exactly one line of JSON).
    LINE="$(printf '%s\n' "$BODY" | grep "\"vers\":\"${NEW}\"" | head -1)"
    if [ -n "$LINE" ] && printf '%s' "$LINE" | grep -q '"yanked":false'; then
      FOUND="$NEW"
    fi
  fi
  if [ -z "$FOUND" ]; then
    if printf '%s\n' "$BODY" | grep -q "\"vers\":\"${NEW}\".*\"yanked\":true\|\"yanked\":true.*\"vers\":\"${NEW}\""; then
      die "uc_service $NEW is YANKED on crates.io — refusing to move UC_VERSION to a yanked release"
    fi
    die "uc_service $NEW is not on crates.io — refusing to move UC_VERSION (typo? not published yet?)"
  fi
else
  echo "uc-upgrade: UC_UPGRADE_SKIP_INDEX=1 — skipping the crates.io check and cargo update"
fi

# ---------------------------------------------------------------- plan
# Everything is checked and computed BEFORE the first file changes, and every
# file this run touches is saved first: a failure at any point (including
# `cargo update`) restores them all, so a refused upgrade never leaves a
# half-moved project behind.

# sed pattern metacharacters in a version string are only ever literal dots.
esc() { printf '%s' "$1" | sed 's/\./\\./g'; }
OLD_RE="$(esc "$OLD")"

# The raw template (this script run in the uc_starter repo itself, as the UC
# release procedure does) has a liquid `name = "{{project-name}}"` that cargo
# cannot parse, so it has no Cargo.lock to update: skip that step there.
TEMPLATE=0; [ -f Cargo.toml ] && grep -q '{{' Cargo.toml && TEMPLATE=1
UPDATE=0
if [ "$SKIP" != 1 ] && [ -f Cargo.toml ] && [ $TEMPLATE = 0 ]; then
  command -v cargo >/dev/null 2>&1 || die "cargo not found — Cargo.lock must move with the pins"
  UPDATE=1
fi
[ $TEMPLATE = 1 ] && echo "uc-upgrade: raw template (Cargo.toml has liquid placeholders) — skipping cargo update"

# Doc links: ANY file in the project (README, WHAT-NEXT.md, .claude/**, an
# example TOML's comment, …) — excluding build/scratch trees a generated
# project may already have, and the template's own template-tests/, whose
# records quote what was true on the day they were written. `grep -I` skips
# binaries by content, not by extension, so this is safe to run over the
# whole tree rather than guessing every file type a link could live in.
LINK_FILES=()
while IFS= read -r -d '' f; do
  grep -Iq "blob/v${OLD_RE}/\|releases/download/v${OLD_RE}" "$f" 2>/dev/null && LINK_FILES+=("$f")
done < <(
  find . \( -path './target' -o -path './.git' -o -path './.uc' -o -path './dist' -o -path './template-tests' \) -prune -o \
       -type f -print0
)
TOUCH=(UC_VERSION ${LINK_FILES[@]+"${LINK_FILES[@]}"})
[ -f Cargo.toml ] && TOUCH+=(Cargo.toml)
[ -f Cargo.lock ] && TOUCH+=(Cargo.lock)

mkdir -p "$PROJECT_DIR/.uc"; BK="$(mktemp -d "$PROJECT_DIR/.uc/uc-upgrade-backup.XXXXXX")" || die "cannot create a backup directory"
for f in "${TOUCH[@]}"; do
  if ! { mkdir -p "$BK/$(dirname "$f")" && cp -p "$f" "$BK/$f"; }; then rm -rf "$BK"; die "cannot back up $f — nothing was changed"; fi
done
LOCK_WAS=0; [ -f Cargo.lock ] && LOCK_WAS=1
restore() {
  local f
  for f in "${TOUCH[@]}"; do cp -p "$BK/$f" "$f"; done
  [ $LOCK_WAS = 1 ] || rm -f Cargo.lock
  rm -rf "$BK"
}
fail_restore() { restore; die "$1 — every file was restored; nothing changed"; }

# ---------------------------------------------------------------- apply
echo "$NEW" > UC_VERSION || fail_restore "cannot write UC_VERSION"

# The four exact pins: `"=<old>"` appears nowhere else in Cargo.toml (every
# other dependency is a bare or caret version).
if [ -f Cargo.toml ]; then
  sed -i "s/\"=${OLD_RE}\"/\"=${NEW}\"/g" Cargo.toml || fail_restore "cannot rewrite Cargo.toml"
fi

for f in ${LINK_FILES[@]+"${LINK_FILES[@]}"}; do
  sed -i "s#blob/v${OLD_RE}/#blob/v${NEW}/#g; s#releases/download/v${OLD_RE}#releases/download/v${NEW}#g" "$f" \
    || fail_restore "cannot rewrite links in $f"
done
echo "uc-upgrade: rewrote upstream links in ${#LINK_FILES[@]} file(s)"

if [ $UPDATE = 1 ]; then
  echo "uc-upgrade: cargo update -p uc_service -p uc_remote -p uc_protocol -p uc_diffreplay"
  cargo update -p uc_service -p uc_remote -p uc_protocol -p uc_diffreplay 2>&1 \
    || fail_restore "cargo update failed"
fi
rm -rf "$BK"

cat <<EOF

ultima_cluster: $OLD -> $NEW

Read before you rebuild:
  release notes  https://github.com/PeterKnego/ultima_cluster/blob/v${NEW}/RELEASES.md
  upgrade guide  https://github.com/PeterKnego/ultima_cluster/blob/v${NEW}/docs/how-to/upgrade-a-cluster.md
  this project's own steps  docs/how-to/upgrade-uc.md
EOF
