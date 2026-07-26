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

VALUES_WITHOUT_IMAGE="${WORK_DIR}/values-without-image.json"
echo '{"replicaCount": 2}' > "${VALUES_WITHOUT_IMAGE}"

HELM_ARGS_FILE="${WORK_DIR}/helm-args.txt"
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
  : > "${STEP_OUTPUT}"
  set +e
  env \
    PATH="${STUB_DIR}:${PATH}" \
    HELM_ARGS_FILE="${HELM_ARGS_FILE}" \
    FAKE_RELEASE_EXISTS="${FAKE_RELEASE_EXISTS}" \
    FAKE_VALUES_FILE="${FAKE_VALUES_FILE}" \
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
    WAIT=false \
    ATOMIC=false \
    TIMEOUT=180s \
    DRY_RUN=false \
    bash "${STEP_SCRIPT}" > "${STEP_LOG}" 2>&1
  STEP_STATUS=$?
  set -e
}

expect_success() {
  [ "${STEP_STATUS}" -eq 0 ] || fail "step exited ${STEP_STATUS}, expected 0"
  ! grep -q 'Traceback (most recent call last)' "${STEP_LOG}" \
    || fail "step printed a Python traceback"
}

# helm receives `--set` and `KEY=VALUE` as separate argv entries, one per recorded line.
expect_helm_set() {
  grep -Fxq "$1" "${HELM_ARGS_FILE}" || fail "missing helm --set $1"
}

expect_step_output() {
  grep -Fxq "$1" "${STEP_OUTPUT}" || fail "missing step output '$1'"
}

begin_case "deploy resolves the stable image from the current release"
ACTION=deploy
IMAGE=registry.example.com/service:canary-sha
STABLE_IMAGE_INPUT=""
FAKE_RELEASE_EXISTS=true
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

if [ "${FAILURES}" -ne 0 ]; then
  echo "${FAILURES} case(s) failed"
  exit 1
fi
echo "all cases passed"
