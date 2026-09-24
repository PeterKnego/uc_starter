#!/usr/bin/env bash
# package.sh — a deploy bundle for three hosts (WHAT-NEXT.md, Step 13):
#   make package HOSTS=ip0,ip1,ip2
# writes dist/<app>-<version>-<arch>.tar.gz: the binaries, the systemd units,
# and a node.toml + gateway.toml per host. See docs/how-to/deploy.md.
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
OFF=0   # a deploy never uses the local cluster's port offset
IFS=, read -r -a H <<<"${HOSTS:-}"
[ "${#H[@]}" = 3 ] || die "HOSTS needs exactly three addresses: make package HOSTS=ip0,ip1,ip2"
for h in "${H[@]}"; do
  case "$h" in ''|0.0.0.0|*[!0-9A-Za-z.:-]*) die "'$h' is not a host address (each node binds exactly its own address, never 0.0.0.0)" ;; esac
done
[ "$(printf '%s\n' "${H[@]}" | sort -u | wc -l)" = 3 ] || die "HOSTS must be three different machines"
for b in uc2-node uc2ctl uc2-gateway; do [ -x "$UC_BIN/$b" ] || die "$UC_BIN/$b is missing — run make bins"; done
[ -f docs/how-to/deploy.md ] || die "docs/how-to/deploy.md is missing"
cargo build --release -q || exit 1
ver="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)"; arch="$(uname -m)"
D="dist/$APP_NAME-$ver-$arch"; rm -rf "$D" "$D.tar.gz"; mkdir -p "$D/bin" "$D/systemd" "$D/hosts"
cp "$UC_BIN"/uc2-node "$UC_BIN"/uc2ctl "$UC_BIN"/uc2-gateway "$(app_bin_dir)/$APP_NAME-service" "$(app_bin_dir)/$APP_NAME" "$D/bin/"
cp .uc/packaging/systemd/uc2-node.service .uc/packaging/systemd/uc2-gateway.service "$D/systemd/"
INSTANCE="/srv/uc2/$APP_NAME"
grep -q '^ExecStart=' .uc/packaging/systemd/uc2-service@.service || die "uc2-service@.service has no ExecStart line to rewrite"
sed "s|^ExecStart=.*|ExecStart=/usr/local/bin/%i --instance-dir $INSTANCE --app-id $APP_ID|" \
  .uc/packaging/systemd/uc2-service@.service >"$D/systemd/uc2-service@.service"
for i in 0 1 2; do
  mkdir -p "$D/hosts/${H[$i]}"
  render_node_toml deploy "$i" "$INSTANCE" /etc/uc2/admin/admin.key "${H[@]}" >"$D/hosts/${H[$i]}/node.toml"
  render_gateway_toml "$i" "$INSTANCE" "${H[@]}" >"$D/hosts/${H[$i]}/gateway.toml"
done
cp docs/how-to/deploy.md "$D/DEPLOY.md"
tar czf "$D.tar.gz" -C dist "$(basename "$D")"
echo "$D.tar.gz"
echo "before installing: create /etc/uc2/node.key, /etc/uc2/allowlist.toml ([crypto]) and /etc/uc2/admin/admin.key ([admin]) on each host — DEPLOY.md says how"
