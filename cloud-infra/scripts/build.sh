#!/usr/bin/env bash
# build.sh — before make cloud-up creates anything: build the binaries for
# terraform.tfvars' arch with package.sh's own build steps, so a compile
# error or a missing target fails here, not after three hosts bill.
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"
require_make
arch="$(tfvar arch)"
echo "== build for ${arch:-x86_64} hosts"
ARCH="${arch:-x86_64}" "$PROJECT_DIR/scripts/package.sh" --build-only
