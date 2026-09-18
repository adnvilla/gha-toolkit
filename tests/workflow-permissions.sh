#!/usr/bin/env bash
# Keep every workflow's GITHUB_TOKEN permissions explicit and least-privileged.
#
# Usage: bash tests/workflow-permissions.sh [workflow.yml ...]
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

expected = {
    "auto-release.yml": {"contents": "write"},
    "ci.yml": {"contents": "read"},
    "docker-build-push.yml": {"contents": "read", "packages": "write"},
    "go-base.yml": {"contents": "read"},
    "go.yml": {"contents": "read"},
    "k8s-bluegreen.yml": {"contents": "read"},
    "k8s-canary.yml": {"contents": "read"},
    "k8s-deploy.yml": {"contents": "read"},
    "k8s-job.yml": {"contents": "read"},
    "node.yml": {"contents": "read"},
    "python.yml": {"contents": "read"},
    "release.yml": {"contents": "write"},
    "rust.yml": {"contents": "read"},
    "test.yml": {"contents": "read"},
}

failures = []
for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    workflow = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    permissions = workflow.get("permissions")
    if not isinstance(permissions, dict):
        failures.append(f"{path}: missing workflow-level permissions mapping")
        continue
    wanted = expected.get(path.name)
    if wanted is not None and permissions != wanted:
        failures.append(f"{path}: permissions {permissions!r}, expected {wanted!r}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("all workflows declare the expected least-privilege permissions")
PY
