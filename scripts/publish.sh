#!/usr/bin/env bash
#
# Builds the .webc package and publishes it to the Wasmer registry.
#
#   bash scripts/publish.sh              # publish
#   bash scripts/publish.sh --dry-run    # validate the publish flow, upload nothing
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

if [ "${DRY_RUN}" = "1" ]; then
    # `wasmer publish --dry-run` cannot tag a version that is not on the registry yet,
    # so validate the package locally instead: `--check` runs the full packaging flow.
    wasmer package build dist --check
    echo "Dry run succeeded: the package builds, nothing was uploaded."
else
    wasmer publish dist --non-interactive
fi