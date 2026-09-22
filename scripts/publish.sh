#!/usr/bin/env bash
#
# Builds the .webc package and publishes it to the Wasmer registry.
#
#   bash scripts/publish.sh              # publish
#   bash scripts/publish.sh --dry-run    # validate the package, upload nothing
#
# Environment:
#   NAMESPACE     registry namespace  (default: the logged in Wasmer user)
#   PACKAGE_NAME  package name        (default: php)
#   PHP_VERSION   package version     (default: the version staged in dist/PHP_VERSION)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

DRY_RUN=0
for argument in "$@"; do
    case "${argument}" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown option: ${argument}" >&2; exit 1 ;;
    esac
done

bash scripts/build-package.sh

NAMESPACE="${NAMESPACE:-$(wasmer whoami 2>/dev/null | tail -n 1 | awk '{print $NF}')}"
PACKAGE_NAME="${PACKAGE_NAME:-php}"
PHP_VERSION="${PHP_VERSION:-$(cat dist/PHP_VERSION 2>/dev/null || echo 0.0.0)}"
REFERENCE="${NAMESPACE}/${PACKAGE_NAME}@${PHP_VERSION}"

if [ "${DRY_RUN}" = "1" ]; then
    # `wasmer publish --dry-run` cannot tag a version that is not on the registry yet,
    # so validate the package locally instead: `--check` runs the full packaging flow.
    wasmer package build dist --check
    echo "Dry run succeeded: the package builds, nothing was uploaded."
    exit 0
fi

# The registry cannot overwrite a published version, so fail before uploading anything.
if wasmer package get "${REFERENCE}" >/dev/null 2>&1; then
    cat >&2 <<EOF
${REFERENCE} is already published and cannot be overwritten.

Release a new version instead, for example:
  PHP_BRANCH=8.5.8-wasix PHP_VERSION=8.5.8 bash scripts/publish.sh
EOF
    exit 1
fi

wasmer publish dist --non-interactive
echo "Published ${REFERENCE}"