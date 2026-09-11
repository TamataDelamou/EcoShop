-- ============================================================================
-- EcoShop — Patch RLS M15quater — bascule boursier (direction) + encaissement
-- (INSERT ... RETURNING)
--
-- Contexte : la toute première exécution locale réelle du test pgTAP 38
-- (`tests/rls/38_m15quater_inscription_encaissement.sql`, 25 assertions) —
-- rendue possible par le déblocage de l'outillage Docker/podman local — a
-- révélé deux défauts jamais détectés jusqu'ici (main local n'a jamais été
-- poussé vers origin, donc jamais passé en CI non plus ; ce module n'avait
-- littéralement jamais tourné) :
--
-- 1. Bascule du statut boursier bloquée pour une direction sans poste RH
--    explicite. La policy UPDATE historique de `inscriptions` (M5,
--    `inscriptions_ecriture_scolarite`) n'autorisait que
--    `a_permission(etablissement_id, 'scolarite.inscription.gerer')`
--    (dépend de `poste_permissions`, donc d'un poste RH configuré) — sans
--    le repli `est_direction(etablissement_id)` que portent pourtant les
--    RPC `creer_inscription_nouvel_eleve`/`creer_reinscription`. Un compte
--    direction sans poste ne pouvait donc pas faire
--    `UPDATE inscriptions SET boursier = ...` (confirmé : `UPDATE 0`, sans
--    erreur, faute silencieuse — `est_direction()` renvoyait pourtant vrai
--    en test isolé).
--
-- 2. `INSERT ... RETURNING` sur `encaissements_scolarite` échouait pour
--    TOUT LE MONDE (direction comprise), avec
--    `new row violates row-level security policy`. Cause racine isolée par
--    test manuel (transaction annulée) : la policy SELECT
--    `encaissements_select_visible` s'appuyait sur `encaissement_visible(id)`,
--    une fonction qui RE-INTERROGE `encaissements_scolarite` par id — cette
--    relecture auto-référentielle ne voit pas la ligne tout juste insérée
--    au moment où Postgres vérifie implicitement la policy SELECT pour
--    construire le résultat de `RETURNING` (comportement reproduit et
--    confirmé : le même INSERT sans `RETURNING` réussit ; remplacer la
--    policy par la forme inline ci-dessous fait réussir `RETURNING`). C'est
--    précisément le chemin de code réel de l'app :
--    `SupabaseScolariteRepository.enregistrerEncaissement()` fait
--    `.insert(...).select().single()` — un vrai encaissement saisi dans
--    l'app aurait échoué de la même façon, pour n'importe quel utilisateur.
--
-- Recherche systémique (même session) : le même anti-pattern (policy SELECT
-- basée sur une fonction `xxx_visible(id)` auto-référentielle) existe aussi sur
-- `notifications`, `sanctions`, `evaluations`, `contrats` (et, non exposé
-- côté client pour l'instant, `groupes_discussion`) — combiné à un
-- `.insert(...).select()` client réel pour les quatre premières. Signalé
-- séparément ; hors périmètre de CE patch (M15quater uniquement), volontai-
-- rement pas corrigé ici sans confirmation explicite du porteur de projet.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Correctif 1 — aligner la policy UPDATE de `inscriptions` sur les RPC
-- (ajout du repli `est_direction`, même principe que les policies
-- `encaissements_insert_gestion`/`encaissements_update_annulation`).
-- ---------------------------------------------------------------------------
drop policy if exists "inscriptions_ecriture_scolarite" on public.inscriptions;
create policy "inscriptions_ecriture_scolarite" on public.inscriptions
  for all
  using (
    public.a_permission(etablissement_id, 'scolarite.inscription.gerer')
    or public.est_direction(etablissement_id)
  )
  with check (
    public.a_permission(etablissement_id, 'scolarite.inscription.gerer')
    or public.est_direction(etablissement_id)
  );

-- ---------------------------------------------------------------------------
-- Correctif 2 — policy SELECT de `encaissements_scolarite` sous forme
-- inline (plus de relecture auto-référentielle de la table), pour que
-- `INSERT ... RETURNING` fonctionne. `encaissement_visible(id)` reste
-- définie (compatible arrière pour un éventuel appel direct existant) mais
-- n'est plus utilisée par cette policy.
-- ---------------------------------------------------------------------------
drop policy if exists "encaissements_select_visible" on public.encaissements_scolarite;
create policy "encaissements_select_visible" on public.encaissements_scolarite
  for select using (
    public.est_personnel(etablissement_id)
    or public.fiche_visible(fiche_eleve_id)
  );
