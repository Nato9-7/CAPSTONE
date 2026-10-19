#!/usr/bin/env bash
# Actualiza la API de RB Alertas cuando hay commits nuevos en origin/main.
# Lo ejecuta cron cada 5 minutos (se instala con "Instalar actualizacion automatica.bat").
# Si la API nueva no responde, vuelve a la imagen anterior y no reintenta ese commit.
set -uo pipefail
# cron trae un PATH mínimo. PATH_EXTRA solo se usa en las pruebas locales.
export PATH="${PATH_EXTRA:+$PATH_EXTRA:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

STACK="${STACK:-$HOME/rbalerta-stack}"
API_DIR="$STACK/api/rb_alertas_api"
RAMA="main"
LOG="$STACK/backups/auto_despliegue.log"
FALLIDO="$STACK/backups/.auto_despliegue_fallido"

log() { printf '%s %s\n' "$(date '+%F %T')" "$1" >> "$LOG"; }

# Evita dos actualizaciones al mismo tiempo (si una construcción tarda más de 5 minutos).
exec 9>"$STACK/backups/.auto_despliegue.lock"
flock -n 9 || exit 0

cd "$API_DIR" || { log "ERROR: no existe $API_DIR"; exit 1; }
git fetch -q origin "$RAMA" >>"$LOG" 2>&1 || { log "ERROR: git fetch falló"; exit 1; }
NUEVO="$(git rev-parse "origin/$RAMA")"
DESPLEGADO="$(grep -E '^API_IMAGE=' "$STACK/.env" | tail -1 | sed -n 's/^API_IMAGE=rbalerta-api:local-//p')"

# Nada que hacer: el código ya está al día y la API corre esa versión (o una sin cambios de API).
if [ "$(git rev-parse HEAD)" = "$NUEVO" ] && [ -n "$DESPLEGADO" ]; then exit 0; fi
# Este commit ya falló antes: se espera uno nuevo en vez de reintentar cada 5 minutos.
if [ -f "$FALLIDO" ] && [ "$(cat "$FALLIDO")" = "$NUEVO" ]; then exit 0; fi

log "Revisando ${NUEVO:0:7} de origin/$RAMA (API desplegada: ${DESPLEGADO:-otra imagen})"
marcar_fallido() { echo "$NUEVO" > "$FALLIDO"; }
[ "$(git rev-parse --abbrev-ref HEAD)" = "$RAMA" ] \
  || { log "ERROR: el servidor no está en la rama $RAMA; no se actualiza"; marcar_fallido; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] \
  || { log "ERROR: hay cambios locales en $API_DIR; no se actualiza"; marcar_fallido; exit 1; }
git merge --ff-only -q "origin/$RAMA" >>"$LOG" 2>&1 \
  || { log "ERROR: no se pudo avanzar a origin/$RAMA"; marcar_fallido; exit 1; }

# Si entre lo desplegado y lo nuevo no cambió nada de la API, no se reinicia.
if [ -n "$DESPLEGADO" ] && git cat-file -e "$DESPLEGADO^{commit}" 2>/dev/null \
   && git diff --quiet "$DESPLEGADO" "$NUEVO" -- .; then
  log "Sin cambios en la API desde ${DESPLEGADO}: no se reinicia"
  rm -f "$FALLIDO"
  exit 0
fi

COMMIT="$(git rev-parse --short HEAD)"
IMAGEN="rbalerta-api:local-$COMMIT"
cd "$STACK" || exit 1
IMAGEN_ANTERIOR="$(grep -E '^API_IMAGE=' .env | tail -1 | cut -d= -f2-)"

fallar() {
  log "ERROR: $1. Se vuelve a ${IMAGEN_ANTERIOR:-la imagen anterior}"
  if [ -n "$IMAGEN_ANTERIOR" ]; then sed -i "s|^API_IMAGE=.*|API_IMAGE=$IMAGEN_ANTERIOR|" .env; fi
  docker compose up -d api >>"$LOG" 2>&1
  marcar_fallido
  exit 1
}

docker build -q -t "$IMAGEN" "$API_DIR" >>"$LOG" 2>&1 || fallar "no se pudo construir la imagen $IMAGEN"
cp -p .env "backups/env.antes_auto_$COMMIT"
if grep -qE '^API_IMAGE=' .env; then
  sed -i "s|^API_IMAGE=.*|API_IMAGE=$IMAGEN|" .env
else
  echo "API_IMAGE=$IMAGEN" >> .env
fi
chmod 600 .env

# La API corre con un usuario sin privilegios: la carpeta de fotos debe ser suya.
USUARIO_APP="$(docker image inspect -f '{{.Config.User}}' "$IMAGEN" 2>/dev/null)"
if [ -n "$USUARIO_APP" ] && grep -q 'uploads_data' docker-compose.yml; then
  docker compose run --rm --no-deps --user 0 --entrypoint sh api \
    -c "mkdir -p /data/uploads/reportes && chown -R '$USUARIO_APP' /data/uploads" >>"$LOG" 2>&1 \
    || fallar "no se pudieron ajustar los permisos de la carpeta de fotos"
fi

docker compose up -d api >>"$LOG" 2>&1 || fallar "no se pudo iniciar la API"
for i in $(seq 1 30); do
  sleep 2
  if curl -fsS -m 5 http://127.0.0.1:8000/api/ping >/dev/null 2>&1 \
     && [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/reportes/categorias)" = 200 ]; then
    rm -f "$FALLIDO"
    log "OK: API actualizada a $COMMIT ($IMAGEN)"
    # Se conservan las 3 imágenes locales más recientes (para poder volver atrás).
    docker images --format '{{.CreatedAt}}|{{.Repository}}:{{.Tag}}' | grep '|rbalerta-api:local-' \
      | sort -r | awk -F'|' 'NR>3 {print $2}' | grep -vx "$IMAGEN" | xargs -r docker rmi >/dev/null 2>&1
    tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    exit 0
  fi
done
fallar "la API nueva no respondió en 60 segundos"
