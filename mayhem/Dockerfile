# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for risc0 (Rust / cargo-fuzz): the org base plus a pinned Rust nightly and
# cargo-fuzz under /opt/toolchains/rust ($HOME-independent, so the air-gapped PATCH re-run finds the
# same toolchain and the cargo registry the first online build populated), then mayhem/build.sh.
#
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] -t risc0-commit:test .

FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS

# -Zsanitizer=address needs nightly; pin it by date. Upstream's own rust-toolchain.toml pins a stable
# channel, so build.sh passes an explicit +<nightly> to every cargo call.
ARG RUST_CHANNEL=nightly-2026-10-15
ARG CARGO_FUZZ_VERSION=0.13.2

ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:${PATH} \
    RUST_FUZZ_TOOLCHAIN=${RUST_CHANNEL}

USER root
RUN install -d /opt/toolchains/rust \
 && curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
 && sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_CHANNEL}" \
 && rustup component add rust-src rustfmt --toolchain "${RUST_CHANNEL}" \
 && cargo install cargo-fuzz --version "${CARGO_FUZZ_VERSION}" --locked \
 && rm -f /tmp/rustup-init.sh \
 && chown -R 2000:2000 /opt/toolchains/rust

# DWARF<=3 anchor (SPEC 6.2 item 10): rustc emits DWARF4+ compile units and the verifier only reads the
# first .debug_info CU, so a tiny DWARF3 object is prepended to every link through a linker wrapper.
RUN set -eux; \
    install -d /opt/toolchains/rust/dwarf3-anchor; \
    printf 'const int mayhem_dwarf3_anchor = 0;\n' > /opt/toolchains/rust/dwarf3-anchor/anchor.c; \
    clang -g -gdwarf-3 -c /opt/toolchains/rust/dwarf3-anchor/anchor.c \
      -o /opt/toolchains/rust/dwarf3-anchor/anchor.o; \
    printf '#!/bin/sh\nexec clang /opt/toolchains/rust/dwarf3-anchor/anchor.o "$@"\n' \
      > /opt/toolchains/rust/dwarf3-anchor/cc-wrapper.sh; \
    chmod +x /opt/toolchains/rust/dwarf3-anchor/cc-wrapper.sh; \
    chmod -R a+rX /opt/toolchains/rust/dwarf3-anchor

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Populates $CARGO_HOME (online, this first build) and builds the sanitized fuzz target + the KAT probe.
RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
