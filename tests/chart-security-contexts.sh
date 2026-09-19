#!/usr/bin/env bash
set -euo pipefail

chart="charts/app"
common=(
  --set image.repository=registry.example.local:5000/test-app
  --set image.tag=test
  --set podSecurityContext.runAsNonRoot=true
  --set podSecurityContext.runAsUser=10001
  --set podSecurityContext.seccompProfile.type=RuntimeDefault
  --set securityContext.allowPrivilegeEscalation=false
  --set securityContext.readOnlyRootFilesystem=true
  --set 'securityContext.capabilities.drop[0]=ALL'
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

rendered="$(helm template test-release "${chart}" "${common[@]}")"
expect_count "${rendered}" 'runAsNonRoot: true' 1
expect_count "${rendered}" 'allowPrivilegeEscalation: false' 1

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set strategy.mode=canary)"
expect_count "${rendered}" 'runAsNonRoot: true' 2
expect_count "${rendered}" 'allowPrivilegeEscalation: false' 2

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set strategy.mode=blueGreen)"
expect_count "${rendered}" 'runAsNonRoot: true' 2
expect_count "${rendered}" 'allowPrivilegeEscalation: false' 2

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set job.enabled=true \
  --set job.podSecurityContext.runAsUser=20002 \
  --set job.securityContext.readOnlyRootFilesystem=false \
  --set migrations.enabled=true \
  --set migrations.podSecurityContext.runAsUser=20003 \
  --set migrations.securityContext.readOnlyRootFilesystem=false \
  --set cronJobs[0].name=cleanup \
  --set 'cronJobs[0].schedule=0 3 * * *' \
  --set cronJobs[0].podSecurityContext.runAsUser=20004 \
  --set cronJobs[0].securityContext.readOnlyRootFilesystem=false)"
expect_count "${rendered}" 'runAsUser: 20002' 1
expect_count "${rendered}" 'runAsUser: 20003' 1
expect_count "${rendered}" 'runAsUser: 20004' 1
expect_count "${rendered}" 'runAsUser: 10001' 1
expect_count "${rendered}" 'readOnlyRootFilesystem: false' 3
expect_count "${rendered}" 'readOnlyRootFilesystem: true' 1

echo "chart security context cases passed"
