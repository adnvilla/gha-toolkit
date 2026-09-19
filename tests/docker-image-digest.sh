#!/usr/bin/env bash
# Regression test for docker-build-push.yml's immutable pushed-image outputs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
cd "${REPO_ROOT}"

WORK_DIR="${WORK_DIR}" python3 <<'PY'
import os
from pathlib import Path
import yaml

workflow = yaml.safe_load(Path(".github/workflows/docker-build-push.yml").read_text(encoding="utf-8"))
step = next(s for s in workflow["jobs"]["build"]["steps"] if s.get("name") == "Resolve pushed image digest")
Path(os.environ["WORK_DIR"], "digest.sh").write_text(step["run"], encoding="utf-8")
PY

mkdir -p "${WORK_DIR}/bin"
cat > "${WORK_DIR}/bin/docker" <<'SH'
#!/usr/bin/env bash
if [ "$1" = image ] && [ "$2" = inspect ]; then
  printf '%s\n' "${REPO_DIGESTS}"
  exit 0
fi
exit 64
SH
chmod +x "${WORK_DIR}/bin/docker"

run_case() {
  local name="$1"
  local registry_image="$2"
  local repo_digests="$3"
  local expected_digest="$4"

  : > "${WORK_DIR}/output"
  GITHUB_OUTPUT="${WORK_DIR}/output" PATH="${WORK_DIR}/bin:${PATH}" \
    REGISTRY_IMAGE="${registry_image}" REPO_DIGESTS="${repo_digests}" SHORT_SHA=abc1234 \
    bash "${WORK_DIR}/digest.sh"

  grep -Fxq "digest=${expected_digest}" "${WORK_DIR}/output"
  grep -Fxq "image-digest-ref=${registry_image}@${expected_digest}" "${WORK_DIR}/output"
  echo "-- ${name}"
}

run_case \
  "selects the requested registry repository" \
  "registry.example.com/service" \
  $'registry.example.com/unrelated@sha256:deadbeef\nregistry.example.com/service@sha256:abcdef' \
  "sha256:abcdef"
run_case \
  "accepts Docker Hub normalized RepoDigests" \
  "docker.io/org/service" \
  $'other/service@sha256:deadbeef\norg/service@sha256:abcdef' \
  "sha256:abcdef"
echo "docker image digest output is immutable and correctly exposed"
