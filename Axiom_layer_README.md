# Axiom Layer

**Sovereign software company. Democratized.**

A complete platform for developers who want to own their infrastructure end-to-end. Three machines, 30 minutes, zero vendors.

```bash
npx create-axiom-layer@latest
```

---

## What is this?

Axiom Layer is an open-source PaaS that gives you everything you need to run a software company—dev platform, business operations, identity management—on hardware you own.

No cloud bills. No vendor lock-in. No permission required.

## The Stack

### Infrastructure Layer
| Component | Purpose |
|-----------|---------|
| K3s | Lightweight Kubernetes |
| Tailscale | Mesh networking, zero firewall config |
| Traefik | Ingress, automatic HTTPS |
| cert-manager | Let's Encrypt certificates |
| Sealed Secrets | GitOps-safe secret management |
| Longhorn | Distributed storage |

### Platform Layer
| Component | Purpose | URL |
|-----------|---------|-----|
| Authentik | SSO + RBAC for everything | `auth.yourdomain.com` |
| GitLab | Code, CI/CD, container registry | `git.yourdomain.com` |
| ArgoCD | GitOps deployments | `deploy.yourdomain.com` |
| CloudNativePG | Managed Postgres | - |
| Redis Operator | Managed Redis | - |
| Grafana + Loki + Prometheus | Observability | `metrics.yourdomain.com` |

### Business Operations Layer
| Component | Purpose | URL |
|-----------|---------|-----|
| Plane | Project management (Linear alternative) | `projects.yourdomain.com` |
| Campfire | Team chat | `chat.yourdomain.com` |
| Outline | Documentation & wiki | `docs.yourdomain.com` |
| Invoice Ninja | Invoicing | `billing.yourdomain.com` |
| Akaunting | Bookkeeping | `books.yourdomain.com` |
| Cal.com | Scheduling | `cal.yourdomain.com` |
| Twenty | CRM | `crm.yourdomain.com` |
| Vaultwarden | Password management | `vault.yourdomain.com` |
| Nextcloud | File storage | `files.yourdomain.com` |
| Postal | Transactional email | `mail.yourdomain.com` |

**Every app inherits SSO. Zero auth code required.**

## Why?

### The Problem

Running a software company requires dozens of SaaS subscriptions:

| Service | Annual Cost |
|---------|-------------|
| Okta / Auth0 | $50,000+ |
| GitHub Enterprise | $20,000+ |
| Jira / Linear | $30,000+ |
| Slack | $20,000+ |
| Salesforce | $50,000+ |
| QuickBooks | $10,000+ |
| Datadog | $50,000+ |
| AWS / Azure | $200,000+ |
| **Total** | **$430,000+/year** |

Plus: vendor lock-in, data sovereignty concerns, compliance complexity, and zero ownership.

### The Solution

| Axiom Layer | Cost |
|-------------|------|
| 3x Mini PCs | $1,200 (one-time) |
| Electricity | ~$100/year |
| Domain | $12/year |
| **Total** | **$1,312 first year, $112 ongoing** |

Same capabilities. Same SSO. Same audit trails. You own it.

## Requirements

### Hardware (Reference Build)

| Qty | Component | Specs | Est. Cost |
|-----|-----------|-------|-----------|
| 3 | Intel NUC / Mini PC | N100+, 16GB RAM, 512GB NVMe | $300-400 each |
| 1 | Network switch | Gigabit, 5+ ports | $30 |
| 1 | UPS (optional) | 600VA+ | $80 |

**Total: ~$1,000-1,400**

Any x86_64 machines with 8GB+ RAM work. Raspberry Pi 4/5 supported as worker nodes.

### Network

- Tailscale account (free tier works)
- Domain name
- Cloudflare account (free tier, for DNS)

## Quick Start

### 1. Provision Nodes

Boot each machine with Ubuntu 24.04 LTS, then:

```bash
curl -fsSL https://get.axiomlayer.com | bash
```

Answer the prompts:
- Node role (control-plane or worker)
- Tailscale auth key
- Domain name

### 2. Access Your Platform

Once provisioned:

```
https://auth.yourdomain.com     → SSO portal
https://git.yourdomain.com      → GitLab
https://deploy.yourdomain.com   → ArgoCD
https://projects.yourdomain.com → Plane
https://chat.yourdomain.com     → Campfire
https://docs.yourdomain.com     → Outline
```

### 3. Push Code

```bash
git clone https://git.yourdomain.com/yourteam/myapp.git
cd myapp
# write code
git push
```

ArgoCD detects the change. Builds. Deploys. Your app is live at `myapp.yourdomain.com` with SSO protection.

## The Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Developer                                    │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ git push
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  GitHub / GitLab                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │    Code     │→ │   CI/CD     │→ │ GHCR/Registry│                 │
│  └─────────────┘  └─────────────┘  └─────────────┘                 │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ image pushed, manifest updated
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ArgoCD (GitOps)                                                     │
│  Watches repo → Syncs to cluster                                    │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ deploys
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  K3s Cluster                                                         │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Nodes: neko (control) + neko2 (control) + bobcat (worker)  │   │
│  │  Connected via Tailscale mesh                                │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ request
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Traefik Ingress + Authentik Forward Auth                           │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  myapp.yourdomain.com                                       │    │
│  │       │                                                     │    │
│  │       ▼                                                     │    │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────┐             │    │
│  │  │ Traefik  │───▶│ Authentik│───▶│   App    │             │    │
│  │  │  (TLS)   │    │ (verify) │    │ (headers)│             │    │
│  │  └──────────┘    └──────────┘    └──────────┘             │    │
│  │                       │                                     │    │
│  │              X-Authentik-Username                           │    │
│  │              X-Authentik-Email                              │    │
│  │              X-Authentik-Groups                             │    │
│  └────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

## SSO Everywhere

Every application is protected by Authentik forward auth. Your apps receive user context via headers:

```
X-Authentik-Username: jasen
X-Authentik-Email: jasen@company.com
X-Authentik-Groups: engineers,admins
```

**No OAuth libraries. No JWT validation. No session management. No auth code.**

Your app just reads headers. Authentik handles the rest.

## RBAC

Define once in Authentik, enforce everywhere:

| Role | GitLab | ArgoCD | Plane | Billing | Docs | Chat |
|------|--------|--------|-------|---------|------|------|
| Founder | Full | Full | Full | Full | Full | Full |
| Engineer | Full | Full | Full | None | Full | Full |
| Finance | Read | None | Read | Full | Full | Full |
| PM | Read | Read | Full | Read | Full | Full |
| Contractor | Scoped | None | Scoped | None | Scoped | Full |

Onboarding: Add user → Assign group → Done.
Offboarding: Disable user → Locked out of everything.

## GitOps

Your entire platform is defined in Git:

```
axiom-layer/
├── infrastructure/
│   ├── cert-manager/
│   ├── authentik/
│   ├── gitlab/
│   └── longhorn/
├── platform/
│   ├── argocd/
│   ├── grafana/
│   └── postgres-operator/
├── business/
│   ├── plane/
│   ├── campfire/
│   ├── outline/
│   └── invoice-ninja/
└── apps/
    └── your-apps-here/
```

Fork it. Customize it. It's yours.

## Comparison

| Feature | AWS + SaaS | Coolify | Dokku | **Axiom Layer** |
|---------|------------|---------|-------|-----------------|
| Multi-node HA | ✅ | ❌ | ❌ | ✅ |
| Built-in SSO | ❌ | ❌ | ❌ | ✅ |
| GitOps | Manual | ❌ | ❌ | ✅ |
| Business ops | Separate SaaS | ❌ | ❌ | ✅ |
| Data sovereignty | ❌ | ✅ | ✅ | ✅ |
| Compliance-ready | $$$$ | ❌ | ❌ | ✅ |
| Cost/year | $100k+ | $0 | $0 | $0 |

## Use Cases

**Solo Developer**
- Tired of $500/month cloud bills
- Wants to own their stack
- Side projects that might become businesses

**Small Team (2-10)**
- Needs real infrastructure without enterprise pricing
- Wants SSO without Auth0 costs
- Values data ownership

**Regulated Industries**
- HIPAA, SOC2, GxP requirements
- Need on-prem but hate enterprise tooling
- Audit trail requirements

**Privacy-Conscious**
- Won't ship user data to AWS
- Wants EU data residency
- Values digital sovereignty

## Current Status

**First workload deployed with full SSO protection** (November 2025)

The core platform is operational:
- telnet-server deployed via GHCR → K3s → Traefik → Authentik
- Forward auth protecting `/metrics` endpoint at `https://telnet.lab.axiomlayer.com/metrics`
- Domain-level SSO with shared cookies across `*.lab.axiomlayer.com`

Live services:
| Service | URL | Status |
|---------|-----|--------|
| Authentik SSO | `https://auth.lab.axiomlayer.com` | ✅ |
| ArgoCD | `https://argocd.lab.axiomlayer.com` | ✅ |
| Telnet Metrics | `https://telnet.lab.axiomlayer.com/metrics` | ✅ |

## Roadmap

- [x] K3s multi-node cluster
- [x] Tailscale mesh networking
- [x] GitOps with ArgoCD
- [x] SSO with Authentik
- [x] Automatic TLS (cert-manager + Cloudflare DNS-01)
- [x] Sealed secrets
- [x] Forward auth middleware (domain-level)
- [x] Container registry (GHCR integration)
- [x] First workload deployed with SSO
- [ ] GitHub Actions CI pipeline
- [ ] GitLab self-hosted (optional, for private repos)
- [ ] Postgres operator (CloudNativePG)
- [ ] Storage (Longhorn)
- [ ] Observability stack (Grafana + Loki + Prometheus)
- [ ] Business ops suite
- [ ] CLI installer
- [ ] Bootable USB image
- [ ] Documentation site

## Contributing

This is early. Very early. But the foundation is solid.

If you believe developers should own their infrastructure:
- Star this repo
- Try it out
- Open issues
- Submit PRs

## Philosophy

> You don't need permission to ship software.
> 
> You don't need a credit card on file with AWS.
> 
> You don't need to pay per seat, per build, per GB.
> 
> Buy hardware once. Own it forever.
> 
> **Platform company in a box.**

## License

MIT. Fork it. Sell it. We don't care. Just build something.

---

**Axiom Layer** — Sovereign software company. Democratized.

[Documentation](https://docs.axiomlayer.com) · [Discord](https://discord.gg/axiomlayer) · [Twitter](https://twitter.com/axiomlayer)