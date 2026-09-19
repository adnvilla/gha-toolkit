#!/usr/bin/env bash
# Regression tests for the slot bookkeeping inside k8s-bluegreen.yml's "Deploy blue/green phase"
# step: which slot receives the image, which replica counts are rendered, where the Service ends up
# pointing, and what the verify/auto-abort health gate does.
#
# The step's `run:` body is extracted from the workflow and executed against stubbed `helm` and
# `curl`, so these tests exercise the shipped code instead of a copy of it. Everything here is on
# the non-dry-run path (reading the live release with `helm get values`), which test.yml's dry-run
# smoke jobs can never reach.
#
# Usage: bash tests/bluegreen-slot-flip.sh [path/to/k8s-bluegreen.yml]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${1:-${REPO_ROOT}/.github/workflows/k8s-bluegreen.yml}"
cd "${REPO_ROOT}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

STEP_SCRIPT="${WORK_DIR}/deploy-bluegreen-phase.sh"
WORKFLOW="${WORKFLOW}" STEP_SCRIPT="${STEP_SCRIPT}" python3 <<'PY'
import os
import sys

import yaml

with open(os.environ["WORKFLOW"]) as fh:
    workflow = yaml.safe_load(fh)
steps = workflow["jobs"]["bluegreen"]["steps"]
run = next((s["run"] for s in steps if s.get("name") == "Deploy blue/green phase"), None)
if run is None:
    sys.exit("step 'Deploy blue/green phase' not found in %s" % os.environ["WORKFLOW"])
with open(os.environ["STEP_SCRIPT"], "w") as fh:
    fh.write(run)
PY

STUB_DIR="${WORK_DIR}/bin"
mkdir -p "${STUB_DIR}"

# `helm` stub: serves the fixture release values and records every upgrade/template call. The last
# call lands in HELM_ARGS_FILE; HELM_CALLS_FILE counts them (auto-abort applies twice).
cat > "${STUB_DIR}/helm" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${HELM_COMMANDS_FILE}"
case "$1" in
  status)
    [ "${FAKE_RELEASE_EXISTS}" == "true" ] || exit 1
    ;;
  get)
    cat "${FAKE_VALUES_FILE}"
    ;;
  upgrade|template)
    printf '%s\n' "$@" > "${HELM_ARGS_FILE}"
    echo "call" >> "${HELM_CALLS_FILE}"
    ;;
  *)
    echo "unexpected helm invocation: $*" >&2
    exit 64
    ;;
esac
STUB
chmod +x "${STUB_DIR}/helm"

# `curl` stub for the verify gate: always answers with FAKE_HTTP_STATUS.
cat > "${STUB_DIR}/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s' "${FAKE_HTTP_STATUS:-200}"
STUB
chmod +x "${STUB_DIR}/curl"

# `sleep` stub so the verify retry loop and the promote overlap window cost no wall-clock time.
cat > "${STUB_DIR}/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "${STUB_DIR}/sleep"

# Live release: green is active on v1, blue holds the previous version and is scaled to 0.
GREEN_ACTIVE_VALUES="${WORK_DIR}/green-active.json"
cat > "${GREEN_ACTIVE_VALUES}" <<'JSON'
{
  "image": {
    "repository": "registry.example.com/worker",
    "tag": "v1"
  },
  "blueGreen": {
    "activeSlot": "green",
    "blue": {
      "replicas": 0,
      "image": {
        "repository": "registry.example.com/worker",
        "tag": "v0"
      }
    },
    "green": {
      "replicas": 2,
      "image": {
        "repository": "registry.example.com/worker",
        "tag": "v1"
      }
    }
  }
}
JSON

# Same topology as above, but the active slot is immutable. Abort must return this exact reference.
GREEN_ACTIVE_DIGEST_VALUES="${WORK_DIR}/green-active-digest.json"
cat > "${GREEN_ACTIVE_DIGEST_VALUES}" <<'JSON'
{
  "image": {
    "repository": "registry.example.com/worker",
    "digest": "sha256:active"
  },
  "blueGreen": {
    "activeSlot": "green",
    "blue": {
      "replicas": 0,
      "image": {
        "repository": "registry.example.com/worker",
        "tag": "v0"
      }
    },
    "green": {
      "replicas": 2,
      "image": {
        "repository": "registry.example.com/worker",
        "digest": "sha256:active"
      }
    }
  }
}
JSON

GREEN_ACTIVE_REPOSITORY_ONLY_VALUES="${WORK_DIR}/green-active-repository-only.json"
cat > "${GREEN_ACTIVE_REPOSITORY_ONLY_VALUES}" <<'JSON'
{
  "image": {
    "repository": "registry.example.com/worker",
    "digest": "sha256:stable"
  },
  "blueGreen": {
    "activeSlot": "green",
    "blue": {
      "replicas": 0,
      "image": {
        "repository": "registry.example.com/worker",
        "tag": "v0"
      }
    },
    "green": {
      "replicas": 2,
      "image": {
        "repository": "registry.example.com/green-worker"
      }
    }
  }
}
JSON

HELM_ARGS_FILE="${WORK_DIR}/helm-args.txt"
HELM_CALLS_FILE="${WORK_DIR}/helm-calls.txt"
HELM_COMMANDS_FILE="${WORK_DIR}/helm-commands.txt"
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

# Runs the extracted step. Callers set ACTION / IMAGE and may override PREVIEW, VERIFY_URL,
# FAKE_HTTP_STATUS, AUTO_ABORT and OVERLAP_SECONDS before calling.
run_step() {
  : > "${HELM_ARGS_FILE}"
  : > "${HELM_CALLS_FILE}"
  : > "${HELM_COMMANDS_FILE}"
  : > "${STEP_OUTPUT}"
  set +e
  env \
    PATH="${STUB_DIR}:${PATH}" \
    HELM_ARGS_FILE="${HELM_ARGS_FILE}" \
    HELM_CALLS_FILE="${HELM_CALLS_FILE}" \
    HELM_COMMANDS_FILE="${HELM_COMMANDS_FILE}" \
    FAKE_RELEASE_EXISTS=true \
    FAKE_VALUES_FILE="${LIVE_VALUES_FILE}" \
    FAKE_HTTP_STATUS="${FAKE_HTTP_STATUS:-200}" \
    GITHUB_OUTPUT="${STEP_OUTPUT}" \
    USE_LOCAL_CHART=true \
    CHART_PATH=charts/app \
    RELEASE_NAME=worker \
    NAMESPACE=worker \
    VALUES_FILE=charts/app/values.yaml \
    IMAGE="${IMAGE}" \
    ACTION="${ACTION}" \
    ACTIVE_SLOT_INPUT="" \
    ACTIVE_REPLICAS=2 \
    INACTIVE_REPLICAS=1 \
    OVERLAP_SECONDS="${OVERLAP_SECONDS:-0}" \
    PREVIEW="${PREVIEW:-false}" \
    VERIFY_URL="${VERIFY_URL:-}" \
    VERIFY_EXPECT_STATUS=200 \
    VERIFY_TIMEOUT_SECONDS=3 \
    VERIFY_INTERVAL_SECONDS=1 \
    AUTO_ABORT="${AUTO_ABORT:-false}" \
    HELM_SET="" \
    WAIT=false \
    ATOMIC=false \
    TIMEOUT=180s \
    DRY_RUN=false \
    KUBE_CONTEXT=test-context \
    bash "${STEP_SCRIPT}" > "${STEP_LOG}" 2>&1
  STEP_STATUS=$?
  set -e
}

reset_env() {
  ACTION=""
  IMAGE=""
  PREVIEW=false
  VERIFY_URL=""
  FAKE_HTTP_STATUS=200
  AUTO_ABORT=false
  OVERLAP_SECONDS=0
  LIVE_VALUES_FILE="${GREEN_ACTIVE_VALUES}"
}

expect_success() {
  [ "${STEP_STATUS}" -eq 0 ] || fail "step exited ${STEP_STATUS}, expected 0"
  ! grep -q 'Traceback (most recent call last)' "${STEP_LOG}" \
    || fail "step printed a Python traceback"
  expect_helm_contexts
}

expect_failure() {
  [ "${STEP_STATUS}" -ne 0 ] || fail "step exited 0, expected a failure"
  expect_helm_contexts
}

expect_helm_contexts() {
  while IFS= read -r call; do
    [ -z "${call}" ] && continue
    [[ "${call}" == *"--kube-context test-context"* ]] \
      || fail "helm call did not select test-context: ${call}"
  done < "${HELM_COMMANDS_FILE}"
}

# helm receives `--set` and `KEY=VALUE` as separate argv entries, one per recorded line.
expect_helm_set() {
  grep -Fxq "$1" "${HELM_ARGS_FILE}" || fail "missing helm --set $1"
}

expect_no_helm_set() {
  ! grep -Fxq "$1" "${HELM_ARGS_FILE}" || fail "unexpected helm --set $1"
}

expect_helm_calls() {
  local want="$1"
  local got
  got="$(wc -l < "${HELM_CALLS_FILE}" | tr -d ' ')"
  [ "${got}" = "${want}" ] || fail "helm applied ${got} time(s), expected ${want}"
}

expect_step_output() {
  grep -Fxq "$1" "${STEP_OUTPUT}" || fail "missing step output '$1'"
}

reset_env
begin_case "deploy ships the inactive slot and leaves the active one serving"
ACTION=deploy
IMAGE=registry.example.com/worker:v2
run_step
expect_success
expect_helm_set "blueGreen.activeSlot=green"
expect_helm_set "blueGreen.blue.image.tag=v2"
expect_helm_set "blueGreen.blue.replicas=1"
expect_helm_set "blueGreen.green.image.tag=v1"
expect_helm_set "blueGreen.green.replicas=2"
expect_helm_set "image.tag=v1"
expect_step_output "active-slot=green"
expect_step_output "inactive-slot=blue"
expect_step_output "deployed-slot=blue"
end_case

reset_env
begin_case "promote flips the Service to the new slot and drains the old one"
ACTION=promote
IMAGE=registry.example.com/worker:v2
run_step
expect_success
expect_helm_set "blueGreen.activeSlot=blue"
expect_helm_set "blueGreen.blue.replicas=2"
expect_helm_set "blueGreen.green.replicas=0"
expect_helm_set "image.tag=v2"
expect_step_output "active-slot=blue"
expect_step_output "inactive-slot=green"
end_case

reset_env
begin_case "promote with an overlap window applies twice and still ends on the new slot"
ACTION=promote
IMAGE=registry.example.com/worker:v2
OVERLAP_SECONDS=30
run_step
expect_success
expect_helm_calls 2
expect_helm_set "blueGreen.activeSlot=blue"
expect_helm_set "blueGreen.blue.replicas=2"
expect_helm_set "blueGreen.green.replicas=0"
end_case

reset_env
begin_case "abort scales the inactive slot back to 0 without touching the active one"
ACTION=abort
run_step
expect_success
expect_helm_set "blueGreen.activeSlot=green"
expect_helm_set "blueGreen.blue.replicas=0"
expect_helm_set "blueGreen.green.replicas=2"
expect_step_output "active-slot=green"
end_case

reset_env
begin_case "abort returns the active digest image when no image is supplied"
LIVE_VALUES_FILE="${GREEN_ACTIVE_DIGEST_VALUES}"
ACTION=abort
run_step
expect_success
expect_step_output "image=registry.example.com/worker@sha256:active"
expect_helm_set "blueGreen.blue.image.tag=v0"
expect_helm_set "blueGreen.blue.image.digest="
end_case

reset_env
begin_case "abort returns a usable tag for a repository-only active slot"
LIVE_VALUES_FILE="${GREEN_ACTIVE_REPOSITORY_ONLY_VALUES}"
ACTION=abort
run_step
expect_success
expect_helm_set "image.repository=registry.example.com/green-worker"
expect_helm_set "image.tag=latest"
expect_helm_set "image.digest="
expect_step_output "image=registry.example.com/green-worker:latest"
end_case

reset_env
begin_case "status returns a usable tag for a repository-only active slot"
LIVE_VALUES_FILE="${GREEN_ACTIVE_REPOSITORY_ONLY_VALUES}"
ACTION=status
run_step
expect_success
expect_helm_calls 0
expect_step_output "image=registry.example.com/green-worker:latest"
end_case

reset_env
begin_case "status reports the slots without applying anything"
ACTION=status
run_step
expect_success
expect_helm_calls 0
expect_step_output "action=status"
expect_step_output "active-slot=green"
expect_step_output "inactive-slot=blue"
expect_step_output "image=registry.example.com/worker:v1"
end_case

reset_env
begin_case "preview renders the preview Service in front of the inactive slot"
ACTION=deploy
IMAGE=registry.example.com/worker:v2
PREVIEW=true
run_step
expect_success
expect_helm_set "blueGreen.preview.enabled=true"
end_case

reset_env
begin_case "preview stays under the values file when the input is false"
ACTION=deploy
IMAGE=registry.example.com/worker:v2
run_step
expect_success
expect_no_helm_set "blueGreen.preview.enabled=true"
end_case

reset_env
begin_case "a passing verify URL keeps the deployed slot up"
ACTION=deploy
IMAGE=registry.example.com/worker:v2
VERIFY_URL="http://preview.example.com/healthz"
FAKE_HTTP_STATUS=200
AUTO_ABORT=true
run_step
expect_success
expect_helm_calls 1
expect_helm_set "blueGreen.blue.replicas=1"
end_case

reset_env
begin_case "a failing verify URL with auto-abort scales the new slot back to 0 and fails"
ACTION=deploy
IMAGE=registry.example.com/worker:v2
VERIFY_URL="http://preview.example.com/healthz"
FAKE_HTTP_STATUS=503
AUTO_ABORT=true
run_step
expect_failure
expect_helm_calls 2
expect_helm_set "blueGreen.activeSlot=green"
expect_helm_set "blueGreen.blue.replicas=0"
expect_helm_set "blueGreen.green.replicas=2"
end_case

reset_env
begin_case "a failing verify URL without auto-abort fails but leaves the slot for inspection"
ACTION=deploy
IMAGE=registry.example.com/worker:v2
VERIFY_URL="http://preview.example.com/healthz"
FAKE_HTTP_STATUS=503
run_step
expect_failure
expect_helm_calls 1
expect_helm_set "blueGreen.blue.replicas=1"
end_case

if [ "${FAILURES}" -ne 0 ]; then
  echo "${FAILURES} case(s) failed"
  exit 1
fi
echo "all cases passed"
