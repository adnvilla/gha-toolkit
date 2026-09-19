#!/usr/bin/env bash
# Regression tests for image-reference parsing in all three Kubernetes workflows.
#
# Each workflow step's `run:` body is extracted from YAML and executed in dry-run mode against the
# real chart. Assertions inspect the rendered Pod image, so they cover both parsing and recomposition.
#
# Usage: bash tests/k8s-image-references.sh [deploy-workflow] [canary-workflow] [bluegreen-workflow]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
cd "${REPO_ROOT}"

DEPLOY_WORKFLOW="${1:-.github/workflows/k8s-deploy.yml}"
CANARY_WORKFLOW="${2:-.github/workflows/k8s-canary.yml}"
BLUEGREEN_WORKFLOW="${3:-.github/workflows/k8s-bluegreen.yml}"

extract_step() {
  local workflow="$1"
  local job="$2"
  local step_name="$3"
  local destination="$4"
  WORKFLOW="${workflow}" JOB="${job}" STEP_NAME="${step_name}" DESTINATION="${destination}" \
    python3 <<'PY'
import os
import sys

import yaml

with open(os.environ["WORKFLOW"]) as fh:
    workflow = yaml.safe_load(fh)
steps = workflow["jobs"][os.environ["JOB"]]["steps"]
run = next((step["run"] for step in steps if step.get("name") == os.environ["STEP_NAME"]), None)
if run is None:
    sys.exit("step %r not found in %s" % (os.environ["STEP_NAME"], os.environ["WORKFLOW"]))
with open(os.environ["DESTINATION"], "w") as fh:
    fh.write(run)
PY
}

DEPLOY_SCRIPT="${WORK_DIR}/deploy.sh"
CANARY_SCRIPT="${WORK_DIR}/canary.sh"
BLUEGREEN_SCRIPT="${WORK_DIR}/bluegreen.sh"
extract_step "${DEPLOY_WORKFLOW}" "deploy" "Deploy with Helm" "${DEPLOY_SCRIPT}"
extract_step "${CANARY_WORKFLOW}" "canary" "Deploy canary phase" "${CANARY_SCRIPT}"
extract_step \
  "${BLUEGREEN_WORKFLOW}" "bluegreen" "Deploy blue/green phase" "${BLUEGREEN_SCRIPT}"

FAILURES=0

expect_rendered_image() {
  local workflow_name="$1"
  local log_file="$2"
  local expected="$3"
  if ! grep -Fq "image: \"${expected}\"" "${log_file}"; then
    echo "FAIL: ${workflow_name} did not render image ${expected}"
    sed 's/^/  | /' "${log_file}"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_chart_image() {
  local description="$1"
  local rendered="$2"
  local expected="$3"
  if ! grep -Fq "image: \"${expected}\"" <<< "${rendered}"; then
    echo "FAIL: ${description} did not render image ${expected}"
    printf '%s\n' "${rendered}" | sed 's/^/  | /'
    FAILURES=$((FAILURES + 1))
  fi
}

run_deploy() {
  local image="$1"
  local expected="$2"
  local log_file="${WORK_DIR}/deploy.log"
  env \
    USE_LOCAL_CHART=true \
    CHART_PATH=charts/app \
    RELEASE_NAME=service \
    NAMESPACE=service \
    VALUES_FILE=charts/app/values.yaml \
    IMAGE="${image}" \
    MIGRATIONS="" \
    HELM_SET="" \
    WAIT=false \
    ATOMIC=false \
    TIMEOUT=180s \
    DRY_RUN=true \
    bash "${DEPLOY_SCRIPT}" > "${log_file}" 2>&1
  expect_rendered_image "k8s-deploy" "${log_file}" "${expected}"
}

run_canary() {
  local image="$1"
  local expected="$2"
  local log_file="${WORK_DIR}/canary.log"
  local output_file="${WORK_DIR}/canary-output.txt"
  : > "${output_file}"
  env \
    GITHUB_OUTPUT="${output_file}" \
    USE_LOCAL_CHART=true \
    CHART_PATH=charts/app \
    RELEASE_NAME=service \
    NAMESPACE=service \
    VALUES_FILE=charts/app/values.yaml \
    IMAGE="${image}" \
    STABLE_IMAGE_INPUT="" \
    ACTION=deploy \
    CANARY_WEIGHT=10 \
    CANARY_REPLICAS=1 \
    HELM_SET="" \
    WAIT=false \
    ATOMIC=false \
    TIMEOUT=180s \
    DRY_RUN=true \
    bash "${CANARY_SCRIPT}" > "${log_file}" 2>&1
  expect_rendered_image "k8s-canary" "${log_file}" "${expected}"
}

run_bluegreen() {
  local image="$1"
  local expected="$2"
  local log_file="${WORK_DIR}/bluegreen.log"
  local output_file="${WORK_DIR}/bluegreen-output.txt"
  : > "${output_file}"
  env \
    GITHUB_OUTPUT="${output_file}" \
    USE_LOCAL_CHART=true \
    CHART_PATH=charts/app \
    RELEASE_NAME=service \
    NAMESPACE=service \
    VALUES_FILE=charts/app/values.yaml \
    IMAGE="${image}" \
    ACTION=deploy \
    ACTIVE_SLOT_INPUT=blue \
    ACTIVE_REPLICAS=1 \
    INACTIVE_REPLICAS=1 \
    OVERLAP_SECONDS=0 \
    PREVIEW=false \
    VERIFY_URL="" \
    VERIFY_EXPECT_STATUS=200 \
    VERIFY_TIMEOUT_SECONDS=10 \
    VERIFY_INTERVAL_SECONDS=1 \
    AUTO_ABORT=false \
    HELM_SET="" \
    WAIT=false \
    ATOMIC=false \
    TIMEOUT=180s \
    DRY_RUN=true \
    bash "${BLUEGREEN_SCRIPT}" > "${log_file}" 2>&1
  expect_rendered_image "k8s-bluegreen" "${log_file}" "${expected}"
}

run_case() {
  local description="$1"
  local image="$2"
  local expected="$3"
  echo "-- ${description}"
  run_deploy "${image}" "${expected}"
  run_canary "${image}" "${expected}"
  run_bluegreen "${image}" "${expected}"
}

run_case \
  "tagged reference" \
  "registry.example.com/service:v1" \
  "registry.example.com/service:v1"
run_case \
  "tagged reference from a registry with a port" \
  "registry.example.local:5000/service:v1" \
  "registry.example.local:5000/service:v1"
run_case \
  "digest reference" \
  "registry.example.com/service@sha256:abcdef" \
  "registry.example.com/service@sha256:abcdef"
run_case \
  "untagged reference from a registry with a port" \
  "registry.example.local:5000/service" \
  "registry.example.local:5000/service"
run_case \
  "untagged reference without a registry port" \
  "registry.example.com/service" \
  "registry.example.com/service:latest"

# A child image with a repository or tag is an explicit override. It must not inherit a top-level
# digest, because doing so would render the child repository at the parent's immutable bytes.
echo "-- tagged child images clear a top-level digest"
canary_rendered="$(helm template child-digest-canary charts/app \
  --set image.repository=registry.example.com/stable \
  --set image.digest=sha256:stable \
  --set strategy.mode=canary \
  --set canary.image.repository=registry.example.com/canary \
  --set canary.image.tag=v2)"
expect_chart_image \
  "canary tagged child override" \
  "${canary_rendered}" \
  "registry.example.com/canary:v2"

bluegreen_rendered="$(helm template child-digest-bluegreen charts/app \
  --set image.repository=registry.example.com/stable \
  --set image.digest=sha256:stable \
  --set strategy.mode=blueGreen \
  --set blueGreen.blue.image.repository=registry.example.com/blue \
  --set blueGreen.blue.image.tag=v2 \
  --set blueGreen.green.image.repository=registry.example.com/green \
  --set blueGreen.green.image.tag=v2)"
expect_chart_image \
  "blue-green tagged child override" \
  "${bluegreen_rendered}" \
  "registry.example.com/blue:v2"
expect_chart_image \
  "blue-green tagged child override" \
  "${bluegreen_rendered}" \
  "registry.example.com/green:v2"

job_rendered="$(helm template child-digest-job charts/app \
  --set image.repository=registry.example.com/stable \
  --set image.digest=sha256:stable \
  --set job.enabled=true \
  --set job.name=work \
  --set job.image.repository=registry.example.com/job \
  --set job.image.tag=v2 \
  --show-only templates/job.yaml)"
expect_chart_image \
  "job tagged child override" \
  "${job_rendered}" \
  "registry.example.com/job:v2"

job_repository_only_rendered="$(helm template child-digest-job-repository-only charts/app \
  --set image.repository=registry.example.com/stable \
  --set image.digest=sha256:stable \
  --set job.enabled=true \
  --set job.name=work \
  --set job.image.repository=registry.example.com/job \
  --show-only templates/job.yaml)"
expect_chart_image \
  "job repository-only child override keeps a usable tag" \
  "${job_repository_only_rendered}" \
  "registry.example.com/job:latest"

if [ "${FAILURES}" -ne 0 ]; then
  echo "${FAILURES} assertion(s) failed"
  exit 1
fi
echo "all cases passed"
