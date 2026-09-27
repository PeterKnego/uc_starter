#!/usr/bin/env bash
# package.sh — a deploy bundle for three hosts (TUTORIAL.md, Steps 13–14):
#   make package HOSTS=ip0,ip1,ip2 [GATEWAYS=pub0,pub1,pub2]
# writes dist/<app>-<version>-<arch>.tar.gz: the binaries, the systemd units,
# and a node.toml + gateway.toml per host (hosts/<HOSTS[i]>/). See
# docs/how-to/deploy.md.
#   GATEWAYS  the addresses clients reach the gateways on (a cloud's public IPs).
#             Given, each gateway listens on 0.0.0.0 and [[members]] names these.
#   ARCH      the hosts' CPU, x86_64|aarch64 (default: this machine's). When it
#             is not this machine's, or this is not Linux, the app is
#             cross-built with cargo-zigbuild and UC comes from .uc/dist/ARCH.
# --build-only: the build steps alone (no HOSTS needed), so make cloud-up can
# fail on a compile error before it creates hosts; the bundle run then
# finds everything in cargo's cache.
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
set -e   # a failed cp/sed/tar must not leave a bundle that looks complete
OFF=0   # a deploy never uses the local cluster's port offset
parse_three() { # NAME VALUE → PARSED=(three distinct host addresses), or die
  local name="$1" h
  [ -n "$2" ] || die "$name needs exactly three addresses: make package $name=ip0,ip1,ip2"
  PARSED=(); IFS=, read -r -a PARSED <<<"$2"
  [ "${#PARSED[@]}" = 3 ] || die "$name needs exactly three addresses: make package $name=ip0,ip1,ip2"
  for h in "${PARSED[@]}"; do
    case "$h" in
      *:*) die "$name: '$h' looks like an IPv6 address — this bundle supports IPv4 addresses (or host names) only" ;;
      ''|0.0.0.0|*[!0-9A-Za-z.-]*) die "$name: '$h' is not a host address (each node binds exactly its own address, never 0.0.0.0)" ;;
    esac
  done
  [ "$(printf '%s\n' "${PARSED[@]}" | sort -u | wc -l | tr -d ' ')" = 3 ] || die "$name must be three different machines"
}
build_only=false; [ "${1:-}" = --build-only ] && build_only=true
if ! $build_only; then
  parse_three HOSTS "${HOSTS:-}"; H=("${PARSED[@]}")
  G=(); if [ -n "${GATEWAYS:-}" ]; then parse_three GATEWAYS "$GATEWAYS"; G=("${PARSED[@]}"); fi
fi
mach="$(uname -m)"; [ "$mach" = arm64 ] && mach=aarch64
ARCH="${ARCH:-$mach}"
case "$ARCH" in x86_64|aarch64) ;; *) die "ARCH must be x86_64 or aarch64 (got '$ARCH')" ;; esac
[ -f docs/how-to/deploy.md ] || die "docs/how-to/deploy.md is missing"
if [ "$(uname -s)" = Linux ] && [ "$ARCH" = "$mach" ]; then
  for b in uc2-node uc2ctl uc2-gateway; do [ -x "$UC_BIN/$b" ] || die "$UC_BIN/$b is missing — run make bins"; done
  UCB="$UC_BIN"; UCP="$PROJECT_DIR/.uc/packaging"
  cargo build --release -q || exit 1
  BIN="$(app_bin_dir)"
else
  command -v cargo-zigbuild >/dev/null || die "building for $ARCH Linux on $(uname -s) $mach needs cargo-zigbuild and zig: cargo install cargo-zigbuild --locked, then brew install zig (macOS) or pip3 install ziglang (cloud-infra/README.md § Control machine)"
  command -v zig >/dev/null || python3 -c 'import ziglang' 2>/dev/null || die "zig not found: brew install zig (macOS) or pip3 install ziglang"
  triple="$ARCH-unknown-linux-gnu"
  rustup target list --installed | grep -qx "$triple" || rustup target add "$triple"
  "$PROJECT_DIR/scripts/fetch-uc.sh" --arch "$ARCH" >&2   # stdout's first line is the bundle path
  UCB="$PROJECT_DIR/.uc/dist/$ARCH/bin"; UCP="$PROJECT_DIR/.uc/dist/$ARCH/packaging"
  cargo zigbuild --release -q --target "$triple.$GLIBC_FLOOR" || exit 1
  BIN="$(app_target_dir)/$triple/release"
fi
if $build_only; then echo "built for $ARCH Linux: $BIN"; exit 0; fi
ver="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)"
D="dist/$APP_NAME-$ver-$ARCH"; rm -rf "$D" "$D.tar.gz"; mkdir -p "$D/bin" "$D/systemd" "$D/hosts"
cp "$UCB"/uc2-node "$UCB"/uc2ctl "$UCB"/uc2-gateway "$BIN/$APP_NAME-service" "$BIN/$APP_NAME" "$D/bin/"
case "$ARCH" in x86_64) want='x86-64' ;; aarch64) want='aarch64' ;; esac
for f in "$D"/bin/*; do
  file -b "$f" | grep -q "ELF 64-bit.*$want" || die "$(basename "$f") is not a Linux $ARCH binary: $(file -b "$f")"
done
cp "$UCP"/systemd/uc2-node.service "$UCP"/systemd/uc2-gateway.service "$D/systemd/"
INSTANCE="/srv/uc2/$APP_NAME"
grep -q '^ExecStart=' "$UCP"/systemd/uc2-service@.service || die "uc2-service@.service has no ExecStart line to rewrite"
sed "s|^ExecStart=.*|ExecStart=/usr/local/bin/%i --instance-dir $INSTANCE --app-id $APP_ID|" \
  "$UCP"/systemd/uc2-service@.service >"$D/systemd/uc2-service@.service"
for i in 0 1 2; do
  mkdir -p "$D/hosts/${H[$i]}"
  render_node_toml deploy "$i" "$INSTANCE" /etc/uc2/admin/admin.key "${H[@]}" >"$D/hosts/${H[$i]}/node.toml"
  render_gateway_toml "$i" "$INSTANCE" "${H[@]}" ${G[@]+"${G[@]}"} >"$D/hosts/${H[$i]}/gateway.toml"
done
cp docs/how-to/deploy.md "$D/DEPLOY.md"
COPYFILE_DISABLE=1 tar czf "$D.tar.gz" -C dist "$(basename "$D")"   # no macOS ._ files
echo "$D.tar.gz"
echo "before installing: create /etc/uc2/node.key, /etc/uc2/allowlist.toml ([crypto]) and /etc/uc2/admin/admin.key ([admin]) on each host — DEPLOY.md says how"
