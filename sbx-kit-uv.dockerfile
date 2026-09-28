# syntax=docker/dockerfile:1

# Build stage: download the OFFICIAL uv release tarball and stage the binaries
# under /out, so the final overlay is just files that land on any base. We
# deliberately pull the fully static *musl* builds (uv-<arch>-unknown-linux-musl):
# they have no shared-library closure, so the overlay travels onto ANY base —
# glibc (Debian/Ubuntu), musl (Alpine/Wolfi) or distroless — with no dependency
# on the composed base's libc or package manager. This is why the install
# happens here at build time rather than in a create-time hook: uv is baked into
# the kit, so every sandbox has it the instant it starts, with no per-create
# download.
#
# The builder is a Docker Hardened Image (dhi.io/debian-base:trixie-dev), the
# base the sandbox-kit-spec RECIPES.md recommends for a mixin overlay build
# stage. Nothing from it reaches the kit: the final stage is scratch and copies
# only the two uv binaries, so the builder choice is about supply-chain hygiene
# of the build itself, not the shipped artifact. Because it is a DHI image,
# `docker buildx build` must be able to pull from dhi.io, so run
# `docker login dhi.io` first (or override with --build-arg BUILDER_IMAGE=...).
ARG BUILDER_IMAGE=dhi.io/debian-base:trixie-dev
FROM ${BUILDER_IMAGE} AS build

# Wired to the uvVersion kit arg via buildArg (see the descriptor).
ARG UV_VERSION=0.12.19
# Set automatically by buildx per target platform (amd64 / arm64).
ARG TARGETARCH

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl tar; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    # Map the Docker platform arch to uv's release triple. musl = fully static.
    case "$TARGETARCH" in \
      amd64) triple=x86_64-unknown-linux-musl ;; \
      arm64) triple=aarch64-unknown-linux-musl ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    ver="${UV_VERSION#v}"; \
    url="https://github.com/astral-sh/uv/releases/download/${ver}/uv-${triple}.tar.gz"; \
    mkdir -p /out/usr/local/bin /tmp/uv; \
    # The tarball unpacks to uv-<triple>/{uv,uvx}; strip that top dir.
    curl -fsSL "$url" | tar -xz -C /tmp/uv --strip-components=1; \
    install -m 0755 /tmp/uv/uv  /out/usr/local/bin/uv; \
    install -m 0755 /tmp/uv/uvx /out/usr/local/bin/uvx; \
    # A pinned version is a claim about content, so make the build ENFORCE it:
    # prove the binary runs, and prove it is the exact version requested.
    /out/usr/local/bin/uv --version; \
    /out/usr/local/bin/uv --version 2>&1 | grep -q "${ver}"; \
    # scratch has no /etc/passwd, so normalize to numeric root ownership. These
    # are system binaries the agent only needs to execute, not own.
    chown -R 0:0 /out

# The overlay: the uv and uvx binaries only. It ships nothing under /home, so
# there are no home-ownership concerns, and it sets no ENTRYPOINT/USER/WORKDIR
# because a mixin cannot own those (the workload does).
FROM scratch
COPY --from=build /out /
