-- ============================================================================
-- EcoShop — Patch transversal — INSERT ... RETURNING sur policies
-- auto-référentielles + replis est_direction() manquants
--
-- Contexte : le patch précédent (20260906001502) a trouvé et corrigé le même
-- symptôme sur `encaissements_scolarite`/`inscriptions` (M15quater) — bloque
-- M16 le temps d'auditer les autres tables. Recherche systémique : même
-- forme (policy SELECT basée sur une fonction `xxx_visible(id)` qui
-- re-interroge SA PROPRE table) sur `notifications`, `sanctions`,
-- `evaluations`, `contrats`, `groupes_discussion` ; et même absence de repli
-- `est_direction()` que sur `inscriptions` sur `relations_parent_eleve`.
--
-- IMPORTANT — chaque cas a été vérifié EMPIRIQUEMENT (transaction annulée,
-- INSERT ... RETURNING vs INSERT seul) avant correction, PAS supposé
-- identique par ressemblance de code :
--
--   • notifications (M9)        : RETURNING échouait (42501)  -> corrigé
--   • evaluations (M6)          : RETURNING échouait (42501)  -> corrigé
--   • groupes_discussion (M9p)  : RETURNING échouait (42501)  -> corrigé
--   • sanctions (M7)            : RETURNING réussissait en fait (policy
--                                  SELECT auto-référentielle mais PAS
--                                  cassée, mécanisme non totalement élucidé)
--                                  -> AUCUN correctif de ce type nécessaire ;
--                                  en revanche policy ALL sans repli
--                                  est_direction() (même défaut que
--                                  inscriptions_ecriture_scolarite dans
--                                  20260906001502) -> corrigé séparément
--   • contrats (M8)             : RETURNING réussissait, ET est_rh() inclut
--                                  déjà est_direction() -> AUCUN correctif,
--                                  table saine, gardée telle quelle
--   • relations_parent_eleve    : policy SELECT non auto-référentielle
--     (M5)                        (RETURNING réussit pour un acteur
--                                  autorisé) ; en revanche policy ALL sans
--                                  repli est_direction() -> corrigé
--
-- Ne pas généraliser aveuglément la prochaine fois : la ressemblance de
-- code (fonction `xxx_visible(id)` auto-référentielle) ne prédit PAS de
-- façon fiable si `INSERT ... RETURNING` échoue — `sanctions` et
-- `contrats` prouvent le contraire malgré une forme quasi identique à
-- `encaissement_visible`/`notif_visible`. Vérifier empiriquement, table
-- par table, reste la seule méthode fiable trouvée ce soir.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. notifications (M9) — policy SELECT sous forme inline.
-- ---------------------------------------------------------------------------
drop policy if exists "notifications_select" on public.notifications;
create policy "notifications_select" on public.notifications
  for select using (
    destinataire = auth.uid()
    or public.est_comm(etablissement_id)
  );

-- ---------------------------------------------------------------------------
-- 2. evaluations (M6) — policy SELECT sous forme inline.
-- ---------------------------------------------------------------------------
drop policy if exists "evaluations_select_visible" on public.evaluations;
create policy "evaluations_select_visible" on public.evaluations
  for select using (
    public.est_personnel(etablissement_id)
    or (statut in ('publiee', 'cloturee') and public.classe_visible(classe_id))
  );

-- ---------------------------------------------------------------------------
-- 3. groupes_discussion (M9-patch) — policy SELECT sous forme inline.
-- `classe_visible`/`fiche_visible` non réutilisables tels quels ici (la
-- règle absolue #4 exclut explicitement les relations parentales, et
-- l'appartenance élève doit être vérifiée sur CETTE classe+année précises,
-- pas sur la visibilité générale de la classe) — on réplique fidèlement le
-- corps de `membre_groupe()`, juste sans re-requêter `groupes_discussion`.
-- ---------------------------------------------------------------------------
drop policy if exists "groupes_select_membre" on public.groupes_discussion;
create policy "groupes_select_membre" on public.groupes_discussion
  for select using (
    enseignant_createur_id = auth.uid()
    or public.est_enseignant_affecte(classe_id)
    or exists (
      select 1 from public.inscriptions i
      join public.fiches_eleves f on f.id = i.fiche_eleve_id
      where i.classe_id = groupes_discussion.classe_id
        and i.annee_scolaire_id = groupes_discussion.annee_scolaire_id
        and i.deleted_at is null
        and f.profile_id = auth.uid()
        and f.deleted_at is null
    )
    or public.a_permission(etablissement_id, 'communication.groupe.moderer')
  );

-- ---------------------------------------------------------------------------
-- 4. sanctions (M7) — pas de défaut RETURNING (vérifié), mais même défaut
-- que inscriptions_ecriture_scolarite (20260906001502) : policy ALL sans
-- repli est_direction(), incohérent avec le reste du module (cf. RPC IA de
-- M7 qui vérifient déjà est_direction() en plus de la permission dédiée).
-- ---------------------------------------------------------------------------
drop policy if exists "sanctions_ecriture_scolarite" on public.sanctions;
create policy "sanctions_ecriture_scolarite" on public.sanctions
  for all
  using (
    public.a_permission(etablissement_id, 'scolarite.sanction.gerer')
    or public.est_direction(etablissement_id)
  )
  with check (
    public.a_permission(etablissement_id, 'scolarite.sanction.gerer')
    or public.est_direction(etablissement_id)
  );

-- ---------------------------------------------------------------------------
-- 5. relations_parent_eleve (M5) — même défaut : policy ALL sans repli
-- est_direction().
-- ---------------------------------------------------------------------------
drop policy if exists "relations_scolarite" on public.relations_parent_eleve;
create policy "relations_scolarite" on public.relations_parent_eleve
  for all
  using (
    public.a_permission(etablissement_id, 'scolarite.relation.gerer')
    or public.est_direction(etablissement_id)
  )
  with check (
    public.a_permission(etablissement_id, 'scolarite.relation.gerer')
    or public.est_direction(etablissement_id)
  );
