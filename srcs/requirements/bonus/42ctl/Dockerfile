# 42ctl — the vault42 remote controller, BUILT FROM SOURCE.
#
# Upstream ships a distroless image (gcr.io/distroless/cc-debian12). This project
# may not pull a pre-made service image, so the binary is compiled here and shipped
# on the same alpine:3.23 base as every other image in this repository.
#
# This image is NOT a docker-compose service, and that is deliberate: 42ctl is a
# CLI that exits when its command finishes. An Inception service must run a real
# daemon as PID 1 with no keep-alive hack (compliance S06/S18/S23, R10/R19), which
# a CLI can never satisfy honestly. It is built by `make 42ctl` and invoked one
# shot at a time by the `make vault-*` targets.
#
# The source is cloned at a pinned revision rather than vendored: the crate pulls
# vault42-core/vault42-proto from git anyway, so the build is already network-bound,
# and a pin is easier to audit than a submodule.

FROM rust:1.96-alpine3.21 AS builder

# musl-dev + g++ for the `ring`/`blake3` C shims, protobuf-dev for the tonic
# codegen in vault42-proto, git for the pinned git dependencies.
RUN apk add --no-cache musl-dev pkgconfig git protobuf-dev cmake make g++ perl

ARG C42_REPO=https://github.com/Univers42/42ctl.git
ARG C42_REF=main

WORKDIR /build
RUN git clone --depth 1 --branch "${C42_REF}" "${C42_REPO}" . \
    && git rev-parse --short HEAD > /git-sha

RUN --mount=type=cache,id=c42-cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=c42-cargo-target,target=/build/target \
    FT_GIT_SHA="$(cat /git-sha)" \
    cargo build --release --target x86_64-unknown-linux-musl \
    && cp target/x86_64-unknown-linux-musl/release/42ctl /42ctl \
    && strip /42ctl

FROM alpine:3.23

# The CLI talks TLS to vault42 and to the platform API, so it needs a trust store.
RUN apk add --no-cache ca-certificates \
    && adduser -D -u 65532 -h /home/nonroot nonroot

COPY --from=builder /42ctl /usr/local/bin/42ctl

# Same non-root uid upstream uses, so a mounted ~/.42ctl keeps working either way.
USER nonroot:nonroot
WORKDIR /home/nonroot

ENTRYPOINT ["/usr/local/bin/42ctl"]
