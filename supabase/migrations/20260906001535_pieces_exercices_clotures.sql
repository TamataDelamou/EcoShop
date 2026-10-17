-- ============================================================================
-- EcoShop — REG-03, lot C2 : pièces comptables, validation, contre-passation,
-- exercices et clôtures
-- (proposition validée le 2026-10-17 : docs/propositions/REG-03_COMPTABILITE.md)
--
-- Exigences du droit comptable OHADA (Acte uniforme relatif au droit
-- comptable et à l'information financière, 2017) traduites ici :
--   • art. 16-17  : enregistrement opération par opération, chronologique,
--                   appuyé sur une pièce justificative référencée ;
--   • art. 66     : journal numéroté de façon CONTINUE → numéro attribué à
--                   la validation, par journal et par exercice, sans trou
--                   (les brouillards n'ont pas de numéro) ;
--   • art. 22 2°  : irréversibilité — une pièce validée ne se modifie ni ne
--                   se supprime ;
--   • art. 20     : correction « exclusivement par inscription en négatif »
--                   → contre-passation en montants négatifs, liée à la pièce
--                   d'origine ;
--   • art. 22 3°  : clôture informatique périodique (au moins trimestrielle)
--                   → `cloturer_periode` fige toutes les dates antérieures ;
--   • art. 7      : exercice de douze mois coïncidant avec l'année civile
--                   (référentiels OHADA ; le premier exercice peut différer).
--
-- Modèle :
--   • `exercices_comptables`  : exercices contigus, ouverts puis clôturés ;
--   • `pieces_comptables` + `lignes_pieces_comptables` : pièce à N lignes,
--     brouillard → validée ; équilibre débit = crédit contrôlé à la
--     validation ;
--   • les écritures M14 à deux comptes restent lisibles et comptées ; en
--     référentiel OHADA, la saisie se fait obligatoirement par pièces ; dans
--     tous les référentiels, aucune écriture ne peut toucher une période
--     clôturée ;
--   • journal, grand livre et balance lisent désormais les deux sources ; la
--     balance est calculée sur l'exercice de la date demandée (à-nouveaux
--     compris).
--
-- Écritures : RPC uniquement (aucun droit d'écriture directe pour les
-- clients sur les nouvelles tables).
--
-- Hors périmètre : changement de plan de comptes avec un historique (lot
-- ultérieur), écritures automatiques (C3), états financiers (C4).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Exercices
-- ---------------------------------------------------------------------------
create table if not exists public.exercices_comptables (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  libelle text not null,
  date_debut date not null,
  date_fin date not null,
  statut text not null default 'ouvert' check (statut in ('ouvert', 'cloture')),
  cloture_jusqu_au date,
  resultat numeric(18, 2),
  cloture_le timestamptz,
  cloture_par uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exercices_dates check (date_fin > date_debut),
  constraint exercices_cloture_periode check (cloture_jusqu_au is null or cloture_jusqu_au between date_debut and date_fin),
  constraint exercices_debut_unique unique (etablissement_id, date_debut)
);

drop trigger if exists exercices_set_updated_at on public.exercices_comptables;
create trigger exercices_set_updated_at
  before update on public.exercices_comptables
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Pièces et lignes
-- ---------------------------------------------------------------------------
create table if not exists public.pieces_comptables (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  exercice_id uuid not null references public.exercices_comptables (id) on delete restrict,
  journal_id uuid not null references public.journaux (id) on delete restrict,
  date_piece date not null,
  libelle text not null check (char_length(trim(libelle)) between 1 and 300),
  piece_justificative text check (piece_justificative is null or char_length(piece_justificative) <= 200),
  statut text not null default 'brouillard' check (statut in ('brouillard', 'validee')),
  numero integer,
  reference text,
  origine text not null default 'saisie'
    check (origine in ('saisie', 'automatique', 'contrepassation', 'a_nouveaux')),
  piece_annulee_id uuid references public.pieces_comptables (id),
  annulee_par_piece_id uuid references public.pieces_comptables (id),
  cree_par uuid references public.profiles (id),
  valide_par uuid references public.profiles (id),
  validee_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pieces_numero_si_validee check ((statut = 'validee') = (numero is not null)),
  constraint pieces_numero_unique unique (journal_id, exercice_id, numero)
);

create index if not exists idx_pieces_etab_date on public.pieces_comptables (etablissement_id, date_piece);
create index if not exists idx_pieces_exercice_statut on public.pieces_comptables (exercice_id, statut);

drop trigger if exists pieces_set_updated_at on public.pieces_comptables;
create trigger pieces_set_updated_at
  before update on public.pieces_comptables
  for each row execute function public.set_updated_at();

create table if not exists public.lignes_pieces_comptables (
  id uuid primary key default gen_random_uuid(),
  piece_id uuid not null references public.pieces_comptables (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  compte_id uuid not null references public.plans_comptables (id) on delete restrict,
  libelle text check (libelle is null or char_length(libelle) <= 300),
  debit numeric(18, 2) not null default 0,
  credit numeric(18, 2) not null default 0,
  ordre smallint not null default 0,
  constraint lignes_un_seul_sens check ((debit <> 0) <> (credit <> 0))
);

create index if not exists idx_lignes_piece on public.lignes_pieces_comptables (piece_id, ordre);
create index if not exists idx_lignes_compte on public.lignes_pieces_comptables (compte_id);

create table if not exists public.compteurs_pieces (
  journal_id uuid not null references public.journaux (id) on delete cascade,
  exercice_id uuid not null references public.exercices_comptables (id) on delete cascade,
  dernier integer not null default 0,
  primary key (journal_id, exercice_id)
);

-- RLS : lecture pour les comptables, aucune écriture directe.
alter table public.exercices_comptables enable row level security;
alter table public.pieces_comptables enable row level security;
alter table public.lignes_pieces_comptables enable row level security;
alter table public.compteurs_pieces enable row level security;

drop policy if exists exercices_select on public.exercices_comptables;
create policy exercices_select on public.exercices_comptables
  for select using (public.est_comptable(etablissement_id));
drop policy if exists pieces_select on public.pieces_comptables;
create policy pieces_select on public.pieces_comptables
  for select using (public.est_comptable(etablissement_id));
drop policy if exists lignes_pieces_select on public.lignes_pieces_comptables;
create policy lignes_pieces_select on public.lignes_pieces_comptables
  for select using (public.est_comptable(etablissement_id));

revoke insert, update, delete on public.exercices_comptables from public, anon, authenticated;
revoke insert, update, delete on public.pieces_comptables from public, anon, authenticated;
revoke insert, update, delete on public.lignes_pieces_comptables from public, anon, authenticated;
revoke all on public.compteurs_pieces from public, anon, authenticated;

-- Défense en profondeur : même par une fonction, une pièce validée et ses
-- lignes sont immuables (seul le lien vers sa contre-passation peut être
-- posé, une fois).
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
    if old.annulee_par_piece_id is null and new.annulee_par_piece_id is not null
       and (to_jsonb(new) - 'annulee_par_piece_id' - 'updated_at') = (to_jsonb(old) - 'annulee_par_piece_id' - 'updated_at') then
      return new;
    end if;
    raise exception 'PIECE_VALIDEE_IMMUABLE' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists pieces_validees_immuables on public.pieces_comptables;
create trigger pieces_validees_immuables
  before update or delete on public.pieces_comptables
  for each row execute function public.pieces_validees_immuables();

create or replace function public.lignes_pieces_validees_immuables()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_statut text;
begin
  select statut into v_statut from public.pieces_comptables
   where id = coalesce(new.piece_id, old.piece_id);
  if v_statut = 'validee' then
    raise exception 'PIECE_VALIDEE_IMMUABLE' using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists lignes_pieces_validees_immuables on public.lignes_pieces_comptables;
create trigger lignes_pieces_validees_immuables
  before insert or update or delete on public.lignes_pieces_comptables
  for each row execute function public.lignes_pieces_validees_immuables();

-- ---------------------------------------------------------------------------
-- 3. Aides
-- ---------------------------------------------------------------------------
create or replace function public.a_des_ecritures(p_etablissement uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.ecritures_comptables
                  where etablissement_id = p_etablissement and deleted_at is null)
      or exists (select 1 from public.pieces_comptables where etablissement_id = p_etablissement);
$$;

-- Date figée : dans un exercice clôturé, ou couverte par une clôture de période.
create or replace function public.date_comptable_figee(p_etablissement uuid, p_date date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.exercices_comptables x
     where x.etablissement_id = p_etablissement
       and p_date between x.date_debut and x.date_fin
       and (x.statut = 'cloture' or (x.cloture_jusqu_au is not null and p_date <= x.cloture_jusqu_au))
  );
$$;

create or replace function public.exercice_ouvert_pour(p_etablissement uuid, p_date date)
returns public.exercices_comptables
language sql
stable
security definer
set search_path = public
as $$
  select x.* from public.exercices_comptables x
   where x.etablissement_id = p_etablissement
     and x.statut = 'ouvert'
     and p_date between x.date_debut and x.date_fin
   limit 1;
$$;

create or replace function public.journal_a_nouveaux(p_etablissement uuid)
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
  values (p_etablissement, 'AN', 'À-nouveaux', 'operations')
  on conflict (etablissement_id, code) do update set deleted_at = null
  returning id into v_id;
  return v_id;
end;
$$;

-- Numérotation continue à la validation (art. 66).
create or replace function public.numeroter_et_valider_piece(p_piece_id uuid, p_valideur uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  p public.pieces_comptables;
  v_num integer;
  v_ref text;
  v_code text;
  v_annee text;
begin
  select * into p from public.pieces_comptables where id = p_piece_id for update;

  insert into public.compteurs_pieces (journal_id, exercice_id, dernier)
  values (p.journal_id, p.exercice_id, 1)
  on conflict (journal_id, exercice_id) do update set dernier = public.compteurs_pieces.dernier + 1
  returning dernier into v_num;

  select code into v_code from public.journaux where id = p.journal_id;
  select to_char(date_fin, 'YYYY') into v_annee from public.exercices_comptables where id = p.exercice_id;
  v_ref := upper(v_code) || '-' || v_annee || '-' || lpad(v_num::text, 6, '0');

  update public.pieces_comptables
     set statut = 'validee', numero = v_num, reference = v_ref,
         valide_par = p_valideur, validee_le = now()
   where id = p_piece_id;
  return v_ref;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Écritures M14 : périodes clôturées et référentiels OHADA
-- ---------------------------------------------------------------------------
create or replace function public.ecritures_regle_pieces()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_etab uuid := coalesce(new.etablissement_id, old.etablissement_id);
begin
  if public.plan_du_referentiel(public.referentiel_comptable_de(v_etab)) is not null then
    raise exception 'SAISIE_PAR_PIECES_OBLIGATOIRE' using errcode = '42501';
  end if;
  if (tg_op <> 'INSERT' and public.date_comptable_figee(v_etab, old.date_ecriture))
     or (tg_op <> 'DELETE' and public.date_comptable_figee(v_etab, new.date_ecriture)) then
    raise exception 'PERIODE_CLOTUREE' using errcode = '55000';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists ecritures_regle_pieces on public.ecritures_comptables;
create trigger ecritures_regle_pieces
  before insert or update or delete on public.ecritures_comptables
  for each row execute function public.ecritures_regle_pieces();

-- ---------------------------------------------------------------------------
-- 5. Exercices : ouverture
-- ---------------------------------------------------------------------------
create or replace function public.ouvrir_exercice(
  p_etablissement uuid,
  p_date_debut date,
  p_date_fin date,
  p_libelle text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_ohada boolean := public.plan_du_referentiel(public.referentiel_comptable_de(p_etablissement)) is not null;
  v_dernier public.exercices_comptables;
  v_id uuid;
begin
  if not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if p_date_debut is null or p_date_fin is null or p_date_fin <= p_date_debut
     or p_date_fin > (p_date_debut + interval '24 months')::date then
    raise exception 'EXERCICE_NON_CONFORME' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('exercices:' || p_etablissement::text));

  if exists (select 1 from public.exercices_comptables
              where etablissement_id = p_etablissement
                and daterange(date_debut, date_fin, '[]') && daterange(p_date_debut, p_date_fin, '[]')) then
    raise exception 'EXERCICE_CHEVAUCHEMENT' using errcode = '23514';
  end if;

  select * into v_dernier from public.exercices_comptables
   where etablissement_id = p_etablissement order by date_fin desc limit 1;

  if v_dernier.id is not null and p_date_debut <> v_dernier.date_fin + 1 then
    raise exception 'EXERCICE_NON_CONTIGU' using errcode = '23514';
  end if;

  -- OHADA (art. 7) : douze mois, année civile ; seul le premier exercice
  -- peut commencer en cours d'année.
  if v_ohada and (
       to_char(p_date_fin, 'MM-DD') <> '12-31'
       or (v_dernier.id is not null and to_char(p_date_debut, 'MM-DD') <> '01-01')
       or (v_dernier.id is not null and p_date_fin <> (p_date_debut + interval '1 year' - interval '1 day')::date)) then
    raise exception 'EXERCICE_NON_CONFORME' using errcode = '22023';
  end if;

  insert into public.exercices_comptables (etablissement_id, libelle, date_debut, date_fin)
  values (p_etablissement,
          coalesce(nullif(trim(p_libelle), ''),
                   case when extract(year from p_date_debut) = extract(year from p_date_fin)
                        then 'Exercice ' || to_char(p_date_fin, 'YYYY')
                        else 'Exercice ' || to_char(p_date_debut, 'YYYY') || '-' || to_char(p_date_fin, 'YYYY') end),
          p_date_debut, p_date_fin)
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Pièces : brouillard, validation, suppression, contre-passation
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_piece(
  p_etablissement uuid,
  p_journal uuid,
  p_date date,
  p_libelle text,
  p_lignes jsonb,
  p_piece_justificative text default null,
  p_piece_id uuid default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ohada boolean := public.plan_du_referentiel(public.referentiel_comptable_de(p_etablissement)) is not null;
  x public.exercices_comptables;
  p public.pieces_comptables;
  v_id uuid;
  l jsonb;
  v_compte public.plans_comptables;
  v_debit numeric;
  v_credit numeric;
  v_ordre smallint := 0;
begin
  if not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if not exists (select 1 from public.journaux where id = p_journal and etablissement_id = p_etablissement and deleted_at is null) then
    raise exception 'JOURNAL_INVALIDE' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_libelle, ''))) = 0 then
    raise exception 'LIBELLE_REQUIS' using errcode = '22023';
  end if;
  if jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 or jsonb_array_length(p_lignes) > 200 then
    raise exception 'LIGNES_INVALIDES' using errcode = '22023';
  end if;

  x := public.exercice_ouvert_pour(p_etablissement, p_date);
  if x.id is null then
    raise exception 'AUCUN_EXERCICE_OUVERT' using errcode = '55000';
  end if;
  if public.date_comptable_figee(p_etablissement, p_date) then
    raise exception 'PERIODE_CLOTUREE' using errcode = '55000';
  end if;

  if p_piece_id is not null then
    select * into p from public.pieces_comptables where id = p_piece_id for update;
    if p.id is null or p.etablissement_id <> p_etablissement then
      raise exception 'PIECE_INTROUVABLE' using errcode = '22023';
    end if;
    if p.statut = 'validee' then
      raise exception 'PIECE_VALIDEE_IMMUABLE' using errcode = '42501';
    end if;
    update public.pieces_comptables
       set exercice_id = x.id, journal_id = p_journal, date_piece = p_date, libelle = trim(p_libelle),
           piece_justificative = nullif(trim(p_piece_justificative), '')
     where id = p_piece_id;
    delete from public.lignes_pieces_comptables where piece_id = p_piece_id;
    v_id := p_piece_id;
  else
    insert into public.pieces_comptables
      (etablissement_id, exercice_id, journal_id, date_piece, libelle, piece_justificative, cree_par)
    values (p_etablissement, x.id, p_journal, p_date, trim(p_libelle), nullif(trim(p_piece_justificative), ''), v_uid)
    returning id into v_id;
  end if;

  for l in select * from jsonb_array_elements(p_lignes) loop
    v_debit := coalesce((l->>'debit')::numeric, 0);
    v_credit := coalesce((l->>'credit')::numeric, 0);
    if v_debit < 0 or v_credit < 0 or ((v_debit > 0) = (v_credit > 0)) then
      raise exception 'LIGNE_INVALIDE' using errcode = '22023';
    end if;

    select * into v_compte from public.plans_comptables where id = (l->>'compte_id')::uuid;
    if v_compte.id is null or v_compte.etablissement_id <> p_etablissement
       or v_compte.deleted_at is not null or not v_compte.actif then
      raise exception 'COMPTE_INVALIDE' using errcode = '22023';
    end if;
    -- OHADA : imputation sur un compte de détail uniquement (sans sous-compte).
    if v_ohada and exists (select 1 from public.plans_comptables c
                            where c.parent_id = v_compte.id and c.deleted_at is null and c.actif) then
      raise exception 'COMPTE_NON_IMPUTABLE' using errcode = '22023';
    end if;

    insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, libelle, debit, credit, ordre)
    values (v_id, p_etablissement, v_compte.id, nullif(trim(l->>'libelle'), ''), v_debit, v_credit, v_ordre);
    v_ordre := v_ordre + 1;
  end loop;

  return v_id;
end;
$$;

create or replace function public.valider_piece(p_piece_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  p public.pieces_comptables;
  v_nb integer;
  v_debit numeric;
  v_credit numeric;
begin
  select * into p from public.pieces_comptables where id = p_piece_id for update;
  if p.id is null then
    raise exception 'PIECE_INTROUVABLE' using errcode = '22023';
  end if;
  if not coalesce(public.est_comptable_ecriture(p.etablissement_id), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if p.statut = 'validee' then
    raise exception 'PIECE_VALIDEE_IMMUABLE' using errcode = '42501';
  end if;
  if not exists (select 1 from public.exercices_comptables where id = p.exercice_id and statut = 'ouvert')
     or public.date_comptable_figee(p.etablissement_id, p.date_piece) then
    raise exception 'PERIODE_CLOTUREE' using errcode = '55000';
  end if;

  select count(*), coalesce(sum(debit), 0), coalesce(sum(credit), 0)
    into v_nb, v_debit, v_credit
    from public.lignes_pieces_comptables where piece_id = p_piece_id;
  if v_nb < 2 or v_debit <> v_credit or v_debit = 0 then
    raise exception 'PIECE_DESEQUILIBREE' using errcode = '23514';
  end if;

  return public.numeroter_et_valider_piece(p_piece_id, auth.uid());
end;
$$;

create or replace function public.supprimer_brouillard(p_piece_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  p public.pieces_comptables;
begin
  select * into p from public.pieces_comptables where id = p_piece_id for update;
  if p.id is null then
    raise exception 'PIECE_INTROUVABLE' using errcode = '22023';
  end if;
  if not coalesce(public.est_comptable_ecriture(p.etablissement_id), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if p.statut = 'validee' then
    raise exception 'PIECE_VALIDEE_IMMUABLE' using errcode = '42501';
  end if;
  delete from public.pieces_comptables where id = p_piece_id;
end;
$$;

-- Art. 20 : correction par inscription en négatif.
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
  x public.exercices_comptables;
  v_id uuid;
begin
  select * into o from public.pieces_comptables where id = p_piece_id for update;
  if o.id is null then
    raise exception 'PIECE_INTROUVABLE' using errcode = '22023';
  end if;
  if not coalesce(public.est_comptable_ecriture(o.etablissement_id), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
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
  -- Une erreur d'un exercice clôturé se corrige par le report à nouveau (art. 20).
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
    (etablissement_id, exercice_id, journal_id, date_piece, libelle, piece_justificative, origine, piece_annulee_id, cree_par)
  values (o.etablissement_id, o.exercice_id, o.journal_id, p_date,
          left('Annulation de ' || o.reference || ' — ' || trim(p_motif), 300),
          o.reference, 'contrepassation', o.id, auth.uid())
  returning id into v_id;

  insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, libelle, debit, credit, ordre)
  select v_id, l.etablissement_id, l.compte_id, l.libelle, -l.debit, -l.credit, l.ordre
    from public.lignes_pieces_comptables l where l.piece_id = o.id;

  perform public.numeroter_et_valider_piece(v_id, auth.uid());
  update public.pieces_comptables set annulee_par_piece_id = v_id where id = o.id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Clôtures
-- ---------------------------------------------------------------------------
-- Clôture de période (art. 22 3°) : fige toutes les dates jusqu'au jour donné.
create or replace function public.cloturer_periode(p_etablissement uuid, p_jusqu_au date)
returns date
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  x public.exercices_comptables;
begin
  if not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  x := public.exercice_ouvert_pour(p_etablissement, p_jusqu_au);
  if x.id is null then
    raise exception 'AUCUN_EXERCICE_OUVERT' using errcode = '55000';
  end if;
  if x.cloture_jusqu_au is not null and p_jusqu_au <= x.cloture_jusqu_au then
    raise exception 'PERIODE_DEJA_CLOTUREE' using errcode = '55000';
  end if;
  if exists (select 1 from public.pieces_comptables
              where exercice_id = x.id and statut = 'brouillard' and date_piece <= p_jusqu_au) then
    raise exception 'BROUILLARDS_EN_ATTENTE' using errcode = '55000';
  end if;
  update public.exercices_comptables set cloture_jusqu_au = p_jusqu_au where id = x.id;
  return p_jusqu_au;
end;
$$;

-- Soldes des comptes sur un intervalle (écritures M14 + pièces validées).
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
  select e.date_ecriture, e.compte_debit_id, e.montant, 0::numeric, e.libelle, null::text,
         e.piece_justificative, e.journal_id, e.created_at, 0
    from public.ecritures_comptables e
   where e.etablissement_id = p_etablissement and e.deleted_at is null
     and e.date_ecriture between coalesce(p_debut, '-infinity'::date) and coalesce(p_fin, 'infinity'::date)
  union all
  select e.date_ecriture, e.compte_credit_id, 0::numeric, e.montant, e.libelle, null::text,
         e.piece_justificative, e.journal_id, e.created_at, 1
    from public.ecritures_comptables e
   where e.etablissement_id = p_etablissement and e.deleted_at is null
     and e.date_ecriture between coalesce(p_debut, '-infinity'::date) and coalesce(p_fin, 'infinity'::date)
  union all
  select p.date_piece, l.compte_id, l.debit, l.credit, coalesce(l.libelle, p.libelle), p.reference,
         coalesce(p.piece_justificative, p.reference), p.journal_id, p.validee_le, l.ordre::integer
    from public.pieces_comptables p
    join public.lignes_pieces_comptables l on l.piece_id = p.id
   where p.etablissement_id = p_etablissement and p.statut = 'validee'
     and p.date_piece between coalesce(p_debut, '-infinity'::date) and coalesce(p_fin, 'infinity'::date);
$$;

-- Clôture d'exercice : résultat, à-nouveaux dans l'exercice suivant.
create or replace function public.cloturer_exercice(p_exercice_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  x public.exercices_comptables;
  v_suivant public.exercices_comptables;
  v_ohada boolean;
  v_resultat numeric;
  v_piece uuid;
  v_journal uuid;
  v_compte_resultat uuid;
  v_ordre smallint := 0;
  r record;
begin
  select * into x from public.exercices_comptables where id = p_exercice_id for update;
  if x.id is null then
    raise exception 'EXERCICE_INTROUVABLE' using errcode = '22023';
  end if;
  if not (coalesce(public.est_direction(x.etablissement_id), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if x.statut = 'cloture' then
    raise exception 'EXERCICE_DEJA_CLOTURE' using errcode = '55000';
  end if;
  if exists (select 1 from public.exercices_comptables
              where etablissement_id = x.etablissement_id and date_fin < x.date_debut and statut = 'ouvert') then
    raise exception 'EXERCICE_PRECEDENT_OUVERT' using errcode = '55000';
  end if;
  if exists (select 1 from public.pieces_comptables where exercice_id = x.id and statut = 'brouillard') then
    raise exception 'BROUILLARDS_EN_ATTENTE' using errcode = '55000';
  end if;

  v_ohada := public.plan_du_referentiel(public.referentiel_comptable_de(x.etablissement_id)) is not null;

  -- Exercice suivant : existant, sinon ouvert automatiquement (douze mois).
  select * into v_suivant from public.exercices_comptables
   where etablissement_id = x.etablissement_id and date_debut = x.date_fin + 1;
  if v_suivant.id is null then
    insert into public.exercices_comptables (etablissement_id, libelle, date_debut, date_fin)
    values (x.etablissement_id,
            'Exercice ' || to_char(x.date_fin + 1, 'YYYY'),
            x.date_fin + 1, (x.date_fin + interval '1 year')::date)
    returning * into v_suivant;
  end if;
  if exists (select 1 from public.pieces_comptables
              where exercice_id = v_suivant.id and origine = 'a_nouveaux') then
    raise exception 'A_NOUVEAUX_DEJA_PASSES' using errcode = '55000';
  end if;

  -- Résultat = produits − charges de l'exercice.
  select coalesce(sum(m.credit - m.debit), 0) into v_resultat
    from public.mouvements_comptables(x.etablissement_id, x.date_debut, x.date_fin) m
    join public.plans_comptables c on c.id = m.compte_id
   where c.type in ('charge', 'produit');

  -- Compte de résultat : 131 (bénéfice / excédent) ou 139 (perte / déficit)
  -- en OHADA ; en simplifié, compte « 13 Résultat de l'exercice » créé au besoin.
  if v_ohada then
    select id into v_compte_resultat from public.plans_comptables
     where etablissement_id = x.etablissement_id and deleted_at is null
       and code = case when v_resultat >= 0 then '131' else '139' end;
  else
    insert into public.plans_comptables (etablissement_id, code, intitule, type)
    values (x.etablissement_id, '13', 'Résultat de l''exercice', 'capitaux')
    on conflict (etablissement_id, code) do update set deleted_at = null, actif = true
    returning id into v_compte_resultat;
  end if;
  if v_compte_resultat is null then
    raise exception 'COMPTE_RESULTAT_INTROUVABLE' using errcode = '55000';
  end if;

  v_journal := public.journal_a_nouveaux(x.etablissement_id);

  insert into public.pieces_comptables
    (etablissement_id, exercice_id, journal_id, date_piece, libelle, origine, cree_par)
  values (x.etablissement_id, v_suivant.id, v_journal, v_suivant.date_debut,
          'À-nouveaux — ' || x.libelle, 'a_nouveaux', auth.uid())
  returning id into v_piece;

  -- Comptes de bilan : leur solde est reporté.
  for r in
    select m.compte_id, sum(m.debit - m.credit) as solde
      from public.mouvements_comptables(x.etablissement_id, x.date_debut, x.date_fin) m
      join public.plans_comptables c on c.id = m.compte_id
     where c.type not in ('charge', 'produit')
     group by m.compte_id
    having sum(m.debit - m.credit) <> 0
     order by min(c.code)
  loop
    insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, libelle, debit, credit, ordre)
    values (v_piece, x.etablissement_id, r.compte_id, 'Report à nouveau',
            greatest(r.solde, 0), greatest(-r.solde, 0), v_ordre);
    v_ordre := v_ordre + 1;
  end loop;

  if v_resultat <> 0 then
    insert into public.lignes_pieces_comptables (piece_id, etablissement_id, compte_id, libelle, debit, credit, ordre)
    values (v_piece, x.etablissement_id, v_compte_resultat,
            'Résultat de l''exercice ' || x.libelle,
            greatest(-v_resultat, 0), greatest(v_resultat, 0), v_ordre);
    v_ordre := v_ordre + 1;
  end if;

  if v_ordre = 0 then
    delete from public.pieces_comptables where id = v_piece;
    v_piece := null;
  else
    perform public.numeroter_et_valider_piece(v_piece, auth.uid());
  end if;

  update public.exercices_comptables
     set statut = 'cloture', cloture_jusqu_au = date_fin, resultat = v_resultat,
         cloture_le = now(), cloture_par = auth.uid()
   where id = x.id;

  return jsonb_build_object(
    'resultat', v_resultat,
    'piece_a_nouveaux_id', v_piece,
    'exercice_suivant_id', v_suivant.id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Documents : journal, grand livre, balance (deux sources)
-- ---------------------------------------------------------------------------
create or replace function public.journal_comptable(
  p_etablissement uuid, p_journal uuid, p_debut date, p_fin date)
returns table (
  date_ecriture date,
  libelle text,
  compte_debit text,
  compte_credit text,
  montant numeric,
  piece_justificative text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  select t.date_ecriture, t.libelle, t.compte_debit, t.compte_credit, t.montant, t.piece_justificative
  from (
    select e.date_ecriture, e.libelle, d.code as compte_debit, c.code as compte_credit, e.montant,
           e.piece_justificative, e.created_at as ordre, 0 as ordre_ligne
      from public.ecritures_comptables e
      join public.plans_comptables d on d.id = e.compte_debit_id
      join public.plans_comptables c on c.id = e.compte_credit_id
     where e.etablissement_id = p_etablissement and e.journal_id = p_journal and e.deleted_at is null
       and e.date_ecriture between p_debut and p_fin
    union all
    select p.date_piece, '[' || p.reference || '] ' || coalesce(l.libelle, p.libelle),
           case when l.debit <> 0 then pc.code else '' end,
           case when l.credit <> 0 then pc.code else '' end,
           l.debit + l.credit,
           coalesce(p.piece_justificative, p.reference), p.validee_le, l.ordre::integer
      from public.pieces_comptables p
      join public.lignes_pieces_comptables l on l.piece_id = p.id
      join public.plans_comptables pc on pc.id = l.compte_id
     where p.etablissement_id = p_etablissement and p.journal_id = p_journal and p.statut = 'validee'
       and p.date_piece between p_debut and p_fin
  ) t
  order by t.date_ecriture, t.ordre, t.ordre_ligne;
end;
$$;

create or replace function public.grand_livre(
  p_etablissement uuid, p_compte uuid, p_debut date, p_fin date)
returns table (
  date_ecriture date,
  libelle text,
  piece_justificative text,
  sens text,
  montant numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  select m.date_mouvement,
         case when m.reference is null then m.libelle else '[' || m.reference || '] ' || m.libelle end,
         m.piece_justificative,
         case when m.debit <> 0 then 'debit' else 'credit' end,
         m.debit + m.credit
    from public.mouvements_comptables(p_etablissement, p_debut, p_fin) m
   where m.compte_id = p_compte
   order by m.date_mouvement, m.ordre, m.ordre_ligne;
end;
$$;

create or replace function public.balance_comptable(p_etablissement uuid, p_date date)
returns table (
  compte_id uuid,
  code text,
  intitule text,
  total_debit numeric,
  total_credit numeric,
  solde_debit numeric,
  solde_credit numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_debut date;
begin
  if auth.uid() is not null
     and not coalesce(public.est_comptable(p_etablissement), false)
     and not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  -- Balance de l'exercice de la date (à-nouveaux compris) ; sans exercice,
  -- cumul depuis l'origine (comportement M14).
  select x.date_debut into v_debut from public.exercices_comptables x
   where x.etablissement_id = p_etablissement and p_date between x.date_debut and x.date_fin;

  return query
  with mouvements as (
    select m.compte_id, m.debit, m.credit from public.mouvements_comptables(p_etablissement, v_debut, p_date) m
  )
  select pc.id, pc.code, pc.intitule,
         coalesce(sum(m.debit), 0)  as total_debit,
         coalesce(sum(m.credit), 0) as total_credit,
         greatest(coalesce(sum(m.debit),0) - coalesce(sum(m.credit),0), 0) as solde_debit,
         greatest(coalesce(sum(m.credit),0) - coalesce(sum(m.debit),0), 0) as solde_credit
  from public.plans_comptables pc
  left join mouvements m on m.compte_id = pc.id
  where pc.etablissement_id = p_etablissement and pc.deleted_at is null
  group by pc.id, pc.code, pc.intitule
  order by pc.code;
end;
$$;

-- Détail d'une pièce (écran) : en-tête + lignes, sous les droits de lecture.
create or replace function public.piece_comptable_detail(p_piece_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  p public.pieces_comptables;
begin
  select * into p from public.pieces_comptables where id = p_piece_id;
  if p.id is null then
    raise exception 'PIECE_INTROUVABLE' using errcode = '22023';
  end if;
  if not coalesce(public.est_comptable(p.etablissement_id), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;
  return to_jsonb(p) || jsonb_build_object(
    'journal_code', (select code from public.journaux where id = p.journal_id),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', l.id, 'compte_id', l.compte_id, 'compte_code', c.code, 'compte_intitule', c.intitule,
               'libelle', l.libelle, 'debit', l.debit, 'credit', l.credit, 'ordre', l.ordre)
             order by l.ordre)
        from public.lignes_pieces_comptables l join public.plans_comptables c on c.id = l.compte_id
       where l.piece_id = p.id), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Choix du référentiel : les pièces comptent aussi comme écritures
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
     and public.a_des_ecritures(p_etablissement) then
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

-- ---------------------------------------------------------------------------
-- 10. Droits
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  -- Fonctions internes : jamais appelables par un client.
  foreach f in array array[
    'public.a_des_ecritures(uuid)',
    'public.date_comptable_figee(uuid, date)',
    'public.exercice_ouvert_pour(uuid, date)',
    'public.journal_a_nouveaux(uuid)',
    'public.numeroter_et_valider_piece(uuid, uuid)',
    'public.mouvements_comptables(uuid, date, date)',
    'public.pieces_validees_immuables()',
    'public.lignes_pieces_validees_immuables()',
    'public.ecritures_regle_pieces()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;

  -- RPC : comptables authentifiés (droits vérifiés dans chaque fonction).
  foreach f in array array[
    'public.ouvrir_exercice(uuid, date, date, text)',
    'public.enregistrer_piece(uuid, uuid, date, text, jsonb, text, uuid)',
    'public.valider_piece(uuid)',
    'public.supprimer_brouillard(uuid)',
    'public.contrepasser_piece(uuid, text, date)',
    'public.cloturer_periode(uuid, date)',
    'public.cloturer_exercice(uuid)',
    'public.piece_comptable_detail(uuid)',
    'public.choisir_referentiel_comptable(uuid, text, text, numeric)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;
