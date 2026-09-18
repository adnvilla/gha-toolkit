#!/usr/bin/env bash
# Prevent mutable action refs and known JavaScript actions from regressing to releases that embed Node.js 20 or older.
#
# This check is intentionally deterministic: resolving remote action manifests during CI would make
# validation depend on GitHub API availability and rate limits. Update the minimum major here when a
# dependency changes its embedded runtime.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

python3 - <<'PY'
from pathlib import Path
import re
import sys

import yaml
from yaml.nodes import MappingNode, ScalarNode, SequenceNode

WORKFLOWS = Path(".github/workflows")
EXTERNAL_ACTION = re.compile(
    r"^(?P<action>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*)@(?P<ref>\S+)$"
)
VERSION_COMMENT = re.compile(r"#\s*(v(?P<major>[0-9]+)(?:[.][0-9A-Za-z.-]+)?)\b")
NODE24_MINIMUMS = {
    "actions/checkout": 5,
    "actions/setup-go": 6,
    "actions/setup-node": 5,
    "actions/setup-python": 6,
    "azure/setup-helm": 5,
    "pnpm/action-setup": 5,
    "astral-sh/setup-uv": 9,
}

failures = 0


def fail(path: Path, line: int, message: str) -> None:
    global failures
    print(f"::error file={path},line={line}::{message}")
    failures += 1


def inspect(node, path: Path, lines: list[str]) -> None:
    if isinstance(node, MappingNode):
        for key, value in node.value:
            if isinstance(key, ScalarNode) and key.value == "uses" and isinstance(value, ScalarNode):
                reference = value.value.strip()
                match = EXTERNAL_ACTION.fullmatch(reference)
                if match:
                    line = value.start_mark.line
                    version = VERSION_COMMENT.search(lines[line])
                    if not re.fullmatch(r"[a-f0-9]{40}", match.group("ref")) or not version:
                        fail(path, line + 1, f"mutable or undocumented external action reference: {reference}")
                    elif match.group("action") in NODE24_MINIMUMS:
                        minimum = NODE24_MINIMUMS[match.group("action")]
                        if int(version.group("major")) < minimum:
                            fail(
                                path,
                                line + 1,
                                f"{match.group('action')} embeds Node.js 20 or older; use v{minimum} or newer",
                            )
            inspect(value, path, lines)
    elif isinstance(node, SequenceNode):
        for item in node.value:
            inspect(item, path, lines)


for workflow in sorted(WORKFLOWS.glob("*.yml")):
    source = workflow.read_text(encoding="utf-8")
    try:
        document = yaml.compose(source)
    except yaml.YAMLError as error:
        fail(workflow, 1, f"could not parse workflow YAML: {error}")
        continue
    if document is not None:
        inspect(document, workflow, source.splitlines())

if failures:
    print(f"{failures} action reference(s) violate the immutable-reference or Node.js 24 policy")
    sys.exit(1)
PY

echo "All external actions are SHA-pinned and tracked JavaScript actions use Node.js 24-compatible releases"
