# CLAUDE.md - Homelab GitOps Repository

## Overview

GitOps-managed K3s homelab with ArgoCD, SSO, TLS, and observability.

- **Domain**: `*.lab.axiomlayer.com`
- **Cluster**: 3-node K3s over Tailscale mesh

## Structure

```
homelab-gitops/
├── apps/                      # Applications
│   ├── argocd/               # GitOps UI + Application CRDs
│   │   └── applications/     # ArgoCD Application manifests (auto-synced via root.yaml)
│   └── telnet-server/        # Demo app
├── infrastructure/           # Core infrastructure
│   ├── cert-manager/         # TLS (Let's Encrypt + Cloudflare)
│   ├── authentik/            # SSO/OIDC
│   ├── longhorn/             # Distributed storage
│   ├── open-webui/           # AI chat interface (connects to Ollama)
│   └── cloudnative-pg/       # PostgreSQL (3-node HA)
├── scripts/                  # Provisioning scripts
│   ├── provision-siberian.sh # GPU workstation (5070Ti + Ollama)
│   ├── provision-k3s-server.sh
│   └── provision-k3s-agent.sh
└── clusters/lab/             # Root kustomization
```

## Stack

| Component | Technology |
|-----------|------------|
| Cluster | K3s |
| GitOps | ArgoCD |
| Config | Kustomize |
| Ingress | Traefik |
| TLS | cert-manager + Let's Encrypt |
| Auth | Authentik (OIDC + forward auth) |
| Storage | Longhorn |
| Database | CloudNativePG |
| Logging | Loki + Promtail |
| Network | Tailscale |
| AI/LLM | Open WebUI + Ollama (external GPU) |

## Patterns

### Component Structure
```
{component}/
├── namespace.yaml
├── deployment.yaml
├── service.yaml
├── certificate.yaml
├── ingress.yaml
├── pdb.yaml              # PodDisruptionBudget for HA
└── kustomization.yaml
```

### Required Labels
All resources use standard Kubernetes labels:
```yaml
labels:
  app.kubernetes.io/name: {name}
  app.kubernetes.io/component: {component}
  app.kubernetes.io/part-of: homelab
  app.kubernetes.io/managed-by: argocd
```

### Deployment Security
All deployments must include:
```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
    livenessProbe: {...}
    readinessProbe: {...}
    resources:
      requests: {...}
      limits: {...}
```

### Ingress with SSO
```yaml
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: authentik-ak-outpost-forward-auth-outpost@kubernetescrd
spec:
  ingressClassName: traefik
```

### ArgoCD Applications (Auto-Synced)

Applications are auto-synced via the App of Apps pattern (`root.yaml`).

```yaml
# apps/argocd/applications/{component}.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    repoURL: https://github.com/jasencdev/axiomlayer.git
    targetRevision: main
    path: {apps|infrastructure}/{component}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Then add to `apps/argocd/applications/kustomization.yaml` - the App of Apps handles the rest.

## Secrets

**Use Sealed Secrets only** - no plaintext secrets in Git.

```bash
# Create sealed secret
kubectl create secret generic {name} -n {namespace} \
  --from-literal=key=value --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-secret.yaml
```

## Commands

```bash
# Validate kustomization
kubectl kustomize apps/telnet-server

# Apply directly (testing)
kubectl apply -k infrastructure/cert-manager

# Check ArgoCD status
kubectl get applications -n argocd

# Check certificates
kubectl get certificates -A
```

## Adding a New Service

1. Create `apps/{service}/` or `infrastructure/{service}/` with:
   - `namespace.yaml` (with labels)
   - `deployment.yaml` (with security context, probes, resources)
   - `service.yaml`
   - `certificate.yaml`
   - `ingress.yaml` (with forward auth)
   - `pdb.yaml` (if replicas > 1)
   - `kustomization.yaml`

2. Create ArgoCD Application in `apps/argocd/applications/{service}.yaml`

3. Add to `apps/argocd/applications/kustomization.yaml`

4. Commit and push - App of Apps auto-syncs everything

## Notes

- ArgoCD excluded from self-management to prevent loops
- Helm charts (Authentik, Longhorn) installed manually
- TLS termination at Traefik; ArgoCD runs HTTP internally (`server.insecure: true`)
- App of Apps (`root.yaml`) auto-syncs all Application manifests
- Ollama runs on external GPU workstation (siberian), connected via Tailscale
- Provisioning scripts in `scripts/` for new nodes and workstations
