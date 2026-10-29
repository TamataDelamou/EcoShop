-- ============================================================================
-- EcoShop — Tâches planifiées (pg_cron + pg_net) et coffre (Vault)
--
-- MODÈLE : rempli et exécuté par scripts/deployer_supabase.ps1 (les {{…}}
-- sont remplacés, le fichier rempli est effacé après exécution). Peut être
-- rejoué sans risque : chaque tâche est remplacée, jamais dupliquée.
-- Heures en UTC (= heure de Conakry).
-- ============================================================================

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

create or replace function pg_temp.ranger_secret(p_nom text, p_valeur text) returns void
language plpgsql as $$
declare v_id uuid;
begin
  if coalesce(p_valeur, '') = '' then return; end if;
  select id into v_id from vault.secrets where name = p_nom;
  if v_id is null then
    perform vault.create_secret(p_valeur, p_nom);
  else
    perform vault.update_secret(v_id, p_valeur);
  end if;
end $$;

create or replace function pg_temp.planifier(p_nom text, p_horaire text, p_commande text) returns void
language plpgsql as $$
begin
  if exists (select 1 from cron.job where jobname = p_nom) then
    perform cron.unschedule(p_nom);
  end if;
  perform cron.schedule(p_nom, p_horaire, p_commande);
end $$;

-- Appel d'une Edge Function : adresse et secret lus dans le coffre au
-- moment de l'appel (jamais en clair dans la tâche).
create or replace function pg_temp.appel(p_fonction text, p_secret text) returns text
language sql as $$
  select format($c$select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'ecoshop_url_projet') || '/functions/v1/%s',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-declencheur-secret', (select decrypted_secret from vault.decrypted_secrets where name = %L)),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000)$c$, p_fonction, p_secret)
$$;

select pg_temp.ranger_secret('ecoshop_url_projet', '{{URL_PROJET}}');
select pg_temp.ranger_secret('notifications_declencheur_secret', '{{NOTIFICATIONS_DECLENCHEUR_SECRET}}');
select pg_temp.ranger_secret('paiements_declencheur_secret', '{{PAIEMENTS_DECLENCHEUR_SECRET}}');
select pg_temp.ranger_secret('kernel_export_declencheur_secret', '{{KERNEL_EXPORT_DECLENCHEUR_SECRET}}');

select pg_temp.planifier('envoyer-notifications', '* * * * *',
  pg_temp.appel('envoyer_notifications', 'notifications_declencheur_secret'));
select pg_temp.planifier('envoyer-push', '* * * * *',
  pg_temp.appel('envoyer_push', 'notifications_declencheur_secret'));
select pg_temp.planifier('relancer-paiements-orange-money', '*/5 * * * *',
  pg_temp.appel('relancer_paiements_orange_money', 'paiements_declencheur_secret'));
select pg_temp.planifier('detecter-absences-portail', '*/10 * * * *',
  'select public.detecter_absences_portail()');
select pg_temp.planifier('expirer-offres-inscription', '7 * * * *',
  'select public.expirer_offres_inscription()');
-- REG-18 : inscriptions abandonnées (adresse jamais vérifiée) après 24 h.
select pg_temp.planifier('purger-comptes-non-verifies', '25 * * * *',
  'select public.purger_comptes_non_verifies()');
select pg_temp.planifier('taches-quotidiennes', '30 2 * * *',
  'select public.executer_taches_quotidiennes()');
select pg_temp.planifier('purger-notifications', '15 3 * * *',
  'select public.purger_notifications(90)');
-- REG-31 : comptes dont le délai de 7 jours est échu ; traces de sécurité > 1 an.
select pg_temp.planifier('effectuer-suppressions-comptes', '35 3 * * *',
  'select public.effectuer_suppressions_comptes()');
select pg_temp.planifier('purger-historique-taches', '45 3 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$);

-- Kernel GSG : seulement quand son secret est fourni.
select pg_temp.planifier('kernel-export', '20 * * * *',
  pg_temp.appel('kernel-export', 'kernel_export_declencheur_secret'))
where '{{KERNEL_EXPORT_DECLENCHEUR_SECRET}}' <> '';

select jsonb_pretty(public.etat_mise_en_service()) as etat_mise_en_service;
