#!/bin/bash
# =============================================================================
# vps-backup — backup-websites.sh
# Comprime los vhosts y los sube a Backblaze B2
# =============================================================================

set -euo pipefail

# === CARGAR CONFIGURACIÓN ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../backup.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[❌] No se encuentra backup.conf en $(dirname "$CONFIG_FILE")"
    echo "     Copia backup.conf.example como backup.conf y configúralo."
    exit 1
fi

source "$CONFIG_FILE"

# === VARIABLES DERIVADAS ===
TIMESTAMP=$(date +%Y%m%d-%H%M)
WEB_BACKUP_DIR="${BACKUP_BASE}/websites"
TMP_DIR="${WEB_BACKUP_DIR}/${TIMESTAMP}"
LOG_DIR="${BACKUP_BASE}/logs"
LOG_FILE="${LOG_DIR}/websites-${TIMESTAMP}.log"
RCLONE_DEST="${RCLONE_REMOTE}:${B2_BUCKET}/${SERVER_ID}/websites/${TIMESTAMP}"
RCLONE_BASE="${RCLONE_REMOTE}:${B2_BUCKET}/${SERVER_ID}/websites"

# === PREPARACIÓN ===
mkdir -p "$TMP_DIR" "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[🚀 $(date)] Iniciando backup de webs — $SERVER_ID ($(hostname))"

# Verificar dependencias
for cmd in rsync tar rclone; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "[❌] Dependencia no encontrada: $cmd"
        exit 1
    fi
done

# Limpieza local (solo se conserva el backup actual)
echo "[🧹 $(date)] Limpiando backups locales antiguos..."
find "$WEB_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "$TIMESTAMP" -exec rm -rf {} +

# Obtener lista de dominios válidos
if [ ! -d "$VHOSTS_DIR" ]; then
    echo "[❌] No se encuentra el directorio de vhosts: $VHOSTS_DIR"
    exit 1
fi

DOMAINS=$(ls -1 "$VHOSTS_DIR" | grep -Ev "^(${VHOSTS_EXCLUDE})$")

if [ -z "$DOMAINS" ]; then
    echo "[⚠️] No se encontraron dominios en $VHOSTS_DIR"
    exit 1
fi

# === COMPRESIÓN POR DOMINIO ===
for DOMAIN in $DOMAINS; do
    echo "[🧊 $(date)] Sincronizando $DOMAIN..."
    RSYNC_DIR="/tmp/backup_${DOMAIN}"
    rm -rf "$RSYNC_DIR"
    rsync -a --delete "${VHOSTS_DIR}/${DOMAIN}/" "$RSYNC_DIR/"

    echo "[📦 $(date)] Empaquetando $DOMAIN..."
    tar -czf "${TMP_DIR}/${DOMAIN}.tar.gz" -C "$RSYNC_DIR" .

    echo "[🧹 $(date)] Limpiando temporal de $DOMAIN..."
    rm -rf "$RSYNC_DIR"
done

# === SUBIDA A B2 ===
echo "[☁️ $(date)] Subiendo a Backblaze B2..."

rclone copy "$TMP_DIR" "$RCLONE_DEST" --progress

echo "[✅ $(date)] Subida completada: $RCLONE_DEST"

# === ROTACIÓN EN B2 ===
echo "[🔄 $(date)] Rotando backups antiguos en B2 (retención: ${WEB_RETENTION_DAYS}d)..."

rclone delete "$RCLONE_BASE" \
    --min-age "${WEB_RETENTION_DAYS}d" \
    --log-file "$LOG_FILE" \
    --log-level INFO

rclone rmdirs "$RCLONE_BASE" --leave-root

echo "[🎉 $(date)] Backup de webs finalizado correctamente"
