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

## Requisitos previos

Antes de ejecutar `install.sh` es necesario preparar Backblaze B2 y configurar rclone en el VPS.

### 1. Crear bucket y API key en Backblaze B2

1. Accede a [backblaze.com](https://backblaze.com) y ve a **B2 Cloud Storage → Buckets**
2. Crea un bucket privado (por ejemplo: `MiServidor-Backups`)
   - Type: **Private**
   - Default Encryption: **Enable** (recomendado)
   - Object Lock: **Disable**
3. Ve a **Account → Application Keys → Add a New Application Key**
   - Limita el acceso al bucket recién creado
   - Anota el **keyID** y el **applicationKey** (solo se muestran una vez)

### 2. Configurar rclone en el VPS
```bash
rclone config
```

Pasos en el asistente:
1. `n` → New remote
2. **Nombre**: el mismo valor que pondrás en `RCLONE_REMOTE` del `.conf` (ej: `b2MiServidor`)
3. **Tipo**: `b2` (Backblaze B2)
4. **Account**: tu keyID de B2
5. **Key**: tu applicationKey de B2
6. Resto de opciones: Enter para dejar por defecto

Verifica que el acceso funciona antes de continuar:
```bash
rclone lsd b2MiServidor:MiServidor-Backups
```

Si el comando devuelve el contenido del bucket (vacío o no) sin error, está listo.

## Instalación rápida
```bash
# 1. Clonar el repositorio
git clone https://github.com/gotdigital-es/vps-backup.git /root/vps-backup
cd /root/vps-backup

# 2. Editar la configuración
nano backup.conf

# 3. Ejecutar el instalador
bash install.sh
```

El instalador:
- Verifica e instala las dependencias necesarias (`rclone`, `mydumper`, `rsync`, `mailutils`)
- Valida que el remote de rclone y el bucket de B2 sean accesibles
- Configura las tareas en el crontab automáticamente

## Parámetros de backup.conf

| Variable | Descripción | Ejemplo |
|---|---|---|
| `SERVER_ID` | Nombre único del VPS | `gotdigital_vps` |
| `EMAIL` | Email para alertas de error | `admin@ejemplo.com` |
| `RCLONE_REMOTE` | Nombre del remote en rclone | `b2MiServidor` |
| `B2_BUCKET` | Nombre del bucket en B2 | `MiServidor-Backups` |
| `DB_RETENTION_DAYS` | Días de retención para bases de datos | `30` |
| `WEB_RETENTION_DAYS` | Días de retención para webs | `7` |
| `MYSQL_THREADS` | Hilos para mydumper | `4` |
| `MYSQL_EXCLUDE` | Bases de datos a excluir (regex) | `mysql\|sys\|...` |
| `VHOSTS_DIR` | Ruta al directorio de vhosts | `/var/www/vhosts` |
| `VHOSTS_EXCLUDE` | Carpetas a ignorar en vhosts (regex) | `chroot\|default\|system` |
| `BACKUP_BASE` | Directorio base para backups locales | `/root/backups` |

## Ejecución manual
```bash
bash /root/vps-backup/backup-databases.sh
bash /root/vps-backup/backup-websites.sh
```

## Crontab resultante
```
30 2 * * * /root/vps-backup/backup-databases.sh >> /root/backups/logs/cron-databases-$(date +\%F).log 2>&1
45 3 * * * /root/vps-backup/backup-websites.sh >> /root/backups/logs/cron-websites-$(date +\%F).log 2>&1
```

## Desplegar en un segundo VPS
```bash
# 1. Configurar Backblaze y rclone (ver Requisitos previos)

# 2. Clonar e instalar
git clone https://github.com/gotdigital-es/vps-backup.git /root/vps-backup
cd /root/vps-backup
nano backup.conf   # cambia SERVER_ID y ajusta retenciones
bash install.sh
```

## Requisitos del sistema

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
