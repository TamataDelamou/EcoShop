-- ============================================================================
-- EcoShop — M4 — Maquette de données du référentiel pédagogique CEDEAO
--
-- 3 pays tests couvrant 2 systèmes : Guinée & Sénégal (francophone_cfa),
-- Ghana (anglophone_waec). Le grade_level_normalise rend la comparaison
-- inter-pays possible (Terminale GN = Terminale SN = SHS3 GH, grade 12/13).
--
-- Idempotent : chaque insertion s'appuie sur des clés naturelles
-- (pays_code + code) et ignore les doublons.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Systèmes éducatifs
-- ---------------------------------------------------------------------------
insert into public.systemes_educatifs (code, nom, description) values
  ('francophone_cfa',  'Francophone (CFA)', 'Systèmes francophones de la zone CFA : BEPC/BAC, CFEE/BFEM/DEF'),
  ('anglophone_waec',  'Anglophone (WAEC)', 'Systèmes anglophones adossés au WAEC : BECE/WASSCE'),
  ('lusophone',        'Lusophone',         'Systèmes lusophones (Guinée-Bissau, Cap-Vert)'),
  ('arabophone_mixte', 'Arabophone / mixte','Systèmes arabophones ou mixtes (Mauritanie)')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Pays
-- ---------------------------------------------------------------------------
insert into public.pays_pedagogiques
  (code_iso, nom, type_systeme, langue_enseignement_principale, organisme_examinateur, devise_code, statut_deploiement)
values
  ('GN', 'Guinée',  'francophone_cfa', 'français', 'Ministère de l''Enseignement Pré-Universitaire', 'GNF', 'deploye'),
  ('SN', 'Sénégal', 'francophone_cfa', 'français', 'Office du Bac / Ministère de l''Éducation nationale', 'XOF', 'deploye'),
  ('GH', 'Ghana',   'anglophone_waec', 'anglais',  'WAEC (West African Examinations Council)', 'GHS', 'deploye')
on conflict (code_iso) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Cycles
-- ---------------------------------------------------------------------------
insert into public.cycles_educatifs
  (id, pays_code, code, nom, ordre, age_min, age_max, duree_annees, isced_min, isced_max, statut)
select gen_random_uuid(), v.pays, v.code, v.nom, v.ordre, v.age_min, v.age_max, v.duree, v.isc_min, v.isc_max, 'publie'
from (values
  ('GN','primaire',    'Primaire',     1, 6, 11, 6, 1, 1),
  ('GN','college',     'Collège',      2, 12, 15, 4, 2, 2),
  ('GN','lycee',       'Lycée',        3, 16, 18, 3, 3, 3),
  ('SN','primaire',    'Primaire',     1, 6, 11, 6, 1, 1),
  ('SN','moyen',       'Moyen',        2, 12, 15, 4, 2, 2),
  ('SN','secondaire',  'Secondaire',   3, 16, 18, 3, 3, 3),
  ('GH','primary',     'Primary',      1, 6, 11, 6, 1, 1),
  ('GH','junior_high', 'Junior High',  2, 12, 14, 3, 2, 2),
  ('GH','senior_high', 'Senior High',  3, 15, 17, 3, 3, 3)
) as v(pays, code, nom, ordre, age_min, age_max, duree, isc_min, isc_max)
on conflict (pays_code, code) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Niveaux (grade_level_normalise continu par pays)
-- ---------------------------------------------------------------------------
insert into public.niveaux_educatifs
  (id, cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre, statut)
select gen_random_uuid(), c.id, v.pays, v.code, v.nom, v.grade, v.isced, v.ordre, 'publie'
from (values
  -- Guinée : primaire (1-6), collège (7-10), lycée (11-13)
  ('GN','primaire','CP1','Cours Préparatoire 1ère année', 1, 1, 1),
  ('GN','primaire','CP2','Cours Préparatoire 2ème année', 2, 1, 2),
  ('GN','primaire','CE1','Cours Élémentaire 1ère année', 3, 1, 3),
  ('GN','primaire','CE2','Cours Élémentaire 2ème année', 4, 1, 4),
  ('GN','primaire','CM1','Cours Moyen 1ère année', 5, 1, 5),
  ('GN','primaire','CM2','Cours Moyen 2ème année', 6, 1, 6),
  ('GN','college','7e','Septième année', 7, 2, 1),
  ('GN','college','8e','Huitième année', 8, 2, 2),
  ('GN','college','9e','Neuvième année', 9, 2, 3),
  ('GN','college','10e','Dixième année', 10, 2, 4),
  ('GN','lycee','11e','Onzième année', 11, 3, 1),
  ('GN','lycee','12e','Douzième année', 12, 3, 2),
  ('GN','lycee','Terminale','Terminale', 13, 3, 3),
  -- Sénégal : primaire (1-6), moyen (7-10), secondaire (11-13)
  ('SN','primaire','CI','Cours d''Initiation', 1, 1, 1),
  ('SN','primaire','CP','Cours Préparatoire', 2, 1, 2),
  ('SN','primaire','CE1','Cours Élémentaire 1ère année', 3, 1, 3),
  ('SN','primaire','CE2','Cours Élémentaire 2ème année', 4, 1, 4),
  ('SN','primaire','CM1','Cours Moyen 1ère année', 5, 1, 5),
  ('SN','primaire','CM2','Cours Moyen 2ème année', 6, 1, 6),
  ('SN','moyen','6e','Sixième', 7, 2, 1),
  ('SN','moyen','5e','Cinquième', 8, 2, 2),
  ('SN','moyen','4e','Quatrième', 9, 2, 3),
  ('SN','moyen','3e','Troisième', 10, 2, 4),
  ('SN','secondaire','2nde','Seconde', 11, 3, 1),
  ('SN','secondaire','1ere','Première', 12, 3, 2),
  ('SN','secondaire','Terminale','Terminale', 13, 3, 3),
  -- Ghana : primary (1-6), JHS (7-9), SHS (10-12)
  ('GH','primary','P1','Primary 1', 1, 1, 1),
  ('GH','primary','P2','Primary 2', 2, 1, 2),
  ('GH','primary','P3','Primary 3', 3, 1, 3),
  ('GH','primary','P4','Primary 4', 4, 1, 4),
  ('GH','primary','P5','Primary 5', 5, 1, 5),
  ('GH','primary','P6','Primary 6', 6, 1, 6),
  ('GH','junior_high','JHS1','Junior High School 1', 7, 2, 1),
  ('GH','junior_high','JHS2','Junior High School 2', 8, 2, 2),
  ('GH','junior_high','JHS3','Junior High School 3', 9, 2, 3),
  ('GH','senior_high','SHS1','Senior High School 1', 10, 3, 1),
  ('GH','senior_high','SHS2','Senior High School 2', 11, 3, 2),
  ('GH','senior_high','SHS3','Senior High School 3', 12, 3, 3)
) as v(pays, cycle, code, nom, grade, isced, ordre)
join public.cycles_educatifs c on c.pays_code = v.pays and c.code = v.cycle
on conflict (pays_code, code) do nothing;

-- ---------------------------------------------------------------------------
-- 5. Examens nationaux
-- ---------------------------------------------------------------------------
insert into public.examens_nationaux
  (id, pays_code, cycle_id, code, nom, organisme, mois_session, periodicite, statut)
select gen_random_uuid(), v.pays, c.id, v.code, v.nom, v.organisme, v.mois, v.periode, 'publie'
from (values
  ('GN','primaire','CEE','Certificat d''Études Élémentaires','Ministère',6,'annuelle'),
  ('GN','college','BEPC','Brevet d''Études du Premier Cycle','Ministère',6,'annuelle'),
  ('GN','lycee','BAC','Baccalauréat unique','Ministère',6,'annuelle'),
  ('SN','primaire','CFEE','Certificat de Fin d''Études Élémentaires','Ministère',6,'annuelle'),
  ('SN','moyen','BFEM','Brevet de Fin d''Études Moyennes','Office du Bac',7,'annuelle'),
  ('SN','secondaire','BAC','Baccalauréat','Office du Bac',7,'annuelle'),
  ('GH','junior_high','BECE','Basic Education Certificate Examination','WAEC',6,'annuelle'),
  ('GH','senior_high','WASSCE','West African Senior School Certificate Examination','WAEC',8,'annuelle')
) as v(pays, cycle, code, nom, organisme, mois, periode)
join public.cycles_educatifs c on c.pays_code = v.pays and c.code = v.cycle
on conflict (pays_code, code) do nothing;

-- ---------------------------------------------------------------------------
-- 6. Filières (séries du secondaire)
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
-- 7. Programmes officiels (un programme représentatif par pays)
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
-- 8. Matières par programme
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
