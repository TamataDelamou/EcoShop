-- ============================================================================
-- EcoShop — M13 — Maquette de données Marketplace AssoShop mono-vendeur
--
-- S'appuie sur : l'établissement « Lycée Innovation Conakry » (seed M0), les
-- comptes et classes M5, et le catalogue de permissions M1/M13.
--
-- Crée : 2 commerçants externes, 4 produits, 2 sous-comptes marchands
-- (CinetPay + Mobile Money) pour l'établissement, un panier mono-vendeur,
-- une commande confirmée et un paiement en attente.
--
-- Règles arbitrées démontrées :
--   1. Panier mono-vendeur (un seul commerçant par panier/commande).
--   2. Sous-comptes marchands dédiés par établissement (isolation).
--   3. Port paiement agnostique (fournisseur cinetpay/mobile_money).
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
-- Clés résolues
-- ---------------------------------------------------------------------------
create temp table if not exists seed_m13 (cle text primary key, val uuid);

insert into seed_m13 (cle, val)
select 'etab', id from public.etablissements where slug = 'lycee-innovation-conakry'
on conflict (cle) do nothing;

insert into seed_m13 (cle, val)
select 'annee', id from public.annees_scolaires
where etablissement_id = (select val from seed_m13 where cle = 'etab') and libelle = '2026-2027'
on conflict (cle) do nothing;

insert into seed_m13 (cle, val) values
  ('acheteur', pg_temp.creer_compte('+224620001030', 'parent'))
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- Commerçants externes
-- ---------------------------------------------------------------------------
insert into public.commercants (nom, raison_sociale, telephone, email) values
  ('Librairie Conakry',   'Librairie Conakry SARL',    '+224620111222', 'contact@librairie-conakry.gn'),
  ('Boutique Scolaire GN', 'Boutique Scolaire Guinée', '+224620333444', 'contact@boutique-scolaire.gn')
on conflict (nom) where deleted_at is null do nothing;

-- ---------------------------------------------------------------------------
-- Catalogue produits
-- ---------------------------------------------------------------------------
insert into public.catalogues_produits (commercant_id, libelle, description, prix, devise)
select c.id, v.libelle, v.description, v.prix, 'GNF'
from public.commercants c
join (values
  ('Librairie Conakry',   'Manuel Maths 7e',        'Manuel de mathématiques niveau 7e',         85000),
  ('Librairie Conakry',   'Cahier 200 pages',       'Cahier grand format 200 pages',            15000),
  ('Boutique Scolaire GN', 'Tenue scolaire (lot)',   'Lot tenue scolaire complète',              120000),
  ('Boutique Scolaire GN', 'Kit géométrie',          'Kit règle, compas, équerre, rapporteur',   22000)
) as v(nom, libelle, description, prix) on v.nom = c.nom
on conflict (commercant_id, libelle) where deleted_at is null do nothing;

-- ---------------------------------------------------------------------------
-- Sous-comptes marchands dédiés à l'établissement (secrets hors table)
-- ---------------------------------------------------------------------------
insert into public.sous_comptes_marchands
  (etablissement_id, fournisseur, libelle, reference_compte)
values
  ((select val from seed_m13 where cle = 'etab'), 'cinetpay',     'CinetPay Lycée Innovation',  'CIN-ETAB-0001'),
  ((select val from seed_m13 where cle = 'etab'), 'mobile_money', 'Orange Money Lycée',         'OM-ETAB-0001')
on conflict (etablissement_id, fournisseur) where deleted_at is null do nothing;

-- ---------------------------------------------------------------------------
-- Panier mono-vendeur (Librairie Conakry) + 2 lignes
-- ---------------------------------------------------------------------------
insert into public.paniers (etablissement_id, profile_id, commercant_id, statut)
select (select val from seed_m13 where cle = 'etab'),
       (select val from seed_m13 where cle = 'acheteur'),
       c.id, 'actif'
from public.commercants c
where c.nom = 'Librairie Conakry'
  and not exists (
    select 1 from public.paniers p
    where p.profile_id = (select val from seed_m13 where cle = 'acheteur')
      and p.statut = 'actif'
      and p.commercant_id = c.id
  );

insert into public.lignes_paniers (panier_id, catalogue_produit_id, quantite)
select p.id, cp.id, v.qte
from public.paniers p
join public.commercants c on c.id = p.commercant_id
join public.catalogues_produits cp on cp.commercant_id = c.id
join (values
  ('Manuel Maths 7e', 2),
  ('Cahier 200 pages', 4)
) as v(libelle, qte) on v.libelle = cp.libelle
where p.profile_id = (select val from seed_m13 where cle = 'acheteur')
  and p.statut = 'actif'
  and not exists (
    select 1 from public.lignes_paniers lp where lp.panier_id = p.id and lp.catalogue_produit_id = cp.id
  );

-- ---------------------------------------------------------------------------
-- Commande confirmée (snapshot des prix) + paiement en attente (CinetPay)
-- ---------------------------------------------------------------------------
insert into public.commandes
  (etablissement_id, commercant_id, profile_id, panier_id, reference, statut, montant_total, devise)
select p.etablissement_id, p.commercant_id, p.profile_id, p.id,
       'CMD-2026-0001', 'confirmee', 230000, 'GNF'
from public.paniers p
where p.profile_id = (select val from seed_m13 where cle = 'acheteur')
  and p.statut = 'actif'
  and not exists (select 1 from public.commandes c where c.reference = 'CMD-2026-0001');

insert into public.lignes_commandes
  (commande_id, catalogue_produit_id, quantite, prix_unitaire, montant_ligne)
select c.id, cp.id, v.qte, cp.prix, cp.prix * v.qte
from public.commandes c
join public.commercants mc on mc.id = c.commercant_id
join public.catalogues_produits cp on cp.commercant_id = mc.id
join (values
  ('Manuel Maths 7e', 2),
  ('Cahier 200 pages', 4)
) as v(libelle, qte) on v.libelle = cp.libelle
where c.reference = 'CMD-2026-0001'
  and not exists (
    select 1 from public.lignes_commandes lc
    where lc.commande_id = c.id and lc.catalogue_produit_id = cp.id
  );

insert into public.paiements
  (etablissement_id, commande_id, sous_compte_id, fournisseur, montant, statut)
select c.etablissement_id, c.id, sc.id, 'cinetpay', c.montant_total, 'en_attente'
from public.commandes c
join public.sous_comptes_marchands sc
  on sc.etablissement_id = c.etablissement_id and sc.fournisseur = 'cinetpay'
where c.reference = 'CMD-2026-0001'
  and not exists (
    select 1 from public.paiements p
    where p.commande_id = c.id and p.fournisseur = 'cinetpay'
  );

-- ============================================================================
-- Fin de la maquette M13.
-- ============================================================================
