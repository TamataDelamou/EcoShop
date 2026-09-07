#!/usr/bin/env bash
# ============================================================================
# EcoShop — Déploiement continu (staging → production)
#
# Usage :
#   ./supabase/scripts/deploy.sh [staging|production]
#
# Pré-requis :
#   - CLI Supabase (supabase) et psql installés
#   - Variables d'environnement :
#       SUPABASE_PROJECT_REF : identifiant du projet cible (supabase link)
#       DATABASE_URL         : chaîne de connexion PostgreSQL cible
#
# Étapes (idempotentes, reprise possible après coupure réseau) :
#   1. Pré-requis outils
#   2. Liaison du projet Supabase
#   3. Application des migrations (db push)
#   4. Application des seeds complémentaires M4→M11
#   5. Tests pgTAP (01→27)
#   6. Audit de cohérence inter-modules
# ============================================================================
set -euo pipefail

ENV_TARGET="${1:-staging}"

echo "==> Déploiement EcoShop — cible : ${ENV_TARGET}"

# 1. Pré-requis
command -v supabase >/dev/null 2>&1 || { echo "ERREUR : supabase CLI requis"; exit 1; }
command -v psql     >/dev/null 2>&1 || { echo "ERREUR : psql requis";     exit 1; }
command -v pg_prove >/dev/null 2>&1 || { echo "ERREUR : pg_prove requis"; exit 1; }

: "${DATABASE_URL:?ERREUR : DATABASE_URL non définie}"

# 2. Liaison du projet (requis pour les fonctions/branches de migration)
if [ -n "${SUPABASE_PROJECT_REF:-}" ]; then
  supabase link --project-ref "${SUPABASE_PROJECT_REF}"
fi

# 3. Migrations (M0→M12, ordonnées par horodatage)
echo "==> Application des migrations"
supabase db push

# 4. Seeds complémentaires (M4→M11) — idempotents
echo "==> Application des seeds"
for f in \
  supabase/seed_referentiel_pedagogique.sql \
  supabase/seed_administration_scolarite.sql \
  supabase/seed_notes_evaluations.sql \
  supabase/seed_vie_scolaire.sql \
  supabase/seed_rh_personnel.sql \
  supabase/seed_communication_notifications.sql \
  supabase/seed_rapports_statistiques.sql \
  supabase/seed_planification_agenda.sql; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"
done

# 5. Tests pgTAP (RLS 01→27)
echo "==> Tests pgTAP"
pg_prove -d "$DATABASE_URL" tests/rls/*.sql

# 6. Audit de cohérence inter-modules
echo "==> Audit de cohérence"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/integration/audit_coherence.sql

echo "==> Déploiement ${ENV_TARGET} terminé (GO)."
