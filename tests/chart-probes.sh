#!/usr/bin/env bash
set -euo pipefail

chart="charts/app"
common=(
  --set image.repository=registry.example.local:5000/test-app
  --set image.tag=test
)

fail() {
  echo "error: $*" >&2
  exit 1
}

expect_count() {
  local rendered="$1"
  local needle="$2"
  local want="$3"
  local got
  got="$(grep -F -c -- "${needle}" <<< "${rendered}" || true)"
  [ "${got}" = "${want}" ] || fail "expected ${want} '${needle}' lines, got ${got}"
}

expect_not_contains() {
  local rendered="$1"
  local needle="$2"
  ! grep -Fq -- "${needle}" <<< "${rendered}" || fail "unexpected '${needle}'"
}

rendered="$(helm template test-release "${chart}" "${common[@]}")"
expect_count "${rendered}" 'port: http' 2
expect_count "${rendered}" 'containerPort: 8080' 1

rendered="$(helm template test-release "${chart}" "${common[@]}" --set containerPort=3000)"
expect_count "${rendered}" 'port: http' 2
expect_count "${rendered}" 'containerPort: 3000' 1

rendered="$(helm template test-release "${chart}" "${common[@]}" --set strategy.mode=canary)"
expect_count "${rendered}" 'port: http' 4
expect_count "${rendered}" 'containerPort: 8080' 2

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set strategy.mode=blueGreen \
  --set probes.enabled=false \
  --set containerPort=0)"
expect_not_contains "${rendered}" 'livenessProbe:'
expect_not_contains "${rendered}" 'readinessProbe:'
expect_not_contains "${rendered}" 'startupProbe:'
expect_not_contains "${rendered}" 'containerPort:'

echo "chart probe cases passed"
