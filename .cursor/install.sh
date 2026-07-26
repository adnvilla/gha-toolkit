#!/usr/bin/env bash
# Installs the validation harness described in AGENTS.md sections 3 and 4, so a
# cloud agent can run every gate in ci.yml without setting up tooling first.
#
# Cursor re-runs this on every VM boot and snapshots the result, so each step is
# guarded: an already-provisioned machine reinstalls nothing.
set -euo pipefail

# Pinned to what ci.yml actually runs, so local results match CI.
# actionlint and shellcheck are the versions inside rhysd/actionlint:1.7.12.
ACTIONLINT_VERSION=1.7.12
SHELLCHECK_VERSION=0.10.0
HELM_VERSION=3.16.2

# yamllint and markdownlint are deliberately unpinned: CI runs them through
# third-party actions that carry their own versions.

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Reports whether $1 is on PATH already at version $2. helm has no --version flag.
have_version() { # command, expected version substring
  command -v "$1" > /dev/null 2>&1 || return 1
  case "$1" in
    helm) helm version --short 2>&1 | grep -qF "$2" ;;
    *) "$1" --version 2>&1 | grep -qF "$2" ;;
  esac
}

if have_version actionlint "${ACTIONLINT_VERSION}"; then
  echo "actionlint ${ACTIONLINT_VERSION} already installed"
else
  echo "installing actionlint ${ACTIONLINT_VERSION}"
  curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
    | tar xz -C "${TMP}" actionlint
  sudo install -m0755 "${TMP}/actionlint" /usr/local/bin/actionlint
fi

# actionlint only runs its `run:` script checks when shellcheck is on PATH.
if have_version shellcheck "${SHELLCHECK_VERSION}"; then
  echo "shellcheck ${SHELLCHECK_VERSION} already installed"
else
  echo "installing shellcheck ${SHELLCHECK_VERSION}"
  curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
    | tar xJ -C "${TMP}"
  sudo install -m0755 "${TMP}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/shellcheck
fi

if have_version helm "${HELM_VERSION}"; then
  echo "helm ${HELM_VERSION} already installed"
else
  echo "installing helm ${HELM_VERSION}"
  curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    | tar xz -C "${TMP}" linux-amd64/helm
  sudo install -m0755 "${TMP}/linux-amd64/helm" /usr/local/bin/helm
fi

# PyYAML backs the tests/ scripts, which extract `run:` bodies from workflow YAML.
# --break-system-packages: the system Python is marked externally managed.
if command -v yamllint > /dev/null 2>&1 && python3 -c 'import yaml' 2> /dev/null; then
  echo "yamllint and PyYAML already installed"
else
  echo "installing yamllint and PyYAML"
  sudo pip install --quiet --break-system-packages yamllint 'pyyaml~=6.0'
fi

# npm is absent from root's secure_path and its global prefix can be '/', so a
# bare `sudo npm install -g` fails with command-not-found or EACCES.
if command -v markdownlint > /dev/null 2>&1; then
  echo "markdownlint already installed"
else
  echo "installing markdownlint-cli"
  sudo env "PATH=${PATH}" "$(command -v npm)" install -g \
    --prefix /usr/local --no-fund --no-audit markdownlint-cli
fi

missing=0
for tool in actionlint shellcheck helm yamllint markdownlint; do
  command -v "${tool}" > /dev/null 2>&1 || { echo "MISSING: ${tool}" >&2; missing=1; }
done
python3 -c 'import yaml' 2> /dev/null || { echo "MISSING: PyYAML" >&2; missing=1; }
[ "${missing}" -eq 0 ] || exit 1

echo "gha-toolkit harness ready"
