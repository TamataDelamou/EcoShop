-- ============================================================================
-- EcoShop — REG-03, lot C6 : changement de plan de comptes avec historique
-- (proposition validée le 2026-10-17 : docs/propositions/REG-03_COMPTABILITE.md)
--
-- Jusqu'ici, changer de plan (simplifié ↔ SYSCOHADA ↔ SYCEBNL) était refusé
-- dès la première écriture (ECRITURES_EXISTANTES). Désormais :
--
--   1. `proposer_changement_plan` prépare un changement qui prend effet au
--      PREMIER JOUR d'un exercice (jamais en cours d'exercice) et propose,
--      pour chaque compte utilisé, un compte du nouveau plan : même numéro
--      et même intitulé, table de correspondance connue (sous-comptes
--      scolaires, paie…), compte de rattachement le plus précis, puis
--      nature (caisse, banque) ; tout ce qui n'est pas identique est
--      signalé « à vérifier ».
--   2. `definir_correspondance` permet de corriger chaque ligne (compte du
--      nouveau plan, ou sous-compte à créer sous un compte réglementaire).
--   3. `appliquer_changement_plan` :
--        • archive les états financiers, tableaux des flux et notes des
--          exercices antérieurs TELS QU'ILS ONT ÉTÉ PRÉSENTÉS ;
--        • retire les anciens comptes (renumérotés « 701* », marqués
--          « ancien plan ») sans toucher à une seule pièce ;
--        • charge le nouveau plan, crée les sous-comptes demandés,
--          réoriente les règles d'écritures automatiques ;
--        • écrit une note sur le changement de méthode (note 1).
--
-- L'historique n'est jamais réécrit : les pièces gardent leurs comptes
-- d'origine ; les calculs (balance, grand livre, états, tableau des flux,
-- notes) lisent chaque ancien compte À TRAVERS la table de correspondance.
-- Les exercices antérieurs se présentent ainsi dans le nouveau plan : la
-- colonne N-1 est comparable (retraitement), et la version publiée
-- d'origine reste disponible dans les archives.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table if not exists public.changements_plan (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  ancien_referentiel text not null,
  nouveau_referentiel text not null
    check (nouveau_referentiel in ('simplifie', 'syscohada_smt', 'syscohada_normal', 'sycebnl')),
  exercice_id uuid not null references public.exercices_comptables (id),
  date_effet date not null,
  statut text not null default 'brouillon' check (statut in ('brouillon', 'applique', 'abandonne')),
  forme_juridique text,
  propose_par uuid references public.profiles (id),
  propose_le timestamptz not null default now(),
  applique_par uuid references public.profiles (id),
  applique_le timestamptz
);
create unique index if not exists changements_plan_un_brouillon
  on public.changements_plan (etablissement_id) where statut = 'brouillon';

create table if not exists public.correspondances_plan (
  changement_id uuid not null references public.changements_plan (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  ancien_compte_id uuid not null references public.plans_comptables (id),
  ancien_code text not null,
  ancien_intitule text not null,
  solde numeric(18, 2) not null default 0,
  code_cible text,
  -- identique : même numéro, même intitulé ; table : correspondance connue ;
  -- meme_numero : même numéro, intitulé différent ; rattachement : compte
  -- parent le plus précis ; nature : selon caisse/banque ; manuel : choisi.
  origine text check (origine is null or origine in ('identique', 'table', 'meme_numero', 'rattachement', 'nature', 'manuel')),
  a_verifier boolean not null default true,
  nouveau_compte_id uuid references public.plans_comptables (id),
  applique boolean not null default false,
  primary key (changement_id, ancien_compte_id)
);
-- Un compte n'a qu'une seule correspondance en vigueur.
create unique index if not exists correspondances_plan_en_vigueur
  on public.correspondances_plan (ancien_compte_id) where applique;

create table if not exists public.etats_financiers_archives (
  exercice_id uuid primary key references public.exercices_comptables (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  changement_id uuid references public.changements_plan (id),
  referentiel text not null,
  etat jsonb,
  flux jsonb,
  notes jsonb,
  archive_le timestamptz not null default now()
);

-- Correspondances connues entre plans de référence (sous-comptes EcoShop et
-- comptes dont le numéro diffère d'un plan à l'autre).
create table if not exists public.correspondances_reference (
  plan_source text not null,
  plan_cible text not null,
  code_source text not null,
  code_cible text not null,
  primary key (plan_source, plan_cible, code_source)
);
insert into public.correspondances_reference (plan_source, plan_cible, code_source, code_cible) values
  ('syscohada', 'sycebnl', '70611', '70521'), ('syscohada', 'sycebnl', '70612', '70522'),
  ('syscohada', 'sycebnl', '70613', '70523'), ('syscohada', 'sycebnl', '70614', '70524'),
  ('syscohada', 'sycebnl', '70618', '70528'), ('syscohada', 'sycebnl', '41111', '4121'),
  ('syscohada', 'sycebnl', '4191', '419'), ('syscohada', 'sycebnl', '661', '66'),
  ('syscohada', 'sycebnl', '447', '44'), ('syscohada', 'sycebnl', '758', '7048'),
  ('sycebnl', 'syscohada', '70521', '70611'), ('sycebnl', 'syscohada', '70522', '70612'),
  ('sycebnl', 'syscohada', '70523', '70613'), ('sycebnl', 'syscohada', '70524', '70614'),
  ('sycebnl', 'syscohada', '70528', '70618'), ('sycebnl', 'syscohada', '4121', '41111'),
  ('sycebnl', 'syscohada', '66', '661'), ('sycebnl', 'syscohada', '44', '447'),
  ('sycebnl', 'syscohada', '7041', '758'), ('sycebnl', 'syscohada', '7042', '758'),
  ('sycebnl', 'syscohada', '7043', '758'), ('sycebnl', 'syscohada', '7044', '758'),
  ('sycebnl', 'syscohada', '7046', '758'), ('sycebnl', 'syscohada', '7047', '758'),
  ('sycebnl', 'syscohada', '7048', '758')
on conflict (plan_source, plan_cible, code_source) do update set code_cible = excluded.code_cible;

alter table public.changements_plan enable row level security;
alter table public.correspondances_plan enable row level security;
alter table public.etats_financiers_archives enable row level security;
alter table public.correspondances_reference enable row level security;
drop policy if exists changements_plan_lecture on public.changements_plan;
create policy changements_plan_lecture on public.changements_plan for select using (public.est_comptable(etablissement_id));
drop policy if exists correspondances_plan_lecture on public.correspondances_plan;
create policy correspondances_plan_lecture on public.correspondances_plan for select using (public.est_comptable(etablissement_id));
drop policy if exists etats_archives_lecture on public.etats_financiers_archives;
create policy etats_archives_lecture on public.etats_financiers_archives for select using (public.est_comptable(etablissement_id));
drop policy if exists correspondances_reference_lecture on public.correspondances_reference;
create policy correspondances_reference_lecture on public.correspondances_reference for select using (auth.uid() is not null);
revoke insert, update, delete on public.changements_plan, public.correspondances_plan,
  public.etats_financiers_archives, public.correspondances_reference from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Lecture de l'historique à travers les correspondances
-- ---------------------------------------------------------------------------
create or replace function public.compte_effectif(p_compte_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select nouveau_compte_id from public.correspondances_plan
                    where ancien_compte_id = p_compte_id and applique), p_compte_id);
$$;

create or replace function public.mouvements_comptables(p_etablissement uuid, p_debut date, p_fin date)
returns table (
  date_mouvement date,
  compte_id uuid,
  debit numeric,
  credit numeric,
  libelle text,
  reference text,
  piece_justificative text,
  journal_id uuid,
  ordre timestamptz,
  ordre_ligne integer
)
language sql
stable
security definer
set search_path = public
as $$
  -- Les comptes d'un plan remplacé sont lus à travers la correspondance en
  -- vigueur : l'historique se présente dans le plan actuel, sans qu'aucune
  -- pièce soit modifiée.
  select e.date_ecriture, coalesce(cd.nouveau_compte_id, e.compte_debit_id), e.montant, 0::numeric, e.libelle, null::text,
         e.piece_justificative, e.journal_id, e.created_at, 0
    from public.ecritures_comptables e
    left join public.correspondances_plan cd on cd.ancien_compte_id = e.compte_debit_id and cd.applique
   where e.etablissement_id = p_etablissement and e.deleted_at is null
     and e.date_ecriture between coalesce(p_debut, '-infinity'::date) and coalesce(p_fin, 'infinity'::date)
  union all
  select e.date_ecriture, coalesce(cc.nouveau_compte_id, e.compte_credit_id), 0::numeric, e.montant, e.libelle, null::text,
         e.piece_justificative, e.journal_id, e.created_at, 1
    from public.ecritures_comptables e
    left join public.correspondances_plan cc on cc.ancien_compte_id = e.compte_credit_id and cc.applique
   where e.etablissement_id = p_etablissement and e.deleted_at is null
     and e.date_ecriture between coalesce(p_debut, '-infinity'::date) and coalesce(p_fin, 'infinity'::date)
  union all
  select p.date_piece, coalesce(cp.nouveau_compte_id, l.compte_id), l.debit, l.credit, coalesce(l.libelle, p.libelle), p.reference,
         coalesce(p.piece_justificative, p.reference), p.journal_id, p.validee_le, l.ordre::integer
    from public.pieces_comptables p
    join public.lignes_pieces_comptables l on l.piece_id = p.id
    left join public.correspondances_plan cp on cp.ancien_compte_id = l.compte_id and cp.applique
   where p.etablissement_id = p_etablissement and p.statut = 'validee'
     and p.date_piece between coalesce(p_debut, '-infinity'::date) and coalesce(p_fin, 'infinity'::date);
$$;

-- Tableau des flux : même lecture à travers les correspondances.
create or replace function public.calculer_flux_tresorerie(p_etablissement uuid, p_plan text, p_debut date, p_fin date)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r public.rubriques_flux_tresorerie;
  v_valeurs jsonb := '{}'::jsonb;
  v_lignes jsonb := '[]'::jsonb;
  v_montant numeric;
  v_ref text;
  v_ouverture numeric;
  v_cloture_reelle numeric;
  v_resultat numeric;
begin
  -- Mouvements de l'exercice, groupés par pièce (ou écriture rapide), hors
  -- à-nouveaux ; « tresorerie » : classe 5 (OHADA) ou banque/caisse.
  create temp table if not exists _ft_lignes (
    cle uuid, compte_id uuid, code text, type text, tresorerie boolean, a_nouveaux boolean, debit numeric, credit numeric
  ) on commit drop;
  truncate _ft_lignes;
  insert into _ft_lignes
  select p.id, c.id, c.code, c.type,
         case when p_plan = 'simplifie' then c.type in ('banque', 'caisse') else left(c.code, 1) = '5' end,
         p.origine = 'a_nouveaux', l.debit, l.credit
    from public.pieces_comptables p
    join public.lignes_pieces_comptables l on l.piece_id = p.id
    join public.plans_comptables c on c.id = public.compte_effectif(l.compte_id)
   where p.etablissement_id = p_etablissement and p.statut = 'validee'
     and p.date_piece between p_debut and p_fin;
  insert into _ft_lignes
  select e.id, c.id, c.code, c.type,
         case when p_plan = 'simplifie' then c.type in ('banque', 'caisse') else left(c.code, 1) = '5' end,
         false, case when s.cote = 'd' then e.montant else 0 end, case when s.cote = 'c' then e.montant else 0 end
    from public.ecritures_comptables e
    cross join lateral (values ('d', e.compte_debit_id), ('c', e.compte_credit_id)) as s(cote, compte_id)
    join public.plans_comptables c on c.id = public.compte_effectif(s.compte_id)
   where e.etablissement_id = p_etablissement and e.deleted_at is null
     and e.date_ecriture between p_debut and p_fin;

  -- Contribution de chaque contrepartie à la trésorerie : pour une pièce
  -- équilibrée, (crédit − débit) de la contrepartie = argent entré.
  create temp table if not exists _ft_flux (code text, type text, montant numeric) on commit drop;
  truncate _ft_flux;
  insert into _ft_flux
  select f.code, f.type, sum(f.credit - f.debit)
    from _ft_lignes f
   where not f.a_nouveaux and not f.tresorerie
     and f.cle in (select cle from _ft_lignes where tresorerie and not a_nouveaux)
   group by f.cle, f.code, f.type
  having sum(f.credit - f.debit) <> 0;

  select coalesce(sum(debit - credit), 0) into v_ouverture from _ft_lignes where tresorerie and a_nouveaux;
  select coalesce(sum(debit - credit), 0) into v_cloture_reelle from _ft_lignes where tresorerie;
  select coalesce(sum(credit - debit), 0) into v_resultat from _ft_lignes where type in ('charge', 'produit');

  -- Classement : rubrique « flux » au préfixe le plus précis, sinon « reste ».
  create temp table if not exists _ft_classes (reference text, montant numeric) on commit drop;
  truncate _ft_classes;
  insert into _ft_classes
  select coalesce(
           (select rf.reference from public.rubriques_flux_tresorerie rf
             where rf.plan = p_plan and rf.mode = 'flux'
               and (rf.sens = 'net' or (rf.sens = 'entree' and fl.montant > 0) or (rf.sens = 'sortie' and fl.montant < 0))
               and public.flux_correspondance(fl.code, fl.type, rf.prefixes, rf.exclusions) > 0
             order by public.flux_correspondance(fl.code, fl.type, rf.prefixes, rf.exclusions) desc, rf.ordre
             limit 1),
           (select rf.reference from public.rubriques_flux_tresorerie rf where rf.plan = p_plan and rf.mode = 'reste' limit 1)),
         fl.montant
    from _ft_flux fl;

  for r in select * from public.rubriques_flux_tresorerie where plan = p_plan order by ordre loop
    if r.mode = 'ouverture' then
      v_montant := v_ouverture;
    elsif r.mode in ('flux', 'reste') then
      select coalesce(sum(montant), 0) into v_montant from _ft_classes where reference = r.reference;
    elsif r.mode = 'indirect' then
      v_montant := case r.calcul
        -- CAFG = résultat + dotations et VNC des cessions − reprises et
        -- produits des cessions (méthode additive).
        when 'CAFG' then v_resultat
          + coalesce((select sum(debit - credit) from _ft_lignes
                       where not a_nouveaux and (code like '68%' or code like '69%' or code like '81%' or code like '85%')), 0)
          - coalesce((select sum(credit - debit) from _ft_lignes
                       where not a_nouveaux and (code like '79%' or code like '82%' or code like '86%')), 0)
        when 'BF_HAO' then -coalesce((select sum(debit - credit) from _ft_lignes
                       where not a_nouveaux and (code like '485%' or code like '488%')), 0)
        when 'BF_STOCKS' then -coalesce((select sum(debit - credit) from _ft_lignes
                       where not a_nouveaux and code like '3%' and code not like '39%'), 0)
        when 'BF_CREANCES' then -coalesce((
            select sum(greatest(s.fin, 0) - greatest(s.debut, 0)) from (
              select compte_id, sum(debit - credit) fin, sum(debit - credit) filter (where a_nouveaux) debut
                from _ft_lignes
               where code like '4%' and code !~ '^(465|481|482|484|485|488)'
               group by compte_id) s), 0)
        when 'BF_DETTES' then coalesce((
            select sum(greatest(-s.fin, 0) - greatest(-coalesce(s.debut, 0), 0)) from (
              select compte_id, sum(debit - credit) fin, sum(debit - credit) filter (where a_nouveaux) debut
                from _ft_lignes
               where code like '4%' and code !~ '^(465|481|482|484|485|488)'
               group by compte_id) s), 0)
      end;
    else
      v_montant := 0;
      foreach v_ref in array r.formule loop
        v_montant := v_montant + coalesce((v_valeurs->>v_ref)::numeric, 0);
      end loop;
    end if;
    v_montant := round(coalesce(v_montant, 0), 2);
    v_valeurs := v_valeurs || jsonb_build_object(r.reference, v_montant);
    if r.affiche then
      v_lignes := v_lignes || jsonb_build_array(jsonb_build_object(
        'reference', r.reference, 'libelle', r.libelle, 'total', r.total, 'montant', v_montant));
    end if;
  end loop;

  return jsonb_build_object(
    'valeurs', v_valeurs,
    'lignes', v_lignes,
    'provisoire', exists (select 1 from public.rubriques_flux_tresorerie where plan = p_plan and provisoire),
    'tresorerie_bilan', round(v_cloture_reelle, 2),
    'ecart_cloture', round(v_cloture_reelle - coalesce((v_valeurs->>(
        select reference from public.rubriques_flux_tresorerie where plan = p_plan and mode = 'cloture'))::numeric, 0), 2),
    -- SYSCOHADA : flux opérationnels pièce par pièce, pour rapprocher la
    -- méthode indirecte (ZB) de la réalité des encaissements.
    'operationnel_direct', case when p_plan = 'syscohada' then v_valeurs->'OPD' end);
end;
$$;


-- ---------------------------------------------------------------------------
-- 3. Proposition
-- ---------------------------------------------------------------------------
-- Compte imputable du plan de référence : sans sous-compte de référence.
create or replace function public.reference_imputable(p_plan text, p_code text)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (select 1 from public.plans_comptables_reference where plan = p_plan and code = p_code)
     and not exists (select 1 from public.plans_comptables_reference r
                      where r.plan = p_plan and r.code <> p_code and public.code_parent_reference(p_plan, r.code) = p_code);
$$;

create or replace function public.suggerer_compte_cible(
  p_plan_source text, p_plan_cible text, p_code text, p_intitule text, p_type text)
returns table (code_cible text, origine text)
language plpgsql
stable
set search_path = public
as $$
declare
  v text;
begin
  -- 1. Même numéro, même intitulé, imputable.
  if public.reference_imputable(p_plan_cible, p_code)
     and exists (select 1 from public.plans_comptables_reference
                  where plan = p_plan_cible and code = p_code and lower(intitule) = lower(p_intitule)) then
    return query select p_code, 'identique'::text;
    return;
  end if;
  -- 2. Table de correspondance connue.
  select r.code_cible into v from public.correspondances_reference r
   where r.plan_source = coalesce(p_plan_source, 'simplifie') and r.plan_cible = p_plan_cible and r.code_source = p_code;
  if v is not null and public.reference_imputable(p_plan_cible, v) then
    return query select v, 'table'::text;
    return;
  end if;
  -- 3. Même numéro (intitulé différent) : à vérifier.
  if p_plan_source is not null and public.reference_imputable(p_plan_cible, p_code) then
    return query select p_code, 'meme_numero'::text;
    return;
  end if;
  -- 4. Compte de rattachement imputable le plus précis (préfixe).
  if p_plan_source is not null then
    select r.code into v from public.plans_comptables_reference r
     where r.plan = p_plan_cible and char_length(r.code) >= 2
       and left(p_code, char_length(r.code)) = r.code and public.reference_imputable(p_plan_cible, r.code)
     order by char_length(r.code) desc limit 1;
    if v is not null then
      return query select v, 'rattachement'::text;
      return;
    end if;
  end if;
  -- 5. Nature du compte (plans libres).
  v := case p_type when 'caisse' then '571' when 'banque' then '521'
                   when 'produit' then case p_plan_cible when 'sycebnl' then '70528' else '70618' end end;
  if v is not null and public.reference_imputable(p_plan_cible, v) then
    return query select v, 'nature'::text;
    return;
  end if;
  return query select null::text, null::text;
end;
$$;

create or replace function public.proposer_changement_plan(
  p_etablissement uuid, p_referentiel text, p_forme_juridique text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_ancien text := public.referentiel_comptable_de(p_etablissement);
  v_plan_source text := public.plan_du_referentiel(public.referentiel_comptable_de(p_etablissement));
  v_plan_cible text := public.plan_du_referentiel(p_referentiel);
  x public.exercices_comptables;
  v_prec public.exercices_comptables;
  v_id uuid;
  r record;
  s record;
begin
  if not (coalesce(public.est_direction(p_etablissement), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if v_plan_cible is null then
    -- Vers le simplifié : le plan reste, il redevient libre (choix direct).
    raise exception 'CHOIX_DIRECT_POSSIBLE' using errcode = '22023';
  end if;
  if v_plan_cible is not distinct from v_plan_source then
    raise exception 'MEME_PLAN' using errcode = '22023';
  end if;

  -- Date d'effet : début du premier exercice sans autre mouvement que des
  -- à-nouveaux (après tous les mouvements existants).
  select ex.* into x from public.exercices_comptables ex
   where ex.etablissement_id = p_etablissement and ex.statut = 'ouvert'
     and not exists (select 1 from public.pieces_comptables p
                      where p.etablissement_id = p_etablissement and p.date_piece >= ex.date_debut
                        and p.origine is distinct from 'a_nouveaux')
     and not exists (select 1 from public.ecritures_comptables e
                      where e.etablissement_id = p_etablissement and e.deleted_at is null
                        and e.date_ecriture >= ex.date_debut)
   order by ex.date_debut limit 1;
  if x.id is null then
    raise exception 'EXERCICE_VIERGE_REQUIS' using errcode = '55000',
      hint = 'Ouvrez (ou clôturez jusqu''à) un exercice sans écriture : le changement prend effet à son premier jour.';
  end if;
  select * into v_prec from public.exercices_comptables
   where etablissement_id = p_etablissement and date_fin = x.date_debut - 1;

  delete from public.changements_plan where etablissement_id = p_etablissement and statut = 'brouillon';
  insert into public.changements_plan
    (etablissement_id, ancien_referentiel, nouveau_referentiel, exercice_id, date_effet, forme_juridique, propose_par)
  values (p_etablissement, v_ancien, p_referentiel, x.id, x.date_debut, p_forme_juridique, auth.uid())
  returning id into v_id;

  -- Comptes concernés : ceux qui ont servi (mouvements, règles) ; solde à
  -- reporter = solde de bilan à la fin de l'exercice précédent.
  for r in
    select c.id, c.code, c.intitule, c.type,
           coalesce((select sum(m.debit - m.credit)
                       from public.mouvements_comptables(p_etablissement,
                              coalesce(v_prec.date_debut, '-infinity'::date), x.date_debut - 1) m
                      where m.compte_id = c.id and c.type not in ('charge', 'produit')), 0) solde
      from public.plans_comptables c
     where c.etablissement_id = p_etablissement and c.deleted_at is null
       and not exists (select 1 from public.correspondances_plan cp where cp.ancien_compte_id = c.id and cp.applique)
       and (exists (select 1 from public.lignes_pieces_comptables l where l.compte_id = c.id)
            or exists (select 1 from public.ecritures_comptables e
                        where e.deleted_at is null and (e.compte_debit_id = c.id or e.compte_credit_id = c.id))
            or exists (select 1 from public.regles_comptabilisation g where g.compte_id = c.id))
     order by c.code
  loop
    select * into s from public.suggerer_compte_cible(v_plan_source, v_plan_cible, r.code, r.intitule, r.type);
    insert into public.correspondances_plan
      (changement_id, etablissement_id, ancien_compte_id, ancien_code, ancien_intitule, solde, code_cible, origine, a_verifier)
    values (v_id, p_etablissement, r.id, r.code, r.intitule, round(r.solde, 2), s.code_cible, s.origine,
            s.origine is distinct from 'identique');
  end loop;

  return public.changement_plan_detail(v_id);
end;
$$;

create or replace function public.changement_plan_detail(p_changement_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  ch public.changements_plan;
begin
  select * into ch from public.changements_plan where id = p_changement_id;
  if ch.id is null or not coalesce(public.est_comptable(ch.etablissement_id), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'id', ch.id,
    'statut', ch.statut,
    'ancien_referentiel', ch.ancien_referentiel,
    'nouveau_referentiel', ch.nouveau_referentiel,
    'date_effet', ch.date_effet,
    'exercice', (select libelle from public.exercices_comptables where id = ch.exercice_id),
    'a_completer', (select count(*) from public.correspondances_plan where changement_id = ch.id and code_cible is null),
    'a_verifier', (select count(*) from public.correspondances_plan where changement_id = ch.id and a_verifier),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'ancien_compte_id', cp.ancien_compte_id, 'ancien_code', cp.ancien_code, 'ancien_intitule', cp.ancien_intitule,
               'solde', cp.solde, 'code_cible', cp.code_cible,
               'intitule_cible', coalesce(
                  (select rf.intitule from public.plans_comptables_reference rf
                    where rf.plan = public.plan_du_referentiel(ch.nouveau_referentiel) and rf.code = cp.code_cible),
                  case when cp.code_cible is not null then cp.ancien_intitule end),
               'origine', cp.origine, 'a_verifier', cp.a_verifier)
             order by cp.code_cible is not null, cp.a_verifier desc, cp.ancien_code)
        from public.correspondances_plan cp where cp.changement_id = ch.id), '[]'::jsonb));
end;
$$;

create or replace function public.definir_correspondance(p_changement_id uuid, p_ancien_compte_id uuid, p_code_cible text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  ch public.changements_plan;
  v_plan text;
  v_code text := nullif(trim(p_code_cible), '');
begin
  select * into ch from public.changements_plan where id = p_changement_id for update;
  if ch.id is null or not (coalesce(public.est_direction(ch.etablissement_id), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if ch.statut <> 'brouillon' then
    raise exception 'CHANGEMENT_DEJA_APPLIQUE' using errcode = '55000';
  end if;
  v_plan := public.plan_du_referentiel(ch.nouveau_referentiel);
  -- Cible admise : compte imputable du nouveau plan, ou sous-compte à créer
  -- sous un compte imputable (le détail de l'école est conservé).
  if v_code is not null and not public.reference_imputable(v_plan, v_code)
     and not (v_code ~ '^[0-9]+$'
              and not exists (select 1 from public.plans_comptables_reference where plan = v_plan and code = v_code)
              and public.reference_imputable(v_plan, public.code_parent_reference(v_plan, v_code))) then
    raise exception 'COMPTE_CIBLE_INVALIDE' using errcode = '22023';
  end if;
  update public.correspondances_plan
     set code_cible = v_code, origine = case when v_code is null then null else 'manuel' end, a_verifier = false
   where changement_id = ch.id and ancien_compte_id = p_ancien_compte_id;
  if not found then
    raise exception 'COMPTE_HORS_CHANGEMENT' using errcode = '22023';
  end if;
  return public.changement_plan_detail(ch.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Application
-- ---------------------------------------------------------------------------
create or replace function public.appliquer_changement_plan(p_changement_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  ch public.changements_plan;
  v_plan text;
  v_ancien_plan text;
  x record;
  r record;
  cp record;
  v_charges integer := 0;
  v_retires integer := 0;
  v_archives integer := 0;
  v_parent uuid;
  v_nouveau uuid;
  v_texte text;
begin
  select * into ch from public.changements_plan where id = p_changement_id for update;
  if ch.id is null or not (coalesce(public.est_direction(ch.etablissement_id), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if ch.statut <> 'brouillon' then
    raise exception 'CHANGEMENT_DEJA_APPLIQUE' using errcode = '55000';
  end if;
  perform pg_advisory_xact_lock(hashtext('referentiel_comptable:' || ch.etablissement_id::text));
  if public.referentiel_comptable_de(ch.etablissement_id) is distinct from ch.ancien_referentiel then
    raise exception 'REFERENTIEL_MODIFIE_ENTRE_TEMPS' using errcode = '55000';
  end if;
  -- Rien ne doit avoir été saisi depuis la proposition à partir de la date d'effet.
  if exists (select 1 from public.pieces_comptables p
              where p.etablissement_id = ch.etablissement_id
                and (p.statut = 'brouillard' or (p.date_piece >= ch.date_effet and p.origine is distinct from 'a_nouveaux')))
     or exists (select 1 from public.ecritures_comptables e
                 where e.etablissement_id = ch.etablissement_id and e.deleted_at is null and e.date_ecriture >= ch.date_effet) then
    raise exception 'ECRITURES_APRES_DATE_EFFET' using errcode = '55000';
  end if;
  if exists (select 1 from public.correspondances_plan where changement_id = ch.id and code_cible is null) then
    raise exception 'CORRESPONDANCES_INCOMPLETES' using errcode = '55000';
  end if;

  v_plan := public.plan_du_referentiel(ch.nouveau_referentiel);
  v_ancien_plan := public.plan_du_referentiel(ch.ancien_referentiel);

  -- a) Archives : les exercices antérieurs tels qu'ils ont été présentés.
  for x in select * from public.exercices_comptables
            where etablissement_id = ch.etablissement_id and date_fin < ch.date_effet
              and not exists (select 1 from public.etats_financiers_archives a where a.exercice_id = exercices_comptables.id)
  loop
    insert into public.etats_financiers_archives (exercice_id, etablissement_id, changement_id, referentiel, etat, flux, notes)
    values (x.id, ch.etablissement_id, ch.id, ch.ancien_referentiel,
            public.etat_financier(ch.etablissement_id, x.id),
            public.tableau_flux_tresorerie(ch.etablissement_id, x.id),
            public.notes_annexes(ch.etablissement_id, x.id));
    v_archives := v_archives + 1;
  end loop;

  perform set_config('ecoshop.chargement_plan_reference', 'on', true);

  -- b) Anciens comptes : ceux qui gardent leur numéro (cible = même code du
  --    nouveau plan) restent ; les autres sont retirés et renumérotés.
  for r in select c.* from public.plans_comptables c
            where c.etablissement_id = ch.etablissement_id and c.deleted_at is null
              and not exists (select 1 from public.correspondances_plan k
                               where k.changement_id = ch.id and k.ancien_compte_id = c.id and k.code_cible = c.code)
            order by char_length(c.code) desc
  loop
    update public.plans_comptables
       set code = left(r.code, 60) || '*' || case when exists (select 1 from public.plans_comptables
                                                                 where etablissement_id = r.etablissement_id
                                                                   and code = left(r.code, 60) || '*')
                                                   then substr(replace(r.id::text, '-', ''), 1, 4) else '' end,
           intitule = left(r.intitule, 180) || ' (ancien plan)',
           deleted_at = now(), actif = false, reglementaire = false, extension_ecoshop = false, parent_id = null
     where id = r.id;
    v_retires := v_retires + 1;
  end loop;

  -- c) Nouveau plan de référence.
  for r in select rf.code, rf.intitule, rf.type, rf.extension_ecoshop
             from public.plans_comptables_reference rf where rf.plan = v_plan
            order by char_length(rf.code), rf.code
  loop
    insert into public.plans_comptables
      (etablissement_id, code, intitule, type, parent_id, actif, reglementaire, extension_ecoshop, deleted_at)
    values (ch.etablissement_id, r.code, r.intitule, r.type,
            (select pc.id from public.plans_comptables pc
              where pc.etablissement_id = ch.etablissement_id and pc.deleted_at is null
                and pc.code = public.code_parent_reference(v_plan, r.code)),
            true, true, r.extension_ecoshop, null)
    on conflict (etablissement_id, code) do update
      set intitule = excluded.intitule, type = excluded.type, parent_id = excluded.parent_id,
          actif = true, reglementaire = true, extension_ecoshop = excluded.extension_ecoshop, deleted_at = null;
    v_charges := v_charges + 1;
  end loop;

  -- d) Sous-comptes demandés (détail de l'école conservé) puis liaison.
  for cp in select * from public.correspondances_plan where changement_id = ch.id order by char_length(code_cible) loop
    select id into v_nouveau from public.plans_comptables
     where etablissement_id = ch.etablissement_id and code = cp.code_cible and deleted_at is null;
    if v_nouveau is null then
      select id into v_parent from public.plans_comptables
       where etablissement_id = ch.etablissement_id and deleted_at is null
         and code = public.code_parent_reference(v_plan, cp.code_cible);
      insert into public.plans_comptables (etablissement_id, code, intitule, type, parent_id, actif, reglementaire)
      select ch.etablissement_id, cp.code_cible, cp.ancien_intitule, p.type, p.id, true, false
        from public.plans_comptables p where p.id = v_parent
      returning id into v_nouveau;
      if v_nouveau is null then
        raise exception 'COMPTE_CIBLE_INVALIDE' using errcode = '22023';
      end if;
    end if;
    update public.correspondances_plan
       set nouveau_compte_id = v_nouveau, applique = (v_nouveau <> cp.ancien_compte_id)
     where changement_id = ch.id and ancien_compte_id = cp.ancien_compte_id;
    -- Chaîne de changements : une correspondance plus ancienne qui menait à
    -- ce compte mène désormais à sa nouvelle cible.
    if v_nouveau <> cp.ancien_compte_id then
      update public.correspondances_plan set nouveau_compte_id = v_nouveau
       where applique and nouveau_compte_id = cp.ancien_compte_id and changement_id <> ch.id;
    end if;
  end loop;

  perform set_config('ecoshop.chargement_plan_reference', 'off', true);

  -- e) Règles d'écritures automatiques réorientées (ou rendues au défaut).
  update public.regles_comptabilisation g
     set compte_id = k.nouveau_compte_id, modifie_le = now()
    from public.correspondances_plan k
   where k.changement_id = ch.id and k.ancien_compte_id = g.compte_id and k.applique
     and g.etablissement_id = ch.etablissement_id;
  delete from public.regles_comptabilisation g
   where g.etablissement_id = ch.etablissement_id
     and exists (select 1 from public.plans_comptables c where c.id = g.compte_id and (c.deleted_at is not null or not c.actif));

  -- f) Référentiel, historique, note sur le changement de méthode.
  update public.parametres_comptables
     set referentiel = ch.nouveau_referentiel,
         forme_juridique = coalesce(ch.forme_juridique, forme_juridique),
         choisi_par = auth.uid(), choisi_le = now()
   where etablissement_id = ch.etablissement_id;
  insert into public.historique_referentiels_comptables
    (etablissement_id, ancien_referentiel, nouveau_referentiel, forme_juridique, comptes_charges, par)
  values (ch.etablissement_id, ch.ancien_referentiel, ch.nouveau_referentiel, ch.forme_juridique, v_charges, auth.uid());

  v_texte := 'Changement de référentiel comptable au ' || to_char(ch.date_effet, 'DD/MM/YYYY') || ' : '
    || public.libelle_referentiel(ch.ancien_referentiel) || ' remplacé par ' || public.libelle_referentiel(ch.nouveau_referentiel)
    || '. Les comptes de l''ancien plan ont été reportés selon une table de correspondance ('
    || (select count(*) from public.correspondances_plan where changement_id = ch.id) || ' comptes). '
    || 'Les montants de l''exercice précédent sont présentés selon le nouveau plan pour rester comparables ; '
    || 'les états publiés à l''origine sont conservés.';
  insert into public.notes_annexes_redigees (exercice_id, etablissement_id, cle, texte, modifie_par)
  values (ch.exercice_id, ch.etablissement_id, 'methodes', v_texte, auth.uid())
  on conflict (exercice_id, cle) do update
    set texte = excluded.texte || E'\n' || notes_annexes_redigees.texte, modifie_par = excluded.modifie_par, modifie_le = now();

  update public.changements_plan set statut = 'applique', applique_par = auth.uid(), applique_le = now() where id = ch.id;

  return jsonb_build_object('referentiel', ch.nouveau_referentiel, 'date_effet', ch.date_effet,
                            'comptes_charges', v_charges, 'comptes_retires', v_retires, 'exercices_archives', v_archives);
end;
$$;

create or replace function public.libelle_referentiel(p text)
returns text
language sql
immutable
as $$
  select case p
    when 'syscohada_normal' then 'SYSCOHADA révisé (système normal)'
    when 'syscohada_smt' then 'SYSCOHADA révisé (système minimal de trésorerie)'
    when 'sycebnl' then 'SYCEBNL'
    else 'comptabilité simplifiée' end;
$$;

create or replace function public.abandonner_changement_plan(p_changement_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  ch public.changements_plan;
begin
  select * into ch from public.changements_plan where id = p_changement_id;
  if ch.id is null or not (coalesce(public.est_direction(ch.etablissement_id), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if ch.statut <> 'brouillon' then
    raise exception 'CHANGEMENT_DEJA_APPLIQUE' using errcode = '55000';
  end if;
  update public.changements_plan set statut = 'abandonne' where id = ch.id;
end;
$$;

-- Comptes imputables d'un plan de référence (choix d'une cible).
create or replace function public.comptes_cibles(p_referentiel text)
returns table (code text, intitule text, type text)
language sql
stable
security definer
set search_path = public
as $$
  select r.code, r.intitule, r.type from public.plans_comptables_reference r
   where r.plan = public.plan_du_referentiel(p_referentiel) and public.reference_imputable(r.plan, r.code)
   order by r.code;
$$;

-- États tels que publiés avant un changement de plan.
create or replace function public.etat_financier_archive(p_exercice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  a public.etats_financiers_archives;
begin
  select * into a from public.etats_financiers_archives where exercice_id = p_exercice_id;
  if a.exercice_id is null then
    return null;
  end if;
  if not coalesce(public.est_comptable(a.etablissement_id), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;
  return jsonb_build_object('referentiel', a.referentiel, 'archive_le', a.archive_le,
                            'etat', a.etat, 'flux', a.flux, 'notes', a.notes);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Droits
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.compte_effectif(uuid)',
    'public.reference_imputable(text, text)',
    'public.suggerer_compte_cible(text, text, text, text, text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  foreach f in array array[
    'public.proposer_changement_plan(uuid, text, text)',
    'public.changement_plan_detail(uuid)',
    'public.definir_correspondance(uuid, uuid, text)',
    'public.appliquer_changement_plan(uuid)',
    'public.abandonner_changement_plan(uuid)',
    'public.comptes_cibles(text)',
    'public.etat_financier_archive(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;
