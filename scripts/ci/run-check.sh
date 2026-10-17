#!/usr/bin/env bash
# Runs in GitHub Actions on the runner. Not a VPS script.
# Usage: run-check.sh lint|test
# Writes <name>.txt and exits with the make target's status.
set -euo pipefail

name="${1:?check name required}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

set -o pipefail
make "$name" 2>&1 | tee "${name}.txt"
