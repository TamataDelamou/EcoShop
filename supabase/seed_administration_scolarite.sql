-- ============================================================================
-- EcoShop — M5 — Maquette de données Administration & Scolarité
--
-- S'appuie sur : l'établissement « Lycée Innovation Conakry » (seed M0) et les
-- niveaux Guinée du référentiel M4. Crée : année scolaire 2026-2027, 3
-- trimestres, 3 classes, 3 fiches élèves, inscriptions, une relation parent
-- ↔ élève (sélecteur d'enfant) et une affectation d'enseignant.
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

-- ---------------------------------------------------------------------------
-- Référentiel : établissement + niveaux Guinée (M4)
-- ---------------------------------------------------------------------------
create temp table if not exists seed_m5 (cle text primary key, val uuid);

insert into seed_m5 (cle, val)
select 'etab', id from public.etablissements where slug = 'lycee-innovation-conakry'
on conflict (cle) do nothing;

insert into seed_m5 (cle, val)
select 'niveau_7e', id from public.niveaux_educatifs where pays_code = 'GN' and code = '7e'
on conflict (cle) do nothing;

insert into seed_m5 (cle, val)
select 'niveau_10e', id from public.niveaux_educatifs where pays_code = 'GN' and code = '10e'
on conflict (cle) do nothing;

insert into seed_m5 (cle, val)
select 'niveau_terminale', id from public.niveaux_educatifs where pays_code = 'GN' and code = 'Terminale'
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- Année scolaire 2026-2027 (courante)
-- ---------------------------------------------------------------------------
insert into seed_m5 (cle, val)
select 'annee', id
from public.annees_scolaires
where etablissement_id = (select val from seed_m5 where cle = 'etab')
  and libelle = '2026-2027'
on conflict (cle) do nothing;

insert into public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
select (select val from seed_m5 where cle = 'etab'), '2026-2027', '2026-10-01', '2027-06-30', true
where not exists (select 1 from seed_m5 where cle = 'annee')
on conflict (etablissement_id, libelle) do nothing;

insert into seed_m5 (cle, val)
select 'annee', id
from public.annees_scolaires
where etablissement_id = (select val from seed_m5 where cle = 'etab')
  and libelle = '2026-2027'
on conflict (cle) do update set val = excluded.val;

-- ---------------------------------------------------------------------------
-- Périodes : 3 trimestres
-- ---------------------------------------------------------------------------
insert into public.periodes_scolaires
  (etablissement_id, annee_scolaire_id, code, libelle, type, ordre, date_debut, date_fin)
select (select val from seed_m5 where cle = 'etab'),
       (select val from seed_m5 where cle = 'annee'),
       v.code, v.libelle, 'trimestre', v.ordre, v.d1, v.d2
from (values
  ('T1', '1er trimestre', 1, '2026-10-01'::date, '2026-12-23'::date),
  ('T2', '2e trimestre',  2, '2027-01-04'::date, '2027-03-26'::date),
  ('T3', '3e trimestre',  3, '2027-04-05'::date, '2027-06-30'::date)
) as v(code, libelle, ordre, d1, d2)
on conflict (annee_scolaire_id, code) do nothing;

-- ---------------------------------------------------------------------------
-- Comptes : 3 élèves, 1 parent, 1 enseignant
-- ---------------------------------------------------------------------------
insert into seed_m5 (cle, val) values
  ('eleve1', pg_temp.creer_compte('+224620001001', 'eleve')),
  ('eleve2', pg_temp.creer_compte('+224620001002', 'eleve')),
  ('eleve3', pg_temp.creer_compte('+224620001003', 'eleve')),
  ('parent1', pg_temp.creer_compte('+224620001010', 'parent')),
  ('enseignant1', pg_temp.creer_compte('+224620001020', 'enseignant'))
on conflict (cle) do nothing;

-- L'enseignant est membre ; les élèves aussi. Le parent ne l'est PAS
-- (sa visibilité passe exclusivement par la relation parentale).
insert into public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
select val, (select val from seed_m5 where cle = 'etab'), v.role
from (values
  ('eleve1', 'eleve'),
  ('eleve2', 'eleve'),
  ('eleve3', 'eleve'),
  ('enseignant1', 'enseignant')
) as v(cle, role)
join seed_m5 s on s.cle = v.cle
on conflict (profile_id, etablissement_id) do nothing;

-- ---------------------------------------------------------------------------
-- Classes (structures d'accueil)
-- ---------------------------------------------------------------------------
insert into public.classes
  (etablissement_id, annee_scolaire_id, niveau_id, code, nom, enseignant_principal_id)
select (select val from seed_m5 where cle = 'etab'),
       (select val from seed_m5 where cle = 'annee'),
       (select val from seed_m5 where cle = v.niveau),
       v.code, v.nom,
       case when v.code = '7A' then (select val from seed_m5 where cle = 'enseignant1') end
from (values
  ('7A', '7e A', 'niveau_7e'),
  ('10A', '10e A', 'niveau_10e'),
  ('TALE_A', 'Terminale A', 'niveau_terminale')
) as v(code, nom, niveau)
on conflict (annee_scolaire_id, code) do nothing;

-- ---------------------------------------------------------------------------
-- Fiches élèves + liaisons compte ↔ fiche
-- ---------------------------------------------------------------------------
insert into public.fiches_eleves
  (etablissement_id, matricule, nom, prenom, date_naissance, sexe, statut, profile_id, lie_le)
select (select val from seed_m5 where cle = 'etab'), v.matricule, v.nom, v.prenom, v.ddn, v.sexe, 'actif',
       (select val from seed_m5 where cle = v.compte), now()
from (values
  ('MAT-2026-001', 'DIALLO', 'Aïcha', '2009-05-12'::date, 'F', 'eleve1'),
  ('MAT-2026-002', 'BARRY',  'Ibrahima', '2005-11-03'::date, 'M', 'eleve2'),
  ('MAT-2026-003', 'CAMARA', 'Fatoumata', '2004-02-18'::date, 'F', 'eleve3')
) as v(matricule, nom, prenom, ddn, sexe, compte)
on conflict (etablissement_id, matricule) do nothing;

-- ---------------------------------------------------------------------------
-- Inscriptions aux classes
-- ---------------------------------------------------------------------------
insert into public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
select (select val from seed_m5 where cle = 'etab'),
       f.id,
       c.id,
       (select val from seed_m5 where cle = 'annee'),
       'active'
from public.fiches_eleves f
join (values
  ('MAT-2026-001', '7A'),
  ('MAT-2026-002', '10A'),
  ('MAT-2026-003', 'TALE_A')
) as v(matricule, classe) on v.matricule = f.matricule
join public.classes c
  on c.code = v.classe
 and c.annee_scolaire_id = (select val from seed_m5 where cle = 'annee')
where f.etablissement_id = (select val from seed_m5 where cle = 'etab')
on conflict (fiche_eleve_id, annee_scolaire_id) do nothing;

-- ---------------------------------------------------------------------------
-- Relation parent ↔ élève (sélecteur d'enfant)
-- ---------------------------------------------------------------------------
insert into public.relations_parent_eleve
  (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
select (select val from seed_m5 where cle = 'etab'),
       (select val from seed_m5 where cle = 'parent1'),
       f.id, 'tuteur_legal', 'confirmee', true
from public.fiches_eleves f
where f.matricule = 'MAT-2026-001'
  and f.etablissement_id = (select val from seed_m5 where cle = 'etab')
on conflict (parent_profile_id, fiche_eleve_id) do nothing;

-- ---------------------------------------------------------------------------
-- Affectation de l'enseignant (titulaire de la 7e A)
-- ---------------------------------------------------------------------------
insert into public.affectations_enseignants
  (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, role_affectation)
select (select val from seed_m5 where cle = 'etab'),
       (select val from seed_m5 where cle = 'annee'),
       (select val from seed_m5 where cle = 'enseignant1'),
       c.id, 'titulaire'
from public.classes c
where c.code = '7A'
  and c.annee_scolaire_id = (select val from seed_m5 where cle = 'annee')
on conflict (annee_scolaire_id, enseignant_profile_id, classe_id, programme_matiere_id) do nothing;

-- ============================================================================
-- Fin de la maquette M5.
-- ============================================================================
