# app

Generic Helm chart for stateless HTTP applications. Shared by every project that consumes
`gha-toolkit`'s `k8s-deploy.yml` reusable workflow — projects supply a small `values-<env>.yaml`
instead of hand-writing `Deployment`/`Service`/`Ingress` manifests.

## Usage

```bash
helm upgrade --install my-app charts/app \
  -n my-namespace --create-namespace \
  -f k8s/values-local.yaml \
  --set image.repository=registry.example.local:5001/my-app \
  --set image.tag=abc1234 \
  --wait --atomic --timeout 180s
```

In practice this is driven by the `k8s-deploy.yml` reusable workflow, which handles the checkout,
context selection and image parsing for you.

## Values

| Key | Default | Description |
|---|---|---|
| `nameOverride` | `""` | Override the chart name used in generated resource names |
| `fullnameOverride` | `""` | Override the fully computed release name |
| `replicaCount` | `1` | Number of pod replicas |
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
| `ingress.enabled` | `false` | Whether to render an Ingress |
| `ingress.className` | unset | `ingressClassName`, if set |
| `ingress.annotations` | `{}` | Ingress annotations (e.g. Traefik entrypoints) |
| `ingress.host` | `""` | Ingress host |
| `ingress.path` / `ingress.pathType` | `/` / `Prefix` | Ingress rule path |

`probes`, `affinity`, `tolerations`, `resources` and `env`/`envFrom` are intentionally raw
pass-through blocks (`toYaml` straight from `values.yaml`) so project-specific quirks — like
avoiding a control-plane node — don't require chart changes, only a values override.

**Gotcha:** if you override `containerPort` (or `service.targetPort`), also override
`livenessProbe`/`readinessProbe`'s `port` to match — they default to `8080` independently and are
not derived from `containerPort`, since they're raw pass-through blocks.

## Versioning

`Chart.yaml`'s `version` is bumped manually whenever a template changes in a way consumers should
notice (see `CONTRIBUTING.md`). `k8s-deploy.yml` auto-resolves the exact `gha-toolkit` commit it was
called at (via the `job.workflow_sha` context) and pulls this chart from there, so a project pinned
to `k8s-deploy.yml@v1.4.0` always gets the exact chart version shipped in that tag — no extra input
needed. `toolkit-ref` remains available as an optional override, e.g. to test a chart change from a
branch before tagging a release.

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
