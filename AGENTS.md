# Repository Guidelines

## Overview
GitOps-managed K3s homelab with ArgoCD, Authentik SSO, managed TLS, automated
backups, and self-hosted CI. Everything in `main` is the cluster’s desired
state; agents edit manifests, validate locally, push, and let Argo sync.

- **Domain**: `*.lab.axiomlayer.com`
- **Cluster**: 4-node K3s (2 control-plane, 2 workers) over Tailscale mesh
- **Ingress/TLS**: Traefik + cert-manager (Cloudflare DNS-01)
- **Auth**: Authentik forward auth + native OIDC providers
- **Storage**: Longhorn with NFS proxy backups to UniFi NAS

## Architecture Snapshot
| Layer | Components | Notes |
|-------|------------|-------|
| Cluster | neko, neko2 (servers); panther, bobcat (agents) | panther hosts ARC runners + Longhorn data |
| GitOps | ArgoCD App-of-Apps rooted at `apps/argocd/applications/root.yaml` | `argocd-helm` Application is manual-sync to avoid loops |
| CI/CD | actions-runner-controller, GitHub Actions self-hosted runners | Runners labeled `self-hosted, homelab`; run on panther |
| Auth & Access | Authentik 2025.10, forward-auth outpost, native OIDC | Tokens + client secrets sealed per app |
| Observability | Prometheus, Grafana, Loki, Alertmanager | Extras under `infrastructure/monitoring` |
| Data | CloudNativePG clusters per app, Longhorn volumes, daily CronJob backups | Backup CronJob pinned to neko for NAS reachability |

## Service Catalog
| Service | URL | Auth Mode | Namespace | Notes |
|---------|-----|-----------|-----------|-------|
| ArgoCD | `argocd.lab.axiomlayer.com` | Dex OIDC (Authentik) | `argocd` | Controlled by `apps/argocd/applications/argocd-helm.yaml` |
| Authentik | `auth.lab.axiomlayer.com` | Native | `authentik` | CNPG-backed; seeds forward-auth + OAuth providers |
| Dashboard | `db.lab.axiomlayer.com` | Forward Auth | `dashboard` | Static Nginx portal |
| Alertmanager | `alerts.lab.axiomlayer.com` | Forward Auth | `monitoring` | Routing + receiver config under `infrastructure/alertmanager` |
| Grafana | `grafana.lab.axiomlayer.com` | Native OIDC | `monitoring` | Datasources provisioned by kube-prometheus-stack |
| Longhorn UI | `longhorn.lab.axiomlayer.com` | Forward Auth | `longhorn-system` | Storage class + backup target definitions |
| Plane | `plane.lab.axiomlayer.com` | Native OIDC | `plane` | Includes Redis + CNPG cluster |
| Outline | `docs.lab.axiomlayer.com` | Native OIDC | `outline` | Works with Outline sync automation |
| n8n | `autom8.lab.axiomlayer.com` | Forward Auth | `n8n` | CNPG database + webhook ingress |
| Campfire | `chat.lab.axiomlayer.com` | Forward Auth | `campfire` | Rails app; documented read-write filesystem |
| Open WebUI | `ai.lab.axiomlayer.com` | Forward Auth | `open-webui` | Connects to Ollama on `siberian` (Tailscale) |

## Repository Layout
```
axiomlayer/
├── clusters/lab/                   # Root kustomization synced by ArgoCD
├── apps/<service>/                 # Workload-specific manifests (namespace → ingress)
│   └── ...
├── apps/argocd/applications/       # App-of-Apps definitions + kustomization
├── infrastructure/<component>/     # Operators, shared services, sealed secrets
├── docs/                           # Markdown synced to Outline (see outline_sync)
├── outline_sync/                   # Outline publishing config/state
├── scripts/                        # Provisioning, backup, outline sync helpers
└── tests/                          # Smoke + regression scripts (bash)
```

## Workflow & Expectations
1. Edit manifests under the appropriate directory (app vs infrastructure).
2. Validate locally (`kubectl kustomize`, `kubectl apply --dry-run=server`).
3. Update or add smoke tests if behavior changes.
4. Document manual steps in the PR description (Argo syncs, secret rotations).
5. Push to a feature branch; CI mirrors the same validation commands before
   ArgoCD reconciles the change downstream.

## Build, Test, and Development Commands
| Command | Purpose |
|---------|---------|
| `kubectl kustomize clusters/lab` | Render entire fleet; catches broken patches before Argo sees them. |
| `kubectl kustomize apps/<name>` | Focused render while iterating on a single workload. |
| `kubectl apply --dry-run=server -k <path>` | API-server validation for manifests/CRDs. |
| `./tests/test-auth.sh` | Authentik forward auth + HTTPS regression suite (health, redirects, OIDC). |
| `python3 scripts/outline_sync.py` | Publish docs to Outline using `OUTLINE_API_TOKEN`; leverages `outline_sync/state.json`. |
| `scripts/provision-k3s-{server,agent}.sh` | Bootstrap nodes with tailscale0 networking, Longhorn deps, and kubeconfig wiring. |
| `scripts/backup-homelab.sh` | Snapshot Sealed Secrets, CNPG dumps, Longhorn metadata prior to risky ops. |

## Coding Style & Naming Conventions
- YAML: two-space indentation, logical key grouping, keep manifests minimal to
  ease diffs. Always apply Kubernetes recommended labels (`app.kubernetes.io/*`,
  `managed-by=argocd`).
- Naming: namespace/service/host slugs match (e.g., `plane` →
  `plane.lab.axiomlayer.com`). Certificates live alongside apps and reference the
  matching hosts.
- Security context: run as UID/GID 1000, drop ALL capabilities, disable privilege
  escalation, prefer read-only root FS. Document any deviation inline.
- Network policy: default deny plus explicit allow objects placed with the app.
- Shell scripts: `#!/bin/bash`, `set -euo pipefail`, lowercase-kebab filenames,
  clear logging for CI readability.
- Markdown: sentence-case headings, short paragraphs for Outline sync stability.

## Testing Guidelines
- Tests live in `tests/` and follow the PASS/FAIL format in `tests/test-auth.sh`.
- Add capability-focused scripts (`test-backups.sh`, `test-nfs-proxy.sh`) when
  touching infrastructure with blast radius.
- Manifest changes that impact cluster primitives must capture validation output
  in PRs (`kubectl kustomize`, dry-run apply). Mention any live checks you ran
  (e.g., `kubectl get applications -n argocd`, `kubectl logs -n cert-manager ...`).
- For fixes to Authentik, Traefik, or TLS, rerun `./tests/test-auth.sh` and paste
  a short summary of results in the PR.

### Existing Test Suite
| Script | Location | Coverage |
|--------|----------|----------|
| `tests/test-auth.sh` | `tests/` | Authentik health, forward-auth redirects, HTTPS probes, OIDC discovery |
| `tests/smoke-test.sh` *(run ad hoc)* | `tests/` | Cluster resources, ingress, Longhorn, CNPG checks (update when new components added) |
| `tests/validate-manifests.sh` | `tests/` | Kustomize render + `kubectl apply --dry-run=server` across critical overlays |

## Commit & Pull Request Guidelines
- Commit messages are imperative, present tense (`Add Copilot coding agent
  instructions`, `Fix CI concurrency guard`). Keep commits deployable; squash
  noisy WIP before opening a PR.
- PR descriptions should include: scope summary, directories touched, validation
  commands run, any manual cluster steps (forced sync, reseal secrets), and
  screenshots/logs for UI or auth changes. Tag issues in Plane/GitHub when
  relevant and note whether ArgoCD needs operator attention.

## Security & Secrets
- Use Sealed Secrets for everything sensitive; never commit plaintext tokens,
  kubeconfigs, or `.env`. Place sealed manifests under the component they serve
  and annotate required scopes (Cloudflare DNS:Edit, GitHub PAT admin:org,
  Outline docs:write).
- cert-manager and external-dns depend on public resolvers 1.1.1.1/8.8.8.8—do not
  alter unless validated.
- Longhorn backups rely on the NFS proxy pod (nodeSelector `neko`) and the `nfsd`
  kernel module loaded at boot (`scripts/provision-k3s-server.sh` handles this).
- Provision new hardware via `scripts/provision-*` to enforce consistent
  tailscale0 networking, containerd settings, and ARC prerequisites.

## Key Commands
```bash
# Render + validate
kubectl kustomize clusters/lab
kubectl apply --dry-run=server -k apps/<name>

# Inspect ArgoCD Applications
kubectl get applications -n argocd
kubectl describe application <name> -n argocd | sed -n '/status:/,$p'

# Troubleshoot cert-manager / DNS
kubectl logs deployment/cert-manager -n cert-manager --tail=200 | grep <host>
kubectl describe certificaterequest <name> -n <namespace>
dig @1.1.1.1 _acme-challenge.<host>.lab.axiomlayer.com TXT

# Longhorn & backups
kubectl get volumes.longhorn.io -n longhorn-system \
  -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness
kubectl get recurringjobs.longhorn.io -n longhorn-system
kubectl logs -n longhorn-system -l job-name=homelab-backup --tail=200

# Authentik forward-auth outpost
kubectl logs -n authentik -l goauthentik.io/outpost-name=forward-auth-outpost --tail=150

# Outline sync
OUTLINE_API_TOKEN=<token> python3 scripts/outline_sync.py
```

## Adding a New Service
1. **Scaffold**: copy `templates/app` or an existing workload (`apps/plane`),
   ensuring namespace, deployment, service, certificate, ingress, network policy,
   optional PDB, and `kustomization.yaml` are present.
2. **Security context**: set UID/GID 1000, drop ALL capabilities, mark root FS
   read-only unless the app requires writes (document exceptions inline).
3. **Register with Argo**: create `apps/argocd/applications/<name>.yaml`, add it
   to the local kustomization, and assign sync waves/prune settings as needed.
4. **Auth**: decide between forward-auth (Traefik annotation) or native OIDC.
   For OIDC, create Authentik provider + application, store client
   ID/secret via Sealed Secret, and configure the workload to use it.
5. **Storage & dependencies**: define PVCs (default `longhorn`), CNPG clusters,
   ConfigMaps/Secrets, and network policies referencing dependent namespaces.
6. **Validation**: run `kubectl kustomize` + server dry-run, execute relevant
   smoke tests, and note results in the PR.
7. **Documentation**: update `docs/` + Outline sync plan if the service surfaces
   to end-users; mention manual steps (e.g., DNS delegation, Authentik setup) in
   the PR checklist.

## Operational Playbooks
- Use `docs/ARCHITECTURE.md`, `docs/APPLICATIONS.md`, and
  `docs/OUTLINE_SYNC_PLAN.md` for deep dives. Reference them instead of
  re-describing workflows in PRs.
- ArgoCD drift: `kubectl get applications -n argocd`, inspect `status.health` and
  `operationState`; unschedulable Jobs may need manual deletion before resync.
- Certificate issues: `kubectl describe certificate`, `certificaterequest`, and
  `challenge` plus `dig @1.1.1.1 _acme-challenge.<host> TXT`.
- Longhorn: `kubectl get volumes -n longhorn-system -o custom-columns=...` to
  spot degraded replicas, then check recurring jobs/backuptargets.
- Outline sync: set `OUTLINE_API_TOKEN`, run the script, review diffs in
  `outline_sync/state.json`, then push once IDs stabilize.
- Secrets rotation: regenerate locally, re-seal with cluster public cert
  (`kubeseal --fetch-cert`), update manifests, and document the rotation in the
  PR so operators can audit later.

## Agent Collaboration Notes
- Multiple AI agents contribute here; leave breadcrumbs via comments or TODOs
  when context is non-obvious (e.g., why a sync wave was changed, why a value is
  hardcoded). Avoid large-scale reformatting—keep diffs scannable.
- When creating scaffolding, prefer `templates/` or cloning a mature app (Plane,
  Outline) so security contexts, probes, and ingress annotations remain
  consistent.
- Sync documentation changes with Outline soon after merging so the on-cluster
  knowledge base stays current.
