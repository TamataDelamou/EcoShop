-- ============================================================================
-- EcoShop — M16 — Sous-livrable 2/7 : bannière dashboard directeur
-- « élèves à risque »
--
-- Ne définit AUCUN nouveau calcul de risque : consomme
-- `statistiques_agregats.risque_reussite`, matérialisé par
-- `materialiser_risque_reussite` (sous-livrable 1/7, migration
-- 20260906001504) — une seule source, un nouveau consommateur.
--
-- Ajoute un 7e code ('eleves_a_risque') au mécanisme de consolidation déjà
-- existant (`consolider_indicateurs_etablissement`, M10) plutôt que
-- d'inventer un second mécanisme de matérialisation parallèle pour le
-- dashboard directeur — même table (`indicateurs_cles`), même RLS, même
-- écran client (`ecran_tableau_bord_rapports.dart`) que les 6 indicateurs
-- existants.
--
-- Seuil : 0.6, identique au seuil par défaut de `generer_alertes_decrochage`
-- (M7) — la bannière compte la MÊME population que celle qui déclenche une
-- alerte décrochage, pas un seuil indépendant inventé pour l'occasion.
--
-- Écart source documenté (rapport de ce sous-livrable) : ecoshop_flutter
-- distingue en plus un sous-compte « dontDonneeFiable » (élèves à risque
-- dont le compte est lié), lié à sa notion de fiabilité de mesure Parent IA
-- (device Android). EcoShop n'a pas d'équivalent : `calculer_score_decrochage`
-- ne porte aucun indicateur de fiabilité de ce type — la nuance n'est pas
-- portée parce qu'elle n'a rien à porter, pas parce qu'elle a été oubliée.
--
-- Migration idempotente.
-- ============================================================================

create or replace function public.consolider_indicateurs_etablissement(p_etab uuid, p_annee uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_effectifs numeric; v_reussite numeric; v_absenteisme numeric;
  v_turnover numeric; v_masse numeric; v_engagement numeric;
  v_eleves_a_risque numeric;
  v_d date; v_f date;
begin
  if not public.est_personnel(p_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  select date_debut, date_fin into v_d, v_f from public.annees_scolaires where id = p_annee;

  select count(*) into v_effectifs
  from public.inscriptions i
  where i.etablissement_id = p_etab and i.annee_scolaire_id = p_annee
    and i.statut = 'active' and i.deleted_at is null;

  select case when count(*) = 0 then 0
              else count(*) filter (where n.valeur / e.bareme >= 0.5)::numeric / count(*)::numeric end
  into v_reussite
  from public.notes n
  join public.evaluations e on e.id = n.evaluation_id
  where n.etablissement_id = p_etab and e.annee_scolaire_id = p_annee
    and n.deleted_at is null and e.deleted_at is null
    and n.absent = false and n.valeur is not null;

  select case when count(*) = 0 then 0
              else count(*) filter (where p.statut <> 'present')::numeric / count(*)::numeric end
  into v_absenteisme
  from public.presences p
  where p.etablissement_id = p_etab and p.annee_scolaire_id = p_annee and p.deleted_at is null;

  select case when count(*) = 0 then 0
              else count(*) filter (where emp.statut in ('demissionnaire','suspendu','retraite'))::numeric / count(*)::numeric end
  into v_turnover
  from public.employes emp
  where emp.etablissement_id = p_etab and emp.deleted_at is null;

  select coalesce(sum(pb.net), 0) into v_masse
  from public.paie_bulletins pb
  where pb.etablissement_id = p_etab and pb.deleted_at is null
    and pb.periode_debut between v_d and v_f;

  select case when count(*) = 0 then 0
              else count(*) filter (where n.date_lecture is not null)::numeric / count(*)::numeric end
  into v_engagement
  from public.notifications n
  where n.etablissement_id = p_etab and n.deleted_at is null
    and n.date_envoi is not null
    and n.date_envoi::date between v_d and v_f;

  -- ★ AJOUTÉ (M16, sous-livrable 2/7) : rafraîchit d'abord la source unique
  -- (statistiques_agregats.risque_reussite), puis compte au seuil 0.6 —
  -- jamais un second calcul parallèle à calculer_score_decrochage.
  perform public.materialiser_risque_reussite(p_etab, p_annee);

  select count(*) into v_eleves_a_risque
  from public.statistiques_agregats sa
  where sa.etablissement_id = p_etab and sa.annee_scolaire_id = p_annee
    and sa.type_agregat = 'risque_reussite'
    and sa.valeur_numeric >= 0.6;

  insert into public.indicateurs_cles (etablissement_id, annee_scolaire_id, code, valeur_numeric, calcule_le, version)
  values
    (p_etab, p_annee, 'effectifs',          v_effectifs,       now(), 1),
    (p_etab, p_annee, 'taux_reussite',      v_reussite,        now(), 1),
    (p_etab, p_annee, 'absentisme',         v_absenteisme,     now(), 1),
    (p_etab, p_annee, 'turnover',           v_turnover,        now(), 1),
    (p_etab, p_annee, 'masse_salariale',    v_masse,           now(), 1),
    (p_etab, p_annee, 'engagement_parents', v_engagement,      now(), 1),
    (p_etab, p_annee, 'eleves_a_risque',    v_eleves_a_risque, now(), 1)
  on conflict (etablissement_id, annee_scolaire_id, code) where periode_id is null and classe_id is null
  do update set valeur_numeric = excluded.valeur_numeric,
                calcule_le = now(),
                version = public.indicateurs_cles.version + 1;

  return 7;
end $$;

-- ============================================================================
-- Fin patch M16 — bannière élèves à risque.
-- ============================================================================
