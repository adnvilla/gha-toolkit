#!/usr/bin/env bash
# Guards release.yml's immutable, script-free semantic-release bootstrap.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

python3 <<'PY'
import json
import re
from pathlib import Path

import yaml

workflow = yaml.safe_load(Path(".github/workflows/release.yml").read_text(encoding="utf-8"))
steps = workflow["jobs"]["release"]["steps"]

toolchain_checkout = next(
    (step for step in steps if step.get("name") == "Checkout locked release toolchain"), None
)
if toolchain_checkout is None:
    raise SystemExit("missing locked release toolchain checkout")

checkout_with = toolchain_checkout.get("with", {})
expected_checkout = {
    "repository": "${{ job.workflow_repository }}",
    "ref": "${{ job.workflow_sha }}",
    "path": ".gha-toolkit-release",
}
if checkout_with != expected_checkout:
    raise SystemExit("toolchain checkout must use the executing workflow repository and SHA")

install = next((step for step in steps if step.get("name") == "Install semantic-release"), None)
if install is None or "npm ci --ignore-scripts --prefix \"${RELEASE_TOOLS_DIR}\"" not in install.get("run", ""):
    raise SystemExit("release toolchain must use npm ci with --ignore-scripts")
if "npm install" in install["run"]:
    raise SystemExit("release toolchain must not use npm install")

release = next((step for step in steps if step.get("name") == "Release"), None)
if release is None:
    raise SystemExit("missing release step")
for command in (
    "npx --prefix \"${RELEASE_TOOLS_DIR}\" --no-install semantic-release --dry-run",
    "npx --prefix \"${RELEASE_TOOLS_DIR}\" --no-install semantic-release",
):
    if command not in release.get("run", ""):
        raise SystemExit("release step must execute the locked local semantic-release binary")

package = json.loads(Path("tools/release/package.json").read_text(encoding="utf-8"))
lock = json.loads(Path("tools/release/package-lock.json").read_text(encoding="utf-8"))
expected_packages = {
    "semantic-release",
    "@semantic-release/git",
    "@semantic-release/changelog",
    "conventional-changelog-conventionalcommits",
}
dependencies = package.get("dependencies")
if set(dependencies or ()) != expected_packages:
    raise SystemExit("release package.json must retain the expected direct dependencies")
for name, version in dependencies.items():
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+[.][0-9]+[.][0-9]+(?:-[0-9A-Za-z.-]+)?", version):
        raise SystemExit("%s must use an exact version, not a range: %r" % (name, version))
if lock.get("lockfileVersion") != 3:
    raise SystemExit("release toolchain must use a lockfileVersion 3 lockfile")
root = lock.get("packages", {}).get("", {})
if root.get("dependencies") != dependencies:
    raise SystemExit("release package-lock root dependencies must match package.json")
for name, version in dependencies.items():
    locked = lock["packages"].get("node_modules/" + name, {}).get("version")
    if locked != version:
        raise SystemExit("package-lock must resolve %s to its exact manifest version" % name)

dependabot = yaml.safe_load(Path(".github/dependabot.yml").read_text(encoding="utf-8"))
if not any(
    update.get("package-ecosystem") == "npm" and update.get("directory") == "/tools/release"
    for update in dependabot.get("updates", [])
):
    raise SystemExit("Dependabot must update /tools/release npm dependencies")
PY

echo "release toolchain is locked, script-free, and maintained by Dependabot"
