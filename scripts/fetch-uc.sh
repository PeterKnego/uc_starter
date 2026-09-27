#!/usr/bin/env bash
# fetch-uc.sh — download the ultima_cluster release named in UC_VERSION, verified.
#   fetch-uc.sh                 this machine's binaries into .uc/bin (+ .uc/packaging)
#                               — the local cluster; Linux only
#   fetch-uc.sh --arch A        Linux A (x86_64|aarch64) binaries into .uc/dist/A
#                               — a deploy bundle for hosts of that CPU; any OS
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
set -e
if [ "${1:-}" = --arch ]; then
  case "${2:-}" in x86_64|aarch64) ARCH="$2" ;; *) die "usage: fetch-uc.sh [--arch x86_64|aarch64]" ;; esac
  BIN_DIR="$PROJECT_DIR/.uc/dist/$ARCH/bin"; PKG_DIR="$PROJECT_DIR/.uc/dist/$ARCH/packaging"
  MARK="$PROJECT_DIR/.uc/dist/$ARCH/VERSION"
  if [ -x "$BIN_DIR/uc2-node" ] && [ -f "$MARK" ] && [ "$(cat "$MARK")" = "$UC_VERSION" ]; then
    echo "ultima_cluster $UC_VERSION ($ARCH) already in .uc/dist/$ARCH"; exit 0
  fi
else
  [ $# -eq 0 ] || die "usage: fetch-uc.sh [--arch x86_64|aarch64]"
  require_linux
  case "$(uname -m)" in x86_64) ARCH=x86_64 ;; aarch64|arm64) ARCH=aarch64 ;; *) die "no ultima_cluster release for $(uname -m)" ;; esac
  BIN_DIR="$UC_BIN"; PKG_DIR="$PROJECT_DIR/.uc/packaging"; MARK=""
  if [ -x "$UC_BIN/uc2-node" ] && "$UC_BIN/uc2-node" --version 2>/dev/null | grep -q "$UC_VERSION"; then
    echo "ultima_cluster $UC_VERSION already in .uc/bin"; exit 0
  fi
fi
NAME="uc2-${UC_VERSION}-${ARCH}-unknown-linux-gnu"
URL="https://github.com/PeterKnego/ultima_cluster/releases/download/v${UC_VERSION}"
DL="$PROJECT_DIR/.uc/download"; rm -rf "$DL"; mkdir -p "$DL"
echo "downloading $NAME.tar.gz"
curl -fsSL -o "$DL/$NAME.tar.gz" "$URL/$NAME.tar.gz"
curl -fsSL -o "$DL/SHA256SUMS" "$URL/SHA256SUMS"
verify_sha256 "$DL/SHA256SUMS" "$DL/$NAME.tar.gz" || die "checksum mismatch for $NAME.tar.gz — refusing to install"
if command -v cosign >/dev/null; then
  curl -fsSL -o "$DL/$NAME.tar.gz.sigstore.json" "$URL/$NAME.tar.gz.sigstore.json"
  # The identity flags are the release page's own (ultima_cluster release.yml).
  # stdout is silenced; stderr is kept and shown when verification fails.
  if ! err="$(cosign verify-blob --bundle "$DL/$NAME.tar.gz.sigstore.json" \
    --certificate-identity-regexp 'https://github.com/PeterKnego/ultima_cluster/.github/workflows/release.yml@refs/tags/v.*' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com "$DL/$NAME.tar.gz" 2>&1 >/dev/null)"; then
    printf '%s\n' "$err" >&2
    die "cosign signature verification failed for $NAME.tar.gz (cosign's output above)"
  fi
  echo "signature verified (cosign)"
else
  echo "cosign not installed: checksum verified, signature not checked"
fi
tar xzf "$DL/$NAME.tar.gz" -C "$DL"
rm -rf "$BIN_DIR" "$PKG_DIR"; mkdir -p "$BIN_DIR"
cp "$DL/$NAME/bin/"* "$BIN_DIR/"
cp -r "$DL/$NAME/packaging" "$PKG_DIR"
if [ -n "$MARK" ]; then
  echo "$UC_VERSION" >"$MARK"; echo "ultima_cluster $UC_VERSION ($ARCH) in .uc/dist/$ARCH"
else
  "$UC_BIN/uc2-node" --version
fi
