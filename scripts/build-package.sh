#!/usr/bin/env bash
#
# Assembles ./dist (built by scripts/build-runtime.sh) into a .webc Wasmer package.
#
# Environment:
#   NAMESPACE     registry namespace   (default: the logged in Wasmer user)
#   PACKAGE_NAME  package name         (default: php)
#   PHP_VERSION   package version      (default: the version staged in dist/PHP_VERSION)
#   OUT_DIR       output directory     (default: build)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ ! -f dist/modules/php ]; then
    echo "dist/modules/php is missing: run scripts/build-runtime.sh first." >&2
    exit 1
fi

NAMESPACE="${NAMESPACE:-$(wasmer whoami 2>/dev/null | tail -n 1 | awk '{print $NF}')}"
PACKAGE_NAME="${PACKAGE_NAME:-php}"
PHP_VERSION="${PHP_VERSION:-$(cat dist/PHP_VERSION 2>/dev/null || echo 0.0.0)}"
OUT_DIR="${OUT_DIR:-build}"

if [ -z "${NAMESPACE}" ]; then
    echo "Unable to detect the registry namespace; set NAMESPACE explicitly." >&2
    exit 1
fi

sed -e "s|__NAMESPACE__|${NAMESPACE}|g" \
    -e "s|__PACKAGE_NAME__|${PACKAGE_NAME}|g" \
    -e "s|__VERSION__|${PHP_VERSION}|g" \
    package/wasmer.toml > dist/wasmer.toml

cp package/README.md dist/README.md
cp package/LICENSE.txt dist/LICENSE

mkdir -p "${OUT_DIR}"

# `wasmer package build` refuses to overwrite an existing artefact.
WEBC="${OUT_DIR}/${PACKAGE_NAME}-${PHP_VERSION}.webc"
rm -f "${WEBC}"

wasmer package build dist --out "${WEBC}"

echo "Packaged ${NAMESPACE}/${PACKAGE_NAME}@${PHP_VERSION} -> ${OUT_DIR}/${PACKAGE_NAME}-${PHP_VERSION}.webc"