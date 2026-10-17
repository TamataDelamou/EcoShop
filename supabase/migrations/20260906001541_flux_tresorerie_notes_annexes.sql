-- ============================================================================
-- EcoShop — REG-03, lot C5 (3/3) : tableau des flux de trésorerie complet et
-- notes annexes (proposition validée le 2026-10-17 :
-- docs/propositions/REG-03_COMPTABILITE.md)
--
-- Tableau des flux de trésorerie (TFT), au modèle du référentiel :
--   • SYSCOHADA révisé : ZA → ZH, flux opérationnels par la méthode
--     indirecte (CAFG FA, variations du besoin de financement FB à FE),
--     investissement (FF à FJ), capitaux propres (FK à FN), capitaux
--     étrangers (FO à FQ) ;
--   • SYCEBNL : ZA → ZG, méthode directe (cotisations, subventions,
--     générosité, manifestations, autres revenus, fournisseurs, personnel,
--     autres décaissements ; investissement FI à FL ; fonds propres FM à
--     FO ; fonds étrangers FP à FQ) ;
--   • simplifié : encaissements et décaissements de l'activité, autres.
--
-- Chaque mouvement de trésorerie (classe 5 ; banque/caisse en simplifié)
-- est rattaché à la contrepartie de SA pièce : le classement est exact,
-- pièce par pièce, sans estimation. En SYSCOHADA, les flux opérationnels
-- sont aussi calculés par la méthode indirecte, comme l'exige le modèle :
-- l'écart éventuel entre les deux méthodes est publié (contrôle), jamais
-- masqué. Contrôle final : trésorerie de clôture = trésorerie du bilan.
--
-- Rubriques stockées comme données (`rubriques_flux_tresorerie`) : un
-- ajustement de l'expert-comptable ne demande pas de code.
--
-- Notes annexes : notes calculées (méthodes, immobilisations, créances et
-- dettes, trésorerie, fonds propres, produits, charges, personnel,
-- produits constatés d'avance ; en SYCEBNL générosité, fonds affectés,
-- engagements reçus) et notes rédigées par l'école (faits marquants,
-- événements postérieurs, engagements hors bilan…), modifiables tant que
-- l'exercice est ouvert.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Rubriques du TFT
-- ---------------------------------------------------------------------------
create table if not exists public.rubriques_flux_tresorerie (
  plan text not null check (plan in ('syscohada', 'sycebnl', 'simplifie')),
  reference text not null,
  libelle text not null,
  ordre integer not null,
  -- ouverture : trésorerie nette au début ; flux : mouvements classés par
  -- contrepartie ; reste : flux non classés ailleurs ; indirect : calcul
  -- SYSCOHADA (CAFG, variations du BF) ; total : somme de références ;
  -- cloture : total final, contrôlé contre le bilan.
  mode text not null check (mode in ('ouverture', 'flux', 'reste', 'indirect', 'total', 'cloture')),
  sens text not null default 'net' check (sens in ('entree', 'sortie', 'net')),
  -- Préfixes de comptes ; « type:xxx » vise une nature de compte.
  prefixes text[] not null default '{}',
  exclusions text[] not null default '{}',
  formule text[] not null default '{}',
  calcul text check (calcul is null or calcul in ('CAFG', 'BF_HAO', 'BF_STOCKS', 'BF_CREANCES', 'BF_DETTES')),
  affiche boolean not null default true,
  total boolean not null default false,
  provisoire boolean not null default false,
  primary key (plan, reference)
);

alter table public.rubriques_flux_tresorerie enable row level security;
drop policy if exists rubriques_flux_lecture on public.rubriques_flux_tresorerie;
create policy rubriques_flux_lecture on public.rubriques_flux_tresorerie for select using (auth.uid() is not null);
revoke insert, update, delete on public.rubriques_flux_tresorerie from anon, authenticated;

delete from public.rubriques_flux_tresorerie;
insert into public.rubriques_flux_tresorerie
  (plan, reference, libelle, ordre, mode, sens, prefixes, exclusions, formule, calcul, affiche, total, provisoire) values
  -- SYSCOHADA révisé (modèle normal)
  ('syscohada', 'ZA', 'Trésorerie nette au 1er janvier (trésorerie actif N-1 − trésorerie passif N-1)', 10, 'ouverture', 'net', '{}', '{}', '{}', null, true, true, false),
  ('syscohada', 'FA', 'Capacité d''autofinancement globale (CAFG)', 20, 'indirect', 'net', '{}', '{}', '{}', 'CAFG', true, false, false),
  ('syscohada', 'FB', '− Actif circulant HAO', 21, 'indirect', 'net', '{}', '{}', '{}', 'BF_HAO', true, false, false),
  ('syscohada', 'FC', '− Variation des stocks', 22, 'indirect', 'net', '{}', '{}', '{}', 'BF_STOCKS', true, false, false),
  ('syscohada', 'FD', '− Variation des créances', 23, 'indirect', 'net', '{}', '{}', '{}', 'BF_CREANCES', true, false, false),
  ('syscohada', 'FE', '+ Variation du passif circulant', 24, 'indirect', 'net', '{}', '{}', '{}', 'BF_DETTES', true, false, false),
  ('syscohada', 'ZB', 'Flux de trésorerie provenant des activités opérationnelles (somme FA à FE)', 29, 'total', 'net', '{}', '{}', '{FA,FB,FC,FD,FE}', null, true, true, false),
  ('syscohada', 'OPD', 'Flux opérationnels constatés pièce par pièce (contrôle)', 30, 'reste', 'net', '{}', '{}', '{}', null, false, false, false),
  ('syscohada', 'FF', '− Décaissements liés aux acquisitions d''immobilisations incorporelles', 40, 'flux', 'sortie', '{21}', '{}', '{}', null, true, false, false),
  ('syscohada', 'FG', '− Décaissements liés aux acquisitions d''immobilisations corporelles', 41, 'flux', 'sortie', '{22,23,24,481,482}', '{}', '{}', null, true, false, false),
  ('syscohada', 'FH', '− Décaissements liés aux acquisitions d''immobilisations financières', 42, 'flux', 'sortie', '{25,26,27}', '{}', '{}', null, true, false, false),
  ('syscohada', 'FI', '+ Encaissements liés aux cessions d''immobilisations incorporelles et corporelles', 43, 'flux', 'entree', '{21,22,23,24,82,485}', '{}', '{}', null, true, false, false),
  ('syscohada', 'FJ', '+ Encaissements liés aux cessions d''immobilisations financières', 44, 'flux', 'entree', '{25,26,27}', '{}', '{}', null, true, false, false),
  ('syscohada', 'ZC', 'Flux de trésorerie provenant des activités d''investissement (somme FF à FJ)', 49, 'total', 'net', '{}', '{}', '{FF,FG,FH,FI,FJ}', null, true, true, false),
  ('syscohada', 'FK', '+ Augmentations de capital par apports nouveaux', 50, 'flux', 'entree', '{10}', '{}', '{}', null, true, false, false),
  ('syscohada', 'FL', '+ Subventions d''investissement reçues', 51, 'flux', 'entree', '{14}', '{}', '{}', null, true, false, false),
  ('syscohada', 'FM', '− Prélèvements sur le capital', 52, 'flux', 'sortie', '{10}', '{}', '{}', null, true, false, false),
  ('syscohada', 'FN', '− Dividendes versés', 53, 'flux', 'sortie', '{465}', '{}', '{}', null, true, false, false),
  ('syscohada', 'ZD', 'Flux de trésorerie provenant des capitaux propres (somme FK à FN)', 59, 'total', 'net', '{}', '{}', '{FK,FL,FM,FN}', null, true, true, false),
  ('syscohada', 'FO', '+ Emprunts', 60, 'flux', 'entree', '{16}', '{}', '{}', null, true, false, false),
  ('syscohada', 'FP', '+ Autres dettes financières', 61, 'flux', 'entree', '{17,18}', '{}', '{}', null, true, false, false),
  ('syscohada', 'FQ', '− Remboursements des emprunts et autres dettes financières', 62, 'flux', 'sortie', '{16,17,18}', '{}', '{}', null, true, false, false),
  ('syscohada', 'ZE', 'Flux de trésorerie provenant des capitaux étrangers (somme FO à FQ)', 69, 'total', 'net', '{}', '{}', '{FO,FP,FQ}', null, true, true, false),
  ('syscohada', 'ZF', 'Flux de trésorerie provenant des activités de financement (D + E)', 70, 'total', 'net', '{}', '{}', '{ZD,ZE}', null, true, true, false),
  ('syscohada', 'ZG', 'VARIATION DE LA TRÉSORERIE NETTE DE LA PÉRIODE (B + C + F)', 80, 'total', 'net', '{}', '{}', '{ZB,ZC,ZF}', null, true, true, false),
  ('syscohada', 'ZH', 'Trésorerie nette au 31 décembre (G + A)', 90, 'cloture', 'net', '{}', '{}', '{ZG,ZA}', null, true, true, false),
  -- SYCEBNL (méthode directe)
  ('sycebnl', 'ZA', 'Trésorerie nette au 1er janvier (trésorerie actif N-1 − trésorerie passif N-1)', 10, 'ouverture', 'net', '{}', '{}', '{}', null, true, true, true),
  ('sycebnl', 'FA', '+ Encaissement des cotisations', 20, 'flux', 'net', '{701,411}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FB', '+ Encaissement des subventions d''exploitation et d''équilibre', 21, 'flux', 'net', '{71,46}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FC', '+ Encaissement des revenus liés à la générosité', 22, 'flux', 'net', '{704,475,754}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FD', '+ Encaissement des revenus des manifestations', 23, 'flux', 'net', '{706}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FE', '+ Encaissement des autres revenus', 24, 'flux', 'net', '{70,72,73,75,77,412,419}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FF', '− Décaissement des sommes versées aux fournisseurs', 25, 'flux', 'net', '{40,60,61,62,63}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FG', '− Décaissement des sommes versées au personnel', 26, 'flux', 'net', '{42,66}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FH', '− Autres décaissements', 27, 'reste', 'net', '{}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'ZB', 'Flux de trésorerie provenant des activités opérationnelles (somme FA à FH)', 29, 'total', 'net', '{}', '{}', '{FA,FB,FC,FD,FE,FF,FG,FH}', null, true, true, true),
  ('sycebnl', 'FI', '− Décaissements liés aux acquisitions d''immobilisations incorporelles et corporelles', 40, 'flux', 'sortie', '{21,22,23,24,481,482}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FJ', '− Décaissements liés aux acquisitions d''immobilisations financières', 41, 'flux', 'sortie', '{25,26,27}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FK', '+ Encaissements liés aux cessions d''immobilisations incorporelles et corporelles', 42, 'flux', 'entree', '{21,22,23,24,82,485}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FL', '+ Encaissements liés aux cessions d''immobilisations financières', 43, 'flux', 'entree', '{25,26,27}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'ZC', 'Flux de trésorerie provenant des activités d''investissement (somme FI à FL)', 49, 'total', 'net', '{}', '{}', '{FI,FJ,FK,FL}', null, true, true, true),
  ('sycebnl', 'FM', '+ Encaissement des dotations et autres fonds propres (dont fonds affectés)', 50, 'flux', 'entree', '{10,11,15,16,17}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FN', '+ Subventions d''investissement reçues', 51, 'flux', 'entree', '{14}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FO', '− Décaissement des dotations et autres fonds propres', 52, 'flux', 'sortie', '{10,11,14,15,16,17}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'ZD', 'Flux de trésorerie provenant des fonds propres (somme FM à FO)', 59, 'total', 'net', '{}', '{}', '{FM,FN,FO}', null, true, true, true),
  ('sycebnl', 'FP', '+ Encaissements provenant des emprunts et autres dettes financières', 60, 'flux', 'entree', '{18}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'FQ', '− Remboursements des emprunts et autres dettes financières', 61, 'flux', 'sortie', '{18}', '{}', '{}', null, true, false, true),
  ('sycebnl', 'ZE', 'Flux de trésorerie provenant des fonds étrangers (somme FP à FQ)', 69, 'total', 'net', '{}', '{}', '{FP,FQ}', null, true, true, true),
  ('sycebnl', 'ZF', 'VARIATION DE LA TRÉSORERIE NETTE DE LA PÉRIODE (B + C + D + E)', 80, 'total', 'net', '{}', '{}', '{ZB,ZC,ZD,ZE}', null, true, true, true),
  ('sycebnl', 'ZG', 'Trésorerie nette au 31 décembre (F + A)', 90, 'cloture', 'net', '{}', '{}', '{ZF,ZA}', null, true, true, true),
  -- Comptabilité simplifiée
  ('simplifie', 'T0', 'Trésorerie au début de l''exercice', 10, 'ouverture', 'net', '{}', '{}', '{}', null, true, true, false),
  ('simplifie', 'T1', '+ Encaissements liés à l''activité (frais scolaires, dons, subventions…)', 20, 'flux', 'net', '{type:produit}', '{}', '{}', null, true, false, false),
  ('simplifie', 'T2', '− Décaissements liés à l''activité (achats, salaires, charges…)', 21, 'flux', 'net', '{type:charge}', '{}', '{}', null, true, false, false),
  ('simplifie', 'T3', 'Autres mouvements (tiers, équipements, apports, emprunts)', 22, 'reste', 'net', '{}', '{}', '{}', null, true, false, false),
  ('simplifie', 'T4', 'Variation de la trésorerie de l''exercice', 80, 'total', 'net', '{}', '{}', '{T1,T2,T3}', null, true, true, false),
  ('simplifie', 'T5', 'Trésorerie à la fin de l''exercice', 90, 'cloture', 'net', '{}', '{}', '{T4,T0}', null, true, true, false);

-- ---------------------------------------------------------------------------
-- 2. Calcul
-- ---------------------------------------------------------------------------
-- Longueur du préfixe le plus précis qui reconnaît le compte (0 : aucun).
create or replace function public.flux_correspondance(p_code text, p_type text, p_prefixes text[], p_exclusions text[])
returns integer
language sql
immutable
as $$
  select case
    when exists (select 1 from unnest(p_exclusions) e where p_code like e || '%') then 0
    else coalesce((select max(case when p like 'type:%' then (case when p = 'type:' || p_type then 1 else 0 end)
                                   when p_code like p || '%' then char_length(p) else 0 end)
                     from unnest(p_prefixes) p), 0)
  end;
$$;

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
    join public.plans_comptables c on c.id = l.compte_id
   where p.etablissement_id = p_etablissement and p.statut = 'validee'
     and p.date_piece between p_debut and p_fin;
  insert into _ft_lignes
  select e.id, c.id, c.code, c.type,
         case when p_plan = 'simplifie' then c.type in ('banque', 'caisse') else left(c.code, 1) = '5' end,
         false, case when s.cote = 'd' then e.montant else 0 end, case when s.cote = 'c' then e.montant else 0 end
    from public.ecritures_comptables e
    cross join lateral (values ('d', e.compte_debit_id), ('c', e.compte_credit_id)) as s(cote, compte_id)
    join public.plans_comptables c on c.id = s.compte_id
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

create or replace function public.tableau_flux_tresorerie(p_etablissement uuid, p_exercice_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  x public.exercices_comptables;
  v_prec public.exercices_comptables;
  v_plan text := coalesce(public.plan_du_referentiel(public.referentiel_comptable_de(p_etablissement)), 'simplifie');
  v_n jsonb;
  v_n1 jsonb;
  v_lignes jsonb := '[]'::jsonb;
  l jsonb;
begin
  if not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;
  select * into x from public.exercices_comptables where id = p_exercice_id and etablissement_id = p_etablissement;
  if x.id is null then
    raise exception 'EXERCICE_INTROUVABLE' using errcode = '22023';
  end if;
  v_n := public.calculer_flux_tresorerie(p_etablissement, v_plan, x.date_debut, x.date_fin);
  select * into v_prec from public.exercices_comptables
   where etablissement_id = p_etablissement and date_fin = x.date_debut - 1;
  if v_prec.id is not null then
    v_n1 := public.calculer_flux_tresorerie(p_etablissement, v_plan, v_prec.date_debut, v_prec.date_fin);
  end if;
  for l in select * from jsonb_array_elements(v_n->'lignes') loop
    v_lignes := v_lignes || jsonb_build_array(l || jsonb_build_object(
      'montant_n1', case when v_n1 is null then null else v_n1->'valeurs'->(l->>'reference') end));
  end loop;
  return jsonb_build_object(
    'plan', v_plan,
    'methode', case v_plan when 'syscohada' then 'indirecte' else 'directe' end,
    'provisoire', x.statut = 'ouvert' or (v_n->>'provisoire')::boolean,
    'lignes', v_lignes,
    'tresorerie_bilan', v_n->'tresorerie_bilan',
    'ecart_cloture', v_n->'ecart_cloture',
    'operationnel_direct', v_n->'operationnel_direct');
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Notes rédigées par l'école
-- ---------------------------------------------------------------------------
create table if not exists public.notes_annexes_redigees (
  exercice_id uuid not null references public.exercices_comptables (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  cle text not null check (cle in ('faits_marquants', 'methodes', 'continuite', 'evenements_posterieurs',
                                    'engagements_hors_bilan', 'autres_informations')),
  texte text not null check (char_length(texte) <= 8000),
  modifie_par uuid references public.profiles (id),
  modifie_le timestamptz not null default now(),
  primary key (exercice_id, cle)
);

alter table public.notes_annexes_redigees enable row level security;
drop policy if exists notes_annexes_lecture on public.notes_annexes_redigees;
create policy notes_annexes_lecture on public.notes_annexes_redigees for select
  using (public.est_comptable(etablissement_id));
revoke insert, update, delete on public.notes_annexes_redigees from anon, authenticated;

create or replace function public.enregistrer_note_annexe(p_exercice_id uuid, p_cle text, p_texte text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  x public.exercices_comptables;
begin
  select * into x from public.exercices_comptables where id = p_exercice_id;
  if x.id is null or not coalesce(public.est_comptable_ecriture(x.etablissement_id), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if x.statut = 'cloture' then
    raise exception 'EXERCICE_DEJA_CLOTURE' using errcode = '55000';
  end if;
  if nullif(trim(coalesce(p_texte, '')), '') is null then
    delete from public.notes_annexes_redigees where exercice_id = x.id and cle = p_cle;
    return;
  end if;
  insert into public.notes_annexes_redigees (exercice_id, etablissement_id, cle, texte, modifie_par)
  values (x.id, x.etablissement_id, p_cle, trim(p_texte), auth.uid())
  on conflict (exercice_id, cle) do update
    set texte = excluded.texte, modifie_par = excluded.modifie_par, modifie_le = now();
exception when check_violation then
  raise exception 'NOTE_INVALIDE' using errcode = '22023';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Notes annexes calculées
-- ---------------------------------------------------------------------------
create or replace function public.notes_annexes(p_etablissement uuid, p_exercice_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  x public.exercices_comptables;
  v_prec public.exercices_comptables;
  v_ref text := public.referentiel_comptable_de(p_etablissement);
  v_plan text := coalesce(public.plan_du_referentiel(public.referentiel_comptable_de(p_etablissement)), 'simplifie');
  v_etab public.etablissements;
  v_notes jsonb := '[]'::jsonb;
  v_redigees jsonb;
  v_pca numeric;
begin
  if not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;
  select * into x from public.exercices_comptables where id = p_exercice_id and etablissement_id = p_etablissement;
  if x.id is null then
    raise exception 'EXERCICE_INTROUVABLE' using errcode = '22023';
  end if;
  select * into v_etab from public.etablissements where id = p_etablissement;
  select * into v_prec from public.exercices_comptables
   where etablissement_id = p_etablissement and date_fin = x.date_debut - 1;

  -- Soldes par compte : ouverture (à-nouveaux), mouvements, clôture ; N-1.
  create temp table if not exists _na (
    compte_id uuid, code text, intitule text, type text,
    debut numeric, debits numeric, credits numeric, fin numeric, n1 numeric
  ) on commit drop;
  truncate _na;
  insert into _na
  select c.id, c.code, c.intitule, c.type,
         coalesce(sum(m.debit - m.credit) filter (where p.origine = 'a_nouveaux'), 0),
         coalesce(sum(m.debit) filter (where p.origine is distinct from 'a_nouveaux'), 0),
         coalesce(sum(m.credit) filter (where p.origine is distinct from 'a_nouveaux'), 0),
         coalesce(sum(m.debit - m.credit), 0), null
    from public.mouvements_comptables(p_etablissement, x.date_debut, x.date_fin) m
    join public.plans_comptables c on c.id = m.compte_id
    left join public.pieces_comptables p
      on p.reference = m.reference and p.etablissement_id = p_etablissement and m.reference is not null
   group by c.id, c.code, c.intitule, c.type;
  if v_prec.id is not null then
    update _na set n1 = s.solde
      from (select m.compte_id, sum(m.debit - m.credit) solde
              from public.mouvements_comptables(p_etablissement, v_prec.date_debut, v_prec.date_fin) m
             group by m.compte_id) s
     where s.compte_id = _na.compte_id;
    insert into _na
    select c.id, c.code, c.intitule, c.type, 0, 0, 0, 0, s.solde
      from (select m.compte_id, sum(m.debit - m.credit) solde
              from public.mouvements_comptables(p_etablissement, v_prec.date_debut, v_prec.date_fin) m
             group by m.compte_id) s
      join public.plans_comptables c on c.id = s.compte_id
     where not exists (select 1 from _na where _na.compte_id = s.compte_id);
  end if;

  select coalesce(jsonb_object_agg(cle, texte), '{}'::jsonb) into v_redigees
    from public.notes_annexes_redigees where exercice_id = x.id;

  -- Note 1 : règles et méthodes (texte généré + précisions de l'école).
  v_notes := v_notes || jsonb_build_array(jsonb_build_object(
    'code', '1', 'titre', 'Règles et méthodes comptables', 'genre', 'texte',
    'texte', concat_ws(E'\n',
      'Les états financiers sont établis selon le ' || case v_ref
          when 'syscohada_normal' then 'SYSCOHADA révisé (système normal)'
          when 'syscohada_smt' then 'SYSCOHADA révisé (système minimal de trésorerie)'
          when 'sycebnl' then 'Système comptable des entités à but non lucratif (SYCEBNL)'
          else 'référentiel simplifié de l''établissement' end
        || ', pour l''exercice du ' || to_char(x.date_debut, 'DD/MM/YYYY') || ' au ' || to_char(x.date_fin, 'DD/MM/YYYY')
        || ', en ' || coalesce(v_etab.devise_code, 'GNF') || '.',
      'Les frais scolaires sont comptabilisés à l''encaissement ; la part qui couvre l''année scolaire au-delà de la '
        || 'clôture est portée en produits constatés d''avance (prorata temporis).',
      case when v_plan = 'sycebnl' then
        'Les dons sont enregistrés en revenus liés à la générosité à leur réception ; les dons affectés à un projet '
        || 'restent en fonds affectés et sont repris en produits au fur et à mesure de leur emploi.' end,
      'Les salaires sont constatés à la validation du bulletin de paie et réglés à son paiement.',
      'Le tableau des flux de trésorerie suit la méthode '
        || case v_plan when 'syscohada' then 'indirecte (à partir de la capacité d''autofinancement)' else 'directe' end
        || ' ; chaque mouvement de trésorerie est rattaché à la contrepartie de sa pièce.',
      v_redigees->>'methodes'),
    'modifiable', 'methodes'));

  -- Note 2 : immobilisations (brut, mouvements, amortissements).
  v_notes := v_notes || jsonb_build_array(jsonb_build_object(
    'code', '2', 'titre', 'Immobilisations', 'genre', 'tableau',
    'colonnes', jsonb_build_array('Rubrique', 'Brut début', 'Augmentations', 'Diminutions', 'Brut fin', 'Amort. et dépréc.', 'Net fin'),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_array(g.libelle, g.debut, g.aug, g.dim, g.fin, g.amort, g.fin - g.amort) order by g.ordre)
        from (
          select k.ordre, k.libelle,
                 coalesce(sum(n.debut) filter (where n.code ~ k.brut), 0) debut,
                 coalesce(sum(n.debits) filter (where n.code ~ k.brut), 0) aug,
                 coalesce(sum(n.credits) filter (where n.code ~ k.brut), 0) dim,
                 coalesce(sum(n.fin) filter (where n.code ~ k.brut), 0) fin,
                 coalesce(-sum(n.fin) filter (where n.code ~ k.amort), 0) amort
            from (values (1, 'Immobilisations incorporelles', '^21', '^2[89]1'),
                         (2, 'Terrains', '^22', '^2[89]2'),
                         (3, 'Bâtiments et aménagements', '^23', '^2[89]3'),
                         (4, 'Matériel, mobilier et véhicules', '^24', '^2[89]4'),
                         (5, 'Immobilisations financières', '^2[5-7]', '^2[89][5-7]')) as k(ordre, libelle, brut, amort)
            left join _na n on n.code ~ k.brut or n.code ~ k.amort
           group by k.ordre, k.libelle) g
       where g.debut <> 0 or g.aug <> 0 or g.dim <> 0 or g.fin <> 0 or g.amort <> 0), '[]'::jsonb)));

  -- Note 3 : créances et dettes (montants positifs dans leur sens).
  v_notes := v_notes || jsonb_build_array(jsonb_build_object(
    'code', '3', 'titre', 'Créances et dettes', 'genre', 'tableau',
    'colonnes', jsonb_build_array('Rubrique', 'Sens', 'Début', 'Fin', 'Variation'),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_array(g.libelle, g.sens, g.debut, g.fin, g.fin - g.debut) order by g.ordre)
        from (
          select k.ordre, k.libelle, case when k.signe = 1 then 'créance' else 'dette' end sens,
                 coalesce(k.signe * sum(n.debut), 0) debut, coalesce(k.signe * sum(n.fin), 0) fin
            from (values (1, 'Familles et usagers', '^41', '^419', 1),
                         (2, 'Avances et trop-perçus des familles', '^419', '^$', -1),
                         (3, 'Fournisseurs', '^40', '^409', -1),
                         (4, 'Personnel', '^42', '^$', -1),
                         (5, 'Organismes sociaux', '^43', '^$', -1),
                         (6, 'État et collectivités', '^44', '^$', -1),
                         (7, 'Générosités et autres débiteurs', '^47[56]', '^$', 1),
                         (8, 'Produits constatés d''avance et autres créditeurs', '^47[0-47-9]|^4[5689]', '^$', -1)
                 ) as k(ordre, libelle, motif, exclu, signe)
            left join _na n on n.code ~ k.motif and n.code !~ k.exclu
           group by k.ordre, k.libelle, k.signe) g
       where g.debut <> 0 or g.fin <> 0), '[]'::jsonb)));

  -- Note 4 : trésorerie, compte par compte.
  v_notes := v_notes || jsonb_build_array(jsonb_build_object(
    'code', '4', 'titre', 'Trésorerie', 'genre', 'tableau',
    'colonnes', jsonb_build_array('Compte', 'Début', 'Fin', 'Variation'),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_array(n.code || ' ' || n.intitule, n.debut, n.fin, n.fin - n.debut) order by n.code)
        from _na n
       where (case when v_plan = 'simplifie' then n.type in ('banque', 'caisse') else left(n.code, 1) = '5' end)
         and (n.debut <> 0 or n.fin <> 0)), '[]'::jsonb)));

  -- Note 5 : variation des fonds propres et ressources assimilées.
  v_notes := v_notes || jsonb_build_array(jsonb_build_object(
    'code', '5', 'titre', case when v_plan = 'sycebnl' then 'Fonds propres, fonds affectés et ressources assimilées'
                               else 'Capitaux propres et ressources assimilées' end,
    'genre', 'tableau',
    'colonnes', jsonb_build_array('Rubrique', 'Début', 'Augmentations', 'Diminutions', 'Fin'),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_array(g.libelle, g.debut, g.aug, g.dim, g.fin) order by g.ordre)
        from (
          select k.ordre, case when v_plan = 'sycebnl' then k.lib_ebnl else k.lib end libelle,
                 coalesce(-sum(n.debut), 0) debut, coalesce(sum(n.credits), 0) aug,
                 coalesce(sum(n.debits), 0) dim, coalesce(-sum(n.fin), 0) fin
            from (values (1, '^10', 'Capital', 'Dotations'),
                         (2, '^11', 'Réserves', 'Réserves'),
                         (3, '^1[23]', 'Report à nouveau et résultat antérieur', 'Report à nouveau et résultat antérieur'),
                         (4, '^14', 'Subventions d''investissement', 'Subventions d''investissement'),
                         (5, '^15', 'Provisions réglementées', 'Provisions réglementées'),
                         (6, '^16', 'Emprunts et dettes assimilées', 'Fonds affectés et fonds provenant de dons et legs'),
                         (7, '^1[7-9]', 'Autres dettes financières et provisions', 'Fonds reportés, emprunts et provisions')
                 ) as k(ordre, motif, lib, lib_ebnl)
            left join _na n on n.code ~ k.motif
           group by k.ordre, k.lib, k.lib_ebnl) g
       where g.debut <> 0 or g.aug <> 0 or g.dim <> 0 or g.fin <> 0), '[]'::jsonb)
      || jsonb_build_array(jsonb_build_array(
           case when v_plan = 'sycebnl' then 'Résultat de l''exercice (excédent ou déficit)' else 'Résultat de l''exercice' end,
           0, 0, 0, coalesce((select -sum(fin) from _na where type in ('charge', 'produit')), 0)))));

  -- Notes 6 et 7 : produits et charges, compte par compte, N et N-1.
  v_notes := v_notes || jsonb_build_array(jsonb_build_object(
    'code', '6', 'titre', 'Produits', 'genre', 'tableau',
    'colonnes', jsonb_build_array('Compte', 'Exercice N', 'Exercice N-1', 'Variation %'),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_array(n.code || ' ' || n.intitule, -n.fin, -n.n1,
               case when coalesce(n.n1, 0) = 0 then null else round(100 * (n.fin - n.n1) / n.n1, 1) end) order by n.code)
        from _na n where n.type = 'produit' and (n.fin <> 0 or coalesce(n.n1, 0) <> 0)), '[]'::jsonb)));
  v_notes := v_notes || jsonb_build_array(jsonb_build_object(
    'code', '7', 'titre', 'Charges', 'genre', 'tableau',
    'colonnes', jsonb_build_array('Compte', 'Exercice N', 'Exercice N-1', 'Variation %'),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_array(n.code || ' ' || n.intitule, n.fin, n.n1,
               case when coalesce(n.n1, 0) = 0 then null else round(100 * (n.fin - n.n1) / n.n1, 1) end) order by n.code)
        from _na n where n.type = 'charge' and (n.fin <> 0 or coalesce(n.n1, 0) <> 0)), '[]'::jsonb)));

  -- Note 8 : personnel (effectifs à la clôture, masse salariale).
  v_notes := v_notes || jsonb_build_array(jsonb_build_object(
    'code', '8', 'titre', 'Personnel', 'genre', 'tableau',
    'colonnes', jsonb_build_array('Indicateur', 'Valeur'),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_array('Effectif — ' || case e.categorie
               when 'enseignant' then 'enseignants' when 'administratif' then 'administratifs'
               when 'direction' then 'direction' else 'autres personnels' end, e.nombre) order by e.categorie)
        from (select categorie, count(*) nombre from public.employes
               where etablissement_id = p_etablissement and deleted_at is null and date_embauche <= x.date_fin
               group by categorie) e), '[]'::jsonb)
      || jsonb_build_array(
           jsonb_build_array('Bulletins de paie validés ou payés',
             (select count(*) from public.paie_bulletins b
               where b.etablissement_id = p_etablissement and b.deleted_at is null and b.statut in ('valide', 'paye')
                 and b.periode_fin between x.date_debut and x.date_fin)),
           jsonb_build_array('Charges de personnel de l''exercice',
             coalesce((select sum(fin) from _na where type = 'charge' and code like '66%'), 0)))));

  -- Note 9 : produits constatés d'avance.
  select coalesce(-sum(fin), 0) into v_pca from _na where code like '477%';
  v_notes := v_notes || jsonb_build_array(jsonb_build_object(
    'code', '9', 'titre', 'Produits constatés d''avance', 'genre', 'texte',
    'texte', case when v_pca = 0
      then 'Aucun produit constaté d''avance à la clôture.'
      else 'Frais scolaires encaissés au cours de l''exercice et couvrant la part de l''année scolaire postérieure '
           || 'à la clôture : ' || to_char(v_pca, 'FM999G999G999G990') || ' ' || coalesce(v_etab.devise_code, 'GNF')
           || ' (compte 477), repris en produits au premier jour de l''exercice suivant.' end));

  -- Notes propres aux entités à but non lucratif.
  if v_plan = 'sycebnl' then
    v_notes := v_notes || jsonb_build_array(jsonb_build_object(
      'code', '10', 'titre', 'Ressources liées à la générosité', 'genre', 'tableau',
      'colonnes', jsonb_build_array('Nature', 'Nombre de dons', 'Montant'),
      'lignes', coalesce((
        select jsonb_agg(jsonb_build_array(public.libelle_nature_don(d.nature), d.n, d.s) order by d.s desc)
          from (select nature, count(*) n, sum(montant) s from public.dons
                 where etablissement_id = p_etablissement and statut = 'valide'
                   and date_don between x.date_debut and x.date_fin group by nature) d), '[]'::jsonb)
        || jsonb_build_array(jsonb_build_array('Donateurs distincts',
             (select count(distinct donateur_id) from public.dons
               where etablissement_id = p_etablissement and statut = 'valide'
                 and date_don between x.date_debut and x.date_fin), null))));

    v_notes := v_notes || jsonb_build_array(jsonb_build_object(
      'code', '11', 'titre', 'Fonds affectés à des projets', 'genre', 'tableau',
      'colonnes', jsonb_build_array('Projet', 'Report au début', 'Reçus', 'Employés', 'Solde à reporter'),
      'lignes', coalesce((
        select jsonb_agg(jsonb_build_array(f.libelle, f.report, f.recus, f.employes, f.report + f.recus - f.employes)
                         order by f.libelle)
          from (
            select a.libelle,
                   coalesce((select sum(d.montant) from public.dons d where d.affectation_id = a.id and d.statut = 'valide'
                              and d.date_don < x.date_debut), 0)
                 - coalesce((select sum(e.montant) from public.emplois_fonds_affectes e where e.affectation_id = a.id
                              and e.statut = 'valide' and e.date_emploi < x.date_debut), 0) report,
                   coalesce((select sum(d.montant) from public.dons d where d.affectation_id = a.id and d.statut = 'valide'
                              and d.date_don between x.date_debut and x.date_fin), 0) recus,
                   coalesce((select sum(e.montant) from public.emplois_fonds_affectes e where e.affectation_id = a.id
                              and e.statut = 'valide' and e.date_emploi between x.date_debut and x.date_fin), 0) employes
              from public.affectations_dons a
             where a.etablissement_id = p_etablissement and a.type = 'projet') f
         where f.report <> 0 or f.recus <> 0 or f.employes <> 0), '[]'::jsonb)));

    v_notes := v_notes || jsonb_build_array(jsonb_build_object(
      'code', '12', 'titre', 'Engagements reçus (promesses et parrainages en cours)', 'genre', 'tableau',
      'colonnes', jsonb_build_array('Donateur', 'Montant par échéance', 'Fréquence', 'Montant annuel'),
      'lignes', coalesce((
        select jsonb_agg(jsonb_build_array(trim(o.nom || ' ' || coalesce(o.prenom, '')), e.montant, e.periodicite,
                 e.montant * case e.periodicite when 'mensuelle' then 12 when 'trimestrielle' then 4 else 1 end)
               order by o.nom)
          from public.engagements_dons e join public.donateurs o on o.id = e.donateur_id
         where e.etablissement_id = p_etablissement and e.actif
           and e.date_debut <= x.date_fin and (e.date_fin is null or e.date_fin >= x.date_fin)), '[]'::jsonb)));
  end if;

  -- Notes rédigées par l'école (vides : proposées à la saisie).
  v_notes := v_notes || coalesce((
    select jsonb_agg(jsonb_build_object('code', k.code, 'titre', k.titre, 'genre', 'texte',
                                        'texte', v_redigees->>k.cle, 'modifiable', k.cle) order by k.ordre)
      from (values (1, 'A', 'faits_marquants', 'Faits marquants de l''exercice'),
                   (2, 'B', 'continuite', 'Continuité de l''activité'),
                   (3, 'C', 'evenements_posterieurs', 'Événements postérieurs à la clôture'),
                   (4, 'D', 'engagements_hors_bilan', 'Engagements donnés et reçus hors bilan'),
                   (5, 'E', 'autres_informations', 'Autres informations')) as k(ordre, code, cle, titre)), '[]'::jsonb);

  return jsonb_build_object(
    'referentiel', v_ref,
    'plan', v_plan,
    'exercice', jsonb_build_object('id', x.id, 'libelle', x.libelle, 'cloture', x.statut = 'cloture'),
    'devise', coalesce(v_etab.devise_code, 'GNF'),
    'notes', v_notes);
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
    'public.calculer_flux_tresorerie(uuid, text, date, date)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  foreach f in array array[
    'public.tableau_flux_tresorerie(uuid, uuid)',
    'public.notes_annexes(uuid, uuid)',
    'public.enregistrer_note_annexe(uuid, text, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;
