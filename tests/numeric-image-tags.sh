#!/usr/bin/env bash
# Regression tests for numeric image tags (NAVI-28).
#
# An all-digit short SHA such as 9033178 is parsed by Helm as int64 (`--set`) or float64 (values
# file). charts/app 0.9.0 formatted tags with printf "%s", so it rendered
# "repo:%!s(int64=9033178)" and kubelet rejected the pod with InvalidImageName. This script checks
# both halves of the fix:
#   1. the chart renders numeric tags as their digits in every workload that has an image;
#   2. the k8s-* workflows pass image tags/digests with --set-string, never --set.
#
# Usage: bash tests/numeric-image-tags.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

chart="charts/app"
repo="registry.example.local:5000/test-app"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

FAILURES=0

fail() {
  FAILURES=$((FAILURES + 1))
  echo "   $*"
}

# Every `image:` line in the render must equal the expected reference.
expect_images() {
  local rendered="$1" want="$2" want_count="$3" got_count
  got_count="$(grep -c '^ *image: ' <<< "${rendered}" || true)"
  [ "${got_count}" = "${want_count}" ] \
    || fail "expected ${want_count} image lines, got ${got_count}"
  while IFS= read -r line; do
    [ "${line}" = "image: \"${want}\"" ] || fail "unexpected ${line} (want ${want})"
  done < <(grep '^ *image: ' <<< "${rendered}" | sed 's/^ *//')
}

echo "-- --set numeric tag renders its digits (rolling, canary, blueGreen, batch)"
rendered="$(helm template t "${chart}" --set image.repository="${repo}" --set image.tag=9033178)"
expect_images "${rendered}" "${repo}:9033178" 1
rendered="$(helm template t "${chart}" --set image.repository="${repo}" --set image.tag=9033178 \
  --set strategy.mode=canary --set canary.image.tag=1234567)"
grep -Fq "image: \"${repo}:9033178\"" <<< "${rendered}" || fail "canary mode: stable tag not rendered"
grep -Fq "image: \"${repo}:1234567\"" <<< "${rendered}" || fail "canary mode: canary tag not rendered"
rendered="$(helm template t "${chart}" --set image.repository="${repo}" --set image.tag=9033178 \
  --set strategy.mode=blueGreen --set blueGreen.green.image.tag=1234567 --set blueGreen.green.replicas=1)"
grep -Fq "image: \"${repo}:9033178\"" <<< "${rendered}" || fail "blueGreen: blue tag not rendered"
grep -Fq "image: \"${repo}:1234567\"" <<< "${rendered}" || fail "blueGreen: green tag not rendered"
rendered="$(helm template t "${chart}" --set image.repository="${repo}" --set image.tag=9033178 \
  --set job.enabled=true --set job.name=migrate --set-json 'job.command=["true"]' \
  --show-only templates/job.yaml)"
expect_images "${rendered}" "${repo}:9033178" 1

echo "-- --set exponent-like tag stays a string"
rendered="$(helm template t "${chart}" --set image.repository="${repo}" --set image.tag=123e4)"
expect_images "${rendered}" "${repo}:123e4" 1

echo "-- values-file numeric tag renders its digits"
printf 'image:\n  repository: %s\n  tag: 9033178\n' "${repo}" > "${WORK_DIR}/int.yaml"
rendered="$(helm template t "${chart}" -f "${WORK_DIR}/int.yaml")"
expect_images "${rendered}" "${repo}:9033178" 1
printf 'image:\n  repository: %s\n  tag: 9033178\ncanary:\n  image:\n    tag: 1234567\nstrategy:\n  mode: canary\n' \
  "${repo}" > "${WORK_DIR}/canary.yaml"
rendered="$(helm template t "${chart}" -f "${WORK_DIR}/canary.yaml")"
grep -Fq "image: \"${repo}:1234567\"" <<< "${rendered}" || fail "values-file canary tag not rendered"

echo "-- values-file fractional tag fails loudly instead of deploying a wrong tag"
printf 'image:\n  repository: %s\n  tag: 1.10\n' "${repo}" > "${WORK_DIR}/float.yaml"
if output="$(helm template t "${chart}" -f "${WORK_DIR}/float.yaml" 2>&1)"; then
  fail "render succeeded for an unquoted fractional tag"
else
  grep -Fq "quote it in the values file" <<< "${output}" || fail "unexpected error: ${output}"
fi

echo "-- values-file integer beyond float64's exact range fails instead of being rounded"
printf 'image:\n  repository: %s\n  tag: 9007199254740993\n' "${repo}" > "${WORK_DIR}/big.yaml"
if output="$(helm template t "${chart}" -f "${WORK_DIR}/big.yaml" 2>&1)"; then
  fail "render succeeded for an unquoted tag beyond 2^53"
else
  grep -Fq "quote it in the values file" <<< "${output}" || fail "unexpected error: ${output}"
fi
printf 'image:\n  repository: %s\n  tag: 9007199254740991\n' "${repo}" > "${WORK_DIR}/max.yaml"
rendered="$(helm template t "${chart}" -f "${WORK_DIR}/max.yaml")"
expect_images "${rendered}" "${repo}:9007199254740991" 1

echo "-- k8s-* workflows never pass an image tag or digest with --set"
if offenders="$(grep -nE -- '--set[[:space:]]+"?[A-Za-z.]*image\.(tag|digest)=' \
  .github/workflows/k8s-*.yml)"; then
  fail "image tags/digests must use --set-string:"
  while IFS= read -r line; do echo "     ${line}"; done <<< "${offenders}"
fi

if [ "${FAILURES}" -ne 0 ]; then
  echo "${FAILURES} check(s) failed"
  exit 1
fi
echo "all checks passed"
