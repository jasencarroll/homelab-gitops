#!/bin/bash
# sync-outline.sh - Sync markdown docs to Outline wiki
#
# Hash-based smart sync: Documents are only updated if their content has changed.
# Compares SHA256 hash of local content against stored hashes in state file.
#
# Required environment variables:
#   OUTLINE_API_TOKEN - API token from Outline Settings
#
# Optional environment variables:
#   OUTLINE_API_URL - Base API URL (default: https://docs.lab.axiomlayer.com/api)
#   FORCE_FULL_SYNC - Set to "true" to sync all files regardless of changes

set -euo pipefail

# Configuration
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG_FILE="$REPO_ROOT/outline_sync/config.json"
STATE_FILE="$REPO_ROOT/outline_sync/state.json"
OUTLINE_API_URL="${OUTLINE_API_URL:-https://docs.lab.axiomlayer.com/api}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_skip() { echo -e "${BLUE}[SKIP]${NC} $1"; }

# Check required tools and environment
check_requirements() {
    local missing=0

    # Accept either OUTLINE_API_TOKEN (CI) or OUTLINE_API_KEY (local .env)
    OUTLINE_API_TOKEN="${OUTLINE_API_TOKEN:-${OUTLINE_API_KEY:-}}"

    if [[ -z "${OUTLINE_API_TOKEN:-}" ]]; then
        log_error "OUTLINE_API_TOKEN (or OUTLINE_API_KEY) is not set"
        missing=1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        missing=1
    fi

    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        missing=1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        echo ""
        echo "Required environment variables:"
        echo "  OUTLINE_API_TOKEN - API token from Outline Settings"
        echo ""
        echo "Optional:"
        echo "  OUTLINE_API_URL   - Base API URL (default: https://docs.lab.axiomlayer.com/api)"
        echo "  FORCE_FULL_SYNC   - Set to 'true' to sync all files"
        exit 1
    fi
}

# Make an API request to Outline
outline_api() {
    local endpoint="$1"
    local payload="$2"

    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OUTLINE_API_TOKEN" \
        -d "$payload" \
        "${OUTLINE_API_URL}/${endpoint}" 2>&1)

    # Check for errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        local error
        error=$(echo "$response" | jq -r '.error // .message // "Unknown error"')
        log_error "API error ($endpoint): $error"
        return 1
    fi

    echo "$response"
}

# Compute SHA256 hash of content
compute_hash() {
    echo -n "$1" | sha256sum | cut -d' ' -f1
}

# Get or create collection ID
get_collection_id() {
    # Check state file first
    if [[ -f "$STATE_FILE" ]]; then
        local collection_id
        collection_id=$(jq -r '.collectionId // empty' "$STATE_FILE" 2>/dev/null)
        if [[ -n "$collection_id" ]]; then
            echo "$collection_id"
            return 0
        fi
    fi

    # Create new collection
    local collection_name
    collection_name=$(jq -r '.collectionName' "$CONFIG_FILE")
    log_info "Creating Outline collection '$collection_name'..."

    local response
    response=$(outline_api "collections.create" "{\"name\": \"$collection_name\"}")

    local collection_id
    collection_id=$(echo "$response" | jq -r '.data.id // empty')

    if [[ -z "$collection_id" ]]; then
        log_error "Failed to create collection"
        return 1
    fi

    # Save to state
    if [[ -f "$STATE_FILE" ]]; then
        local tmp
        tmp=$(mktemp)
        jq --arg id "$collection_id" '.collectionId = $id' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    else
        echo "{\"collectionId\": \"$collection_id\", \"documents\": {}}" > "$STATE_FILE"
    fi

    echo "$collection_id"
}

# Get document info from state (id and hash)
get_document_info() {
    local path="$1"

    if [[ -f "$STATE_FILE" ]]; then
        jq -r --arg path "$path" '.documents[$path] | "\(.id // "")\t\(.hash // "")"' "$STATE_FILE" 2>/dev/null
    fi
}

# Save document info to state (id and hash)
save_document_info() {
    local path="$1"
    local doc_id="$2"
    local hash="$3"

    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"documents": {}}' > "$STATE_FILE"
    fi

    local tmp
    tmp=$(mktemp)
    jq --arg path "$path" --arg id "$doc_id" --arg hash "$hash" \
        '.documents[$path] = {"id": $id, "hash": $hash}' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# Convert file path to title
path_to_title() {
    local path="$1"
    local name
    name=$(basename "$path" .md)

    # Replace dashes and underscores with spaces, then title case
    echo "$name" | sed 's/[-_]/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1'
}

# Get title for a document from config or generate from path
get_doc_title() {
    local path="$1"

    # Check config for explicit title
    local title
    title=$(jq -r --arg path "$path" '.documents[] | select(.path == $path) | .title // empty' "$CONFIG_FILE" 2>/dev/null)

    if [[ -n "$title" ]]; then
        echo "$title"
    else
        path_to_title "$path"
    fi
}

# Escape content for JSON
escape_json() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || \
    jq -Rs '.' 2>/dev/null
}

# Sync a single document
sync_document() {
    local path="$1"
    local collection_id="$2"

    local full_path="$REPO_ROOT/$path"

    if [[ ! -f "$full_path" ]]; then
        log_warn "Skipping '$path' (file not found)"
        return 0
    fi

    local title
    title=$(get_doc_title "$path")

    local content
    content=$(cat "$full_path")

    # Compute hash of local content
    local local_hash
    local_hash=$(compute_hash "$content")

    # Get stored document info
    local doc_info
    doc_info=$(get_document_info "$path")
    local doc_id stored_hash
    doc_id=$(echo "$doc_info" | cut -f1)
    stored_hash=$(echo "$doc_info" | cut -f2)

    # Check if content has changed
    if [[ -n "$doc_id" ]] && [[ "$stored_hash" == "$local_hash" ]] && [[ "${FORCE_FULL_SYNC:-}" != "true" ]]; then
        log_skip "$title (unchanged)"
        return 0
    fi

    # Escape content for JSON
    local escaped_content
    escaped_content=$(echo "$content" | escape_json)

    if [[ -n "$doc_id" ]]; then
        # Update existing document
        log_info "Updating '$title' (content changed)..."

        local payload
        payload=$(jq -n \
            --arg id "$doc_id" \
            --arg title "$title" \
            --argjson text "$escaped_content" \
            '{id: $id, title: $title, text: $text, publish: true}')

        local response
        response=$(outline_api "documents.update" "$payload")

        if echo "$response" | jq -e '.data.id' > /dev/null 2>&1; then
            save_document_info "$path" "$doc_id" "$local_hash"
            log_info "  ✓ Updated"
            return 0
        else
            log_error "  Failed to update"
            return 1
        fi
    else
        # Create new document
        log_info "Creating '$title' (new document)..."

        local payload
        payload=$(jq -n \
            --arg collection_id "$collection_id" \
            --arg title "$title" \
            --argjson text "$escaped_content" \
            '{collectionId: $collection_id, title: $title, text: $text, publish: true}')

        local response
        response=$(outline_api "documents.create" "$payload")

        local new_id
        new_id=$(echo "$response" | jq -r '.data.id // empty')

        if [[ -n "$new_id" ]]; then
            save_document_info "$path" "$new_id" "$local_hash"
            log_info "  ✓ Created (ID: ${new_id:0:8}...)"
            return 0
        else
            log_error "  Failed to create"
            return 1
        fi
    fi
}

# Get list of docs to sync from config
get_configured_docs() {
    jq -r '.documents[].path' "$CONFIG_FILE" 2>/dev/null
}

# Main sync function
sync_to_outline() {
    log_info "Starting Outline sync (hash-based smart sync)"
    log_info "API URL: $OUTLINE_API_URL"
    log_info "Repository root: $REPO_ROOT"
    echo ""

    # Get collection ID
    local collection_id
    collection_id=$(get_collection_id)
    log_info "Collection ID: $collection_id"
    echo ""

    local synced=0
    local unchanged=0
    local failed=0

    # Process all configured documents
    while IFS= read -r doc; do
        [[ -z "$doc" ]] && continue

        local full_path="$REPO_ROOT/$doc"
        if [[ ! -f "$full_path" ]]; then
            log_warn "Skipping '$doc' (file not found)"
            continue
        fi

        # Get stored hash
        local doc_info
        doc_info=$(get_document_info "$doc")
        local doc_id stored_hash
        doc_id=$(echo "$doc_info" | cut -f1)
        stored_hash=$(echo "$doc_info" | cut -f2)

        # Compute local hash
        local content local_hash
        content=$(cat "$full_path")
        local_hash=$(compute_hash "$content")

        # Check if unchanged
        if [[ -n "$doc_id" ]] && [[ "$stored_hash" == "$local_hash" ]] && [[ "${FORCE_FULL_SYNC:-}" != "true" ]]; then
            local title
            title=$(get_doc_title "$doc")
            log_skip "$title (unchanged)"
            unchanged=$((unchanged + 1))
            continue
        fi

        # Sync document
        if sync_document "$doc" "$collection_id"; then
            synced=$((synced + 1))
        else
            failed=$((failed + 1))
        fi
    done < <(get_configured_docs)

    echo ""
    log_info "===== Sync Summary ====="
    log_info "  Unchanged: $unchanged (skipped)"
    log_info "  Synced:    $synced"
    log_info "  Failed:    $failed"

    if [[ $failed -gt 0 ]]; then
        log_warn "Sync completed with errors"
        exit 1
    fi

    if [[ $unchanged -gt 0 ]] && [[ $synced -eq 0 ]]; then
        log_info "All documents unchanged - nothing to sync!"
    fi

    log_info "Sync completed successfully"
}

# Run
check_requirements
sync_to_outline
