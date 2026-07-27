# AGENTS.md

Working harness for agents (and humans) operating in `gha-toolkit`. Read this before making any
change. It defines what the repo is, how to validate work, the conventions that gate a merge, and the
traps that are easy to fall into.

> Relationship to other docs: **this file is the single source of truth for the working harness.**
> When anything disagrees, **this file and the actual files in the repo win**. `README.md`,
> `ARCHITECTURE.md`, `EXAMPLES.md`, `ENVIRONMENTS.md`, `CONTRIBUTING.md`, and `charts/app/README.md`
> are the human-facing docs you must keep in sync (see [Definition of Done](#10-definition-of-done)).

## 1. What this repo is

`gha-toolkit` ships **no application source code**. The product is:

1. A set of **reusable GitHub Actions workflows** in `.github/workflows/`, consumed by other repos via
   `uses: adnvilla/gha-toolkit/.github/workflows/<file>.yml@<ref>`.
2. A **generic Helm chart** in `charts/app/`, pulled by the k8s deploy workflows at the same git ref
   the caller pinned.

Everything else (`README`, `ARCHITECTURE`, `EXAMPLES`, `ENVIRONMENTS`, `CONTRIBUTING`, `charts/app/README`)
documents those two things. There is no build step and no application runtime — "testing" means linting
YAML/Actions/Markdown, rendering the chart, and running the shell-logic tests. Treat every workflow as a public API consumed by other repos:
backward compatibility matters (see [Change classification](#7-change-classification-breaking-vs-non-breaking)).

## 2. Repo map

```
.github/workflows/
  # Reusable (on: workflow_call) — the product, consumed by other repos:
  go-base.yml            # Go build/test, no external services
  go.yml                 # Go build/test + PostgreSQL service container
  node.yml               # Node/TS install+build+lint+typecheck+test (pnpm|npm|yarn)
  rust.yml               # Rust fmt/clippy/build/test + optional PostgreSQL container
  docker-build-push.yml  # Build a Docker image, push to registry (ghcr/dockerhub/local), outputs `image`
  k8s-deploy.yml         # Rolling deploy via Helm using charts/app, bound to a GitHub Environment
  k8s-canary.yml         # Canary phases (deploy/promote/abort) for HTTP APIs
  k8s-bluegreen.yml      # Blue/green phases for workers (e.g. Kafka consumers)
  release.yml            # semantic-release runner
  # Internal (govern THIS repo's lifecycle, not reusable):
  ci.yml                 # lint YAML + Actions semantics + Markdown, validate chart, run shell-logic
                         # tests, validate doc pins
  auto-release.yml       # workflow_run after CI success on master -> runs release logic (dogfoods release.yml)
  test.yml               # workflow_dispatch smoke test that calls the reusable workflows locally
charts/app/              # Generic Helm chart (rolling/canary/blueGreen + optional SA/HPA/PDB/NetworkPolicy)
tests/                   # Shell-logic tests: extract a workflow step's `run:` body and run it stubbed
  canary-image-resolution.sh  # k8s-canary.yml stable/canary image discovery (non-dry-run path)
.releaserc.json          # THIS repo's semantic-release config — SOURCE OF TRUTH for release rules
.releaserc.json.example  # Template consumers copy into their own repo
.yamllint.yml            # YAML lint rules
.markdownlint.json       # Markdown lint rules
.github/actionlint.yaml  # actionlint config — ignore rules (see the job.workflow_* trap in section 11)
.cursor/environment.json # Cursor cloud-agent env: runs install.sh on every VM boot
.cursor/install.sh       # Provisions the tools below (idempotent; cold ~4s, warm ~0.1s)
```

## 3. Prerequisites

Local validation needs these tools (match CI versions where it matters). On a Cursor cloud agent they
are already installed: `.cursor/environment.json` runs `.cursor/install.sh` on every VM boot, so do
not reinstall them by hand — just run the harness in section 4.

- `yamllint`
- `actionlint` (CI pins `v1.7.12` via Docker; locally either `docker` or the pinned binary works — see
  the harness below. `shellcheck` on `PATH` enables the `run:` script checks; the Docker image bundles it)
- `markdownlint` (npm `markdownlint-cli`)
- `helm` (CI uses `v3.16.2`)
- `python3` with `PyYAML` (for the shell-logic tests in `tests/`)
- `node` + `npx` (only to dry-run semantic-release)

## 4. The validation harness

Run these before proposing any change. They mirror `ci.yml`'s jobs one-to-one — if they pass locally,
CI should pass too.

```bash
# 1. Workflow YAML style (matches ci.yml -> validate-workflows)
yamllint -c .yamllint.yml .github/workflows/

# 2. Actions semantics + `run:` scripts (matches ci.yml -> validate-actions).
# Reads ignore rules from .github/actionlint.yaml. This is the CI command verbatim:
docker run --rm -v "${PWD}:/repo:ro" -w /repo rhysd/actionlint:1.7.12 -color
# Same job also lints the standalone test scripts, which actionlint never sees:
docker run --rm -v "${PWD}:/repo:ro" -w /repo --entrypoint shellcheck \
  rhysd/actionlint:1.7.12 tests/*.sh
# Without Docker, install the same version and run `actionlint` (needs shellcheck on PATH):
#   go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.12

# 3. Markdown docs (matches ci.yml -> validate-markdown; warning-only in CI, but keep it clean)
markdownlint . --config .markdownlint.json --ignore node_modules

# 4. Helm chart (matches ci.yml -> validate-chart)
helm lint charts/app
helm template test-release charts/app \
  --set image.repository=registry.example.local:5000/test-app \
  --set image.tag=test \
  --set ingress.enabled=true --set ingress.host=test.local > /dev/null
# Also render with all default-off resources ON (SA/HPA/PDB/NetworkPolicy) to catch template errors:
helm template test-release charts/app \
  --set image.repository=registry.example.local:5000/test-app \
  --set image.tag=test \
  --set serviceAccount.create=true --set autoscaling.enabled=true \
  --set podDisruptionBudget.enabled=true --set networkPolicy.enabled=true > /dev/null
# Canary + blueGreen modes (match ci.yml validate-chart extras):
helm template test-release charts/app \
  --set image.repository=registry.example.local:5000/test-app --set image.tag=stable \
  --set strategy.mode=canary --set canary.image.repository=registry.example.local:5000/test-app \
  --set canary.image.tag=canary --set ingress.enabled=true --set ingress.host=api.local > /dev/null
helm template test-release charts/app \
  --set image.repository=registry.example.local:5000/test-app --set image.tag=blue \
  --set strategy.mode=blueGreen --set blueGreen.activeSlot=blue \
  --set blueGreen.blue.image.repository=registry.example.local:5000/test-app \
  --set blueGreen.blue.image.tag=blue --set blueGreen.green.image.repository=registry.example.local:5000/test-app \
  --set blueGreen.green.image.tag=green --set blueGreen.green.replicas=1 > /dev/null

# 5. Workflow shell logic (matches ci.yml -> validate-shell-logic)
bash tests/canary-image-resolution.sh

# 6. Release dry-run (optional; needs GITHUB_TOKEN)
npx semantic-release --dry-run
```

Single-file variants while iterating:

```bash
yamllint -c .yamllint.yml .github/workflows/go.yml
docker run --rm -v "${PWD}:/repo:ro" -w /repo rhysd/actionlint:1.7.12 .github/workflows/go.yml
markdownlint README.md --config .markdownlint.json
```

### The shell-logic tests (`tests/`)

Reusable workflows carry non-trivial `bash` in `run:` blocks, and `test.yml`'s smoke jobs can only
reach the `dry-run` branches of it. `tests/*.sh` closes that gap: each script extracts a step's `run:`
body straight out of the workflow YAML (via `PyYAML`) and executes it with `helm`/`kubectl` stubbed on
`PATH`, asserting on the recorded arguments. Because the body is extracted rather than copied, a test
can't drift away from the code it covers.

Rules when adding to them:

- Never duplicate workflow logic into the test — extract it by step `name`. Renaming a step breaks its
  test loudly, which is the intent.
- Cover the branches `dry-run` skips (anything guarded by `[ "${DRY_RUN}" != "true" ]`); that's the
  whole reason these exist.
- Each script takes an optional workflow path argument, so you can point it at an older revision
  (`git show HEAD:<path> > /tmp/x.yml`) to confirm a new test actually fails before your fix.
- The scripts themselves are linted by `shellcheck` in `validate-actions` (actionlint only reads `run:`
  blocks, never standalone `.sh` files), so keep them warning-free.

### The doc-version-pin gate (easy to miss)

`ci.yml`'s `validate-doc-pins` job greps `README.md`, `EXAMPLES.md`, and `ENVIRONMENTS.md` for every
`adnvilla/gha-toolkit/.github/workflows/<file>.yml@<ref>` pin and **fails the build unless the file
resolves for that pin**. The rule depends on whether the ref is a version/tag or a branch:

- **Version/tag pins** (e.g. `@v1.5.0`, `@1.5.0`) are validated strictly against that exact ref, so a
  consumer copying the example never gets a broken `uses:`. Documenting an unreleased `@vX.Y.Z` fails CI.
- **Branch pins** (e.g. `@master`) mean "latest": the file only needs to exist in the code under review
  (`HEAD`). This lets you add a new reusable workflow **and** its `@master` examples in a single PR —
  after merge, the branch contains the file. Use `@master` in docs until a tag ships it, then bump.
- Don't reference a workflow file/path that doesn't exist anywhere (typos in the path still fail, since
  they're absent from `HEAD` and every ref).
- Renaming or deleting a workflow file breaks every doc pin that referenced its old path.

Reproduce the check locally:

```bash
grep -ohE 'adnvilla/gha-toolkit/\.github/workflows/[A-Za-z0-9_-]+\.yml@[A-Za-z0-9._/-]+' \
  README.md EXAMPLES.md ENVIRONMENTS.md | sort -u
# For tag pins confirm `git show <tag>:<path>`; for branch pins (e.g. @master) a match in the current
# tree (`git show HEAD:<path>`) or `git show origin/<branch>:<path>` is enough.
```

## 5. Manual / end-to-end testing

`test.yml` (`workflow_dispatch`) is the only way to exercise the reusable workflows without a real
consumer repo. It calls them via the local `./.github/workflows/` ref with safe flags:

- `go.yml` / `node.yml` with `run-tests: false` (this repo has no Go/Node code)
- `release.yml` with `dry-run: true`
- `docker-build-push.yml` build-only (`push: false`)
- `k8s-deploy.yml` with `dry-run: true` (`helm template`, no cluster contact)
- `k8s-canary.yml` / `k8s-bluegreen.yml` with `dry-run: true` for every phase

Because every smoke job is a dry run, cluster-facing logic is only reachable from the `tests/`
shell-logic scripts (see section 4) — `k8s-canary.yml`'s image discovery from the live Helm release is
covered there, not here.

**Not covered by any automated test:** `adopt-existing: true` in `k8s-deploy.yml` (skipped under
`dry-run`; needs a disposable cluster/namespace). Validate it manually against a throwaway namespace if
you touch it.

## 6. Conventions when editing workflows

Every reusable workflow MUST:

1. Trigger on `on: workflow_call`.
2. Declare all `inputs` and `secrets` with a `description`, and sensible `default`s where applicable.
3. Expose a `runs-on` input (string, default `ubuntu-latest`) — **except** where a private network is
   inherent: `k8s-deploy.yml` defaults to `self-hosted`.
4. Stay **generic** — never hardcode a single project's names, hosts, org, or paths. Even the
   `gha-toolkit` repo/ref is resolved dynamically (`job.workflow_repository` / `job.workflow_sha`) so a
   fork works unmodified.
5. Pin third-party action versions (`@v4`, not `@latest`/`@master`) and pin any ad-hoc installed package
   majors (see `release.yml`'s `npm install -g` of `semantic-release@^25` etc.).
6. Never log secrets; require them to be passed explicitly via `secrets:`.

Internal workflows (`ci.yml`, `auto-release.yml`, `test.yml`) are exempt from the reusable rules — they
govern this repo only and are not meant to be called by others.

## 7. Change classification (breaking vs non-breaking)

Because consumers pin versions, input/behavior changes are an API contract.

**Breaking (`feat!:` or `BREAKING CHANGE:` footer, call it out in the PR):**

- Renaming or removing an input/secret/output.
- Changing a default in a way that changes observed behavior/rendered output.
- Renaming or moving a workflow file (breaks `uses:` paths and doc pins).
- Chart: renaming/removing a value, or changing a default that changes rendered manifests.

**Non-breaking:**

- Adding a new **optional** input with a backward-compatible default.
- Bug fixes and performance improvements that preserve the contract.
- Adding a new workflow or a new optional chart value (default off).

Prefer adding a new optional input over changing the meaning of an existing one.

## 8. Editing the Helm chart (`charts/app`)

- It's consumed by every `k8s-deploy.yml` user, versioned by the git ref they pin — treat template
  changes as API changes.
- Optional resources (`serviceAccount`, `autoscaling`, `podDisruptionBudget`, `networkPolicy`) default
  **off**; keep it that way so existing consumers see no behavior change.
- `probes`, `affinity`, `tolerations`, `resources`, `env`/`envFrom` are intentionally raw pass-through
  (`toYaml` from values). Don't add project-specific logic to templates — expose a values override.
- Gotcha: `livenessProbe`/`readinessProbe` ports default to `8080` and are **not** derived from
  `containerPort`. If you change one, keep the docs' warning about overriding the others.
- Manually bump `charts/app/Chart.yaml`'s `version` when a template change is consumer-visible (there is
  no automation for this).
- Update the values table in `charts/app/README.md` for any value added/changed/removed.
- Validate with both `helm template` renders from the harness above (default and all-optional-on).

## 9. Commits and releases

**Conventional Commits are required** for anything that should participate in the release calculus. The
authoritative mapping is `.releaserc.json`'s `commit-analyzer.releaseRules` (NOT the looser descriptions
in `CONTRIBUTING.md`/`ARCHITECTURE.md`):

| Commit type | Release |
| --- | --- |
| `feat:` | minor |
| `fix:`, `perf:`, `revert:`, `docs:`, `refactor:` | patch |
| `feat!:` / `BREAKING CHANGE:` footer | major |
| `chore:`, `test:`, `build:`, `ci:` | no release |

Release flow: commit to `master` -> `ci.yml` lints/validates -> on success `auto-release.yml` fires ->
`semantic-release` (config in `.releaserc.json`) analyzes commits, bumps version, updates `CHANGELOG.md`,
and creates the GitHub release/tag. The changelog commit is `chore(release): <version> [skip ci]`.

`.releaserc.json.example` is the template consumers copy into their own repos — keep it representative of
a typical consumer config; it does not need to match this repo's own `.releaserc.json` exactly.

Do NOT create commits unless the user explicitly asks. When asked, follow the git safety rules (no config
changes, no force-push to protected branches, no `--no-verify`).

## 10. Definition of Done

Before considering a change complete:

- [ ] `yamllint -c .yamllint.yml .github/workflows/` passes.
- [ ] `actionlint` reports nothing, and `shellcheck tests/*.sh` is clean; if you silenced a finding, the
      ignore is scoped and justified (see the `job.workflow_*` trap in section 11 before assuming a
      finding is real).
- [ ] `markdownlint . --config .markdownlint.json --ignore node_modules` is clean.
- [ ] `bash tests/canary-image-resolution.sh` passes; if you touched shell in a `run:` block that
      `dry-run` can't reach, it's covered by a `tests/` script.
- [ ] If the chart changed: both `helm template` renders pass, `Chart.yaml` version bumped if
      consumer-visible, and `charts/app/README.md` values table updated.
- [ ] Docs synced: new/changed reusable workflow -> add a usage example to `EXAMPLES.md`, update
      `README.md`'s workflow list, and update `ARCHITECTURE.md` if the design/inputs changed.
- [ ] All workflow version pins referenced in `README.md`/`EXAMPLES.md`/`ENVIRONMENTS.md` resolve at
      their ref (the `validate-doc-pins` gate).
- [ ] Breaking changes committed as `feat!:`/`BREAKING CHANGE:` and called out explicitly.
- [ ] Commit message uses a Conventional Commit type matching the intended release impact.

## 11. Traps and non-goals

- **Don't tailor a reusable workflow to one project.** No hardcoded org/repo/host/path strings.
- **Don't reference nonexistent version pins in docs** — `validate-doc-pins` will fail CI.
- **Don't leave `adopt-existing: true` on permanently** in `k8s-deploy.yml` examples/docs — it deletes &
  recreates Service/Ingress (new ClusterIP + brief gap) on every deploy. It's a one-time migration switch.
- **Don't use `helm upgrade --dry-run=client` as the dry-run** in `k8s-deploy.yml`; it still contacts the
  cluster. The workflow uses `helm template` for cluster-free dry-run — preserve that.
- **Don't rebuild images per environment.** `docker-build-push.yml` builds once; the same image is
  promoted staging -> production (see `ENVIRONMENTS.md`).
- **Keep guidance in one place.** This file is the source of truth for the harness; when in doubt,
  verify against the actual workflow/chart files rather than duplicating guidance elsewhere.
- **Don't read piped data with `python3 - <<'EOF'`.** The heredoc *is* stdin, so the pipe is silently
  discarded and `json.load(sys.stdin)` sees EOF. Pass data through the environment and keep stdin for
  the program (`VALUES_JSON="$json" python3 <<'PY'`), as `k8s-canary.yml`/`k8s-bluegreen.yml` do.
- **Don't "fix" `job.workflow_repository` / `job.workflow_sha` because actionlint flags them.** Those
  properties are valid (GitHub added them in April 2026) and load-bearing: they resolve the toolkit
  repo/ref for the `charts/app` checkout in the k8s workflows, which is what keeps forks working.
  actionlint's `job` context schema predates them, so it reports `property "workflow_repository" is not
  defined in object type` — a false positive already silenced in `.github/actionlint.yaml` (which only
  applies when actionlint runs from the repository root, as CI does). Issues #29/#30
  are a full round-trip of someone acting on it: the "fix" (`github.workflow_sha`) resolves to the
  *caller's* commit and breaks the chart checkout for every cross-repo consumer.
- **Don't quote the `${FLAGS}` expansions in `go`/`node`/`rust` `run:` steps.** They must word-split so a
  consumer can pass several flags in one string input; that's why each carries a
  `# shellcheck disable=SC2086`. SC2086 stays enabled everywhere else on purpose.
- **Don't raise `conventional-changelog-conventionalcommits` past `^9`** in `release.yml` without
  checking the notes of the release it produces. Paired with the
  `@semantic-release/release-notes-generator@^14` that `semantic-release@^25` pulls in, `^10` renders
  every section empty: the version bump is still correct, so nothing fails — you just get releases and
  `CHANGELOG.md` entries with no content, which is how v1.4.0 through v1.6.2 shipped blank.
- Markdown lint is warning-only in CI (`ci-complete` doesn't fail on it), but YAML, Actions semantics,
  chart, shell-logic, and doc-pin validation are hard gates — keep them green.
