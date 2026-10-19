# RB Alertas — Runbook de operación del stack Docker

Documento de operación del stack contenerizado en el VPS Oracle Cloud (ARM / Ubuntu 20.04).
Última actualización: 13 de septiembre de 2026.

---

## 1. Arquitectura

| Servicio | Imagen                                   | Exposición                    | Rol                                                   |
| -------- | ---------------------------------------- | ----------------------------- | ----------------------------------------------------- |
| `db`     | `mysql:8.0` (oficial, multiarquitectura) | `127.0.0.1:3307` (solo local) | Base de datos `rbalerta_db`                           |
| `api`    | `ghcr.io/nato9-7/rbalerta-api:<versión>` | Interna (sin publicar)        | API FastAPI                                           |
| `caddy`  | `caddy:2-alpine`                         | `80`, `443`                   | Proxy inverso + HTTPS. **Activo** desde el 03/10/2026 |

La API alcanza la base por el nombre `db` dentro de la red interna de Docker. El puerto 3306 **no está
expuesto a internet**.

### Ubicaciones

| Elemento                | Ruta                                                             |
| ----------------------- | ---------------------------------------------------------------- |
| Stack                   | `~/rbalerta-stack/`                                              |
| Credenciales            | `~/rbalerta-stack/.env` (permisos 600, no versionar)             |
| Respaldos               | `~/rbalerta-stack/backups/`                                      |
| Script de respaldo      | `~/rbalerta-stack/scripts/backup.sh`                             |
| Código fuente de la API | `~/rbalerta-stack/api/rb_alertas_api/`                           |
| Override de desarrollo  | `~/rbalerta-stack/docker-compose.override.yml.dev` (desactivado) |
| Registry de imágenes    | `ghcr.io/nato9-7/rbalerta-api`                                   |

### Servicios nativos (desactivados, conservados como respaldo)

- `rbalertas-api.service` — deshabilitado
- `mysql.service` — deshabilitado; datos intactos en `/var/lib/mysql`

---

## 2. Operación diaria

```bash
cd ~/rbalerta-stack

docker compose ps                    # estado de los servicios
docker compose logs -f api           # logs en vivo de la API
docker compose logs --tail=50 db     # logs de la base
docker compose restart api           # reiniciar solo la API
docker compose up -d                 # aplicar cambios de configuración
docker compose down                  # detener (SIN borrar datos)
```

### Acceso a la base de datos

```bash
cd ~/rbalerta-stack
docker compose exec db sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" rbalerta_db'
```

Desde un cliente gráfico en el PC, vía túnel SSH:

```bash
ssh -i clave.pem -L 3307:127.0.0.1:3307 ubuntu@IP_DEL_VPS
# luego conectar el cliente a 127.0.0.1:3307
```

> **Nunca** ejecutar `docker compose down -v` en producción: la bandera `-v` destruye el volumen
> de datos.

---

## 3. Desplegar una nueva versión de la API

```bash
# 1. Traer los cambios
cd ~/rbalerta-stack/api/rb_alertas_api
git pull

# 2. Construir y publicar para ambas arquitecturas
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/nato9-7/rbalerta-api:X.Y.Z \
  -t ghcr.io/nato9-7/rbalerta-api:latest \
  --push .

# 3. Apuntar el stack a la nueva versión
sed -i 's|^API_IMAGE=.*|API_IMAGE=ghcr.io/nato9-7/rbalerta-api:X.Y.Z|' ~/rbalerta-stack/.env

# 4. Desplegar
cd ~/rbalerta-stack && docker compose up -d
```

**Rollback:** cambiar `API_IMAGE` a la versión anterior y repetir el paso 4. Cada versión queda
inmutable en el registry.

Requisitos previos: `docker login ghcr.io -u Nato9-7` con un token de `write:packages`, y tener
activo el builder multiarquitectura (`docker buildx use multiarch`).

---

## 4. Respaldos

Un cron diario ejecuta `scripts/backup.sh` a las 03:15. El script valida cada dump y descarta
los truncados o vacíos. Retención: 14 días.

```bash
~/rbalerta-stack/scripts/backup.sh      # respaldo manual
ls -lht ~/rbalerta-stack/backups/       # historial
tail -20 ~/rbalerta-stack/backups/backup.log
crontab -l                              # verificar programación
```

### Generar el paquete portable

```bash
cd ~/rbalerta-stack && ./scripts/backup.sh
rm -f db/init/*.sql
zcat "$(ls -t backups/rbalerta_db_*.sql.gz | head -1)" > db/init/01-rbalerta_db.sql

cd ~ && rm -f rbalerta-stack_*.tar.gz
tar czf rbalerta-stack_$(date +%F).tar.gz \
  rbalerta-stack/docker-compose.yml rbalerta-stack/.env \
  rbalerta-stack/.env.example rbalerta-stack/.gitignore \
  rbalerta-stack/caddy rbalerta-stack/scripts rbalerta-stack/db \
  rbalerta-stack/backups/rbalerta_db_*.sql.gz
```

Descargarlo al PC (ejecutar **en el PC**, no en el VPS):

```bash
scp -i clave.pem ubuntu@IP_DEL_VPS:~/rbalerta-stack_*.tar.gz ~/Descargas/
```

> El `.tar.gz` contiene el `.env` con credenciales en texto plano. Tratar como material sensible:
> no subir a repositorios ni a almacenamiento compartido sin cifrar.

---

## 5. Recuperación total en un servidor nuevo

Funciona en cualquier arquitectura (ARM o x86): las imágenes son multiarquitectura.

```bash
# 1. Instalar Docker (repositorio oficial)
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
# cerrar sesión y volver a entrar

# 2. Desplegar
tar xzf rbalerta-stack_FECHA.tar.gz && cd rbalerta-stack
rm -f db/init/*.sql
zcat "$(ls -t backups/rbalerta_db_*.sql.gz | head -1)" > db/init/01-rbalerta_db.sql
docker compose up -d

# 3. Verificar
docker compose ps
curl -s http://127.0.0.1:8000/api/ping
```

Si el paquete de GHCR es privado, antes del paso 2:
`docker login ghcr.io -u Nato9-7` con un token de `read:packages`.

### Probar la restauración sin afectar producción

```bash
mkdir -p /tmp/restore-test && cd /tmp/restore-test
tar xzf ~/rbalerta-stack_*.tar.gz && cd rbalerta-stack
cat > docker-compose.override.yml <<'EOF'
services:
  db:
    ports: !override
      - "127.0.0.1:3309:3306"
  api:
    ports: !override
      - "127.0.0.1:8002:8000"
EOF
docker compose -p restoretest up -d
curl -s http://127.0.0.1:8002/api/ping

# limpieza
docker compose -p restoretest down -v && rm -rf /tmp/restore-test
```

El `-p restoretest` aísla contenedores, red y volúmenes. Conviene repetir esta prueba al menos
una vez al mes.

---

## 6. Marcha atrás a la instalación nativa

Los servicios originales siguen instalados. En caso de emergencia:

```bash
cd ~/rbalerta-stack && docker compose down
sudo systemctl start mysql
sudo systemctl start rbalertas-api
```

Los datos nativos en `/var/lib/mysql` están congelados desde el cambio del 13/09/2026: cualquier
escritura posterior vive solo en el volumen Docker.

---

### HTTPS (activo)

Procedimiento completo, diagnóstico y estado en `Documentacion_https_duckdns_caddy.md`.

Operación diaria del proxy:

```bash
cd ~/rbalerta-stack
docker compose --profile proxy up -d       # levantar incluyendo caddy
docker compose logs -f caddy               # certificados y tráfico
```

> **Importante:** toda invocación de `docker compose up` sobre este stack debe incluir
> `--profile proxy`. Sin esa bandera, y especialmente si se combina con `--remove-orphans`,
> el contenedor de Caddy puede quedar fuera y la API dejaría de ser accesible.

Caddy renueva el certificado Let's Encrypt automáticamente. Requiere los puertos 80 y 443
abiertos **tanto en la Security List de la subred como en el NSG** de la VNIC.
