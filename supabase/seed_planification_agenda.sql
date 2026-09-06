-- ============================================================================
-- EcoShop — M11 — Maquette de données Planification & Agenda
--
-- S'appuie sur les seeds M0→M10 (établissement lycee-innovation-conakry,
-- année 2026-2027, classes 7A/10A, enseignants +224620001020/+224620001021).
--
-- Crée : 3 salles, 3 créneaux d'emploi du temps, 3 événements d'agenda,
-- 1 séance de progression et 1 contrainte d'indisponibilité.
--
-- Les fonctions IA (placement, conflits, charge, recommandation) sont exercées
-- par les tests pgTAP (26).
--
-- Idempotent : recherches par clés naturelles + on conflict do nothing.
-- ============================================================================

create temp table if not exists seed_m11 (cle text primary key, val uuid);

-- ---------------------------------------------------------------------------
-- Référentiel partagé (mêmes clés naturelles que les seeds M5→M10)
-- ---------------------------------------------------------------------------
insert into seed_m11 (cle, val)
select 'etab', id from public.etablissements where slug = 'lycee-innovation-conakry'
on conflict (cle) do nothing;

insert into seed_m11 (cle, val)
select 'annee', id from public.annees_scolaires
where etablissement_id = (select val from seed_m11 where cle = 'etab') and libelle = '2026-2027'
on conflict (cle) do nothing;

insert into seed_m11 (cle, val)
select 'classe_7a', id from public.classes
where annee_scolaire_id = (select val from seed_m11 where cle = 'annee') and code = '7A'
on conflict (cle) do nothing;

insert into seed_m11 (cle, val)
select 'classe_10a', id from public.classes
where annee_scolaire_id = (select val from seed_m11 where cle = 'annee') and code = '10A'
on conflict (cle) do nothing;

insert into seed_m11 (cle, val)
select 'ens1', p.id from public.profiles p
join public.identifiants_comptes i on i.profile_id = p.id
where i.valeur = '+224620001020'
on conflict (cle) do nothing;

insert into seed_m11 (cle, val)
select 'ens2', p.id from public.profiles p
join public.identifiants_comptes i on i.profile_id = p.id
where i.valeur = '+224620001021'
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- 1. Salles
-- ---------------------------------------------------------------------------
insert into public.salles (etablissement_id, code, nom, capacite)
select (select val from seed_m11 where cle = 'etab'), 'SALLE-A', 'Salle A', 30
on conflict (etablissement_id, code) do nothing;

insert into public.salles (etablissement_id, code, nom, capacite)
select (select val from seed_m11 where cle = 'etab'), 'SALLE-B', 'Salle B', 25
on conflict (etablissement_id, code) do nothing;

insert into public.salles (etablissement_id, code, nom, capacite)
select (select val from seed_m11 where cle = 'etab'), 'LABO', 'Laboratoire', 20
on conflict (etablissement_id, code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Emplois du temps (créneaux hebdomadaires)
-- ---------------------------------------------------------------------------
insert into public.emplois_du_temps
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, salle_id,
   jour_semaine, heure_debut, heure_fin, type)
select (select val from seed_m11 where cle = 'etab'),
       (select val from seed_m11 where cle = 'annee'),
       (select val from seed_m11 where cle = 'classe_7a'),
       (select val from seed_m11 where cle = 'ens1'),
       s.id, 1, '08:00', '09:00', 'cours'
from public.salles s
where s.etablissement_id = (select val from seed_m11 where cle = 'etab') and s.code = 'SALLE-A'
on conflict (etablissement_id, annee_scolaire_id, classe_id, jour_semaine, heure_debut, heure_fin) do nothing;

insert into public.emplois_du_temps
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, salle_id,
   jour_semaine, heure_debut, heure_fin, type)
select (select val from seed_m11 where cle = 'etab'),
       (select val from seed_m11 where cle = 'annee'),
       (select val from seed_m11 where cle = 'classe_7a'),
       (select val from seed_m11 where cle = 'ens1'),
       s.id, 2, '10:00', '11:00', 'cours'
from public.salles s
where s.etablissement_id = (select val from seed_m11 where cle = 'etab') and s.code = 'SALLE-B'
on conflict (etablissement_id, annee_scolaire_id, classe_id, jour_semaine, heure_debut, heure_fin) do nothing;

insert into public.emplois_du_temps
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, salle_id,
   jour_semaine, heure_debut, heure_fin, type)
select (select val from seed_m11 where cle = 'etab'),
       (select val from seed_m11 where cle = 'annee'),
       (select val from seed_m11 where cle = 'classe_10a'),
       (select val from seed_m11 where cle = 'ens2'),
       s.id, 3, '08:00', '09:00', 'cours'
from public.salles s
where s.etablissement_id = (select val from seed_m11 where cle = 'etab') and s.code = 'SALLE-A'
on conflict (etablissement_id, annee_scolaire_id, classe_id, jour_semaine, heure_debut, heure_fin) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Événements d'agenda
-- ---------------------------------------------------------------------------
insert into public.evenements_agenda
  (etablissement_id, annee_scolaire_id, classe_id, titre, type, date_debut, date_fin, heure_debut, heure_fin, lieu, rappel)
select (select val from seed_m11 where cle = 'etab'),
       (select val from seed_m11 where cle = 'annee'),
       (select val from seed_m11 where cle = 'classe_7a'),
       'Conseil de classe 7A', 'conseil_classe', '2026-11-15', '2026-11-15', '15:00', '16:00', 'Salle des profs', true
where not exists (
  select 1 from public.evenements_agenda e
  where e.etablissement_id = (select val from seed_m11 where cle = 'etab')
    and e.classe_id = (select val from seed_m11 where cle = 'classe_7a')
    and e.titre = 'Conseil de classe 7A'
);

insert into public.evenements_agenda
  (etablissement_id, annee_scolaire_id, classe_id, titre, type, date_debut, date_fin, rappel)
select (select val from seed_m11 where cle = 'etab'),
       (select val from seed_m11 where cle = 'annee'),
       (select val from seed_m11 where cle = 'classe_10a'),
       'Examen blanc', 'examen', '2026-12-01', '2026-12-03', true
where not exists (
  select 1 from public.evenements_agenda e
  where e.etablissement_id = (select val from seed_m11 where cle = 'etab')
    and e.classe_id = (select val from seed_m11 where cle = 'classe_10a')
    and e.titre = 'Examen blanc'
);

insert into public.evenements_agenda
  (etablissement_id, annee_scolaire_id, titre, type, date_debut, date_fin, heure_debut, heure_fin, lieu)
select (select val from seed_m11 where cle = 'etab'),
       (select val from seed_m11 where cle = 'annee'),
       'Réunion de rentrée', 'reunion', '2026-10-05', '2026-10-05', '09:00', '10:30', 'Salle A'
where not exists (
  select 1 from public.evenements_agenda e
  where e.etablissement_id = (select val from seed_m11 where cle = 'etab')
    and e.titre = 'Réunion de rentrée'
);

-- ---------------------------------------------------------------------------
-- 4. Progression pédagogique
-- ---------------------------------------------------------------------------
insert into public.progression_pedagogique
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, seance, objectifs, statut, date_prevue)
select (select val from seed_m11 where cle = 'etab'),
       (select val from seed_m11 where cle = 'annee'),
       (select val from seed_m11 where cle = 'classe_7a'),
       (select val from seed_m11 where cle = 'ens1'),
       'Séance 1 — Calcul littéral', 'Introduire les expressions algébriques', 'planifiee', '2026-10-12'
where not exists (
  select 1 from public.progression_pedagogique p
  where p.etablissement_id = (select val from seed_m11 where cle = 'etab')
    and p.classe_id = (select val from seed_m11 where cle = 'classe_7a')
    and p.seance = 'Séance 1 — Calcul littéral'
);

-- ---------------------------------------------------------------------------
-- 5. Contraintes de planification
-- ---------------------------------------------------------------------------
insert into public.contraintes_emploi
  (etablissement_id, annee_scolaire_id, enseignant_profile_id, jour_semaine, heure_debut, heure_fin, type, raison)
select (select val from seed_m11 where cle = 'etab'),
       (select val from seed_m11 where cle = 'annee'),
       (select val from seed_m11 where cle = 'ens2'),
       5, '08:00', '10:00', 'indisponibilite_enseignant', 'Réunion pédagogique hebdomadaire'
where not exists (
  select 1 from public.contraintes_emploi c
  where c.etablissement_id = (select val from seed_m11 where cle = 'etab')
    and c.enseignant_profile_id = (select val from seed_m11 where cle = 'ens2')
    and c.jour_semaine = 5
);

-- ============================================================================
-- Fin de la maquette M11.
-- ============================================================================
