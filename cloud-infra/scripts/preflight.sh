#!/usr/bin/env bash
# preflight.sh — refuse early, with the fix, before anything is created.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
require_make
[ -f "$TFV" ] || die "no cloud-infra/terraform.tfvars — cp cloud-infra/example.tfvars cloud-infra/terraform.tfvars and edit it"
for t in terraform ansible-playbook jq ssh; do
  command -v "$t" >/dev/null || die "$t not found — cloud-infra/README.md § Control machine has the install lines"
done
v="$(terraform version -json | jq -r .terraform_version)"
ver_ge "$v" 1.7.0 || die "terraform $v is too old: need 1.7 or newer (cloud-infra/README.md § Control machine)"
cloud="$(tfvar cloud)"; cloud="${cloud:-hetzner}"
case "$cloud" in
  hetzner) [ -n "${HCLOUD_TOKEN:-}" ] || die "cloud = hetzner needs HCLOUD_TOKEN in cloud-infra/.env (cp cloud-infra/.env.example cloud-infra/.env)" ;;
  aws) [ -n "${AWS_ACCESS_KEY_ID:-}${AWS_PROFILE:-}" ] || [ -f "$HOME/.aws/credentials" ] \
         || die "cloud = aws needs AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY (cloud-infra/.env) or AWS_PROFILE" ;;
  gcp) [ -n "${GOOGLE_PROJECT:-}" ] || die "cloud = gcp needs GOOGLE_PROJECT (cloud-infra/.env) and GOOGLE_APPLICATION_CREDENTIALS, or gcloud auth application-default login" ;;
  *) die "cloud = \"$cloud\" in terraform.tfvars: must be hetzner, aws or gcp" ;;
esac
pubkey="$(tfvar ssh_public_key)"
[ -n "$pubkey" ] || die "ssh_public_key is empty in cloud-infra/terraform.tfvars"
key="$(ssh_key_file)"
if [ ! -r "$key" ] && ! ssh-add -L 2>/dev/null | grep -qF "$(echo "$pubkey" | awk '{print $2}')"; then
  die "the SSH private key $key is not readable and ssh-agent does not hold it. In the devcontainer: VS Code forwards your host's agent (ssh-add the key on the host); the devcontainer CLI needs ~/.ssh mounted — cloud-infra/README.md § SSH key"
fi
arch="$(tfvar arch)"; arch="${arch:-x86_64}"
mach="$(uname -m)"; [ "$mach" = arm64 ] && mach=aarch64
if [ "$(uname -s)" != Linux ] || [ "$arch" != "$mach" ]; then
  command -v cargo-zigbuild >/dev/null || die "hosts are $arch Linux and this is $(uname -s) $mach: the bundle is cross-built — cargo install cargo-zigbuild --locked"
  command -v zig >/dev/null || python3 -c 'import ziglang' 2>/dev/null || die "zig not found: brew install zig (macOS) or pip3 install ziglang"
else   # native: package.sh bundles .uc/bin as it is
  v="$("$UC_BIN/uc2-node" --version 2>/dev/null || true)"
  case " $v " in *" $UC_VERSION "*) ;; *) die "no ultima_cluster $UC_VERSION in .uc/bin (found: ${v:-nothing}) — run make bins" ;; esac
fi
echo "preflight: ok (cloud=$cloud arch=$arch owner=${TF_VAR_owner:-})"
