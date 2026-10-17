-- ============================================================================
-- EcoShop — REG-03, lot C1 : référentiel comptable choisi par l'établissement
-- (proposition validée le 2026-10-17 : docs/propositions/REG-03_COMPTABILITE.md)
--
-- Quatre référentiels, un seul moteur d'écritures (M14) :
--   • simplifie        — plan ouvert M14 (suivi de gestion), inchangé ;
--   • syscohada_smt    — SYSCOHADA révisé, Système minimal de trésorerie ;
--   • syscohada_normal — SYSCOHADA révisé, Système normal ;
--   • sycebnl          — entités à but non lucratif (associations,
--                        confessionnelles, fondations), en vigueur 1/1/2024.
--
-- Ce lot livre :
--   1. Les plans de comptes de référence (lecture seule, communs à tous les
--      établissements), réduits aux comptes utiles à une école, avec des
--      sous-comptes EcoShop identifiés (`extension_ecoshop`) pour la
--      scolarité, la cantine, le transport et Orange Money.
--   2. Le choix du référentiel par la Direction, l'historique des choix, et
--      le chargement du plan de référence dans `plans_comptables`.
--   3. La protection des comptes réglementaires (ni modifiables ni
--      supprimables) et la règle des sous-comptes : un compte propre à
--      l'école prolonge obligatoirement un compte réglementaire.
--   4. L'assistant de recommandation (forme juridique, chiffre d'affaires,
--      souhait de comptabilité réglementaire) — il RECOMMANDE, la Direction
--      DÉCIDE.
--
-- Sources et réserves :
--   • SYSCOHADA : numéros et intitulés relevés dans le plan de comptes
--     SYSCOHADA révisé (Acte uniforme du 26 janvier 2017) ; seuil SMT
--     « services » de l'art. 13 : 30 M FCFA HT « ou l'équivalent dans
--     l'unité monétaire ayant cours légal ».
--   • SYCEBNL : relevé sur une copie non officielle du plan → toutes les
--     lignes portent `a_relire = true`.
--   • Équivalent GNF du seuil SMT : aucun texte guinéen trouvé ; valeur
--     indicative calculée au cours du 4 octobre 2026 (1 XOF ≈ 15,06 GNF),
--     marquée `a_confirmer`.
--   → Relecture par un expert-comptable inscrit en Guinée AVANT mise en
--     production (registre REG-03).
--
-- Hors périmètre (lots suivants) : passage d'une comptabilité déjà tenue à
-- un autre plan (C2, à l'ouverture d'un exercice), pièces multi-lignes et
-- clôture (C2), écritures automatiques (C3), états financiers (C4).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Plans de comptes de référence (données communes, lecture seule)
-- ---------------------------------------------------------------------------
create table if not exists public.plans_comptables_reference (
  plan text not null check (plan in ('syscohada', 'sycebnl')),
  code text not null check (code ~ '^[0-9]{1,8}$'),
  intitule text not null,
  type text not null check (type in ('capitaux', 'actif', 'passif', 'banque', 'caisse', 'charge', 'produit', 'autre')),
  extension_ecoshop boolean not null default false,
  a_relire boolean not null default false,
  primary key (plan, code)
);

alter table public.plans_comptables_reference enable row level security;
drop policy if exists plans_reference_lecture on public.plans_comptables_reference;
create policy plans_reference_lecture on public.plans_comptables_reference
  for select using (auth.role() in ('authenticated', 'service_role'));
revoke insert, update, delete on public.plans_comptables_reference from public, anon, authenticated;
grant select on public.plans_comptables_reference to authenticated;

-- Le parent d'un compte de référence est le plus long code de référence
-- qui le préfixe (classe « 6 » → « 60 » → « 605 » → « 6051 »).
create or replace function public.code_parent_reference(p_plan text, p_code text)
returns text
language sql
stable
set search_path = public
as $$
  select r.code
    from public.plans_comptables_reference r
   where r.plan = p_plan
     and char_length(r.code) < char_length(p_code)
     and left(p_code, char_length(r.code)) = r.code
   order by char_length(r.code) desc
   limit 1;
$$;

-- 1.1 SYSCOHADA révisé (commun au SMT et au Système normal)
insert into public.plans_comptables_reference (plan, code, intitule, type, extension_ecoshop) values
  ('syscohada', '1', 'Comptes de ressources durables', 'capitaux', false),
  ('syscohada', '101', 'Capital social', 'capitaux', false),
  ('syscohada', '103', 'Capital personnel', 'capitaux', false),
  ('syscohada', '104', 'Compte de l''exploitant', 'capitaux', false),
  ('syscohada', '11', 'Réserves', 'capitaux', false),
  ('syscohada', '111', 'Réserve légale', 'capitaux', false),
  ('syscohada', '12', 'Report à nouveau', 'capitaux', false),
  ('syscohada', '121', 'Report à nouveau créditeur', 'capitaux', false),
  ('syscohada', '129', 'Report à nouveau débiteur', 'capitaux', false),
  ('syscohada', '13', 'Résultat net de l''exercice', 'capitaux', false),
  ('syscohada', '131', 'Résultat net : bénéfice', 'capitaux', false),
  ('syscohada', '139', 'Résultat net : perte', 'capitaux', false),
  ('syscohada', '14', 'Subventions d''investissement', 'capitaux', false),
  ('syscohada', '16', 'Emprunts et dettes assimilées', 'passif', false),
  ('syscohada', '162', 'Emprunts et dettes auprès des établissements de crédit', 'passif', false),
  ('syscohada', '2', 'Comptes d''actif immobilisé', 'actif', false),
  ('syscohada', '21', 'Immobilisations incorporelles', 'actif', false),
  ('syscohada', '213', 'Logiciels et sites internet', 'actif', false),
  ('syscohada', '22', 'Terrains', 'actif', false),
  ('syscohada', '23', 'Bâtiments, installations techniques et agencements', 'actif', false),
  ('syscohada', '231', 'Bâtiments industriels, agricoles, administratifs et commerciaux sur sol propre', 'actif', false),
  ('syscohada', '24', 'Matériel, mobilier et actifs biologiques', 'actif', false),
  ('syscohada', '244', 'Matériel et mobilier', 'actif', false),
  ('syscohada', '2441', 'Matériel de bureau', 'actif', false),
  ('syscohada', '2442', 'Matériel informatique', 'actif', false),
  ('syscohada', '2444', 'Mobilier de bureau', 'actif', false),
  ('syscohada', '245', 'Matériel de transport', 'actif', false),
  ('syscohada', '28', 'Amortissements', 'actif', false),
  ('syscohada', '284', 'Amortissements du matériel', 'actif', false),
  ('syscohada', '3', 'Comptes de stocks', 'actif', false),
  ('syscohada', '33', 'Autres approvisionnements', 'actif', false),
  ('syscohada', '4', 'Comptes de tiers', 'autre', false),
  ('syscohada', '40', 'Fournisseurs et comptes rattachés', 'passif', false),
  ('syscohada', '401', 'Fournisseurs, dettes en compte', 'passif', false),
  ('syscohada', '409', 'Fournisseurs débiteurs', 'actif', false),
  ('syscohada', '4091', 'Fournisseurs, avances et acomptes versés', 'actif', false),
  ('syscohada', '41', 'Clients et comptes rattachés', 'actif', false),
  ('syscohada', '411', 'Clients', 'actif', false),
  ('syscohada', '4111', 'Clients', 'actif', false),
  ('syscohada', '41111', 'Familles — frais scolaires à recevoir', 'actif', true),
  ('syscohada', '416', 'Créances clients litigieuses ou douteuses', 'actif', false),
  ('syscohada', '418', 'Clients, produits à recevoir', 'actif', false),
  ('syscohada', '419', 'Clients créditeurs', 'passif', false),
  ('syscohada', '4191', 'Clients, avances et acomptes reçus', 'passif', false),
  ('syscohada', '42', 'Personnel', 'passif', false),
  ('syscohada', '421', 'Personnel, avances et acomptes', 'actif', false),
  ('syscohada', '422', 'Personnel, rémunérations dues', 'passif', false),
  ('syscohada', '43', 'Organismes sociaux', 'passif', false),
  ('syscohada', '431', 'Sécurité sociale', 'passif', false),
  ('syscohada', '44', 'État et collectivités publiques', 'passif', false),
  ('syscohada', '447', 'État, impôts retenus à la source', 'passif', false),
  ('syscohada', '47', 'Débiteurs et créditeurs divers', 'autre', false),
  ('syscohada', '471', 'Débiteurs et créditeurs divers', 'autre', false),
  ('syscohada', '5', 'Comptes de trésorerie', 'autre', false),
  ('syscohada', '52', 'Banques', 'banque', false),
  ('syscohada', '521', 'Banques locales', 'banque', false),
  ('syscohada', '55', 'Instruments de monnaie électronique', 'banque', false),
  ('syscohada', '552', 'Monnaie électronique — téléphone portable', 'banque', false),
  ('syscohada', '5521', 'Orange Money', 'banque', true),
  ('syscohada', '57', 'Caisse', 'caisse', false),
  ('syscohada', '571', 'Caisse siège social', 'caisse', false),
  ('syscohada', '58', 'Régies d''avances, accréditifs et virements internes', 'autre', false),
  ('syscohada', '585', 'Virements de fonds', 'autre', false),
  ('syscohada', '6', 'Comptes de charges des activités ordinaires', 'charge', false),
  ('syscohada', '60', 'Achats', 'charge', false),
  ('syscohada', '604', 'Achats stockés de matières et fournitures consommables', 'charge', false),
  ('syscohada', '605', 'Autres achats', 'charge', false),
  ('syscohada', '6051', 'Fournitures non stockables — eau', 'charge', false),
  ('syscohada', '6052', 'Fournitures non stockables — électricité', 'charge', false),
  ('syscohada', '6053', 'Fournitures non stockables — autres énergies', 'charge', false),
  ('syscohada', '6054', 'Fournitures d''entretien non stockables', 'charge', false),
  ('syscohada', '6055', 'Fournitures de bureau non stockables', 'charge', false),
  ('syscohada', '6056', 'Achats de petit matériel et outillage', 'charge', false),
  ('syscohada', '61', 'Transports', 'charge', false),
  ('syscohada', '62', 'Services extérieurs', 'charge', false),
  ('syscohada', '622', 'Locations et charges locatives', 'charge', false),
  ('syscohada', '624', 'Entretien, réparations et maintenance', 'charge', false),
  ('syscohada', '625', 'Primes d''assurance', 'charge', false),
  ('syscohada', '627', 'Publicité, publications, relations publiques', 'charge', false),
  ('syscohada', '628', 'Frais de télécommunications', 'charge', false),
  ('syscohada', '63', 'Autres services extérieurs', 'charge', false),
  ('syscohada', '631', 'Frais bancaires', 'charge', false),
  ('syscohada', '632', 'Rémunérations d''intermédiaires et de conseils', 'charge', false),
  ('syscohada', '64', 'Impôts et taxes', 'charge', false),
  ('syscohada', '641', 'Impôts et taxes directs', 'charge', false),
  ('syscohada', '65', 'Autres charges', 'charge', false),
  ('syscohada', '658', 'Charges diverses', 'charge', false),
  ('syscohada', '66', 'Charges de personnel', 'charge', false),
  ('syscohada', '661', 'Rémunérations directes versées au personnel national', 'charge', false),
  ('syscohada', '663', 'Indemnités forfaitaires versées au personnel', 'charge', false),
  ('syscohada', '664', 'Charges sociales', 'charge', false),
  ('syscohada', '67', 'Frais financiers et charges assimilées', 'charge', false),
  ('syscohada', '671', 'Intérêts des emprunts', 'charge', false),
  ('syscohada', '68', 'Dotations aux amortissements', 'charge', false),
  ('syscohada', '681', 'Dotations aux amortissements d''exploitation', 'charge', false),
  ('syscohada', '7', 'Comptes de produits des activités ordinaires', 'produit', false),
  ('syscohada', '70', 'Ventes', 'produit', false),
  ('syscohada', '706', 'Services vendus', 'produit', false),
  ('syscohada', '7061', 'Services vendus dans la Région', 'produit', false),
  ('syscohada', '70611', 'Frais de scolarité', 'produit', true),
  ('syscohada', '70612', 'Frais d''inscription et de réinscription', 'produit', true),
  ('syscohada', '70613', 'Cantine scolaire', 'produit', true),
  ('syscohada', '70614', 'Transport scolaire', 'produit', true),
  ('syscohada', '70618', 'Autres prestations scolaires', 'produit', true),
  ('syscohada', '707', 'Produits accessoires', 'produit', false),
  ('syscohada', '71', 'Subventions d''exploitation', 'produit', false),
  ('syscohada', '75', 'Autres produits', 'produit', false),
  ('syscohada', '758', 'Produits divers', 'produit', false),
  ('syscohada', '77', 'Revenus financiers et produits assimilés', 'produit', false),
  ('syscohada', '8', 'Comptes des autres charges et des autres produits', 'autre', false),
  ('syscohada', '82', 'Produits des cessions d''immobilisations', 'produit', false),
  ('syscohada', '83', 'Charges hors activités ordinaires', 'charge', false),
  ('syscohada', '84', 'Produits hors activités ordinaires', 'produit', false),
  ('syscohada', '89', 'Impôts sur le résultat', 'charge', false)
on conflict (plan, code) do update
  set intitule = excluded.intitule, type = excluded.type, extension_ecoshop = excluded.extension_ecoshop;

-- 1.2 SYCEBNL (à relire : source non officielle)
insert into public.plans_comptables_reference (plan, code, intitule, type, extension_ecoshop, a_relire) values
  ('sycebnl', '1', 'Comptes de ressources durables', 'capitaux', false, true),
  ('sycebnl', '101', 'Dotation non consomptible sans droit de reprise', 'capitaux', false, true),
  ('sycebnl', '102', 'Dotation non consomptible avec droit de reprise', 'capitaux', false, true),
  ('sycebnl', '104', 'Dotation consomptible', 'capitaux', false, true),
  ('sycebnl', '11', 'Réserves', 'capitaux', false, true),
  ('sycebnl', '12', 'Report à nouveau', 'capitaux', false, true),
  ('sycebnl', '121', 'Report à nouveau des excédents', 'capitaux', false, true),
  ('sycebnl', '129', 'Report à nouveau des déficits', 'capitaux', false, true),
  ('sycebnl', '13', 'Résultat net de l''exercice', 'capitaux', false, true),
  ('sycebnl', '131', 'Excédent de l''exercice', 'capitaux', false, true),
  ('sycebnl', '139', 'Déficit de l''exercice', 'capitaux', false, true),
  ('sycebnl', '14', 'Subventions d''investissement', 'capitaux', false, true),
  ('sycebnl', '141', 'Subventions d''équipement', 'capitaux', false, true),
  ('sycebnl', '16', 'Fonds affectés et provenant de dons ou legs d''immobilisations', 'capitaux', false, true),
  ('sycebnl', '165', 'Fonds non consommés en fin d''exercice destinés à un projet spécifique', 'capitaux', false, true),
  ('sycebnl', '18', 'Emprunts et dettes assimilées', 'passif', false, true),
  ('sycebnl', '182', 'Emprunts et dettes auprès des établissements de crédit', 'passif', false, true),
  ('sycebnl', '2', 'Comptes d''actif immobilisé', 'actif', false, true),
  ('sycebnl', '21', 'Immobilisations incorporelles', 'actif', false, true),
  ('sycebnl', '22', 'Terrains', 'actif', false, true),
  ('sycebnl', '23', 'Bâtiments, installations techniques et agencements', 'actif', false, true),
  ('sycebnl', '24', 'Matériel, mobilier et actifs biologiques', 'actif', false, true),
  ('sycebnl', '244', 'Matériel et mobilier', 'actif', false, true),
  ('sycebnl', '245', 'Matériel de transport', 'actif', false, true),
  ('sycebnl', '28', 'Amortissements', 'actif', false, true),
  ('sycebnl', '3', 'Comptes de stocks', 'actif', false, true),
  ('sycebnl', '4', 'Comptes de tiers', 'autre', false, true),
  ('sycebnl', '40', 'Fournisseurs et comptes rattachés', 'passif', false, true),
  ('sycebnl', '401', 'Fournisseurs, dettes en compte', 'passif', false, true),
  ('sycebnl', '41', 'Adhérents, clients-usagers et comptes rattachés', 'actif', false, true),
  ('sycebnl', '411', 'Adhérents', 'actif', false, true),
  ('sycebnl', '412', 'Clients-usagers', 'actif', false, true),
  ('sycebnl', '4121', 'Familles — frais scolaires à recevoir', 'actif', true, true),
  ('sycebnl', '419', 'Adhérents et clients-usagers créditeurs', 'passif', false, true),
  ('sycebnl', '42', 'Personnel', 'passif', false, true),
  ('sycebnl', '421', 'Personnel, avances et acomptes', 'actif', false, true),
  ('sycebnl', '422', 'Personnel, rémunérations dues', 'passif', false, true),
  ('sycebnl', '43', 'Organismes sociaux', 'passif', false, true),
  ('sycebnl', '44', 'État et collectivités publiques', 'passif', false, true),
  ('sycebnl', '45', 'Fondateurs, apporteurs et comptes courants', 'passif', false, true),
  ('sycebnl', '46', 'Bailleurs, État et autres organismes, fonds d''administration', 'passif', false, true),
  ('sycebnl', '47', 'Débiteurs et créditeurs divers', 'autre', false, true),
  ('sycebnl', '5', 'Comptes de trésorerie', 'autre', false, true),
  ('sycebnl', '52', 'Banques', 'banque', false, true),
  ('sycebnl', '521', 'Banques locales', 'banque', false, true),
  ('sycebnl', '55', 'Instruments de monnaie électronique', 'banque', false, true),
  ('sycebnl', '552', 'Monnaie électronique — téléphone portable', 'banque', false, true),
  ('sycebnl', '5521', 'Orange Money', 'banque', true, true),
  ('sycebnl', '57', 'Caisse', 'caisse', false, true),
  ('sycebnl', '571', 'Caisse siège', 'caisse', false, true),
  ('sycebnl', '58', 'Régies d''avances, accréditifs et virements internes', 'autre', false, true),
  ('sycebnl', '6', 'Comptes de charges des activités ordinaires', 'charge', false, true),
  ('sycebnl', '60', 'Achats', 'charge', false, true),
  ('sycebnl', '605', 'Autres achats', 'charge', false, true),
  ('sycebnl', '61', 'Transports', 'charge', false, true),
  ('sycebnl', '62', 'Services extérieurs', 'charge', false, true),
  ('sycebnl', '63', 'Autres services extérieurs', 'charge', false, true),
  ('sycebnl', '64', 'Impôts et taxes', 'charge', false, true),
  ('sycebnl', '65', 'Autres charges', 'charge', false, true),
  ('sycebnl', '66', 'Charges de personnel', 'charge', false, true),
  ('sycebnl', '68', 'Dotations aux amortissements', 'charge', false, true),
  ('sycebnl', '7', 'Comptes de produits des activités ordinaires', 'produit', false, true),
  ('sycebnl', '701', 'Cotisations des adhérents', 'produit', false, true),
  ('sycebnl', '704', 'Revenus liés à la générosité', 'produit', false, true),
  ('sycebnl', '7041', 'Dons', 'produit', false, true),
  ('sycebnl', '7042', 'Legs', 'produit', false, true),
  ('sycebnl', '7043', 'Deniers du culte', 'produit', false, true),
  ('sycebnl', '7044', 'Zakat, dîme, quête et assimilées', 'produit', false, true),
  ('sycebnl', '705', 'Ventes de marchandises, services et produits finis', 'produit', false, true),
  ('sycebnl', '7052', 'Services vendus', 'produit', false, true),
  ('sycebnl', '70521', 'Frais de scolarité', 'produit', true, true),
  ('sycebnl', '70522', 'Frais d''inscription et de réinscription', 'produit', true, true),
  ('sycebnl', '70523', 'Cantine scolaire', 'produit', true, true),
  ('sycebnl', '70524', 'Transport scolaire', 'produit', true, true),
  ('sycebnl', '70528', 'Autres prestations scolaires', 'produit', true, true),
  ('sycebnl', '707', 'Produits accessoires', 'produit', false, true),
  ('sycebnl', '71', 'Subventions d''exploitation', 'produit', false, true),
  ('sycebnl', '711', 'Subventions de l''État et des collectivités', 'produit', false, true),
  ('sycebnl', '712', 'Subventions des bailleurs de projets de développement', 'produit', false, true),
  ('sycebnl', '713', 'Subventions des organismes internationaux', 'produit', false, true),
  ('sycebnl', '718', 'Autres subventions d''exploitation', 'produit', false, true),
  ('sycebnl', '75', 'Autres produits', 'produit', false, true),
  ('sycebnl', '752', 'Versements des fondateurs', 'produit', false, true),
  ('sycebnl', '758', 'Produits divers', 'produit', false, true),
  ('sycebnl', '77', 'Revenus financiers et produits assimilés', 'produit', false, true),
  ('sycebnl', '8', 'Comptes des autres charges et des autres produits', 'autre', false, true)
on conflict (plan, code) do update
  set intitule = excluded.intitule, type = excluded.type,
      extension_ecoshop = excluded.extension_ecoshop, a_relire = excluded.a_relire;

-- ---------------------------------------------------------------------------
-- 2. Seuil du Système minimal de trésorerie (activités de services, art. 13)
-- ---------------------------------------------------------------------------
create table if not exists public.seuils_smt_services (
  devise_code text primary key,
  montant numeric(18, 0) not null check (montant > 0),
  a_confirmer boolean not null default false,
  note text
);

alter table public.seuils_smt_services enable row level security;
drop policy if exists seuils_smt_lecture on public.seuils_smt_services;
create policy seuils_smt_lecture on public.seuils_smt_services
  for select using (auth.role() in ('authenticated', 'service_role'));
revoke insert, update, delete on public.seuils_smt_services from public, anon, authenticated;
grant select on public.seuils_smt_services to authenticated;

insert into public.seuils_smt_services (devise_code, montant, a_confirmer, note) values
  ('XOF', 30000000, false, 'AUDCIF art. 13 — services'),
  ('XAF', 30000000, false, 'AUDCIF art. 13 — services'),
  ('GNF', 450000000, true, 'Équivalent indicatif de 30 M FCFA (1 XOF ≈ 15,06 GNF au 2026-10-04) — à confirmer par un expert-comptable')
on conflict (devise_code) do update
  set montant = excluded.montant, a_confirmer = excluded.a_confirmer, note = excluded.note;

-- ---------------------------------------------------------------------------
-- 3. Choix de l'établissement
-- ---------------------------------------------------------------------------
create table if not exists public.parametres_comptables (
  etablissement_id uuid primary key references public.etablissements (id) on delete cascade,
  referentiel text not null default 'simplifie'
    check (referentiel in ('simplifie', 'syscohada_smt', 'syscohada_normal', 'sycebnl')),
  forme_juridique text
    check (forme_juridique is null or forme_juridique in
      ('societe', 'entreprise_individuelle', 'association', 'confessionnelle', 'fondation', 'publique', 'autre')),
  chiffre_affaires_estime numeric(18, 0) check (chiffre_affaires_estime is null or chiffre_affaires_estime >= 0),
  choisi_par uuid references public.profiles (id),
  choisi_le timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists parametres_comptables_set_updated_at on public.parametres_comptables;
create trigger parametres_comptables_set_updated_at
  before update on public.parametres_comptables
  for each row execute function public.set_updated_at();

create table if not exists public.historique_referentiels_comptables (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  ancien_referentiel text,
  nouveau_referentiel text not null,
  forme_juridique text,
  chiffre_affaires_estime numeric(18, 0),
  comptes_charges integer not null default 0,
  par uuid references public.profiles (id),
  le timestamptz not null default now()
);

create index if not exists idx_historique_referentiels_etab
  on public.historique_referentiels_comptables (etablissement_id, le desc);

alter table public.parametres_comptables enable row level security;
alter table public.historique_referentiels_comptables enable row level security;

drop policy if exists parametres_comptables_select on public.parametres_comptables;
create policy parametres_comptables_select on public.parametres_comptables
  for select using (public.est_comptable(etablissement_id));
drop policy if exists historique_referentiels_select on public.historique_referentiels_comptables;
create policy historique_referentiels_select on public.historique_referentiels_comptables
  for select using (public.est_comptable(etablissement_id));

-- Aucune écriture directe : RPC uniquement. (Les privilèges par défaut du
-- schéma accordent tout à anon/authenticated : on les retire explicitement.)
revoke insert, update, delete on public.parametres_comptables from public, anon, authenticated;
revoke insert, update, delete on public.historique_referentiels_comptables from public, anon, authenticated;

create or replace function public.referentiel_comptable_de(p_etablissement uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select referentiel from public.parametres_comptables where etablissement_id = p_etablissement),
    'simplifie');
$$;

create or replace function public.plan_du_referentiel(p_referentiel text)
returns text
language sql
immutable
as $$
  select case
    when p_referentiel in ('syscohada_smt', 'syscohada_normal') then 'syscohada'
    when p_referentiel = 'sycebnl' then 'sycebnl'
    else null
  end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Plan comptable de l'établissement : comptes réglementaires protégés
-- ---------------------------------------------------------------------------
alter table public.plans_comptables add column if not exists reglementaire boolean not null default false;
alter table public.plans_comptables add column if not exists extension_ecoshop boolean not null default false;

create or replace function public.plans_comptables_regle_referentiel()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_chargement boolean := coalesce(current_setting('ecoshop.chargement_plan_reference', true), '') = 'on';
  v_plan text;
  v_parent public.plans_comptables;
begin
  if v_chargement then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    if old.reglementaire then
      raise exception 'COMPTE_REGLEMENTAIRE_PROTEGE' using errcode = '42501';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and old.reglementaire then
    if new.code is distinct from old.code or new.intitule is distinct from old.intitule
       or new.type is distinct from old.type or new.parent_id is distinct from old.parent_id
       or new.reglementaire is distinct from old.reglementaire or new.actif is distinct from old.actif
       or new.deleted_at is distinct from old.deleted_at or new.etablissement_id is distinct from old.etablissement_id then
      raise exception 'COMPTE_REGLEMENTAIRE_PROTEGE' using errcode = '42501';
    end if;
    return new;
  end if;

  -- Seul le chargement du plan de référence crée des comptes réglementaires.
  if new.reglementaire then
    raise exception 'COMPTE_REGLEMENTAIRE_PROTEGE' using errcode = '42501';
  end if;
  new.extension_ecoshop := false;

  v_plan := public.plan_du_referentiel(public.referentiel_comptable_de(new.etablissement_id));
  if v_plan is null or new.deleted_at is not null then
    return new;  -- plan ouvert (simplifié) : aucune contrainte de numérotation
  end if;

  -- Référentiel OHADA : un compte propre à l'école prolonge un compte
  -- réglementaire (sous-compte), en chiffres uniquement.
  if new.code !~ '^[0-9]{2,10}$' then
    raise exception 'SOUS_COMPTE_INVALIDE' using errcode = '23514';
  end if;

  select pc.* into v_parent
    from public.plans_comptables pc
   where pc.etablissement_id = new.etablissement_id
     and pc.reglementaire and pc.deleted_at is null
     and char_length(pc.code) < char_length(new.code)
     and left(new.code, char_length(pc.code)) = pc.code
   order by char_length(pc.code) desc
   limit 1;

  if v_parent.id is null or char_length(v_parent.code) < 2 then
    raise exception 'SOUS_COMPTE_INVALIDE' using errcode = '23514';
  end if;

  new.parent_id := coalesce(new.parent_id, v_parent.id);
  -- Le sous-compte hérite de la nature du compte qu'il prolonge.
  new.type := v_parent.type;
  return new;
end;
$$;

drop trigger if exists plans_comptables_regle_referentiel on public.plans_comptables;
create trigger plans_comptables_regle_referentiel
  before insert or update or delete on public.plans_comptables
  for each row execute function public.plans_comptables_regle_referentiel();

-- ---------------------------------------------------------------------------
-- 5. Assistant : recommandation (n'enregistre rien)
-- ---------------------------------------------------------------------------
create or replace function public.recommander_referentiel_comptable(
  p_forme_juridique text,
  p_chiffre_affaires numeric default null,
  p_devise text default 'GNF',
  p_souhait_reglementaire boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  s public.seuils_smt_services;
  v_ref text;
  v_raison text;
  v_alternatives text[] := array[]::text[];
begin
  select * into s from public.seuils_smt_services where devise_code = upper(coalesce(p_devise, 'GNF'));

  if p_forme_juridique in ('association', 'confessionnelle', 'fondation') then
    v_ref := 'sycebnl';
    v_raison := 'Les associations, organisations confessionnelles et fondations relèvent du SYCEBNL (OHADA), en vigueur depuis le 1er janvier 2024.';
    v_alternatives := array['simplifie'];
  elsif p_forme_juridique in ('societe', 'entreprise_individuelle') then
    if p_chiffre_affaires is not null and s.devise_code is not null and p_chiffre_affaires <= s.montant then
      v_ref := 'syscohada_smt';
      v_raison := 'Entreprise de services dont le chiffre d''affaires ne dépasse pas le seuil du Système minimal de trésorerie (SYSCOHADA révisé, art. 13). Le Système normal reste possible sur option.';
      v_alternatives := array['syscohada_normal', 'simplifie'];
    else
      v_ref := 'syscohada_normal';
      v_raison := case when p_chiffre_affaires is null or s.devise_code is null
        then 'Une entreprise relève du SYSCOHADA révisé ; sans chiffre d''affaires connu, le Système normal est retenu par défaut.'
        else 'Entreprise dont le chiffre d''affaires dépasse le seuil du Système minimal de trésorerie : Système normal du SYSCOHADA révisé.' end;
      v_alternatives := array['syscohada_smt', 'simplifie'];
    end if;
  elsif p_forme_juridique = 'publique' then
    v_ref := 'simplifie';
    v_raison := 'Un établissement public suit la comptabilité publique de l''État : EcoShop sert alors de suivi de gestion.';
  else
    v_ref := 'simplifie';
    v_raison := 'Forme juridique non précisée : la comptabilité simplifiée est proposée en attendant ; un expert-comptable confirmera le référentiel applicable.';
    v_alternatives := array['syscohada_smt', 'syscohada_normal', 'sycebnl'];
  end if;

  -- L'école ne souhaite pas de comptabilité réglementaire : on le respecte,
  -- en le signalant quand la loi l'impose.
  if not coalesce(p_souhait_reglementaire, true) and v_ref <> 'simplifie' then
    v_alternatives := array_prepend(v_ref, array_remove(v_alternatives, 'simplifie'));
    v_raison := v_raison || ' Vous avez indiqué ne pas souhaiter de comptabilité réglementaire : la comptabilité simplifiée est possible pour le suivi, mais ne remplace pas les obligations légales.';
    v_ref := 'simplifie';
  end if;

  return jsonb_build_object(
    'referentiel', v_ref,
    'raison', v_raison,
    'alternatives', to_jsonb(v_alternatives),
    'seuil_smt', s.montant,
    'seuil_devise', s.devise_code,
    'seuil_a_confirmer', coalesce(s.a_confirmer, true)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Choix par la Direction + chargement du plan de référence
-- ---------------------------------------------------------------------------
create or replace function public.choisir_referentiel_comptable(
  p_etablissement uuid,
  p_referentiel text,
  p_forme_juridique text default null,
  p_chiffre_affaires numeric default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ancien text := public.referentiel_comptable_de(p_etablissement);
  v_ancien_plan text;
  v_plan text := public.plan_du_referentiel(p_referentiel);
  v_charges integer := 0;
  r record;
begin
  if not (coalesce(public.est_direction(p_etablissement), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if p_referentiel not in ('simplifie', 'syscohada_smt', 'syscohada_normal', 'sycebnl') then
    raise exception 'REFERENTIEL_INCONNU' using errcode = '22023';
  end if;
  if p_forme_juridique is not null and p_forme_juridique not in
     ('societe', 'entreprise_individuelle', 'association', 'confessionnelle', 'fondation', 'publique', 'autre') then
    raise exception 'FORME_JURIDIQUE_INCONNUE' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('referentiel_comptable:' || p_etablissement::text));
  v_ancien_plan := public.plan_du_referentiel(v_ancien);

  -- Changer de PLAN de comptes alors que des écritures existent : réservé à
  -- l'ouverture d'un nouvel exercice (lot C2). SMT ↔ normal partagent le
  -- même plan : toujours possible ; revenir au simplifié aussi (le plan
  -- reste, il redevient ouvert).
  if v_plan is not null and v_plan is distinct from v_ancien_plan
     and exists (select 1 from public.ecritures_comptables
                  where etablissement_id = p_etablissement and deleted_at is null) then
    raise exception 'ECRITURES_EXISTANTES' using errcode = '55000';
  end if;

  perform set_config('ecoshop.chargement_plan_reference', 'on', true);

  if v_plan is not null and v_plan is distinct from v_ancien_plan then
    -- Aucune écriture : les comptes libres ou d'un autre plan sont retirés
    -- (soft-delete), puis le plan de référence est chargé.
    update public.plans_comptables
       set deleted_at = now(), actif = false, reglementaire = false
     where etablissement_id = p_etablissement and deleted_at is null;

    for r in
      select rf.code, rf.intitule, rf.type, rf.extension_ecoshop
        from public.plans_comptables_reference rf
       where rf.plan = v_plan
       order by char_length(rf.code), rf.code
    loop
      insert into public.plans_comptables
        (etablissement_id, code, intitule, type, parent_id, actif, reglementaire, extension_ecoshop, deleted_at)
      values (
        p_etablissement, r.code, r.intitule, r.type,
        (select pc.id from public.plans_comptables pc
          where pc.etablissement_id = p_etablissement
            and pc.code = public.code_parent_reference(v_plan, r.code)),
        true, true, r.extension_ecoshop, null)
      on conflict (etablissement_id, code) do update
        set intitule = excluded.intitule, type = excluded.type, parent_id = excluded.parent_id,
            actif = true, reglementaire = true, extension_ecoshop = excluded.extension_ecoshop,
            deleted_at = null;
      v_charges := v_charges + 1;
    end loop;
  elsif v_plan is null and v_ancien_plan is not null then
    update public.plans_comptables
       set reglementaire = false, extension_ecoshop = false
     where etablissement_id = p_etablissement;
  end if;

  perform set_config('ecoshop.chargement_plan_reference', 'off', true);

  insert into public.parametres_comptables
    (etablissement_id, referentiel, forme_juridique, chiffre_affaires_estime, choisi_par, choisi_le)
  values (p_etablissement, p_referentiel, p_forme_juridique, p_chiffre_affaires, v_uid, now())
  on conflict (etablissement_id) do update
    set referentiel = excluded.referentiel,
        forme_juridique = coalesce(excluded.forme_juridique, parametres_comptables.forme_juridique),
        chiffre_affaires_estime = coalesce(excluded.chiffre_affaires_estime, parametres_comptables.chiffre_affaires_estime),
        choisi_par = excluded.choisi_par,
        choisi_le = excluded.choisi_le;

  insert into public.historique_referentiels_comptables
    (etablissement_id, ancien_referentiel, nouveau_referentiel, forme_juridique, chiffre_affaires_estime, comptes_charges, par)
  values (p_etablissement, v_ancien, p_referentiel, p_forme_juridique, p_chiffre_affaires, v_charges, v_uid);

  return jsonb_build_object(
    'referentiel', p_referentiel,
    'ancien_referentiel', v_ancien,
    'comptes_charges', v_charges
  );
end;
$$;

revoke all on function public.referentiel_comptable_de(uuid) from public, anon;
grant execute on function public.referentiel_comptable_de(uuid) to authenticated, service_role;
revoke all on function public.recommander_referentiel_comptable(text, numeric, text, boolean) from public, anon;
grant execute on function public.recommander_referentiel_comptable(text, numeric, text, boolean) to authenticated;
revoke all on function public.choisir_referentiel_comptable(uuid, text, text, numeric) from public, anon;
grant execute on function public.choisir_referentiel_comptable(uuid, text, text, numeric) to authenticated;
revoke all on function public.plans_comptables_regle_referentiel() from public, anon, authenticated;
