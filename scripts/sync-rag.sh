#!/bin/bash
# sync-rag.sh - Sync repository files to Open WebUI RAG knowledge base
#
# Tag-based versioned sync: Files are uploaded with version suffix (e.g., README__v1.0.0.md)
# This avoids ChromaDB duplicate embedding issues and provides version history.
#
# Usage: RAG_VERSION=v1.0.0 ./sync-rag.sh
#
# Required environment variables:
#   OPEN_WEBUI_API_KEY - API key from Open WebUI Settings > Account
#   OPEN_WEBUI_KNOWLEDGE_ID - Knowledge base ID to sync files to
#
# Optional environment variables:
#   RAG_VERSION - Version tag (default: from git describe or 'unversioned')
#   FORCE_FULL_SYNC - Set to "true" to sync all files regardless of changes

set -euo pipefail

# Configuration
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
export KUBECONFIG="${KUBECONFIG:-/home/jasen/.kube/config}"

# Get version from env or git tag
RAG_VERSION="${RAG_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo 'unversioned')}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --help|-h)
            echo "Usage: RAG_VERSION=v1.0.0 $0"
            echo ""
            echo "Tag-based versioned sync to Open WebUI RAG knowledge base."
            echo "Files are uploaded with version suffix (e.g., README__v1.0.0.md)"
            echo ""
            echo "Environment variables:"
            echo "  OPEN_WEBUI_API_KEY      - API key (required)"
            echo "  OPEN_WEBUI_KNOWLEDGE_ID - Knowledge base ID (required)"
            echo "  RAG_VERSION             - Version tag (default: from git describe)"
            echo "  FORCE_FULL_SYNC         - Set to 'true' to sync all files"
            exit 0
            ;;
    esac
done

# Get Open WebUI pod name
get_pod() {
    kubectl get pods -n open-webui -l app.kubernetes.io/name=open-webui -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Helper to call Open WebUI API from within the cluster
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    if [[ -n "$data" ]]; then
        echo "curl -s -X '$method' -H 'Authorization: Bearer $OPEN_WEBUI_API_KEY' -H 'Content-Type: application/json' -d '$data' 'http://localhost:8080$endpoint'" | \
            kubectl exec -i -n open-webui "$POD" -- bash
    else
        echo "curl -s -X '$method' -H 'Authorization: Bearer $OPEN_WEBUI_API_KEY' 'http://localhost:8080$endpoint'" | \
            kubectl exec -i -n open-webui "$POD" -- bash
    fi
}

# Convert path to versioned safe filename
# Example: apps/dashboard/configmap.yaml v1.0.0 -> apps__dashboard__configmap__v1.0.0.yaml
path_to_versioned_name() {
    local path="$1"
    local version="$2"
    local base="${path%.*}"
    local ext="${path##*.}"
    echo "${base}__${version}.${ext}" | sed 's|/|__|g'
}

# Check if file should be excluded
is_excluded() {
    local file="$1"
    case "$file" in
        *sealed-secret*|*.env*|*AGENTS.md*) return 0 ;;
    esac
    case "$(basename "$file")" in
        *sealed-secret*|*.env*|*AGENTS.md*) return 0 ;;
    esac
    return 1
}

# Get the previous tag for comparison
get_previous_tag() {
    # Find the tag before the current one
    git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo ""
}

# Get all files matching sync patterns
get_all_matching_files() {
    cd "$REPO_ROOT" || return 1
    find . -type f \( -name "*.md" -o -name "*.yaml" \) \
        ! -path "./.git/*" \
        ! -name "*sealed-secret*" \
        ! -name "*.env*" \
        ! -name "*AGENTS.md*" \
        | sed 's|^\./||' | sort
}

# Get files changed since previous tag
get_changed_files() {
    local prev_tag="$1"
    cd "$REPO_ROOT" || return 1

    if [[ -z "$prev_tag" ]] || [[ "${FORCE_FULL_SYNC:-}" == "true" ]]; then
        # First release or force sync - sync all files
        log_info "Full sync mode - syncing all matching files" >&2
        get_all_matching_files
    else
        # Get files changed since previous tag
        log_info "Incremental sync - changes since $prev_tag" >&2
        git diff --name-only "$prev_tag" HEAD -- '*.md' '*.yaml' 2>/dev/null | \
            grep -v sealed-secret | grep -v '.env' | grep -v 'AGENTS.md' || true
    fi
}

# Upload a file with versioned name
upload_file() {
    local file_path="$1"
    local versioned_name="$2"

    # Copy file to pod
    kubectl cp "$file_path" "open-webui/$POD:/tmp/sync-file" 2>/dev/null

    # Upload and add to KB inside the pod
    local result
    result=$(cat <<UPLOAD_SCRIPT | kubectl exec -i -n open-webui "$POD" -- bash
RESP=\$(curl -s -X POST -H 'Authorization: Bearer $OPEN_WEBUI_API_KEY' -F "file=@/tmp/sync-file;filename=$versioned_name" http://localhost:8080/api/v1/files/)
FID=\$(echo "\$RESP" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
if [ -n "\$FID" ] && [ "\$FID" != "None" ]; then
    ADD_RESP=\$(curl -s -X POST -H 'Authorization: Bearer $OPEN_WEBUI_API_KEY' -H 'Content-Type: application/json' -d "{\"file_id\":\"\$FID\"}" 'http://localhost:8080/api/v1/knowledge/$OPEN_WEBUI_KNOWLEDGE_ID/file/add')
    if echo "\$ADD_RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);exit(0 if "files" in d else 1)' 2>/dev/null; then
        echo 'OK'
    else
        # Failed to add to KB - delete the orphaned file
        curl -s -X DELETE -H 'Authorization: Bearer $OPEN_WEBUI_API_KEY' "http://localhost:8080/api/v1/files/\$FID" >/dev/null 2>&1
        echo 'FAIL_KB'
    fi
else
    echo 'FAIL_UPLOAD'
fi
rm -f /tmp/sync-file
UPLOAD_SCRIPT
)

    case "$result" in
        OK*)
            log_info "  ✓ Added: $versioned_name"
            return 0
            ;;
        FAIL_KB*)
            log_error "  ✗ KB add failed: $versioned_name"
            return 1
            ;;
        *)
            log_error "  ✗ Upload failed: $versioned_name"
            return 1
            ;;
    esac
}

# Main sync function
sync_to_rag() {
    log_info "Starting RAG sync (tag-based versioning)"
    log_info "Version: $RAG_VERSION"
    log_info "Knowledge base ID: $OPEN_WEBUI_KNOWLEDGE_ID"
    log_info "Repository root: $REPO_ROOT"
    echo ""

    # Get pod
    POD=$(get_pod)
    if [[ -z "$POD" ]]; then
        log_error "Could not find Open WebUI pod"
        exit 1
    fi
    log_info "Using pod: $POD"

    # Get previous tag for comparison
    local prev_tag
    prev_tag=$(get_previous_tag)
    if [[ -n "$prev_tag" ]]; then
        log_info "Previous tag: $prev_tag"
    else
        log_info "No previous tag found (first release)"
    fi
    echo ""

    local uploaded=0
    local skipped=0
    local failed=0
    declare -a FAILED_FILES=()

    log_info "Processing files..."

    cd "$REPO_ROOT" || { log_error "Cannot access repo root"; exit 1; }

    # Process changed files
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Check exclusions
        if is_excluded "$file"; then
            continue
        fi

        local full_path="$REPO_ROOT/$file"

        # Skip if file doesn't exist or is empty
        if [[ ! -f "$full_path" ]] || [[ ! -s "$full_path" ]]; then
            continue
        fi

        # Skip files larger than 500KB
        local size
        size=$(stat -c%s "$full_path" 2>/dev/null || stat -f%z "$full_path" 2>/dev/null || echo "0")
        if [[ "$size" -gt 512000 ]]; then
            log_warn "Skipping $file (${size} bytes > 500KB limit)"
            skipped=$((skipped + 1))
            continue
        fi

        # Generate versioned filename
        local versioned_name
        versioned_name=$(path_to_versioned_name "$file" "$RAG_VERSION")

        log_info "Uploading: $file -> $versioned_name"
        if upload_file "$full_path" "$versioned_name"; then
            uploaded=$((uploaded + 1))
        else
            failed=$((failed + 1))
            FAILED_FILES+=("$file")
        fi

    done < <(get_changed_files "$prev_tag")

    echo ""
    log_info "===== Sync Summary ====="
    log_info "  Version:    $RAG_VERSION"
    log_info "  Uploaded:   $uploaded"
    log_info "  Skipped:    $skipped"
    log_info "  Failed:     $failed"

    if [[ $failed -gt 0 ]]; then
        log_error "Sync failed with $failed failures:"
        for file in "${FAILED_FILES[@]}"; do
            log_error "  - $file"
        done
        exit 1
    fi

    log_info "Sync completed successfully"
}

# Run
sync_to_rag
