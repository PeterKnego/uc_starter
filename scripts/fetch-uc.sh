#!/usr/bin/env bash
# fetch-uc.sh — download the ultima_cluster release named in UC_VERSION into
# .uc/bin (binaries) and .uc/packaging (systemd units, alert rules), verified.
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
set -e
require_linux
case "$(uname -m)" in x86_64) ARCH=x86_64 ;; aarch64|arm64) ARCH=aarch64 ;; *) die "no ultima_cluster release for $(uname -m)" ;; esac
NAME="uc2-${UC_VERSION}-${ARCH}-unknown-linux-gnu"
URL="https://github.com/PeterKnego/ultima_cluster/releases/download/v${UC_VERSION}"
if [ -x "$UC_BIN/uc2-node" ] && "$UC_BIN/uc2-node" --version 2>/dev/null | grep -q "$UC_VERSION"; then
  echo "ultima_cluster $UC_VERSION already in .uc/bin"; exit 0
fi
DL="$PROJECT_DIR/.uc/download"; rm -rf "$DL"; mkdir -p "$DL"
echo "downloading $NAME.tar.gz"
curl -fsSL -o "$DL/$NAME.tar.gz" "$URL/$NAME.tar.gz"
curl -fsSL -o "$DL/SHA256SUMS" "$URL/SHA256SUMS"
(cd "$DL" && sha256sum -c SHA256SUMS --ignore-missing) || die "checksum mismatch for $NAME.tar.gz — refusing to install"
if command -v cosign >/dev/null; then
  curl -fsSL -o "$DL/$NAME.tar.gz.sigstore.json" "$URL/$NAME.tar.gz.sigstore.json"
  # The identity flags are the release page's own (ultima_cluster release.yml).
  cosign verify-blob --bundle "$DL/$NAME.tar.gz.sigstore.json" \
    --certificate-identity-regexp 'https://github.com/PeterKnego/ultima_cluster/.github/workflows/release.yml@refs/tags/v.*' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com "$DL/$NAME.tar.gz" >/dev/null 2>&1 \
    || die "cosign signature verification failed for $NAME.tar.gz"
  echo "signature verified (cosign)"
else
  echo "cosign not installed: checksum verified, signature not checked"
fi
tar xzf "$DL/$NAME.tar.gz" -C "$DL"
rm -rf "$UC_BIN" "$PROJECT_DIR/.uc/packaging"; mkdir -p "$UC_BIN"
cp "$DL/$NAME/bin/"* "$UC_BIN/"
cp -r "$DL/$NAME/packaging" "$PROJECT_DIR/.uc/packaging"
"$UC_BIN/uc2-node" --version
