# syntax=docker/dockerfile:1

# Build environment for the WASIX/WASI PHP runtime published as the
# `<namespace>/php` Wasmer package.
#
# It mirrors the toolchain pinned by the upstream PHP WASIX CI
# (wasix-org/php: .github/workflows/wasix-pr.yaml):
#   * wasixcc            - clang wrapper driving LLVM + the WASIX sysroot
#   * wasix-libc sysroot - WASIX libc with the POSIX extensions PHP needs
#   * binaryen           - wasm-opt / wasm-strip used to post-process php.wasm
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
# The upstream PHP WASIX CI pins are stale: its wasixcc v0.3.0 rejects
# WASM_EXCEPTIONS=legacy (used by wasix-configure-eh.sh) and its sysroot tag
# v2026-02-16.1 predates the sysroot-exnref-eh variant that wasixcc v0.4.x
# links against. These are the versions the 8.5 branch actually builds with.
ARG WASIXCC_VERSION=v0.4.7
ARG WASIX_SYSROOT_TAG=v2026-07-03.1
ARG WASIX_LLVM_TAG=21.1.206
ARG BINARYEN_VERSION=version_123

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf \
        bison \
        build-essential \
        ca-certificates \
        curl \
        git \
        pkg-config \
        re2c \
        tar \
        wabt \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# wasm-opt and wasm-strip (the PHP WASIX build post-processes php.wasm with wasm-opt).
RUN curl -fsSL -o /tmp/binaryen.tar.gz \
        "https://github.com/WebAssembly/binaryen/releases/download/${BINARYEN_VERSION}/binaryen-${BINARYEN_VERSION}-x86_64-linux.tar.gz" \
    && tar -xzf /tmp/binaryen.tar.gz -C /tmp \
    && cp /tmp/binaryen-${BINARYEN_VERSION}/bin/* /usr/local/bin/ \
    && rm -rf /tmp/binaryen.tar.gz /tmp/binaryen-${BINARYEN_VERSION}

# wasixcc + WASIX sysroot + LLVM toolchain.
RUN curl -fsSL -o /tmp/wasixcc.tar.gz \
        "https://github.com/wasix-org/wasixcc/releases/download/${WASIXCC_VERSION}/wasixcc-x86_64-unknown-linux-gnu.tar.gz" \
    && tar -xzf /tmp/wasixcc.tar.gz -C /tmp \
    && mkdir -p /opt/wasixcc/bin \
    && mv /tmp/wasixccenv /opt/wasixcc/wasixccenv \
    && chmod +x /opt/wasixcc/wasixccenv \
    && /opt/wasixcc/wasixccenv install-executables /opt/wasixcc/bin \
    && /opt/wasixcc/wasixccenv download-sysroot "${WASIX_SYSROOT_TAG}" \
    && /opt/wasixcc/wasixccenv download-llvm "${WASIX_LLVM_TAG}" \
    && rm -f /tmp/wasixcc.tar.gz

ENV PATH="/opt/wasixcc/bin:${PATH}"

# Sources live in a named volume so rebuilds do not re-clone PHP.
VOLUME ["/src"]

WORKDIR /work
CMD ["bash"]