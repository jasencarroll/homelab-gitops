#!/bin/bash
# Homelab Backup Script
# Run periodically to backup critical components
# Usage: ./scripts/backup-homelab.sh [backup_dir]

set -euo pipefail

BACKUP_DIR="${1:-$HOME/homelab-backups}"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$DATE"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

export KUBECONFIG

mkdir -p "$BACKUP_PATH"

echo "=== Homelab Backup - $DATE ==="
echo "Backup location: $BACKUP_PATH"
echo ""

# 1. Backup .env file (contains all secrets)
echo "[1/5] Backing up .env file..."
if [ -f "/home/jasen/homelab-gitops/.env" ]; then
    cp /home/jasen/homelab-gitops/.env "$BACKUP_PATH/env.backup"
    echo "  ✓ .env backed up"
else
    echo "  ⚠ .env not found"
fi

# 2. Backup sealed-secrets private key (CRITICAL - needed to unseal secrets)
echo "[2/5] Backing up sealed-secrets key..."
if kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o yaml > "$BACKUP_PATH/sealed-secrets-key.yaml" 2>/dev/null; then
    if [ -s "$BACKUP_PATH/sealed-secrets-key.yaml" ]; then
        echo "  ✓ sealed-secrets key backed up"
    else
        rm -f "$BACKUP_PATH/sealed-secrets-key.yaml"
        echo "  ⚠ sealed-secrets not configured"
    fi
else
    echo "  ⚠ sealed-secrets not found"
fi

# 3. Backup Authentik database
echo "[3/5] Backing up Authentik database..."
AUTHENTIK_DB_PASSWORD=$(kubectl get secret -n authentik authentik-db-app -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
if [ -n "$AUTHENTIK_DB_PASSWORD" ]; then
    if kubectl exec -n authentik authentik-db-1 -- sh -c "PGPASSWORD='$AUTHENTIK_DB_PASSWORD' pg_dump -h localhost -U authentik authentik" > "$BACKUP_PATH/authentik-db.sql" 2>/dev/null; then
        LINES=$(wc -l < "$BACKUP_PATH/authentik-db.sql")
        echo "  ✓ Authentik database backed up ($LINES lines)"
    else
        echo "  ⚠ Authentik database backup failed"
    fi
else
    echo "  ⚠ Authentik database password not found"
fi

# 4. Backup Outline database
echo "[4/5] Backing up Outline database..."
OUTLINE_DB_PASSWORD=$(kubectl get secret -n outline outline-db-app -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
if [ -n "$OUTLINE_DB_PASSWORD" ]; then
    if kubectl exec -n outline outline-db-1 -- sh -c "PGPASSWORD='$OUTLINE_DB_PASSWORD' pg_dump -h localhost -U outline outline" > "$BACKUP_PATH/outline-db.sql" 2>/dev/null; then
        LINES=$(wc -l < "$BACKUP_PATH/outline-db.sql")
        echo "  ✓ Outline database backed up ($LINES lines)"
    else
        echo "  ⚠ Outline database backup failed"
    fi
else
    echo "  ⚠ Outline database password not found"
fi

# 5. Export Longhorn volume list and settings
echo "[5/5] Backing up Longhorn configuration..."
kubectl get volumes.longhorn.io -n longhorn-system -o yaml > "$BACKUP_PATH/longhorn-volumes.yaml" 2>/dev/null || true
kubectl get settings.longhorn.io -n longhorn-system -o yaml > "$BACKUP_PATH/longhorn-settings.yaml" 2>/dev/null || true
kubectl get pvc -A -o yaml > "$BACKUP_PATH/all-pvcs.yaml" 2>/dev/null || true
echo "  ✓ Longhorn configuration exported"

# Create a summary
echo ""
echo "=== Backup Complete ==="
echo "Location: $BACKUP_PATH"
echo ""
echo "Files backed up:"
ls -lh "$BACKUP_PATH"

# Calculate total size
TOTAL_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
echo ""
echo "Total backup size: $TOTAL_SIZE"

# Cleanup old backups (keep last 7)
echo ""
echo "Cleaning up old backups (keeping last 7)..."
if [ -d "$BACKUP_DIR" ]; then
    cd "$BACKUP_DIR" && ls -dt */ 2>/dev/null | tail -n +8 | xargs -r rm -rf
fi
echo "Done."

echo ""
echo "=== Backup Tips ==="
echo "1. Copy $BACKUP_PATH to an external location (NAS, cloud, USB)"
echo "2. The .env file contains ALL your secrets - keep it secure!"
echo "3. Run this script before any major changes"
echo "4. Consider setting up a cron job: 0 3 * * * $0"
