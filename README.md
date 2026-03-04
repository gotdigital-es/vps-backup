# vps-backup

Scripts de backup automatizado para VPS Linux hacia **Backblaze B2**, con rotación configurable. Diseñado para entornos **Plesk** con múltiples dominios y bases de datos MySQL/MariaDB.

## Qué hace

- **Bases de datos**: exporta con `mydumper`, comprime por base de datos y sube a B2. Retención configurable (por defecto 30 días).
- **Webs**: comprime cada vhost de `/var/www/vhosts` y sube a B2. Retención configurable (por defecto 7 días).
- **Rotación automática**: borra en B2 los backups más antiguos que el período de retención configurado.
- **Notificaciones por email** en caso de error.

## Estructura en B2

```
Mi-Bucket-Backups/
└── mi_servidor/
    ├── databases/
    │   ├── 20260304-0230/
    │   │   ├── wordpress_db.tar.gz
    │   │   └── tienda_db.tar.gz
    │   └── 20260305-0230/
    └── websites/
        ├── 20260304-0345/
        │   ├── dominio1.com.tar.gz
        │   └── dominio2.es.tar.gz
        └── 20260305-0345/
```

## Instalación rápida

```bash
# 1. Clonar el repositorio
git clone https://github.com/tuusuario/vps-backup.git /root/vps-backup
cd /root/vps-backup

# 2. Crear y editar la configuración
cp backup.conf.example backup.conf
nano backup.conf

# 3. Ejecutar el instalador
bash install.sh
```

El instalador:
- Verifica e instala las dependencias necesarias (`rclone`, `mydumper`, `rsync`, `mailutils`)
- Valida que el remote de rclone y el bucket de B2 sean accesibles
- Configura las tareas en el crontab automáticamente

## Configuración manual de rclone (si es la primera vez)

Antes de ejecutar `install.sh`, configura el remote de Backblaze B2 en rclone:

```bash
rclone config
```

Pasos en el asistente:
1. `n` → New remote
2. **Nombre**: el mismo valor que pongas en `RCLONE_REMOTE` del `.conf`
3. **Tipo**: `b2` (Backblaze B2)
4. **Account**: tu Account ID de B2 (en *Application Keys*)
5. **Key**: tu Application Key de B2
6. Resto de opciones: Enter para dejar por defecto

Verifica que funciona:
```bash
rclone lsd b2NombreRemoto:Mi-Bucket-Backups
```

## Parámetros de backup.conf

| Variable | Descripción | Ejemplo |
|---|---|---|
| `SERVER_ID` | Nombre único del VPS | `gotdigital_vps` |
| `EMAIL` | Email para alertas de error | `admin@ejemplo.com` |
| `RCLONE_REMOTE` | Nombre del remote en rclone | `b2Bucket_Gotdigital` |
| `B2_BUCKET` | Nombre del bucket en B2 | `GotDigital-Backups` |
| `DB_RETENTION_DAYS` | Días de retención para bases de datos | `30` |
| `WEB_RETENTION_DAYS` | Días de retención para webs | `7` |
| `MYSQL_THREADS` | Hilos para mydumper | `4` |
| `MYSQL_EXCLUDE` | Bases de datos a excluir (regex) | `mysql\|sys\|...` |
| `VHOSTS_DIR` | Ruta al directorio de vhosts | `/var/www/vhosts` |
| `VHOSTS_EXCLUDE` | Carpetas a ignorar en vhosts (regex) | `chroot\|default\|system` |
| `BACKUP_BASE` | Directorio base para backups locales | `/root/backups` |

## Ejecución manual

```bash
bash /root/vps-backup/scripts/backup-databases.sh
bash /root/vps-backup/scripts/backup-websites.sh
```

## Crontab resultante

```
30 2 * * * /root/vps-backup/scripts/backup-databases.sh >> /root/backups/logs/cron-databases-$(date +\%F).log 2>&1
45 3 * * * /root/vps-backup/scripts/backup-websites.sh >> /root/backups/logs/cron-websites-$(date +\%F).log 2>&1
```

## Desplegar en un segundo VPS

```bash
git clone https://github.com/tuusuario/vps-backup.git /root/vps-backup
cd /root/vps-backup
cp backup.conf.example backup.conf
nano backup.conf   # cambia SERVER_ID y ajusta retenciones
bash install.sh
```

## Requisitos

- Ubuntu / Debian
- MySQL o MariaDB
- Plesk (o cualquier estructura con vhosts en `/var/www/vhosts`)
- Acceso root

Las dependencias (`rclone`, `mydumper`, `rsync`, `mailutils`) se instalan automáticamente con `install.sh`.

## Logs

Los logs se guardan en `BACKUP_BASE/logs/`:
- `databases-YYYYMMDD-HHMM.log` — log detallado de cada ejecución
- `websites-YYYYMMDD-HHMM.log`
- `cron-databases-YYYY-MM-DD.log` — salida del cron
- `cron-websites-YYYY-MM-DD.log`
