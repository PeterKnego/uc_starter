# Builds this app's service binary for compose.yml's svcN containers. Not
# liquid-processed (cargo-generate.toml only templates Cargo.toml, uc-app.env,
# src/identity.rs and README.md), so APP_NAME arrives as a build ARG, read by
# compose.yml from uc-app.env — never `{{project-name}}` here.
FROM rust:1.96.0-bookworm AS builder
ARG APP_NAME
WORKDIR /src
COPY . .
RUN cargo build --release --bin "${APP_NAME}-service" --bin "${APP_NAME}"

FROM debian:bookworm-slim
ARG APP_NAME
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
# Two fixed names regardless of APP_NAME, so compose.yml never needs the app
# name at the container level: the service (ENTRYPOINT, what svcN runs) and
# the remote client (for a one-shot `docker run --entrypoint
# /usr/local/bin/app-client ...` against this image, e.g. a put/get
# round-trip through a gateway — see compose.yml's own header).
COPY --from=builder /src/target/release/${APP_NAME}-service /usr/local/bin/app-service
COPY --from=builder /src/target/release/${APP_NAME} /usr/local/bin/app-client
ENTRYPOINT ["/usr/local/bin/app-service"]
