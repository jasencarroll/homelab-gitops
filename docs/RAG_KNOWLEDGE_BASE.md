# Homelab GitOps Complete Knowledge Base

This document is a comprehensive, RAG-optimized knowledge base for the AxiomLayer homelab Kubernetes cluster. It covers every aspect of the infrastructure from architecture to troubleshooting.

---

## TABLE OF CONTENTS

1. [Executive Summary](#executive-summary)
2. [Cluster Architecture](#cluster-architecture)
3. [Node Inventory and Hardware](#node-inventory-and-hardware)
4. [Network Architecture](#network-architecture)
5. [GitOps and ArgoCD](#gitops-and-argocd)
6. [Authentication and SSO](#authentication-and-sso)
7. [TLS and Certificate Management](#tls-and-certificate-management)
8. [DNS Management](#dns-management)
9. [Storage Architecture](#storage-architecture)
10. [Database Management](#database-management)
11. [Monitoring and Observability](#monitoring-and-observability)
12. [Backup and Disaster Recovery](#backup-and-disaster-recovery)
13. [CI/CD Pipeline](#cicd-pipeline)
14. [Secrets Management](#secrets-management)
15. [Application Catalog](#application-catalog)
16. [Security Patterns](#security-patterns)
17. [Provisioning Scripts](#provisioning-scripts)
18. [Testing Framework](#testing-framework)
19. [Operational Procedures](#operational-procedures)
20. [Troubleshooting Reference](#troubleshooting-reference)
21. [Configuration Reference](#configuration-reference)
22. [API and Integration Reference](#api-and-integration-reference)

---

## EXECUTIVE SUMMARY

### What is this repository?

The `homelab-gitops` repository (https://github.com/jasencdev/axiomlayer) is a GitOps-managed Kubernetes homelab running on K3s. It uses ArgoCD for continuous deployment with the "app of apps" pattern.

### Key Facts

- **Domain**: `*.lab.axiomlayer.com`
- **Kubernetes Distribution**: K3s v1.33.6+k3s1
- **GitOps Tool**: ArgoCD 8.0.14
- **Configuration Management**: Kustomize (no Helm templating in apps, but Helm sources for third-party charts)
- **SSO Provider**: Authentik 2025.10.2
- **Storage Provider**: Longhorn distributed block storage
- **Database Operator**: CloudNativePG for PostgreSQL
- **Network Mesh**: Tailscale (WireGuard-based)
- **Ingress Controller**: Traefik (bundled with K3s)
- **Certificate Authority**: Let's Encrypt via cert-manager
- **DNS Provider**: Cloudflare (managed by external-dns)

### Repository Structure Overview

```
homelab-gitops/
├── apps/                      # User-facing applications
│   ├── argocd/               # ArgoCD configuration + Application manifests
│   ├── campfire/             # Team chat (37signals)
│   ├── dashboard/            # Custom homelab dashboard
│   ├── n8n/                  # Workflow automation
│   ├── outline/              # Documentation wiki
│   ├── plane/                # Project management
│   └── telnet-server/        # Demo application
├── infrastructure/           # Core infrastructure components
│   ├── actions-runner/       # GitHub Actions self-hosted runners
│   ├── alertmanager/         # Alert routing and management
│   ├── authentik/            # Identity provider (SSO)
│   ├── backups/              # Automated backup CronJobs
│   ├── cert-manager/         # TLS certificate automation
│   ├── cloudnative-pg/       # PostgreSQL operator
│   ├── external-dns/         # DNS record automation
│   ├── longhorn/             # Distributed storage
│   ├── monitoring/           # Grafana extras (OIDC config)
│   ├── nfs-proxy/            # NFS proxy for backup target
│   ├── open-webui/           # AI chat interface
│   └── sealed-secrets/       # Secret encryption controller
├── scripts/                  # Provisioning and utility scripts
├── tests/                    # Automated test suite
├── docs/                     # Documentation
├── templates/                # Application templates
└── clusters/lab/             # Cluster-specific kustomization
```

---

## CLUSTER ARCHITECTURE

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                              Internet                                │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Cloudflare DNS                               │
│              *.lab.axiomlayer.com → Tailscale IPs                   │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Tailscale Mesh                               │
│   neko (100.67.134.110) ←→ neko2 (100.106.35.14) ←→ panther/bobcat │
│                              ↕                                       │
│                    siberian (GPU workstation)                        │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        K3s Cluster                                   │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                    Traefik Ingress                              │ │
│  │         TLS termination + routing + forward auth                │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                              │                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                 Authentik Forward Auth                          │ │
│  │              SSO verification middleware                        │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                              │                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                    Application Pods                             │ │
│  │    Dashboard, Campfire, Outline, Plane, n8n, Open WebUI...     │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                              │                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                      Longhorn Storage                           │ │
│  │         Distributed across neko, neko2, panther, bobcat         │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         UniFi NAS                                    │
│                       192.168.1.234                                  │
│                    Backup storage via NFS                            │
└─────────────────────────────────────────────────────────────────────┘
```

### Kubernetes Components

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| Distribution | K3s | v1.33.6+k3s1 | Lightweight Kubernetes |
| Container Runtime | containerd | 2.1.5 | Container execution |
| CNI | Flannel | Built-in | Pod networking (via Tailscale interface) |
| Ingress | Traefik | Built-in | Load balancing, TLS termination |
| Service LB | ServiceLB (Klipper) | Built-in | LoadBalancer service type |
| Local Storage | Local Path Provisioner | Built-in | Legacy storage |

### Control Plane Configuration

The cluster uses a **2-node embedded etcd** configuration:
- First server initialized with `--cluster-init`
- Second server joined with `--server https://<first-server>:6443`
- All inter-node communication uses Tailscale IPs for encryption

### Flannel Configuration

Flannel is configured to use the Tailscale interface:
```bash
--flannel-iface=tailscale0
```

This ensures all pod-to-pod traffic is automatically encrypted via WireGuard.

---

## NODE INVENTORY AND HARDWARE

### Control Plane Nodes

#### neko (Primary Control Plane)

| Property | Value |
|----------|-------|
| Role | control-plane, etcd, master |
| Hardware | Mini PC |
| CPU | AMD Ryzen |
| RAM | 32GB |
| Storage | 462GB NVMe |
| Tailscale IP | 100.67.134.110 |
| Local IP | 192.168.1.167 |
| Special | NFS proxy runs here (nodeSelector) |

#### neko2 (Secondary Control Plane)

| Property | Value |
|----------|-------|
| Role | control-plane, etcd, master |
| Hardware | Mini PC |
| CPU | AMD Ryzen |
| RAM | 32GB |
| Storage | 462GB NVMe |
| Tailscale IP | 100.106.35.14 |
| Local IP | 192.168.1.103 |

### Worker Nodes

#### panther (Primary Worker)

| Property | Value |
|----------|-------|
| Role | worker |
| Hardware | Unknown |
| Tailscale IP | 100.79.124.94 |
| GPU | RTX 3050 Ti (used for embeddings) |
| Special | Ollama for RAG embeddings (granite4:3b) |

#### bobcat (Raspberry Pi Worker)

| Property | Value |
|----------|-------|
| Role | worker |
| Hardware | Raspberry Pi 5 |
| CPU | ARM64 |
| RAM | 8GB |
| Storage | 500GB SSD |
| Tailscale IP | 100.121.67.60 |
| Local IP | 192.168.1.49 |

### External Resources

#### siberian (GPU Workstation)

| Property | Value |
|----------|-------|
| Role | External GPU compute |
| GPU | RTX 5070 Ti |
| Service | Ollama for LLM generation |
| Tailscale IP | 100.115.3.88 |
| Port | 11434 |
| Use Case | Open WebUI LLM inference |

#### UniFi NAS

| Property | Value |
|----------|-------|
| Role | Backup storage |
| IP | 192.168.1.234 |
| Protocol | NFS |
| NFS Path | /volume/e8e70d24-82e0-45f1-8ef6-f8ca399ad2d6/.srv/.unifi-drive/Shared_Drive_Example/.data |

---

## NETWORK ARCHITECTURE

### Network Layers (Top to Bottom)

1. **Internet** → User requests
2. **Cloudflare DNS** → `*.lab.axiomlayer.com` resolves to Tailscale IPs
3. **Tailscale Mesh** → WireGuard-encrypted connectivity
4. **Traefik Ingress** → TLS termination, routing
5. **Authentik Forward Auth** → SSO verification
6. **Application Pods** → Receive authenticated requests

### Tailscale Configuration

- All nodes connected via Tailscale mesh VPN
- Uses `100.0.0.0/8` CGNAT range
- MagicDNS enabled for `.ts.net` resolution
- Exit nodes not used (direct mesh connectivity)

### DNS Architecture

| Record Type | Name | Target | Manager |
|-------------|------|--------|---------|
| A | *.lab.axiomlayer.com | 100.67.134.110 | external-dns |
| A | *.lab.axiomlayer.com | 100.106.35.14 | external-dns |
| A | *.lab.axiomlayer.com | 100.79.124.94 | external-dns |
| A | *.lab.axiomlayer.com | 100.121.67.60 | external-dns |
| TXT | _acme-challenge.*.lab.axiomlayer.com | (dynamic) | cert-manager |

### External-DNS Configuration

Location: `infrastructure/external-dns/deployment.yaml`

```yaml
args:
  - --source=ingress
  - --domain-filter=lab.axiomlayer.com
  - --provider=cloudflare
  - --policy=upsert-only
  - --registry=txt
  - --txt-owner-id=homelab-k3s
  - --interval=1m
```

The `upsert-only` policy prevents external-dns from deleting records it didn't create.

### Ingress Patterns

All ingresses use Traefik with the following patterns:

**Standard Ingress with Forward Auth**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: myapp
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.middlewares: authentik-ak-outpost-forward-auth-outpost@kubernetescrd
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - myapp.lab.axiomlayer.com
      secretName: myapp-tls
  rules:
    - host: myapp.lab.axiomlayer.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 8080
```

**Ingress without Forward Auth (Native OIDC apps)**:
```yaml
annotations:
  traefik.ingress.kubernetes.io/router.entrypoints: websecure
  traefik.ingress.kubernetes.io/router.tls: "true"
  # No middlewares annotation - app handles auth natively
```

### Network Policies

Every namespace has default-deny policies with explicit allow rules.

**Pattern - Default Deny**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: myapp-default-deny
  namespace: myapp
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

**Pattern - Allow Traefik Ingress**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: myapp-allow-ingress
  namespace: myapp
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: myapp
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              app.kubernetes.io/name: traefik
      ports:
        - protocol: TCP
          port: 8080
```

**Pattern - Allow DNS Egress**:
```yaml
egress:
  - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
    ports:
      - protocol: UDP
        port: 53
      - protocol: TCP
        port: 53
```

**Pattern - Allow Database Egress (CNPG)**:
```yaml
egress:
  - to:
      - podSelector:
          matchLabels:
            cnpg.io/cluster: myapp-db
    ports:
      - protocol: TCP
        port: 5432
```

---

## GITOPS AND ARGOCD

### App of Apps Pattern

The repository uses the ArgoCD "app of apps" pattern:

1. **Root Application** (`apps/argocd/applications/root.yaml`)
   - Points to `apps/argocd/applications/`
   - Creates all child Application resources
   - Manual sync only (triggered by CI after tests pass)

2. **Child Applications** (`apps/argocd/applications/*.yaml`)
   - Each points to its application directory
   - Auto-sync enabled with prune and selfHeal

### Sync Flow

```
1. Developer pushes to main branch
2. GitHub Actions CI runs:
   - validate-manifests.sh
   - kube-linter
   - Trivy security scan
3. ci-passed job triggers ArgoCD sync via API
4. ArgoCD syncs root application
5. Child applications sync automatically
6. Integration tests run (smoke-test.sh, test-auth.sh)
```

### ArgoCD Application Structure

Location: `apps/argocd/applications/kustomization.yaml`

Managed applications:
- `actions-runner-controller.yaml` - GitHub Actions runner controller (Helm)
- `actions-runner-infra.yaml` - Runner deployment and RBAC
- `alertmanager.yaml` - Custom Alertmanager deployment
- `argocd-helm.yaml` - ArgoCD itself (Helm, manual sync)
- `authentik-helm.yaml` - Authentik (Helm)
- `authentik.yaml` - Authentik extras (CNPG, outpost, blueprints)
- `backups.yaml` - Backup CronJob
- `campfire.yaml` - Team chat
- `cert-manager-helm.yaml` - cert-manager (Helm)
- `cert-manager.yaml` - ClusterIssuer and secrets
- `cloudnative-pg.yaml` - CNPG operator (Helm)
- `dashboard.yaml` - Custom dashboard
- `external-dns.yaml` - DNS automation
- `kube-prometheus-stack.yaml` - Prometheus + Grafana (Helm)
- `monitoring-extras.yaml` - Grafana OIDC config
- `longhorn-helm.yaml` - Longhorn (Helm)
- `longhorn.yaml` - Longhorn extras (ingress, recurring jobs)
- `loki.yaml` - Log aggregation (Helm)
- `n8n.yaml` - Workflow automation
- `nfs-proxy.yaml` - NFS proxy for backups
- `open-webui.yaml` - AI chat interface
- `outline.yaml` - Documentation wiki
- `plane.yaml` - Project management (Helm)
- `plane-extras.yaml` - Plane TLS certificate
- `sealed-secrets.yaml` - Secret controller
- `telnet-server.yaml` - Demo application

### ArgoCD Configuration

**ConfigMaps** (`apps/argocd/configmaps.yaml`):

```yaml
# argocd-cm - Main config
data:
  url: https://argocd.lab.axiomlayer.com
  oidc.config: |
    name: Authentik
    issuer: https://auth.lab.axiomlayer.com/application/o/argocd/
    clientID: argocd
    clientSecret: $oidc.authentik.clientSecret
    requestedScopes: ["openid", "profile", "email"]
    insecureSkipVerify: true

# argocd-cmd-params-cm - Server params
data:
  server.insecure: "true"  # TLS at Traefik

# argocd-rbac-cm - RBAC
data:
  policy.csv: |
    g, jasen@axiomlayer.com, role:admin
  scopes: "[email]"
```

### Sync Policies

**Manual Sync (argocd-helm, root)**:
```yaml
syncPolicy:
  syncOptions:
    - ApplyOutOfSyncOnly=true
```

**Auto Sync (most apps)**:
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

### Sync Waves

Applications are ordered by sync waves:
- Wave 0: ArgoCD, Sealed Secrets, cert-manager
- Wave 4: Authentik
- Wave 5: Prometheus/Grafana
- Wave 8: Plane (depends on storage)

---

## AUTHENTICATION AND SSO

### Authentik Overview

Authentik is the identity provider (IdP) for all homelab applications.

- **URL**: https://auth.lab.axiomlayer.com
- **Version**: 2025.10.2
- **Deployment**: Helm chart + custom Kustomize overlays

### Authentication Types

#### 1. Forward Auth (Proxy Provider)

For applications without native OIDC support. Traefik forwards auth requests to Authentik outpost.

**Protected Apps**:
- Dashboard (db.lab.axiomlayer.com)
- n8n (autom8.lab.axiomlayer.com)
- Alertmanager (alerts.lab.axiomlayer.com)
- Longhorn (longhorn.lab.axiomlayer.com)
- Open WebUI (ai.lab.axiomlayer.com)
- Campfire (chat.lab.axiomlayer.com)
- Telnet Server (telnet.lab.axiomlayer.com)

**Flow**:
```
User → Traefik → Authentik Outpost (check session)
                        ↓
         Has session? → YES → Forward to app with X-Authentik-* headers
                        ↓
                       NO → Redirect to auth.lab.axiomlayer.com/login
```

**Headers passed to applications**:
```
X-Authentik-Username: jasen
X-Authentik-Email: jasen@axiomlayer.com
X-Authentik-Groups: Homelab Admins,Homelab Users
X-Authentik-Uid: abc123def456
X-Authentik-Name: Jasen
X-Authentik-Jwt: <JWT token>
```

#### 2. Native OIDC (OAuth2 Provider)

For applications with built-in OIDC support.

**Apps with Native OIDC**:
- ArgoCD (argocd.lab.axiomlayer.com)
- Grafana (grafana.lab.axiomlayer.com)
- Outline (docs.lab.axiomlayer.com)
- Plane (plane.lab.axiomlayer.com)

**Flow**:
```
User → App → Redirect to Authentik /application/o/authorize/
          → User authenticates
          → Redirect back to App callback URL
          → App exchanges code for tokens
```

### Authentik Components

#### 1. Helm Chart (`apps/argocd/applications/authentik-helm.yaml`)

```yaml
source:
  repoURL: https://charts.goauthentik.io
  chart: authentik
  targetRevision: 2025.10.2
  helm:
    valuesObject:
      global:
        env:
          - name: AUTHENTIK_SECRET_KEY
            valueFrom:
              secretKeyRef:
                name: authentik-helm-secrets
                key: secret_key
          - name: AUTHENTIK_POSTGRESQL__PASSWORD
            valueFrom:
              secretKeyRef:
                name: authentik-db-app
                key: password
      authentik:
        postgresql:
          host: authentik-db-rw.authentik.svc
          name: authentik
          user: authentik
      postgresql:
        enabled: false  # Using CNPG
      redis:
        enabled: true
      server:
        ingress:
          enabled: true
          hosts:
            - auth.lab.axiomlayer.com
        volumes:
          - name: blueprints
            configMap:
              name: authentik-blueprints
        volumeMounts:
          - name: blueprints
            mountPath: /blueprints/custom
```

#### 2. Postgres Cluster (`infrastructure/authentik/postgres-cluster.yaml`)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: authentik-db
  namespace: authentik
spec:
  instances: 1
  storage:
    size: 5Gi
    storageClass: longhorn
  bootstrap:
    initdb:
      database: authentik
      owner: authentik
  monitoring:
    enablePodMonitor: true
```

#### 3. Forward Auth Outpost (`infrastructure/authentik/outpost.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ak-outpost-forward-auth-outpost
  namespace: authentik
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: proxy
          image: ghcr.io/goauthentik/proxy:2025.10.2
          ports:
            - containerPort: 9000  # HTTP
            - containerPort: 9443  # HTTPS
          env:
            - name: AUTHENTIK_HOST
              value: "https://auth.lab.axiomlayer.com"
            - name: AUTHENTIK_TOKEN
              valueFrom:
                secretKeyRef:
                  name: authentik-outpost-token
                  key: token
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: ak-outpost-forward-auth-outpost
  namespace: authentik
spec:
  forwardAuth:
    address: http://ak-outpost-forward-auth-outpost.authentik.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik
    trustForwardHeader: true
    authResponseHeaders:
      - X-authentik-username
      - X-authentik-groups
      - X-authentik-email
      - X-authentik-name
      - X-authentik-uid
      - X-authentik-jwt
```

#### 4. Blueprints (`infrastructure/authentik/blueprints/homelab-apps.yaml`)

Authentik blueprints declaratively configure:
- User groups (Homelab Admins, Homelab Users)
- Users (jasen)
- Proxy Providers (one per forward-auth app)
- OAuth2 Providers (for native OIDC apps)
- Kubernetes Service Connection
- Outpost configuration
- Applications
- Access Policies

Key blueprint entries:
```yaml
# Proxy Provider (Forward Auth)
- model: authentik_providers_proxy.proxyprovider
  id: provider-dashboard
  identifiers:
    name: Dashboard Proxy Provider
  attrs:
    mode: forward_single
    external_host: https://db.lab.axiomlayer.com

# OAuth2 Provider (Native OIDC)
- model: authentik_providers_oauth2.oauth2provider
  id: provider-argocd
  identifiers:
    name: ArgoCD OIDC Provider
  attrs:
    client_type: confidential
    client_id: argocd
    client_secret: "..."
    redirect_uris:
      - matching_mode: strict
        url: https://argocd.lab.axiomlayer.com/auth/callback

# Outpost
- model: authentik_outposts.outpost
  id: outpost-forward-auth
  identifiers:
    name: forward-auth-outpost
  attrs:
    type: proxy
    providers:
      - !KeyOf provider-dashboard
      - !KeyOf provider-n8n
      # ... all forward-auth providers
```

### OIDC Configuration by Application

#### ArgoCD OIDC

Location: `apps/argocd/configmaps.yaml`

```yaml
oidc.config: |
  name: Authentik
  issuer: https://auth.lab.axiomlayer.com/application/o/argocd/
  clientID: argocd
  clientSecret: $oidc.authentik.clientSecret
  requestedScopes: ["openid", "profile", "email"]
  insecureSkipVerify: true  # For internal Traefik -> Authentik
```

Redirect URI: `https://argocd.lab.axiomlayer.com/auth/callback`

#### Grafana OIDC

Location: `apps/argocd/applications/kube-prometheus-stack.yaml` (Helm values)

```yaml
grafana.ini:
  auth.generic_oauth:
    enabled: true
    name: Authentik
    allow_sign_up: true
    use_pkce: true
    scopes: openid email profile groups
    auth_url: https://auth.lab.axiomlayer.com/application/o/authorize/
    token_url: https://auth.lab.axiomlayer.com/application/o/token/
    api_url: https://auth.lab.axiomlayer.com/application/o/userinfo
    client_id: $__env{client-id}
    client_secret: $__env{client-secret}
    role_attribute_path: contains(groups[*], 'Homelab Admins') && 'Admin' || 'Viewer'
```

#### Outline OIDC

Location: `apps/outline/deployment.yaml`

```yaml
env:
  - name: OIDC_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: outline-secrets
        key: oidc-client-id
  - name: OIDC_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: outline-secrets
        key: oidc-client-secret
  - name: OIDC_AUTH_URI
    value: "https://auth.lab.axiomlayer.com/application/o/authorize/"
  - name: OIDC_TOKEN_URI
    value: "http://authentik-helm-server.authentik.svc.cluster.local/application/o/token/"
  - name: OIDC_USERINFO_URI
    value: "http://authentik-helm-server.authentik.svc.cluster.local/application/o/userinfo/"
  - name: OIDC_DISPLAY_NAME
    value: "Authentik"
```

Note: Token/userinfo URIs use internal cluster DNS to avoid TLS issues.

---

## TLS AND CERTIFICATE MANAGEMENT

### cert-manager Configuration

**ClusterIssuer** (`infrastructure/cert-manager/cluster-issuer.yaml`):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: jasen.c7@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
        selector:
          dnsZones:
            - "axiomlayer.com"
```

### DNS-01 Challenge Flow

```
1. Certificate resource created
2. cert-manager creates CertificateRequest
3. ACME Order created
4. Challenge created (DNS-01)
5. cert-manager creates TXT record via Cloudflare API
6. Let's Encrypt validates TXT record
7. Certificate issued
8. Secret created with TLS key/cert
9. Traefik loads new certificate
```

### Certificate Pattern

Every application with an ingress has a Certificate resource:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-tls
  namespace: myapp
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - myapp.lab.axiomlayer.com
```

### Current Certificates

| Namespace | Certificate | DNS Name |
|-----------|-------------|----------|
| argocd | argocd-tls | argocd.lab.axiomlayer.com |
| authentik | authentik-tls | auth.lab.axiomlayer.com |
| campfire | campfire-tls | chat.lab.axiomlayer.com |
| dashboard | dashboard-tls | db.lab.axiomlayer.com |
| longhorn-system | longhorn-tls | longhorn.lab.axiomlayer.com |
| monitoring | grafana-tls | grafana.lab.axiomlayer.com |
| monitoring | alertmanager-tls | alerts.lab.axiomlayer.com |
| n8n | n8n-tls | autom8.lab.axiomlayer.com |
| open-webui | open-webui-tls | ai.lab.axiomlayer.com |
| outline | outline-tls | docs.lab.axiomlayer.com |
| plane | plane-tls | plane.lab.axiomlayer.com |
| telnet-server | telnet-server-tls | telnet.lab.axiomlayer.com |

---

## DNS MANAGEMENT

### external-dns Overview

external-dns automatically creates DNS records in Cloudflare based on Ingress resources.

Location: `infrastructure/external-dns/`

### Configuration

```yaml
args:
  - --source=ingress           # Watch Ingress resources
  - --domain-filter=lab.axiomlayer.com  # Only manage this subdomain
  - --provider=cloudflare
  - --policy=upsert-only       # Never delete records
  - --registry=txt             # Use TXT records to track ownership
  - --txt-owner-id=homelab-k3s # Ownership identifier
  - --interval=1m              # Sync interval
```

### How Records Are Created

When an Ingress is created:
1. external-dns detects the new Ingress
2. Extracts the hostname from `.spec.rules[].host`
3. Creates A records pointing to node Tailscale IPs
4. Creates TXT record for ownership tracking

### DNS Records Example

For `db.lab.axiomlayer.com`:
```
db.lab.axiomlayer.com.         A     100.67.134.110
db.lab.axiomlayer.com.         A     100.106.35.14
db.lab.axiomlayer.com.         A     100.79.124.94
db.lab.axiomlayer.com.         A     100.121.67.60
heritage=external-dns,external-dns/owner=homelab-k3s  TXT
```

---

## STORAGE ARCHITECTURE

### Longhorn Overview

Longhorn provides distributed block storage across all nodes.

- **UI**: https://longhorn.lab.axiomlayer.com
- **Default Replicas**: 3
- **StorageClass**: `longhorn` (default)

### Storage Classes

| Class | Provider | Replicas | Use Case |
|-------|----------|----------|----------|
| longhorn | Longhorn | 3 | Production workloads |
| local-path | Rancher Local Path | 0 | Legacy (Authentik Redis) |

### Volume Distribution

Longhorn distributes volume replicas across:
- neko (462GB NVMe)
- neko2 (462GB NVMe)
- panther
- bobcat (500GB SSD)

### Recurring Jobs

Location: `infrastructure/backups/longhorn-recurring-jobs.yaml`

```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: daily-snapshot
  namespace: longhorn-system
spec:
  task: snapshot
  cron: "0 2 * * *"  # 2 AM daily
  retain: 7          # Keep 7 snapshots
  groups:
    - default
---
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: weekly-snapshot
  namespace: longhorn-system
spec:
  task: snapshot
  cron: "0 3 * * 0"  # 3 AM Sunday
  retain: 4          # Keep 4 snapshots
  groups:
    - default
```

### Current Volumes

| Namespace | PVC | Size | Purpose |
|-----------|-----|------|---------|
| campfire | campfire-storage | 5Gi | Campfire data |
| n8n | n8n-data | 5Gi | n8n workflows |
| n8n | n8n-db-1 | 5Gi | n8n PostgreSQL |
| open-webui | open-webui-data | 5Gi | Open WebUI data |
| open-webui | open-webui-db-1 | 10Gi | Open WebUI PostgreSQL |
| outline | outline-data | 5Gi | Outline attachments |
| outline | outline-db-1 | 5Gi | Outline PostgreSQL |
| plane | pvc-plane-* | various | Plane components |
| monitoring | storage-loki-0 | 10Gi | Loki logs |
| authentik | authentik-db-1 | 5Gi | Authentik PostgreSQL |

### NFS Proxy Architecture

The UniFi NAS only allows NFS connections from a single IP. The NFS proxy solves this:

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Any Pod        │────▶│   NFS Proxy      │────▶│   UniFi NAS      │
│   (any node)     │     │   (on neko)      │     │  192.168.1.234   │
└──────────────────┘     └──────────────────┘     └──────────────────┘
                         ClusterIP Service
```

Location: `infrastructure/nfs-proxy/deployment.yaml`

```yaml
spec:
  nodeSelector:
    kubernetes.io/hostname: neko  # Must run on neko
  containers:
    - name: nfs-server
      image: erichough/nfs-server
      env:
        - name: NFS_EXPORT_0
          value: "/data/k8s-backup *(rw,sync,no_subtree_check,no_root_squash,fsid=0)"
      volumeMounts:
        - name: upstream-nfs
          mountPath: /data
  volumes:
    - name: upstream-nfs
      nfs:
        server: 192.168.1.234
        path: /volume/.../Shared_Drive_Example/.data
```

---

## DATABASE MANAGEMENT

### CloudNativePG Overview

CloudNativePG manages PostgreSQL clusters as Kubernetes-native resources.

### PostgreSQL Clusters

| Cluster | Namespace | Service | Instances | Size | Backed Up |
|---------|-----------|---------|-----------|------|-----------|
| authentik-db | authentik | authentik-db-rw.authentik.svc:5432 | 1 | 5Gi | Yes |
| outline-db | outline | outline-db-rw.outline.svc:5432 | 1 | 5Gi | Yes |
| n8n-db | n8n | n8n-db-rw.n8n.svc:5432 | 1 | 5Gi | No |
| open-webui-db | open-webui | open-webui-db-rw.open-webui.svc:5432 | 1 | 10Gi | No |
| plane-db | plane | plane-db-rw.plane.svc:5432 | 1 (Helm) | 10Gi | No |

### Cluster Definition Pattern

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: myapp-db
  namespace: myapp
spec:
  instances: 1
  storage:
    size: 5Gi
    storageClass: longhorn
  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "128MB"
  bootstrap:
    initdb:
      database: myapp
      owner: myapp
  monitoring:
    enablePodMonitor: true
```

### Connecting to Databases

**From within cluster**:
```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: myapp-db-app  # Auto-generated by CNPG
        key: uri
```

**Manual connection**:
```bash
kubectl exec -it -n authentik authentik-db-1 -- psql -U authentik -d authentik
```

### Database Secrets

CNPG automatically creates secrets with connection details:
- `{cluster}-app` - Application credentials (user/password/uri)
- `{cluster}-superuser` - Superuser credentials

---

## MONITORING AND OBSERVABILITY

### Stack Components

| Component | Purpose | URL |
|-----------|---------|-----|
| Prometheus | Metrics collection | Internal |
| Grafana | Dashboards | grafana.lab.axiomlayer.com |
| Alertmanager | Alert routing | alerts.lab.axiomlayer.com |
| Loki | Log aggregation | Internal |
| Promtail | Log shipping | Internal |

### Prometheus Configuration

Location: `apps/argocd/applications/kube-prometheus-stack.yaml`

Key settings:
```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # Discover all ServiceMonitors
```

### Grafana Datasources

1. **Prometheus** - Auto-provisioned by kube-prometheus-stack
2. **Loki** - Added via Helm values:

```yaml
grafana:
  additionalDataSources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki:3100
      isDefault: false
```

### Alert Rules

Location: `infrastructure/alertmanager/prometheus-rules.yaml`

**Node Alerts**:
- `NodeDown` - Node unreachable for 2m (critical)
- `NodeHighCPU` - CPU > 80% for 5m (warning)
- `NodeHighMemory` - Memory > 85% for 5m (warning)
- `NodeDiskSpaceLow` - Disk < 15% for 5m (warning)
- `NodeDiskSpaceCritical` - Disk < 5% for 2m (critical)

**Kubernetes Alerts**:
- `PodCrashLooping` - Pod restarted 3+ times in 15m (warning)
- `PodNotReady` - Pod not ready for 10m (warning)
- `DeploymentReplicasMismatch` - Replicas mismatch for 10m (warning)
- `PersistentVolumeSpaceLow` - PV < 15% space for 5m (warning)

**Certificate Alerts**:
- `CertificateExpiringSoon` - Expires in < 7 days (warning)
- `CertificateExpiryCritical` - Expires in < 24 hours (critical)

**Longhorn Alerts**:
- `LonghornVolumeHealthy` - Volume not attached for 5m (warning)
- `LonghornNodeDown` - Storage node not ready for 5m (critical)

### Alertmanager Configuration

Location: `infrastructure/alertmanager/configmap.yaml`

```yaml
route:
  group_by: ['alertname', 'namespace', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'critical'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://n8n.n8n.svc:5678/webhook/alerts'
        send_resolved: true
  - name: 'critical'
    webhook_configs:
      - url: 'http://n8n.n8n.svc:5678/webhook/alerts-critical'
        send_resolved: true
```

Alerts are sent to n8n webhooks for custom notification workflows.

---

## BACKUP AND DISASTER RECOVERY

### Backup Strategy

1. **Database Backups** - Daily pg_dump via CronJob
2. **Longhorn Snapshots** - Daily/Weekly via RecurringJobs
3. **etcd Snapshots** - K3s automatic snapshots

### Database Backup CronJob

Location: `infrastructure/backups/backup-cronjob.yaml`

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: homelab-backup
  namespace: longhorn-system
spec:
  schedule: "0 3 * * *"  # 3 AM daily
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          nodeSelector:
            kubernetes.io/hostname: neko  # NFS access
          containers:
            - name: backup
              image: postgres:16-alpine
              command:
                - /bin/sh
                - -c
                - |
                  DATE=$(date +%Y%m%d-%H%M%S)
                  BACKUP_DIR="/backup/homelab-$DATE"
                  mkdir -p "$BACKUP_DIR"

                  # Backup Authentik DB
                  PGPASSWORD="$AUTHENTIK_DB_PASSWORD" pg_dump \
                    -h authentik-db-rw.authentik.svc \
                    -U authentik -d authentik \
                    > "$BACKUP_DIR/authentik-db.sql"

                  # Backup Outline DB
                  PGPASSWORD="$OUTLINE_DB_PASSWORD" pg_dump \
                    -h outline-db-rw.outline.svc \
                    -U outline -d outline \
                    > "$BACKUP_DIR/outline-db.sql"

                  # Cleanup old (keep 7)
                  cd /backup && ls -dt homelab-*/ | tail -n +8 | xargs -r rm -rf
              volumeMounts:
                - name: backup-storage
                  mountPath: /backup
          volumes:
            - name: backup-storage
              nfs:
                server: 192.168.1.234
                path: /.../.data/k8s-backup
```

### Backup Locations

| Backup Type | Location | Retention |
|-------------|----------|-----------|
| Database dumps | NAS:/k8s-backup/homelab-YYYYMMDD/ | 7 days |
| Longhorn snapshots | Local Longhorn storage | 7 daily, 4 weekly |
| etcd snapshots | /var/lib/rancher/k3s/server/db/snapshots/ | K3s default |

### Disaster Recovery Procedures

#### Full Cluster Rebuild

1. **Provision K3s nodes**:
   ```bash
   sudo ./scripts/provision-k3s-server.sh jasen --init          # First node
   sudo ./scripts/provision-k3s-server.sh jasen --join <IP>     # Additional
   ```

2. **Bootstrap ArgoCD**:
   ```bash
   ./scripts/bootstrap-argocd.sh
   ```

3. **Re-seal all secrets** (new Sealed Secrets controller = new keys):
   ```bash
   kubeseal --fetch-cert > sealed-secrets-pub.pem
   # Re-seal all secrets from .env
   ```

4. **Sync root application in ArgoCD UI**

5. **Restore databases from NAS backups**

#### Database Restore

```bash
# Connect to new database pod
kubectl exec -it -n authentik authentik-db-1 -- bash

# Restore from backup
psql -U authentik -d authentik < /backup/homelab-YYYYMMDD/authentik-db.sql
```

#### Longhorn Volume Restore

1. Access Longhorn UI
2. Go to Backup tab
3. Find volume by PVC name
4. Click "Restore Latest Backup"
5. Create PV/PVC pointing to restored volume

---

## CI/CD PIPELINE

### GitHub Actions Workflow

Location: `.github/workflows/ci.yaml`

### Jobs Overview

```
┌─────────────────────┐
│  validate-manifests │
│    (kustomize)      │
└─────────┬───────────┘
          │
┌─────────▼───────────┐
│        lint         │
│   (kube-linter)     │
└─────────┬───────────┘
          │
┌─────────▼───────────┐
│      security       │
│      (Trivy)        │
└─────────┬───────────┘
          │
┌─────────▼───────────┐
│     ci-passed       │
│  (gate + sync)      │
└─────────┬───────────┘
          │
     ┌────┴────┐
     │         │
┌────▼────┐ ┌──▼───────┐
│ integ-  │ │ outline- │
│ tests   │ │   sync   │
└─────────┘ └──────────┘
```

### Job Details

#### 1. validate-manifests

Runs `./tests/validate-manifests.sh`:
- Finds all kustomization.yaml files
- Runs `kubectl kustomize` on each
- Fails if any kustomization is invalid

#### 2. lint

Runs kube-linter with `.kube-linter.yaml` config:
```yaml
checks:
  exclude:
    - "no-read-only-root-fs"  # Some apps need writable fs
    - "no-anti-affinity"       # Single replica apps
    - "latest-tag"             # Tracked separately
```

#### 3. security

Runs Trivy:
```bash
trivy config . --severity HIGH,CRITICAL --exit-code 0
trivy fs . --scanners secret --exit-code 1  # Fail on secrets
```

#### 4. ci-passed

Gate job that:
- Checks all previous jobs succeeded
- Triggers ArgoCD sync via API:
  ```bash
  curl -X POST \
    -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" \
    "https://argocd.lab.axiomlayer.com/api/v1/applications/applications/sync"
  ```

#### 5. integration-tests

Runs after ArgoCD sync:
- `./tests/smoke-test.sh` - 29 infrastructure health checks
- `./tests/test-auth.sh` - 14 authentication flow tests

#### 6. outline-sync

Syncs markdown docs to Outline wiki:
```bash
python3 scripts/outline_sync.py
```

### Self-Hosted Runners

Location: `infrastructure/actions-runner/`

Runners are deployed using actions-runner-controller:
```yaml
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: homelab-runners
  namespace: actions-runner
spec:
  replicas: 1
  template:
    spec:
      repository: jasencdev/axiomlayer
      labels:
        - homelab
        - self-hosted
      serviceAccountName: actions-runner
      dockerEnabled: true
```

Runner RBAC provides read-only cluster access for tests.

### Required Secrets

| Secret | Purpose |
|--------|---------|
| ARGOCD_AUTH_TOKEN | ArgoCD API access for sync trigger |
| OUTLINE_API_TOKEN | Outline API for doc sync |

---

## SECRETS MANAGEMENT

### Sealed Secrets Overview

All secrets are encrypted using Bitnami Sealed Secrets.

**Controller**: `infrastructure/sealed-secrets/`
**Namespace**: `kube-system`

### Creating a Sealed Secret

```bash
# Create regular secret manifest
kubectl create secret generic my-secret \
  --namespace my-namespace \
  --from-literal=api-key=supersecret \
  --dry-run=client -o yaml > secret.yaml

# Seal it
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --format yaml \
  < secret.yaml > sealed-secret.yaml

# Commit sealed-secret.yaml (never the plain secret!)
```

### Secrets Inventory

| Namespace | Secret | Purpose | Keys |
|-----------|--------|---------|------|
| actions-runner | github-arc-token | GitHub PAT | github_token |
| argocd | argocd-secret | OIDC client secret | oidc.authentik.clientSecret |
| authentik | authentik-helm-secrets | Authentik config | secret_key |
| authentik | authentik-outpost-token | Outpost auth | token |
| campfire | campfire-secret | Rails secret | SECRET_KEY_BASE, VAPID keys |
| campfire | ghcr-pull-secret | GHCR pull | .dockerconfigjson |
| cert-manager | cloudflare-api-token | DNS-01 | api-token |
| external-dns | cloudflare-api-token | DNS mgmt | api-token |
| longhorn-system | backup-db-credentials | DB backup | authentik-password, outline-password |
| monitoring | grafana-oidc-secret | Grafana OIDC | client-id, client-secret |
| n8n | n8n-secrets | n8n config | db-password, encryption-key |
| open-webui | open-webui-secret | Open WebUI | WEBUI_SECRET_KEY |
| outline | outline-secrets | Outline config | database-url, secret-key, utils-secret, oidc-* |

### .env File

The `.env` file (gitignored) stores plain-text values for re-sealing:

```bash
# Example .env structure (NOT real values)
AUTHENTIK_SECRET_KEY=...
AUTHENTIK_POSTGRESQL_PASSWORD=...
CLOUDFLARE_API_TOKEN=...
GITHUB_RUNNER_TOKEN=...
GRAFANA_OIDC_CLIENT_ID=...
GRAFANA_OIDC_CLIENT_SECRET=...
# ... etc
```

### Secret Rotation Procedure

1. Generate new credential
2. Update `.env`
3. Re-create sealed secret:
   ```bash
   kubectl create secret generic my-secret \
     --from-literal=key=NEW_VALUE \
     --dry-run=client -o yaml | \
     kubeseal --format yaml > sealed-secret.yaml
   ```
4. Commit and push
5. Restart affected pods

---

## APPLICATION CATALOG

### Platform Applications

#### Dashboard

- **URL**: db.lab.axiomlayer.com
- **Auth**: Forward Auth
- **Purpose**: Homelab service dashboard with real-time metrics
- **Technology**: Static HTML + JavaScript + nginx
- **Location**: `apps/dashboard/`

Features:
- Live CPU, memory, storage, network metrics from Prometheus
- Service status indicators
- Links to all applications
- Dark theme with modern UI

#### ArgoCD

- **URL**: argocd.lab.axiomlayer.com
- **Auth**: Native OIDC
- **Purpose**: GitOps continuous delivery
- **Technology**: ArgoCD Helm chart
- **Location**: `apps/argocd/`

### User Applications

#### Campfire

- **URL**: chat.lab.axiomlayer.com
- **Auth**: Forward Auth
- **Purpose**: Team chat (37signals open source)
- **Technology**: Ruby on Rails
- **Database**: SQLite (local PVC)
- **Location**: `apps/campfire/`

Special requirements:
- Needs writable filesystem (`readOnlyRootFilesystem: false`)
- Private GHCR image (requires pull secret)
- AMD64 only (nodeSelector)

#### n8n (autom8)

- **URL**: autom8.lab.axiomlayer.com
- **Auth**: Forward Auth
- **Purpose**: Workflow automation
- **Database**: CNPG PostgreSQL (n8n-db)
- **Location**: `apps/n8n/`

Integration points:
- Receives Alertmanager webhooks
- Can trigger external APIs

#### Outline

- **URL**: docs.lab.axiomlayer.com
- **Auth**: Native OIDC
- **Purpose**: Documentation wiki
- **Database**: CNPG PostgreSQL (outline-db) + Redis
- **Location**: `apps/outline/`

Features:
- Markdown documentation
- OIDC authentication
- S3-compatible storage (local filesystem)

#### Plane

- **URL**: plane.lab.axiomlayer.com
- **Auth**: Native OIDC
- **Purpose**: Project management / issue tracking
- **Technology**: Helm chart (plane-ce)
- **Location**: `apps/plane/`

Components (via Helm):
- PostgreSQL
- Redis
- RabbitMQ
- MinIO (object storage)

#### Open WebUI

- **URL**: ai.lab.axiomlayer.com
- **Auth**: Forward Auth
- **Purpose**: AI chat interface
- **Backend**: Ollama on siberian (100.115.3.88:11434)
- **Database**: CNPG PostgreSQL (open-webui-db)
- **Location**: `infrastructure/open-webui/`

Configuration:
```yaml
OLLAMA_BASE_URL: "http://100.115.3.88:11434"
RAG_EMBEDDING_ENGINE: "ollama"
RAG_EMBEDDING_MODEL: "granite4:3b"
RAG_OLLAMA_BASE_URL: "http://100.79.124.94:11434"  # panther for embeddings
```

### Infrastructure Applications

#### Telnet Server

- **URL**: telnet.lab.axiomlayer.com
- **Auth**: Forward Auth
- **Purpose**: Demo application for testing SSO
- **Replicas**: 2 (with PDB)
- **Location**: `apps/telnet-server/`

---

## SECURITY PATTERNS

### Pod Security Standards

All deployments follow these security patterns:

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true  # When possible
        capabilities:
          drop: ["ALL"]
```

### Exceptions

Some applications require exceptions:

| Application | Exception | Reason |
|-------------|-----------|--------|
| Campfire | readOnlyRootFilesystem: false | Rails tmp/cache |
| n8n | readOnlyRootFilesystem: false | Node.js modules |
| Outline | readOnlyRootFilesystem: false | File uploads |
| NFS Proxy | privileged: true | NFS kernel module |

### RBAC Patterns

**Minimal cluster access** (actions-runner):
```yaml
rules:
  - apiGroups: [""]
    resources: ["nodes", "pods", "pods/log", "persistentvolumeclaims", "configmaps"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list"]
  - apiGroups: ["cert-manager.io"]
    resources: ["certificates"]
    verbs: ["get", "list"]
```

**Service account with specific namespace access** (external-dns):
```yaml
rules:
  - apiGroups: ["", "extensions", "networking.k8s.io"]
    resources: ["services", "endpoints", "pods", "ingresses", "nodes"]
    verbs: ["get", "watch", "list"]
```

### Network Security

Default-deny network policies in every namespace with explicit allow rules:
1. Allow ingress from Traefik only
2. Allow egress to DNS
3. Allow egress to specific databases
4. Allow egress to external APIs (when needed)

---

## PROVISIONING SCRIPTS

### provision-k3s-server.sh

Location: `scripts/provision-k3s-server.sh`

Purpose: Sets up a K3s server node with full hardening.

**Usage**:
```bash
# First server
sudo ./provision-k3s-server.sh jasen --init

# Additional servers
sudo ./provision-k3s-server.sh jasen --join 100.67.134.110
```

**What it does**:
1. System update
2. Install packages (btop, curl, git, zsh, etc.)
3. Install GitHub CLI
4. Install Tailscale
5. SSH hardening (port 22879, key-only, no root)
6. UFW firewall (allow K3s ports, Tailscale)
7. Oh My Zsh + Dracula theme
8. Realtek R8125 driver (for NUCs)
9. K3s installation with Tailscale interface

### bootstrap-argocd.sh

Location: `scripts/bootstrap-argocd.sh`

Purpose: Bootstrap ArgoCD and GitOps from scratch.

**What it does**:
1. Install Helm
2. Install Sealed Secrets controller
3. Install ArgoCD via Helm
4. Apply root application
5. Output admin password

### Other Scripts

- `provision-k3s-agent.sh` - Set up worker node
- `provision-ollama-workstation.sh` - Set up GPU workstation
- `backup-homelab.sh` - Pre-maintenance backup
- `outline_sync.py` - Sync docs to Outline

---

## TESTING FRAMEWORK

### smoke-test.sh

Location: `tests/smoke-test.sh`

**Tests** (29 total):
1. Node health (all Ready)
2. Core services (ArgoCD, Traefik, cert-manager)
3. Authentication (Authentik server, outpost)
4. Storage (Longhorn, PVCs bound)
5. Monitoring (Prometheus, Grafana)
6. Databases (CNPG clusters)
7. Applications (Dashboard, Outline, n8n, Open WebUI, Plane, Campfire)
8. Certificates (all valid)
9. Endpoint health (HTTP status checks)

### test-auth.sh

Location: `tests/test-auth.sh`

**Tests** (14 total):
1. Authentik health check
2. Forward auth outpost running
3. Forward auth apps redirect to Authentik
4. HTTPS connectivity
5. Native OIDC apps accessible
6. OIDC discovery endpoints
7. ArgoCD OIDC integration
8. Grafana OIDC integration

### validate-manifests.sh

Location: `tests/validate-manifests.sh`

Validates all Kustomize manifests compile without errors.

---

## OPERATIONAL PROCEDURES

### Adding a New Application

1. Create directory structure:
   ```
   apps/myapp/
   ├── namespace.yaml
   ├── deployment.yaml
   ├── service.yaml
   ├── certificate.yaml
   ├── ingress.yaml
   ├── networkpolicy.yaml
   └── kustomization.yaml
   ```

2. Create ArgoCD Application:
   ```
   apps/argocd/applications/myapp.yaml
   ```

3. Add to kustomization:
   ```
   apps/argocd/applications/kustomization.yaml
   ```

4. Configure Authentik (if using Forward Auth):
   - Add Proxy Provider in blueprints
   - Add to outpost providers list

5. Commit and push

### Rolling Back

**Via ArgoCD UI**:
1. Open ArgoCD
2. Select application
3. Click History
4. Select previous sync
5. Click Rollback

**Via kubectl**:
```bash
kubectl rollout undo deployment/myapp -n myapp
```

### Node Maintenance

```bash
# Cordon
kubectl cordon node-name

# Drain
kubectl drain node-name --ignore-daemonsets --delete-emptydir-data

# Perform maintenance

# Uncordon
kubectl uncordon node-name
```

### Debugging Applications

```bash
# Logs
kubectl logs -n namespace deployment/app -f

# Shell access
kubectl exec -it -n namespace deployment/app -- /bin/sh

# Events
kubectl get events -n namespace --sort-by='.lastTimestamp'

# Describe
kubectl describe pod/app-xxx -n namespace
```

---

## TROUBLESHOOTING REFERENCE

### Certificate Not Issuing

```bash
# Check certificate
kubectl describe certificate myapp-tls -n myapp

# Check CertificateRequest
kubectl get certificaterequests -n myapp

# Check Challenge
kubectl get challenges -n myapp
kubectl describe challenge xxx -n myapp

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager | grep myapp
```

**Common causes**:
- Cloudflare API token invalid
- DNS propagation delay (wait 7+ minutes)
- Rate limiting

### ArgoCD Sync Issues

```bash
# Force sync
kubectl patch application myapp -n argocd --type merge \
  -p '{"operation":{"sync":{"force":true}}}'

# Hard refresh
kubectl patch application myapp -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Pod Won't Start

```bash
# Check status
kubectl describe pod/xxx -n namespace

# Common issues:
# - ImagePullBackOff: Check image name, pull secret
# - CrashLoopBackOff: Check logs, resources, config
# - Pending: Check node resources, PVC binding, node selectors
```

### Database Connection Failed

```bash
# Check CNPG cluster
kubectl get clusters -n namespace
kubectl describe cluster mydb -n namespace

# Check endpoints
kubectl get endpoints mydb-rw -n namespace

# Test connection
kubectl run psql --rm -it --image=postgres:16 -- \
  psql -h mydb-rw.namespace.svc -U user -d database
```

### Authentik Issues

```bash
# Check server
kubectl logs -n authentik -l app.kubernetes.io/name=authentik-server

# Check outpost
kubectl logs -n authentik -l goauthentik.io/outpost-name=forward-auth-outpost

# Restart outpost
kubectl rollout restart deployment/ak-outpost-forward-auth-outpost -n authentik
```

---

## CONFIGURATION REFERENCE

### Key ConfigMaps

| Namespace | ConfigMap | Purpose |
|-----------|-----------|---------|
| argocd | argocd-cm | ArgoCD main config |
| argocd | argocd-cmd-params-cm | Server parameters |
| argocd | argocd-rbac-cm | RBAC policies |
| authentik | authentik-blueprints | App/provider definitions |
| alertmanager | alertmanager-config | Alert routing |
| dashboard | dashboard-config | HTML content |
| open-webui | open-webui-config | Ollama endpoints |

### Important Annotations

**Ingress Forward Auth**:
```yaml
traefik.ingress.kubernetes.io/router.middlewares: authentik-ak-outpost-forward-auth-outpost@kubernetescrd
```

**Ingress TLS**:
```yaml
traefik.ingress.kubernetes.io/router.entrypoints: websecure
traefik.ingress.kubernetes.io/router.tls: "true"
```

**ArgoCD Sync Wave**:
```yaml
argocd.argoproj.io/sync-wave: "5"
```

### Required Labels

```yaml
labels:
  app.kubernetes.io/name: myapp
  app.kubernetes.io/component: server
  app.kubernetes.io/part-of: homelab
  app.kubernetes.io/managed-by: argocd
```

---

## API AND INTEGRATION REFERENCE

### ArgoCD API

**Trigger sync**:
```bash
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  "https://argocd.lab.axiomlayer.com/api/v1/applications/myapp/sync"
```

### Authentik API

**Base URL**: `https://auth.lab.axiomlayer.com/api/v3/`

### Prometheus API

**Query**:
```bash
curl "http://prometheus:9090/api/v1/query?query=up"
```

### Alertmanager API

**Silence**:
```bash
curl -X POST "http://alertmanager:9093/api/v2/silences" \
  -H "Content-Type: application/json" \
  -d '{"matchers":[{"name":"alertname","value":"MyAlert"}],"startsAt":"...","endsAt":"..."}'
```

### Longhorn API

**List volumes**:
```bash
kubectl get volumes -n longhorn-system -o json
```

### Outline API

**Base URL**: `https://docs.lab.axiomlayer.com/api/`

Used by `scripts/outline_sync.py` for documentation synchronization.

---

## GLOSSARY

| Term | Definition |
|------|------------|
| ArgoCD | GitOps continuous delivery tool |
| Authentik | Identity provider / SSO platform |
| Blueprint | Authentik declarative configuration |
| CNPG | CloudNativePG - PostgreSQL operator |
| Forward Auth | Authentication via proxy (Traefik → Authentik) |
| Kustomize | Kubernetes manifest templating |
| Longhorn | Distributed block storage for Kubernetes |
| OIDC | OpenID Connect - authentication protocol |
| Sealed Secret | Encrypted Kubernetes secret |
| Tailscale | WireGuard-based mesh VPN |
| Traefik | Ingress controller and load balancer |

---

## QUICK REFERENCE COMMANDS

```bash
# Cluster status
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running

# ArgoCD apps
kubectl get applications -n argocd

# Certificates
kubectl get certificates -A

# PVCs
kubectl get pvc -A

# Secrets (sealed)
kubectl get sealedsecrets -A

# Recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -10

# Restart deployment
kubectl rollout restart deployment/myapp -n namespace

# Port forward for debugging
kubectl port-forward svc/myapp -n namespace 8080:80

# Run tests
./tests/smoke-test.sh
./tests/test-auth.sh
./tests/validate-manifests.sh
```

---

*This document was generated for RAG indexing. Last updated: 2025-11-30*
