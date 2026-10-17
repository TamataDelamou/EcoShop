-- ============================================================================
-- EcoShop — REG-03, lot C3 : comptabilisation automatique des encaissements
-- (proposition validée le 2026-10-17 : docs/propositions/REG-03_COMPTABILITE.md)
--
-- Chaque encaissement de scolarité (M15quater) — espèces, Orange Money
-- (créé par `traiter_resultat_mobile_money`), virement, chèque — produit
-- sa pièce comptable VALIDÉE, sans ressaisie ; son annulation produit la
-- contre-passation (art. 20 de l'Acte uniforme).
--
--   Encaissement : Débit  trésorerie du moyen de paiement
--                  Crédit produit du type de frais
--   Annulation   : contre-passation en négatif de la pièce automatique
--
-- Comptes par défaut (référentiels OHADA, remplaçables par l'école) :
--   espèces / autre → 571 ; Orange Money → 5521 ; virement / chèque → 521 ;
--   SYSCOHADA : 70611-70618 ; SYCEBNL : 70521-70528.
-- Journaux créés au besoin : CAI (caisse), OM (Orange Money), BQ (banque).
-- En comptabilité simplifiée, rien n'est automatique tant que l'école n'a
-- pas désigné ses comptes (`definir_regle_comptabilisation`).
--
-- Principe de sûreté : la comptabilité ne bloque JAMAIS l'encaissement.
-- Sans exercice ouvert, en période clôturée ou sans compte, l'encaissement
-- est enregistré et un incident est consigné ; `comptabiliser_en_attente`
-- rattrape tout ce qui manque, de façon idempotente (une seule pièce par
-- encaissement, garantie par un index unique).
--
-- Reconnaissance du produit : à l'encaissement (cohérent avec le Système
-- minimal de trésorerie). En Système normal, la part des frais couvrant
-- l'exercice suivant relève des produits constatés d'avance : régularisation
-- prévue avec les états financiers (lot C4) — à valider par l'expert-comptable.
--
-- Hors périmètre : ventes marketplace (l'argent revient au vendeur, pas à
-- l'école) ; facturation GSG / CinetPay (charges de l'école envers GSG,
-- à saisir comme fournisseur).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Lien pièce ↔ opération d'origine
-- ---------------------------------------------------------------------------
alter table public.pieces_comptables add column if not exists source_type text
  check (source_type is null or source_type in ('encaissement_scolarite'));
alter table public.pieces_comptables add column if not exists source_id uuid;

create unique index if not exists idx_pieces_source_automatique
  on public.pieces_comptables (source_type, source_id)
  where origine = 'automatique';

-- ---------------------------------------------------------------------------
-- 2. Règles de comptabilisation (comptes choisis par l'école)
-- ---------------------------------------------------------------------------
create table if not exists public.regles_comptabilisation (
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  cle text not null check (cle in (
    'tresorerie:especes', 'tresorerie:mobile_money', 'tresorerie:virement', 'tresorerie:cheque', 'tresorerie:autre',
    'produit:scolarite', 'produit:inscription', 'produit:cantine', 'produit:transport', 'produit:autre')),
  compte_id uuid not null references public.plans_comptables (id) on delete cascade,
  modifie_par uuid references public.profiles (id),
  modifie_le timestamptz not null default now(),
  primary key (etablissement_id, cle)
);

alter table public.regles_comptabilisation enable row level security;
drop policy if exists regles_comptabilisation_select on public.regles_comptabilisation;
create policy regles_comptabilisation_select on public.regles_comptabilisation
  for select using (public.est_comptable(etablissement_id));
revoke insert, update, delete on public.regles_comptabilisation from public, anon, authenticated;

-- Incidents : ce qui n'a pas pu être comptabilisé, et pourquoi.
create table if not exists public.incidents_comptabilisation (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  source_type text not null,
  source_id uuid not null,
  operation text not null check (operation in ('comptabilisation', 'annulation')),
  code text not null,
  detail text,
  resolu boolean not null default false,
  created_at timestamptz not null default now(),
  resolu_le timestamptz
);

create index if not exists idx_incidents_ouverts
  on public.incidents_comptabilisation (etablissement_id, created_at desc) where not resolu;

alter table public.incidents_comptabilisation enable row level security;
drop policy if exists incidents_comptabilisation_select on public.incidents_comptabilisation;
create policy incidents_comptabilisation_select on public.incidents_comptabilisation
  for select using (public.est_comptable(etablissement_id));
revoke insert, update, delete on public.incidents_comptabilisation from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Résolution des comptes et journaux
-- ---------------------------------------------------------------------------
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
    else case p_plan
      when 'syscohada' then case p_cle
        when 'produit:scolarite' then '70611' when 'produit:inscription' then '70612'
        when 'produit:cantine' then '70613' when 'produit:transport' then '70614'
        when 'produit:autre' then '70618' end
      when 'sycebnl' then case p_cle
        when 'produit:scolarite' then '70521' when 'produit:inscription' then '70522'
        when 'produit:cantine' then '70523' when 'produit:transport' then '70524'
        when 'produit:autre' then '70528' end
    end
  end;
$$;

-- Compte effectif : règle de l'école, sinon compte par défaut du plan
-- (actif, non supprimé, et de détail).
create or replace function public.compte_comptabilisation(p_etablissement uuid, p_cle text)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_plan text := public.plan_du_referentiel(public.referentiel_comptable_de(p_etablissement));
begin
  select r.compte_id into v_id
    from public.regles_comptabilisation r
    join public.plans_comptables c on c.id = r.compte_id and c.deleted_at is null and c.actif
   where r.etablissement_id = p_etablissement and r.cle = p_cle;
  if v_id is not null or v_plan is null then
    return v_id;
  end if;
  select c.id into v_id from public.plans_comptables c
   where c.etablissement_id = p_etablissement and c.deleted_at is null and c.actif
     and c.code = public.code_compte_par_defaut(v_plan, p_cle)
     and not exists (select 1 from public.plans_comptables f
                      where f.parent_id = c.id and f.deleted_at is null and f.actif);
  return v_id;
end;
$$;

create or replace function public.journal_automatique(p_etablissement uuid, p_moyen text)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_code text := case p_moyen when 'mobile_money' then 'OM' when 'virement' then 'BQ' when 'cheque' then 'BQ' else 'CAI' end;
  v_id uuid;
begin
  insert into public.journaux (etablissement_id, code, intitule, type)
  values (p_etablissement, v_code,
          case v_code when 'OM' then 'Orange Money' when 'BQ' then 'Banque' else 'Caisse' end,
          case v_code when 'CAI' then 'caisse' else 'banque' end)
  on conflict (etablissement_id, code) do update set deleted_at = null
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Contre-passation : noyau commun (RPC et système)
-- ---------------------------------------------------------------------------
create or replace function public.contrepasser_piece_interne(
  p_piece_id uuid, p_motif text, p_date date, p_auteur uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  o public.pieces_comptables;
  x public.exercices_comptables;
  v_id uuid;
begin
  select * into o from public.pieces_comptables where id = p_piece_id for update;
  if o.id is null then
    raise exception 'PIECE_INTROUVABLE' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_motif, ''))) = 0 then
    raise exception 'MOTIF_REQUIS' using errcode = '22023';
  end if;
  if o.statut <> 'validee' or o.origine in ('contrepassation', 'a_nouveaux') then
    raise exception 'PIECE_NON_CONTREPASSABLE' using errcode = '55000';
  end if;
  if o.annulee_par_piece_id is not null then
    raise exception 'PIECE_DEJA_CONTREPASSEE' using errcode = '55000';
  end if;
  if not exists (select 1 from public.exercices_comptables where id = o.exercice_id and statut = 'ouvert') then
    raise exception 'PIECE_EXERCICE_CLOTURE' using errcode = '55000';
  end if;
  x := public.exercice_ouvert_pour(o.etablissement_id, p_date);
  if x.id is null or x.id <> o.exercice_id or p_date < o.date_piece then
    raise exception 'DATE_CONTREPASSATION_INVALIDE' using errcode = '22023';
  end if;
  if public.date_comptable_figee(o.etablissement_id, p_date) then
    raise exception 'PERIODE_CLOTUREE' using errcode = '55000';
  end if;

  insert into public.pieces_comptables
    (etablissement_id, exercice_id, journal_id, date_piece, libelle, piece_justificative, origine,
     piece_annulee_id, cree_par, source_type, source_id)
  values (o.etablissement_id, o.exercice_id, o.journal_id, p_date,
          left('Annulation de ' || o.reference || ' — ' || trim(p_motif), 300),
          o.reference, 'contrepassation', o.id, p_auteur, o.source_type, o.source_id)
  returning id into v_id;

  insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, libelle, debit, credit, ordre)
  select v_id, l.etablissement_id, l.compte_id, l.libelle, -l.debit, -l.credit, l.ordre
    from public.lignes_pieces_comptables l where l.piece_id = o.id;

  perform public.numeroter_et_valider_piece(v_id, p_auteur);
  update public.pieces_comptables set annulee_par_piece_id = v_id where id = o.id;
  return v_id;
end;
$$;

-- La RPC garde ses contrôles de droits ; une pièce automatique ne s'annule
-- que par l'annulation de son encaissement (cohérence scolarité ↔ compta).
create or replace function public.contrepasser_piece(
  p_piece_id uuid,
  p_motif text,
  p_date date default current_date
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  o public.pieces_comptables;
begin
  select * into o from public.pieces_comptables where id = p_piece_id;
  if o.id is null then
    raise exception 'PIECE_INTROUVABLE' using errcode = '22023';
  end if;
  if not coalesce(public.est_comptable_ecriture(o.etablissement_id), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if o.origine = 'automatique' then
    raise exception 'PIECE_AUTOMATIQUE' using errcode = '55000';
  end if;
  return public.contrepasser_piece_interne(p_piece_id, p_motif, p_date, auth.uid());
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Comptabilisation d'un encaissement (idempotente)
-- ---------------------------------------------------------------------------
create or replace function public.comptabiliser_encaissement(p_encaissement_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  e public.encaissements_scolarite;
  x public.exercices_comptables;
  v_piece public.pieces_comptables;
  v_tresorerie uuid;
  v_produit uuid;
  v_id uuid;
  v_journal uuid;
  v_libelle text;
  v_date date;
begin
  select * into e from public.encaissements_scolarite where id = p_encaissement_id;
  if e.id is null then
    return 'introuvable';
  end if;

  select * into v_piece from public.pieces_comptables
   where source_type = 'encaissement_scolarite' and source_id = e.id and origine = 'automatique';

  -- Annulation : contre-passer la pièce, s'il y en a une.
  if e.statut = 'annule' then
    if v_piece.id is null or v_piece.annulee_par_piece_id is not null then
      return 'rien_a_faire';
    end if;
    v_date := greatest(coalesce(e.annule_le::date, current_date), v_piece.date_piece);
    perform public.contrepasser_piece_interne(
      v_piece.id, coalesce(nullif(trim(e.motif_annulation), ''), 'Annulation de l''encaissement'), v_date, e.annule_par);
    return 'contrepassee';
  end if;

  if v_piece.id is not null then
    return 'deja_comptabilise';
  end if;

  v_tresorerie := public.compte_comptabilisation(e.etablissement_id, 'tresorerie:' || e.moyen_paiement::text);
  v_produit := public.compte_comptabilisation(e.etablissement_id, 'produit:' || e.type_frais::text);
  if v_tresorerie is null or v_produit is null then
    -- Simplifié sans règles : pas de comptabilisation automatique (non une erreur).
    if public.plan_du_referentiel(public.referentiel_comptable_de(e.etablissement_id)) is null
       and not exists (select 1 from public.regles_comptabilisation where etablissement_id = e.etablissement_id) then
      return 'non_applicable';
    end if;
    raise exception 'COMPTE_AUTO_INTROUVABLE' using errcode = '55000';
  end if;

  x := public.exercice_ouvert_pour(e.etablissement_id, e.date_paiement);
  if x.id is null then
    raise exception 'AUCUN_EXERCICE_OUVERT' using errcode = '55000';
  end if;
  if public.date_comptable_figee(e.etablissement_id, e.date_paiement) then
    raise exception 'PERIODE_CLOTUREE' using errcode = '55000';
  end if;

  v_journal := public.journal_automatique(e.etablissement_id, e.moyen_paiement::text);
  v_libelle := 'Encaissement ' || case e.type_frais::text
      when 'scolarite' then 'scolarité' when 'inscription' then 'inscription'
      when 'cantine' then 'cantine' when 'transport' then 'transport' else 'frais divers' end
    || coalesce(' — ' || (select nullif(trim(coalesce(f.nom, '') || ' ' || coalesce(f.prenom, '')), '')
                            from public.fiches_eleves f where f.id = e.fiche_eleve_id), '');

  insert into public.pieces_comptables
    (etablissement_id, exercice_id, journal_id, date_piece, libelle, piece_justificative, origine,
     cree_par, source_type, source_id)
  values (e.etablissement_id, x.id, v_journal, e.date_paiement, left(v_libelle, 300),
          left(coalesce(e.reference_paiement, 'ENC-' || upper(left(replace(e.id::text, '-', ''), 8))), 200),
          'automatique', e.saisi_par, 'encaissement_scolarite', e.id)
  returning id into v_id;

  insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, debit, credit, ordre) values
    (v_id, e.etablissement_id, v_tresorerie, e.montant, 0, 0),
    (v_id, e.etablissement_id, v_produit, 0, e.montant, 1);

  perform public.numeroter_et_valider_piece(v_id, null);
  return 'comptabilise';
end;
$$;

-- Déclencheur : jamais bloquant pour l'encaissement.
create or replace function public.encaissements_comptabiliser()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation text := case when new.statut = 'annule' then 'annulation' else 'comptabilisation' end;
begin
  begin
    perform public.comptabiliser_encaissement(new.id);
    update public.incidents_comptabilisation
       set resolu = true, resolu_le = now()
     where source_type = 'encaissement_scolarite' and source_id = new.id
       and operation = v_operation and not resolu;
  exception when others then
    insert into public.incidents_comptabilisation
      (etablissement_id, source_type, source_id, operation, code, detail)
    values (new.etablissement_id, 'encaissement_scolarite', new.id, v_operation,
            left(sqlerrm, 80), sqlstate);
  end;
  return null;
end;
$$;

drop trigger if exists encaissements_comptabiliser on public.encaissements_scolarite;
create trigger encaissements_comptabiliser
  after insert or update of statut on public.encaissements_scolarite
  for each row execute function public.encaissements_comptabiliser();

-- ---------------------------------------------------------------------------
-- 6. RPC : rattrapage, état, règles
-- ---------------------------------------------------------------------------
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
        insert into public.incidents_comptabilisation
          (etablissement_id, source_type, source_id, operation, code, detail)
        values (p_etablissement, 'encaissement_scolarite', r.id,
                case when r.statut = 'annule' then 'annulation' else 'comptabilisation' end,
                left(sqlerrm, 80), sqlstate);
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
    'incidents', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', i.id, 'source_id', i.source_id, 'operation', i.operation, 'code', i.code, 'le', i.created_at)
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
          (7, 'produit:inscription'), (8, 'produit:cantine'), (9, 'produit:transport'), (10, 'produit:autre')
        ) as k(ordre, cle)
        left join public.plans_comptables c on c.id = public.compte_comptabilisation(p_etablissement, k.cle)), '[]'::jsonb)
  );
end;
$$;

create or replace function public.definir_regle_comptabilisation(
  p_etablissement uuid, p_cle text, p_compte_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c public.plans_comptables;
begin
  if not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if p_compte_id is null then
    delete from public.regles_comptabilisation where etablissement_id = p_etablissement and cle = p_cle;
    return;
  end if;
  select * into c from public.plans_comptables where id = p_compte_id;
  if c.id is null or c.etablissement_id <> p_etablissement or c.deleted_at is not null or not c.actif
     or exists (select 1 from public.plans_comptables f where f.parent_id = c.id and f.deleted_at is null and f.actif) then
    raise exception 'COMPTE_NON_IMPUTABLE' using errcode = '22023';
  end if;
  insert into public.regles_comptabilisation (etablissement_id, cle, compte_id, modifie_par)
  values (p_etablissement, p_cle, p_compte_id, auth.uid())
  on conflict (etablissement_id, cle) do update
    set compte_id = excluded.compte_id, modifie_par = excluded.modifie_par, modifie_le = now();
exception when check_violation then
  raise exception 'REGLE_INCONNUE' using errcode = '22023';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Droits
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.compte_comptabilisation(uuid, text)',
    'public.journal_automatique(uuid, text)',
    'public.contrepasser_piece_interne(uuid, text, date, uuid)',
    'public.comptabiliser_encaissement(uuid)',
    'public.encaissements_comptabiliser()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;

  foreach f in array array[
    'public.contrepasser_piece(uuid, text, date)',
    'public.comptabiliser_en_attente(uuid)',
    'public.etat_comptabilisation_automatique(uuid)',
    'public.definir_regle_comptabilisation(uuid, text, uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;
