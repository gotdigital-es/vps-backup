#!/bin/bash
# =============================================================================
# vps-backup — install.sh
# Instala dependencias, configura rclone y añade entradas al crontab
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║         vps-backup — Instalador      ║"
echo "╚══════════════════════════════════════╝"
echo ""

# === ROOT CHECK ===
if [ "$EUID" -ne 0 ]; then
    echo "[❌] Este script debe ejecutarse como root."
    exit 1
fi

# === VERIFICAR CONFIG ===
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[⚠️] No existe backup.conf. Creando desde el ejemplo..."
    cp "${SCRIPT_DIR}/backup.conf.example" "$CONFIG_FILE"
    echo ""
    echo "[✏️] Edita el fichero de configuración antes de continuar:"
    echo "     nano ${CONFIG_FILE}"
    echo ""
    echo "     Luego vuelve a ejecutar: bash install.sh"
    exit 0
fi

source "$CONFIG_FILE"

echo "[✅] Configuración cargada: SERVER_ID=${SERVER_ID}"
echo ""

# === INSTALAR DEPENDENCIAS ===
install_if_missing() {
    if ! command -v "$1" &> /dev/null; then
        echo "[📦] Instalando $1..."
        apt-get install -y "$2" > /dev/null 2>&1
        echo "[✅] $1 instalado"
    else
        echo "[✅] $1 ya está disponible"
    fi
}

echo "── Verificando dependencias ──────────────"
apt-get update -qq

install_if_missing rsync rsync
install_if_missing tar tar
install_if_missing mysql "default-mysql-client"
install_if_missing mydumper mydumper
install_if_missing mail "mailutils"

# Instalar rclone si no existe
if ! command -v rclone &> /dev/null; then
    echo "[📦] Instalando rclone..."
    curl -fsSL https://rclone.org/install.sh | bash > /dev/null 2>&1
    echo "[✅] rclone instalado"
else
    echo "[✅] rclone ya está disponible ($(rclone --version | head -1))"
fi

echo ""

# === VERIFICAR CONFIGURACIÓN DE RCLONE ===
echo "── Configuración de rclone ───────────────"

if rclone listremotes | grep -q "^${RCLONE_REMOTE}:"; then
    echo "[✅] Remote '${RCLONE_REMOTE}' ya configurado en rclone"
else
    echo "[⚠️] El remote '${RCLONE_REMOTE}' NO está configurado en rclone."
    echo ""
    echo "     Ejecuta el asistente interactivo de rclone:"
    echo "     rclone config"
    echo ""
    echo "     Pasos para Backblaze B2:"
    echo "       n  → New remote"
    echo "       Nombre: ${RCLONE_REMOTE}"
    echo "       Tipo: b2 (Backblaze B2)"
    echo "       Account: tu Account ID de B2"
    echo "       Key: tu Application Key de B2"
    echo ""
    echo "     Una vez configurado, vuelve a ejecutar: bash install.sh"
    exit 1
fi

# Verificar acceso al bucket
echo "[🔍] Verificando acceso al bucket ${B2_BUCKET}..."
if rclone lsd "${RCLONE_REMOTE}:${B2_BUCKET}" > /dev/null 2>&1; then
    echo "[✅] Acceso al bucket confirmado"
else
    echo "[❌] No se puede acceder al bucket '${B2_BUCKET}'."
    echo "     Verifica el nombre del bucket y los permisos de la Application Key."
    exit 1
fi

echo ""

# === PERMISOS DE SCRIPTS ===
echo "── Permisos de scripts ───────────────────"
chmod +x "${SCRIPT_DIR}/scripts/backup-databases.sh"
chmod +x "${SCRIPT_DIR}/scripts/backup-websites.sh"
echo "[✅] Permisos configurados"

# === DIRECTORIO DE BACKUPS ===
echo ""
echo "── Directorios de backup ─────────────────"
mkdir -p "${BACKUP_BASE}/databases" "${BACKUP_BASE}/websites" "${BACKUP_BASE}/logs"
echo "[✅] Directorios creados en ${BACKUP_BASE}"

# === CRONTAB ===
echo ""
echo "── Configuración de crontab ──────────────"

DB_CRON="30 2 * * * ${SCRIPT_DIR}/scripts/backup-databases.sh >> ${BACKUP_BASE}/logs/cron-databases-\$(date +\\%F).log 2>&1"
WEB_CRON="45 3 * * * ${SCRIPT_DIR}/scripts/backup-websites.sh >> ${BACKUP_BASE}/logs/cron-websites-\$(date +\\%F).log 2>&1"

CURRENT_CRONTAB=$(crontab -l 2>/dev/null || true)

UPDATED=0

if echo "$CURRENT_CRONTAB" | grep -q "backup-databases.sh"; then
    echo "[⏭️] Entrada de bases de datos ya existe en crontab, omitiendo"
else
    CURRENT_CRONTAB="${CURRENT_CRONTAB}"$'\n'"${DB_CRON}"
    echo "[✅] Añadida tarea cron: backup-databases.sh (2:30 AM)"
    UPDATED=1
fi

if echo "$CURRENT_CRONTAB" | grep -q "backup-websites.sh"; then
    echo "[⏭️] Entrada de webs ya existe en crontab, omitiendo"
else
    CURRENT_CRONTAB="${CURRENT_CRONTAB}"$'\n'"${WEB_CRON}"
    echo "[✅] Añadida tarea cron: backup-websites.sh (3:45 AM)"
    UPDATED=1
fi

if [ $UPDATED -eq 1 ]; then
    echo "$CURRENT_CRONTAB" | crontab -
    echo "[✅] Crontab actualizado"
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  ✅  Instalación completada correctamente    ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Servidor:   ${SERVER_ID}"
echo "  Bucket:     ${B2_BUCKET}"
echo "  Retención:  BD=${DB_RETENTION_DAYS}d  Webs=${WEB_RETENTION_DAYS}d"
echo "  Logs:       ${BACKUP_BASE}/logs/"
echo ""
echo "  Prueba manual:"
echo "  bash ${SCRIPT_DIR}/scripts/backup-databases.sh"
echo "  bash ${SCRIPT_DIR}/scripts/backup-websites.sh"
echo ""
