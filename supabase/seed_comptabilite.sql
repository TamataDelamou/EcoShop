-- ============================================================================
-- EcoShop — M14 — Maquette de données Comptabilité sans OHADA
--
-- S'appuie sur : l'établissement « Lycée Innovation Conakry » (seed M0).
-- Crée : un plan comptable de base (structure ouverte), 3 journaux, et des
-- écritures de démonstration (scolarité, cantine, fournitures, salaires
-- récurrents sur 2 mois, caisse).
--
-- Idempotent : recherches par clés naturelles + gardes NOT EXISTS.
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

-- ---------------------------------------------------------------------------
-- Clés résolues
-- ---------------------------------------------------------------------------
create temp table if not exists seed_m14 (cle text primary key, val uuid);

insert into seed_m14 (cle, val)
select 'etab', id from public.etablissements where slug = 'lycee-innovation-conakry'
on conflict (cle) do nothing;

insert into seed_m14 (cle, val) values
  ('saisisseur', pg_temp.creer_compte('+224620001040', 'direction'))
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- Plan comptable de base (structure ouverte, sans plan OHADA imposé)
-- ---------------------------------------------------------------------------
insert into public.plans_comptables (etablissement_id, code, intitule, type)
select (select val from seed_m14 where cle = 'etab'), v.code, v.intitule, v.type
from (values
  ('100', 'Capital social',            'capitaux'),
  ('200', 'Immobilisations',           'actif'),
  ('401', 'Fournisseurs',              'passif'),
  ('411', 'Clients',                   'actif'),
  ('520', 'Banque',                    'banque'),
  ('530', 'Caisse',                    'caisse'),
  ('600', 'Achats & fournitures',      'charge'),
  ('610', 'Salaires',                  'charge'),
  ('620', 'Abonnements & services',    'charge'),
  ('700', 'Ventes & services',         'produit'),
  ('701', 'Scolarité',                 'produit')
) as v(code, intitule, type)
on conflict (etablissement_id, code) do nothing;

-- ---------------------------------------------------------------------------
-- Journaux
-- ---------------------------------------------------------------------------
insert into public.journaux (etablissement_id, code, intitule, type)
select (select val from seed_m14 where cle = 'etab'), v.code, v.intitule, v.type
from (values
  ('OP', 'Journal des opérations diverses', 'operations'),
  ('BQ', 'Livre de banque',                'banque'),
  ('CS', 'Livre de caisse',                'caisse')
) as v(code, intitule, type)
on conflict (etablissement_id, code) do nothing;

-- ---------------------------------------------------------------------------
-- Écritures (idempotentes via NOT EXISTS sur clés naturelles)
-- ---------------------------------------------------------------------------
insert into public.ecritures_comptables
  (etablissement_id, date_ecriture, libelle, compte_debit_id, compte_credit_id,
   montant, piece_justificative, journal_id, user_id)
select (select val from seed_m14 where cle = 'etab'),
       v.date_ecriture, v.libelle,
       d.id, c.id, v.montant, v.piece,
       j.id, (select val from seed_m14 where cle = 'saisisseur')
from (values
  ('2026-09-15', 'Scolarité trimestre 1',    '520', '701', 500000, 'ENC-2026-0001', 'BQ'),
  ('2026-09-20', 'Cantine septembre',        '520', '700', 120000, 'ENC-2026-0002', 'BQ'),
  ('2026-09-25', 'Achat fournitures',        '600', '520',  85000, 'FAC-2026-0001', 'BQ'),
  ('2026-09-28', 'Salaires septembre',       '610', '520', 300000, 'PAIE-2026-09',  'BQ'),
  ('2026-10-28', 'Salaires octobre',         '610', '520', 300000, 'PAIE-2026-10',  'BQ'),
  ('2026-10-05', 'Retrait caisse',           '530', '520',  50000, 'CSH-2026-0001', 'CS')
) as v(date_ecriture, libelle, dcode, ccode, montant, piece, jcode)
join public.plans_comptables d on d.code = v.dcode
  and d.etablissement_id = (select val from seed_m14 where cle = 'etab')
join public.plans_comptables c on c.code = v.ccode
  and c.etablissement_id = (select val from seed_m14 where cle = 'etab')
join public.journaux j on j.code = v.jcode
  and j.etablissement_id = (select val from seed_m14 where cle = 'etab')
where not exists (
  select 1 from public.ecritures_comptables e
  where e.etablissement_id = (select val from seed_m14 where cle = 'etab')
    and e.date_ecriture = v.date_ecriture
    and e.libelle = v.libelle
    and e.montant = v.montant
);

-- ============================================================================
-- Fin de la maquette M14.
-- ============================================================================
