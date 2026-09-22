#!/usr/bin/env bash
#
# Ports the WASIX patch set of a wasix-org/php branch onto a newer upstream php-src tag,
# so a PHP release that has no `*-wasix` branch yet can still be built for WASIX.
#
# Run it inside the build image (it needs git and network):
#
#   docker run --rm -v "$PWD":/work -w /work wasmer-php-builder:8.5 \
#     bash scripts/port-wasix-version.sh
#
# Environment:
#   PHP_VERSION       upstream PHP version to port to        (default: 8.5.10)
#   PHP_BASE_BRANCH   wasix-org/php branch carrying the patches (default: 8.5.7-wasix)
#   BASE_TAG          upstream tag the branch is based on    (default: php-<branch prefix>)
#   UPSTREAM_TAG      upstream tag to port onto              (default: php-$PHP_VERSION)
#   PHP_FORK_DIR      clone of wasix-org/php                 (default: .work/php-fork)
#   OUT_DIR           result, consumed by build-runtime.sh   (default: .work/php-$PHP_VERSION)
#   FORCE             set to 1 to recreate an existing OUT_DIR
#
# Steps:
#   1. clone wasix-org/php and the requested php-src tag;
#   2. extract the WASIX overlay as diff(BASE_TAG -> PHP_BASE_BRANCH), skipping the
#      vendored PECL extensions, CI files and test fixtures;
#   3. vendor ext/igbinary and ext/imagick (the WASIX configure script enables them);
#   4. apply the overlay onto the upstream tag.
#
# Then build it with:
#   PHP_VERSION=8.5.10 PHP_SOURCE_DIR=.work/php-8.5.10 bash scripts/build-runtime.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PHP_VERSION="${PHP_VERSION:-8.5.10}"
PHP_BASE_BRANCH="${PHP_BASE_BRANCH:-8.5.7-wasix}"
BASE_TAG="${BASE_TAG:-php-${PHP_BASE_BRANCH%-wasix}}"
UPSTREAM_TAG="${UPSTREAM_TAG:-php-${PHP_VERSION}}"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/.work}"
PHP_FORK_DIR="${PHP_FORK_DIR:-${WORK_DIR}/php-fork}"
OUT_DIR="${OUT_DIR:-${WORK_DIR}/php-${PHP_VERSION}}"
PATCH_FILE="${WORK_DIR}/wasix-overlay-${PHP_VERSION}.patch"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

if [ -e "${OUT_DIR}" ] && [ -n "$(ls -A "${OUT_DIR}" 2>/dev/null)" ]; then
    if [ "${FORCE:-0}" != "1" ]; then
        echo "${OUT_DIR} already exists; re-run with FORCE=1 to recreate it." >&2
        exit 1
    fi

    log "Removing the existing ${OUT_DIR}"
    rm -rf "${OUT_DIR}"
fi

mkdir -p "${WORK_DIR}"

if [ ! -d "${PHP_FORK_DIR}/.git" ]; then
    log "Cloning wasix-org/php (blobless)"
    git clone --filter=blob:none --no-checkout --quiet https://github.com/wasix-org/php.git "${PHP_FORK_DIR}"
fi

git -C "${PHP_FORK_DIR}" remote add upstream https://github.com/php/php-src.git 2>/dev/null || true

log "Fetching ${PHP_BASE_BRANCH}, ${BASE_TAG} and ${UPSTREAM_TAG}"
git -C "${PHP_FORK_DIR}" fetch --filter=blob:none --quiet origin "${PHP_BASE_BRANCH}"
git -C "${PHP_FORK_DIR}" fetch --filter=blob:none --quiet upstream tag "${BASE_TAG}" tag "${UPSTREAM_TAG}"

log "Extracting the WASIX overlay (diff ${BASE_TAG} -> ${PHP_BASE_BRANCH})"
git -C "${PHP_FORK_DIR}" diff "${BASE_TAG}" "origin/${PHP_BASE_BRANCH}" -- . \
    ':!ext/igbinary' ':!ext/imagick' ':!.github' ':!docs' ':!scripts' ':!wasix-tests' \
    > "${PATCH_FILE}"
echo "  $(grep -c '^diff --git' "${PATCH_FILE}") files, $(wc -l < "${PATCH_FILE}") lines"

log "Cloning php-src at ${UPSTREAM_TAG}"
git clone --depth 1 --branch "${UPSTREAM_TAG}" --quiet https://github.com/php/php-src.git "${OUT_DIR}"

log "Vendoring ext/igbinary and ext/imagick"
git -C "${PHP_FORK_DIR}" archive "origin/${PHP_BASE_BRANCH}" ext/igbinary ext/imagick | tar -x -C "${OUT_DIR}"

log "Applying the overlay onto ${UPSTREAM_TAG}"
git -C "${OUT_DIR}" apply "${PATCH_FILE}"

PORTED_VERSION="$(grep -m1 '^#define PHP_VERSION' "${OUT_DIR}/main/php_version.h" | tr -d '"' | awk '{print $3}')"
log "Ported PHP ${PORTED_VERSION} into ${OUT_DIR}"
echo "Build it with:"
echo "  PHP_VERSION=${PHP_VERSION} PHP_SOURCE_DIR=${OUT_DIR} bash scripts/build-runtime.sh"