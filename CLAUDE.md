# CLAUDE.md - Homelab GitOps Repository

## Overview

GitOps-managed K3s homelab with ArgoCD, SSO, TLS, and observability.

- **Domain**: `*.lab.axiomlayer.com`
- **Cluster**: 3-node K3s over Tailscale mesh
- **Repository**: https://github.com/jasencdev/axiomlayer

## Nodes

| Node | Role | Purpose |
|------|------|---------|
| leopard | control-plane | K3s server |
| bobcat | worker | K3s agent |
| lynx | worker | K3s agent |
| siberian | external | GPU workstation (Ollama) |

## Structure

```
homelab-gitops/
├── apps/                      # Applications
│   ├── argocd/               # GitOps + Application CRDs
│   │   └── applications/     # ArgoCD Application manifests
│   ├── campfire/             # Team chat
│   ├── dashboard/            # Homelab dashboard
│   ├── n8n/                  # Workflow automation
│   ├── outline/              # Documentation wiki
│   ├── plane/                # Project management
│   └── telnet-server/        # Demo app
├── infrastructure/           # Core infrastructure
│   ├── actions-runner/       # GitHub Actions self-hosted runners
│   ├── alertmanager/         # Alert routing
│   ├── authentik/            # SSO/OIDC provider
│   ├── cert-manager/         # TLS certificates
│   ├── cloudnative-pg/       # PostgreSQL operator
│   ├── external-dns/         # DNS management
│   ├── longhorn/             # Distributed storage
│   ├── nfs-proxy/            # NFS access
│   └── open-webui/           # AI chat interface
├── tests/                    # Test suite
│   ├── smoke-test.sh         # Infrastructure health (29 tests)
│   ├── test-auth.sh          # Authentication flows (14 tests)
│   └── validate-manifests.sh # Kustomize validation (17 checks)
├── scripts/                  # Provisioning scripts
└── .github/workflows/        # CI/CD pipeline
    └── ci.yaml               # Main workflow
```

## Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| Cluster | K3s | Lightweight Kubernetes |
| GitOps | ArgoCD | Continuous deployment |
| Config | Kustomize | Manifest management |
| Ingress | Traefik | Load balancing, TLS termination |
| TLS | cert-manager + Let's Encrypt | Automatic certificates |
| Auth | Authentik | OIDC + forward auth SSO |
| Storage | Longhorn | Distributed block storage |
| Database | CloudNativePG | PostgreSQL operator |
| Monitoring | Prometheus + Grafana | Metrics and dashboards |
| Logging | Loki + Promtail | Log aggregation |
| Network | Tailscale | Mesh VPN |
| AI/LLM | Open WebUI + Ollama | Chat interface |

## Applications

| App | URL | Auth Type | Namespace |
|-----|-----|-----------|-----------|
| Dashboard | db.lab.axiomlayer.com | Forward Auth | dashboard |
| Open WebUI | ai.lab.axiomlayer.com | Forward Auth | open-webui |
| Campfire | chat.lab.axiomlayer.com | Forward Auth | campfire |
| n8n | autom8.lab.axiomlayer.com | Forward Auth | n8n |
| Alertmanager | alerts.lab.axiomlayer.com | Forward Auth | monitoring |
| Longhorn | longhorn.lab.axiomlayer.com | Forward Auth | longhorn-system |
| ArgoCD | argocd.lab.axiomlayer.com | Native OIDC | argocd |
| Grafana | grafana.lab.axiomlayer.com | Native OIDC | monitoring |
| Outline | docs.lab.axiomlayer.com | Native OIDC | outline |
| Plane | plane.lab.axiomlayer.com | Native OIDC | plane |
| Authentik | auth.lab.axiomlayer.com | Native | authentik |

## CI/CD Pipeline

### Flow
1. Push to main → GitHub Actions CI
2. Jobs: validate-manifests, lint, security scan
3. ci-passed gate → triggers ArgoCD sync
4. ArgoCD deploys → changes applied
5. integration-tests → smoke + auth tests

### GitHub Actions Secrets
| Secret | Purpose |
|--------|---------|
| ARGOCD_AUTH_TOKEN | ArgoCD API access for sync trigger |

### Running Tests Locally
```bash
./tests/validate-manifests.sh  # Kustomize validation
./tests/smoke-test.sh          # Infrastructure health
./tests/test-auth.sh           # Authentication flows
```

## Patterns

### Component Structure
```
{component}/
├── namespace.yaml
├── deployment.yaml
├── service.yaml
├── certificate.yaml
├── ingress.yaml
├── networkpolicy.yaml    # Default deny + explicit allows
├── pdb.yaml              # PodDisruptionBudget (if replicas > 1)
└── kustomization.yaml
```

### Required Labels
```yaml
labels:
  app.kubernetes.io/name: {name}
  app.kubernetes.io/component: {component}
  app.kubernetes.io/part-of: homelab
  app.kubernetes.io/managed-by: argocd
```

### Deployment Security
```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
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

### Ingress with Forward Auth
```yaml
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: authentik-ak-outpost-forward-auth-outpost@kubernetescrd
spec:
  ingressClassName: traefik
```

### Network Policy Pattern
```yaml
# Default deny
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {app}-default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
# Allow specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {app}-allow-ingress
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: {app}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: traefik
```

## Secrets Management

**Use Sealed Secrets only** - no plaintext secrets in Git.

```bash
# Create sealed secret
kubectl create secret generic {name} -n {namespace} \
  --from-literal=key=value --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-secret.yaml
```

## API Tokens (stored in .env)

| Variable | Purpose |
|----------|---------|
| AUTHENTIK_AUTH_TOKEN | Authentik API access |
| PLANE_API_KEY | Plane API access |
| OUTLINE_API_KEY | Outline API access |

## Key Commands

```bash
# Validate kustomization
kubectl kustomize apps/{service}

# Check ArgoCD status
kubectl get applications -n argocd

# Check certificates
kubectl get certificates -A

# Check pods across namespaces
kubectl get pods -A

# Drain node for maintenance
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Uncordon node
kubectl uncordon <node>

# Restart deployment
kubectl rollout restart deployment/<name> -n <namespace>

# Check Authentik outpost
kubectl logs -n authentik -l goauthentik.io/outpost-name=forward-auth-outpost --tail=100
```

## Adding a New Service

1. Create `apps/{service}/` or `infrastructure/{service}/` with:
   - `namespace.yaml`
   - `deployment.yaml` (with security context, probes, resources)
   - `service.yaml`
   - `certificate.yaml`
   - `ingress.yaml` (with forward auth annotation)
   - `networkpolicy.yaml`
   - `kustomization.yaml`

2. Create ArgoCD Application: `apps/argocd/applications/{service}.yaml`

3. Add to `apps/argocd/applications/kustomization.yaml`

4. If using forward auth, create Authentik provider and add to outpost

5. Commit and push - CI validates, then ArgoCD syncs

## Authentik Configuration

### Forward Auth Apps
Each app needs:
1. Provider (Proxy Provider, forward auth mode)
2. Application linked to provider
3. Provider added to forward-auth-outpost

### Native OIDC Apps
Each app needs:
1. Provider (OAuth2/OpenID Provider)
2. Application linked to provider
3. Client ID/Secret configured in app

### Outpost Configuration
The forward-auth-outpost requires PostgreSQL env vars (Authentik 2025.10+):
- AUTHENTIK_POSTGRESQL__HOST
- AUTHENTIK_POSTGRESQL__USER
- AUTHENTIK_POSTGRESQL__PASSWORD
- AUTHENTIK_POSTGRESQL__NAME

## Documentation

Full documentation in Outline at https://docs.lab.axiomlayer.com:
- Cluster Overview
- CI/CD Pipeline
- Monitoring and Observability
- Runbooks
- Security
- GitHub Actions Runners
- Dashboard
- GitOps Workflow
- Networking and TLS
- Application Catalog
- Authentik SSO Configuration
- Cloudflare DNS and ACME Challenges
- Storage and Databases

## Notes

- Root application (`applications`) uses manual sync - triggered by CI after tests pass
- Child applications use auto-sync with prune and selfHeal
- ArgoCD excluded from self-management to prevent loops
- Helm charts (Authentik, Longhorn, kube-prometheus-stack) installed via ArgoCD Helm source
- TLS termination at Traefik; internal services use HTTP
- Ollama runs on siberian (GPU workstation) via Tailscale
- GitHub Actions runners have read-only cluster RBAC for tests
