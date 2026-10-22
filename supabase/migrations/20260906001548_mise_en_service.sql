-- ============================================================================
-- EcoShop — Mise en service (kit de déploiement)
--
-- 1. `executer_taches_quotidiennes()` : un seul appel planifié par nuit
--    pour toutes les écoles (année courante) — alertes de décrochage (M7)
--    et risque de réussite (M16), jusque-là sans planification. Une école
--    en erreur n'empêche pas les autres.
-- 2. `etat_mise_en_service()` : liste de contrôle lisible par l'équipe GSG
--    (et par le script de déploiement) — tâches planifiées, secrets rangés,
--    administrateur GSG, prix des packs SMS. Ne révèle aucune valeur
--    secrète, seulement leur présence.
--
-- Les tâches planifiées elles-mêmes (pg_cron) sont créées par
-- `supabase/mise_en_service/taches_planifiees.modele.sql`, rempli par
-- `scripts/deployer_supabase.ps1` : elles dépendent de l'adresse du projet
-- et de secrets qui n'ont pas leur place dans une migration.
--
-- Migration idempotente.
-- ============================================================================

create or replace function public.executer_taches_quotidiennes()
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  a record;
  v_alertes integer := 0;
  v_risques integer := 0;
  v_ecoles integer := 0;
  v_erreurs jsonb := '[]'::jsonb;
  v_n integer;
begin
  for a in
    select an.id, an.etablissement_id
    from public.annees_scolaires an
    join public.etablissements e on e.id = an.etablissement_id
    where an.courante and not an.cloturee and e.deleted_at is null and e.statut = 'actif'
  loop
    begin
      select count(*) into v_n from public.generer_alertes_decrochage(a.etablissement_id, a.id);
      v_alertes := v_alertes + v_n;
      select count(*) into v_n from public.materialiser_risque_reussite(a.etablissement_id, a.id);
      v_risques := v_risques + v_n;
      v_ecoles := v_ecoles + 1;
    exception when others then
      v_erreurs := v_erreurs || jsonb_build_object('etablissement', a.etablissement_id, 'erreur', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('ecoles', v_ecoles, 'alertes_decrochage', v_alertes,
                            'risques_reussite', v_risques, 'erreurs', v_erreurs);
end;
$$;

revoke all on function public.executer_taches_quotidiennes() from public, anon, authenticated;
grant execute on function public.executer_taches_quotidiennes() to service_role;

-- Tâches planifiées attendues : nom pg_cron → rôle.
create or replace function public.taches_planifiees_attendues()
returns table (nom text, role text)
language sql immutable set search_path = public
as $$
  values
    ('envoyer-notifications', 'Courriels et SMS (chaque minute)'),
    ('envoyer-push', 'Notifications push (chaque minute)'),
    ('relancer-paiements-orange-money', 'Paiements Orange Money restés en suspens (toutes les 5 min)'),
    ('detecter-absences-portail', 'Absences au portail (toutes les 10 min)'),
    ('expirer-offres-inscription', 'Places d''inscription non confirmées (chaque heure)'),
    ('taches-quotidiennes', 'Décrochage et risque de réussite (chaque nuit)'),
    ('purger-notifications', 'Ménage des notifications de plus de 90 jours (chaque nuit)'),
    ('purger-historique-taches', 'Ménage de l''historique des tâches (chaque nuit)')
$$;

create or replace function public.etat_mise_en_service()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_controles jsonb := '[]'::jsonb;
  v_ok boolean;
  v_detail text;
  t record;
  v_present boolean;
  v_dernier text;
begin
  -- Un compte connecté doit être de l'équipe GSG ; sans compte, c'est le
  -- serveur (script de déploiement, service_role).
  if auth.uid() is not null and not public.est_admin_gsg() then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  -- Extensions
  for t in select unnest(array['pg_cron', 'pg_net']) as ext loop
    v_ok := exists (select 1 from pg_extension where extname = t.ext);
    v_controles := v_controles || jsonb_build_object('controle', 'Extension ' || t.ext, 'ok', v_ok,
      'detail', case when v_ok then 'activée' else 'à activer (Database → Extensions)' end);
  end loop;

  -- Tâches planifiées (lecture dynamique : pg_cron peut être absent)
  for t in select * from public.taches_planifiees_attendues() loop
    v_present := false; v_dernier := null;
    if to_regclass('cron.job') is not null then
      execute 'select exists (select 1 from cron.job where jobname = $1 and active)' into v_present using t.nom;
      if v_present and to_regclass('cron.job_run_details') is not null then
        execute 'select d.status || '' le '' || to_char(d.start_time at time zone ''UTC'', ''DD/MM HH24:MI'') || '' UTC''
                   from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                  where j.jobname = $1 order by d.start_time desc limit 1'
          into v_dernier using t.nom;
      end if;
    end if;
    v_controles := v_controles || jsonb_build_object('controle', 'Tâche « ' || t.nom || ' »', 'ok', v_present,
      'detail', t.role || case when v_present then coalesce(' — dernier passage : ' || v_dernier, ' — pas encore exécutée')
                               else ' — absente' end);
  end loop;

  -- Secrets rangés dans le coffre (présence seulement)
  for t in select unnest(array['ecoshop_url_projet', 'notifications_declencheur_secret', 'paiements_declencheur_secret']) as nom loop
    v_present := false;
    if to_regclass('vault.secrets') is not null then
      execute 'select exists (select 1 from vault.secrets where name = $1)' into v_present using t.nom;
    end if;
    v_controles := v_controles || jsonb_build_object('controle', 'Coffre : ' || t.nom, 'ok', v_present,
      'detail', case when v_present then 'rangé' else 'absent' end);
  end loop;

  -- Administrateur GSG
  v_ok := exists (select 1 from public.profiles where role_racine = 'admin_gsg' and deleted_at is null);
  v_controles := v_controles || jsonb_build_object('controle', 'Administrateur GSG', 'ok', v_ok,
    'detail', case when v_ok then 'désigné' else 'à désigner (premier_admin.modele.sql)' end);

  -- Packs SMS
  select string_agg(code, ', ') into v_detail from public.packs_sms where actif and prix > 0;
  v_ok := v_detail is not null;
  v_controles := v_controles || jsonb_build_object('controle', 'Packs SMS en vente', 'ok', v_ok,
    'detail', coalesce(v_detail, 'aucun : fixer les prix (écran Crédits SMS GSG)'));

  return jsonb_build_object(
    'pret', not exists (select 1 from jsonb_array_elements(v_controles) c where not (c ->> 'ok')::boolean),
    'controles', v_controles);
end;
$$;

revoke all on function public.taches_planifiees_attendues() from public, anon;
grant execute on function public.taches_planifiees_attendues() to authenticated, service_role;
revoke all on function public.etat_mise_en_service() from public, anon;
grant execute on function public.etat_mise_en_service() to authenticated, service_role;
