#!/usr/bin/env bash
# Prevent known JavaScript actions from regressing to releases that embed Node.js 20 or older.
#
# This check is intentionally deterministic: resolving remote action manifests during CI would make
# validation depend on GitHub API availability and rate limits. Update the minimum major here when a
# dependency changes its embedded runtime.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

FAILURES=0

check_minimum_major() {
  local action="$1"
  local minimum="$2"
  local match
  local version

  while IFS= read -r match; do
    [ -z "${match}" ] && continue
    version="${match##*@v}"
    if [ "${version}" -lt "${minimum}" ]; then
      echo "::error::${match} embeds Node.js 20 or older; use ${action}@v${minimum} or newer"
      FAILURES=$((FAILURES + 1))
    fi
  done < <(grep -rhoE "uses:[[:space:]]*${action}@v[0-9]+" .github/workflows || true)
}

check_minimum_major "actions/checkout" 5
check_minimum_major "actions/setup-go" 6
check_minimum_major "actions/setup-node" 5
check_minimum_major "actions/setup-python" 6
check_minimum_major "azure/setup-helm" 5
check_minimum_major "pnpm/action-setup" 5

if [ "${FAILURES}" -ne 0 ]; then
  echo "${FAILURES} action reference(s) still use Node.js 20 or older"
  exit 1
fi

echo "All tracked JavaScript actions use Node.js 24-compatible releases"
