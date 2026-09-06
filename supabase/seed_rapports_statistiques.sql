-- ============================================================================
-- EcoShop — M10 — Maquette de données Rapports & Statistiques académiques
--
-- S'appuie sur les seeds M0→M9 (établissement lycee-innovation-conakry,
-- année 2026-2027, classes 7A/10A, fiches MAT-2026-001/002, employés, paie,
-- notifications).
--
-- Crée : des indicateurs clés (KPI) de démonstration, deux demandes de
-- rapports (bulletin individuel, relevé de notes 7A), une anomalie
-- statistique et une recommandation stratégique.
--
-- Les fonctions IA (consolidation, détection, risque, recommandation, résumé)
-- sont exercées par les tests pgTAP (22-24), qui appellent ces fonctions avec
-- un contexte JWT authentifié.
--
-- Idempotent : recherches par clés naturelles + on conflict do nothing.
-- ============================================================================

create temp table if not exists seed_m10 (cle text primary key, val uuid);

-- ---------------------------------------------------------------------------
-- Référentiel partagé (mêmes clés naturelles que les seeds M5→M9)
-- ---------------------------------------------------------------------------
insert into seed_m10 (cle, val)
select 'etab', id from public.etablissements where slug = 'lycee-innovation-conakry'
on conflict (cle) do nothing;

insert into seed_m10 (cle, val)
select 'annee', id from public.annees_scolaires
where etablissement_id = (select val from seed_m10 where cle = 'etab') and libelle = '2026-2027'
on conflict (cle) do nothing;

insert into seed_m10 (cle, val)
select 'periode_t1', id from public.periodes_scolaires
where annee_scolaire_id = (select val from seed_m10 where cle = 'annee') and code = 'T1'
on conflict (cle) do nothing;

insert into seed_m10 (cle, val)
select 'classe_7a', id from public.classes
where annee_scolaire_id = (select val from seed_m10 where cle = 'annee') and code = '7A'
on conflict (cle) do nothing;

insert into seed_m10 (cle, val)
select 'fiche_aicha', id from public.fiches_eleves
where etablissement_id = (select val from seed_m10 where cle = 'etab') and matricule = 'MAT-2026-001'
on conflict (cle) do nothing;

insert into seed_m10 (cle, val)
select 'direction', p.id from public.profiles p
join public.identifiants_comptes i on i.profile_id = p.id
where i.valeur = '+224620001030'
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- 1. Indicateurs clés de démonstration (réels : recalculés par la fonction
--    consolider_indicateurs_etablissement, exercée dans les tests pgTAP).
-- ---------------------------------------------------------------------------
insert into public.indicateurs_cles
  (etablissement_id, annee_scolaire_id, code, valeur_numeric, calcule_le)
select (select val from seed_m10 where cle = 'etab'),
       (select val from seed_m10 where cle = 'annee'),
       'effectifs', 15, now()
on conflict (etablissement_id, annee_scolaire_id, code)
  where periode_id is null and classe_id is null do nothing;

insert into public.indicateurs_cles
  (etablissement_id, annee_scolaire_id, code, valeur_numeric, calcule_le)
select (select val from seed_m10 where cle = 'etab'),
       (select val from seed_m10 where cle = 'annee'),
       'taux_reussite', 0.88, now()
on conflict (etablissement_id, annee_scolaire_id, code)
  where periode_id is null and classe_id is null do nothing;

insert into public.indicateurs_cles
  (etablissement_id, annee_scolaire_id, code, valeur_numeric, calcule_le)
select (select val from seed_m10 where cle = 'etab'),
       (select val from seed_m10 where cle = 'annee'),
       'absentisme', 0.12, now()
on conflict (etablissement_id, annee_scolaire_id, code)
  where periode_id is null and classe_id is null do nothing;

insert into public.indicateurs_cles
  (etablissement_id, annee_scolaire_id, code, valeur_numeric, calcule_le)
select (select val from seed_m10 where cle = 'etab'),
       (select val from seed_m10 where cle = 'annee'),
       'turnover', 0.05, now()
on conflict (etablissement_id, annee_scolaire_id, code)
  where periode_id is null and classe_id is null do nothing;

insert into public.indicateurs_cles
  (etablissement_id, annee_scolaire_id, code, valeur_numeric, calcule_le)
select (select val from seed_m10 where cle = 'etab'),
       (select val from seed_m10 where cle = 'annee'),
       'masse_salariale', 4500000, now()
on conflict (etablissement_id, annee_scolaire_id, code)
  where periode_id is null and classe_id is null do nothing;

insert into public.indicateurs_cles
  (etablissement_id, annee_scolaire_id, code, valeur_numeric, calcule_le)
select (select val from seed_m10 where cle = 'etab'),
       (select val from seed_m10 where cle = 'annee'),
       'engagement_parents', 0.64, now()
on conflict (etablissement_id, annee_scolaire_id, code)
  where periode_id is null and classe_id is null do nothing;

-- ---------------------------------------------------------------------------
-- 2. Demandes de rapports (génération différée)
-- ---------------------------------------------------------------------------
insert into public.rapports
  (etablissement_id, annee_scolaire_id, periode_id, classe_id, fiche_eleve_id,
   type, format, filtres, statut, genere_par, genere_le, demande_hors_ligne, cache_valide_jus)
select (select val from seed_m10 where cle = 'etab'),
       (select val from seed_m10 where cle = 'annee'),
       (select val from seed_m10 where cle = 'periode_t1'),
       (select val from seed_m10 where cle = 'classe_7a'),
       (select val from seed_m10 where cle = 'fiche_aicha'),
       'bulletin', 'pdf',
       '{"periodes": ["T1"], "options": {"signature": true}}'::jsonb,
       'genere',
       (select val from seed_m10 where cle = 'direction'),
       now(),
       true, (current_date + interval '30 days')::date
where not exists (
  select 1 from public.rapports r
  where r.etablissement_id = (select val from seed_m10 where cle = 'etab')
    and r.fiche_eleve_id = (select val from seed_m10 where cle = 'fiche_aicha')
    and r.type = 'bulletin'
);

insert into public.rapports
  (etablissement_id, annee_scolaire_id, periode_id, classe_id,
   type, format, filtres, statut, genere_par, demande_hors_ligne)
select (select val from seed_m10 where cle = 'etab'),
       (select val from seed_m10 where cle = 'annee'),
       (select val from seed_m10 where cle = 'periode_t1'),
       (select val from seed_m10 where cle = 'classe_7a'),
       'releve_notes', 'excel',
       '{"periodes": ["T1"], "tri": "matiere"}'::jsonb,
       'demande',
       (select val from seed_m10 where cle = 'direction'),
       true
where not exists (
  select 1 from public.rapports r
  where r.etablissement_id = (select val from seed_m10 where cle = 'etab')
    and r.classe_id = (select val from seed_m10 where cle = 'classe_7a')
    and r.type = 'releve_notes'
);

-- ---------------------------------------------------------------------------
-- 3. Anomalie statistique de démonstration (note aberrante, à valider)
-- ---------------------------------------------------------------------------
insert into public.anomalies_statistiques
  (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, type, severite,
   description, valeur_observee, valeur_attendue, ecart, contexte, signature, statut, detectee_le)
select (select val from seed_m10 where cle = 'etab'),
       (select val from seed_m10 where cle = 'annee'),
       (select val from seed_m10 where cle = 'classe_7a'),
       (select val from seed_m10 where cle = 'fiche_aicha'),
       'note', 'moyenne',
       'Note aberrante détectée : écart > 2 écarts-types à la moyenne de l''évaluation (maquette).',
       19.0, 12.5, 6.5,
       '{"evaluation": "maquette-controle", "moyenne": 12.5, "ecart_type": 2.1, "bareme": 20}'::jsonb,
       md5((select val from seed_m10 where cle = 'annee')::text || ':demo:note:maquette'),
       'ouverte', now()
on conflict (etablissement_id, signature) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Recommandation stratégique de démonstration
-- ---------------------------------------------------------------------------
insert into public.recommandations_strategiques
  (etablissement_id, annee_scolaire_id, classe_id, type, titre, description,
   justification, priorite, statut, cree_le)
select (select val from seed_m10 where cle = 'etab'),
       (select val from seed_m10 where cle = 'annee'),
       (select val from seed_m10 where cle = 'classe_7a'),
       'renforcement', 'Renforcement pédagogique de la classe 7A',
       'Consolider les acquis en calcul et surveiller l''assiduité (maquette).',
       '{"score_risque": 0.42, "source": "maquette"}'::jsonb,
       'moyenne', 'proposee', now()
on conflict (etablissement_id, annee_scolaire_id, classe_id, type)
  where classe_id is not null do nothing;

-- ============================================================================
-- Fin de la maquette M10.
-- ============================================================================
