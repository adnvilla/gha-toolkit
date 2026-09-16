#!/usr/bin/env bash
# Regression tests for the Python workflow command steps.
#
# Each run body is extracted from python.yml, then executed with a stubbed uv function. This keeps
# the assertions tied to the public workflow instead of duplicating its command logic here.
#
# Usage: bash tests/python-workflow.sh [workflow-path]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
cd "${REPO_ROOT}"

WORKFLOW="${1:-.github/workflows/python.yml}"
UV_LOG="${WORK_DIR}/uv.log"

extract_step() {
  local step_name="$1"
  WORKFLOW="${WORKFLOW}" STEP_NAME="${step_name}" python3 <<'PY'
import os
import sys

import yaml

with open(os.environ["WORKFLOW"]) as fh:
    workflow = yaml.safe_load(fh)
steps = workflow["jobs"]["build"]["steps"]
run = next((step["run"] for step in steps if step.get("name") == os.environ["STEP_NAME"]), None)
if run is None:
    sys.exit("step %r not found in %s" % (os.environ["STEP_NAME"], os.environ["WORKFLOW"]))
print(run)
PY
}

uv() {
  printf '%s\n' "$*" >> "${UV_LOG}"
}
export -f uv

run_step() {
  local step_name="$1"
  shift
  env UV_LOG="${UV_LOG}" "$@" bash -c "$(extract_step "${step_name}")"
}

assert_call() {
  local expected="$1"
  if ! grep -Fxq -- "${expected}" "${UV_LOG}"; then
    echo "FAIL: expected uv ${expected}"
    sed 's/^/  | uv /' "${UV_LOG}"
    exit 1
  fi
}

: > "${UV_LOG}"
run_step "Install dependencies"
run_step "Format" FORMAT_ARGS='--check .'
run_step "Lint" LINT_ARGS='.'
run_step "Typecheck" TYPECHECK_ARGS='.'
run_step "Build" BUILD_ARGS=''
run_step "Test" TEST_ARGS=''

assert_call 'sync --frozen'
assert_call 'run ruff format --check .'
assert_call 'run ruff check .'
assert_call 'run mypy .'
assert_call 'build'
assert_call 'run pytest'

echo "all cases passed"
