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
      node-version: '22'
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
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version: '1.24'
      - name: golangci-lint
        uses: golangci/golangci-lint-action@v3

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
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
    uses: adnvilla/gha-toolkit/.github/workflows/node.yml@v1.2.0
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
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@v1.2.0
    with:
      # workflow_run's own GITHUB_SHA is the default branch HEAD, not the commit CI
      # actually validated — pass the real one explicitly so build/deploy never race ahead.
      ref: ${{ github.event.workflow_run.head_sha || github.sha }}
      dockerfile: apps/web/Dockerfile
      image-name: my-app-web
      registry-host: registry.example.local:5001
      verify-insecure-registry: true
      runs-on: self-hosted

  deploy:
    needs: build
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-deploy.yml@v1.2.0
    with:
      ref: ${{ github.event.workflow_run.head_sha || github.sha }}
      # toolkit-ref not needed: k8s-deploy.yml auto-pins charts/app to this same
      # workflow's own commit (job.workflow_sha) unless you override it explicitly.
      environment: production   # default already, spelled out here for clarity
      release-name: my-app-web
      namespace: my-app
      kube-context: ${{ github.event.inputs.kube_context || 'local' }}
      values-file: k8s/values-local.yaml
      image: ${{ needs.build.outputs.image }}
```

Want a staging environment in front of this (PRs deploy automatically, production stays exactly as
above)? See [ENVIRONMENTS.md](ENVIRONMENTS.md) for the full recipe.

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

**Prefix-only Ingress host.** If the cluster publishes `INGRESS_BASE_DOMAIN` (GitHub Actions var on
the caller repo/environment, or env on the self-hosted runner), omit `ingress.host` and pass a
prefix. The workflow composes `{prefix}.{INGRESS_BASE_DOMAIN}` and will not overwrite a host already
set in values (the `host: my-app.local` example above keeps working). Local charts
(`use-local-chart: true`) are left alone.

```yaml
# .github/workflows/cd.yml — pin @master until a release ships ingress-prefix
jobs:
  deploy:
    needs: build
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-deploy.yml@master
    with:
      release-name: my-app-web
      namespace: my-app
      kube-context: local
      values-file: k8s/values-local.yaml
      image: ${{ needs.build.outputs.image }}
      ingress-prefix: my-app          # optional; defaults to release-name
      environment-url: https://my-app.example.com   # still caller-supplied
```

```yaml
# k8s/values-local.yaml — hostname is composed at deploy time
ingress:
  enabled: true
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
# host omitted: becomes my-app.{INGRESS_BASE_DOMAIN}
```

The same `ingress-prefix` input exists on `k8s-canary.yml` and `k8s-bluegreen.yml`. Canary and
preview hosts still derive from `ingress.host` (`canary.<host>` / `preview.<host>`).

**Migrating a service that's currently deployed with raw `kubectl apply`?** The first `k8s-deploy.yml`
run against it will fail (Helm refuses to adopt resources it doesn't own). Add `adopt-existing: true`
to the `deploy` job for that one run only, then remove it — see "Migrating an existing deployment" in
`charts/app/README.md` for the full runbook and why it must not stay on permanently.

## Example 9: Push to GitHub Container Registry (ghcr.io)

`docker-build-push.yml` auto-logs in to `ghcr.io` with `github.token` when `registry-host` starts
with `ghcr.io` — no `secrets:` block needed. The caller must grant `packages: write`.

```yaml
# .github/workflows/publish-image.yml
name: Publish Image

on:
  push:
    branches: [main]

jobs:
  build:
    permissions:
      contents: read
      packages: write
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@v1.2.0
    with:
      dockerfile: Dockerfile
      image-name: my-app
      registry-host: ghcr.io/my-org
```

For Docker Hub (or any other registry), pass credentials explicitly:

```yaml
jobs:
  build:
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@v1.2.0
    with:
      dockerfile: Dockerfile
      image-name: my-app
      registry-host: docker.io/my-org
    secrets:
      registry-username: ${{ secrets.DOCKERHUB_USERNAME }}
      registry-password: ${{ secrets.DOCKERHUB_TOKEN }}
```

## Example 10: Rust REST API — CI

Format, lint, build and test a Rust service. Enable PostgreSQL for integration tests that need a
database (`DATABASE_URL` is exposed to the test step):

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ "master", "main" ]
  pull_request:
    branches: [ "master", "main" ]

jobs:
  ci:
    uses: adnvilla/gha-toolkit/.github/workflows/rust.yml@master
    with:
      rust-version: 'stable'
      postgres-enabled: true
      postgres-version: '16'
      database-url: 'postgres://postgres:postgres@localhost:5432/postgres'
```

## Example 11: Rust REST API — Full CI/CD (build image + deploy)

The CD half reuses the language-agnostic `docker-build-push.yml` + `k8s-deploy.yml` — same pattern as
the Node example above, just pointing at a Rust Dockerfile.

```yaml
# .github/workflows/cd.yml
name: CD

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
    branches: [main]

jobs:
  build:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    permissions:
      contents: read
      packages: write
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@master
    with:
      # Build the exact commit CI validated, not the default-branch HEAD.
      ref: ${{ github.event.workflow_run.head_sha || github.sha }}
      dockerfile: Dockerfile
      image-name: my-rust-api
      registry-host: ghcr.io/my-org

  deploy:
    needs: build
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-deploy.yml@master
    with:
      ref: ${{ github.event.workflow_run.head_sha || github.sha }}
      release-name: my-rust-api
      namespace: my-rust-api
      kube-context: local
      values-file: k8s/values-local.yaml
      image: ${{ needs.build.outputs.image }}
```

A minimal multi-stage `Dockerfile` for the service (compiles a release binary, then ships it on a
slim runtime image):

```dockerfile
# syntax=docker/dockerfile:1
FROM rust:1.83 AS builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/target/release/my-rust-api /usr/local/bin/my-rust-api
EXPOSE 8080
CMD ["my-rust-api"]
```

## Example 12: API Canary Deploy (deploy → promote)

Canary for HTTP APIs. Put `strategy` defaults in values if you want a smoke host; the workflow
always sets `strategy.mode=canary` and the canary image via `--set`.

```yaml
# k8s/values-api.yaml
fullnameOverride: my-api
ingress:
  enabled: true
  host: my-api.local
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
canary:
  trafficProvider: none   # or traefik for weighted split (requires Traefik CRDs)
  ingress:
    enabled: true         # exposes canary.my-api.local for smoke tests
```

```yaml
# .github/workflows/cd-api.yml
name: CD API

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
    branches: [main]
  workflow_dispatch:
    inputs:
      action:
        description: 'canary phase'
        type: choice
        options: [deploy, promote, abort]
        default: deploy

jobs:
  build:
    if: ${{ github.event_name != 'workflow_dispatch' || inputs.action == 'deploy' }}
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@master
    with:
      ref: ${{ github.event.workflow_run.head_sha || github.sha }}
      dockerfile: Dockerfile
      image-name: my-api
      registry-host: ${{ vars.REGISTRY_HOST }}
      runs-on: self-hosted

  canary:
    needs: [build]
    if: ${{ always() && (needs.build.result == 'success' || github.event_name == 'workflow_dispatch') }}
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-canary.yml@master
    with:
      action: ${{ github.event.inputs.action || 'deploy' }}
      ref: ${{ github.event.workflow_run.head_sha || github.sha }}
      environment: production   # gate promote with Environment required reviewers
      release-name: my-api
      namespace: my-api
      kube-context: ${{ vars.KUBE_CONTEXT }}
      values-file: k8s/values-api.yaml
      image: ${{ needs.build.outputs.image }}
      canary-weight: 10
      runs-on: self-hosted
```

Typical flow: automatic `action=deploy` after CI → smoke on `canary.my-api.local` →
`workflow_dispatch` with `promote` (or `abort`). For Traefik weighted traffic, set
`canary.trafficProvider: traefik` in values (cluster must have Traefik CRDs).

## Example 13: Kafka Worker Blue/Green

Blue/green for consumers. Disable Ingress; use TCP/exec probes if the process has no HTTP port.
Both slots must share the same Kafka `group.id`. Prefer `overlap-seconds: 0`.

```yaml
# k8s/values-worker.yaml
fullnameOverride: my-worker
ingress:
  enabled: false
replicaCount: 2
livenessProbe:
  exec:
    command: ["pgrep", "-f", "my-worker"]
  initialDelaySeconds: 10
  periodSeconds: 30
readinessProbe:
  exec:
    command: ["pgrep", "-f", "my-worker"]
  initialDelaySeconds: 5
  periodSeconds: 10
env:
  - name: KAFKA_GROUP_ID
    value: my-worker
```

```yaml
# .github/workflows/cd-worker.yml
name: CD Worker

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
    branches: [main]
  workflow_dispatch:
    inputs:
      action:
        type: choice
        options: [deploy, promote, abort]
        default: deploy

jobs:
  build:
    if: ${{ github.event_name != 'workflow_dispatch' || inputs.action == 'deploy' }}
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@master
    with:
      ref: ${{ github.event.workflow_run.head_sha || github.sha }}
      dockerfile: Dockerfile
      image-name: my-worker
      registry-host: ${{ vars.REGISTRY_HOST }}
      runs-on: self-hosted

  bluegreen:
    needs: [build]
    if: ${{ always() && (needs.build.result == 'success' || github.event_name == 'workflow_dispatch') }}
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-bluegreen.yml@master
    with:
      action: ${{ github.event.inputs.action || 'deploy' }}
      ref: ${{ github.event.workflow_run.head_sha || github.sha }}
      environment: production
      release-name: my-worker
      namespace: my-worker
      kube-context: ${{ vars.KUBE_CONTEXT }}
      values-file: k8s/values-worker.yaml
      image: ${{ needs.build.outputs.image }}
      active-replicas: 2
      inactive-replicas: 2
      overlap-seconds: 0
      runs-on: self-hosted
```

Flow: `deploy` starts the new image on the inactive slot while the active slot keeps consuming →
check lag/errors → `promote` flips `activeSlot` and scales the old slot to 0 → or `abort` scales
the inactive slot down.

## Example 14: Database Migrations, One-Off Jobs and CronJobs

Three ways to run non-HTTP work with the same chart and values file the app deploys with, so the
Job always inherits the image, `env`, `envFrom`, `resources` and ServiceAccount.

```yaml
# k8s/values-local.yaml
fullnameOverride: my-api
image:
  repository: registry.example.local:5000/my-api
envFrom:
  - secretRef:
      name: my-api-secrets

# 1. Migrations as a Helm pre-upgrade hook: `helm upgrade` blocks on this Job and aborts the
#    release if it fails. Enabled per deploy via the workflow's `migrations` input.
migrations:
  command: ["/app/bin/migrate"]
  args: ["up"]
  backoffLimit: 0

# 2. Default command for the on-demand Job (k8s-job.yml can override command/args per run).
job:
  ttlSecondsAfterFinished: 900

# 3. Scheduled work, deployed together with the app by k8s-deploy.yml.
cronJobs:
  - name: cleanup
    schedule: "0 3 * * *"
    timeZone: America/Mexico_City
    command: ["/app/bin/cleanup"]
    args: ["--older-than=30d"]
    concurrencyPolicy: Forbid
  - name: nightly-report
    schedule: "@daily"
    command: ["/app/bin/report"]
    resources:
      limits:
        memory: 1Gi
```

Run the migrations on every deploy:

```yaml
  deploy:
    needs: build
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-deploy.yml@master
    with:
      release-name: my-api
      namespace: my-api
      kube-context: ${{ vars.KUBE_CONTEXT }}
      values-file: k8s/values-local.yaml
      image: ${{ needs.build.outputs.image }}
      migrations: 'true'   # '' (default) respects the values file, 'false' skips it
      runs-on: self-hosted
```

Or run a Job by hand — a backfill, a one-time fix, a re-run of a failed migration:

```yaml
# .github/workflows/job.yml
name: Run Job

on:
  workflow_dispatch:
    inputs:
      action:
        type: choice
        options: [run, trigger-cronjob, suspend-cronjob, resume-cronjob]
        default: run
      image:
        description: 'Image to run (defaults to the values file)'
        default: ''

jobs:
  job:
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-job.yml@master
    with:
      action: ${{ inputs.action }}
      environment: production
      release-name: my-api
      namespace: my-api
      kube-context: ${{ vars.KUBE_CONTEXT }}
      values-file: k8s/values-local.yaml
      image: ${{ inputs.image }}
      job-name: backfill
      command: |
        /app/bin/backfill
      args: |
        --from=2026-01-01
        --to=2026-02-01
      cronjob-name: cleanup      # used by the trigger/suspend/resume actions
      timeout-seconds: 1800
      runs-on: self-hosted
```

Notes:

- `command`/`args` take one argv entry per line, so an argument may contain spaces or commas.
- The Job name is `<release>-app-<job-name>-<run id>-<attempt>`, so re-runs never collide.
- The workflow fails as soon as the Job reports a failure — it does not wait out the timeout — and
  prints the pod logs plus a `kubectl describe` either way.
- `suspend-cronjob` is the safe switch before a risky deploy; `resume-cronjob` puts it back.

## Example 15: HTTP API Blue/Green with a Preview Host

Blue/green is not only for workers. With `preview: true` the chart renders a Service (and, when
the values file enables it, an Ingress on `preview.<host>`) in front of the **inactive** slot, so
the new version can be smoke-tested on a real URL before it takes production traffic.

```yaml
# k8s/values-api.yaml
fullnameOverride: my-api
strategy:
  mode: blueGreen
ingress:
  enabled: true
  className: traefik
  host: api.example.com
blueGreen:
  preview:
    enabled: true
    ingress:
      enabled: true       # host defaults to preview.api.example.com
```

```yaml
  deploy:
    needs: build
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-bluegreen.yml@master
    with:
      action: deploy
      release-name: my-api
      namespace: my-api
      kube-context: ${{ vars.KUBE_CONTEXT }}
      values-file: k8s/values-api.yaml
      image: ${{ needs.build.outputs.image }}
      preview: true
      verify-url: https://preview.api.example.com/healthz
      auto-abort: true          # scale the bad slot back to 0 instead of leaving it up
      runs-on: self-hosted

  promote:
    needs: deploy
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-bluegreen.yml@master
    with:
      action: promote
      release-name: my-api
      namespace: my-api
      kube-context: ${{ vars.KUBE_CONTEXT }}
      values-file: k8s/values-api.yaml
      image: ${{ needs.build.outputs.image }}
      verify-url: https://api.example.com/healthz
      runs-on: self-hosted
```

`action: status` returns the current `active-slot` / `inactive-slot` / `image` outputs without
touching the release — use it when a scheduled or manual workflow needs to decide whether to
deploy or promote.

## Important Notes

### Permissions

Make sure the calling workflow has the necessary permissions:

```yaml
permissions:
  contents: write   # For semantic-release
  packages: write   # For docker-build-push.yml → ghcr.io
```

### Secrets

Secrets must be passed explicitly when required by the reusable workflow:

```yaml
secrets:
  github-token: ${{ secrets.GITHUB_TOKEN }}   # release.yml
  # docker-build-push.yml — only for non-ghcr registries:
  # registry-username: ${{ secrets.DOCKERHUB_USERNAME }}
  # registry-password: ${{ secrets.DOCKERHUB_TOKEN }}
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
