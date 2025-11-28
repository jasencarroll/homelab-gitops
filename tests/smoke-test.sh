#!/bin/bash
# Smoke tests for homelab infrastructure
# Run: ./tests/smoke-test.sh

set -e

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0
PASSED=0

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAILED=$((FAILED + 1))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found"
    exit 1
fi

section "Node Health"

# Check all nodes are Ready
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
READY_NODES=$(kubectl get nodes --no-headers | grep -c " Ready")
if [ "$NODE_COUNT" -eq "$READY_NODES" ]; then
    pass "All $NODE_COUNT nodes are Ready"
else
    fail "Only $READY_NODES/$NODE_COUNT nodes are Ready"
fi

section "Core Services"

# ArgoCD
if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers | grep -q "Running"; then
    pass "ArgoCD server is running"
else
    fail "ArgoCD server is not running"
fi

# Traefik
if kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik --no-headers | grep -q "Running"; then
    pass "Traefik ingress is running"
else
    fail "Traefik ingress is not running"
fi

# Cert-manager
if kubectl get pods -n cert-manager -l app.kubernetes.io/name=cert-manager --no-headers | grep -q "Running"; then
    pass "cert-manager is running"
else
    fail "cert-manager is not running"
fi

section "Authentication"

# Authentik server
if kubectl get pods -n authentik -l app.kubernetes.io/name=authentik --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Authentik server is running"
else
    fail "Authentik server is not running"
fi

# Authentik outpost
if kubectl get pods -n authentik -l goauthentik.io/outpost-name=forward-auth-outpost --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Authentik forward-auth outpost is running"
else
    fail "Authentik forward-auth outpost is not running"
fi

section "Storage"

# Longhorn
if kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers | grep -q "Running"; then
    pass "Longhorn manager is running"
else
    fail "Longhorn manager is not running"
fi

# Check PVCs are bound
UNBOUND_PVC=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -v "Bound" | wc -l)
if [ "$UNBOUND_PVC" -eq 0 ]; then
    pass "All PVCs are bound"
else
    fail "$UNBOUND_PVC PVCs are not bound"
fi

section "Monitoring"

# Prometheus
if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Prometheus is running"
else
    fail "Prometheus is not running"
fi

# Grafana
if kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Grafana is running"
else
    fail "Grafana is not running"
fi

section "Databases"

# CloudNativePG - Authentik DB
if kubectl get pods -n authentik -l cnpg.io/cluster=authentik-db --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Authentik PostgreSQL is running"
else
    fail "Authentik PostgreSQL is not running"
fi

# CloudNativePG - Outline DB
if kubectl get pods -n outline -l cnpg.io/cluster=outline-db --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Outline PostgreSQL is running"
else
    fail "Outline PostgreSQL is not running"
fi

section "Applications"

# Dashboard
if kubectl get pods -n dashboard -l app.kubernetes.io/name=dashboard --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Dashboard is running"
else
    fail "Dashboard is not running"
fi

# Outline
if kubectl get pods -n outline -l app.kubernetes.io/name=outline --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Outline is running"
else
    fail "Outline is not running"
fi

# n8n
if kubectl get pods -n n8n -l app.kubernetes.io/name=n8n --no-headers 2>/dev/null | grep -q "Running"; then
    pass "n8n is running"
else
    fail "n8n is not running"
fi

# Open WebUI
if kubectl get pods -n open-webui -l app.kubernetes.io/name=open-webui --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Open WebUI is running"
else
    fail "Open WebUI is not running"
fi

# Plane
PLANE_PODS=$(kubectl get pods -n plane --no-headers 2>/dev/null | grep -c "Running" || echo 0)
if [ "$PLANE_PODS" -gt 0 ]; then
    pass "Plane is running ($PLANE_PODS pods)"
else
    fail "Plane is not running"
fi

# Campfire
if kubectl get pods -n campfire -l app.kubernetes.io/name=campfire --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Campfire is running"
else
    fail "Campfire is not running"
fi

section "Certificates"

# Check certificates are valid
INVALID_CERTS=$(kubectl get certificates -A --no-headers 2>/dev/null | grep -v "True" | wc -l)
if [ "$INVALID_CERTS" -eq 0 ]; then
    pass "All certificates are valid"
else
    fail "$INVALID_CERTS certificates are not ready"
    kubectl get certificates -A --no-headers | grep -v "True"
fi

section "Endpoint Health Checks"

check_endpoint() {
    local name=$1
    local url=$2
    local expected=$3

    STATUS=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
    if [ "$STATUS" = "$expected" ] || [ "$STATUS" = "302" ] || [ "$STATUS" = "200" ]; then
        pass "$name ($url) - HTTP $STATUS"
    else
        fail "$name ($url) - HTTP $STATUS (expected $expected)"
    fi
}

check_endpoint "Dashboard" "https://db.lab.axiomlayer.com/" "302"
check_endpoint "ArgoCD" "https://argocd.lab.axiomlayer.com/" "200"
check_endpoint "Grafana" "https://grafana.lab.axiomlayer.com/" "302"
check_endpoint "Authentik" "https://auth.lab.axiomlayer.com/" "200"
check_endpoint "Outline" "https://docs.lab.axiomlayer.com/" "200"
check_endpoint "n8n" "https://autom8.lab.axiomlayer.com/" "302"
check_endpoint "Open WebUI" "https://ai.lab.axiomlayer.com/" "302"
check_endpoint "Plane" "https://plane.lab.axiomlayer.com/" "200"
check_endpoint "Longhorn" "https://longhorn.lab.axiomlayer.com/" "302"
check_endpoint "Alertmanager" "https://alerts.lab.axiomlayer.com/" "302"

section "Summary"

TOTAL=$((PASSED + FAILED))
echo ""
echo "Tests: $TOTAL | Passed: $PASSED | Failed: $FAILED"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
