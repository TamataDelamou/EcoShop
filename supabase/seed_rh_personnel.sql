-- ============================================================================
-- EcoShop — M8 — Maquette de données RH & Personnel
--
-- S'appuie sur : l'établissement « Lycée Innovation Conakry » (M0), l'année
-- 2026-2027 et les enseignants des seeds M5/M6 (phones +224620001020 et
-- +224620001021). Crée : un compte direction (RH), 3 dossiers employés,
-- 3 contrats, 3 congés (dont une validation humaine), 4 absences personnel
-- et 3 bulletins de paie.
--
-- Idempotent : recherches par clés naturelles + on conflict do nothing.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Helper : créer ou retrouver un compte (auth.users → profil, par téléphone)
-- ---------------------------------------------------------------------------
create or replace function pg_temp.creer_compte(p_phone text, p_role text)
returns uuid
language plpgsql
set search_path = public, auth, pg_catalog
as $$
declare
  v_id uuid;
begin
  select p.id into v_id
  from public.profiles p
  join public.identifiants_comptes i on i.profile_id = p.id
  where i.valeur = p_phone
  limit 1;

  if v_id is null then
    insert into auth.users (id, phone) values (gen_random_uuid(), replace(p_phone, '+', ''));
    select p.id into v_id
    from public.profiles p
    join public.identifiants_comptes i on i.profile_id = p.id
    where i.valeur = p_phone
    limit 1;
  end if;

  update public.profiles set role_racine = p_role::public.role_racine where id = v_id;
  return v_id;
end $$;

create temp table if not exists seed_m8 (cle text primary key, val uuid);

-- ---------------------------------------------------------------------------
-- Référentiel partagé
-- ---------------------------------------------------------------------------
insert into seed_m8 (cle, val)
select 'etab', id from public.etablissements where slug = 'lycee-innovation-conakry'
on conflict (cle) do nothing;

insert into seed_m8 (cle, val)
select 'annee', id from public.annees_scolaires
where etablissement_id = (select val from seed_m8 where cle = 'etab') and libelle = '2026-2027'
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- Comptes : direction (RH) + retrouver les deux enseignants existants
-- ---------------------------------------------------------------------------
insert into seed_m8 (cle, val)
values ('dir1', pg_temp.creer_compte('+224620001030', 'direction'))
on conflict (cle) do nothing;

insert into seed_m8 (cle, val)
select 'ens1', p.id from public.profiles p
join public.identifiants_comptes i on i.profile_id = p.id
where i.valeur = '+224620001020'
on conflict (cle) do nothing;

insert into seed_m8 (cle, val)
select 'ens2', p.id from public.profiles p
join public.identifiants_comptes i on i.profile_id = p.id
where i.valeur = '+224620001021'
on conflict (cle) do nothing;

-- La direction est membre de l'établissement (rôle « direction »).
insert into public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
select (select val from seed_m8 where cle = 'dir1'),
       (select val from seed_m8 where cle = 'etab'),
       'direction'
on conflict (profile_id, etablissement_id) do nothing;

-- ---------------------------------------------------------------------------
-- Dossiers employés
-- ---------------------------------------------------------------------------
insert into public.employes
  (etablissement_id, profile_id, matricule, categorie, date_embauche)
values
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'dir1'), 'EMP-000', 'direction',  '2020-01-15'::date),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'ens1'), 'EMP-001', 'enseignant', '2023-09-01'::date),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'ens2'), 'EMP-002', 'enseignant', '2026-08-01'::date)
on conflict do nothing;

insert into seed_m8 (cle, val)
select 'emp_dir', id from public.employes
where etablissement_id = (select val from seed_m8 where cle = 'etab') and matricule = 'EMP-000'
on conflict (cle) do update set val = excluded.val;

insert into seed_m8 (cle, val)
select 'emp_ens1', id from public.employes
where etablissement_id = (select val from seed_m8 where cle = 'etab') and matricule = 'EMP-001'
on conflict (cle) do update set val = excluded.val;

insert into seed_m8 (cle, val)
select 'emp_ens2', id from public.employes
where etablissement_id = (select val from seed_m8 where cle = 'etab') and matricule = 'EMP-002'
on conflict (cle) do update set val = excluded.val;

-- ---------------------------------------------------------------------------
-- Contrats
-- ---------------------------------------------------------------------------
insert into public.contrats
  (etablissement_id, employe_id, type, date_debut, date_fin, salaire_base, renouvellement_auto)
values
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_dir'),  'cdi', '2020-01-15'::date, null,               6000000, false),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_ens1'), 'cdi', '2023-09-01'::date, null,               3500000, false),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_ens2'), 'cdd', '2026-08-01'::date, '2026-11-30'::date, 2800000, true)
on conflict (employe_id, date_debut, type) do nothing;

insert into seed_m8 (cle, val)
select 'contrat_dir', id from public.contrats
where employe_id = (select val from seed_m8 where cle = 'emp_dir')
on conflict (cle) do update set val = excluded.val;

insert into seed_m8 (cle, val)
select 'contrat_ens1', id from public.contrats
where employe_id = (select val from seed_m8 where cle = 'emp_ens1')
on conflict (cle) do update set val = excluded.val;

insert into seed_m8 (cle, val)
select 'contrat_ens2', id from public.contrats
where employe_id = (select val from seed_m8 where cle = 'emp_ens2')
on conflict (cle) do update set val = excluded.val;

-- ---------------------------------------------------------------------------
-- Congés : un validé (direction), une demande en attente (enseignant 1),
-- un arrêt maladie validé (enseignant 2).
-- ---------------------------------------------------------------------------
insert into public.conges
  (etablissement_id, employe_id, type, date_debut, date_fin, nb_jours, statut, motif)
values
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_dir'),  'annuel',  '2026-12-20'::date, '2027-01-03'::date, 10, 'valide',  'Congés de fin d''année'),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_ens1'), 'annuel',  '2026-10-15'::date, '2026-10-17'::date,  3, 'demande', 'Motif familial'),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_ens2'), 'maladie', '2026-09-10'::date, '2026-09-12'::date,  3, 'valide',  'Certificat médical')
on conflict (employe_id, date_debut, type) do nothing;

-- ---------------------------------------------------------------------------
-- Absences personnel (enseignant 2 : 3 injustifiées + 1 maladie) — alimente
-- le risque de turn-over (score élevé attendu).
-- ---------------------------------------------------------------------------
insert into public.absences_personnel
  (etablissement_id, employe_id, date_absence, type, justifie, motif)
values
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_ens2'), '2026-08-20'::date, 'injustifiee', false, null),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_ens2'), '2026-09-02'::date, 'injustifiee', false, null),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_ens2'), '2026-09-15'::date, 'injustifiee', false, null),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_ens2'), '2026-09-11'::date, 'maladie',     true,  'Certificat médical')
on conflict (employe_id, date_absence) do nothing;

-- ---------------------------------------------------------------------------
-- Paie légère — trois bulletins (net recalculé par le trigger serveur)
-- ---------------------------------------------------------------------------
insert into public.paie_bulletins
  (etablissement_id, employe_id, contrat_id, periode_debut, periode_fin,
   salaire_base, primes, retenues, net, statut)
values
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_dir'),  (select val from seed_m8 where cle = 'contrat_dir'),  '2026-10-01'::date, '2026-10-31'::date, 6000000, 300000, 250000, 0, 'paye'),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_ens1'), (select val from seed_m8 where cle = 'contrat_ens1'), '2026-10-01'::date, '2026-10-31'::date, 3500000, 200000, 100000, 0, 'brouillon'),
  ((select val from seed_m8 where cle = 'etab'), (select val from seed_m8 where cle = 'emp_ens2'), (select val from seed_m8 where cle = 'contrat_ens2'), '2026-10-01'::date, '2026-10-31'::date, 2800000, 0,      150000, 0, 'valide')
on conflict (employe_id, periode_debut) do nothing;

-- ============================================================================
-- Fin de la maquette M8.
-- ============================================================================
