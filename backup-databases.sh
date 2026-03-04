#!/bin/bash
# =============================================================================
# vps-backup — backup-databases.sh
# Exporta todas las bases de datos MySQL/MariaDB y las sube a Backblaze B2
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
DB_BACKUP_DIR="${BACKUP_BASE}/databases"
DEST_DIR="${DB_BACKUP_DIR}/${TIMESTAMP}"
LOG_DIR="${BACKUP_BASE}/logs"
LOG_FILE="${LOG_DIR}/databases-${TIMESTAMP}.log"
RCLONE_DEST="${RCLONE_REMOTE}:${B2_BUCKET}/${SERVER_ID}/databases/${TIMESTAMP}"
RCLONE_BASE="${RCLONE_REMOTE}:${B2_BUCKET}/${SERVER_ID}/databases"

# === PREPARACIÓN ===
mkdir -p "$DEST_DIR" "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[🕐 $(date)] Iniciando backup de bases de datos — $SERVER_ID"

# Limpieza local (solo se conserva el backup actual)
echo "[🧹 $(date)] Limpiando copias locales anteriores..."
find "$DB_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "$TIMESTAMP" -exec rm -rf {} +

# Verificar dependencias
for cmd in mysql mydumper rclone; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "[❌] Dependencia no encontrada: $cmd"
        exit 1
    fi
done

# Obtener bases de datos válidas
DBS=$(mysql -e "SHOW DATABASES;" -s --skip-column-names | grep -Ev "^(${MYSQL_EXCLUDE})$")

if [ -z "$DBS" ]; then
    echo "[⚠️] No se encontraron bases de datos para exportar."
    exit 1
fi

# === EXPORTACIÓN Y COMPRESIÓN ===
for db in $DBS; do
    echo "[💾 $(date)] Exportando: $db"
    DUMP_DIR="${DEST_DIR}/${db}_dump"
    mkdir -p "$DUMP_DIR"

    mydumper \
        --outputdir="$DUMP_DIR" \
        --compress \
        --threads="$MYSQL_THREADS" \
        --less-locking \
        --verbose 3 \
        --database="$db"

    echo "[🎁 $(date)] Empaquetando $db..."
    tar -czf "${DEST_DIR}/${db}.tar.gz" -C "$DUMP_DIR" .
    rm -rf "$DUMP_DIR"
done

# === SUBIDA A B2 ===
echo "[☁️ $(date)] Subiendo a Backblaze B2..."

rclone copy "$DEST_DIR" "$RCLONE_DEST" --progress

echo "[✅ $(date)] Subida completada: $RCLONE_DEST"

# === ROTACIÓN EN B2 ===
echo "[🔄 $(date)] Rotando backups antiguos en B2 (retención: ${DB_RETENTION_DAYS}d)..."

rclone delete "$RCLONE_BASE" \
    --min-age "${DB_RETENTION_DAYS}d" \
    --log-file "$LOG_FILE" \
    --log-level INFO

rclone rmdirs "$RCLONE_BASE" --leave-root

echo "[🎉 $(date)] Backup de bases de datos finalizado correctamente"
