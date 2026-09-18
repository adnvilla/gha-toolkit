#!/usr/bin/env bash
# Regression guard for gha-toolkit#45. It reads the shipped YAML and checks that
# cluster-facing Helm/kubectl calls name the caller's context explicitly instead
# of relying on (or mutating) the runner's kubeconfig current-context.
#
# Usage: bash tests/k8s-context-isolation.sh [k8s-deploy.yml k8s-canary.yml k8s-bluegreen.yml k8s-job.yml]
set -euo pipefail

if (( $# == 0 )); then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
  WORKFLOWS=(
    "${REPO_ROOT}/.github/workflows/k8s-deploy.yml"
    "${REPO_ROOT}/.github/workflows/k8s-canary.yml"
    "${REPO_ROOT}/.github/workflows/k8s-bluegreen.yml"
    "${REPO_ROOT}/.github/workflows/k8s-job.yml"
  )
elif (( $# == 4 )); then
  WORKFLOWS=("$@")
else
  echo "usage: $0 [k8s-deploy.yml k8s-canary.yml k8s-bluegreen.yml k8s-job.yml]" >&2
  exit 2
fi

python3 - "${WORKFLOWS[@]}" <<'PY'
import sys
from pathlib import Path

import yaml

workflows = {
    "k8s-deploy.yml": {
        "Adopt existing resources": (
            'kubectl --context "${KUBE_CONTEXT}" get',
            'kubectl --context "${KUBE_CONTEXT}" delete',
        ),
        "Deploy with Helm": ('--kube-context "${KUBE_CONTEXT}"',),
    },
    "k8s-canary.yml": {
        "Deploy canary phase": (
            'helm status "${RELEASE_NAME}" -n "${NAMESPACE}" --kube-context "${KUBE_CONTEXT}"',
            'helm get values "${RELEASE_NAME}" -n "${NAMESPACE}" -a -o json --kube-context "${KUBE_CONTEXT}"',
            '--kube-context "${KUBE_CONTEXT}"',
            'kubectl --context "${KUBE_CONTEXT}" get deploy',
            'kubectl --context "${KUBE_CONTEXT}" rollout status',
        ),
    },
    "k8s-bluegreen.yml": {
        "Deploy blue/green phase": (
            'helm status "${RELEASE_NAME}" -n "${NAMESPACE}" --kube-context "${KUBE_CONTEXT}"',
            'helm get values "${RELEASE_NAME}" -n "${NAMESPACE}" -a -o json --kube-context "${KUBE_CONTEXT}"',
            '--kube-context "${KUBE_CONTEXT}"',
        ),
    },
    "k8s-job.yml": {
        "Render Job manifest": ('--kube-context "${KUBE_CONTEXT}"',),
        "Apply Job": ('kubectl --context "${KUBE_CONTEXT}" apply',),
        "Operate CronJob": (
            'kubectl --context "${KUBE_CONTEXT}" get cronjob',
            'kubectl --context "${KUBE_CONTEXT}" create job',
            'kubectl --context "${KUBE_CONTEXT}" patch cronjob',
        ),
        "Wait for Job and collect logs": (
            'kubectl --context "${KUBE_CONTEXT}" get job',
            'kubectl --context "${KUBE_CONTEXT}" logs',
            'kubectl --context "${KUBE_CONTEXT}" describe job',
            'kubectl --context "${KUBE_CONTEXT}" delete job',
        ),
    },
}

failures = []
for filename, path_text in zip(workflows, sys.argv[1:]):
    expected_steps = workflows[filename]
    path = Path(path_text)
    text = path.read_text(encoding="utf-8")
    if "kubectl config use-context" in text:
        failures.append(f"{filename}: mutates kubeconfig with kubectl config use-context")
    workflow = yaml.safe_load(text)
    job = next(iter(workflow["jobs"].values()))
    steps = {step.get("name"): step for step in job.get("steps", [])}
    verify = steps.get("Verify kube context")
    if not verify:
        failures.append(f"{filename}: missing Verify kube context step")
    else:
        if verify.get("env", {}).get("KUBE_CONTEXT") != "${{ inputs.kube-context }}":
            failures.append(f"{filename}: verification step does not map kube-context through env")
        if 'kubectl --context "${KUBE_CONTEXT}" cluster-info' not in verify.get("run", ""):
            failures.append(f"{filename}: verification step does not use an explicit context")
    for step_name, snippets in expected_steps.items():
        step = steps.get(step_name)
        if not step:
            failures.append(f"{filename}: missing {step_name!r} step")
            continue
        run = step.get("run", "")
        if step.get("env", {}).get("KUBE_CONTEXT") != "${{ inputs.kube-context }}":
            failures.append(f"{filename}: {step_name} does not map kube-context through env")
        for snippet in snippets:
            if snippet not in run:
                failures.append(f"{filename}: {step_name} missing {snippet}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("all Kubernetes workflows use explicit kube contexts without mutating kubeconfig")
PY
