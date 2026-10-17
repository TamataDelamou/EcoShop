-- ============================================================================
-- EcoShop — REG-03, lot C5 (2/3) : registre des donateurs et des dons
-- (proposition validée le 2026-10-17 : docs/propositions/REG-03_COMPTABILITE.md)
--
-- Pour les écoles confessionnelles et associatives (SYCEBNL) — utilisable
-- aussi par toute école qui reçoit des dons :
--   • donateurs (personnes, organisations, églises), avec accord de contact ;
--   • dons : don, legs, denier du culte, quête, mécénat, parrainage, autre ;
--     reçu numéroté sans trou par année (REC-2026-000001), jamais modifié :
--     une erreur s'annule (motif obligatoire) et se ressaisit ;
--   • campagnes et fonds : libres, projets à fonds affectés, parrainage
--     d'élèves ; objectif, collecté, employé, solde ;
--   • engagements (parrainage mensuel, promesse annuelle…) : attendu,
--     reçu, retard ;
--   • tableau de bord : par nature, par campagne, donateurs fidèles,
--     nouveaux donateurs, donateurs à relancer (ont donné l'an dernier,
--     pas encore cette année).
--
-- Comptabilisation automatique (même sûreté qu'aux lots C3 et C5-paie :
-- jamais bloquante, incidents, rattrapage) :
--   • don libre   : D trésorerie / C 704x (SYCEBNL : 7041 dons, 7042 legs,
--                   7043 deniers du culte, 7044 quêtes, 7046 mécénat,
--                   7047 parrainage, 7048 autres) ;
--   • don affecté à un projet : D trésorerie / C 165 « fonds affectés »
--                   (SYCEBNL, chap. « Fonds affectés ») ;
--   • emploi des fonds affectés : D 165 / C 7925 « reprises de fonds
--                   affectés à un projet spécifique » ; le solde non employé
--                   reste en 165 à la clôture ;
--   • SYSCOHADA : dons en 758 « produits divers » (pas de fonds affectés :
--                   le suivi des projets reste dans le registre) ;
--   • simplifié : selon les règles choisies par l'école.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Comptes SYCEBNL utiles aux dons (plan de référence, à relire)
-- ---------------------------------------------------------------------------
insert into public.plans_comptables_reference (plan, code, intitule, type, extension_ecoshop, a_relire) values
  ('sycebnl', '7045', 'Célébrations', 'produit', false, true),
  ('sycebnl', '7046', 'Mécénats', 'produit', false, true),
  ('sycebnl', '7047', 'Parrainage', 'produit', false, true),
  ('sycebnl', '7048', 'Autres revenus liés à la générosité', 'produit', false, true),
  ('sycebnl', '79', 'Reprises de provisions, de dépréciations et autres reprises', 'produit', false, true),
  ('sycebnl', '792', 'Reprises de fonds affectés', 'produit', false, true),
  ('sycebnl', '7925', 'Reprises de fonds affectés à un projet spécifique', 'produit', false, true),
  ('sycebnl', '475', 'Générosités financières à recevoir', 'actif', false, true),
  ('sycebnl', '636', 'Frais de recherche de fonds', 'charge', false, true)
on conflict (plan, code) do update
  set intitule = excluded.intitule, type = excluded.type,
      extension_ecoshop = excluded.extension_ecoshop, a_relire = excluded.a_relire;

-- Les écoles déjà en SYCEBNL reçoivent ces comptes (sans toucher à un
-- compte de même numéro qu'elles auraient déjà créé).
do $$
declare
  r record;
begin
  perform set_config('ecoshop.chargement_plan_reference', 'on', true);
  for r in
    select p.etablissement_id, rf.code, rf.intitule, rf.type
      from public.parametres_comptables p
      join public.plans_comptables_reference rf on rf.plan = 'sycebnl'
     where public.plan_du_referentiel(p.referentiel) = 'sycebnl'
       and rf.code in ('79', '792', '7925', '475', '636', '7045', '7046', '7047', '7048')
     order by p.etablissement_id, char_length(rf.code), rf.code
  loop
    insert into public.plans_comptables
      (etablissement_id, code, intitule, type, parent_id, actif, reglementaire, extension_ecoshop)
    values (r.etablissement_id, r.code, r.intitule, r.type,
            (select pc.id from public.plans_comptables pc
              where pc.etablissement_id = r.etablissement_id and pc.deleted_at is null
                and pc.code = public.code_parent_reference('sycebnl', r.code)),
            true, true, false)
    on conflict (etablissement_id, code) do nothing;
  end loop;
  perform set_config('ecoshop.chargement_plan_reference', 'off', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Registre
-- ---------------------------------------------------------------------------
create table if not exists public.donateurs (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  type text not null default 'personne' check (type in ('personne', 'organisation', 'eglise')),
  nom text not null check (char_length(trim(nom)) between 1 and 150),
  prenom text check (prenom is null or char_length(prenom) <= 100),
  telephone text check (telephone is null or char_length(telephone) <= 30),
  email text check (email is null or char_length(email) <= 200),
  adresse text check (adresse is null or char_length(adresse) <= 300),
  -- Accord pour être recontacté (remerciements, relances) : donnée
  -- personnelle, jamais présumée pour les relances.
  accepte_contact boolean not null default true,
  notes text check (notes is null or char_length(notes) <= 2000),
  cree_par uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists idx_donateurs_etablissement on public.donateurs (etablissement_id) where deleted_at is null;

create table if not exists public.affectations_dons (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  libelle text not null check (char_length(trim(libelle)) between 1 and 150),
  description text check (description is null or char_length(description) <= 2000),
  -- libre : campagne sans affectation comptable ; projet : fonds affectés
  -- (165 en SYCEBNL) ; parrainage : parrainage d'élèves.
  type text not null default 'libre' check (type in ('libre', 'projet', 'parrainage')),
  objectif numeric(18, 2) check (objectif is null or objectif > 0),
  date_debut date,
  date_fin date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint affectations_dons_dates check (date_fin is null or date_debut is null or date_fin >= date_debut),
  unique (etablissement_id, libelle)
);

create table if not exists public.dons (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  numero_recu text not null,
  donateur_id uuid references public.donateurs (id),
  nature text not null check (nature in ('don', 'legs', 'denier_culte', 'quete', 'mecenat', 'parrainage', 'autre')),
  moyen_paiement public.moyen_paiement not null default 'especes',
  montant numeric(18, 2) not null check (montant > 0),
  date_don date not null default current_date,
  affectation_id uuid references public.affectations_dons (id),
  fiche_eleve_id uuid references public.fiches_eleves (id),
  reference_paiement text check (reference_paiement is null or char_length(reference_paiement) <= 200),
  commentaire text check (commentaire is null or char_length(commentaire) <= 1000),
  -- Le donateur ne souhaite pas apparaître nommément (listes, rapports).
  anonyme boolean not null default false,
  statut text not null default 'valide' check (statut in ('valide', 'annule')),
  motif_annulation text,
  annule_par uuid references public.profiles (id),
  annule_le timestamptz,
  saisi_par uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  unique (etablissement_id, numero_recu),
  constraint dons_annulation_motivee check (statut <> 'annule' or char_length(trim(coalesce(motif_annulation, ''))) >= 3)
);
create index if not exists idx_dons_etablissement_date on public.dons (etablissement_id, date_don);
create index if not exists idx_dons_donateur on public.dons (donateur_id);
create index if not exists idx_dons_affectation on public.dons (affectation_id);

create table if not exists public.compteurs_recus_dons (
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee integer not null,
  dernier integer not null default 0,
  primary key (etablissement_id, annee)
);

create table if not exists public.engagements_dons (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  donateur_id uuid not null references public.donateurs (id),
  affectation_id uuid references public.affectations_dons (id),
  fiche_eleve_id uuid references public.fiches_eleves (id),
  montant numeric(18, 2) not null check (montant > 0),
  periodicite text not null default 'mensuelle' check (periodicite in ('mensuelle', 'trimestrielle', 'annuelle')),
  date_debut date not null default current_date,
  date_fin date,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint engagements_dons_dates check (date_fin is null or date_fin >= date_debut)
);
create index if not exists idx_engagements_dons_etablissement on public.engagements_dons (etablissement_id) where actif;

create table if not exists public.emplois_fonds_affectes (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  affectation_id uuid not null references public.affectations_dons (id),
  montant numeric(18, 2) not null check (montant > 0),
  date_emploi date not null default current_date,
  libelle text not null check (char_length(trim(libelle)) between 3 and 300),
  statut text not null default 'valide' check (statut in ('valide', 'annule')),
  motif_annulation text,
  saisi_par uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index if not exists idx_emplois_fonds_affectation on public.emplois_fonds_affectes (affectation_id);

-- Cohérence multi-établissement des références (donateur, campagne, élève).
create or replace function public.dons_verifie_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.donateur_id is not null and not exists (
       select 1 from public.donateurs d where d.id = new.donateur_id and d.etablissement_id = new.etablissement_id) then
    raise exception 'DONATEUR_INCONNU' using errcode = '23503';
  end if;
  if new.affectation_id is not null and not exists (
       select 1 from public.affectations_dons a where a.id = new.affectation_id and a.etablissement_id = new.etablissement_id) then
    raise exception 'AFFECTATION_INCONNUE' using errcode = '23503';
  end if;
  if new.fiche_eleve_id is not null and not exists (
       select 1 from public.fiches_eleves f where f.id = new.fiche_eleve_id and f.etablissement_id = new.etablissement_id) then
    raise exception 'ELEVE_INCONNU' using errcode = '23503';
  end if;
  return new;
end;
$$;

drop trigger if exists dons_verifie_tenant on public.dons;
create trigger dons_verifie_tenant
  before insert on public.dons
  for each row execute function public.dons_verifie_tenant();

drop trigger if exists engagements_dons_verifie_tenant on public.engagements_dons;
create trigger engagements_dons_verifie_tenant
  before insert or update on public.engagements_dons
  for each row execute function public.dons_verifie_tenant();

-- Une campagne qui a reçu des dons ne change plus de type : sa
-- comptabilisation (fonds affectés ou produit) en dépend.
create or replace function public.affectations_dons_type_fige()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.type is distinct from old.type and exists (select 1 from public.dons where affectation_id = old.id) then
    raise exception 'AFFECTATION_UTILISEE' using errcode = '55000';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists affectations_dons_type_fige on public.affectations_dons;
create trigger affectations_dons_type_fige
  before update on public.affectations_dons
  for each row execute function public.affectations_dons_type_fige();

-- Dons et emplois : écriture par les fonctions ci-dessous uniquement ;
-- une ligne validée ne change plus, sauf pour être annulée.
create or replace function public.dons_immuables()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'DON_IMMUABLE' using errcode = '42501';
  end if;
  if old.statut = 'annule'
     or (to_jsonb(new) - 'statut' - 'motif_annulation' - 'annule_par' - 'annule_le')
        <> (to_jsonb(old) - 'statut' - 'motif_annulation' - 'annule_par' - 'annule_le') then
    raise exception 'DON_IMMUABLE' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists dons_immuables on public.dons;
create trigger dons_immuables
  before update or delete on public.dons
  for each row execute function public.dons_immuables();

drop trigger if exists emplois_fonds_immuables on public.emplois_fonds_affectes;
create trigger emplois_fonds_immuables
  before update or delete on public.emplois_fonds_affectes
  for each row execute function public.dons_immuables();

-- Le second trigger vise une table sans annule_par / annule_le : les clés
-- absentes sont ignorées par `-` sur jsonb, le contrôle reste valable.

-- ---------------------------------------------------------------------------
-- 3. RLS : direction et comptables (données personnelles des donateurs)
-- ---------------------------------------------------------------------------
alter table public.donateurs enable row level security;
alter table public.affectations_dons enable row level security;
alter table public.dons enable row level security;
alter table public.compteurs_recus_dons enable row level security;
alter table public.engagements_dons enable row level security;
alter table public.emplois_fonds_affectes enable row level security;

drop policy if exists donateurs_lecture on public.donateurs;
create policy donateurs_lecture on public.donateurs for select
  using (public.est_comptable(etablissement_id));
drop policy if exists donateurs_ecriture on public.donateurs;
create policy donateurs_ecriture on public.donateurs for all
  using (public.est_comptable_ecriture(etablissement_id))
  with check (public.est_comptable_ecriture(etablissement_id));

drop policy if exists affectations_dons_lecture on public.affectations_dons;
create policy affectations_dons_lecture on public.affectations_dons for select
  using (public.est_comptable(etablissement_id));
drop policy if exists affectations_dons_ecriture on public.affectations_dons;
create policy affectations_dons_ecriture on public.affectations_dons for all
  using (public.est_comptable_ecriture(etablissement_id))
  with check (public.est_comptable_ecriture(etablissement_id));

drop policy if exists engagements_dons_lecture on public.engagements_dons;
create policy engagements_dons_lecture on public.engagements_dons for select
  using (public.est_comptable(etablissement_id));
drop policy if exists engagements_dons_ecriture on public.engagements_dons;
create policy engagements_dons_ecriture on public.engagements_dons for all
  using (public.est_comptable_ecriture(etablissement_id))
  with check (public.est_comptable_ecriture(etablissement_id));

drop policy if exists dons_lecture on public.dons;
create policy dons_lecture on public.dons for select
  using (public.est_comptable(etablissement_id));
drop policy if exists emplois_fonds_lecture on public.emplois_fonds_affectes;
create policy emplois_fonds_lecture on public.emplois_fonds_affectes for select
  using (public.est_comptable(etablissement_id));

revoke insert, update, delete on public.dons, public.emplois_fonds_affectes, public.compteurs_recus_dons
  from anon, authenticated;
revoke all on public.compteurs_recus_dons from anon, authenticated;

-- Pas de suppression physique d'un donateur ayant donné : archivage.
create or replace function public.donateurs_suppression()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (select 1 from public.dons where donateur_id = old.id) then
    raise exception 'DONATEUR_A_DES_DONS' using errcode = '55000';
  end if;
  return old;
end;
$$;

drop trigger if exists donateurs_suppression on public.donateurs;
create trigger donateurs_suppression
  before delete on public.donateurs
  for each row execute function public.donateurs_suppression();

-- ---------------------------------------------------------------------------
-- 4. Comptes par défaut et contraintes partagées
-- ---------------------------------------------------------------------------
alter table public.pieces_comptables drop constraint if exists pieces_comptables_source_type_check;
alter table public.pieces_comptables add constraint pieces_comptables_source_type_check
  check (source_type is null or source_type in (
    'encaissement_scolarite', 'produits_constates_avance', 'extourne_pca',
    'paie_constatation', 'paie_reglement', 'paie_constatation_annulee', 'paie_reglement_annule',
    'don', 'emploi_fonds_affectes'));

alter table public.regles_comptabilisation drop constraint if exists regles_comptabilisation_cle_check;
alter table public.regles_comptabilisation add constraint regles_comptabilisation_cle_check
  check (cle in (
    'tresorerie:especes', 'tresorerie:mobile_money', 'tresorerie:virement', 'tresorerie:cheque', 'tresorerie:autre',
    'produit:scolarite', 'produit:inscription', 'produit:cantine', 'produit:transport', 'produit:autre',
    'paie:charge', 'paie:dette', 'paie:retenues', 'paie:tresorerie',
    'don:don', 'don:legs', 'don:denier_culte', 'don:quete', 'don:mecenat', 'don:parrainage', 'don:autre',
    'don:fonds_affectes', 'don:reprise_fonds_affectes'));

create or replace function public.code_compte_par_defaut(p_plan text, p_cle text)
returns text
language sql
immutable
as $$
  select case p_cle
    when 'tresorerie:especes' then '571'
    when 'tresorerie:autre' then '571'
    when 'tresorerie:mobile_money' then '5521'
    when 'tresorerie:virement' then '521'
    when 'tresorerie:cheque' then '521'
    when 'paie:dette' then '422'
    when 'paie:tresorerie' then '571'
    else case p_plan
      when 'syscohada' then case
        when p_cle = 'produit:scolarite' then '70611' when p_cle = 'produit:inscription' then '70612'
        when p_cle = 'produit:cantine' then '70613' when p_cle = 'produit:transport' then '70614'
        when p_cle = 'produit:autre' then '70618'
        when p_cle = 'paie:charge' then '661' when p_cle = 'paie:retenues' then '447'
        when p_cle = 'don:reprise_fonds_affectes' then null
        when p_cle like 'don:%' then '758' end
      when 'sycebnl' then case p_cle
        when 'produit:scolarite' then '70521' when 'produit:inscription' then '70522'
        when 'produit:cantine' then '70523' when 'produit:transport' then '70524'
        when 'produit:autre' then '70528'
        when 'paie:charge' then '66' when 'paie:retenues' then '44'
        when 'don:don' then '7041' when 'don:legs' then '7042' when 'don:denier_culte' then '7043'
        when 'don:quete' then '7044' when 'don:mecenat' then '7046' when 'don:parrainage' then '7047'
        when 'don:autre' then '7048'
        when 'don:fonds_affectes' then '165' when 'don:reprise_fonds_affectes' then '7925' end
    end
  end;
$$;

-- Vrai si l'école a une comptabilité automatique pour une famille de règles.
create or replace function public.comptabilisation_applicable(p_etablissement uuid, p_famille text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.plan_du_referentiel(public.referentiel_comptable_de(p_etablissement)) is not null
      or exists (select 1 from public.regles_comptabilisation
                  where etablissement_id = p_etablissement and cle like p_famille || ':%');
$$;

-- ---------------------------------------------------------------------------
-- 5. Comptabilisation d'un don et d'un emploi de fonds affectés
-- ---------------------------------------------------------------------------
create or replace function public.journal_operations_diverses(p_etablissement uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.journaux (etablissement_id, code, intitule, type)
  values (p_etablissement, 'OD', 'Opérations diverses', 'operations')
  on conflict (etablissement_id, code) do update set deleted_at = null
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.libelle_nature_don(p_nature text)
returns text
language sql
immutable
as $$
  select case p_nature
    when 'don' then 'Don' when 'legs' then 'Legs' when 'denier_culte' then 'Denier du culte'
    when 'quete' then 'Quête' when 'mecenat' then 'Mécénat' when 'parrainage' then 'Parrainage'
    else 'Don' end;
$$;

create or replace function public.comptabiliser_don(p_don_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  d public.dons;
  a public.affectations_dons;
  x public.exercices_comptables;
  v_piece public.pieces_comptables;
  v_tresorerie uuid;
  v_credit uuid;
  v_id uuid;
  v_nom text;
begin
  select * into d from public.dons where id = p_don_id;
  if d.id is null then
    return 'introuvable';
  end if;

  select * into v_piece from public.pieces_comptables
   where source_type = 'don' and source_id = d.id and origine = 'automatique';

  if d.statut = 'annule' then
    if v_piece.id is null or v_piece.annulee_par_piece_id is not null then
      return 'rien_a_faire';
    end if;
    perform public.contrepasser_piece_interne(v_piece.id,
      'Annulation du reçu ' || d.numero_recu || ' : ' || d.motif_annulation,
      greatest(coalesce(d.annule_le::date, current_date), v_piece.date_piece), d.annule_par);
    return 'contrepassee';
  end if;

  if v_piece.id is not null then
    return 'deja_comptabilise';
  end if;
  if not public.comptabilisation_applicable(d.etablissement_id, 'don') then
    return 'non_applicable';
  end if;

  select * into a from public.affectations_dons where id = d.affectation_id;
  v_tresorerie := public.compte_comptabilisation(d.etablissement_id, 'tresorerie:' || d.moyen_paiement::text);
  v_credit := public.compte_comptabilisation(d.etablissement_id,
    case when a.type = 'projet' then 'don:fonds_affectes' else 'don:' || d.nature end);
  if v_tresorerie is null or v_credit is null then
    raise exception 'COMPTE_AUTO_INTROUVABLE' using errcode = '55000';
  end if;

  x := public.exercice_ouvert_pour(d.etablissement_id, d.date_don);
  if x.id is null then
    raise exception 'AUCUN_EXERCICE_OUVERT' using errcode = '55000';
  end if;
  if public.date_comptable_figee(d.etablissement_id, d.date_don) then
    raise exception 'PERIODE_CLOTUREE' using errcode = '55000';
  end if;

  select nullif(trim(coalesce(o.nom, '') || ' ' || coalesce(o.prenom, '')), '') into v_nom
    from public.donateurs o where o.id = d.donateur_id;

  insert into public.pieces_comptables
    (etablissement_id, exercice_id, journal_id, date_piece, libelle, piece_justificative, origine,
     cree_par, source_type, source_id)
  values (d.etablissement_id, x.id, public.journal_automatique(d.etablissement_id, d.moyen_paiement::text), d.date_don,
          left(public.libelle_nature_don(d.nature)
               || case when d.anonyme then ' anonyme' else coalesce(' — ' || v_nom, '') end
               || coalesce(' — ' || a.libelle, ''), 300),
          d.numero_recu, 'automatique', d.saisi_par, 'don', d.id)
  returning id into v_id;

  insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, debit, credit, ordre) values
    (v_id, d.etablissement_id, v_tresorerie, d.montant, 0, 0),
    (v_id, d.etablissement_id, v_credit, 0, d.montant, 1);

  perform public.numeroter_et_valider_piece(v_id, null);
  return 'comptabilise';
end;
$$;

create or replace function public.comptabiliser_emploi_fonds(p_emploi_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  em public.emplois_fonds_affectes;
  a public.affectations_dons;
  x public.exercices_comptables;
  v_piece public.pieces_comptables;
  v_fonds public.plans_comptables;
  v_reprise uuid;
  v_id uuid;
begin
  select * into em from public.emplois_fonds_affectes where id = p_emploi_id;
  if em.id is null then
    return 'introuvable';
  end if;
  select * into v_piece from public.pieces_comptables
   where source_type = 'emploi_fonds_affectes' and source_id = em.id and origine = 'automatique';

  if em.statut = 'annule' then
    if v_piece.id is null or v_piece.annulee_par_piece_id is not null then
      return 'rien_a_faire';
    end if;
    perform public.contrepasser_piece_interne(v_piece.id,
      'Annulation de l''emploi de fonds : ' || em.motif_annulation, greatest(current_date, v_piece.date_piece), null);
    return 'contrepassee';
  end if;
  if v_piece.id is not null then
    return 'deja_comptabilise';
  end if;
  if not public.comptabilisation_applicable(em.etablissement_id, 'don') then
    return 'non_applicable';
  end if;

  -- Les dons affectés n'ont été portés en fonds affectés (classe 1) que si
  -- le compte choisi en est un ; sinon ils sont déjà en produits et
  -- l'emploi n'appelle pas d'écriture : le registre suffit.
  select * into v_fonds from public.plans_comptables
   where id = public.compte_comptabilisation(em.etablissement_id, 'don:fonds_affectes');
  if v_fonds.id is null or v_fonds.type <> 'capitaux' then
    return 'non_applicable';
  end if;
  v_reprise := public.compte_comptabilisation(em.etablissement_id, 'don:reprise_fonds_affectes');
  if v_reprise is null then
    raise exception 'COMPTE_AUTO_INTROUVABLE' using errcode = '55000';
  end if;

  x := public.exercice_ouvert_pour(em.etablissement_id, em.date_emploi);
  if x.id is null then
    raise exception 'AUCUN_EXERCICE_OUVERT' using errcode = '55000';
  end if;
  if public.date_comptable_figee(em.etablissement_id, em.date_emploi) then
    raise exception 'PERIODE_CLOTUREE' using errcode = '55000';
  end if;
  select * into a from public.affectations_dons where id = em.affectation_id;

  insert into public.pieces_comptables
    (etablissement_id, exercice_id, journal_id, date_piece, libelle, piece_justificative, origine,
     cree_par, source_type, source_id)
  values (em.etablissement_id, x.id, public.journal_operations_diverses(em.etablissement_id), em.date_emploi,
          left('Emploi des fonds affectés — ' || a.libelle || ' — ' || em.libelle, 300),
          'EMP-' || upper(left(replace(em.id::text, '-', ''), 8)), 'automatique', em.saisi_par,
          'emploi_fonds_affectes', em.id)
  returning id into v_id;

  insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, debit, credit, ordre) values
    (v_id, em.etablissement_id, v_fonds.id, em.montant, 0, 0),
    (v_id, em.etablissement_id, v_reprise, 0, em.montant, 1);

  perform public.numeroter_et_valider_piece(v_id, null);
  return 'comptabilise';
end;
$$;

-- Déclencheurs communs : jamais bloquants.
create or replace function public.dons_comptabiliser()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text := case tg_table_name when 'dons' then 'don' else 'emploi_fonds_affectes' end;
begin
  begin
    if v_type = 'don' then
      perform public.comptabiliser_don(new.id);
    else
      perform public.comptabiliser_emploi_fonds(new.id);
    end if;
    update public.incidents_comptabilisation set resolu = true, resolu_le = now()
     where source_type = v_type and source_id = new.id and not resolu;
  exception when others then
    insert into public.incidents_comptabilisation (etablissement_id, source_type, source_id, operation, code, detail)
    values (new.etablissement_id, v_type, new.id,
            case when new.statut = 'annule' then 'annulation' else 'comptabilisation' end, left(sqlerrm, 80), sqlstate);
  end;
  -- Journal d'audit : création et annulation.
  if tg_op = 'UPDATE' and old.statut is distinct from new.statut then
    perform public.enregistrer_audit(new.etablissement_id, v_type::public.type_entite_journal_audit, new.id, 'statut',
      to_jsonb(old.statut), to_jsonb(new.statut), null, null);
  end if;
  return null;
end;
$$;

drop trigger if exists dons_comptabiliser on public.dons;
create trigger dons_comptabiliser
  after insert or update on public.dons
  for each row execute function public.dons_comptabiliser();

drop trigger if exists emplois_fonds_comptabiliser on public.emplois_fonds_affectes;
create trigger emplois_fonds_comptabiliser
  after insert or update on public.emplois_fonds_affectes
  for each row execute function public.dons_comptabiliser();

-- ---------------------------------------------------------------------------
-- 6. Fonctions appelées par l'application
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_don(
  p_etablissement uuid,
  p_montant numeric,
  p_nature text default 'don',
  p_moyen text default 'especes',
  p_date date default current_date,
  p_donateur_id uuid default null,
  p_affectation_id uuid default null,
  p_fiche_eleve_id uuid default null,
  p_reference text default null,
  p_commentaire text default null,
  p_anonyme boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_annee integer := extract(year from coalesce(p_date, current_date))::int;
  v_numero integer;
  v_id uuid;
  v_recu text;
  a public.affectations_dons;
begin
  if not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;
  if p_nature is null or p_nature not in ('don', 'legs', 'denier_culte', 'quete', 'mecenat', 'parrainage', 'autre') then
    raise exception 'NATURE_INVALIDE' using errcode = '22023';
  end if;
  if p_date is null or p_date > current_date then
    raise exception 'DATE_DON_FUTURE' using errcode = '22023';
  end if;
  if p_donateur_id is not null and not exists (
       select 1 from public.donateurs where id = p_donateur_id and etablissement_id = p_etablissement and deleted_at is null) then
    raise exception 'DONATEUR_INCONNU' using errcode = '22023';
  end if;
  if p_affectation_id is not null then
    select * into a from public.affectations_dons where id = p_affectation_id and etablissement_id = p_etablissement;
    if a.id is null then
      raise exception 'AFFECTATION_INCONNUE' using errcode = '22023';
    end if;
    if not a.active then
      raise exception 'AFFECTATION_CLOSE' using errcode = '22023';
    end if;
  end if;
  if p_fiche_eleve_id is not null and not exists (
       select 1 from public.fiches_eleves where id = p_fiche_eleve_id and etablissement_id = p_etablissement) then
    raise exception 'ELEVE_INCONNU' using errcode = '22023';
  end if;

  -- Numéro de reçu continu par établissement et par année.
  insert into public.compteurs_recus_dons (etablissement_id, annee, dernier)
  values (p_etablissement, v_annee, 1)
  on conflict (etablissement_id, annee) do update set dernier = compteurs_recus_dons.dernier + 1
  returning dernier into v_numero;
  v_recu := 'REC-' || v_annee || '-' || lpad(v_numero::text, 6, '0');

  insert into public.dons
    (etablissement_id, numero_recu, donateur_id, nature, moyen_paiement, montant, date_don, affectation_id,
     fiche_eleve_id, reference_paiement, commentaire, anonyme, saisi_par)
  values (p_etablissement, v_recu, p_donateur_id, p_nature, p_moyen::public.moyen_paiement, round(p_montant, 2), p_date,
          p_affectation_id, p_fiche_eleve_id, nullif(trim(p_reference), ''), nullif(trim(p_commentaire), ''),
          coalesce(p_anonyme, false), auth.uid())
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'numero_recu', v_recu,
    'comptabilise', exists (select 1 from public.pieces_comptables
                             where source_type = 'don' and source_id = v_id and origine = 'automatique'),
    'incident', (select code from public.incidents_comptabilisation
                  where source_type = 'don' and source_id = v_id and not resolu limit 1));
exception
  when invalid_text_representation then
    raise exception 'MOYEN_INVALIDE' using errcode = '22023';
end;
$$;

create or replace function public.annuler_don(p_don_id uuid, p_motif text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  d public.dons;
begin
  select * into d from public.dons where id = p_don_id;
  if d.id is null or not coalesce(public.est_comptable_ecriture(d.etablissement_id), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if d.statut = 'annule' then
    raise exception 'DON_DEJA_ANNULE' using errcode = '55000';
  end if;
  if char_length(trim(coalesce(p_motif, ''))) < 3 then
    raise exception 'MOTIF_REQUIS' using errcode = '22023';
  end if;
  update public.dons
     set statut = 'annule', motif_annulation = trim(p_motif), annule_par = auth.uid(), annule_le = now()
   where id = p_don_id;
end;
$$;

-- Fonds d'une campagne : collecté, employé, disponible.
create or replace function public.solde_affectation(p_affectation_id uuid)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select sum(montant) from public.dons where affectation_id = p_affectation_id and statut = 'valide'), 0)
       - coalesce((select sum(montant) from public.emplois_fonds_affectes
                    where affectation_id = p_affectation_id and statut = 'valide'), 0);
$$;

create or replace function public.constater_emploi_fonds(
  p_affectation_id uuid, p_montant numeric, p_libelle text, p_date date default current_date)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  a public.affectations_dons;
  v_id uuid;
begin
  select * into a from public.affectations_dons where id = p_affectation_id for update;
  if a.id is null or not coalesce(public.est_comptable_ecriture(a.etablissement_id), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if a.type <> 'projet' then
    raise exception 'AFFECTATION_NON_PROJET' using errcode = '22023';
  end if;
  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;
  if p_date is null or p_date > current_date then
    raise exception 'DATE_FUTURE' using errcode = '22023';
  end if;
  if p_montant > public.solde_affectation(a.id) then
    raise exception 'FONDS_INSUFFISANTS' using errcode = '55000';
  end if;
  if char_length(trim(coalesce(p_libelle, ''))) < 3 then
    raise exception 'LIBELLE_REQUIS' using errcode = '22023';
  end if;

  insert into public.emplois_fonds_affectes (etablissement_id, affectation_id, montant, date_emploi, libelle, saisi_par)
  values (a.etablissement_id, a.id, round(p_montant, 2), p_date, trim(p_libelle), auth.uid())
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'solde', public.solde_affectation(a.id),
    'comptabilise', exists (select 1 from public.pieces_comptables
                             where source_type = 'emploi_fonds_affectes' and source_id = v_id and origine = 'automatique'));
end;
$$;

create or replace function public.annuler_emploi_fonds(p_emploi_id uuid, p_motif text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  em public.emplois_fonds_affectes;
begin
  select * into em from public.emplois_fonds_affectes where id = p_emploi_id;
  if em.id is null or not coalesce(public.est_comptable_ecriture(em.etablissement_id), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if em.statut = 'annule' then
    raise exception 'EMPLOI_DEJA_ANNULE' using errcode = '55000';
  end if;
  if char_length(trim(coalesce(p_motif, ''))) < 3 then
    raise exception 'MOTIF_REQUIS' using errcode = '22023';
  end if;
  update public.emplois_fonds_affectes set statut = 'annule', motif_annulation = trim(p_motif) where id = p_emploi_id;
end;
$$;

-- Reçu d'un don (pour le PDF) : tout ce qu'il faut, rien de plus.
create or replace function public.recu_don(p_don_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d public.dons;
begin
  select * into d from public.dons where id = p_don_id;
  if d.id is null or not coalesce(public.est_comptable(d.etablissement_id), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'id', d.id,
    'numero_recu', d.numero_recu,
    'date_don', d.date_don,
    'montant', d.montant,
    'nature', d.nature,
    'moyen_paiement', d.moyen_paiement,
    'reference_paiement', d.reference_paiement,
    'statut', d.statut,
    'motif_annulation', d.motif_annulation,
    'anonyme', d.anonyme,
    'affectation', (select a.libelle from public.affectations_dons a where a.id = d.affectation_id),
    'eleve', (select nullif(trim(f.prenom || ' ' || f.nom), '') from public.fiches_eleves f where f.id = d.fiche_eleve_id),
    'donateur', (select jsonb_build_object('nom', o.nom, 'prenom', o.prenom, 'type', o.type, 'adresse', o.adresse,
                                           'telephone', o.telephone, 'email', o.email)
                   from public.donateurs o where o.id = d.donateur_id),
    'saisi_par', (select nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), '')
                    from public.profiles p where p.id = d.saisi_par));
end;
$$;

-- Relevé annuel d'un donateur (attestation récapitulative).
create or replace function public.releve_donateur(p_donateur_id uuid, p_annee integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  o public.donateurs;
begin
  select * into o from public.donateurs where id = p_donateur_id;
  if o.id is null or not coalesce(public.est_comptable(o.etablissement_id), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'donateur', jsonb_build_object('id', o.id, 'nom', o.nom, 'prenom', o.prenom, 'type', o.type, 'adresse', o.adresse),
    'annee', p_annee,
    'total', coalesce((select sum(montant) from public.dons
                        where donateur_id = o.id and statut = 'valide' and extract(year from date_don) = p_annee), 0),
    'dons', coalesce((select jsonb_agg(jsonb_build_object(
                         'numero_recu', d.numero_recu, 'date_don', d.date_don, 'montant', d.montant, 'nature', d.nature,
                         'affectation', (select a.libelle from public.affectations_dons a where a.id = d.affectation_id))
                       order by d.date_don, d.numero_recu)
                       from public.dons d
                      where d.donateur_id = o.id and d.statut = 'valide' and extract(year from d.date_don) = p_annee),
                     '[]'::jsonb));
end;
$$;

-- Nombre d'échéances d'un engagement arrivées dans l'année, à ce jour.
create or replace function public.echeances_engagement(e public.engagements_dons, p_annee integer, p_au date)
returns integer
language sql
immutable
as $$
  select count(*)::int
    from generate_series(e.date_debut,
                         least(coalesce(e.date_fin, p_au), p_au, make_date(p_annee, 12, 31)),
                         case e.periodicite when 'mensuelle' then interval '1 month'
                                            when 'trimestrielle' then interval '3 months'
                                            else interval '1 year' end) as g(echeance)
   where g.echeance >= make_date(p_annee, 1, 1);
$$;

create or replace function public.tableau_bord_dons(p_etablissement uuid, p_annee integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_annee integer := coalesce(p_annee, extract(year from current_date)::int);
  v_au date := least(current_date, make_date(v_annee, 12, 31));
begin
  if not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'annee', v_annee,
    'total', coalesce((select sum(montant) from public.dons
                        where etablissement_id = p_etablissement and statut = 'valide'
                          and extract(year from date_don) = v_annee), 0),
    'total_annee_precedente', coalesce((select sum(montant) from public.dons
                        where etablissement_id = p_etablissement and statut = 'valide'
                          and extract(year from date_don) = v_annee - 1), 0),
    'nombre_dons', (select count(*) from public.dons
                     where etablissement_id = p_etablissement and statut = 'valide'
                       and extract(year from date_don) = v_annee),
    'nombre_donateurs', (select count(distinct donateur_id) from public.dons
                          where etablissement_id = p_etablissement and statut = 'valide'
                            and extract(year from date_don) = v_annee),
    -- Premier don cette année.
    'nouveaux_donateurs', (select count(*) from (
        select donateur_id from public.dons
         where etablissement_id = p_etablissement and statut = 'valide' and donateur_id is not null
         group by donateur_id
        having min(date_don) >= make_date(v_annee, 1, 1) and min(date_don) <= make_date(v_annee, 12, 31)) n),
    -- Ont donné cette année ET l'année précédente.
    'donateurs_fideles', (select count(*) from (
        select donateur_id from public.dons
         where etablissement_id = p_etablissement and statut = 'valide' and donateur_id is not null
           and extract(year from date_don) in (v_annee, v_annee - 1)
         group by donateur_id
        having count(distinct extract(year from date_don)) = 2) f),
    'par_nature', coalesce((select jsonb_agg(jsonb_build_object('nature', nature, 'montant', s, 'nombre', n) order by s desc)
        from (select nature, sum(montant) s, count(*) n from public.dons
               where etablissement_id = p_etablissement and statut = 'valide'
                 and extract(year from date_don) = v_annee group by nature) t), '[]'::jsonb),
    'par_moyen', coalesce((select jsonb_agg(jsonb_build_object('moyen', moyen, 'montant', s) order by s desc)
        from (select moyen_paiement::text moyen, sum(montant) s from public.dons
               where etablissement_id = p_etablissement and statut = 'valide'
                 and extract(year from date_don) = v_annee group by moyen_paiement) t), '[]'::jsonb),
    -- Campagnes : collecté depuis l'origine (un projet dure souvent plus
    -- d'un an), employé, disponible, progression vers l'objectif.
    'affectations', coalesce((select jsonb_agg(jsonb_build_object(
          'id', a.id, 'libelle', a.libelle, 'type', a.type, 'active', a.active, 'objectif', a.objectif,
          'date_fin', a.date_fin,
          'collecte', c.collecte, 'collecte_annee', c.collecte_annee, 'emploie', c.emploie,
          'disponible', c.collecte - c.emploie, 'donateurs', c.donateurs)
        order by a.active desc, a.libelle)
        from public.affectations_dons a
        cross join lateral (
          select coalesce(sum(d.montant) filter (where d.statut = 'valide'), 0) collecte,
                 coalesce(sum(d.montant) filter (where d.statut = 'valide' and extract(year from d.date_don) = v_annee), 0) collecte_annee,
                 count(distinct d.donateur_id) filter (where d.statut = 'valide') donateurs,
                 coalesce((select sum(em.montant) from public.emplois_fonds_affectes em
                            where em.affectation_id = a.id and em.statut = 'valide'), 0) emploie
            from public.dons d where d.affectation_id = a.id) c
       where a.etablissement_id = p_etablissement), '[]'::jsonb),
    'meilleurs_donateurs', coalesce((select jsonb_agg(jsonb_build_object(
          'donateur_id', t.donateur_id, 'nom', t.nom, 'montant', t.s, 'nombre', t.n) order by t.s desc)
        from (select d.donateur_id,
                     case when bool_or(d.anonyme) then 'Donateur anonyme'
                          else max(trim(o.nom || ' ' || coalesce(o.prenom, ''))) end nom,
                     sum(d.montant) s, count(*) n
                from public.dons d join public.donateurs o on o.id = d.donateur_id
               where d.etablissement_id = p_etablissement and d.statut = 'valide'
                 and extract(year from d.date_don) = v_annee
               group by d.donateur_id order by sum(d.montant) desc limit 10) t), '[]'::jsonb),
    -- À relancer : ont donné l'an dernier, rien cette année, et acceptent
    -- d'être contactés.
    'a_relancer', coalesce((select jsonb_agg(jsonb_build_object(
          'donateur_id', o.id, 'nom', trim(o.nom || ' ' || coalesce(o.prenom, '')), 'telephone', o.telephone,
          'email', o.email, 'montant_annee_precedente', p.s, 'dernier_don', p.dernier) order by p.s desc)
        from public.donateurs o
        join (select donateur_id, sum(montant) s, max(date_don) dernier from public.dons
               where etablissement_id = p_etablissement and statut = 'valide'
                 and extract(year from date_don) = v_annee - 1 group by donateur_id) p on p.donateur_id = o.id
       where o.deleted_at is null and o.accepte_contact
         and not exists (select 1 from public.dons d where d.donateur_id = o.id and d.statut = 'valide'
                           and extract(year from d.date_don) = v_annee)), '[]'::jsonb),
    -- Engagements : attendu à ce jour dans l'année, reçu, retard.
    'engagements', coalesce((select jsonb_agg(jsonb_build_object(
          'id', e.id, 'donateur_id', e.donateur_id, 'donateur', trim(o.nom || ' ' || coalesce(o.prenom, '')),
          'affectation', (select a.libelle from public.affectations_dons a where a.id = e.affectation_id),
          'eleve', (select nullif(trim(f.prenom || ' ' || f.nom), '') from public.fiches_eleves f where f.id = e.fiche_eleve_id),
          'montant', e.montant, 'periodicite', e.periodicite,
          'attendu', x.attendu, 'recu', x.recu, 'retard', greatest(x.attendu - x.recu, 0))
        order by greatest(x.attendu - x.recu, 0) desc, o.nom)
        from public.engagements_dons e
        join public.donateurs o on o.id = e.donateur_id
        cross join lateral (
          select e.montant * public.echeances_engagement(e, v_annee, v_au) attendu,
                 coalesce((select sum(d.montant) from public.dons d
                            where d.donateur_id = e.donateur_id and d.statut = 'valide'
                              and extract(year from d.date_don) = v_annee
                              and d.affectation_id is not distinct from e.affectation_id
                              and (e.fiche_eleve_id is null or d.fiche_eleve_id = e.fiche_eleve_id)), 0) recu) x
       where e.etablissement_id = p_etablissement and e.actif), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Rattrapage et état : les dons rejoignent encaissements et paie
-- ---------------------------------------------------------------------------
create or replace function public.dons_a_comptabiliser(p_etablissement uuid)
returns table (source_type text, source_id uuid, operation text)
language sql
stable
security definer
set search_path = public
as $$
  select 'don', d.id, case when d.statut = 'annule' then 'annulation' else 'comptabilisation' end
    from public.dons d
    left join public.pieces_comptables p
      on p.source_type = 'don' and p.source_id = d.id and p.origine = 'automatique'
   where d.etablissement_id = p_etablissement
     and ((d.statut = 'valide' and p.id is null and public.comptabilisation_applicable(p_etablissement, 'don'))
          or (d.statut = 'annule' and p.id is not null and p.annulee_par_piece_id is null))
  union all
  select 'emploi_fonds_affectes', em.id, case when em.statut = 'annule' then 'annulation' else 'comptabilisation' end
    from public.emplois_fonds_affectes em
    left join public.pieces_comptables p
      on p.source_type = 'emploi_fonds_affectes' and p.source_id = em.id and p.origine = 'automatique'
   where em.etablissement_id = p_etablissement
     and ((em.statut = 'valide' and p.id is null and coalesce((
             select c.type = 'capitaux' from public.plans_comptables c
              where c.id = public.compte_comptabilisation(p_etablissement, 'don:fonds_affectes')), false))
          or (em.statut = 'annule' and p.id is not null and p.annulee_par_piece_id is null));
$$;

create or replace function public.comptabiliser_en_attente(p_etablissement uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r record;
  v_ok integer := 0;
  v_echecs integer := 0;
  v_resultat text;
begin
  if not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;

  -- Encaissements (lot C3).
  for r in
    select e.id, e.statut::text as statut
      from public.encaissements_scolarite e
      left join public.pieces_comptables p
        on p.source_type = 'encaissement_scolarite' and p.source_id = e.id and p.origine = 'automatique'
     where e.etablissement_id = p_etablissement
       and ((e.statut = 'valide' and p.id is null)
            or (e.statut = 'annule' and p.id is not null and p.annulee_par_piece_id is null))
     order by e.date_paiement, e.created_at
  loop
    begin
      v_resultat := public.comptabiliser_encaissement(r.id);
      if v_resultat in ('comptabilise', 'contrepassee') then
        v_ok := v_ok + 1;
        update public.incidents_comptabilisation set resolu = true, resolu_le = now()
         where source_type = 'encaissement_scolarite' and source_id = r.id and not resolu;
      end if;
    exception when others then
      v_echecs := v_echecs + 1;
      if not exists (select 1 from public.incidents_comptabilisation
                      where source_type = 'encaissement_scolarite' and source_id = r.id and not resolu
                        and code = left(sqlerrm, 80)) then
        insert into public.incidents_comptabilisation (etablissement_id, source_type, source_id, operation, code, detail)
        values (p_etablissement, 'encaissement_scolarite', r.id,
                case when r.statut = 'annule' then 'annulation' else 'comptabilisation' end, left(sqlerrm, 80), sqlstate);
      end if;
    end;
  end loop;

  -- Paie (lot C5).
  for r in select id from public.paie_a_synchroniser(p_etablissement) as t(id) loop
    begin
      v_resultat := public.synchroniser_paie(r.id);
      if v_resultat not in ('a_jour', 'non_applicable', 'introuvable') then
        v_ok := v_ok + 1;
      end if;
      update public.incidents_comptabilisation set resolu = true, resolu_le = now()
       where source_type = 'paie_bulletin' and source_id = r.id and not resolu;
    exception when others then
      v_echecs := v_echecs + 1;
      if not exists (select 1 from public.incidents_comptabilisation
                      where source_type = 'paie_bulletin' and source_id = r.id and not resolu and code = left(sqlerrm, 80)) then
        insert into public.incidents_comptabilisation (etablissement_id, source_type, source_id, operation, code, detail)
        values (p_etablissement, 'paie_bulletin', r.id, 'comptabilisation', left(sqlerrm, 80), sqlstate);
      end if;
    end;
  end loop;

  -- Dons et emplois de fonds affectés (lot C5) : dons d'abord, par date.
  for r in
    select t.source_type, t.source_id, t.operation
      from public.dons_a_comptabiliser(p_etablissement) t
     order by t.source_type = 'emploi_fonds_affectes', t.operation = 'annulation'
  loop
    begin
      v_resultat := case r.source_type when 'don' then public.comptabiliser_don(r.source_id)
                                       else public.comptabiliser_emploi_fonds(r.source_id) end;
      if v_resultat in ('comptabilise', 'contrepassee') then
        v_ok := v_ok + 1;
      end if;
      update public.incidents_comptabilisation set resolu = true, resolu_le = now()
       where source_type = r.source_type and source_id = r.source_id and not resolu;
    exception when others then
      v_echecs := v_echecs + 1;
      if not exists (select 1 from public.incidents_comptabilisation
                      where source_type = r.source_type and source_id = r.source_id and not resolu
                        and code = left(sqlerrm, 80)) then
        insert into public.incidents_comptabilisation (etablissement_id, source_type, source_id, operation, code, detail)
        values (p_etablissement, r.source_type, r.source_id, r.operation, left(sqlerrm, 80), sqlstate);
      end if;
    end;
  end loop;

  return jsonb_build_object('comptabilises', v_ok, 'en_echec', v_echecs);
end;
$$;

create or replace function public.etat_comptabilisation_automatique(p_etablissement uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_plan text := public.plan_du_referentiel(public.referentiel_comptable_de(p_etablissement));
begin
  if not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'active', v_plan is not null
              or exists (select 1 from public.regles_comptabilisation where etablissement_id = p_etablissement),
    'non_comptabilises', (
      select count(*) from public.encaissements_scolarite e
       where e.etablissement_id = p_etablissement and e.statut = 'valide'
         and not exists (select 1 from public.pieces_comptables p
                          where p.source_type = 'encaissement_scolarite' and p.source_id = e.id and p.origine = 'automatique')),
    'annulations_en_attente', (
      select count(*) from public.encaissements_scolarite e
        join public.pieces_comptables p
          on p.source_type = 'encaissement_scolarite' and p.source_id = e.id and p.origine = 'automatique'
       where e.etablissement_id = p_etablissement and e.statut = 'annule' and p.annulee_par_piece_id is null),
    'paies_a_synchroniser', (select count(*) from public.paie_a_synchroniser(p_etablissement)),
    'dons_a_comptabiliser', (select count(*) from public.dons_a_comptabiliser(p_etablissement)),
    'incidents', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', i.id, 'source_id', i.source_id, 'source_type', i.source_type,
               'operation', i.operation, 'code', i.code, 'le', i.created_at)
             order by i.created_at desc)
        from (select * from public.incidents_comptabilisation
               where etablissement_id = p_etablissement and not resolu
               order by created_at desc limit 50) i), '[]'::jsonb),
    'regles', coalesce((
      select jsonb_agg(jsonb_build_object(
               'cle', k.cle,
               'compte_id', public.compte_comptabilisation(p_etablissement, k.cle),
               'compte_code', c.code, 'compte_intitule', c.intitule,
               'personnalisee', exists (select 1 from public.regles_comptabilisation r
                                         where r.etablissement_id = p_etablissement and r.cle = k.cle))
             order by k.ordre)
        from (values
          (1, 'tresorerie:especes'), (2, 'tresorerie:mobile_money'), (3, 'tresorerie:virement'),
          (4, 'tresorerie:cheque'), (5, 'tresorerie:autre'), (6, 'produit:scolarite'),
          (7, 'produit:inscription'), (8, 'produit:cantine'), (9, 'produit:transport'), (10, 'produit:autre'),
          (11, 'paie:charge'), (12, 'paie:dette'), (13, 'paie:retenues'), (14, 'paie:tresorerie'),
          (15, 'don:don'), (16, 'don:legs'), (17, 'don:denier_culte'), (18, 'don:quete'), (19, 'don:mecenat'),
          (20, 'don:parrainage'), (21, 'don:autre'), (22, 'don:fonds_affectes'), (23, 'don:reprise_fonds_affectes')
        ) as k(ordre, cle)
        left join public.plans_comptables c on c.id = public.compte_comptabilisation(p_etablissement, k.cle)), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Droits sur les fonctions
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.dons_verifie_tenant()',
    'public.affectations_dons_type_fige()',
    'public.dons_immuables()',
    'public.donateurs_suppression()',
    'public.comptabilisation_applicable(uuid, text)',
    'public.journal_operations_diverses(uuid)',
    'public.comptabiliser_don(uuid)',
    'public.comptabiliser_emploi_fonds(uuid)',
    'public.dons_comptabiliser()',
    'public.dons_a_comptabiliser(uuid)',
    'public.solde_affectation(uuid)',
    'public.echeances_engagement(public.engagements_dons, integer, date)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;

  foreach f in array array[
    'public.enregistrer_don(uuid, numeric, text, text, date, uuid, uuid, uuid, text, text, boolean)',
    'public.annuler_don(uuid, text)',
    'public.constater_emploi_fonds(uuid, numeric, text, date)',
    'public.annuler_emploi_fonds(uuid, text)',
    'public.recu_don(uuid)',
    'public.releve_donateur(uuid, integer)',
    'public.tableau_bord_dons(uuid, integer)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;
