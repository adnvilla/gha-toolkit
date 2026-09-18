#!/usr/bin/env bash
# Regression tests for k8s-job.yml's shell logic: rendering a one-off Job from the chart,
# waiting for it (including the fail-fast path), and the CronJob operations.
#
# Each step's `run:` body is extracted from the workflow and executed against stubbed `helm` and
# `kubectl`, so these tests exercise the shipped code instead of a copy of it. None of this is
# reachable from test.yml's dry-run smoke job, which never applies anything to a cluster.
#
# Usage: bash tests/k8s-job-run.sh [path/to/k8s-job.yml]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${1:-${REPO_ROOT}/.github/workflows/k8s-job.yml}"
cd "${REPO_ROOT}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

RENDER_SCRIPT="${WORK_DIR}/render.sh"
WAIT_SCRIPT="${WORK_DIR}/wait.sh"
CRONJOB_SCRIPT="${WORK_DIR}/cronjob.sh"
WORKFLOW="${WORKFLOW}" \
  RENDER_SCRIPT="${RENDER_SCRIPT}" \
  WAIT_SCRIPT="${WAIT_SCRIPT}" \
  CRONJOB_SCRIPT="${CRONJOB_SCRIPT}" \
  python3 <<'PY'
import os
import sys

import yaml

with open(os.environ["WORKFLOW"]) as fh:
    workflow = yaml.safe_load(fh)
steps = workflow["jobs"]["k8s-job"]["steps"]
wanted = {
    "Render Job manifest": os.environ["RENDER_SCRIPT"],
    "Wait for Job and collect logs": os.environ["WAIT_SCRIPT"],
    "Operate CronJob": os.environ["CRONJOB_SCRIPT"],
}
for name, destination in wanted.items():
    run = next((s["run"] for s in steps if s.get("name") == name), None)
    if run is None:
        sys.exit("step %r not found in %s" % (name, os.environ["WORKFLOW"]))
    with open(destination, "w") as fh:
        fh.write(run)
PY

STUB_DIR="${WORK_DIR}/bin"
mkdir -p "${STUB_DIR}"

# `helm` stub: records the template arguments and writes a Job manifest whose name is derived
# from the --set values the step passed, mirroring what charts/app renders.
cat > "${STUB_DIR}/helm" <<'STUB'
#!/usr/bin/env bash
if [ "$1" != "template" ]; then
  echo "unexpected helm invocation: $*" >&2
  exit 64
fi
printf '%s\n' "$@" > "${HELM_ARGS_FILE}"
release="$2"
name="job"
suffix=""
for arg in "$@"; do
  case "${arg}" in
    job.name=*) name="${arg#job.name=}" ;;
    job.nameSuffix=*) suffix="${arg#job.nameSuffix=}" ;;
  esac
done
full="${release}-app-${name}"
[ -n "${suffix}" ] && full="${full}-${suffix}"
cat <<MANIFEST
---
# Source: app/templates/job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: ${full}
spec:
  template:
    spec:
      containers:
        - name: ${name}
MANIFEST
STUB
chmod +x "${STUB_DIR}/helm"

# `kubectl` stub: records every invocation, answers Job status from FAKE_JOB_RESULT and knows
# about exactly one CronJob (FAKE_CRONJOB).
cat > "${STUB_DIR}/kubectl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KUBECTL_CALLS_FILE}"
if [ "$1" = "--context" ]; then
  shift 2
fi
case "$1" in
  get)
    case "$2" in
      job)
        # The step reads the Job's terminal conditions. "retrying" mimics a Job with
        # backoffLimit > 0 whose pods have failed but which the controller is still retrying:
        # failed pods, no terminal condition yet.
        case "${FAKE_JOB_RESULT}" in
          succeeded) printf 'Complete ' ;;
          failed) printf 'Failed ' ;;
        esac
        ;;
      cronjob)
        # "get cronjob -n ns -l ... -o jsonpath" lists the release's CronJobs; anything else is
        # an existence check for one exact name.
        case "$3" in
          -*) printf '%s\n' "${FAKE_RELEASE_CRONJOBS}" ;;
          *) [ "$3" == "${FAKE_CRONJOB}" ] || exit 1 ;;
        esac
        ;;
    esac
    ;;
  logs|describe|apply|create|patch|delete) ;;
  *)
    echo "unexpected kubectl invocation: $*" >&2
    exit 64
    ;;
esac
STUB
chmod +x "${STUB_DIR}/kubectl"

# `sleep` stub so the wait loop costs no wall-clock time.
printf '#!/usr/bin/env bash\nexit 0\n' > "${STUB_DIR}/sleep"
chmod +x "${STUB_DIR}/sleep"

HELM_ARGS_FILE="${WORK_DIR}/helm-args.txt"
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

reset_step_state() {
  : > "${HELM_ARGS_FILE}"
  : > "${KUBECTL_CALLS_FILE}"
  : > "${STEP_OUTPUT}"
}

run_render() {
  reset_step_state
  set +e
  env \
    PATH="${STUB_DIR}:${PATH}" \
    HELM_ARGS_FILE="${HELM_ARGS_FILE}" \
    GITHUB_OUTPUT="${STEP_OUTPUT}" \
    GITHUB_RUN_ID=42 \
    GITHUB_RUN_ATTEMPT=1 \
    USE_LOCAL_CHART=true \
    CHART_PATH=charts/app \
    JOB_TEMPLATE=templates/job.yaml \
    RELEASE_NAME=service \
    NAMESPACE=service \
    VALUES_FILE=charts/app/values.yaml \
    IMAGE="${IMAGE}" \
    JOB_NAME="${JOB_NAME}" \
    NAME_SUFFIX="${NAME_SUFFIX}" \
    COMMAND="${COMMAND}" \
    ARGS="${ARGS}" \
    HELM_SET="" \
    DRY_RUN="${DRY_RUN}" \
    MANIFEST="${WORK_DIR}/manifest.yaml" \
    KUBE_CONTEXT=test-context \
    bash "${RENDER_SCRIPT}" > "${STEP_LOG}" 2>&1
  STEP_STATUS=$?
  set -e
}

run_wait() {
  reset_step_state
  set +e
  env \
    PATH="${STUB_DIR}:${PATH}" \
    KUBECTL_CALLS_FILE="${KUBECTL_CALLS_FILE}" \
    FAKE_JOB_RESULT="${FAKE_JOB_RESULT}" \
    GITHUB_OUTPUT="${STEP_OUTPUT}" \
    NAMESPACE=service \
    JOB_NAME=service-app-migrate-42-1 \
    TIMEOUT_SECONDS=2 \
    POLL_INTERVAL=1 \
    TAIL_LINES=-1 \
    DELETE_ON_SUCCESS="${DELETE_ON_SUCCESS}" \
    KUBE_CONTEXT=test-context \
    bash "${WAIT_SCRIPT}" > "${STEP_LOG}" 2>&1
  STEP_STATUS=$?
  set -e
}

run_cronjob() {
  reset_step_state
  set +e
  env \
    PATH="${STUB_DIR}:${PATH}" \
    KUBECTL_CALLS_FILE="${KUBECTL_CALLS_FILE}" \
    FAKE_CRONJOB="${FAKE_CRONJOB}" \
    FAKE_RELEASE_CRONJOBS="${FAKE_RELEASE_CRONJOBS}" \
    GITHUB_OUTPUT="${STEP_OUTPUT}" \
    GITHUB_RUN_ID=42 \
    GITHUB_RUN_ATTEMPT=1 \
    ACTION="${ACTION}" \
    RELEASE_NAME=service \
    NAMESPACE=service \
    CRONJOB_NAME="${CRONJOB_NAME}" \
    NAME_SUFFIX="${NAME_SUFFIX}" \
    KUBE_CONTEXT=test-context \
    bash "${CRONJOB_SCRIPT}" > "${STEP_LOG}" 2>&1
  STEP_STATUS=$?
  set -e
}

reset_env() {
  IMAGE=""
  JOB_NAME="job"
  NAME_SUFFIX=""
  COMMAND=""
  ARGS=""
  DRY_RUN=false
  FAKE_JOB_RESULT=succeeded
  DELETE_ON_SUCCESS=false
  ACTION=""
  CRONJOB_NAME=""
  # No exact-name match by default: the chart renders <fullname>-<name>, so a bare name has to be
  # discovered through the release's labels.
  FAKE_CRONJOB=""
  FAKE_RELEASE_CRONJOBS="service-app-cleanup
service-app-nightly-report"
}

expect_success() {
  [ "${STEP_STATUS}" -eq 0 ] || fail "step exited ${STEP_STATUS}, expected 0"
  expect_contexts
}

expect_failure() {
  [ "${STEP_STATUS}" -ne 0 ] || fail "step exited 0, expected a failure"
  expect_contexts
}

expect_contexts() {
  if [ -s "${HELM_ARGS_FILE}" ]; then
    grep -Fxq -- "--kube-context" "${HELM_ARGS_FILE}" \
      || fail "helm template did not receive --kube-context"
    grep -Fxq -- "test-context" "${HELM_ARGS_FILE}" \
      || fail "helm template did not receive test-context"
  fi
  while IFS= read -r call; do
    [ -z "${call}" ] && continue
    [[ "${call}" == "--context test-context "* ]] \
      || fail "kubectl call did not select test-context: ${call}"
  done < "${KUBECTL_CALLS_FILE}"
}

expect_helm_arg() {
  grep -Fxq -- "$1" "${HELM_ARGS_FILE}" || fail "missing helm argument '$1'"
}

# image.repository/image.tag must recompose to the reference the caller passed — that is the
# contract the other k8s workflows keep for tagless and digest references (see
# tests/k8s-image-references.sh), not a specific repository/tag split.
expect_image_roundtrip() {
  local repo tag
  repo="$(sed -n 's/^image\.repository=//p' "${HELM_ARGS_FILE}")"
  tag="$(sed -n 's/^image\.tag=//p' "${HELM_ARGS_FILE}")"
  [ "${repo}:${tag}" = "$1" ] || fail "image sets recompose to '${repo}:${tag}', expected '$1'"
}

expect_step_output() {
  grep -Fxq "$1" "${STEP_OUTPUT}" || fail "missing step output '$1'"
}

expect_kubectl_call() {
  grep -Fq -- "$1" "${KUBECTL_CALLS_FILE}" || fail "missing kubectl call matching '$1'"
}

expect_no_kubectl_call() {
  ! grep -Fq -- "$1" "${KUBECTL_CALLS_FILE}" || fail "unexpected kubectl call matching '$1'"
}

reset_env
begin_case "render turns the run id into a unique Job name and enables the Job template"
JOB_NAME=migrate
IMAGE=registry.example.com/service:v2
run_render
expect_success
expect_helm_arg "job.enabled=true"
expect_helm_arg "job.name=migrate"
expect_helm_arg "job.nameSuffix=42-1"
expect_helm_arg "image.repository=registry.example.com/service"
expect_helm_arg "image.tag=v2"
expect_helm_arg "--show-only"
expect_step_output "job-name=service-app-migrate-42-1"
end_case

reset_env
begin_case "a tagless reference from a registry with a port survives the split"
JOB_NAME=migrate
IMAGE=registry.example.local:5000/service
run_render
expect_success
expect_image_roundtrip "registry.example.local:5000/service"
end_case

reset_env
begin_case "a digest reference survives the split"
JOB_NAME=migrate
IMAGE=registry.example.com/service@sha256:abcdef
run_render
expect_success
expect_image_roundtrip "registry.example.com/service@sha256:abcdef"
end_case

reset_env
begin_case "no image input leaves the values file's image alone"
JOB_NAME=migrate
run_render
expect_success
! grep -q '^image.repository=' "${HELM_ARGS_FILE}" \
  || fail "image.repository was set without an image input"
end_case

reset_env
begin_case "command and args keep entries with spaces and commas intact"
JOB_NAME=seed
COMMAND="/bin/sh
-c"
ARGS="./seed.sh --tables=users,orders --note=hello world"
run_render
expect_success
expect_helm_arg 'job.command=["/bin/sh", "-c"]'
expect_helm_arg 'job.args=["./seed.sh --tables=users,orders --note=hello world"]'
end_case

reset_env
begin_case "dry-run reports a rendered status"
JOB_NAME=migrate
DRY_RUN=true
run_render
expect_success
expect_step_output "status=rendered"
end_case

reset_env
begin_case "a succeeded Job prints logs and passes"
FAKE_JOB_RESULT=succeeded
run_wait
expect_success
expect_step_output "status=succeeded"
expect_kubectl_call "logs job/service-app-migrate-42-1"
expect_no_kubectl_call "delete job"
end_case

reset_env
begin_case "delete-on-success removes the Job after it passes"
FAKE_JOB_RESULT=succeeded
DELETE_ON_SUCCESS=true
run_wait
expect_success
expect_kubectl_call "delete job service-app-migrate-42-1"
end_case

reset_env
begin_case "a failed Job fails the step immediately with logs and a describe"
FAKE_JOB_RESULT=failed
run_wait
expect_failure
expect_step_output "status=failed"
expect_kubectl_call "logs job/service-app-migrate-42-1"
expect_kubectl_call "describe job service-app-migrate-42-1"
end_case

reset_env
begin_case "failed pods under a retry budget are not treated as a terminal failure"
FAKE_JOB_RESULT=retrying
run_wait
expect_failure
expect_step_output "status=timeout"
end_case

reset_env
begin_case "a Job that never finishes fails on the timeout"
FAKE_JOB_RESULT=pending
run_wait
expect_failure
expect_step_output "status=timeout"
end_case

reset_env
begin_case "trigger-cronjob discovers the chart-rendered name from a bare name segment"
ACTION=trigger-cronjob
CRONJOB_NAME=cleanup
run_cronjob
expect_success
expect_kubectl_call "create job service-app-cleanup-42-1 --from=cronjob/service-app-cleanup"
expect_step_output "job-name=service-app-cleanup-42-1"
end_case

reset_env
begin_case "a bare name is not assumed to be <release>-<name>"
ACTION=trigger-cronjob
CRONJOB_NAME=cleanup
run_cronjob
expect_success
expect_no_kubectl_call "--from=cronjob/service-cleanup"
end_case

reset_env
begin_case "trigger-cronjob accepts a full resource name"
ACTION=trigger-cronjob
CRONJOB_NAME=my-own-report
FAKE_CRONJOB="my-own-report"
run_cronjob
expect_success
expect_kubectl_call "--from=cronjob/my-own-report"
end_case

reset_env
begin_case "the uniqueness suffix survives a CronJob name at the length limit"
ACTION=trigger-cronjob
CRONJOB_NAME="$(printf 'c%.0s' $(seq 1 52))"
FAKE_CRONJOB="${CRONJOB_NAME}"
NAME_SUFFIX="rerun-20260913-1200"
run_cronjob
expect_success
CREATED_JOB="$(sed -n 's/^job-name=//p' "${STEP_OUTPUT}")"
case "${CREATED_JOB}" in
  *-"${NAME_SUFFIX}") ;;
  *) fail "created Job '${CREATED_JOB}' lost the uniqueness suffix" ;;
esac
[ "${#CREATED_JOB}" -le 63 ] || fail "created Job name is ${#CREATED_JOB} chars, over the 63 limit"
end_case

reset_env
begin_case "suspend-cronjob patches suspend true"
ACTION=suspend-cronjob
CRONJOB_NAME=cleanup
run_cronjob
expect_success
expect_kubectl_call '{"spec":{"suspend":true}}'
expect_kubectl_call "patch cronjob service-app-cleanup"
expect_step_output "status=patched"
end_case

reset_env
begin_case "resume-cronjob patches suspend false"
ACTION=resume-cronjob
CRONJOB_NAME=cleanup
run_cronjob
expect_success
expect_kubectl_call '{"spec":{"suspend":false}}'
end_case

reset_env
begin_case "an unknown CronJob fails instead of silently doing nothing"
ACTION=suspend-cronjob
CRONJOB_NAME=missing
run_cronjob
expect_failure
end_case

reset_env
begin_case "an ambiguous bare name fails instead of picking one at random"
ACTION=suspend-cronjob
CRONJOB_NAME=cleanup
FAKE_RELEASE_CRONJOBS="service-app-cleanup
service-app-extra-cleanup"
run_cronjob
expect_failure
expect_no_kubectl_call "patch cronjob"
end_case

if [ "${FAILURES}" -ne 0 ]; then
  echo "${FAILURES} case(s) failed"
  exit 1
fi
echo "all cases passed"
