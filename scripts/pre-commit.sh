#!/usr/bin/env bash
# Runs on the control-plane machine, before git commit. Not on the VPS.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

root="$(git rev-parse --show-toplevel)"
cd "$root"
log "pre-commit: lint"
make lint
log "pre-commit: test"
make test
