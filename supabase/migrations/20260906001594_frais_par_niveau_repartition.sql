-- ============================================================================
-- EcoShop — REG-39 : frais de scolarité par classe et répartition automatique.
--
-- Retour du test sur téléphone (2026-10-31) : les frais se fixent en
-- fonction des classes, et le montant doit se répartir automatiquement entre
-- les tranches de paiement ou les mois.
--
-- 1. enregistrer_frais_niveau : tarif d'un niveau (toutes les classes de ce
--    niveau), ou tarif par défaut (niveau nul). L'écran faisait un upsert
--    PostgREST sur (etablissement, année, niveau) alors que l'unicité est un
--    index sur une expression (coalesce du niveau) : PostgREST ne peut pas
--    s'en servir pour ON CONFLICT. Mise à jour sinon insertion, côté serveur.
-- 2. repartir_paliers : remplace d'un coup les paliers de l'année (3 tranches
--    égales, 9 mois…). Les ajouter un par un butait sur la somme de 100 %.
--
-- Ces fonctions s'exécutent avec les droits du propriétaire : le verrou du
-- réseau à grille commune (REG-17) laisserait passer, on le vérifie donc
-- explicitement.
-- ============================================================================

create or replace function public.enregistrer_frais_niveau(
  p_etablissement uuid,
  p_annee uuid,
  p_niveau uuid,
  p_montant_annuel numeric,
  p_frais_inscription numeric default 0
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if not (coalesce(public.est_direction(p_etablissement), false)
          or coalesce(public.a_permission(p_etablissement, 'scolarite.parametres.gerer'), false)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if public.reseau_frais_communs(p_etablissement) is not null then
    raise exception 'FRAIS_FIXES_PAR_RESEAU' using errcode = '42501';
  end if;
  if not exists (select 1 from public.annees_scolaires where id = p_annee and etablissement_id = p_etablissement) then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  -- Montant vide pour un niveau : on revient au tarif par défaut.
  if p_montant_annuel is null then
    if p_niveau is not null then
      update public.frais_scolarite_config set deleted_at = now()
       where etablissement_id = p_etablissement and annee_scolaire_id = p_annee
         and niveau_id = p_niveau and deleted_at is null;
    end if;
    return;
  end if;
  if p_montant_annuel < 0 or coalesce(p_frais_inscription, 0) < 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;

  update public.frais_scolarite_config
     set montant_annuel = p_montant_annuel,
         frais_inscription = coalesce(p_frais_inscription, 0)
   where etablissement_id = p_etablissement and annee_scolaire_id = p_annee
     and niveau_id is not distinct from p_niveau and deleted_at is null;
  if not found then
    insert into public.frais_scolarite_config
      (etablissement_id, annee_scolaire_id, niveau_id, montant_annuel, frais_inscription)
    values (p_etablissement, p_annee, p_niveau, p_montant_annuel, coalesce(p_frais_inscription, 0));
  end if;
end;
$$;

revoke all on function public.enregistrer_frais_niveau(uuid, uuid, uuid, numeric, numeric) from public, anon;
grant execute on function public.enregistrer_frais_niveau(uuid, uuid, uuid, numeric, numeric) to authenticated;

-- p_paliers : tableau JSON [{ "nom": "Tranche 1", "pourcentage": 33.34,
-- "date_limite": "2026-11-30" }, …], dans l'ordre. Somme = 100 (à 0,05 près,
-- l'arrondi est porté par le dernier palier). Tableau vide : paiement en une
-- fois.
create or replace function public.repartir_paliers(
  p_etablissement uuid,
  p_annee uuid,
  p_paliers jsonb
)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_n integer := coalesce(jsonb_array_length(p_paliers), 0);
  v_somme numeric := 0;
  v_ordre integer := 0;
  v_p jsonb;
  v_pourcentage numeric;
begin
  if not (coalesce(public.est_direction(p_etablissement), false)
          or coalesce(public.a_permission(p_etablissement, 'scolarite.parametres.gerer'), false)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if not exists (select 1 from public.annees_scolaires where id = p_annee and etablissement_id = p_etablissement) then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  if v_n > 12 then
    raise exception 'TROP_DE_PALIERS' using errcode = '22023';
  end if;

  select coalesce(sum((x->>'pourcentage')::numeric), 0) into v_somme
    from jsonb_array_elements(coalesce(p_paliers, '[]'::jsonb)) x;
  if v_n > 0 and abs(v_somme - 100) > 0.05 then
    raise exception 'SOMME_DIFFERENTE_DE_100' using errcode = '22023';
  end if;

  -- L'unicité (établissement, année, ordre) ne tient pas compte de
  -- deleted_at : les anciens paliers sont retirés pour de bon (aucune table
  -- ne les référence).
  delete from public.paliers_paiement_config
   where etablissement_id = p_etablissement and annee_scolaire_id = p_annee;

  for v_p in select * from jsonb_array_elements(coalesce(p_paliers, '[]'::jsonb)) loop
    v_ordre := v_ordre + 1;
    v_pourcentage := round((v_p->>'pourcentage')::numeric, 2);
    -- Dernier palier : complète exactement à 100.
    if v_ordre = v_n then
      v_pourcentage := 100 - coalesce((
        select sum(pourcentage) from public.paliers_paiement_config
         where etablissement_id = p_etablissement and annee_scolaire_id = p_annee and deleted_at is null), 0);
    end if;
    insert into public.paliers_paiement_config
      (etablissement_id, annee_scolaire_id, nom, pourcentage, ordre, date_limite)
    values (p_etablissement, p_annee, coalesce(nullif(trim(v_p->>'nom'), ''), 'Tranche ' || v_ordre),
            v_pourcentage, v_ordre, nullif(v_p->>'date_limite', '')::date);
  end loop;
  return v_ordre;
end;
$$;

revoke all on function public.repartir_paliers(uuid, uuid, jsonb) from public, anon;
grant execute on function public.repartir_paliers(uuid, uuid, jsonb) to authenticated;
