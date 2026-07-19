# GitHub Actions Toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Release](https://img.shields.io/github/v/release/adnvilla/gha-toolkit)](https://github.com/adnvilla/gha-toolkit/releases)

Reusable GitHub Actions workflows for CI/CD. Centralizes logic, reduces duplication, and simplifies maintenance across multiple projects.

## 🎯 What Is It For?

This repository is a **workflow library** that other projects can use:

```yaml
# In your project - just 10 lines
jobs:
  build:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
```

Instead of having ~200 lines of duplicated workflows in each project.

**Benefits**:
- ✅ 95% less duplicated code
- ✅ Centralized updates
- ✅ Controlled versioning (each project uses the version it needs)
- ✅ Simplified maintenance

## 📚 Documentation

- **[EXAMPLES.md](EXAMPLES.md)** - Practical usage examples
- **[ENVIRONMENTS.md](ENVIRONMENTS.md)** - Staging/production environments, approval gates
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - How to add workflows
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Technical details

## 🏷️ Versioning

This toolkit uses automatic semantic versioning:

```yaml
# Specific version (RECOMMENDED for production)
uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0

# Latest 1.x version (auto-updates)
uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1

# Latest version (development)
uses: adnvilla/gha-toolkit/.github/workflows/go.yml@master
```

Each commit with `feat:` or `fix:` automatically generates a new version.

## 📋 Available Workflows

### 1. Go Build and Test — no external services (`go-base.yml`)

Build and test for Go libraries/projects that don't need a database or other services. Prefer this
over `go.yml` unless your tests require PostgreSQL.

**Usage**:

```yaml
name: CI

on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]

jobs:
  test:
    uses: adnvilla/gha-toolkit/.github/workflows/go-base.yml@v1.0.0
    with:
      go-version: '1.24'           # Optional, default: '1.24'
      run-tests: true              # Optional, default: true
```

### 2. Go Build and Test — with PostgreSQL (`go.yml`)

Same as `go-base.yml`, but spins up a PostgreSQL service container and passes `POSTGRES_DSN` to the
test step. Use this when your tests need a database; otherwise use `go-base.yml`.

**Usage**:

```yaml
name: CI

on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]

jobs:
  test:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'           # Optional, default: '1.24'
      postgres-version: '15'        # Optional, default: '15'
      run-tests: true              # Optional, default: true
      postgres-dsn: 'host=localhost user=postgres password=postgres dbname=postgres port=5432 sslmode=disable'  # Optional
```

### 3. Semantic Release (`release.yml`)

Generates automatic releases with semantic versioning.

**Usage**:

```yaml
name: Release

on:
  workflow_run:
    workflows: ["CI"]
    types: [completed]
    branches: [master]

jobs:
  release:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    uses: adnvilla/gha-toolkit/.github/workflows/release.yml@v1.0.0
    permissions:
      contents: write
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

**Required configuration**: Copy `.releaserc.json.example` to your project as `.releaserc.json`

### 4. Node Build and Test (`node.yml`)

Install/build/lint/typecheck/test for Node.js/TypeScript projects (pnpm, npm or yarn), including
monorepo/workspace layouts.

**Usage**:

```yaml
jobs:
  ci:
    uses: adnvilla/gha-toolkit/.github/workflows/node.yml@v1.2.0
    with:
      node-version: '20'          # Optional, default: '20'
      package-manager: 'pnpm'     # Optional, default: 'pnpm' (pnpm | npm | yarn)
      run-build: true             # Optional, default: true
      run-lint: true              # Optional, default: true
      run-typecheck: true         # Optional, default: true
      run-tests: true             # Optional, default: true
```

### 5. Docker Build and Push (`docker-build-push.yml`)

Builds a Docker image and pushes it to a registry (public or a private/local insecure one), tagging
it with the short commit SHA plus any extra tags. Outputs `image` so a following job can consume the
exact ref that was built.

**Auth:** `ghcr.io/...` auto-logs in with `github.token` (set `permissions: packages: write`). For
Docker Hub or other registries, pass `secrets: registry-username` / `registry-password`. Local
insecure registries need neither.

**Usage** (local/insecure registry):

```yaml
jobs:
  build:
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@v1.2.0
    with:
      dockerfile: apps/web/Dockerfile
      image-name: my-app
      registry-host: registry.example.local:5001
      verify-insecure-registry: true   # For local/self-hosted registries
      runs-on: self-hosted
```

**Usage** (GitHub Container Registry):

```yaml
jobs:
  build:
    permissions:
      contents: read
      packages: write
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@v1.2.0
    with:
      dockerfile: apps/web/Dockerfile
      image-name: my-app
      registry-host: ghcr.io/my-org
```

### 6. Kubernetes Deploy (`k8s-deploy.yml`)

Deploys to Kubernetes via Helm using the generic chart shipped in this repo (`charts/app`), so
consumers only need a small `values.yaml` instead of hand-written manifests. Runs
`helm upgrade --install --create-namespace --wait --atomic`, bound to a GitHub Environment
(`environment` input, default `production`) for deployment history and optional approval gates —
see [ENVIRONMENTS.md](ENVIRONMENTS.md).

**Usage** (chained after `docker-build-push.yml` via `needs`):

```yaml
jobs:
  build:
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@v1.2.0
    with:
      dockerfile: apps/web/Dockerfile
      image-name: my-app
      registry-host: registry.example.local:5001
      runs-on: self-hosted

  deploy:
    needs: build
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-deploy.yml@v1.2.0
    with:
      release-name: my-app
      namespace: my-app
      kube-context: local
      values-file: k8s/values-local.yaml
      image: ${{ needs.build.outputs.image }}
      # environment defaults to 'production' — set explicitly for a staging deploy,
      # see ENVIRONMENTS.md
```

See `charts/app/README.md` for the full values reference, `ENVIRONMENTS.md` for staging/production
setup, and `EXAMPLES.md` for a complete CI → build → deploy pipeline.

## 🚀 Future Workflows

- Python (pytest, coverage, lint)
- Terraform (plan, apply, security scan)

Have an idea? Open an [issue](https://github.com/adnvilla/gha-toolkit/issues) or contribute following [CONTRIBUTING.md](CONTRIBUTING.md)

## 🔧 Semantic Release Configuration

To use the release workflow, create `.releaserc.json` in your project:

```json
{
  "branches": ["master"],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/changelog",
    "@semantic-release/git",
    "@semantic-release/github"
  ]
}
```

See `.releaserc.json.example` for complete configuration.

## 📝 Conventional Commits

Automatic versioning works with commits in this format:

- `feat:` → minor version (1.0.0 → 1.1.0)
- `fix:`, `perf:`, `revert:`, `docs:`, `refactor:` → patch version (1.0.0 → 1.0.1)
- `feat!:` or a `BREAKING CHANGE:` footer → major version (1.0.0 → 2.0.0)
- `chore:`, `test:`, `build:`, `ci:` → no release

See the `commit-analyzer` `releaseRules` in `.releaserc.json` for the authoritative mapping.

## 🚀 Getting Started

### 1. Make the initial commit for this repo

```bash
cd d:\Code\gha-toolkit
git add .
git commit -m "feat: initial release of reusable workflows toolkit

BREAKING CHANGE: Initial release"
git push origin master
```

This will automatically create version `v1.0.0`.

### 2. Use in your projects

Wait for `v1.0.0` to be available, then in your Go projects:

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  build:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
```

See [EXAMPLES.md](EXAMPLES.md) for more examples.

## 📚 References

- [Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [Semantic Release](https://semantic-release.gitbook.io/)
- [Conventional Commits](https://www.conventionalcommits.org/)

## 📄 License

MIT
