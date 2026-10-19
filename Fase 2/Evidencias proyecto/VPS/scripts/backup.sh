#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$STACK_DIR"

STAMP=$(date +%F_%H%M)
OUT="backups/rbalerta_db_${STAMP}.sql.gz"
RETENTION_DAYS=14

docker compose exec -T db sh -c \
  'exec mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
     --databases "$MYSQL_DATABASE" \
     --single-transaction --routines --triggers --events \
     --set-gtid-purged=OFF --default-character-set=utf8mb4' \
  2>/dev/null | gzip -9 > "$OUT"

if [ ! -s "$OUT" ] || ! gzip -t "$OUT" 2>/dev/null; then
  echo "ERROR: respaldo invalido, se descarta: $OUT" >&2
  rm -f "$OUT"
  exit 1
fi

if ! zcat "$OUT" | tail -2 | grep -q "Dump completed"; then
  echo "ERROR: respaldo truncado, se descarta: $OUT" >&2
  rm -f "$OUT"
  exit 1
fi

find backups -name 'rbalerta_db_*.sql.gz' -mtime +$RETENTION_DAYS -delete
echo "OK $(date -Is) $OUT ($(du -h "$OUT" | cut -f1))"
