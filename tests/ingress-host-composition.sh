#!/usr/bin/env bash
# Regression tests for composing ingress.host from prefix + INGRESS_BASE_DOMAIN.
#
# Each workflow step's `run:` body is extracted from YAML and executed in dry-run mode against the
# real chart. Assertions inspect the rendered Ingress host so a values-file host is not clobbered
# and composition is skipped when the base domain is missing or use-local-chart is true.
#
# Usage: bash tests/ingress-host-composition.sh [deploy-workflow] [canary-workflow] [bluegreen-workflow]
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

mkdir -p "${WORK_DIR}/.gha-toolkit-chart"
ln -s "${REPO_ROOT}/charts" "${WORK_DIR}/.gha-toolkit-chart/charts"

VALUES_COMPOSE="${WORK_DIR}/values-compose.yaml"
cat > "${VALUES_COMPOSE}" <<'YAML'
ingress:
  enabled: true
YAML

VALUES_HOST="${WORK_DIR}/values-host.yaml"
cat > "${VALUES_HOST}" <<'YAML'
ingress:
  enabled: true
  host: already.set.example
YAML

VALUES_EMPTY_HOST="${WORK_DIR}/values-empty-host.yaml"
cat > "${VALUES_EMPTY_HOST}" <<'YAML'
ingress:
  enabled: true
  host: ""
YAML

VALUES_CANARY="${WORK_DIR}/values-canary.yaml"
cat > "${VALUES_CANARY}" <<'YAML'
ingress:
  enabled: true
canary:
  ingress:
    enabled: true
YAML

VALUES_PREVIEW="${WORK_DIR}/values-preview.yaml"
cat > "${VALUES_PREVIEW}" <<'YAML'
ingress:
  enabled: true
blueGreen:
  preview:
    ingress:
      enabled: true
YAML

FAILURES=0
LOG_FILE="${WORK_DIR}/render.log"

fail() {
  echo "FAIL: $*"
  sed 's/^/  | /' "${LOG_FILE}"
  FAILURES=$((FAILURES + 1))
}

expect_host() {
  local expected="$1"
  grep -Fq "host: \"${expected}\"" "${LOG_FILE}" \
    || fail "rendered output missing host ${expected}"
}

expect_no_host() {
  local unexpected="$1"
  ! grep -Fq "host: \"${unexpected}\"" "${LOG_FILE}" \
    || fail "rendered output unexpectedly contains host ${unexpected}"
}

# INGRESS_BASE_DOMAIN / INGRESS_BASE_DOMAIN_VAR are always set (possibly empty) so a
# runner that already exports the cluster domain cannot leak into these cases.
common_env() {
  env \
    RUNNER_TEMP="${WORK_DIR}" \
    USE_LOCAL_CHART="${USE_LOCAL_CHART}" \
    CHART_PATH=charts/app \
    RELEASE_NAME="${RELEASE_NAME:-service}" \
    NAMESPACE=service \
    VALUES_FILE="${VALUES_FILE}" \
    IMAGE=registry.example.local:5000/service:v1 \
    MIGRATIONS="" \
    HELM_SET="${HELM_SET:-}" \
    INGRESS_PREFIX="${INGRESS_PREFIX:-}" \
    INGRESS_BASE_DOMAIN="${INGRESS_BASE_DOMAIN:-}" \
    INGRESS_BASE_DOMAIN_VAR="${INGRESS_BASE_DOMAIN_VAR:-}" \
    WAIT=false \
    ATOMIC=false \
    TIMEOUT=180s \
    DRY_RUN=true \
    GITHUB_OUTPUT="${WORK_DIR}/github-output.txt" \
    STABLE_IMAGE_INPUT="" \
    ACTION="${ACTION:-deploy}" \
    CANARY_WEIGHT=10 \
    CANARY_REPLICAS=1 \
    ACTIVE_SLOT_INPUT=blue \
    ACTIVE_REPLICAS=1 \
    INACTIVE_REPLICAS=1 \
    OVERLAP_SECONDS=0 \
    PREVIEW="${PREVIEW:-false}" \
    VERIFY_URL="" \
    VERIFY_EXPECT_STATUS=200 \
    VERIFY_TIMEOUT_SECONDS=10 \
    VERIFY_INTERVAL_SECONDS=1 \
    AUTO_ABORT=false \
    "$@"
}

run_deploy() {
  : > "${WORK_DIR}/github-output.txt"
  common_env bash "${DEPLOY_SCRIPT}" > "${LOG_FILE}" 2>&1
}

run_canary() {
  : > "${WORK_DIR}/github-output.txt"
  common_env bash "${CANARY_SCRIPT}" > "${LOG_FILE}" 2>&1
}

run_bluegreen() {
  : > "${WORK_DIR}/github-output.txt"
  common_env bash "${BLUEGREEN_SCRIPT}" > "${LOG_FILE}" 2>&1
}

reset_case() {
  USE_LOCAL_CHART=false
  RELEASE_NAME=service
  VALUES_FILE="${VALUES_COMPOSE}"
  HELM_SET=""
  INGRESS_PREFIX=""
  INGRESS_BASE_DOMAIN=""
  INGRESS_BASE_DOMAIN_VAR=""
  ACTION=deploy
  PREVIEW=false
}

begin_case() {
  reset_case
  echo "-- $1"
}

begin_case "composes ingress.host from release-name + runner env"
INGRESS_BASE_DOMAIN=cluster.test
cd "${WORK_DIR}"
run_deploy
expect_host "service.cluster.test"
expect_no_host "already.set.example"

begin_case "uses ingress-prefix when set"
INGRESS_PREFIX=api
INGRESS_BASE_DOMAIN=cluster.test
cd "${WORK_DIR}"
run_deploy
expect_host "api.cluster.test"

begin_case "prefers vars.INGRESS_BASE_DOMAIN over the runner env"
INGRESS_PREFIX=api
INGRESS_BASE_DOMAIN=from.runner.test
INGRESS_BASE_DOMAIN_VAR=from.vars.test
cd "${WORK_DIR}"
run_deploy
expect_host "api.from.vars.test"
expect_no_host "api.from.runner.test"

begin_case "does not clobber an existing ingress.host in values"
INGRESS_BASE_DOMAIN=cluster.test
VALUES_FILE="${VALUES_HOST}"
cd "${WORK_DIR}"
run_deploy
expect_host "already.set.example"
expect_no_host "service.cluster.test"

begin_case "does not clobber an explicit empty ingress.host"
INGRESS_BASE_DOMAIN=cluster.test
VALUES_FILE="${VALUES_EMPTY_HOST}"
cd "${WORK_DIR}"
run_deploy
expect_host ""
expect_no_host "service.cluster.test"

begin_case "skips composition when the base domain is unset"
cd "${WORK_DIR}"
run_deploy
expect_no_host "service.cluster.test"
expect_host ""

begin_case "skips composition for a local chart"
USE_LOCAL_CHART=true
INGRESS_BASE_DOMAIN=cluster.test
cd "${REPO_ROOT}"
VALUES_FILE="${VALUES_COMPOSE}"
run_deploy
expect_no_host "service.cluster.test"
expect_host ""

begin_case "helm-set still wins over the composed host"
INGRESS_PREFIX=api
INGRESS_BASE_DOMAIN=cluster.test
HELM_SET="ingress.host=from.set.example"
cd "${WORK_DIR}"
run_deploy
expect_host "from.set.example"
expect_no_host "api.cluster.test"

begin_case "canary derives canary.<composed host>"
INGRESS_PREFIX=api
INGRESS_BASE_DOMAIN=cluster.test
VALUES_FILE="${VALUES_CANARY}"
cd "${WORK_DIR}"
run_canary
expect_host "api.cluster.test"
expect_host "canary.api.cluster.test"

begin_case "bluegreen derives preview.<composed host>"
INGRESS_PREFIX=api
INGRESS_BASE_DOMAIN=cluster.test
VALUES_FILE="${VALUES_PREVIEW}"
PREVIEW=true
cd "${WORK_DIR}"
run_bluegreen
expect_host "api.cluster.test"
expect_host "preview.api.cluster.test"

if [ "${FAILURES}" -ne 0 ]; then
  echo "${FAILURES} assertion(s) failed"
  exit 1
fi
echo "all cases passed"
