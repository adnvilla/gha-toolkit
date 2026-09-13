#!/usr/bin/env bash
# Guards the rule that makes breaking changes release a major version.
#
# @semantic-release/commit-analyzer consults its built-in rules ONLY when no custom `releaseRules`
# entry matched the commit. A custom list that covers `feat`/`fix`/`chore`/... therefore shadows the
# built-in `{ breaking: true, release: "major" }` rule for every commit it matches, and breaking
# changes silently ship at the matched rule's level. That is how v1.7.0 shipped a documented
# breaking chart change as a minor.
#
# Order inside the list does NOT matter: commit-analyzer keeps the highest release type among all
# matching rules. Measured against @semantic-release/commit-analyzer@13 with
# conventional-changelog-conventionalcommits@9:
#
#   rules                    feat!:   feat: + BREAKING CHANGE footer   chore: + footer
#   without a breaking rule  minor    minor                            no release
#   breaking rule first      major    major                            major
#   breaking rule last       major    major                            major
#
# So the invariant to guard is presence, not position: every custom releaseRules list must carry a
# `{ "breaking": true, "release": "major" }` entry.
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
        # No custom rules means the built-in ones apply, and those already release breaking
        # changes as major.
        print("-- %s: no custom releaseRules, the built-in rules apply" % path)
        continue

    breaking = [rule for rule in rules if rule.get("breaking") is True]

    if not breaking:
        failures += 1
        print('FAIL: %s has custom releaseRules but no { "breaking": true } entry' % path)
        print("      custom rules shadow commit-analyzer's built-in rules for every commit they "
              "match, so breaking changes would ship at the matched rule's level")
        continue

    wrong = [rule for rule in breaking if rule.get("release") != "major"]
    if wrong:
        failures += 1
        print("FAIL: %s releases breaking changes as %s"
              % (path, ", ".join(str(rule.get("release")) for rule in wrong)))
        continue

    print("-- %s: breaking changes release as major" % path)

if failures:
    sys.exit("%d config(s) would release a breaking change without a major bump" % failures)
print("all configs release breaking changes as major")
PY
