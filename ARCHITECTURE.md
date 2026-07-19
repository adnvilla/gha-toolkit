# Architecture - GitHub Actions Toolkit

This document explains the technical design and architecture of the reusable workflows toolkit.

## Overview

The toolkit follows a **two-tier architecture**:

1. **Reusable Workflows**: Generic workflows that other projects can consume
2. **Internal Workflows**: Workflows that manage the toolkit's own lifecycle

## Reusable Workflows

### go-base.yml

**Purpose:** CI pipeline for Go projects/libraries that don't need any external service (no
PostgreSQL). Same `build`/`test` steps as `go.yml` minus the service container.

**Trigger:**
```yaml
on:
  workflow_call:
```

**Inputs:**
- `go-version` (string): Go version to use (default: '1.24')
- `run-tests` (boolean): Whether to execute tests (default: true)
- `test-flags` / `build-flags` (string): Extra flags for `go test`/`go build` (default: `-v`)
- `runs-on` (string): Runner label (default: `ubuntu-latest`)

**Usage Pattern:**
```yaml
jobs:
  ci:
    uses: adnvilla/gha-toolkit/.github/workflows/go-base.yml@v1.0.0
    with:
      go-version: '1.24'
```

### go.yml

**Purpose:** Provides a complete CI pipeline for Go projects with optional PostgreSQL integration.

**Trigger:**
```yaml
on:
  workflow_call:
```

**Inputs:**
- `go-version` (string): Go version to use (default: '1.24')
- `postgres-version` (string): PostgreSQL version (default: '15')
- `run-tests` (boolean): Whether to execute tests (default: true)
- `postgres-dsn` (string): PostgreSQL connection string (optional)

**Jobs:**

1. **build:**
   - Sets up Go environment with specified version
   - Builds the project with `go build -v ./...`
   - Validates compilation without running tests

2. **test:**
   - Depends on `build` job completion
   - Conditionally starts PostgreSQL service (if `postgres-dsn` provided)
   - Runs tests with `go test -v ./...`
   - Uses environment variable for database connection

**Design Decisions:**
- Separates build and test for better error diagnosis
- PostgreSQL is optional to support projects without databases
- Uses service containers (more efficient than installing PostgreSQL)
- Allows customization of connection string for different schemas

**Usage Pattern:**
```yaml
jobs:
  ci:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
      postgres-version: '16'
```

### release.yml

**Purpose:** Implements semantic versioning and automatic releases using conventional commits.

**Trigger:**
```yaml
on:
  workflow_call:
```

**Inputs:**
- `node-version` (string): Node.js version for semantic-release (default: '20')
- `dry-run` (boolean): Test mode without publishing (default: false)

**Secrets:**
- `github-token`: Required for creating releases and tags

**Jobs:**

1. **semantic-release:**
   - Checks out repository with full history (`fetch-depth: 0`)
   - Sets up Node.js environment
   - Installs semantic-release and plugins
   - Analyzes commits to determine version
   - Creates tags and GitHub releases

**Design Decisions:**
- Requires full git history to analyze all commits
- Uses semantic-release plugins for automation
- Supports dry-run for testing
- Requires explicit token passing (security)

**Dependencies:**
```json
{
  "semantic-release": "^19.0.0",
  "@semantic-release/commit-analyzer": "^9.0.0",
  "@semantic-release/release-notes-generator": "^10.0.0",
  "@semantic-release/github": "^8.0.0"
}
```

**Usage Pattern:**
```yaml
jobs:
  release:
    uses: adnvilla/gha-toolkit/.github/workflows/release.yml@v1.0.0
    permissions:
      contents: write
    with:
      dry-run: false
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

### node.yml

**Purpose:** CI pipeline for Node.js/TypeScript projects — install, build, lint, typecheck and test,
including workspace/monorepo layouts.

**Trigger:**
```yaml
on:
  workflow_call:
```

**Inputs:**
- `node-version` (string): Node.js version (default: '20')
- `package-manager` (string): `pnpm`, `npm` or `yarn` (default: `pnpm`)
- `pnpm-version` (string): pnpm version, only used when `package-manager` is `pnpm` (default: '9.14.2')
- `install-args` (string): Extra args for the install command (default: `--frozen-lockfile`)
- `run-build` / `run-lint` / `run-typecheck` / `run-tests` (boolean): Each independently toggleable (default: true)
- `runs-on` (string): Runner label (default: `ubuntu-latest`)

**Jobs:**

1. **build:**
   - `pnpm/action-setup` (only for `package-manager: pnpm`) then `actions/setup-node` with native
     package-manager caching (`cache: <package-manager>`)
   - Installs dependencies **only if** at least one of `run-build`/`run-lint`/`run-typecheck`/`run-tests`
     is true — skips install entirely when the caller wants none of them
   - Runs the equivalent build/lint/typecheck/test command for the selected package manager
     (`pnpm -r run X`, `npm run X --workspaces --if-present`, or `yarn workspaces run X`)

**Design Decisions:**
- Generic across the three major Node package managers instead of a pnpm-only workflow, so it fits
  any future JS/TS project, not just pnpm monorepos
- Uses `actions/setup-node`'s built-in cache instead of manually caching the pnpm store (simpler than
  a hand-rolled `actions/cache` step)

### docker-build-push.yml

**Purpose:** Builds a Docker image and optionally pushes it to a registry — public (ghcr.io, Docker
Hub) or a private/local insecure one. Tags with the short commit SHA plus any `extra-tags`.

**Trigger:**
```yaml
on:
  workflow_call:
```

**Inputs:**
- `dockerfile` (string, required), `context` (string, default `.`)
- `image-name` (string, required), `registry-host` (string, required) — host plus optional org path,
  e.g. `ghcr.io/org`, `docker.io/org`, or `registry.example.local:5001`
- `extra-tags` (string, one tag per line, default `latest`)
- `build-args` (string, one `KEY=VALUE` per line)
- `verify-insecure-registry` (boolean): Preflight-checks the Docker daemon can reach the registry
  before building (only relevant when `push` is true; default: false)
- `push` (boolean): Set to false to only validate that the image builds, without publishing
  (default: true)
- `runs-on` (string, default `ubuntu-latest`)

**Secrets (optional):**
- `registry-username` / `registry-password`: `docker login` credentials for Docker Hub or any
  non-ghcr registry. When both are set they take precedence over the automatic ghcr.io login.
- **ghcr.io auto-login:** if `registry-host` starts with `ghcr.io` and no explicit secrets are
  passed, the workflow logs in with `${{ github.actor }}` / `${{ github.token }}`. Callers must set
  `permissions: packages: write` on the job (or workflow) for the push to succeed.
- Local/insecure registries: omit both secrets — login is skipped (previous behavior).

**Outputs:**
- `image`: full ref of the primary tag, e.g. `registry.example.local:5001/my-app:abc1234`
- `short-sha`: the short commit SHA used as the primary tag

**Design Decisions:**
- Tag/build-arg lists are parsed into bash arrays inside a single step rather than interpolating
  multi-line `GITHUB_OUTPUT` values into a `run:` line, which breaks shell line-continuation
- Outputs `image` so a downstream `k8s-deploy.yml` job can consume the exact built ref via
  `needs.<job>.outputs.image` without recomputing the tag
- Registry auth is opt-in by host/secrets so the navi-admin local-registry path stays zero-config,
  while the documented `ghcr.io/org` example works without extra secret wiring

### k8s-deploy.yml

**Purpose:** Deploys an application to Kubernetes via Helm, using the generic chart shipped in this
repo (`charts/app`) unless the caller supplies its own chart. Replaces raw `kubectl apply` +
`kubectl set image` + `kubectl rollout status` with a single atomic `helm upgrade --install`.

**Trigger:**
```yaml
on:
  workflow_call:
```

**Inputs:**
- `toolkit-ref` (string, optional, default `''`): override for the git ref of `adnvilla/gha-toolkit`
  to pull `charts/app` from. Left empty, it auto-resolves to `job.workflow_sha` (the exact commit this
  workflow was called at — see Design Decisions below), so the chart version always matches the
  workflow version with **no input needed**. Only set this to test a chart from a branch. Ignored when
  `use-local-chart` is true.
- `ref` (string, optional, default `''`): git ref/SHA of the *calling* repo to check out (for the
  values file). Left empty, defaults to whatever the run's own context resolves to — which for
  `workflow_run`-triggered CD is the default branch HEAD, **not** the commit that triggered the event.
  Pass `github.event.workflow_run.head_sha` explicitly in that case (see `EXAMPLES.md` Example 8).
- `use-local-chart` (boolean, default false) / `chart-path` (string, default `charts/app`)
- `release-name`, `namespace`, `kube-context`, `values-file`, `image` (all string, required)
- `helm-set` (string, one `KEY=VALUE` per line, for one-off overrides)
- `wait` / `atomic` (boolean, default true), `timeout` (string, default `180s`)
- `helm-version` (string, default `v3.16.2`, installed via `azure/setup-helm` if not already present)
- `dry-run` (boolean, default false): renders the chart client-side via `helm template` — no
  kube-context/cluster access needed in this mode, used by `test.yml` to smoke-test the workflow.
  (`helm upgrade --dry-run=client` is intentionally *not* used: it still contacts the cluster and
  would hit whatever context is current in the runner's kubeconfig when context selection is skipped.)
- `adopt-existing` (boolean, default false): one-time migration switch — deletes any pre-existing
  `Deployment`/`Service`/`Ingress` named `release-name` in `namespace` before the Helm upgrade, so a
  service previously managed by raw `kubectl apply` can be adopted. See `charts/app/README.md` for why
  this deletes rather than adopts-in-place (a naive adopt-by-annotation was tested and found to
  silently break Service routing).
- `environment` (string, default `'production'`) / `environment-url` (string, default `''`): binds the
  job to a GitHub Environment — see `ENVIRONMENTS.md`. The default means every existing caller is
  automatically treated as production with no `with:` changes.
- `runs-on` (string, default `self-hosted` — deploying to a private cluster almost always requires a
  runner that already has network access and a working kubeconfig)

**Jobs:**

1. **deploy:** (job-level `environment: { name: inputs.environment, url: inputs.environment-url }`)
   - Checks out the calling repo at `ref` (for `values-file`) and, unless `use-local-chart`, checks out
     `${{ job.workflow_repository }}@${{ inputs.toolkit-ref || job.workflow_sha }}` into
     `.gha-toolkit-chart/` to get the chart
   - Selects the `kube-context` (skipped entirely when `dry-run` is true)
   - If `adopt-existing`, deletes any pre-existing `deployment`/`service`/`ingress` matching
     `release-name` in `namespace`
   - Splits `image` into `image.repository`/`image.tag` and runs
     `helm upgrade --install --create-namespace -f <values-file> --set image.repository=... --set image.tag=... --wait --atomic`
     (or `helm template` with the same values/`--set` flags when `dry-run` is true — no
     `--create-namespace`/`--wait`/`--atomic`/`--timeout`, and no cluster contact)

**Design Decisions:**
- No `Namespace` template in the chart — `--create-namespace` replaces the manual "apply namespace
  first" ordering workaround that raw `kubectl apply -f dir/` needs (alphabetical ordering otherwise
  creates `deployment`/`ingress` before the namespace exists)
- `--atomic` gives automatic rollback on a failed rollout, which the previous `kubectl set image` +
  `kubectl rollout status` approach didn't have
- The chart is versioned inside `gha-toolkit` itself and auto-resolved via `job.workflow_repository`/
  `job.workflow_sha` — the context GitHub documents specifically for a reusable workflow to check out
  its own repo at the exact ref it was called with — so a project pinned to `k8s-deploy.yml@v1.4.0`
  always deploys the exact chart shipped in that tag with zero extra input. This also means a fork of
  `gha-toolkit` works unmodified (no hardcoded `adnvilla/gha-toolkit` string).
- `environment:` can only be declared inside this workflow's own job — GitHub rejects `environment:` on
  a job that also has `uses:` (a reusable workflow call). Because a reusable workflow's execution
  context (identity, permissions, billing) always belongs to the *calling* repo, the environment
  referenced here resolves against each consumer's own Settings → Environments independently; this
  toolkit doesn't need to know they exist. This specific cross-repo resolution behavior is documented
  by GitHub but wasn't verified against a second live repo while building it — see `ENVIRONMENTS.md`'s
  "Known limitation" section.

### Helm Chart: charts/app

A generic, reusable Helm chart for stateless HTTP applications, living in this repo so every
consumer of `k8s-deploy.yml` shares one implementation instead of hand-writing
`Deployment`/`Service`/`Ingress` manifests per project.

- `Deployment`, `Service`, and an optional `Ingress` (rendered only when `ingress.enabled`)
- `affinity`, `tolerations`, `nodeSelector`, `env`, `envFrom`, `resources`, `livenessProbe` and
  `readinessProbe` are raw pass-through blocks (`toYaml` straight from `values.yaml`) — the chart
  doesn't need new features for project-specific quirks (e.g. node affinity rules to avoid scheduling
  on a control-plane node), only a values override
- See `charts/app/README.md` for the full values reference and `Chart.yaml` version bump policy

## Self-hosted runner prerequisites

`docker-build-push.yml` (with a local registry) and `k8s-deploy.yml` are designed to run on a
**self-hosted** runner with network access to the target registry/cluster — this is not obvious from
the workflow YAML alone. The runner machine must have:

- **Docker daemon** configured with the registry host under `insecure-registries` (Docker Desktop:
  Settings → Docker Engine) if pushing to a local/private registry without TLS
- **kubectl**, with every context passed via `kube-context` already defined locally — the kubeconfig
  lives on the runner machine and is never passed as a GitHub secret, matching how `navi-admin`'s
  existing pipeline works today
- **helm** — `k8s-deploy.yml` installs it via `azure/setup-helm` if missing, but a pre-installed
  version avoids the extra download on every run
- **Node/pnpm/corepack** available if `node.yml` also runs on that runner

`REGISTRY_HOST` and `KUBE_CONTEXT` are the recommended repo/org-level GitHub Variables for consumers
to standardize on (see `navi-admin`'s `cd.yml` for the pattern), referenced as
`${{ vars.REGISTRY_HOST }}` / `${{ vars.KUBE_CONTEXT }}` in the calling workflow.

## Internal Workflows

### ci.yml

**Purpose:** Validates the toolkit itself - lints YAML/Markdown and validates the Helm chart.

**Trigger:**
```yaml
on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]
```

**Jobs:**

1. **validate-workflows:** Validates all `.yml` files with `yamllint`
2. **validate-markdown:** Validates all `.md` files with `markdownlint`
3. **validate-chart:** `helm lint charts/app` and `helm template charts/app` with sample values, to
   catch broken chart templates before they ship in a tag
4. **ci-complete:** Consolidated status gate over the three jobs above

**Configuration Files:**
- `.yamllint.yml`: YAML linting rules
- `.markdownlint.json`: Markdown linting rules

**Design Decisions:**
- Runs on every push/PR to maintain quality
- Blocks merging if validation fails
- Uses GitHub Actions for consistency

### auto-release.yml

**Purpose:** Generates semantic versions for the toolkit itself.

**Trigger:**
```yaml
on:
  workflow_run:
    workflows: ["CI"]
    types: [completed]
    branches: [master]
```

**Conditional Execution:**
```yaml
if: ${{ github.event.workflow_run.conclusion == 'success' }}
```

**Jobs:**

1. **release:**
   - Waits for `ci.yml` to complete successfully
   - Calls `release.yml` as a reusable workflow
   - Creates tags like `v1.0.0`, `v1.1.0`, etc.

**Design Decisions:**
- Only runs after CI passes (quality gate)
- Only runs on `master` branch
- Uses the same `release.yml` that consumers use (dogfooding)
- Automatically triggered (no manual intervention)

## Workflow Interaction Diagram

```
┌───────────────────────────────────────────────────────────────────┐
│                   External Project (e.g. navi-admin)                │
├───────────────────────────────────────────────────────────────────┤
│                                                                     │
│  .github/workflows/ci.yml                                          │
│    uses: gha-toolkit/.github/workflows/{go,go-base,node}.yml@v1.x  │
│                                                                     │
│  .github/workflows/cd.yml                                          │
│    build:  uses: .../docker-build-push.yml@v1.x                    │
│                       │ outputs.image                               │
│                       ▼                                            │
│    deploy: uses: .../k8s-deploy.yml@v1.x  (needs: build)           │
│              -f k8s/values-<env>.yaml  --image ${{ outputs.image }}│
│                                                                     │
│  .github/workflows/release.yml                                     │
│    uses: gha-toolkit/.github/workflows/release.yml@v1.x            │
│                                                                     │
└───────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────┐
│                       gha-toolkit Repository                        │
├───────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Reusable Workflows:                                                │
│    go-base.yml, go.yml, node.yml,                                   │
│    docker-build-push.yml, k8s-deploy.yml, release.yml               │
│                                                                     │
│  charts/app/  ◄── generic Helm chart, pulled by k8s-deploy.yml      │
│               at the same git ref (toolkit-ref) the caller pinned   │
│                                                                     │
│  Internal Workflows:                                                │
│    ci.yml (lint + validate-chart) ──► auto-release.yml ──► release.yml│
│                                                                     │
└───────────────────────────────────────────────────────────────────┘
```

## Version Management

### Semantic Versioning Flow

```
Conventional Commit → Commit Analyzer → Version Calculator → Tag Creator → Release Publisher
```

**Commit Types → Version Impact** (per the `commit-analyzer` `releaseRules` in `.releaserc.json`):

| Type | Example | Version Change |
|------|---------|----------------|
| `feat:` | `feat: add new input` | 1.0.0 → 1.1.0 (MINOR) |
| `fix:` | `fix: correct validation` | 1.0.0 → 1.0.1 (PATCH) |
| `perf:` | `perf: reduce checkout time` | 1.0.0 → 1.0.1 (PATCH) |
| `revert:` | `revert: revert previous change` | 1.0.0 → 1.0.1 (PATCH) |
| `docs:` | `docs: clarify usage example` | 1.0.0 → 1.0.1 (PATCH) |
| `refactor:` | `refactor: simplify job steps` | 1.0.0 → 1.0.1 (PATCH) |
| `feat!:` | `feat!: change API` | 1.0.0 → 2.0.0 (MAJOR) |
| `BREAKING CHANGE:` | In commit body | 1.0.0 → 2.0.0 (MAJOR) |
| `chore:`, `test:`, `build:`, `ci:` | Maintenance/CI-only | No release |

### Configuration (.releaserc.json)

This repository's own `.releaserc.json` (used by `auto-release.yml`):

```json
{
  "branches": ["master"],
  "plugins": [
    ["@semantic-release/commit-analyzer", { "preset": "conventionalcommits", "releaseRules": ["..."] }],
    ["@semantic-release/release-notes-generator", { "preset": "conventionalcommits", "presetConfig": { "...": "..." } }],
    "@semantic-release/changelog",
    ["@semantic-release/git", { "assets": ["CHANGELOG.md"], "message": "chore(release): ..." }],
    ["@semantic-release/github", { "successComment": false, "failComment": false, "releasedLabels": false }]
  ]
}
```

See the actual `.releaserc.json` for the full `releaseRules` and `presetConfig`; `.releaserc.json.example` shows the equivalent config consumers should copy into their own projects.

**Plugin Roles:**
- **commit-analyzer**: Determines if a release is needed and the version bump, per the custom `releaseRules` (see the table above)
- **release-notes-generator**: Creates changelog notes from commits, grouped into sections via `presetConfig`
- **changelog**: Writes/updates `CHANGELOG.md`
- **git**: Commits `CHANGELOG.md` back to the repo as `chore(release): <version> [skip ci]`
- **github**: Publishes the GitHub release and tag

## Extensibility

### Adding New Workflows

1. Create workflow with `workflow_call` trigger
2. Define inputs clearly with descriptions
3. Add examples to `EXAMPLES.md`
4. Update `README.md`
5. Commit with `feat: add X workflow`

### Modifying Existing Workflows

**Breaking Changes:**
- Changing input names
- Removing inputs
- Changing default behavior

**Non-Breaking Changes:**
- Adding optional inputs
- Fixing bugs
- Improving performance

## Security Considerations

### Secret Handling

- Secrets are never logged or exposed
- Must be passed explicitly with `secrets:`
- Use `GITHUB_TOKEN` when possible (auto-rotated)

### Permissions

Reusable workflows inherit caller's permissions:

```yaml
permissions:
  contents: write  # Needed for releases
  pull-requests: read  # Needed for PR comments
```

### Dependency Management

- Pin action versions (`@v3`, not `@latest`)
- Review dependencies regularly
- Use Dependabot for updates

## Testing

### Manual Testing

```bash
# Test YAML validation
yamllint .github/workflows/*.yml

# Test Markdown validation
markdownlint *.md

# Test the Helm chart (no cluster required)
helm lint charts/app
helm template charts/app --set image.repository=test --set image.tag=test

# Test release (dry-run)
npx semantic-release --dry-run
```

`test.yml` (`workflow_dispatch`) exercises `go.yml`, `release.yml`, `node.yml`,
`docker-build-push.yml` (build-only) and `k8s-deploy.yml` (`helm template` dry-run) against this repo
without needing real Go/Node projects, a registry, or a cluster.

### Integration Testing

- Create test repository
- Use workflows from branch before merging
- Verify outputs and behaviors

## Performance

### Optimization Strategies

1. **Caching:**
   - Go modules cached with `actions/cache`
   - `node.yml` uses `actions/setup-node`'s native package-manager cache
   - Node modules cached in release workflow

2. **Parallel Execution:**
   - Build and test run sequentially (dependency)
   - Multiple reusable workflows can run in parallel
   - `docker-build-push.yml` and `k8s-deploy.yml` are separate workflows chained via `needs`, so a
     project that only needs to build/push (no deploy) can skip the deploy job entirely

3. **Resource Usage:**
   - Every reusable workflow accepts a `runs-on` input (default `ubuntu-latest`, except
     `k8s-deploy.yml` which defaults to `self-hosted`) — GitHub-hosted where possible, self-hosted
     only where a private registry/cluster requires it
   - PostgreSQL as service container (lightweight)

## Monitoring

### Workflow Status

Check workflow runs at:
```
https://github.com/adnvilla/gha-toolkit/actions
```

### Release History

Check releases at:
```
https://github.com/adnvilla/gha-toolkit/releases
```

## Future Considerations

### Potential Additions

- Python project workflow
- Multi-platform Docker builds (`docker buildx` + QEMU)
- Security scanning integration (e.g. `gosec`, `trivy`)
- Kustomize-style overlays or per-environment values presets in `charts/app` for promoting the same
  image across `dev`/`staging`/`prod` without duplicating `values-<env>.yaml` files per project
- Publishing `charts/app` as an OCI artifact (`helm push`) instead of a git checkout, once multiple
  charts exist and a registry is worth the extra moving part

### Backward Compatibility

- Version tags are immutable
- Consumers should pin to specific versions
- Major version updates documented clearly

## References

- [GitHub Actions Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [Semantic Release](https://semantic-release.gitbook.io/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Semantic Versioning](https://semver.org/)
