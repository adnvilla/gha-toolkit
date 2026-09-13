#!/usr/bin/env bash
# Guards the one ordering rule that makes breaking changes release a major version.
#
# @semantic-release/commit-analyzer evaluates custom `releaseRules` BEFORE its built-in ones, and
# it stops at the first match. A `{ "type": "feat" }` rule therefore matches `feat!:` — and any
# `feat:` carrying a `BREAKING CHANGE:` footer — before the built-in
# `{ breaking: true, release: "major" }` rule is ever reached, so the breaking change ships as a
# minor. That is how v1.7.0 shipped a documented breaking chart change without a major bump.
# Verified against @semantic-release/commit-analyzer@13 + conventionalcommits@9:
#
#   releaseRules without the breaking rule first   feat!: -> minor, fix!+footer -> patch
#   releaseRules with    the breaking rule first   feat!: -> major, fix!+footer -> major
#
# A `{ "breaking": true, "release": "major" }` entry must therefore come first in every
# releaseRules list in this repo, including the template consumers copy.
#
# Usage: bash tests/release-rules.sh [config...]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [ "$#" -gt 0 ]; then
  CONFIGS=("$@")
else
  CONFIGS=(.releaserc.json .releaserc.json.example)
fi

CONFIG_LIST="${CONFIGS[*]}" python3 <<'PY'
import json
import os
import sys

failures = 0

for path in os.environ["CONFIG_LIST"].split():
    with open(path) as fh:
        config = json.load(fh)

    rules = None
    for plugin in config.get("plugins", []):
        if isinstance(plugin, list) and plugin[0] == "@semantic-release/commit-analyzer":
            rules = (plugin[1] or {}).get("releaseRules")
            break

    if rules is None:
        print("-- %s: no commit-analyzer releaseRules, nothing to guard" % path)
        continue

    first = rules[0] if rules else {}
    if first.get("breaking") is True and first.get("release") == "major":
        print("-- %s: breaking -> major is the first rule" % path)
        continue

    failures += 1
    print("FAIL: %s does not start releaseRules with "
          '{ "breaking": true, "release": "major" }' % path)
    if any(r.get("breaking") is True for r in rules):
        print("      the rule exists but is preceded by %d rule(s); commit-analyzer stops at the "
              "first match, so a `type` rule above it wins for feat!/BREAKING CHANGE commits"
              % next(i for i, r in enumerate(rules) if r.get("breaking") is True))
    else:
        print("      breaking changes would be released as %s, not major"
              % (first.get("release") or "no release"))
    print("      first rule is: %s" % json.dumps(first))

if failures:
    sys.exit("%d config(s) would release a breaking change without a major bump" % failures)
print("all configs release breaking changes as major")
PY
