-- ============================================================================
-- EcoShop — Seed de développement (M0 → M2)
--
-- Données de démonstration uniquement. Le catalogue de permissions n'est pas
-- ici : c'est une donnée de référence, livrée par la migration M1.
--
-- Les profils sont créés par le trigger handle_new_user à l'inscription : ce
-- seed ne fabrique aucun compte, il prépare l'environnement qui les accueille.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Paramètres globaux — aucune valeur métier codée en dur côté client
-- ---------------------------------------------------------------------------
insert into public.parametres_globaux (cle, valeur, description) values
  ('seuil_effectif_gratuit',     '{"valeur": 100}',   'Effectif en deçà duquel la licence de base est gratuite'),
  ('commission_marketplace_pct', '{"valeur": 3}',     'Commission GSG sur chaque vente marketplace (jamais sur la scolarité)'),
  ('devise_defaut',              '{"valeur": "GNF"}', 'Devise par défaut des établissements'),
  ('liaison_tentatives_max',     '{"valeur": 5}',     'Tentatives de liaison compte↔fiche par heure'),
  ('invitation_validite_jours',  '{"valeur": 14}',    'Durée de validité d''une invitation')
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- Établissements de démonstration
-- ---------------------------------------------------------------------------
insert into public.etablissements (nom, slug, pays_code, ville) values
  ('Lycée Innovation Conakry', 'lycee-innovation-conakry', 'GN', 'Conakry'),
  ('Collège Énergie Labé',     'college-energie-labe',     'GN', 'Labé')
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------------
-- Unités opérationnelles
-- ---------------------------------------------------------------------------
insert into public.unites_operationnelles (etablissement_id, code, nom, adresse)
select e.id, u.code, u.nom, u.adresse
from public.etablissements e
join (values
  ('lycee-innovation-conakry', 'PRINCIPAL', 'Campus principal', 'Kaloum, Conakry'),
  ('lycee-innovation-conakry', 'ANNEXE-R',  'Annexe Ratoma',    'Ratoma, Conakry'),
  ('college-energie-labe',     'PRINCIPAL', 'Campus principal', 'Centre, Labé')
) as u(slug, code, nom, adresse) on u.slug = e.slug
on conflict (etablissement_id, code) do nothing;

-- ---------------------------------------------------------------------------
-- Années scolaires — une seule courante par établissement (index unique partiel)
-- ---------------------------------------------------------------------------
insert into public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
select e.id, a.libelle, a.debut::date, a.fin::date, a.courante
from public.etablissements e
join (values
  ('2025-2026', '2025-09-15', '2026-07-10', false),
  ('2026-2027', '2026-09-14', '2027-07-09', true)
) as a(libelle, debut, fin, courante) on true
on conflict (etablissement_id, libelle) do nothing;

-- ---------------------------------------------------------------------------
-- Postes déclarés et leurs permissions (modèle de rôles à deux niveaux, ch. 4)
-- ---------------------------------------------------------------------------
insert into public.postes (etablissement_id, code, nom, description)
select e.id, p.code, p.nom, p.description
from public.etablissements e
join (values
  ('PROVISEUR',  'Proviseur',            'Direction de l''établissement — permissions étendues.'),
  ('SECRETAIRE', 'Secrétaire scolaire',  'Gestion des fiches élèves et des inscriptions.'),
  ('ENSEIGNANT', 'Enseignant',           'Consultation de l''annuaire interne.')
) as p(code, nom, description) on true
on conflict (etablissement_id, code) where code is not null and deleted_at is null
do nothing;

-- Proviseur : gestion complète de l'établissement.
insert into public.poste_permissions (poste_id, permission_code)
select po.id, perm.code
from public.postes po
cross join public.permissions perm
where po.code = 'PROVISEUR'
  and perm.code in (
    'etablissement.fiche.gerer',
    'etablissement.unite.gerer',
    'etablissement.annee.gerer',
    'etablissement.poste.gerer',
    'etablissement.membre.gerer',
    'etablissement.membre.lire',
    'etablissement.invitation.gerer',
    'scolarite.eleve.gerer'
  )
on conflict do nothing;

-- Secrétaire : scolarité et annuaire, sans administration de l'établissement.
insert into public.poste_permissions (poste_id, permission_code)
select po.id, perm.code
from public.postes po
cross join public.permissions perm
where po.code = 'SECRETAIRE'
  and perm.code in ('scolarite.eleve.gerer', 'etablissement.membre.lire')
on conflict do nothing;

-- Enseignant : lecture seule de l'annuaire à ce stade (M4+ élargira).
insert into public.poste_permissions (poste_id, permission_code)
select po.id, 'etablissement.membre.lire'
from public.postes po
where po.code = 'ENSEIGNANT'
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Fiches élèves de démonstration — support du parcours de liaison (ch. 5.8).
-- Un compte élève de test se lie avec le matricule et la date ci-dessous.
-- ---------------------------------------------------------------------------
insert into public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance)
select e.id, f.matricule, f.nom, f.prenom, f.naissance::date
from public.etablissements e
join (values
  ('lycee-innovation-conakry', 'LIC-2026-0148', 'Diallo',  'Aminata', '2011-04-17'),
  ('lycee-innovation-conakry', 'LIC-2026-0149', 'Camara',  'Ibrahima', '2010-11-02'),
  ('college-energie-labe',     'CEL-2026-0032', 'Barry',   'Fatoumata', '2012-01-25')
) as f(slug, matricule, nom, prenom, naissance) on f.slug = e.slug
on conflict (etablissement_id, matricule) do nothing;
