-- ============================================================================
-- EcoShop — REG-03, lot C5 (1/3) : la paie passe en comptabilité
-- (proposition validée le 2026-10-17 : docs/propositions/REG-03_COMPTABILITE.md)
--
-- Bulletin de paie M8 (`paie_bulletins`, brouillon → valide → paye) :
--   • VALIDÉ  → constatation, datée de la fin de période :
--               Débit  charges de personnel (salaire de base + primes)
--               Crédit personnel, rémunérations dues (net)
--               Crédit retenues (salaire brut − net)
--   • PAYÉ    → règlement, daté du jour du passage à « payé » :
--               Débit  personnel, rémunérations dues / Crédit trésorerie
--   • modifié, supprimé ou ramené en brouillon après coup → les pièces
--     devenues fausses sont contre-passées (art. 20), puis les bonnes sont
--     créées : la comptabilité suit toujours le bulletin.
--
-- Comptes par défaut (remplaçables par l'école, comme au lot C3) :
--   SYSCOHADA : 661 / 422 / 447 / 571 ;  SYCEBNL : 66 / 422 / 44 / 571.
-- Les retenues de M8 sont un total unique (cotisation salariale, impôt,
-- avance…) : un seul compte par défaut, à affiner avec l'expert-comptable.
-- Les charges patronales ne sont pas encore calculées par M8 (hors champ).
--
-- Même principe de sûreté qu'au lot C3 : la comptabilité ne bloque jamais
-- la paie ; tout échec devient un incident, rattrapé par
-- `comptabiliser_en_attente`.
--
-- Migration idempotente.
-- ============================================================================

alter table public.pieces_comptables drop constraint if exists pieces_comptables_source_type_check;
alter table public.pieces_comptables add constraint pieces_comptables_source_type_check
  check (source_type is null or source_type in (
    'encaissement_scolarite', 'produits_constates_avance', 'extourne_pca', 'paie_constatation', 'paie_reglement'));

alter table public.regles_comptabilisation drop constraint if exists regles_comptabilisation_cle_check;
alter table public.regles_comptabilisation add constraint regles_comptabilisation_cle_check
  check (cle in (
    'tresorerie:especes', 'tresorerie:mobile_money', 'tresorerie:virement', 'tresorerie:cheque', 'tresorerie:autre',
    'produit:scolarite', 'produit:inscription', 'produit:cantine', 'produit:transport', 'produit:autre',
    'paie:charge', 'paie:dette', 'paie:retenues', 'paie:tresorerie'));

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
      when 'syscohada' then case p_cle
        when 'produit:scolarite' then '70611' when 'produit:inscription' then '70612'
        when 'produit:cantine' then '70613' when 'produit:transport' then '70614'
        when 'produit:autre' then '70618'
        when 'paie:charge' then '661' when 'paie:retenues' then '447' end
      when 'sycebnl' then case p_cle
        when 'produit:scolarite' then '70521' when 'produit:inscription' then '70522'
        when 'produit:cantine' then '70523' when 'produit:transport' then '70524'
        when 'produit:autre' then '70528'
        when 'paie:charge' then '66' when 'paie:retenues' then '44' end
    end
  end;
$$;

-- ---------------------------------------------------------------------------
-- Synchronisation d'un bulletin avec ses pièces (idempotente)
-- ---------------------------------------------------------------------------
create or replace function public.creer_piece_paie(
  b public.paie_bulletins, p_type text, p_date date, p_lignes jsonb)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  x public.exercices_comptables;
  v_id uuid;
  v_journal uuid;
  v_nom text;
  l jsonb;
  v_ordre smallint := 0;
begin
  x := public.exercice_ouvert_pour(b.etablissement_id, p_date);
  if x.id is null then
    raise exception 'AUCUN_EXERCICE_OUVERT' using errcode = '55000';
  end if;
  if public.date_comptable_figee(b.etablissement_id, p_date) then
    raise exception 'PERIODE_CLOTUREE' using errcode = '55000';
  end if;

  insert into public.journaux (etablissement_id, code, intitule, type)
  values (b.etablissement_id, 'PAIE', 'Paie', 'operations')
  on conflict (etablissement_id, code) do update set deleted_at = null
  returning id into v_journal;

  select nullif(trim(coalesce(p.nom, '') || ' ' || coalesce(p.prenom, '')), '') into v_nom
    from public.employes e join public.profiles p on p.id = e.profile_id where e.id = b.employe_id;

  insert into public.pieces_comptables
    (etablissement_id, exercice_id, journal_id, date_piece, libelle, piece_justificative, origine, source_type, source_id)
  values (b.etablissement_id, x.id, v_journal, p_date,
          left(case p_type when 'paie_constatation' then 'Salaire ' else 'Paiement du salaire ' end
               || to_char(b.periode_debut, 'MM/YYYY') || coalesce(' — ' || v_nom, ''), 300),
          'PAIE-' || upper(left(replace(b.id::text, '-', ''), 8)),
          'automatique', p_type, b.id)
  returning id into v_id;

  for l in select * from jsonb_array_elements(p_lignes) loop
    if coalesce((l->>'debit')::numeric, 0) = 0 and coalesce((l->>'credit')::numeric, 0) = 0 then
      continue;
    end if;
    insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, libelle, debit, credit, ordre)
    values (v_id, b.etablissement_id, (l->>'compte_id')::uuid, l->>'libelle',
            coalesce((l->>'debit')::numeric, 0), coalesce((l->>'credit')::numeric, 0), v_ordre);
    v_ordre := v_ordre + 1;
  end loop;

  perform public.numeroter_et_valider_piece(v_id, null);
  return v_id;
end;
$$;

create or replace function public.synchroniser_paie(p_bulletin_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  b public.paie_bulletins;
  v_charge uuid;
  v_dette uuid;
  v_retenues uuid;
  v_treso uuid;
  v_constat public.pieces_comptables;
  v_regl public.pieces_comptables;
  v_veut_constat boolean;
  v_veut_regl boolean;
  v_brut numeric;
  v_actions text := '';
  v_montant numeric;
begin
  select * into b from public.paie_bulletins where id = p_bulletin_id;
  if b.id is null then
    return 'introuvable';
  end if;

  -- Comptabilité simplifiée sans règles « paie » et sans pièce existante :
  -- rien d'automatique (ce n'est pas une erreur).
  if public.plan_du_referentiel(public.referentiel_comptable_de(b.etablissement_id)) is null
     and not exists (select 1 from public.regles_comptabilisation
                      where etablissement_id = b.etablissement_id and cle like 'paie:%')
     and not exists (select 1 from public.pieces_comptables
                      where source_id = b.id and source_type like 'paie_%') then
    return 'non_applicable';
  end if;

  v_charge := public.compte_comptabilisation(b.etablissement_id, 'paie:charge');
  v_dette := public.compte_comptabilisation(b.etablissement_id, 'paie:dette');
  v_retenues := public.compte_comptabilisation(b.etablissement_id, 'paie:retenues');
  v_treso := public.compte_comptabilisation(b.etablissement_id, 'paie:tresorerie');

  select * into v_constat from public.pieces_comptables
   where source_type = 'paie_constatation' and source_id = b.id and origine = 'automatique';
  select * into v_regl from public.pieces_comptables
   where source_type = 'paie_reglement' and source_id = b.id and origine = 'automatique';

  v_brut := b.salaire_base + b.primes;
  v_veut_constat := b.deleted_at is null and b.statut in ('valide', 'paye') and v_brut > 0;
  v_veut_regl := b.deleted_at is null and b.statut = 'paye' and b.net > 0;

  -- 1. Pièces devenues fausses : contre-passation (jamais de modification).
  if v_regl.id is not null and v_regl.annulee_par_piece_id is null then
    select sum(l.debit) into v_montant from public.lignes_pieces_comptables l where l.piece_id = v_regl.id;
    if not v_veut_regl or v_montant is distinct from b.net then
      perform public.contrepasser_piece_interne(v_regl.id, 'Bulletin de paie modifié ou annulé',
        greatest(current_date, v_regl.date_piece), null);
      v_actions := v_actions || 'reglement_contrepasse ';
    end if;
  end if;
  if v_constat.id is not null and v_constat.annulee_par_piece_id is null then
    select sum(l.debit) into v_montant from public.lignes_pieces_comptables l where l.piece_id = v_constat.id;
    if not v_veut_constat or v_montant is distinct from v_brut
       or not exists (select 1 from public.lignes_pieces_comptables l
                       where l.piece_id = v_constat.id and l.credit = b.net and l.compte_id = v_dette) then
      perform public.contrepasser_piece_interne(v_constat.id, 'Bulletin de paie modifié ou annulé',
        greatest(current_date, v_constat.date_piece), null);
      v_actions := v_actions || 'constatation_contrepassee ';
    end if;
  end if;

  -- 2. Pièces manquantes. L'index unique (source_type, source_id) n'admet
  --    qu'une pièce automatique par type : après contre-passation, la
  --    nouvelle pièce remplace l'ancienne dans l'index en la renommant.
  if v_veut_constat and not exists (
       select 1 from public.pieces_comptables
        where source_type = 'paie_constatation' and source_id = b.id and origine = 'automatique'
          and annulee_par_piece_id is null) then
    if v_charge is null or v_dette is null or (b.retenues > 0 and v_retenues is null) then
      raise exception 'COMPTE_AUTO_INTROUVABLE' using errcode = '55000';
    end if;
    update public.pieces_comptables set source_type = 'paie_constatation_annulee'
     where source_type = 'paie_constatation' and source_id = b.id and origine = 'automatique';
    perform public.creer_piece_paie(b, 'paie_constatation', b.periode_fin, jsonb_build_array(
      jsonb_build_object('compte_id', v_charge, 'debit', v_brut, 'libelle', 'Salaire brut'),
      jsonb_build_object('compte_id', v_dette, 'credit', b.net, 'libelle', 'Net à payer'),
      jsonb_build_object('compte_id', v_retenues, 'credit', b.retenues, 'libelle', 'Retenues')));
    v_actions := v_actions || 'constatation ';
  end if;

  if v_veut_regl and not exists (
       select 1 from public.pieces_comptables
        where source_type = 'paie_reglement' and source_id = b.id and origine = 'automatique'
          and annulee_par_piece_id is null) then
    if v_dette is null or v_treso is null then
      raise exception 'COMPTE_AUTO_INTROUVABLE' using errcode = '55000';
    end if;
    update public.pieces_comptables set source_type = 'paie_reglement_annule'
     where source_type = 'paie_reglement' and source_id = b.id and origine = 'automatique';
    perform public.creer_piece_paie(b, 'paie_reglement', greatest(current_date, b.periode_fin), jsonb_build_array(
      jsonb_build_object('compte_id', v_dette, 'debit', b.net, 'libelle', 'Salaire payé'),
      jsonb_build_object('compte_id', v_treso, 'credit', b.net, 'libelle', 'Salaire payé')));
    v_actions := v_actions || 'reglement ';
  end if;

  return coalesce(nullif(trim(v_actions), ''), 'a_jour');
end;
$$;

-- Les pièces renommées ci-dessus doivent rester valides vis-à-vis de la
-- contrainte : on ajoute les deux états « annulés ».
alter table public.pieces_comptables drop constraint if exists pieces_comptables_source_type_check;
alter table public.pieces_comptables add constraint pieces_comptables_source_type_check
  check (source_type is null or source_type in (
    'encaissement_scolarite', 'produits_constates_avance', 'extourne_pca',
    'paie_constatation', 'paie_reglement', 'paie_constatation_annulee', 'paie_reglement_annule'));

-- La pièce validée est immuable ; seul le renommage technique de sa
-- source (pour libérer l'index d'unicité après contre-passation) est admis.
create or replace function public.pieces_validees_immuables()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if old.statut = 'validee' then
      raise exception 'PIECE_VALIDEE_IMMUABLE' using errcode = '42501';
    end if;
    return old;
  end if;
  if old.statut = 'validee' then
    if (to_jsonb(new) - 'annulee_par_piece_id' - 'updated_at' - 'source_type')
         = (to_jsonb(old) - 'annulee_par_piece_id' - 'updated_at' - 'source_type')
       and (new.annulee_par_piece_id is not distinct from old.annulee_par_piece_id
            or (old.annulee_par_piece_id is null and new.annulee_par_piece_id is not null))
       and (new.source_type is not distinct from old.source_type
            or new.source_type in ('paie_constatation_annulee', 'paie_reglement_annule')) then
      return new;
    end if;
    raise exception 'PIECE_VALIDEE_IMMUABLE' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.paie_comptabiliser()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform public.synchroniser_paie(new.id);
    update public.incidents_comptabilisation set resolu = true, resolu_le = now()
     where source_type = 'paie_bulletin' and source_id = new.id and not resolu;
  exception when others then
    insert into public.incidents_comptabilisation (etablissement_id, source_type, source_id, operation, code, detail)
    values (new.etablissement_id, 'paie_bulletin', new.id, 'comptabilisation', left(sqlerrm, 80), sqlstate);
  end;
  return null;
end;
$$;

drop trigger if exists paie_comptabiliser on public.paie_bulletins;
create trigger paie_comptabiliser
  after insert or update on public.paie_bulletins
  for each row execute function public.paie_comptabiliser();

-- Suppression définitive d'un bulletin (au lieu de l'archivage) : ses
-- pièces encore actives sont contre-passées avant qu'il disparaisse.
-- Comme ailleurs, un échec ne bloque pas la suppression : il devient un
-- incident (la pièce reste visible et se corrige à la main).
create or replace function public.paie_suppression_comptabiliser()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
begin
  for p in select id, date_piece from public.pieces_comptables
            where source_id = old.id and source_type in ('paie_reglement', 'paie_constatation')
              and origine = 'automatique' and annulee_par_piece_id is null
            order by source_type  -- règlement d'abord
  loop
    begin
      perform public.contrepasser_piece_interne(p.id, 'Bulletin de paie supprimé',
        greatest(current_date, p.date_piece), null);
    exception when others then
      insert into public.incidents_comptabilisation (etablissement_id, source_type, source_id, operation, code, detail)
      values (old.etablissement_id, 'paie_bulletin', old.id, 'annulation', left(sqlerrm, 80), sqlstate);
    end;
  end loop;
  return old;
end;
$$;

drop trigger if exists paie_suppression_comptabiliser on public.paie_bulletins;
create trigger paie_suppression_comptabiliser
  before delete on public.paie_bulletins
  for each row execute function public.paie_suppression_comptabiliser();

-- ---------------------------------------------------------------------------
-- Rattrapage et état : la paie rejoint les encaissements
-- ---------------------------------------------------------------------------
create or replace function public.paie_a_synchroniser(p_etablissement uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  with applicable as (
    select public.plan_du_referentiel(public.referentiel_comptable_de(p_etablissement)) is not null
        or exists (select 1 from public.regles_comptabilisation
                    where etablissement_id = p_etablissement and cle like 'paie:%') as oui
  )
  select b.id from public.paie_bulletins b, applicable a
   where b.etablissement_id = p_etablissement
     and (
       (a.oui and b.deleted_at is null and b.statut in ('valide', 'paye')
        and not exists (select 1 from public.pieces_comptables p
                         where p.source_type = 'paie_constatation' and p.source_id = b.id and p.origine = 'automatique' and p.annulee_par_piece_id is null))
       or (a.oui and b.deleted_at is null and b.statut = 'paye'
        and not exists (select 1 from public.pieces_comptables p
                         where p.source_type = 'paie_reglement' and p.source_id = b.id and p.origine = 'automatique' and p.annulee_par_piece_id is null))
       or ((b.deleted_at is not null or b.statut = 'brouillon')
        and exists (select 1 from public.pieces_comptables p
                     where p.source_type in ('paie_constatation', 'paie_reglement') and p.source_id = b.id
                       and p.origine = 'automatique' and p.annulee_par_piece_id is null)));
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
            or (e.statut = 'annule' and p.id is not null and p.origine = 'automatique' and p.annulee_par_piece_id is null))
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
       where e.etablissement_id = p_etablissement and e.statut = 'annule' and p.origine = 'automatique' and p.annulee_par_piece_id is null),
    'paies_a_synchroniser', (select count(*) from public.paie_a_synchroniser(p_etablissement)),
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
          (11, 'paie:charge'), (12, 'paie:dette'), (13, 'paie:retenues'), (14, 'paie:tresorerie')
        ) as k(ordre, cle)
        left join public.plans_comptables c on c.id = public.compte_comptabilisation(p_etablissement, k.cle)), '[]'::jsonb)
  );
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.creer_piece_paie(public.paie_bulletins, text, date, jsonb)',
    'public.synchroniser_paie(uuid)',
    'public.paie_comptabiliser()',
    'public.paie_suppression_comptabiliser()',
    'public.paie_a_synchroniser(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;
