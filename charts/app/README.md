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
notice (see `CONTRIBUTING.md`). `k8s-deploy.yml` pulls this chart from `gha-toolkit` at the same git
ref (`toolkit-ref` input) the caller pinned for the workflow itself, so a project pinned to `@v1.4.0`
always gets the exact chart version shipped in that tag.
