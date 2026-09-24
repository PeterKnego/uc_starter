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
 # the bind-mounted workspace is writable), but $CARGO_HOME/{registry,git}
 # — the two trees `cargo build`/`cargo test` write into at runtime, fetching
 # and unpacking deps — were just created above at the umask's default mode:
 # not group- or other-writable past their top level. A remapped vscode can
 # then read them but not write into them, and the first build in the
 # running container fails with "Permission denied" opening the registry
 # cache. Both toolchains rust-toolchain.toml / this Makefile's MSRV gate
 # need (1.96.0, 1.89.0) are already installed above, so rustup itself
 # writes nothing at runtime — /usr/local/rustup and the toolchain binaries
 # (rustc, cargo, clippy-driver, rustfmt) stay exactly as installed, not
 # world-writable.
 && mkdir -p /usr/local/cargo/registry /usr/local/cargo/git \
 && chmod -R a+rwX /usr/local/cargo/registry /usr/local/cargo/git
