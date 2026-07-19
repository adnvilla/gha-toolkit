# Usage Examples - GitHub Actions Toolkit

This document contains practical examples of how to use the reusable workflows in different scenarios.

## Example 1: Simple Go Project

For a Go project without a database:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ "master", "main" ]
  pull_request:
    branches: [ "master", "main" ]

jobs:
  build-and-test:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
      run-tests: true
```

## Example 2: Go Project with PostgreSQL

For a project that needs PostgreSQL for tests:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]

jobs:
  build-and-test:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
      postgres-version: '16'
      run-tests: true
      postgres-dsn: 'host=localhost user=postgres password=postgres dbname=testdb port=5432 sslmode=disable'
```

## Example 3: Complete CI/CD (Build + Release)

Complete pipeline that runs tests and then creates automatic releases:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]

jobs:
  build-and-test:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
      postgres-version: '15'
```

```yaml
# .github/workflows/release.yml
name: Release

on:
  workflow_run:
    workflows: ["CI"]
    types:
      - completed
    branches:
      - master

jobs:
  semantic-release:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    uses: adnvilla/gha-toolkit/.github/workflows/release.yml@v1.0.0
    permissions:
      contents: write
    with:
      node-version: '20'
      dry-run: false
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Example 4: Multiple Jobs in CI

If you need to run multiple jobs before release:

```yaml
# .github/workflows/ci.yml
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
      go-version: '1.24'
  
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-go@v4
        with:
          go-version: '1.24'
      - name: golangci-lint
        uses: golangci/golangci-lint-action@v3

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Gosec Security Scanner
        uses: securego/gosec@master
        with:
          args: './...'
```

## Example 5: Dry-Run Release

To test the release process without publishing:

```yaml
# .github/workflows/test-release.yml
name: Test Release

on:
  workflow_dispatch:  # Run manually

jobs:
  test-release:
    uses: adnvilla/gha-toolkit/.github/workflows/release.yml@v1.0.0
    permissions:
      contents: write
    with:
      dry-run: true
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Example 6: Use a Specific Version of the Workflow

Instead of using `@master`, you can use tags for greater stability:

```yaml
jobs:
  build:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
```

## Example 7: Multiple Go Versions (Matrix)

If you want to test with multiple Go versions:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]

jobs:
  test:
    strategy:
      matrix:
        go-version: ['1.22', '1.23', '1.24']
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: ${{ matrix.go-version }}
```

## Example 8: Node.js Monorepo with Docker + Kubernetes Deploy (self-hosted)

Full CI/CD pipeline for a pnpm monorepo (e.g. a Next.js app) that builds a Docker image and deploys
it to a self-hosted k3s cluster — mirrors what `navi-admin` runs today, but as three chained calls
instead of ~150 lines of inline YAML.

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    uses: adnvilla/gha-toolkit/.github/workflows/node.yml@v1.0.0
    with:
      node-version: '20'
      package-manager: 'pnpm'
```

```yaml
# .github/workflows/cd.yml
name: CD

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
    branches: [main]
  workflow_dispatch:
    inputs:
      kube_context:
        description: 'kubectl context to deploy to'
        required: true
        default: local
        type: choice
        options: [local, raspi-k3s]

jobs:
  build:
    if: >-
      github.event_name == 'workflow_dispatch' ||
      github.event.workflow_run.conclusion == 'success'
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@v1.0.0
    with:
      dockerfile: apps/web/Dockerfile
      image-name: my-app-web
      registry-host: registry.example.local:5001
      verify-insecure-registry: true
      runs-on: self-hosted

  deploy:
    needs: build
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-deploy.yml@v1.0.0
    with:
      toolkit-ref: v1.0.0   # same tag used above, pins charts/app to that version
      release-name: my-app-web
      namespace: my-app
      kube-context: ${{ github.event.inputs.kube_context || 'local' }}
      values-file: k8s/values-local.yaml
      image: ${{ needs.build.outputs.image }}
```

```yaml
# k8s/values-local.yaml — replaces hand-written deployment.yml/service.yml/ingress.yml
fullnameOverride: my-app-web

containerPort: 3000

env:
  - name: HOSTNAME
    value: "0.0.0.0"
  - name: PORT
    value: "3000"

service:
  targetPort: 3000

# Probe ports don't inherit containerPort automatically — override them too
livenessProbe:
  httpGet:
    path: /
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 30
readinessProbe:
  httpGet:
    path: /
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 10

ingress:
  enabled: true
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
  host: my-app.local

# Keep pods off the control-plane node if it isn't configured to pull from the local registry
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: node-role.kubernetes.io/control-plane
              operator: DoesNotExist
```

See `charts/app/README.md` for the full list of values you can override this way.

## Important Notes

### Permissions

Make sure the calling workflow has the necessary permissions:

```yaml
permissions:
  contents: write  # For semantic-release
```

### Secrets

Secrets must be passed explicitly:

```yaml
secrets:
  github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Semantic Release Configuration

Don't forget to add `.releaserc.json` to your project. See `.releaserc.json.example` for reference.

### Conventional Commits

Examples of commits that generate releases:

```bash
# Generates PATCH (1.0.0 -> 1.0.1)
git commit -m "fix: correct validation error"

# Generates MINOR (1.0.0 -> 1.1.0)
git commit -m "feat: add new feature"

# Generates MAJOR (1.0.0 -> 2.0.0)
git commit -m "feat!: breaking compatibility change

BREAKING CHANGE: The API has completely changed"

# Does not generate release
git commit -m "chore: update dependencies"
git commit -m "docs: improve documentation"
```
