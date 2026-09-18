#!/usr/bin/env bash
# Ensure every job has a bounded execution time. Reusable callers pass the
# timeout input to the called workflow because jobs using `uses:` cannot carry
# their own timeout-minutes key.
#
# Usage: bash tests/workflow-timeouts.sh [workflow.yml ...]
set -euo pipefail

if (( $# == 0 )); then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WORKFLOW_DIR="$(cd "${SCRIPT_DIR}/../.github/workflows" && pwd)"
  shopt -s nullglob
  WORKFLOWS=("${WORKFLOW_DIR}"/*.yml "${WORKFLOW_DIR}"/*.yaml)
else
  WORKFLOWS=("$@")
fi

if (( ${#WORKFLOWS[@]} == 0 )); then
  echo "no workflow files to scan" >&2
  exit 2
fi

python3 - "${WORKFLOWS[@]}" <<'PY'
import sys
from pathlib import Path

import yaml

reusable_defaults = {
    "docker-build-push.yml": 30,
    "go-base.yml": 30,
    "go.yml": 30,
    "k8s-bluegreen.yml": 30,
    "k8s-canary.yml": 20,
    "k8s-deploy.yml": 20,
    "k8s-job.yml": 35,
    "node.yml": 30,
    "python.yml": 30,
    "release.yml": 15,
    "rust.yml": 30,
}

failures = []
for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    workflow = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    jobs = workflow.get("jobs") or {}

    trigger = workflow.get(True) or workflow.get("on") or {}
    reusable = isinstance(trigger, dict) and "workflow_call" in trigger
    if reusable:
        inputs = (trigger.get("workflow_call") or {}).get("inputs", {})
        timeout = inputs.get("timeout-minutes") if isinstance(inputs, dict) else None
        expected = reusable_defaults.get(path.name)
        if not isinstance(timeout, dict) or timeout.get("type") != "number":
            failures.append(f"{path}: reusable workflow must expose a numeric timeout-minutes input")
        elif not isinstance(timeout.get("default"), int) or timeout["default"] <= 0:
            failures.append(f"{path}: timeout-minutes input must have a positive default")
        elif expected is None:
            failures.append(f"{path}: reusable workflow is missing an approved timeout default")
        elif timeout["default"] != expected:
            failures.append(f"{path}: timeout-minutes input default {timeout['default']}, expected {expected}")

    for job_name, job in jobs.items():
        if not isinstance(job, dict):
            failures.append(f"{path}:{job_name}: job must be a mapping")
            continue
        if "uses" in job:
            timeout = (job.get("with") or {}).get("timeout-minutes")
            if not isinstance(timeout, int) or timeout <= 0:
                failures.append(f"{path}:{job_name}: reusable call must pass a positive timeout-minutes input")
        else:
            timeout = job.get("timeout-minutes")
            if timeout is None:
                failures.append(f"{path}:{job_name}: missing timeout-minutes")
            elif reusable and timeout != "${{ inputs.timeout-minutes }}":
                failures.append(
                    f"{path}:{job_name}: reusable job must consume ${{{{ inputs.timeout-minutes }}}}"
                )
            elif isinstance(timeout, int) and timeout <= 0:
                failures.append(f"{path}:{job_name}: timeout-minutes must be positive")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("all workflow jobs have bounded execution time")
PY
