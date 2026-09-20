#!/usr/bin/env bash
set -euo pipefail

chart="charts/app"
common=(
  --set image.repository=registry.example.local:5000/test-app
  --set image.tag=test
  --set ingress.enabled=true
  --set ingress.host=api.example.test
  --set ingress.tls.enabled=true
)

fail() {
  echo "error: $*" >&2
  exit 1
}

expect_contains() {
  local rendered="$1"
  local needle="$2"
  grep -Fq -- "${needle}" <<< "${rendered}" || fail "missing '${needle}'"
}

expect_not_contains() {
  local rendered="$1"
  local needle="$2"
  ! grep -Fq -- "${needle}" <<< "${rendered}" || fail "unexpected '${needle}'"
}

expect_count() {
  local rendered="$1"
  local needle="$2"
  local want="$3"
  local got
  got="$(grep -F -c -- "${needle}" <<< "${rendered}" || true)"
  [ "${got}" = "${want}" ] || fail "expected ${want} '${needle}' lines, got ${got}"
}

rendered="$(helm template test-release "${chart}" \
  --set image.repository=registry.example.local:5000/test-app \
  --set image.tag=test \
  --set ingress.enabled=true \
  --set ingress.host=api.example.test)"
expect_not_contains "${rendered}" 'secretName:'

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set 'ingress.tls.extraHosts[0]=www.api.example.test')"
expect_contains "${rendered}" 'secretName: test-release-app-tls'
expect_contains "${rendered}" 'host: "api.example.test"'
expect_contains "${rendered}" '"www.api.example.test"'

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set ingress.tls.secretName=existing-api-tls)"
expect_contains "${rendered}" 'secretName: existing-api-tls'

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set strategy.mode=canary \
  --set canary.ingress.enabled=true \
  --set 'ingress.annotations.cert-manager\.io/cluster-issuer=test-issuer' \
  --set canary.ingress.tls.secretName=canary-tls)"
expect_contains "${rendered}" 'secretName: test-release-app-tls'
expect_contains "${rendered}" 'secretName: canary-tls'
expect_contains "${rendered}" 'host: "canary.api.example.test"'
expect_count "${rendered}" 'cert-manager.io/cluster-issuer: test-issuer' 2

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set strategy.mode=blueGreen \
  --set blueGreen.preview.enabled=true \
  --set blueGreen.preview.ingress.enabled=true \
  --set 'ingress.annotations.cert-manager\.io/cluster-issuer=test-issuer')"
expect_contains "${rendered}" 'secretName: test-release-app-tls'
expect_contains "${rendered}" 'secretName: test-release-app-preview-tls'
expect_contains "${rendered}" 'host: "preview.api.example.test"'
expect_count "${rendered}" 'cert-manager.io/cluster-issuer: test-issuer' 2

set +e
rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set strategy.mode=canary \
  --set canary.trafficProvider=traefik \
  --set 'canary.traefik.entryPoints[0]=websecure' 2>&1)"
status=$?
set -e
[ "${status}" -ne 0 ] || fail "Traefik TLS without an explicit Secret unexpectedly rendered"
expect_contains "${rendered}" 'ingress.tls.secretName is required'

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set strategy.mode=canary \
  --set canary.trafficProvider=traefik \
  --set ingress.tls.secretName=existing-traefik-tls \
  --set 'canary.traefik.entryPoints[0]=websecure')"
expect_contains "${rendered}" 'entryPoints:'
expect_contains "${rendered}" '- websecure'
expect_contains "${rendered}" 'secretName: existing-traefik-tls'

echo "chart ingress TLS cases passed"
