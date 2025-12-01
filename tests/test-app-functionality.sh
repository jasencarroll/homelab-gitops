#!/bin/bash
# test-app-functionality.sh - Application functionality verification tests
# Tests that applications are not just running but actually functioning correctly

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Test results array
declare -a TEST_RESULTS=()

# Application endpoints
OPEN_WEBUI_URL="${OPEN_WEBUI_URL:-https://ai.lab.axiomlayer.com}"
N8N_URL="${N8N_URL:-https://autom8.lab.axiomlayer.com}"
OUTLINE_URL="${OUTLINE_URL:-https://docs.lab.axiomlayer.com}"
PLANE_URL="${PLANE_URL:-https://plane.lab.axiomlayer.com}"
CAMPFIRE_URL="${CAMPFIRE_URL:-https://chat.lab.axiomlayer.com}"
DASHBOARD_URL="${DASHBOARD_URL:-https://db.lab.axiomlayer.com}"
ARGOCD_URL="${ARGOCD_URL:-https://argocd.lab.axiomlayer.com}"
GRAFANA_URL="${GRAFANA_URL:-https://grafana.lab.axiomlayer.com}"
AUTHENTIK_URL="${AUTHENTIK_URL:-https://auth.lab.axiomlayer.com}"

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_section() {
    echo -e "\n${YELLOW}─── $1 ───${NC}\n"
}

pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    PASSED=$((PASSED + 1))
    TEST_RESULTS+=("PASS: $1")
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
    TEST_RESULTS+=("FAIL: $1")
}

skip() {
    echo -e "${YELLOW}○ SKIP${NC}: $1"
    SKIPPED=$((SKIPPED + 1))
    TEST_RESULTS+=("SKIP: $1")
}

info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
}

# Check if curl is available
check_prerequisites() {
    print_section "Checking Prerequisites"

    if ! command -v curl &> /dev/null; then
        fail "curl not found in PATH"
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        fail "kubectl not found in PATH"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        fail "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    pass "Prerequisites met (curl, kubectl available)"
}

# Helper function to make HTTP requests
http_request() {
    local url="$1"
    local method="${2:-GET}"
    local data="${3:-}"
    local headers="${4:-}"
    local timeout="${5:-10}"

    local curl_args=(-s -S -L --max-time "$timeout" -X "$method")

    # Add headers if provided
    if [[ -n "$headers" ]]; then
        while IFS= read -r header; do
            curl_args+=(-H "$header")
        done <<< "$headers"
    fi

    # Add data if provided
    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    curl "${curl_args[@]}" "$url" 2>&1
}

# Helper function to check HTTP status
check_http_status() {
    local url="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-10}"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" -L "$url" 2>/dev/null || echo "000")

    if [[ "$status" == "$expected_status" ]]; then
        return 0
    else
        echo "$status"
        return 1
    fi
}

# Test 1: Authentik SSO Provider
test_authentik() {
    print_section "Authentik SSO Tests"

    # Check Authentik API health
    local health_url="${AUTHENTIK_URL}/api/v3/root/config/"
    local response
    response=$(http_request "$health_url" "GET" "" "" 15)

    if echo "$response" | grep -q "error_reporting"; then
        pass "Authentik API is responding"
    else
        fail "Authentik API not responding properly"
        return
    fi

    # Check OpenID configuration endpoint
    local oidc_url="${AUTHENTIK_URL}/application/o/.well-known/openid-configuration"
    response=$(http_request "$oidc_url" "GET" "" "" 10)

    if echo "$response" | grep -q "authorization_endpoint"; then
        pass "Authentik OIDC discovery endpoint accessible"
    else
        fail "Authentik OIDC discovery endpoint not working"
    fi

    # Check JWKS endpoint
    local jwks_url="${AUTHENTIK_URL}/application/o/argocd/jwks/"
    response=$(http_request "$jwks_url" "GET" "" "" 10)

    if echo "$response" | grep -q "keys"; then
        pass "Authentik JWKS endpoint accessible"
    else
        skip "Authentik JWKS endpoint check (may need specific provider)"
    fi

    # Check Authentik outpost is running
    local outpost_pods
    outpost_pods=$(kubectl get pods -n authentik -l "goauthentik.io/outpost-name=forward-auth-outpost" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)

    if [[ "$outpost_pods" -ge 1 ]]; then
        pass "Authentik forward-auth outpost is running ($outpost_pods pod(s))"
    else
        fail "Authentik forward-auth outpost not running"
    fi
}

# Test 2: ArgoCD GitOps
test_argocd() {
    print_section "ArgoCD GitOps Tests"

    # Check ArgoCD API health
    local api_url="${ARGOCD_URL}/api/version"
    local response
    response=$(http_request "$api_url" "GET" "" "" 10)

    if echo "$response" | grep -q "Version\|version"; then
        pass "ArgoCD API is responding"
        local version
        version=$(echo "$response" | grep -o '"Version":"[^"]*"' | cut -d'"' -f4)
        info "ArgoCD version: $version"
    else
        fail "ArgoCD API not responding properly"
    fi

    # Check ArgoCD health endpoint
    local health_url="${ARGOCD_URL}/healthz"
    if check_http_status "$health_url" "200"; then
        pass "ArgoCD health endpoint returns 200"
    else
        fail "ArgoCD health endpoint not healthy"
    fi

    # Check application sync status via kubectl
    local apps_synced
    apps_synced=$(kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.status.sync.status}{"\n"}{end}' 2>/dev/null | grep -c "Synced" || echo "0")

    local apps_total
    apps_total=$(kubectl get applications -n argocd -o name 2>/dev/null | wc -l)

    if [[ "$apps_synced" -eq "$apps_total" ]] && [[ "$apps_total" -gt 0 ]]; then
        pass "All $apps_total ArgoCD applications are synced"
    else
        info "$apps_synced of $apps_total ArgoCD applications are synced"
        # List out-of-sync apps
        local out_of_sync
        out_of_sync=$(kubectl get applications -n argocd -o jsonpath='{range .items[?(@.status.sync.status!="Synced")]}{.metadata.name}{" "}{end}' 2>/dev/null)
        if [[ -n "$out_of_sync" ]]; then
            info "Out of sync apps: $out_of_sync"
        fi
    fi

    # Check application health status
    local apps_healthy
    apps_healthy=$(kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.status.health.status}{"\n"}{end}' 2>/dev/null | grep -c "Healthy" || echo "0")

    if [[ "$apps_healthy" -eq "$apps_total" ]] && [[ "$apps_total" -gt 0 ]]; then
        pass "All $apps_total ArgoCD applications are healthy"
    else
        info "$apps_healthy of $apps_total ArgoCD applications are healthy"
    fi
}

# Test 3: Grafana Monitoring Dashboard
test_grafana() {
    print_section "Grafana Dashboard Tests"

    # Check Grafana health
    local health_url="${GRAFANA_URL}/api/health"
    local response
    response=$(http_request "$health_url" "GET" "" "" 10)

    if echo "$response" | grep -q "ok\|database"; then
        pass "Grafana health endpoint accessible"
    else
        fail "Grafana health endpoint not responding"
        return
    fi

    # Check Grafana frontend loads
    local main_url="${GRAFANA_URL}/login"
    response=$(http_request "$main_url" "GET" "" "" 10)

    if echo "$response" | grep -qi "grafana\|login"; then
        pass "Grafana login page loads"
    else
        fail "Grafana login page not loading"
    fi

    # Check datasources via kubectl (Prometheus should be configured)
    local prometheus_ds
    prometheus_ds=$(kubectl get configmap -n monitoring -o name 2>/dev/null | grep -c "grafana-datasource\|prometheus" || echo "0")

    if [[ "$prometheus_ds" -gt 0 ]]; then
        pass "Grafana has datasource configurations"
    else
        info "Could not verify Grafana datasource configuration"
    fi
}

# Test 4: Open WebUI AI Interface
test_open_webui() {
    print_section "Open WebUI Tests"

    # Check if namespace exists
    if ! kubectl get namespace open-webui &> /dev/null; then
        skip "Open WebUI namespace does not exist"
        return
    fi

    # Check Open WebUI health endpoint
    local health_url="${OPEN_WEBUI_URL}/health"
    local response
    response=$(http_request "$health_url" "GET" "" "" 10)

    if echo "$response" | grep -qi "status.*true\|ok\|healthy"; then
        pass "Open WebUI health endpoint returns healthy"
    else
        # Try alternative health check - just see if main page loads
        if check_http_status "$OPEN_WEBUI_URL" "200" || check_http_status "$OPEN_WEBUI_URL" "302"; then
            pass "Open WebUI main page accessible"
        else
            fail "Open WebUI not responding"
            return
        fi
    fi

    # Check if Ollama backend is configured and reachable
    local ollama_endpoint="http://100.115.3.88:11434/api/tags"
    response=$(http_request "$ollama_endpoint" "GET" "" "" 5 2>/dev/null || echo "unreachable")

    if echo "$response" | grep -q "models"; then
        pass "Ollama backend (siberian) is reachable"
        local model_count
        model_count=$(echo "$response" | grep -o '"name"' | wc -l)
        info "Ollama has $model_count model(s) available"
    else
        skip "Ollama backend not reachable (may be expected if siberian is offline)"
    fi

    # Check database connectivity
    local db_pod
    db_pod=$(kubectl get pods -n open-webui -l "cnpg.io/cluster=open-webui-db" --field-selector=status.phase=Running -o name 2>/dev/null | head -1)

    if [[ -n "$db_pod" ]]; then
        pass "Open WebUI database pod is running"
    else
        fail "Open WebUI database pod not running"
    fi
}

# Test 5: n8n Workflow Automation
test_n8n() {
    print_section "n8n Workflow Automation Tests"

    # Check if namespace exists
    if ! kubectl get namespace n8n &> /dev/null; then
        skip "n8n namespace does not exist"
        return
    fi

    # Check n8n health
    local health_url="${N8N_URL}/healthz"
    if check_http_status "$health_url" "200"; then
        pass "n8n health endpoint returns 200"
    else
        # Try alternative - check if redirect to auth happens
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${N8N_URL}" 2>/dev/null || echo "000")
        if [[ "$status" == "200" ]] || [[ "$status" == "302" ]] || [[ "$status" == "401" ]]; then
            pass "n8n is responding (status: $status)"
        else
            fail "n8n not responding (status: $status)"
            return
        fi
    fi

    # Check n8n pod is running with correct configuration
    local n8n_pod
    n8n_pod=$(kubectl get pods -n n8n -l "app.kubernetes.io/name=n8n" --field-selector=status.phase=Running -o name 2>/dev/null | head -1)

    if [[ -n "$n8n_pod" ]]; then
        pass "n8n pod is running"

        # Check for database connection errors in logs
        local db_errors
        db_errors=$(kubectl logs "${n8n_pod#pod/}" -n n8n --tail=100 2>/dev/null | grep -iE "database.*error|connection.*refused|postgres.*fail" | wc -l)

        if [[ "$db_errors" -eq 0 ]]; then
            pass "n8n has no database connection errors in recent logs"
        else
            fail "n8n has $db_errors database error(s) in recent logs"
        fi
    else
        fail "n8n pod not running"
    fi

    # Check database
    local db_pod
    db_pod=$(kubectl get pods -n n8n -l "cnpg.io/cluster=n8n-db" --field-selector=status.phase=Running -o name 2>/dev/null | head -1)

    if [[ -n "$db_pod" ]]; then
        pass "n8n database pod is running"
    else
        fail "n8n database pod not running"
    fi
}

# Test 6: Outline Documentation Wiki
test_outline() {
    print_section "Outline Wiki Tests"

    # Check if namespace exists
    if ! kubectl get namespace outline &> /dev/null; then
        skip "Outline namespace does not exist"
        return
    fi

    # Check Outline health/api
    local main_url="${OUTLINE_URL}"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -L "$main_url" 2>/dev/null || echo "000")

    if [[ "$status" == "200" ]] || [[ "$status" == "302" ]]; then
        pass "Outline is responding (status: $status)"
    else
        fail "Outline not responding (status: $status)"
        return
    fi

    # Check Outline API availability
    local api_url="${OUTLINE_URL}/api/auth.config"
    local response
    response=$(http_request "$api_url" "POST" "" "Content-Type: application/json" 10)

    if echo "$response" | grep -qiE "providers\|name\|services"; then
        pass "Outline API is functional"
    else
        info "Outline API response check inconclusive"
    fi

    # Check Outline pod
    local outline_pod
    outline_pod=$(kubectl get pods -n outline -l "app.kubernetes.io/name=outline" --field-selector=status.phase=Running -o name 2>/dev/null | head -1)

    if [[ -n "$outline_pod" ]]; then
        pass "Outline pod is running"
    else
        fail "Outline pod not running"
    fi

    # Check database
    local db_pod
    db_pod=$(kubectl get pods -n outline -l "cnpg.io/cluster=outline-db" --field-selector=status.phase=Running -o name 2>/dev/null | head -1)

    if [[ -n "$db_pod" ]]; then
        pass "Outline database pod is running"
    else
        fail "Outline database pod not running"
    fi
}

# Test 7: Plane Project Management
test_plane() {
    print_section "Plane Project Management Tests"

    # Check if namespace exists
    if ! kubectl get namespace plane &> /dev/null; then
        skip "Plane namespace does not exist"
        return
    fi

    # Check Plane main page
    local main_url="${PLANE_URL}"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -L "$main_url" 2>/dev/null || echo "000")

    if [[ "$status" == "200" ]] || [[ "$status" == "302" ]]; then
        pass "Plane is responding (status: $status)"
    else
        fail "Plane not responding (status: $status)"
        return
    fi

    # Check Plane pods
    local plane_pods
    plane_pods=$(kubectl get pods -n plane --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)

    if [[ "$plane_pods" -gt 0 ]]; then
        pass "Plane has $plane_pods running pod(s)"
    else
        fail "Plane has no running pods"
    fi

    # Check for critical errors in logs
    local api_pod
    api_pod=$(kubectl get pods -n plane -l "app.kubernetes.io/component=api" --field-selector=status.phase=Running -o name 2>/dev/null | head -1)

    if [[ -n "$api_pod" ]]; then
        local critical_errors
        critical_errors=$(kubectl logs "${api_pod#pod/}" -n plane --tail=50 2>/dev/null | grep -iE "critical|fatal|panic" | wc -l)

        if [[ "$critical_errors" -eq 0 ]]; then
            pass "Plane API has no critical errors in recent logs"
        else
            fail "Plane API has $critical_errors critical error(s) in recent logs"
        fi
    fi
}

# Test 8: Campfire Team Chat
test_campfire() {
    print_section "Campfire Team Chat Tests"

    # Check if namespace exists
    if ! kubectl get namespace campfire &> /dev/null; then
        skip "Campfire namespace does not exist"
        return
    fi

    # Check Campfire main page
    local main_url="${CAMPFIRE_URL}"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -L "$main_url" 2>/dev/null || echo "000")

    if [[ "$status" == "200" ]] || [[ "$status" == "302" ]]; then
        pass "Campfire is responding (status: $status)"
    else
        fail "Campfire not responding (status: $status)"
        return
    fi

    # Check Campfire pod
    local campfire_pod
    campfire_pod=$(kubectl get pods -n campfire -l "app.kubernetes.io/name=campfire" --field-selector=status.phase=Running -o name 2>/dev/null | head -1)

    if [[ -n "$campfire_pod" ]]; then
        pass "Campfire pod is running"

        # Check for Rails errors
        local rails_errors
        rails_errors=$(kubectl logs "${campfire_pod#pod/}" -n campfire --tail=50 2>/dev/null | grep -iE "ActionView::Template::Error\|ActiveRecord::.*Error\|RuntimeError" | wc -l)

        if [[ "$rails_errors" -eq 0 ]]; then
            pass "Campfire has no Rails errors in recent logs"
        else
            info "Campfire has $rails_errors Rails error(s) in recent logs"
        fi
    else
        fail "Campfire pod not running"
    fi
}

# Test 9: Dashboard
test_dashboard() {
    print_section "Dashboard Tests"

    # Check if namespace exists
    if ! kubectl get namespace dashboard &> /dev/null; then
        skip "Dashboard namespace does not exist"
        return
    fi

    # Check Dashboard main page
    local main_url="${DASHBOARD_URL}"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -L "$main_url" 2>/dev/null || echo "000")

    if [[ "$status" == "200" ]] || [[ "$status" == "302" ]]; then
        pass "Dashboard is responding (status: $status)"
    else
        fail "Dashboard not responding (status: $status)"
        return
    fi

    # Check Dashboard pod
    local dashboard_pod
    dashboard_pod=$(kubectl get pods -n dashboard --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)

    if [[ "$dashboard_pod" -gt 0 ]]; then
        pass "Dashboard has $dashboard_pod running pod(s)"
    else
        fail "Dashboard has no running pods"
    fi
}

# Test 10: Database Health Checks
test_database_health() {
    print_section "Database Health Tests"

    local databases=(
        "authentik:authentik-db"
        "outline:outline-db"
        "n8n:n8n-db"
        "open-webui:open-webui-db"
    )

    for db_info in "${databases[@]}"; do
        IFS=':' read -r namespace cluster <<< "$db_info"

        if ! kubectl get namespace "$namespace" &> /dev/null; then
            skip "Namespace '$namespace' does not exist"
            continue
        fi

        # Check CNPG cluster status
        local cluster_status
        cluster_status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null)

        if [[ "$cluster_status" == "Cluster in healthy state" ]]; then
            pass "Database cluster '$cluster' is healthy"
        elif [[ -n "$cluster_status" ]]; then
            info "Database cluster '$cluster' status: $cluster_status"
        else
            # Fallback: check if pods are running
            local db_pods
            db_pods=$(kubectl get pods -n "$namespace" -l "cnpg.io/cluster=$cluster" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)

            if [[ "$db_pods" -gt 0 ]]; then
                pass "Database '$cluster' has $db_pods running pod(s)"
            else
                fail "Database '$cluster' has no running pods"
            fi
        fi

        # Check replication status for HA databases
        local replicas
        replicas=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.spec.instances}' 2>/dev/null)

        if [[ -n "$replicas" ]] && [[ "$replicas" -gt 1 ]]; then
            local ready_replicas
            ready_replicas=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.readyInstances}' 2>/dev/null)

            if [[ "$ready_replicas" -eq "$replicas" ]]; then
                pass "Database '$cluster' has all $replicas replicas ready"
            else
                info "Database '$cluster' has $ready_replicas of $replicas replicas ready"
            fi
        fi
    done
}

# Print summary
print_summary() {
    print_header "Test Summary"

    echo -e "Total tests: $((PASSED + FAILED + SKIPPED))"
    echo -e "${GREEN}Passed${NC}: $PASSED"
    echo -e "${RED}Failed${NC}: $FAILED"
    echo -e "${YELLOW}Skipped${NC}: $SKIPPED"

    if [[ $FAILED -gt 0 ]]; then
        echo -e "\n${RED}Failed tests:${NC}"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == FAIL:* ]]; then
                echo "  - ${result#FAIL: }"
            fi
        done
    fi

    echo ""

    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}All application functionality tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some application functionality tests failed!${NC}"
        exit 1
    fi
}

# Main execution
main() {
    print_header "Application Functionality Tests"

    check_prerequisites

    # Core infrastructure tests
    test_authentik
    test_argocd
    test_grafana

    # Application tests
    test_open_webui
    test_n8n
    test_outline
    test_plane
    test_campfire
    test_dashboard

    # Database health
    test_database_health

    print_summary
}

main "$@"
