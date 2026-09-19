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
  printf '%s\n' 'registry.example.com/service@sha256:abcdef'
  exit 0
fi
exit 64
SH
chmod +x "${WORK_DIR}/bin/docker"

GITHUB_OUTPUT="${WORK_DIR}/output" PATH="${WORK_DIR}/bin:${PATH}" \
  REGISTRY_IMAGE=registry.example.com/service SHORT_SHA=abc1234 bash "${WORK_DIR}/digest.sh"

grep -Fxq 'digest=sha256:abcdef' "${WORK_DIR}/output"
grep -Fxq 'image-digest-ref=registry.example.com/service@sha256:abcdef' "${WORK_DIR}/output"
echo "docker image digest output is immutable and correctly exposed"
