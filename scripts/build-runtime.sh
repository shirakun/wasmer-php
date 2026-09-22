#!/usr/bin/env bash
#
# Builds the PHP CLI for WASIX and stages the runtime artefacts in ./dist.
#
# Run it inside the build container (see docker/Dockerfile):
#
#   docker compose run --rm builder bash scripts/build-runtime.sh
#
# Environment:
#   PHP_BRANCH       wasix-org/php branch to build          (default: 8.5.7-wasix)
#   PHP_VERSION      version recorded in the package        (default: 8.5.7)
#   PHP_SOURCE_DIR   build a prepared tree instead of cloning (see scripts/port-wasix-version.sh)
#   SRC_DIR          checkout location inside the image     (default: /src)
#   WORKSPACE        mounted workspace                      (default: /work)
#   SKIP_CONFIGURE   set to 1 to reuse an existing configure run
set -euo pipefail

PHP_BRANCH="${PHP_BRANCH:-8.5.7-wasix}"
PHP_VERSION="${PHP_VERSION:-8.5.7}"
PHP_SOURCE_DIR="${PHP_SOURCE_DIR:-}"
SRC_DIR="${SRC_DIR:-/src}"
WORKSPACE="${WORKSPACE:-/work}"
PHP_REPOSITORY="${PHP_REPOSITORY:-https://github.com/wasix-org/php.git}"
DEPS_REPOSITORY="${DEPS_REPOSITORY:-https://github.com/wasix-org/php-wasix-deps.git}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

mkdir -p "${SRC_DIR}"

# PHP sources: either a tree prepared by scripts/port-wasix-version.sh (used when the
# requested PHP release has no wasix-org/php branch yet) or the branch itself.
if [ -n "${PHP_SOURCE_DIR}" ]; then
    PHP_TREE="${PHP_SOURCE_DIR}"
    log "Using the prepared PHP source tree at ${PHP_TREE} (PHP ${PHP_VERSION})"

    if [ ! -f "${PHP_TREE}/buildconf" ]; then
        echo "${PHP_TREE} does not look like a php-src checkout." >&2
        exit 1
    fi
else
    PHP_TREE="${SRC_DIR}/php"
    log "Checking out wasix-org/php (${PHP_BRANCH})"

    if [ -d "${PHP_TREE}/.git" ]; then
        git -C "${PHP_TREE}" fetch --depth 1 origin "${PHP_BRANCH}"
        git -C "${PHP_TREE}" checkout --force FETCH_HEAD
    else
        git clone --depth 1 --branch "${PHP_BRANCH}" "${PHP_REPOSITORY}" "${PHP_TREE}"
    fi
fi

log "Checking out php-wasix-deps (prebuilt WASIX libraries: openssl, icu, curl, gd, ...)"

if [ -d "${SRC_DIR}/php-wasix-deps/.git" ]; then
    git -C "${SRC_DIR}/php-wasix-deps" pull --ff-only
else
    git clone --depth 1 "${DEPS_REPOSITORY}" "${SRC_DIR}/php-wasix-deps"
fi

export PHP_WASIX_DEPS="${SRC_DIR}/php-wasix-deps"

# `wasix-configure-eh.sh` exports these inside its own subshell only, so `make`
# would fall back to wasixcc's defaults and link against the exnref sysroot
# instead of the legacy-EH libraries shipped by php-wasix-deps (undefined
# `__cxa_*`/`operator new` symbols in libc++.a). Keep them exported for the build.
export WASIXCC_WASM_EXCEPTIONS="${WASIXCC_WASM_EXCEPTIONS:-legacy}"
export WASIXCC_INCLUDE_CPP_SYMBOLS="${WASIXCC_INCLUDE_CPP_SYMBOLS:-yes}"
export WASIX_64BIT_LONG_PATCH="${WASIX_64BIT_LONG_PATCH:-yes}"

cd "${PHP_TREE}"

if [ "${SKIP_CONFIGURE:-0}" = "1" ]; then
    log "Skipping configure (SKIP_CONFIGURE=1)"
else
    log "Configuring PHP ${PHP_VERSION} for wasm32-wasi (64-bit)"
    bash wasix-configure-eh-64.sh
fi

log "Compiling PHP and running wasm-opt (this is the long step)"
bash wasix-build-eh.sh

log "Staging runtime artefacts in ${WORKSPACE}/dist"
mkdir -p "${WORKSPACE}/dist/modules" "${WORKSPACE}/dist/php-wasix-deps/openssl"
cp "${PHP_TREE}/sapi/cli/php.wasm" "${WORKSPACE}/dist/modules/php"

rm -rf "${WORKSPACE}/dist/php-wasix-deps/icu"
cp -R "${PHP_WASIX_DEPS}/icu" "${WORKSPACE}/dist/php-wasix-deps/icu"

rm -rf "${WORKSPACE}/dist/php-wasix-deps/openssl/ssl"
cp -R "${PHP_WASIX_DEPS}/openssl/ssl" "${WORKSPACE}/dist/php-wasix-deps/openssl/ssl"

printf '%s\n' "${PHP_VERSION}" > "${WORKSPACE}/dist/PHP_VERSION"

# The build runs as root inside the container, so the staged files would belong to
# root on the host. Linux/WSL users (and CI runners) then cannot write into dist/
# when packaging. Hand the artefacts back to whoever owns the workspace.
if [ -w "${WORKSPACE}/dist" ]; then
    chmod -R a+rwX "${WORKSPACE}/dist" 2>/dev/null || true
fi

log "Built $(du -h "${WORKSPACE}/dist/modules/php" | cut -f1) php.wasm for PHP ${PHP_VERSION}"