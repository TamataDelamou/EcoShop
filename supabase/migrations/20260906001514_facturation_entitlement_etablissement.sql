-- ============================================================================
-- EcoShop — Chantier Facturation/Quota IA — Étape (a) : primitive
-- d'entitlement établissement générique.
--
-- Périmètre : licence Pro établissement (barème par tranche, cumulatif,
-- §2.4/17.7/36.1) et frais IA admin annuel (montant fixe, §17.7/21.1/36.1).
-- Le chapitre 18 (§18.7) et le futur tarif du point de retrait marketplace
-- (§27.16) réutiliseront cette même primitive plus tard — chapitre 18
-- consomme directement entitlement_actif(etab, 'licence_pro', ...), aucun
-- type dédié ; le point de retrait n'ajoute RIEN ici (modèle tarifaire non
-- arbitré, §27.16 interdit explicitement toute table/champ avant activation
-- — l'enum s'étendra proprement par ALTER TYPE ... ADD VALUE le jour venu).
--
-- **Amélioration assumée par rapport à ecoshop_flutter** (VERSION_PRO.md) :
-- la référence recalcule "l'année scolaire en cours" par une heuristique de
-- bascule au 1er septembre, dupliquée client/serveur, faute de document
-- Firestore faisant autorité. EcoShop a déjà une vraie table
-- `annees_scolaires` par établissement avec un flag `courante` garanti
-- unique par index partiel (M1) — cette primitive s'appuie dessus plutôt
-- que de reproduire l'heuristique. Approuvé explicitement par le porteur de
-- projet, documenté ici comme tel (pas une lacune, un vrai mieux).
--
-- Stockage séparé par type (licence Pro / frais IA admin), jamais mutualisé
-- en une seule table générique — même discipline que VERSION_PRO.md règle
-- absolue 9 ("ne jamais généraliser une logique conçue pour une cadence aux
-- deux autres"). Un seul contrat d'accès unifié pour les consommateurs :
-- entitlement_actif(etablissement, type, annee_scolaire).
--
-- Deux corrections de sécurité actées avant écriture (issues de l'audit RPC,
-- migration 20260906001513) :
--   1. coalesce(est_admin_gsg(), false) dans les deux RPC d'écriture —
--      est_admin_gsg() dépend de role_racine, nullable par conception,
--      IF NOT est_admin_gsg() sans coalesce serait l'anti-patron NULL déjà
--      corrigé ailleurs.
--   2. entitlement_actif() vérifie elle-même est_personnel(etablissement)
--      OR est_admin_gsg() avant de renvoyer son booléen — étant security
--      definer, elle contournerait sinon la RLS des tables et laisserait
--      n'importe quel compte authentifié sonder le statut de paiement de
--      n'importe quel établissement (même classe de fuite inter-
--      établissements que l'audit RPC visait à éliminer partout).
--
-- Renouvellement manuel pour cette passe (décision actée) : les deux RPC
-- d'écriture sont réservées à est_admin_gsg() — pas de circuit CinetPay
-- encore câblé (étape b, distincte). Barème/tarif : valeurs PLACEHOLDER
-- explicitement signalées comme telles, à remplacer par le porteur de
-- projet avant toute activation réelle — configurables sans code (§30.4),
-- non bloquant pour livrer le schéma.
--
-- Hors périmètre de cette étape (tracé pour la suite, pas construit ici) :
-- blocage d'inscription au-delà de la tranche payée (consommateur futur de
-- creer_inscription_nouvel_eleve, même discipline de recompte d'effectif EN
-- DIRECT dans sa propre transaction, jamais un champ précalculé) ; alerte de
-- bascule d'année scolaire (§17.7, mécanisme séparé, pas de colonnes de
-- notification ajoutées ici).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Type fermé, contrôlé par GSG (pas par chaque établissement, contrairement
-- à catalogue_permissions qui est ouvert/dynamique par poste) — un enum
-- classique, comme type_frais_scolaire/moyen_paiement/type_fournisseur_
-- paiement déjà dans ce schéma.
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.type_entitlement_etablissement as enum ('licence_pro', 'frais_ia_admin');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- Licence Pro établissement — barème par tranche, cumulatif, par année
-- scolaire. tranche_actuelle = 0 est la valeur "gratuit" par défaut : une
-- ligne absente équivaut à une ligne à 0 (même principe qu'ecoshop_flutter,
-- "un document portant uniquement un marqueur est traité identiquement à un
-- document absent").
-- ---------------------------------------------------------------------------
create table if not exists public.etablissements_licence_pro (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  tranche_actuelle int not null default 0 check (tranche_actuelle >= 0),
  montant_total_paye_periode numeric(12, 2) not null default 0 check (montant_total_paye_periode >= 0),
  effectif_au_dernier_paiement int check (effectif_au_dernier_paiement >= 0),
  date_dernier_paiement timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint licence_pro_etablissement_annee_unique unique (etablissement_id, annee_scolaire_id)
);

drop trigger if exists licence_pro_set_updated_at on public.etablissements_licence_pro;
create trigger licence_pro_set_updated_at
  before update on public.etablissements_licence_pro
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Frais IA admin annuel — montant fixe, booléen, par année scolaire.
-- Table INDÉPENDANTE de la précédente (règle absolue 8/9 de VERSION_PRO.md :
-- payer l'un ne débloque jamais l'autre, aucune logique partagée).
-- ---------------------------------------------------------------------------
create table if not exists public.etablissements_frais_ia_admin (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  paye boolean not null default false,
  montant_paye numeric(12, 2) check (montant_paye >= 0),
  date_paiement timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint frais_ia_admin_etablissement_annee_unique unique (etablissement_id, annee_scolaire_id)
);

drop trigger if exists frais_ia_admin_set_updated_at on public.etablissements_frais_ia_admin;
create trigger frais_ia_admin_set_updated_at
  before update on public.etablissements_frais_ia_admin
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — écriture TOUJOURS refusée au client, RPC dédiée uniquement (même
-- règle qu'ecoshop_flutter pour statut_annuel/distributions_fin_annee).
-- Lecture : personnel de l'établissement concerné + admin GSG.
-- ---------------------------------------------------------------------------
alter table public.etablissements_licence_pro enable row level security;
alter table public.etablissements_frais_ia_admin enable row level security;

drop policy if exists "licence_pro_select" on public.etablissements_licence_pro;
create policy "licence_pro_select" on public.etablissements_licence_pro
  for select using (
    coalesce(public.est_personnel(etablissement_id), false) or coalesce(public.est_admin_gsg(), false)
  );

drop policy if exists "licence_pro_no_direct_write" on public.etablissements_licence_pro;
create policy "licence_pro_no_direct_write" on public.etablissements_licence_pro
  for all using (false) with check (false);

drop policy if exists "frais_ia_admin_select" on public.etablissements_frais_ia_admin;
create policy "frais_ia_admin_select" on public.etablissements_frais_ia_admin
  for select using (
    coalesce(public.est_personnel(etablissement_id), false) or coalesce(public.est_admin_gsg(), false)
  );

drop policy if exists "frais_ia_admin_no_direct_write" on public.etablissements_frais_ia_admin;
create policy "frais_ia_admin_no_direct_write" on public.etablissements_frais_ia_admin
  for all using (false) with check (false);

-- ---------------------------------------------------------------------------
-- Configuration (§30.4 — rien codé en dur). Valeurs PLACEHOLDER
-- explicitement signalées comme temporaires dans leur description — à
-- remplacer par le porteur de projet avant toute activation réelle.
-- seuil_effectif_gratuit existe déjà (seed.sql) mais n'avait jusqu'ici aucun
-- consommateur ; calculer_tranche_pro() est son premier lecteur réel.
-- ---------------------------------------------------------------------------
insert into public.parametres_globaux (cle, valeur, description) values
  (
    'bareme_licence_pro',
    '{
      "tranches_explicites": [
        {"tranche": 1, "borne_basse": 101, "borne_haute": 400, "tarif_par_eleve": 1, "bloc_montant": 300}
      ],
      "regime_plancher": {"tranche_depart": 2, "borne_basse_depart": 401, "largeur_tranche": 300, "tarif_par_eleve": 1, "bloc_montant": 300}
    }'::jsonb,
    'PLACEHOLDER — montants fictifs (1 GNF/élève). Barème par tranche du palier Pro établissement, cumulatif/progressif. À remplacer par le porteur de projet avant toute activation réelle.'
  )
on conflict (cle) do nothing;

insert into public.parametres_globaux (cle, valeur, description) values
  (
    'tarif_frais_ia_admin_annuel',
    '{"valeur": 1}'::jsonb,
    'PLACEHOLDER — montant fictif (1 GNF). Frais IA admin annuel, fixe, indépendant de l''effectif. À remplacer par le porteur de projet avant toute activation réelle.'
  )
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- Fonctions pures de calcul (miroir de version_pro_helpers.js) — lecture
-- seule de parametres_globaux, déjà en lecture publique (RLS "using (true)"
-- posée en core_schema) : pas besoin de security definer, principe du
-- moindre privilège.
-- ---------------------------------------------------------------------------
create or replace function public.calculer_tranche_pro(p_effectif int)
returns int
language plpgsql
stable
set search_path = public
as $$
declare
  v_seuil int;
  v_bareme jsonb;
  v_tranches jsonb;
  v_plancher jsonb;
  v_tranche jsonb;
  v_depart int;
  v_borne_basse_depart int;
  v_largeur int;
begin
  select (valeur->>'valeur')::int into v_seuil
  from public.parametres_globaux where cle = 'seuil_effectif_gratuit';

  if p_effectif is null or p_effectif <= coalesce(v_seuil, 0) then
    return 0;
  end if;

  select valeur into v_bareme from public.parametres_globaux where cle = 'bareme_licence_pro';
  if v_bareme is null then
    return 0;
  end if;

  v_tranches := coalesce(v_bareme->'tranches_explicites', '[]'::jsonb);

  for v_tranche in select * from jsonb_array_elements(v_tranches)
  loop
    if p_effectif between (v_tranche->>'borne_basse')::int and (v_tranche->>'borne_haute')::int then
      return (v_tranche->>'tranche')::int;
    end if;
  end loop;

  v_plancher := v_bareme->'regime_plancher';
  if v_plancher is null then
    return coalesce(jsonb_array_length(v_tranches), 0);
  end if;

  v_depart := (v_plancher->>'tranche_depart')::int;
  v_borne_basse_depart := (v_plancher->>'borne_basse_depart')::int;
  v_largeur := (v_plancher->>'largeur_tranche')::int;

  if p_effectif < v_borne_basse_depart then
    return greatest(v_depart - 1, 0);
  end if;

  return v_depart + floor((p_effectif - v_borne_basse_depart)::numeric / v_largeur)::int;
end;
$$;

create or replace function public.calculer_montant_cumule_pro(p_tranche int)
returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  v_bareme jsonb;
  v_tranches jsonb;
  v_plancher jsonb;
  v_total numeric := 0;
  v_tranche_rec jsonb;
  v_depart int;
  v_bloc numeric;
begin
  if p_tranche is null or p_tranche <= 0 then
    return 0;
  end if;

  select valeur into v_bareme from public.parametres_globaux where cle = 'bareme_licence_pro';
  if v_bareme is null then
    return 0;
  end if;

  v_tranches := coalesce(v_bareme->'tranches_explicites', '[]'::jsonb);

  for v_tranche_rec in select * from jsonb_array_elements(v_tranches)
  loop
    if (v_tranche_rec->>'tranche')::int <= p_tranche then
      v_total := v_total + (v_tranche_rec->>'bloc_montant')::numeric;
    end if;
  end loop;

  v_plancher := v_bareme->'regime_plancher';
  if v_plancher is not null then
    v_depart := (v_plancher->>'tranche_depart')::int;
    v_bloc := (v_plancher->>'bloc_montant')::numeric;
    if p_tranche >= v_depart then
      v_total := v_total + (p_tranche - v_depart + 1) * v_bloc;
    end if;
  end if;

  return v_total;
end;
$$;

grant execute on function public.calculer_tranche_pro(int) to authenticated;
grant execute on function public.calculer_montant_cumule_pro(int) to authenticated;

-- ---------------------------------------------------------------------------
-- Contrat de vérification unifié — le seul point d'appel pour tout futur
-- consommateur (chapitre 18, policies RLS, Edge Functions). Toujours une
-- lecture directe des tables, jamais un cache. Correction de sécurité 2 :
-- vérifie elle-même est_personnel/est_admin_gsg avant de renvoyer son
-- booléen — sans quoi, étant security definer, elle contournerait la RLS
-- des tables et laisserait n'importe quel compte authentifié sonder le
-- statut de paiement de n'importe quel établissement.
-- ---------------------------------------------------------------------------
create or replace function public.entitlement_actif(
  p_etablissement uuid,
  p_type public.type_entitlement_etablissement,
  p_annee_scolaire uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_annee uuid;
begin
  if not (coalesce(public.est_personnel(p_etablissement), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  v_annee := coalesce(
    p_annee_scolaire,
    (select id from public.annees_scolaires where etablissement_id = p_etablissement and courante)
  );

  if v_annee is null then
    return false;
  end if;

  case p_type
    when 'licence_pro' then
      return coalesce((
        select tranche_actuelle >= 1 from public.etablissements_licence_pro
        where etablissement_id = p_etablissement and annee_scolaire_id = v_annee
      ), false);
    when 'frais_ia_admin' then
      return coalesce((
        select paye from public.etablissements_frais_ia_admin
        where etablissement_id = p_etablissement and annee_scolaire_id = v_annee
      ), false);
    else
      return false;
  end case;
end;
$$;

grant execute on function public.entitlement_actif(uuid, public.type_entitlement_etablissement, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC d'écriture — renouvellement manuel pour cette passe, réservées
-- est_admin_gsg() (pas encore de circuit CinetPay, étape b distincte).
-- Correction de sécurité 1 : coalesce(est_admin_gsg(), false) — sans quoi
-- un compte fraîchement authentifié sans role_racine choisi contournerait
-- la garde (anti-patron NULL déjà corrigé ailleurs, cf. audit RPC).
-- Cohérence croisée étab/année vérifiée explicitement : ces tables n'ayant
-- aucun autre chemin d'écriture (RLS "using (false)" ci-dessus), la garde
-- vit ici plutôt que dans un trigger dupliqué.
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_paiement_licence_pro(
  p_etablissement uuid,
  p_annee_scolaire uuid,
  p_effectif_constate int,
  p_montant numeric
)
returns public.etablissements_licence_pro
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.etablissements_licence_pro;
  v_tranche_cible int;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ADMIN_GSG_REQUIS' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.annees_scolaires
    where id = p_annee_scolaire and etablissement_id = p_etablissement
  ) then
    raise exception 'ANNEE_SCOLAIRE_INCOHERENTE' using errcode = '23514';
  end if;

  if p_effectif_constate is null or p_effectif_constate < 0 then
    raise exception 'EFFECTIF_INVALIDE' using errcode = '22023';
  end if;

  if p_montant is null or p_montant < 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;

  v_tranche_cible := public.calculer_tranche_pro(p_effectif_constate);

  insert into public.etablissements_licence_pro (
    etablissement_id, annee_scolaire_id, tranche_actuelle,
    montant_total_paye_periode, effectif_au_dernier_paiement, date_dernier_paiement
  )
  values (
    p_etablissement, p_annee_scolaire, v_tranche_cible,
    p_montant, p_effectif_constate, now()
  )
  on conflict (etablissement_id, annee_scolaire_id) do update
    set tranche_actuelle = greatest(public.etablissements_licence_pro.tranche_actuelle, v_tranche_cible),
        montant_total_paye_periode = public.etablissements_licence_pro.montant_total_paye_periode + excluded.montant_total_paye_periode,
        effectif_au_dernier_paiement = excluded.effectif_au_dernier_paiement,
        date_dernier_paiement = excluded.date_dernier_paiement
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function public.enregistrer_paiement_frais_ia_admin(
  p_etablissement uuid,
  p_annee_scolaire uuid,
  p_montant numeric
)
returns public.etablissements_frais_ia_admin
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.etablissements_frais_ia_admin;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ADMIN_GSG_REQUIS' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.annees_scolaires
    where id = p_annee_scolaire and etablissement_id = p_etablissement
  ) then
    raise exception 'ANNEE_SCOLAIRE_INCOHERENTE' using errcode = '23514';
  end if;

  if p_montant is null or p_montant < 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;

  insert into public.etablissements_frais_ia_admin (
    etablissement_id, annee_scolaire_id, paye, montant_paye, date_paiement
  )
  values (p_etablissement, p_annee_scolaire, true, p_montant, now())
  on conflict (etablissement_id, annee_scolaire_id) do update
    set paye = true,
        montant_paye = excluded.montant_paye,
        date_paiement = excluded.date_paiement
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.enregistrer_paiement_licence_pro(uuid, uuid, int, numeric) to authenticated;
grant execute on function public.enregistrer_paiement_frais_ia_admin(uuid, uuid, numeric) to authenticated;

-- ============================================================================
-- Fin — Chantier Facturation/Quota IA, étape (a).
-- ============================================================================
