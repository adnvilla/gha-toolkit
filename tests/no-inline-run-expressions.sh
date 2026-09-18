#!/usr/bin/env bash
# Reject GitHub expression interpolation inside shell scripts. Expressions are
# evaluated before bash parses run:, so caller-controlled inputs must cross the
# boundary through env instead.
#
# Usage: bash tests/no-inline-run-expressions.sh [workflow.yml ...]
set -euo pipefail

if (( $# == 0 )); then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WORKFLOW_DIR="$(cd "${SCRIPT_DIR}/../.github/workflows" && pwd)"
  WORKFLOWS=("${WORKFLOW_DIR}"/*.yml)
else
  WORKFLOWS=("$@")
fi

python3 - "${WORKFLOWS[@]}" <<'PY'
import sys
from pathlib import Path

import yaml

failures = []
for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    workflow = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    for job_name, job in (workflow.get("jobs") or {}).items():
        for index, step in enumerate(job.get("steps") or []):
            if not isinstance(step, dict):
                continue
            run = step.get("run")
            if isinstance(run, str) and "${{" in run:
                name = step.get("name", "unnamed step")
                failures.append(f"{path}:{job_name}:step {index + 1} ({name}) interpolates an expression in run:")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("no workflow run block interpolates GitHub expressions")
PY
