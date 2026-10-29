# 42ctl — the vault42 remote controller, BUILT FROM SOURCE.
#
# Upstream ships a distroless image (gcr.io/distroless/cc-debian12). This project
# may not pull a pre-made image of any kind — the subject excepts Alpine and Debian
# only, so not even a rust:* builder — and the binary is compiled here with
# Alpine's own toolchain, on the same alpine:3.23 base as every other image in
# this repository. 42ctl declares rust-version 1.91; alpine:3.23 ships 1.91.1.
#
# This image is NOT a docker-compose service, and that is deliberate: 42ctl is a
# CLI that exits when its command finishes. An Inception service must run a real
# daemon as PID 1 with no keep-alive hack (compliance S06/S18/S23, R10/R19), which
# a CLI can never satisfy honestly. It is built by `make 42ctl` and invoked one
# shot at a time by the `make vault-*` targets.
#
# The source is cloned from a named ref (C42_REF, a branch or a tag; main by
# default) rather than vendored: the crate pulls vault42-core/vault42-proto from
# git anyway, so the build is already network-bound.

FROM alpine:3.23.7 AS builder

# rust + cargo from Alpine's repository; musl-dev + g++ for the `ring`/`blake3`
# C shims, protobuf-dev for the tonic codegen in vault42-proto, git for the git
# dependencies.
RUN apk add --no-cache rust cargo musl-dev pkgconfig git protobuf-dev cmake make g++ perl

ARG C42_REPO=https://github.com/Univers42/42ctl.git
ARG C42_REF=main

WORKDIR /build
RUN git clone --depth 1 --branch "${C42_REF}" "${C42_REPO}" . \
    && git rev-parse --short HEAD > /git-sha

# Alpine's rust carries the standard library for its own triple only
# (x86_64-alpine-linux-musl), and links musl dynamically unless told otherwise.
# crt-static keeps the binary self-contained for the bare runtime stage; naming
# the target keeps that flag off the build scripts and proc-macros, which must
# stay dynamic.
RUN --mount=type=cache,id=c42-cargo-registry,target=/root/.cargo/registry \
    --mount=type=cache,id=c42-cargo-target-alpine,target=/build/target \
    FT_GIT_SHA="$(cat /git-sha)" \
    RUSTFLAGS="-C target-feature=+crt-static" \
    cargo build --release --target x86_64-alpine-linux-musl \
    && cp target/x86_64-alpine-linux-musl/release/42ctl /42ctl \
    && strip /42ctl

FROM alpine:3.23.7

# The CLI talks TLS to vault42 and to the platform API, so it needs a trust store.
RUN apk add --no-cache ca-certificates \
    && adduser -D -u 65532 -h /home/nonroot nonroot

COPY --from=builder /42ctl /usr/local/bin/42ctl

# Same non-root uid upstream uses, so a mounted ~/.42ctl keeps working either way.
USER nonroot:nonroot
WORKDIR /home/nonroot

ENTRYPOINT ["/usr/local/bin/42ctl"]
