#!/bin/bash
# Validate Kubernetes manifests
# Run: ./tests/validate-manifests.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

FAILED=0
PASSED=0

echo "Validating Kubernetes manifests..."
echo ""

# Find all kustomization directories
KUSTOMIZE_DIRS=$(find "$REPO_ROOT/apps" "$REPO_ROOT/infrastructure" -name "kustomization.yaml" -exec dirname {} \; 2>/dev/null | sort)

for dir in $KUSTOMIZE_DIRS; do
    REL_PATH="${dir#$REPO_ROOT/}"

    # Try to build the kustomization
    if kubectl kustomize "$dir" > /dev/null 2>&1; then
        echo -e "${GREEN}[PASS]${NC} $REL_PATH"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}[FAIL]${NC} $REL_PATH"
        kubectl kustomize "$dir" 2>&1 | head -5
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "========================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "========================================"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
