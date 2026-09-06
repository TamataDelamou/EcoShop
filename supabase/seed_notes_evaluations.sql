-- ============================================================================
-- EcoShop — M6 — Maquette de données Notes & Évaluations
--
-- S'appuie sur les seeds M0 (établissements, années), M4 (référentiel,
-- matière « Mathématiques » du programme guinéen 10e) et M5 (classes 7A/10A,
-- fiches MAT-2026-001/002, enseignant1 titulaire 7A).
--
-- Crée : un second enseignant (10A), deux évaluations (7A sans matière,
-- 10A Mathématiques), les notes associées (dont une saisie hors-ligne),
-- deux appréciations, un bulletin publié et des statistiques/signaux IA.
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

create temp table if not exists seed_m6 (cle text primary key, val uuid);

-- ---------------------------------------------------------------------------
-- Référentiel partagé
-- ---------------------------------------------------------------------------
insert into seed_m6 (cle, val)
select 'etab', id from public.etablissements where slug = 'lycee-innovation-conakry'
on conflict (cle) do nothing;

insert into seed_m6 (cle, val)
select 'annee', id from public.annees_scolaires
where etablissement_id = (select val from seed_m6 where cle = 'etab') and libelle = '2026-2027'
on conflict (cle) do nothing;

insert into seed_m6 (cle, val)
select 'periode_t1', id from public.periodes_scolaires
where annee_scolaire_id = (select val from seed_m6 where cle = 'annee') and code = 'T1'
on conflict (cle) do nothing;

insert into seed_m6 (cle, val)
select 'classe_7a', id from public.classes
where annee_scolaire_id = (select val from seed_m6 where cle = 'annee') and code = '7A'
on conflict (cle) do nothing;

insert into seed_m6 (cle, val)
select 'classe_10a', id from public.classes
where annee_scolaire_id = (select val from seed_m6 where cle = 'annee') and code = '10A'
on conflict (cle) do nothing;

insert into seed_m6 (cle, val)
select 'fiche_aicha', id from public.fiches_eleves
where etablissement_id = (select val from seed_m6 where cle = 'etab') and matricule = 'MAT-2026-001'
on conflict (cle) do nothing;

insert into seed_m6 (cle, val)
select 'fiche_ibrahima', id from public.fiches_eleves
where etablissement_id = (select val from seed_m6 where cle = 'etab') and matricule = 'MAT-2026-002'
on conflict (cle) do nothing;

insert into seed_m6 (cle, val)
select 'enseignant1', p.id from public.profiles p
join public.identifiants_comptes i on i.profile_id = p.id
where i.valeur = '+224620001020'
on conflict (cle) do nothing;

insert into seed_m6 (cle, val)
select 'matiere_math', m.id
from public.programmes_matieres m
join public.programmes_officiels p on p.id = m.programme_id
where p.code = 'PROG-GN-10E' and m.code = 'MATH'
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- Second enseignant (10A) + affectation à la matière Mathématiques
-- ---------------------------------------------------------------------------
insert into seed_m6 (cle, val)
values ('enseignant2', pg_temp.creer_compte('+224620001021', 'enseignant'))
on conflict (cle) do nothing;

insert into public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
values (
  (select val from seed_m6 where cle = 'enseignant2'),
  (select val from seed_m6 where cle = 'etab'),
  'enseignant'
)
on conflict (profile_id, etablissement_id) do nothing;

insert into public.affectations_enseignants
  (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, programme_matiere_id, role_affectation)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'enseignant2'),
       (select val from seed_m6 where cle = 'classe_10a'),
       (select val from seed_m6 where cle = 'matiere_math'),
       'enseignant'
on conflict (annee_scolaire_id, enseignant_profile_id, classe_id, programme_matiere_id) do nothing;

-- ---------------------------------------------------------------------------
-- Évaluations
-- ---------------------------------------------------------------------------
insert into public.evaluations
  (etablissement_id, annee_scolaire_id, periode_id, classe_id, programme_matiere_id,
   enseignant_profile_id, type, libelle, date_evaluation, coefficient, bareme, statut, publie_le)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'periode_t1'),
       (select val from seed_m6 where cle = 'classe_7a'),
       null,
       (select val from seed_m6 where cle = 'enseignant1'),
       'controle', 'Contrôle de calcul mental', '2026-11-10', 2, 20, 'publiee', now()
on conflict do nothing;

insert into public.evaluations
  (etablissement_id, annee_scolaire_id, periode_id, classe_id, programme_matiere_id,
   enseignant_profile_id, type, libelle, date_evaluation, coefficient, bareme, statut, publie_le)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'periode_t1'),
       (select val from seed_m6 where cle = 'classe_10a'),
       (select val from seed_m6 where cle = 'matiere_math'),
       (select val from seed_m6 where cle = 'enseignant2'),
       'controle', 'Contrôle n°1 — Mathématiques', '2026-11-12', 3, 20, 'publiee', now()
on conflict do nothing;

insert into public.evaluations
  (etablissement_id, annee_scolaire_id, periode_id, classe_id, programme_matiere_id,
   enseignant_profile_id, type, libelle, date_evaluation, coefficient, bareme, statut, publie_le)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'periode_t1'),
       (select val from seed_m6 where cle = 'classe_10a'),
       (select val from seed_m6 where cle = 'matiere_math'),
       (select val from seed_m6 where cle = 'enseignant2'),
       'devoir', 'Devoir maison — Mathématiques', '2026-10-28', 1, 20, 'publiee', now()
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Notes (une saisie hors-ligne pour Aïcha, deux en ligne pour Ibrahima)
-- ---------------------------------------------------------------------------
insert into public.notes
  (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par,
   saisi_hors_ligne, device_id, client_ts)
select (select val from seed_m6 where cle = 'etab'),
       e.id,
       (select val from seed_m6 where cle = 'fiche_aicha'),
       16.5,
       (select val from seed_m6 where cle = 'enseignant1'),
       true, 'seed-device-01', now()
from public.evaluations e
where e.classe_id = (select val from seed_m6 where cle = 'classe_7a')
  and e.libelle = 'Contrôle de calcul mental'
on conflict (evaluation_id, fiche_eleve_id) do nothing;

insert into public.notes
  (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
select (select val from seed_m6 where cle = 'etab'),
       e.id,
       (select val from seed_m6 where cle = 'fiche_ibrahima'),
       14.0,
       (select val from seed_m6 where cle = 'enseignant2')
from public.evaluations e
where e.classe_id = (select val from seed_m6 where cle = 'classe_10a')
  and e.libelle = 'Contrôle n°1 — Mathématiques'
on conflict (evaluation_id, fiche_eleve_id) do nothing;

insert into public.notes
  (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
select (select val from seed_m6 where cle = 'etab'),
       e.id,
       (select val from seed_m6 where cle = 'fiche_ibrahima'),
       17.0,
       (select val from seed_m6 where cle = 'enseignant2')
from public.evaluations e
where e.classe_id = (select val from seed_m6 where cle = 'classe_10a')
  and e.libelle = 'Devoir maison — Mathématiques'
on conflict (evaluation_id, fiche_eleve_id) do nothing;

-- ---------------------------------------------------------------------------
-- Appréciations (dont une matière, prête pour l'analyse sémantique)
-- ---------------------------------------------------------------------------
insert into public.appreciations
  (etablissement_id, fiche_eleve_id, annee_scolaire_id, periode_id, programme_matiere_id,
   type, texte, ton, redige_par)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'fiche_aicha'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'periode_t1'),
       null,
       'generale', 'Excellente progression, continuez ainsi.', 'positif',
       (select val from seed_m6 where cle = 'enseignant1')
on conflict do nothing;

insert into public.appreciations
  (etablissement_id, fiche_eleve_id, annee_scolaire_id, periode_id, programme_matiere_id,
   type, texte, ton, redige_par)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'fiche_ibrahima'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'periode_t1'),
       (select val from seed_m6 where cle = 'matiere_math'),
       'matiere', 'Des efforts à consolider en géométrie.', 'neutre',
       (select val from seed_m6 where cle = 'enseignant2')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Bulletin publié (snapshot signé) pour Aïcha — 1er trimestre
-- ---------------------------------------------------------------------------
insert into public.bulletins
  (etablissement_id, annee_scolaire_id, periode_id, classe_id, fiche_eleve_id,
   type, statut, contenu, signature_sha256, genere_le, publie_le)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'periode_t1'),
       (select val from seed_m6 where cle = 'classe_7a'),
       (select val from seed_m6 where cle = 'fiche_aicha'),
       'trimestriel', 'publie',
       '{"moyenne_generale": 16.5, "rang": 1, "effectif_classe": 15, "matieres": []}'::jsonb,
       'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
       now(), now()
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Statistiques & signaux IA (aides à la décision, jamais bloquants)
-- ---------------------------------------------------------------------------
insert into public.statistiques_agregats
  (etablissement_id, annee_scolaire_id, periode_id, classe_id, programme_matiere_id,
   fiche_eleve_id, type_agregat, valeur_numeric, valeur_jsonb)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'periode_t1'),
       (select val from seed_m6 where cle = 'classe_10a'),
       (select val from seed_m6 where cle = 'matiere_math'),
       (select val from seed_m6 where cle = 'fiche_ibrahima'),
       'moyenne_matiere', 15.5, null
on conflict do nothing;

insert into public.statistiques_agregats
  (etablissement_id, annee_scolaire_id, periode_id, classe_id,
   type_agregat, valeur_numeric)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'periode_t1'),
       (select val from seed_m6 where cle = 'classe_7a'),
       'moyenne_classe', 16.5
on conflict do nothing;

insert into public.statistiques_agregats
  (etablissement_id, annee_scolaire_id, periode_id, classe_id,
   fiche_eleve_id, type_agregat, valeur_numeric)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'periode_t1'),
       (select val from seed_m6 where cle = 'classe_7a'),
       (select val from seed_m6 where cle = 'fiche_aicha'),
       'risque_reussite', 0.08
on conflict do nothing;

insert into public.statistiques_agregats
  (etablissement_id, annee_scolaire_id, periode_id, classe_id, programme_matiere_id,
   fiche_eleve_id, type_agregat, valeur_jsonb)
select (select val from seed_m6 where cle = 'etab'),
       (select val from seed_m6 where cle = 'annee'),
       (select val from seed_m6 where cle = 'periode_t1'),
       (select val from seed_m6 where cle = 'classe_10a'),
       (select val from seed_m6 where cle = 'matiere_math'),
       (select val from seed_m6 where cle = 'fiche_ibrahima'),
       'recommandation_contenu',
       '{"lacunes": ["geometrie"], "ressources_m4": ["PC-10E-GEO-01"], "score_confiance": 0.82}'::jsonb
on conflict do nothing;

-- ============================================================================
-- Fin de la maquette M6.
-- ============================================================================
