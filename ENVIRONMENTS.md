# Environments (staging / production)

`k8s-deploy.yml` binds every deployment to a [GitHub Environment](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments),
so each run shows up in your repo's **Environments** tab with deployment history, and — if you turn on
protection rules for that environment — can require approval before it runs.

This document covers:

1. [Zero-change rollout](#zero-change-rollout) — what happens to deploys you already have.
2. [Turning on approval for production](#turning-on-approval-for-production) (optional).
3. [Adding a staging environment](#adding-a-staging-environment) — a generic recipe for a new project
   to copy.
4. [Known limitation](#known-limitation--verify-on-first-use) you should verify the first time you
   adopt this.

## Zero-change rollout

`k8s-deploy.yml` has two new inputs:

| Input | Default | What it does |
|---|---|---|
| `environment` | `'production'` | GitHub Environment name for this deployment |
| `environment-url` | `''` | Optional clickable URL shown next to the environment in the Actions UI |

Both are optional with backward-compatible defaults. **If your `with:` block never mentions
`environment`, nothing about your deploy changes** — bump your `k8s-deploy.yml@vX` pin and you're done.
The only visible difference: your deploy now shows up under Settings → Environments → `production` with
a deployment history, instead of being an unlabeled workflow run.

```yaml
deploy:
  uses: adnvilla/gha-toolkit/.github/workflows/k8s-deploy.yml@v1.3.0
  with:
    release-name: my-app
    namespace: my-app
    kube-context: local
    values-file: k8s/values-local.yaml
    image: ${{ needs.build.outputs.image }}
    # environment defaults to 'production' — nothing else changes
```

After your next deploy, check **Settings → Environments** in your repo: a `production` environment
should now exist (GitHub creates it automatically the first time a workflow references it by name, with
no protection rules attached — this doesn't gate anything by default).

## Turning on approval for production

Once the `production` environment exists, you can optionally add protection rules to it:
**Settings → Environments → production → Required reviewers**. Once configured, GitHub blocks the
deploy job until a listed reviewer approves it in the Actions UI — no toolkit changes needed, this is
entirely configured on the consumer side.

**Caveat for private repos**: environment protection rules (and branch protection) require GitHub Pro,
Team, or Enterprise for *private* repositories — they're free for public repos. If you're on GitHub Free
with a private repo, this option won't be available. Two alternatives that don't need a paid plan:

- **Manual promotion**: don't auto-deploy to production on merge; instead expose a `workflow_dispatch`
  input on your CD workflow that a maintainer runs by hand after checking staging. This is what several
  of the examples in `EXAMPLES.md` already do for `kube_context` selection — the same pattern works as
  an approval gate.
- **Treat PR review as the gate**: if production already only deploys after a merge to `main`/`master`
  (the default pattern in this toolkit's examples), and merging already requires a PR review, that
  review *is* your approval step — you don't need a second, separate gate.

## Adding a staging environment

A generic recipe — no navi-admin-specific names, adapt `release-name`/`namespace`/`host` to your project.
Staging here is a **single shared namespace** (not one per PR): every push to any open PR overwrites it.
This is deliberately simple — no per-PR ephemeral environments, no cleanup job on PR close — appropriate
for a small number of contributors where two people are rarely testing different PRs in staging at the
exact same moment. If that stops being true for your project, consider per-PR namespaces instead (out of
scope for this guide).

```yaml
# .github/workflows/cd-staging.yml
name: CD (staging)

on:
  pull_request:
    types: [opened, synchronize, reopened]
    branches: [main]

concurrency:
  group: my-app-staging
  cancel-in-progress: true   # a newer push wins; don't waste a run deploying a stale PR

jobs:
  build:
    uses: adnvilla/gha-toolkit/.github/workflows/docker-build-push.yml@v1.3.0
    with:
      # pull_request's own GITHUB_SHA is a synthetic merge commit, not the PR's real head —
      # pass it explicitly so the image is built from the code actually under review.
      ref: ${{ github.event.pull_request.head.sha }}
      dockerfile: apps/web/Dockerfile
      image-name: my-app-web
      registry-host: registry.example.local:5001
      runs-on: self-hosted

  deploy:
    needs: build
    uses: adnvilla/gha-toolkit/.github/workflows/k8s-deploy.yml@v1.3.0
    with:
      ref: ${{ github.event.pull_request.head.sha }}
      environment: staging
      environment-url: https://staging.my-app.local
      release-name: my-app-web
      namespace: my-app-staging
      kube-context: local
      values-file: k8s/values-staging.yaml
      image: ${{ needs.build.outputs.image }}
```

`k8s/values-staging.yaml` is a second values file next to your existing `values-local.yaml` — same
shape, different `ingress.host` (e.g. `staging.my-app.local` instead of `my-app.local`). See
`charts/app/README.md` for the full values reference.

**Production is unaffected** — it keeps whatever trigger it already has (typically `workflow_run` after
CI succeeds on `main`, per `EXAMPLES.md`'s Example 8). Nothing in this recipe changes when or how
production deploys.

**Build once, deploy many**: notice `docker-build-push.yml` isn't touched by this guide at all —
`environment` only exists on `k8s-deploy.yml`. The same image built once should be the one promoted from
staging to production; don't rebuild per environment, or you risk staging validating a slightly
different artifact than what actually ships.

## Known limitation — verify on first use

When `environment:` is set inside a reusable workflow's own job (as `k8s-deploy.yml` does), GitHub's
documentation on reusable workflow secrets implies the environment is resolved against the **calling**
repository — each consumer controls their own Environments independently, and gha-toolkit doesn't need
to know about them. This is what makes the feature usable across many different consumer repos.

This behavior could not be verified end-to-end against a second real repository while building this
feature (only same-repo `workflow_dispatch` testing was possible from gha-toolkit itself). The first
time you adopt `environment` in your project, check your repo's **Settings → Environments** after a
deploy to confirm it shows up as expected. If it doesn't behave as documented here, please open an issue
against `gha-toolkit` — and in the meantime, the manual `workflow_dispatch` promotion pattern above works
regardless, since it doesn't depend on this mechanism.
