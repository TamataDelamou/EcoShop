-- ============================================================================
-- EcoShop — M4 — Maquette de démonstration du référentiel pédagogique
--
-- Les systèmes, pays, cycles, niveaux et examens (Guinée, Sénégal, Ghana)
-- sont des données de référence : ils sont livrés en production par la
-- migration 20260906001560_referentiel_production.sql. Ce fichier ne garde
-- que des exemples incomplets, réservés au développement : quelques filières,
-- un programme officiel par pays et ses matières (coefficients et volumes
-- d'illustration).
--
-- Idempotent : clés naturelles + on conflict do nothing.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Filières (séries du secondaire)
-- ---------------------------------------------------------------------------
insert into public.filieres_educatives
  (id, pays_code, niveau_id, code, nom, description, statut)
select gen_random_uuid(), v.pays, n.id, v.code, v.nom, v.description, 'publie'
from (values
  ('GN','Terminale','SM','Sciences Mathématiques','Série scientifique dominante mathématiques'),
  ('GN','Terminale','SExp','Sciences Expérimentales','Série scientifique dominante sciences expérimentales'),
  ('GN','Terminale','SS','Sciences Sociales','Série littéraire et sciences sociales'),
  ('SN','1ere','L','Littéraire','Série littéraire'),
  ('SN','1ere','S','Scientifique','Série scientifique'),
  ('GH','SHS1','GEN_SCI','General Science','Sciences générales'),
  ('GH','SHS1','GEN_ART','General Arts','Lettres et sciences humaines'),
  ('GH','SHS1','BUSINESS','Business','Économie, comptabilité et gestion')
) as v(pays, niveau, code, nom, description)
join public.niveaux_educatifs n on n.pays_code = v.pays and n.code = v.niveau
on conflict (pays_code, code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Programmes officiels (un programme représentatif par pays)
-- ---------------------------------------------------------------------------
insert into public.programmes_officiels
  (id, pays_code, niveau_id, code, nom, annee_scolaire, version, statut)
select gen_random_uuid(), v.pays, n.id, v.code, v.nom, '2026-2027', 1, 'publie'
from (values
  ('GN','10e','PROG-GN-10E','Programme officiel 10e (Guinée)'),
  ('SN','3e','PROG-SN-3E','Programme officiel 3e (Sénégal)'),
  ('GH','JHS3','BECE-CURR','BECE Curriculum (Ghana)')
) as v(pays, niveau, code, nom)
join public.niveaux_educatifs n on n.pays_code = v.pays and n.code = v.niveau
on conflict (pays_code, code, version) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Matières par programme
-- ---------------------------------------------------------------------------
insert into public.programmes_matieres
  (id, programme_id, code, nom, coefficient, volume_horaire_annuel, ordre, statut)
select gen_random_uuid(), p.id, v.code, v.nom, v.coef, v.volume, v.ordre, 'publie'
from (values
  ('GN','PROG-GN-10E','FR','Français', 3, 120, 1),
  ('GN','PROG-GN-10E','MATH','Mathématiques', 3, 120, 2),
  ('GN','PROG-GN-10E','PC','Physique-Chimie', 2, 80, 3),
  ('GN','PROG-GN-10E','ANG','Anglais', 1, 60, 4),
  ('SN','PROG-SN-3E','FR','Français', 3, 120, 1),
  ('SN','PROG-SN-3E','MATH','Mathématiques', 3, 120, 2),
  ('SN','PROG-SN-3E','SVT','Sciences de la Vie et de la Terre', 2, 80, 3),
  ('SN','PROG-SN-3E','HG','Histoire-Géographie', 2, 80, 4),
  ('GH','BECE-CURR','ENG','English Language', 2, 100, 1),
  ('GH','BECE-CURR','MATH','Mathematics', 2, 100, 2),
  ('GH','BECE-CURR','SCI','Integrated Science', 2, 100, 3),
  ('GH','BECE-CURR','SST','Social Studies', 1, 80, 4)
) as v(pays, programme, code, nom, coef, volume, ordre)
join public.programmes_officiels p on p.pays_code = v.pays and p.code = v.programme
on conflict (programme_id, code) do nothing;

-- ============================================================================
-- Fin de la maquette M4.
-- ============================================================================
