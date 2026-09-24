#!/usr/bin/env bash
# tree_hash contract: the same tree hashes the same under any locale, editor
# droppings do not count, and a one-byte source edit does.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HOME/scratch/uc_starter-gen/tree-hash"
rm -rf "$OUT"; mkdir -p "$OUT"
fail() { echo "FAIL: $*" >&2; exit 1; }

"$HERE/gen.sh" "$OUT" >/dev/null 2>&1
P="$OUT/demo-app"
mkdir -p "$P/src/x"
echo 'pub fn b() {}' >"$P/src/x/B.rs"
echo 'pub fn a() {}' >"$P/src/x/a.rs"

hash_in() { # locale → code_hash of $P; a fresh project has no Cargo.lock yet,
  # which must not make code_hash fail (callers run under set -e)
  (export LC_ALL="$1"; cd "$P"; . scripts/lib.sh; set -e; code_hash) || fail "code_hash exited nonzero (LC_ALL=$1)"
}

utf8="$(locale -a 2>/dev/null | grep -iE '^en_US\.utf-?8$' | head -1 || true)"
if [ -z "$utf8" ]; then
  echo "note: no en_US UTF-8 locale installed; comparing C against C.UTF-8"
  utf8="$(locale -a 2>/dev/null | grep -iE '^C\.utf-?8$' | head -1 || true)"
fi
base="$(hash_in C)"
if [ -n "$utf8" ]; then
  other="$(hash_in "$utf8")"
  [ "$base" = "$other" ] || fail "code_hash differs by locale: C=$base $utf8=$other"
else
  echo "note: no UTF-8 locale at all; locale comparison skipped"
fi

for junk in src/.x.swp src/x/a.rs~ 'src/.#a.rs'; do
  echo junk >"$P/$junk"
  [ "$(hash_in C)" = "$base" ] || fail "editor dropping $junk changed code_hash"
  rm -f "$P/$junk"
done

echo 'pub fn a() {} ' >"$P/src/x/a.rs"
[ "$(hash_in C)" != "$base" ] || fail "a one-byte edit in src/ did not change code_hash"
echo "tree-hash: PASS"
