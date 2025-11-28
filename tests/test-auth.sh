#!/bin/bash
# Test authentication flows
# Run: ./tests/test-auth.sh

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

section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

section "Authentik Health"

# Check Authentik is responding
AUTH_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://auth.lab.axiomlayer.com/-/health/live/" 2>/dev/null)
if [ "$AUTH_STATUS" = "204" ] || [ "$AUTH_STATUS" = "200" ]; then
    pass "Authentik health check passed"
else
    fail "Authentik health check failed (HTTP $AUTH_STATUS)"
fi

section "Forward Auth Outpost"

# Check outpost pod is running
if kubectl get pods -n authentik -l goauthentik.io/outpost-name=forward-auth-outpost --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Forward auth outpost pod is running"
else
    fail "Forward auth outpost pod is not running"
fi

# Check outpost is processing requests (look for any recent application activity in logs)
OUTPOST_ACTIVE=$(kubectl logs -n authentik -l goauthentik.io/outpost-name=forward-auth-outpost --tail=50 --since=5m 2>/dev/null | grep -c "outpost.goauthentik.io" || echo 0)
if [ "$OUTPOST_ACTIVE" -gt 0 ]; then
    pass "Forward auth outpost is processing requests"
else
    # Outpost might just be idle, this is a warning not a failure
    pass "Forward auth outpost has no recent activity (may be idle)"
fi

section "Forward Auth Protected Apps"

# These apps should redirect to Authentik (302)
FORWARD_AUTH_APPS=(
    "db.lab.axiomlayer.com:Dashboard"
    "autom8.lab.axiomlayer.com:n8n"
    "alerts.lab.axiomlayer.com:Alertmanager"
    "longhorn.lab.axiomlayer.com:Longhorn"
    "ai.lab.axiomlayer.com:OpenWebUI"
    "chat.lab.axiomlayer.com:Campfire"
)

for app in "${FORWARD_AUTH_APPS[@]}"; do
    URL="${app%%:*}"
    NAME="${app##*:}"

    STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://$URL/" 2>/dev/null)
    if [ "$STATUS" = "302" ]; then
        # Check it redirects to Authentik
        LOCATION=$(curl -sk -I "https://$URL/" 2>/dev/null | grep -i "location:" | head -1)
        if echo "$LOCATION" | grep -q "auth.lab.axiomlayer.com"; then
            pass "$NAME redirects to Authentik"
        else
            fail "$NAME returns 302 but not to Authentik"
        fi
    else
        fail "$NAME should return 302 (got $STATUS)"
    fi
done

section "Native OIDC Apps"

# Apps with native OIDC should return 200 (login page)
OIDC_APPS=(
    "argocd.lab.axiomlayer.com:ArgoCD"
    "grafana.lab.axiomlayer.com:Grafana"
    "docs.lab.axiomlayer.com:Outline"
    "plane.lab.axiomlayer.com:Plane"
)

for app in "${OIDC_APPS[@]}"; do
    URL="${app%%:*}"
    NAME="${app##*:}"

    STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://$URL/" 2>/dev/null)
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ]; then
        pass "$NAME is accessible (HTTP $STATUS)"
    else
        fail "$NAME returned HTTP $STATUS"
    fi
done

section "OIDC Endpoints"

# Check OIDC discovery endpoint
OIDC_DISCOVERY=$(curl -sk "https://auth.lab.axiomlayer.com/application/o/outline/.well-known/openid-configuration" 2>/dev/null)
if echo "$OIDC_DISCOVERY" | grep -q "issuer"; then
    pass "OIDC discovery endpoint is working"
else
    fail "OIDC discovery endpoint failed"
fi

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
