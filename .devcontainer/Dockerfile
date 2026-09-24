FROM mcr.microsoft.com/devcontainers/rust:1-bookworm

# The macOS/Windows path (README.md § Devcontainer): ultima_cluster nodes are
# Linux-only, so this image is where `make up` actually runs a cluster.
ARG COSIGN_VERSION=3.1.3

RUN apt-get update && apt-get install -y --no-install-recommends jq iproute2 python3 \
 && rm -rf /var/lib/apt/lists/* \
 && arch="$(dpkg --print-architecture)" \
 && cd /tmp \
 && curl -fsSL -o "cosign-linux-${arch}" "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${arch}" \
 && curl -fsSL -o cosign_checksums.txt "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign_checksums.txt" \
 && grep " cosign-linux-${arch}\$" cosign_checksums.txt | sha256sum -c - \
 && install -m 0755 "cosign-linux-${arch}" /usr/local/bin/cosign \
 && rm -f "cosign-linux-${arch}" cosign_checksums.txt

USER vscode
# rust-toolchain.toml pins 1.96.0 (installs itself via rustup on first build);
# `make lint` also needs 1.89.0, the MSRV clippy gate (CLAUDE.md's own rule,
# and this template's Makefile runs it too).
RUN rustup toolchain install 1.96.0 --profile minimal --component rustfmt --component clippy \
 && rustup toolchain install 1.89.0 --profile minimal --component clippy \
 && cargo install cargo-generate --locked \
 # The devcontainer CLI remaps `vscode`'s uid/gid to match the host user (so
 # the bind-mounted workspace is writable), but the subdirectories rustup and
 # cargo just created above take the umask's default mode — not group- or
 # other-writable past their top level. A remapped vscode can then read the
 # toolchain/registry but not write cargo's own cache, and the first `cargo
 # build`/`cargo test` in the running container fails with "Permission
 # denied". Open both trees up now, as their owning (pre-remap) uid; this
 # image is a local dev container, not a shared host. (The base image's own
 # preinstalled root-owned toolchain under /usr/local/rustup is skipped with
 # a non-fatal error — vscode doesn't own it and doesn't need to write it.)
 ; chmod -R a+rwX /usr/local/cargo /usr/local/rustup 2>/dev/null; true
