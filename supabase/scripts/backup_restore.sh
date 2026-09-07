#!/usr/bin/env bash
# ============================================================================
# EcoShop — Sauvegarde / restauration PostgreSQL (reprise après sinistre)
#
# Usage :
#   ./supabase/scripts/backup_restore.sh backup   [répertoire]
#   ./supabase/scripts/backup_restore.sh restore  <fichier.dump>
#   ./supabase/scripts/backup_restore.sh list
#
# Pré-requis : DATABASE_URL (cible) et pg_dump/pg_restore installés.
# Format : dump custom compressé (--format=custom), restauré sans owner.
# ============================================================================
set -euo pipefail

: "${DATABASE_URL:?ERREUR : DATABASE_URL non définie}"
BACKUP_DIR="${BACKUP_DIR:-backups}"

command -v pg_dump   >/dev/null 2>&1 || { echo "ERREUR : pg_dump requis";   exit 1; }
command -v pg_restore >/dev/null 2>&1 || { echo "ERREUR : pg_restore requis"; exit 1; }

ACTION="${1:-backup}"

case "$ACTION" in
  backup)
    mkdir -p "$BACKUP_DIR"
    STAMP="$(date +%Y%m%d_%H%M%S)"
    FILE="$BACKUP_DIR/ecoshop_${STAMP}.dump"
    echo "==> Sauvegarde vers ${FILE}"
    pg_dump "$DATABASE_URL" --format=custom --no-owner --file "$FILE"
    echo "==> Sauvegarde terminée : ${FILE}"
    ;;
  restore)
    FILE="${2:?ERREUR : fichier .dump requis}"
    [ -f "$FILE" ] || { echo "ERREUR : fichier introuvable : ${FILE}"; exit 1; }
    echo "==> Restauration depuis ${FILE}"
    pg_restore "$DATABASE_URL" --clean --if-exists --no-owner --exit-on-error "$FILE"
    echo "==> Restauration terminée. Relancer migrations + seeds + tests."
    ;;
  list)
    ls -lh "$BACKUP_DIR" 2>/dev/null || echo "Aucune sauvegarde dans ${BACKUP_DIR}"
    ;;
  *)
    echo "Usage : $0 [backup|restore <fichier>|list]"
    exit 1
    ;;
esac
