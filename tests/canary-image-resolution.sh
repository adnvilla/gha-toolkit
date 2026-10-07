#!/usr/bin/env bash
# Regression tests for the image resolution inside k8s-canary.yml's "Deploy canary phase" step.
#
# The step's `run:` body is extracted from the workflow and executed against a stubbed `helm`, so
# these tests exercise the shipped code instead of a copy of it. Non-dry-run resolution (reading the
# stable/canary images from the current Helm release) cannot be covered by test.yml's dry-run smoke
# jobs, which is how the stdin collision in gha-toolkit#32 shipped unnoticed.
#
# Usage: bash tests/canary-image-resolution.sh [path/to/k8s-canary.yml]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${1:-${REPO_ROOT}/.github/workflows/k8s-canary.yml}"
cd "${REPO_ROOT}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

STEP_SCRIPT="${WORK_DIR}/deploy-canary-phase.sh"
WORKFLOW="${WORKFLOW}" STEP_SCRIPT="${STEP_SCRIPT}" python3 <<'PY'
import os
import sys

import yaml

with open(os.environ["WORKFLOW"]) as fh:
    workflow = yaml.safe_load(fh)
steps = workflow["jobs"]["canary"]["steps"]
run = next((s["run"] for s in steps if s.get("name") == "Deploy canary phase"), None)
if run is None:
    sys.exit("step 'Deploy canary phase' not found in %s" % os.environ["WORKFLOW"])
with open(os.environ["STEP_SCRIPT"], "w") as fh:
    fh.write(run)
PY

# `helm` stub: answers whether the release exists, serves the fixture values, and records the
# arguments of the upgrade/template call so the assertions can inspect them.
STUB_DIR="${WORK_DIR}/bin"
mkdir -p "${STUB_DIR}"
cat > "${STUB_DIR}/helm" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${HELM_CALLS_FILE}"
case "$1" in
  status)
    [ "${FAKE_RELEASE_EXISTS}" == "true" ] || exit 1
    ;;
  get)
    cat "${FAKE_VALUES_FILE}"
    ;;
  upgrade|template)
    printf '%s\n' "$@" > "${HELM_ARGS_FILE}"
    ;;
  *)
    echo "unexpected helm invocation: $*" >&2
    exit 64
    ;;
esac
STUB
chmod +x "${STUB_DIR}/helm"

cat > "${STUB_DIR}/kubectl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KUBECTL_CALLS_FILE}"
if [ "$1" = "--context" ]; then
  shift 2
fi
case "$1" in
  get)
    if [ "${*: -1}" = "name" ]; then
      # Emulate the API server: the chart's canary Deployment *metadata* carries
      # instance=<release> + track=canary (not the pod template's instance=<release>-canary),
      # so only that exact selector returns it.
      if [[ " $* " == *" -l app.kubernetes.io/instance=service,app.kubernetes.io/track=canary "* ]]; then
        echo "deployment.apps/service-app-canary"
      fi
    elif [ -n "${FAKE_CANARY_DEPLOY_FILE:-}" ]; then
      cat "${FAKE_CANARY_DEPLOY_FILE}"
    fi
    ;;
  rollout)
    [ "${FAKE_ROLLOUT_FAILS:-false}" != "true" ] || exit 1
    ;;
  *)
    echo "unexpected kubectl invocation: $*" >&2
    exit 64
    ;;
esac
STUB
chmod +x "${STUB_DIR}/kubectl"

VALUES_WITH_IMAGES="${WORK_DIR}/values-with-images.json"
cat > "${VALUES_WITH_IMAGES}" <<'JSON'
{
  "image": {
    "repository": "registry.example.com/service",
    "tag": "stable-sha"
  },
  "canary": {
    "image": {
      "repository": "registry.example.com/service",
      "tag": "canary-sha"
    }
  }
}
JSON

# Live canary Deployment fixtures for the expected-canary-image promote guard.
write_canary_deploy() {
  local replicas="$1" image="$2"
  cat <<JSON
{"items": [{"metadata": {"name": "service-app-canary"},
  "spec": {"replicas": ${replicas}, "template": {"spec": {"containers": [
    {"name": "app", "image": "${image}"}, {"name": "sidecar", "image": "registry.example.com/proxy:1"}
  ]}}}}]}
JSON
}
CANARY_DEPLOY_MATCHING="${WORK_DIR}/canary-deploy-matching.json"
write_canary_deploy 1 registry.example.com/service:canary-sha > "${CANARY_DEPLOY_MATCHING}"
CANARY_DEPLOY_SCALED_DOWN="${WORK_DIR}/canary-deploy-scaled-down.json"
write_canary_deploy 0 registry.example.com/service:canary-sha > "${CANARY_DEPLOY_SCALED_DOWN}"
CANARY_DEPLOY_OTHER_IMAGE="${WORK_DIR}/canary-deploy-other-image.json"
write_canary_deploy 1 registry.example.com/service:newer-sha > "${CANARY_DEPLOY_OTHER_IMAGE}"
CANARY_DEPLOY_MISSING="${WORK_DIR}/canary-deploy-missing.json"
echo '{"items": []}' > "${CANARY_DEPLOY_MISSING}"

VALUES_WITHOUT_IMAGE="${WORK_DIR}/values-without-image.json"
echo '{"replicaCount": 2}' > "${VALUES_WITHOUT_IMAGE}"

VALUES_WITH_DIGEST_ONLY_CANARY="${WORK_DIR}/values-with-digest-only-canary.json"
cat > "${VALUES_WITH_DIGEST_ONLY_CANARY}" <<'JSON'
{
  "image": {
    "repository": "registry.example.com/service",
    "tag": "stable-sha"
  },
  "canary": {
    "image": {
      "digest": "sha256:canary"
    }
  }
}
JSON

VALUES_WITH_REPOSITORY_ONLY_CANARY="${WORK_DIR}/values-with-repository-only-canary.json"
cat > "${VALUES_WITH_REPOSITORY_ONLY_CANARY}" <<'JSON'
{
  "image": {
    "repository": "registry.example.com/service",
    "digest": "sha256:stable"
  },
  "canary": {
    "image": {
      "repository": "registry.example.com/canary"
    }
  }
}
JSON

HELM_ARGS_FILE="${WORK_DIR}/helm-args.txt"
HELM_CALLS_FILE="${WORK_DIR}/helm-calls.txt"
KUBECTL_CALLS_FILE="${WORK_DIR}/kubectl-calls.txt"
STEP_OUTPUT="${WORK_DIR}/step-output.txt"
STEP_LOG="${WORK_DIR}/step.log"

FAILURES=0
CASE_FAILURES=0

begin_case() {
  CASE_FAILURES=0
  echo "-- $1"
}

fail() {
  CASE_FAILURES=$((CASE_FAILURES + 1))
  echo "   $*"
}

end_case() {
  [ "${CASE_FAILURES}" -eq 0 ] && return 0
  FAILURES=$((FAILURES + 1))
  echo "   step log:"
  sed 's/^/     | /' "${STEP_LOG}"
  return 0
}

# Runs the extracted step. Callers set ACTION / IMAGE / STABLE_IMAGE_INPUT /
# FAKE_RELEASE_EXISTS / FAKE_VALUES_FILE beforehand.
run_step() {
  : > "${HELM_ARGS_FILE}"
  : > "${HELM_CALLS_FILE}"
  : > "${KUBECTL_CALLS_FILE}"
  : > "${STEP_OUTPUT}"
  set +e
  env \
    PATH="${STUB_DIR}:${PATH}" \
    HELM_ARGS_FILE="${HELM_ARGS_FILE}" \
    HELM_CALLS_FILE="${HELM_CALLS_FILE}" \
    KUBECTL_CALLS_FILE="${KUBECTL_CALLS_FILE}" \
    FAKE_RELEASE_EXISTS="${FAKE_RELEASE_EXISTS}" \
    FAKE_VALUES_FILE="${FAKE_VALUES_FILE}" \
    FAKE_CANARY_DEPLOY_FILE="${FAKE_CANARY_DEPLOY_FILE:-}" \
    FAKE_ROLLOUT_FAILS="${FAKE_ROLLOUT_FAILS:-false}" \
    EXPECTED_CANARY_IMAGE="${EXPECTED_CANARY_IMAGE:-}" \
    GITHUB_OUTPUT="${STEP_OUTPUT}" \
    USE_LOCAL_CHART=true \
    CHART_PATH=charts/app \
    RELEASE_NAME=service \
    NAMESPACE=service \
    VALUES_FILE=charts/app/values.yaml \
    IMAGE="${IMAGE}" \
    STABLE_IMAGE_INPUT="${STABLE_IMAGE_INPUT}" \
    ACTION="${ACTION}" \
    CANARY_WEIGHT=10 \
    CANARY_REPLICAS=1 \
    HELM_SET="" \
    WAIT="${WAIT}" \
    ATOMIC=false \
    TIMEOUT=180s \
    DRY_RUN="${DRY_RUN:-false}" \
    KUBE_CONTEXT=test-context \
    bash "${STEP_SCRIPT}" > "${STEP_LOG}" 2>&1
  STEP_STATUS=$?
  set -e
}

expect_success() {
  [ "${STEP_STATUS}" -eq 0 ] || fail "step exited ${STEP_STATUS}, expected 0"
  ! grep -q 'Traceback (most recent call last)' "${STEP_LOG}" \
    || fail "step printed a Python traceback"
  while IFS= read -r call; do
    [ -z "${call}" ] && continue
    [[ "${call}" == *"--kube-context test-context"* ]] \
      || fail "helm call did not select test-context: ${call}"
  done < "${HELM_CALLS_FILE}"
  while IFS= read -r call; do
    [ -z "${call}" ] && continue
    [[ "${call}" == "--context test-context "* ]] \
      || fail "kubectl call did not select test-context: ${call}"
  done < "${KUBECTL_CALLS_FILE}"
}

# helm receives `--set` and `KEY=VALUE` as separate argv entries, one per recorded line.
expect_helm_set() {
  grep -Fxq "$1" "${HELM_ARGS_FILE}" || fail "missing helm --set $1"
}

expect_no_helm_set_key() {
  ! grep -Fq -- "$1=" "${HELM_ARGS_FILE}" || fail "unexpected helm --set key $1"
}

expect_step_output() {
  grep -Fxq "$1" "${STEP_OUTPUT}" || fail "missing step output '$1'"
}

expect_failure_before_helm() {
  [ "${STEP_STATUS}" -ne 0 ] || fail "step exited 0, expected a failure"
  [ ! -s "${HELM_ARGS_FILE}" ] || fail "helm upgrade/template ran despite the failed check"
  grep -Fq -- "$1" "${STEP_LOG}" || fail "step log does not mention '$1'"
}

expect_kubectl_call() {
  grep -Fq -- "$1" "${KUBECTL_CALLS_FILE}" || fail "missing kubectl call matching '$1'"
}

begin_case "deploy resolves the stable image from the current release"
ACTION=deploy
IMAGE=registry.example.com/service:canary-sha
STABLE_IMAGE_INPUT=""
FAKE_RELEASE_EXISTS=true
WAIT=false
FAKE_VALUES_FILE="${VALUES_WITH_IMAGES}"
run_step
expect_success
expect_helm_set "image.repository=registry.example.com/service"
expect_helm_set "image.tag=stable-sha"
expect_helm_set "canary.image.tag=canary-sha"
expect_helm_set "canary.replicas=1"
expect_helm_set "canary.weight=10"
expect_step_output "stable-image=registry.example.com/service:stable-sha"
end_case

begin_case "abort resolves the canary image from the current release"
ACTION=abort
IMAGE=""
STABLE_IMAGE_INPUT=""
FAKE_RELEASE_EXISTS=true
FAKE_VALUES_FILE="${VALUES_WITH_IMAGES}"
run_step
expect_success
expect_helm_set "image.tag=stable-sha"
expect_helm_set "canary.image.tag=canary-sha"
expect_helm_set "canary.replicas=0"
expect_helm_set "canary.weight=0"
expect_step_output "image=registry.example.com/service:canary-sha"
end_case

begin_case "abort preserves a digest-only canary image from the current release"
ACTION=abort
IMAGE=""
STABLE_IMAGE_INPUT=""
FAKE_RELEASE_EXISTS=true
FAKE_VALUES_FILE="${VALUES_WITH_DIGEST_ONLY_CANARY}"
run_step
expect_success
expect_helm_set "canary.image.repository=registry.example.com/service"
expect_no_helm_set_key "image.digest"
expect_no_helm_set_key "canary.image.digest"
expect_step_output "image=registry.example.com/service@sha256:canary"
end_case

begin_case "abort gives a repository-only canary image a usable tag"
ACTION=abort
IMAGE=""
STABLE_IMAGE_INPUT=""
FAKE_RELEASE_EXISTS=true
FAKE_VALUES_FILE="${VALUES_WITH_REPOSITORY_ONLY_CANARY}"
run_step
expect_success
expect_helm_set "canary.image.repository=registry.example.com/canary"
expect_helm_set "canary.image.tag=latest"
expect_step_output "image=registry.example.com/canary:latest"
end_case

begin_case "explicit stable-image wins over the current release"
ACTION=deploy
IMAGE=registry.example.com/service:canary-sha
STABLE_IMAGE_INPUT=registry.example.com/service:pinned-sha
FAKE_RELEASE_EXISTS=true
FAKE_VALUES_FILE="${VALUES_WITH_IMAGES}"
run_step
expect_success
expect_helm_set "image.tag=pinned-sha"
end_case

begin_case "deploy falls back to the canary image when no release exists"
ACTION=deploy
IMAGE=registry.example.com/service:first-sha
STABLE_IMAGE_INPUT=""
FAKE_RELEASE_EXISTS=false
FAKE_VALUES_FILE="${VALUES_WITH_IMAGES}"
run_step
expect_success
expect_helm_set "image.tag=first-sha"
expect_helm_set "canary.image.tag=first-sha"
end_case

begin_case "a release without an image key falls back instead of failing the step"
ACTION=deploy
IMAGE=registry.example.com/service:new-sha
STABLE_IMAGE_INPUT=""
FAKE_RELEASE_EXISTS=true
FAKE_VALUES_FILE="${VALUES_WITHOUT_IMAGE}"
run_step
expect_success
expect_helm_set "image.tag=new-sha"
end_case

begin_case "deploy with wait selects the chart's canary Deployment and waits for its rollout"
ACTION=deploy
IMAGE=registry.example.com/service:new-sha
STABLE_IMAGE_INPUT=""
FAKE_RELEASE_EXISTS=true
FAKE_VALUES_FILE="${VALUES_WITH_IMAGES}"
WAIT=true
run_step
expect_success
expect_kubectl_call "--context test-context get deploy -n service -l app.kubernetes.io/instance=service,app.kubernetes.io/track=canary -o name"
expect_kubectl_call "--context test-context rollout status deployment.apps/service-app-canary -n service --timeout=180s"
end_case

begin_case "deploy with wait fails the step when the canary rollout fails"
FAKE_ROLLOUT_FAILS=true
run_step
[ "${STEP_STATUS}" -ne 0 ] || fail "step exited 0 despite a failed canary rollout"
FAKE_ROLLOUT_FAILS=false
WAIT=false
end_case

begin_case "promote without expected-canary-image does not inspect the live canary"
ACTION=promote
IMAGE=registry.example.com/service:canary-sha
STABLE_IMAGE_INPUT=""
FAKE_RELEASE_EXISTS=true
FAKE_VALUES_FILE="${VALUES_WITH_IMAGES}"
EXPECTED_CANARY_IMAGE=""
FAKE_CANARY_DEPLOY_FILE="${CANARY_DEPLOY_MISSING}"
run_step
expect_success
[ ! -s "${KUBECTL_CALLS_FILE}" ] || fail "kubectl was called without expected-canary-image"
expect_helm_set "image.tag=canary-sha"
expect_helm_set "canary.replicas=0"
end_case

begin_case "promote with a matching live canary proceeds to helm"
EXPECTED_CANARY_IMAGE=registry.example.com/service:canary-sha
FAKE_CANARY_DEPLOY_FILE="${CANARY_DEPLOY_MATCHING}"
run_step
expect_success
expect_kubectl_call "--context test-context get deploy -n service -l app.kubernetes.io/instance=service,app.kubernetes.io/track=canary"
expect_helm_set "image.tag=canary-sha"
expect_helm_set "canary.replicas=0"
end_case

begin_case "promote fails before helm when the canary Deployment is missing"
FAKE_CANARY_DEPLOY_FILE="${CANARY_DEPLOY_MISSING}"
run_step
expect_failure_before_helm "no canary Deployment found"
end_case

begin_case "promote fails before helm when the canary is scaled to 0"
FAKE_CANARY_DEPLOY_FILE="${CANARY_DEPLOY_SCALED_DOWN}"
run_step
expect_failure_before_helm "has 0 replicas"
end_case

begin_case "promote fails before helm when the canary runs another image"
FAKE_CANARY_DEPLOY_FILE="${CANARY_DEPLOY_OTHER_IMAGE}"
run_step
expect_failure_before_helm "runs 'registry.example.com/service:newer-sha'"
end_case

begin_case "promote dry-run skips the live canary check"
FAKE_CANARY_DEPLOY_FILE="${CANARY_DEPLOY_MISSING}"
DRY_RUN=true
run_step
# `helm template` never takes --kube-context, so expect_success's context check does not apply.
[ "${STEP_STATUS}" -eq 0 ] || fail "step exited ${STEP_STATUS}, expected 0"
grep -Fq "skipping expected-canary-image check" "${STEP_LOG}" || fail "missing dry-run skip notice"
[ ! -s "${KUBECTL_CALLS_FILE}" ] || fail "kubectl was called on dry-run"
DRY_RUN=false
EXPECTED_CANARY_IMAGE=""
FAKE_CANARY_DEPLOY_FILE=""
end_case

if [ "${FAILURES}" -ne 0 ]; then
  echo "${FAILURES} case(s) failed"
  exit 1
fi
echo "all cases passed"
