-- ============================================================================
-- EcoShop — M16 — Score de risque par élève : matérialisation & exposition
--
-- Ne définit AUCUNE nouvelle formule de risque : réutilise
-- `calculer_score_decrochage` (M7), qui existait déjà (50 % absences non
-- justifiées + 20 % retards non justifiés + 30 % moyenne) mais n'était
-- jamais persisté ni exposé au-delà de `alertes_decrochage`. Ce patch
-- persiste ce score dans `statistiques_agregats` (type_agregat déjà réservé
-- 'risque_reussite' depuis M6) pour qu'il devienne consommable par le
-- dashboard directeur (bannière) et le grounding IA (Directeur-Adviser,
-- Parent IA) — une seule source de vérité, plusieurs consommateurs.
--
-- Poids/seuil de `calculer_score_decrochage`/`alertes_decrochage` : INTACTS,
-- non modifiés par ce patch. Échelle : la donnée persistée reste 0-1
-- (identique à `calculer_score_decrochage`) ; la conversion 0-100 est un
-- choix d'AFFICHAGE laissé aux consommateurs (bannière), jamais stocké ici.
--
-- Écart documenté (voir rapport de ce sous-livrable, pas silencieux) :
-- ecoshop_flutter calcule un score différent (70 % tendance des moyennes
-- sur ~3 mois + 30 % présence) — délibérément NON importé : EcoShop a déjà
-- sa propre formule, antérieure à M16 et déjà testée (M7). Choix de
-- conception assumé, pas un écart non traité.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Une seule ligne « risque_reussite » par (fiche_eleve_id, annee_scolaire_id)
-- ---------------------------------------------------------------------------
create unique index if not exists idx_statistiques_risque_reussite_unique
  on public.statistiques_agregats (fiche_eleve_id, annee_scolaire_id)
  where type_agregat = 'risque_reussite';

-- ---------------------------------------------------------------------------
-- 2. Matérialisation — même pattern que `generer_alertes_decrochage` (M7) :
--    boucle par établissement/année, réservée service_role (cron / Edge
--    Function), jamais appelable par le client.
-- ---------------------------------------------------------------------------
create or replace function public.materialiser_risque_reussite(
  p_etab uuid,
  p_annee uuid
)
returns setof uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_fiche uuid;
  v_score numeric;
  v_id uuid;
begin
  for v_fiche in
    select distinct i.fiche_eleve_id
    from public.inscriptions i
    where i.annee_scolaire_id = p_annee and i.deleted_at is null
      and exists (
        select 1 from public.fiches_eleves f
        where f.id = i.fiche_eleve_id and f.etablissement_id = p_etab and f.deleted_at is null
      )
  loop
    v_score := public.calculer_score_decrochage(v_fiche, p_annee);

    insert into public.statistiques_agregats
      (etablissement_id, annee_scolaire_id, fiche_eleve_id, type_agregat,
       valeur_numeric, calcule_le, version)
    values
      (p_etab, p_annee, v_fiche, 'risque_reussite', v_score, now(), 1)
    on conflict (fiche_eleve_id, annee_scolaire_id) where type_agregat = 'risque_reussite'
    do update set
      valeur_numeric = excluded.valeur_numeric,
      calcule_le = excluded.calcule_le,
      version = public.statistiques_agregats.version + 1
    returning id into v_id;

    return next v_id;
  end loop;

  return;
end;
$$;

revoke execute on function public.materialiser_risque_reussite(uuid, uuid) from public, anon, authenticated;
grant execute on function public.materialiser_risque_reussite(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Exposition — lecture unique pour tous les consommateurs (bannière
--    dashboard, grounding IA). Retourne le score de l'année scolaire
--    COURANTE de l'établissement de la fiche, échelle 0-1 (inchangée).
--    ⚠️ SECURITY DEFINER : la RLS de `statistiques_agregats` NE S'APPLIQUE
--    PAS à l'intérieur de cette fonction (elle s'exécute avec les droits du
--    propriétaire, pas de l'appelant) — la visibilité (`statistiques_select` :
--    personnel OU fiche_visible) est donc REVÉRIFIÉE explicitement ici, même
--    pattern que `note_visible`/`presence_visible` (M6/M7), jamais une
--    confiance dans la RLS de la table sous-jacente pour une fonction
--    SECURITY DEFINER.
-- ---------------------------------------------------------------------------
create or replace function public.risque_reussite_actuel(p_fiche uuid)
returns numeric
language sql stable security definer set search_path = public
as $$
  select sa.valeur_numeric
  from public.statistiques_agregats sa
  join public.annees_scolaires an on an.id = sa.annee_scolaire_id
  where sa.fiche_eleve_id = p_fiche
    and sa.type_agregat = 'risque_reussite'
    and an.courante
    and (public.est_personnel(sa.etablissement_id) or public.fiche_visible(sa.fiche_eleve_id))
  order by sa.calcule_le desc
  limit 1;
$$;

grant execute on function public.risque_reussite_actuel(uuid) to authenticated;

-- ============================================================================
-- Fin patch M16 — score de risque par élève.
-- ============================================================================
