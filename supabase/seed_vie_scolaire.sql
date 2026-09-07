-- ============================================================================
-- EcoShop — M7 — Maquette de données Absences & Vie scolaire
--
-- S'appuie sur les seeds M5 (classe 7A/10A, fiches MAT-2026-001/002,
-- enseignant1 titulaire 7A) et M6 (moyennes). Crée : pointages (présences),
-- retards, une sanction humaine et une sanction recommandée par IA (non
-- validée), des événements scolaires, puis génère l'alerte décrochage via la
-- fonction serveur generer_alertes_decrochage().
--
-- Idempotent : on conflict do nothing + clés naturelles.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Helper : retrouver un compte existant par téléphone
-- ---------------------------------------------------------------------------
create or replace function pg_temp.trouver_compte(p_phone text)
returns uuid
language sql
set search_path = public, pg_catalog
as $$
  select p.id
  from public.profiles p
  join public.identifiants_comptes i on i.profile_id = p.id
  where i.valeur = p_phone
  limit 1;
$$;

create temp table if not exists seed_m7 (cle text primary key, val uuid);

insert into seed_m7 (cle, val)
select 'etab', id from public.etablissements where slug = 'lycee-innovation-conakry'
on conflict (cle) do nothing;

insert into seed_m7 (cle, val)
select 'annee', id from public.annees_scolaires
where etablissement_id = (select val from seed_m7 where cle = 'etab') and libelle = '2026-2027'
on conflict (cle) do nothing;

insert into seed_m7 (cle, val)
select 'classe_7a', id from public.classes
where annee_scolaire_id = (select val from seed_m7 where cle = 'annee') and code = '7A'
on conflict (cle) do nothing;

insert into seed_m7 (cle, val)
select 'classe_10a', id from public.classes
where annee_scolaire_id = (select val from seed_m7 where cle = 'annee') and code = '10A'
on conflict (cle) do nothing;

insert into seed_m7 (cle, val)
select 'fiche_aicha', id from public.fiches_eleves
where etablissement_id = (select val from seed_m7 where cle = 'etab') and matricule = 'MAT-2026-001'
on conflict (cle) do nothing;

insert into seed_m7 (cle, val)
select 'fiche_ibrahima', id from public.fiches_eleves
where etablissement_id = (select val from seed_m7 where cle = 'etab') and matricule = 'MAT-2026-002'
on conflict (cle) do nothing;

insert into seed_m7 (cle, val)
select 'enseignant1', pg_temp.trouver_compte('+224620001020')
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- Présences : Aïcha (7A) en difficulté d'assiduité, Ibrahima (10A) assidu
-- ---------------------------------------------------------------------------
insert into public.presences
  (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
select (select val from seed_m7 where cle = 'etab'),
       (select val from seed_m7 where cle = 'annee'),
       (select val from seed_m7 where cle = 'classe_7a'),
       (select val from seed_m7 where cle = 'fiche_aicha'),
       (date '2026-10-05' + n::int),
       'demi_journee',
       (case when (n % 2) = 0 then 'absent' else 'present' end)::public.statut_presence,
       false,
       (select val from seed_m7 where cle = 'enseignant1')
from generate_series(0, 7) as n
on conflict do nothing;

insert into public.presences
  (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
select (select val from seed_m7 where cle = 'etab'),
       (select val from seed_m7 where cle = 'annee'),
       (select val from seed_m7 where cle = 'classe_10a'),
       (select val from seed_m7 where cle = 'fiche_ibrahima'),
       (date '2026-10-05' + n::int),
       'demi_journee',
       'present',
       false,
       (select val from seed_m7 where cle = 'enseignant1')
from generate_series(0, 2) as n
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Retards : Aïcha, trois retards non justifiés
-- ---------------------------------------------------------------------------
insert into public.retards
  (etablissement_id, fiche_eleve_id, annee_scolaire_id, date_retard, minutes_retard, justifie, saisi_par)
select (select val from seed_m7 where cle = 'etab'),
       (select val from seed_m7 where cle = 'fiche_aicha'),
       (select val from seed_m7 where cle = 'annee'),
       v.d,
       v.minutes,
       false,
       (select val from seed_m7 where cle = 'enseignant1')
from (values
  (date '2026-10-12', 10),
  (date '2026-10-19', 15),
  (date '2026-10-26', 20)
) as v(d, minutes)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Sanctions : une humaine (notifiée), une recommandée par IA (non validée)
-- ---------------------------------------------------------------------------
insert into public.sanctions
  (etablissement_id, fiche_eleve_id, annee_scolaire_id, type_sanction, motif,
   contexte_educatif, date_debut, decisionnaire_id, origine, statut)
select (select val from seed_m7 where cle = 'etab'),
       (select val from seed_m7 where cle = 'fiche_aicha'),
       (select val from seed_m7 where cle = 'annee'),
       'avertissement', 'Retards répétés', 'Rappel du règlement intérieur',
       date '2026-11-02',
       (select val from seed_m7 where cle = 'enseignant1'),
       'humaine', 'notifiee'
on conflict do nothing;

insert into public.sanctions
  (etablissement_id, fiche_eleve_id, annee_scolaire_id, type_sanction, motif,
   contexte_educatif, date_debut, decisionnaire_id, origine, recommandation_ia, statut)
select (select val from seed_m7 where cle = 'etab'),
       (select val from seed_m7 where cle = 'fiche_aicha'),
       (select val from seed_m7 where cle = 'annee'),
       'entretien_famille_et_tutorat', 'Absences répétées non justifiées',
       'Proposition issue du moteur de recommandation éducative',
       date '2026-11-05',
       (select val from seed_m7 where cle = 'enseignant1'),
       'ia',
       public.recommander_sanction_educative(
         (select val from seed_m7 where cle = 'fiche_aicha'),
         (select val from seed_m7 where cle = 'annee')
       ),
       'proposee'
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Événements scolaires (calendrier, grève, férié)
-- ---------------------------------------------------------------------------
insert into public.evenements_scolaires
  (etablissement_id, annee_scolaire_id, type, libelle, date_debut, date_fin, impact_presence)
select (select val from seed_m7 where cle = 'etab'),
       (select val from seed_m7 where cle = 'annee'),
       v.type::public.type_evenement, v.libelle, v.debut, v.fin, v.impact
from (values
  ('ferie',      'Fête de l''indépendance',  date '2026-10-02', date '2026-10-02', 0.5),
  ('greve',      'Journée de grève',          date '2026-10-15', date '2026-10-15', 0.3),
  ('vacances',   'Vacances de Noël',          date '2026-12-24', date '2027-01-04', 0.0)
) as v(type, libelle, debut, fin, impact)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Génération des alertes décrochage (seuil 0.4) puis transmission à la famille
-- ---------------------------------------------------------------------------
select public.generer_alertes_decrochage(
  (select val from seed_m7 where cle = 'etab'),
  (select val from seed_m7 where cle = 'annee'),
  0.4
);

update public.alertes_decrochage
set statut = 'transmise', transmise_le = now()
where fiche_eleve_id = (select val from seed_m7 where cle = 'fiche_aicha')
  and annee_scolaire_id = (select val from seed_m7 where cle = 'annee')
  and statut = 'ouverte';

-- ============================================================================
-- Fin de la maquette M7.
-- ============================================================================
