#!/usr/bin/env bash
set -euo pipefail

chart="charts/app"
common=(
  --set image.repository=registry.example.local:5000/test-app
  --set image.tag=test
  --set 'podAnnotations.rollout\.example/managed=enabled'
  --set podLabels.cost-center=platform
  --set 'topologySpreadConstraints[0].maxSkew=1'
  --set 'topologySpreadConstraints[0].topologyKey=kubernetes.io/hostname'
  --set 'topologySpreadConstraints[0].whenUnsatisfiable=ScheduleAnyway'
  --set startupProbe.httpGet.path=/startup
  --set startupProbe.httpGet.port=8080
  --set startupProbe.periodSeconds=5
  --set 'lifecycle.preStop.exec.command[0]=sh'
  --set 'lifecycle.preStop.exec.command[1]=-c'
  --set 'lifecycle.preStop.exec.command[2]=sleep 5'
  --set priorityClassName=platform-critical
  --set terminationGracePeriodSeconds=30
  --set 'volumes[0].name=tmp'
  --set 'volumes[0].emptyDir.sizeLimit=1Gi'
  --set 'volumeMounts[0].name=tmp'
  --set 'volumeMounts[0].mountPath=/tmp'
  --set 'initContainers[0].name=prepare'
  --set 'initContainers[0].image=busybox:1.37'
  --set 'initContainers[0].command[0]=sh'
  --set 'extraContainers[0].name=metrics'
  --set 'extraContainers[0].image=busybox:1.37'
  --set revisionHistoryLimit=3
  --set strategy.rollingUpdate.maxSurge=0
  --set strategy.rollingUpdate.maxUnavailable=1
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

assert_deployments() {
  local rendered="$1"
  local count="$2"

  expect_count "${rendered}" 'rollout.example/managed: enabled' "${count}"
  expect_count "${rendered}" 'cost-center: platform' "${count}"
  expect_count "${rendered}" 'topologySpreadConstraints:' "${count}"
  expect_count "${rendered}" 'priorityClassName: platform-critical' "${count}"
  expect_count "${rendered}" 'terminationGracePeriodSeconds: 30' "${count}"
  expect_count "${rendered}" 'volumes:' "${count}"
  expect_count "${rendered}" 'initContainers:' "${count}"
  expect_count "${rendered}" 'startupProbe:' "${count}"
  expect_count "${rendered}" 'lifecycle:' "${count}"
  expect_count "${rendered}" 'sleep 5' "${count}"
  expect_count "${rendered}" 'volumeMounts:' "${count}"
  expect_count "${rendered}" 'name: metrics' "${count}"
  expect_count "${rendered}" 'revisionHistoryLimit: 3' "${count}"
  expect_count "${rendered}" 'maxSurge: 0' "${count}"
  expect_count "${rendered}" 'maxUnavailable: 1' "${count}"
}

rendered="$(helm template test-release "${chart}" \
  --set image.repository=registry.example.local:5000/test-app \
  --set image.tag=test)"
expect_not_contains "${rendered}" 'rollout.example/managed:'
expect_not_contains "${rendered}" 'cost-center: platform'
expect_not_contains "${rendered}" 'topologySpreadConstraints:'
expect_not_contains "${rendered}" 'priorityClassName:'
expect_not_contains "${rendered}" 'terminationGracePeriodSeconds:'
expect_not_contains "${rendered}" 'volumes:'
expect_not_contains "${rendered}" 'initContainers:'
expect_not_contains "${rendered}" 'lifecycle:'
expect_not_contains "${rendered}" 'startupProbe:'
expect_not_contains "${rendered}" 'volumeMounts:'
expect_not_contains "${rendered}" 'revisionHistoryLimit:'

rendered="$(helm template test-release "${chart}" "${common[@]}")"
assert_deployments "${rendered}" 1

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set strategy.mode=canary)"
assert_deployments "${rendered}" 2

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set strategy.mode=blueGreen)"
assert_deployments "${rendered}" 2

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set job.enabled=true \
  --set migrations.enabled=true \
  --set 'cronJobs[0].name=cleanup' \
  --set 'cronJobs[0].schedule=0 3 * * *')"
expect_count "${rendered}" 'priorityClassName: platform-critical' 4
expect_count "${rendered}" 'terminationGracePeriodSeconds: 30' 4
expect_count "${rendered}" 'sizeLimit: 1Gi' 4
expect_count "${rendered}" 'mountPath: /tmp' 4

rendered="$(helm template test-release "${chart}" "${common[@]}" \
  --set job.enabled=true \
  --set-json 'job.volumes=[]' \
  --set-json 'job.volumeMounts=[]' \
  --set-string 'job.priorityClassName=')"
expect_count "${rendered}" 'priorityClassName: platform-critical' 1
expect_count "${rendered}" 'sizeLimit: 1Gi' 1
expect_count "${rendered}" 'mountPath: /tmp' 1

echo "chart deployment operability cases passed"
