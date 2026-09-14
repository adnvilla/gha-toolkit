# app

Generic Helm chart for stateless HTTP applications and Kafka-style workers. Shared by every project
that consumes `gha-toolkit`'s `k8s-deploy.yml`, `k8s-canary.yml`, or `k8s-bluegreen.yml` reusable
workflows — projects supply a small `values-<env>.yaml` instead of hand-writing
`Deployment`/`Service`/`Ingress` manifests.

## Usage

```bash
helm upgrade --install my-app charts/app \
  -n my-namespace --create-namespace \
  -f k8s/values-local.yaml \
  --set image.repository=registry.example.local:5001/my-app \
  --set image.tag=abc1234 \
  --wait --atomic --timeout 180s
```

In practice this is driven by the reusable deploy workflows, which handle the checkout, context
selection and image parsing for you.

## Deployment strategies

| `strategy.mode` | Workflow | Behaviour |
| --- | --- | --- |
| `rolling` (default) | `k8s-deploy.yml` | Single Deployment/Service/Ingress — unchanged from earlier chart versions |
| `canary` | `k8s-canary.yml` | Stable Deployment + canary Deployment/Service; promote/abort via workflow `action` |
| `blueGreen` | `k8s-bluegreen.yml` | `-blue` / `-green` Deployments; Service selects `blueGreen.activeSlot`, optional preview Service/Ingress on the inactive slot |

**Do not flip `strategy.mode` on an existing release without a migration plan** — blue/green and
canary introduce new Deployments and (for blue/green) change the Service selector. Prefer enabling
the mode on a new release name, or delete the old Deployment/Service first (same caveats as
`adopt-existing` in the migration section below).

### Canary (APIs)

- Stable resources keep the rolling names and selectors (`app.fullname`).
- Canary pods use a distinct `app.kubernetes.io/instance` (`<release>-canary`) so they never join
  the stable Service endpoints.
- `canary.trafficProvider: none` (default): main Ingress → stable; optional `canary.ingress` for a
  smoke host (`canary.<ingress.host>` when `canary.ingress.host` is empty).
- `canary.trafficProvider: traefik`: renders a `TraefikService` + `IngressRoute` with weighted
  backends (requires Traefik CRDs). Standard Ingress is skipped. `canary.weight` is the % sent to
  the canary (0–100).
- Pods get `DEPLOYMENT_TRACK=canary` on the canary container.

### Blue/green (Kafka workers and HTTP APIs)

- Two Deployments: `<fullname>-blue` and `<fullname>-green`, labeled with `app.kubernetes.io/slot`.
- The Service selects only `blueGreen.activeSlot`.
- Each pod gets `DEPLOYMENT_SLOT=blue|green` for logs/metrics.
- The toolkit does **not** talk to Kafka. Use the same consumer `group.id` on both slots; prefer
  `overlapSeconds: 0` (scale up new → cut over → scale down old) unless handlers are idempotent
  under overlapping consumers.
- Disable Ingress for workers (`ingress.enabled: false`). Override probes to TCP/exec as needed.
- For HTTP apps `ingress.enabled: true` now renders the Ingress in this mode too; it points at the
  main Service, so `promote` flips traffic with no Ingress change. Chart versions before 0.4.0
  rendered nothing for that combination.
- `blueGreen.preview.enabled: true` adds `<fullname>-preview`, a Service selecting the **inactive**
  slot, plus an optional Ingress on `preview.<ingress.host>` — the URL `k8s-bluegreen.yml`'s
  `verify-url` health gate is meant to poll before you promote.
- `autoscaling` and `podDisruptionBudget` now apply to the **active slot** in this mode (before
  0.4.0 they were skipped entirely). Under an HPA the active slot's Deployment omits `replicas`
  so Helm and the autoscaler don't fight; the inactive slot keeps its explicit count.

### Jobs, migrations and CronJobs

Batch workloads reuse the same values as the app — image, `env`, `envFrom`, `resources`,
`imagePullSecrets`, ServiceAccount and the scheduling blocks — and every field is overridable per
job. Job pods carry a suffixed `app.kubernetes.io/instance` so the app Service can never select
them.

- `job.*` — a single on-demand Job, default off. `k8s-job.yml` turns it on for one run via
  `--set` and appends `job.nameSuffix` (the run id) so repeat runs never collide.
- `migrations.*` — the same Job wired as a Helm `pre-install,pre-upgrade` hook, default off.
  `helm upgrade` waits for it and aborts the release if it fails. `k8s-deploy.yml`'s `migrations`
  input toggles it per deploy.
- `cronJobs` — a list of CronJobs deployed together with the app. `name` and `schedule` are
  required; set `enabled: false` on an entry to render nothing for it. `k8s-job.yml` can trigger,
  suspend and resume them.

Details worth knowing:

- **ServiceAccount on a first install.** Helm runs `pre-install` hooks *before* the chart's ordinary
  resources, so the migration Job cannot use the ServiceAccount from `serviceaccount.yaml` — it does
  not exist yet. With `serviceAccount.create: true` the chart therefore renders a dedicated
  `<fullname>-migrations` SA (same annotations, hook weight `-10`, i.e. before the Job at `-5`).
  Point `migrations.serviceAccountName` at an existing SA to skip it.
- **Reserved labels.** `podLabels` entries named `app.kubernetes.io/name`, `instance`, `component`
  or `managed-by` are dropped: keeping them would let a Job pod match the app Service and take
  production traffic.
- **CronJob names cap at 52 characters**, not 63 — Kubernetes appends an 11-character suffix to
  build each Job name — so `<fullname>-<entry name>` is truncated to 52.
- **Explicit zeros are honoured.** `backoffLimit`, `ttlSecondsAfterFinished`,
  `successfulJobsHistoryLimit` and `failedJobsHistoryLimit` are read with `hasKey`, so a value of
  `0` is not silently replaced by the default (Helm's `default` treats `0` as empty).

## Values

| Key | Default | Description |
| --- | --- | --- |
| `nameOverride` | `""` | Override the chart name used in generated resource names |
| `fullnameOverride` | `""` | Override the fully computed release name |
| `replicaCount` | `1` | Number of pod replicas (rolling / canary stable) |
| `image.repository` | `""` | Image repository (required) |
| `image.tag` | `"latest"` | Image tag |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy |
| `imagePullSecrets` | `[]` | List of `{ name: ... }` secrets for private registries |
| `containerPort` | `8080` | Port the container listens on |
| `env` | `[]` | List of `{ name, value }` env vars |
| `envFrom` | `[]` | List of `envFrom` sources (`configMapRef`/`secretRef`), passed through as-is |
| `resources` | 128Mi/100m requests, 256Mi/500m limits | Pod resource requests/limits |
| `livenessProbe` | HTTP GET `/` on port `8080` | Passed through as-is — **not** derived from `containerPort` |
| `readinessProbe` | HTTP GET `/` on port `8080` | Passed through as-is — **not** derived from `containerPort` |
| `affinity` | `{}` | Passed through as-is to the pod spec |
| `tolerations` | `[]` | Passed through as-is to the pod spec |
| `nodeSelector` | `{}` | Passed through as-is to the pod spec |
| `service.type` | `ClusterIP` | Service type |
| `service.port` | `80` | Service port |
| `service.targetPort` | `8080` | Port forwarded to the container |
| `ingress.enabled` | `false` | Whether to render an Ingress (or Traefik IngressRoute when canary+traefik) |
| `ingress.className` | unset | `ingressClassName`, if set |
| `ingress.annotations` | `{}` | Ingress annotations (e.g. Traefik entrypoints) |
| `ingress.host` | `""` | Ingress host. `k8s-deploy.yml` / `k8s-canary.yml` / `k8s-bluegreen.yml` compose `{ingress-prefix}.{INGRESS_BASE_DOMAIN}` when both are set and this key is omitted from the values file |
| `ingress.path` / `ingress.pathType` | `/` / `Prefix` | Ingress rule path |
| `strategy.mode` | `rolling` | `rolling` \| `canary` \| `blueGreen` |
| `canary.image.repository` / `tag` | `""` | Canary image (workflows set via `--set`) |
| `canary.replicas` | `1` | Canary Deployment replicas |
| `canary.weight` | `10` | % traffic to canary when `trafficProvider=traefik` |
| `canary.trafficProvider` | `none` | `none` \| `traefik` |
| `canary.ingress.enabled` | `false` | Smoke Ingress for canary Service (`none` provider) |
| `canary.ingress.host` | `""` | Defaults to `canary.<ingress.host>` |
| `canary.traefik.entryPoints` | `[web]` | IngressRoute entryPoints when using Traefik |
| `blueGreen.activeSlot` | `blue` | `blue` \| `green` — Service selects this slot |
| `blueGreen.overlapSeconds` | `0` | Documented for promote overlap; workflows drive the cutover |
| `blueGreen.blue` / `green` `.replicas` | `1` / `0` | Per-slot replica counts |
| `blueGreen.blue` / `green` `.image` | empty | Per-slot image; falls back to top-level `image` |
| `blueGreen.preview.enabled` | `false` | Render `<fullname>-preview`, a Service selecting the inactive slot |
| `blueGreen.preview.ingress.enabled` | `false` | Ingress for the preview Service |
| `blueGreen.preview.ingress.host` | `""` | Defaults to `preview.<ingress.host>` |
| `blueGreen.preview.ingress.path` / `pathType` / `className` / `annotations` | `/` / `Prefix` / from `ingress` / `{}` | Preview Ingress rule |
| `serviceAccount.create` | `false` | Create a ServiceAccount and mount it on pods |
| `serviceAccount.name` | `""` | SA name override (defaults to fullname when create is true) |
| `serviceAccount.annotations` | `{}` | SA annotations (e.g. workload identity) |
| `serviceAccount.automountServiceAccountToken` | `true` | Automount the SA token into pods |
| `autoscaling.enabled` | `false` | Render an HPA (rolling/canary stable Deployment, or the active blueGreen slot) |
| `autoscaling.minReplicas` / `maxReplicas` | `1` / `3` | HPA replica bounds |
| `autoscaling.targetCPUUtilizationPercentage` | `80` | CPU target; set `targetMemoryUtilizationPercentage` for memory |
| `podDisruptionBudget.enabled` | `false` | Render a PodDisruptionBudget (rolling/canary pods, or the active blueGreen slot) |
| `podDisruptionBudget.minAvailable` | `1` | Min available pods (preferred over `maxUnavailable` if both set) |
| `networkPolicy.enabled` | `false` | Render a NetworkPolicy selecting the app pods |
| `networkPolicy.allowSameNamespace` | `true` | Allow ingress from any pod in the same namespace to `service.port` |
| `networkPolicy.extraIngress` / `egress` | `[]` / `[]` | Extra ingress rules / egress rules (pass-through) |
| `job.enabled` | `false` | Render the on-demand Job (`k8s-job.yml` sets this per run) |
| `job.name` | `job` | Name segment of the Job and of its container |
| `job.nameSuffix` | `""` | Extra suffix so repeat runs get distinct Job names |
| `job.image.repository` / `tag` / `pullPolicy` | `""` | Falls back to the top-level `image` |
| `job.command` / `job.args` | `[]` / `[]` | Container entrypoint / arguments |
| `job.env` / `job.envFrom` | `[]` / `[]` | Appended to the top-level `env` / `envFrom` |
| `job.resources` | `{}` | Falls back to the top-level `resources` |
| `job.restartPolicy` | `Never` | Pod restart policy |
| `job.backoffLimit` | `0` | Job retries before it is marked failed |
| `job.ttlSecondsAfterFinished` | `300` | Cluster-side cleanup delay after the Job finishes |
| `job.activeDeadlineSeconds` / `parallelism` / `completions` | unset | Passed through when set |
| `job.serviceAccountName` | `""` | Override the SA for this Job; empty inherits `serviceAccount` resolution |
| `job.annotations` / `podAnnotations` / `podLabels` | `{}` | Extra metadata; reserved `app.kubernetes.io/*` selector keys are stripped from `podLabels` |
| `migrations.enabled` | `false` | Render the migration Job as a Helm hook |
| `migrations.*` | same as `job.*` | Same shape as `job` (minus `nameSuffix` semantics) |
| `migrations.hook` | `pre-install,pre-upgrade` | `helm.sh/hook` value |
| `migrations.hookWeight` | `"-5"` | `helm.sh/hook-weight` value |
| `migrations.hookDeletePolicy` | `before-hook-creation` | `helm.sh/hook-delete-policy` value |
| `migrations.serviceAccountName` | `""` | Reuse an existing SA instead of the dedicated hook SA |
| `migrations.serviceAccountHookWeight` | `"-10"` | Hook weight of the dedicated migration SA (must sort before `hookWeight`) |
| `cronJobs` | `[]` | List of CronJobs; each entry takes the `job.*` fields plus `schedule` |
| `cronJobs[].name` / `schedule` | required | Name segment and cron expression |
| `cronJobs[].enabled` | `true` | Set `false` to render nothing for that entry |
| `cronJobs[].suspend` | `false` | Create the CronJob suspended |
| `cronJobs[].concurrencyPolicy` | `Forbid` | `Allow` \| `Forbid` \| `Replace` |
| `cronJobs[].successfulJobsHistoryLimit` / `failedJobsHistoryLimit` | `3` / `1` | Job history kept |
| `cronJobs[].timeZone` / `startingDeadlineSeconds` | unset | Passed through when set |

`probes`, `affinity`, `tolerations`, `resources` and `env`/`envFrom` are intentionally raw
pass-through blocks (`toYaml` straight from `values.yaml`) so project-specific quirks — like
avoiding a control-plane node — don't require chart changes, only a values override.

Optional resources (`serviceAccount`, `autoscaling`, `podDisruptionBudget`, `networkPolicy`) default
to off so existing consumers see no behavior change — enable them in your values file when needed.

**Gotcha:** if you override `containerPort` (or `service.targetPort`), also override
`livenessProbe`/`readinessProbe`'s `port` to match — they default to `8080` independently and are
not derived from `containerPort`, since they're raw pass-through blocks.

## Versioning

`Chart.yaml`'s `version` is bumped manually whenever a template changes in a way consumers should
notice (see `CONTRIBUTING.md`). `k8s-deploy.yml` / `k8s-canary.yml` / `k8s-bluegreen.yml` auto-resolve
the exact `gha-toolkit` commit they were called at (via the `job.workflow_sha` context) and pull this
chart from there, so a project pinned to `k8s-deploy.yml@v1.4.0` always gets the exact chart version
shipped in that tag — no extra input needed. `toolkit-ref` remains available as an optional override,
e.g. to test a chart change from a branch before tagging a release.

## Migrating an existing deployment

If a service is currently deployed with raw `kubectl apply -f k8s/` (no Helm involved) and you point
`k8s-deploy.yml` at it, the first `helm upgrade --install` **fails** — reproduced and confirmed against
a real cluster:

1. **Ownership**: the existing Service/Ingress/Deployment don't carry Helm's ownership annotations
   (`meta.helm.sh/release-name`, `meta.helm.sh/release-namespace`) or the `app.kubernetes.io/managed-by:
   Helm` label, so Helm refuses to touch them (`invalid ownership metadata`).
2. **Immutable selector**: even after annotating ownership by hand, the Deployment's
   `spec.selector` is immutable and almost never matches `charts/app`'s selector
   (`app.kubernetes.io/name`/`app.kubernetes.io/instance`), so the upgrade is rejected outright.

**Do not just `kubectl annotate`/`kubectl label` the Service and stop there** — that alone leaves the
Service in a broken state. Kubernetes' default patch merges the `spec.selector` map instead of
replacing it, so the *old* selector key (e.g. `app: my-app`) survives alongside the chart's new keys.
New pods don't carry that old label, so the Service ends up matching **zero pods** — `helm upgrade`
reports success and `kubectl rollout status` looks healthy, but the Service silently has no endpoints
and all traffic drops. (This exact failure was reproduced while validating this section.)

The resources this chart manages are stateless (no PVCs, no Secrets holding data), so the correct fix
is simpler than adopting them: **delete the old Deployment/Service/Ingress and let Helm create them
fresh.** The only externally visible cost is a new ClusterIP, which doesn't matter for anything that
reaches the Service by DNS name or through the Ingress (i.e. virtually always).

### Option A: `adopt-existing: true` (recommended)

```yaml
deploy:
  uses: adnvilla/gha-toolkit/.github/workflows/k8s-deploy.yml@v1.3.0
  with:
    adopt-existing: true   # one-time only — see warning below
    release-name: my-app
    namespace: my-app
    # ...the rest of your usual inputs
```

Run the workflow once with `adopt-existing: true` (ideally via `workflow_dispatch`, not your normal
automatic CD trigger, so it's a deliberate one-off action). It deletes any pre-existing
`deployment`/`service`/`ingress` named `<release-name>` in `<namespace>` before the Helm upgrade, then
proceeds as normal.

**⚠️ Set it back to `false` (or remove it) immediately after that one deploy.** Left `true`
permanently, every future deploy deletes and recreates the Service/Ingress again — a new ClusterIP,
and a brief gap, on every single release.

### Option B: manual runbook

Equivalent to what `adopt-existing` does, if you'd rather run it by hand:

```bash
kubectl delete deployment <release-name> -n <namespace> --ignore-not-found
kubectl delete service <release-name> -n <namespace> --ignore-not-found
kubectl delete ingress <release-name> -n <namespace> --ignore-not-found

helm upgrade --install <release-name> charts/app -n <namespace> --create-namespace \
  -f k8s/values-<env>.yaml \
  --set image.repository=... --set image.tag=... \
  --wait --atomic
```

A pre-existing plain `Namespace` needs no special handling — `--create-namespace` is already a safe
no-op when the namespace exists and isn't Helm-owned (also confirmed against a real cluster).
