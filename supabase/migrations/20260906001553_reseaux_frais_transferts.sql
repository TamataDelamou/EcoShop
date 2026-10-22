-- ============================================================================
-- EcoShop — Réseaux : politique de frais et transferts d'élèves (REG-17)
--
-- Les réseaux ne fonctionnent pas tous pareil. Certains laissent chaque
-- école fixer ses frais selon sa localité ; d'autres appliquent une grille
-- commune. La Direction Générale choisit :
--
--   * politique de frais : « autonome » (chaque école, rien d'imposé),
--     « indicative » (grille de référence publiée, chaque école l'adopte ou
--     non), « commune » (grille appliquée à toutes les écoles membres, qui ne
--     peuvent plus modifier leurs tarifs elles-mêmes) ;
--   * conditions de transfert d'un élève entre deux écoles du réseau :
--     transferts ouverts ou non, frais soldés exigés au départ, validation
--     par la Direction Générale, frais d'inscription offerts à l'arrivée,
--     dossier (assiduité, famille) transmis à l'école d'accueil.
--
-- Transfert : l'école de départ le demande, la Direction Générale le valide
-- si le réseau l'exige, l'école d'accueil l'accepte en choisissant la
-- classe. À l'acceptation, tout est fait en une fois : fiche et inscription
-- créées à l'arrivée, parents rattachés, élève retiré au départ, familles
-- prévenues. Clé fournie par l'appareil : une demande saisie sans réseau et
-- renvoyée deux fois n'est enregistrée qu'une fois.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Règles du réseau
-- ---------------------------------------------------------------------------
alter table public.reseaux
  add column if not exists politique_frais text not null default 'autonome'
    check (politique_frais in ('autonome', 'indicative', 'commune')),
  add column if not exists transferts_ouverts boolean not null default true,
  add column if not exists transfert_quitus_requis boolean not null default true,
  add column if not exists transfert_validation_reseau boolean not null default false,
  add column if not exists transfert_inscription_offerte boolean not null default true,
  add column if not exists transfert_dossier_partage boolean not null default true,
  add column if not exists regles_modifiees_par uuid references public.profiles (id),
  add column if not exists regles_modifiees_le timestamptz;

-- Grille du réseau : une ligne par niveau (niveau null = tarif par défaut).
create table if not exists public.grilles_frais_reseau (
  id uuid primary key default gen_random_uuid(),
  reseau_id uuid not null references public.reseaux (id) on delete cascade,
  niveau_id uuid references public.niveaux_educatifs (id) on delete cascade,
  montant_annuel numeric(12, 2) not null check (montant_annuel >= 0),
  frais_inscription numeric(12, 2) not null default 0 check (frais_inscription >= 0),
  modifie_par uuid references public.profiles (id),
  modifie_le timestamptz not null default now()
);
create unique index if not exists idx_grille_reseau_niveau
  on public.grilles_frais_reseau (reseau_id, coalesce(niveau_id, '00000000-0000-0000-0000-000000000000'));

-- Tarif d'une école posé par la grille du réseau (traçabilité).
alter table public.frais_scolarite_config
  add column if not exists fixe_par_reseau_id uuid references public.reseaux (id) on delete set null;

alter table public.grilles_frais_reseau enable row level security;
revoke all on public.grilles_frais_reseau from anon, authenticated;

-- Réseau à grille commune dont l'école est membre (null sinon).
create or replace function public.reseau_frais_communs(p_etablissement uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select n.id from public.reseaux_etablissements re
  join public.reseaux n on n.id = re.reseau_id
  where re.etablissement_id = p_etablissement and re.statut in ('membre', 'retrait_demande')
    and n.statut = 'actif' and n.politique_frais = 'commune'
  limit 1;
$$;

-- Verrou : en grille commune, l'école ne modifie plus ses tarifs elle-même.
-- Exécutée avec les droits de l'appelant : dans une fonction du serveur
-- (propriétaire), est_appel_service() est vrai et la grille passe.
create or replace function public.frais_config_verrou_reseau()
returns trigger
language plpgsql set search_path = public
as $$
declare
  v_etab uuid := coalesce(new.etablissement_id, old.etablissement_id);
begin
  if coalesce(current_setting('ecoshop.grille_reseau', true), '') = '1' or public.est_appel_service() then
    return coalesce(new, old);
  end if;
  if public.reseau_frais_communs(v_etab) is not null then
    raise exception 'FRAIS_FIXES_PAR_RESEAU' using errcode = '42501',
      hint = 'Les frais de cette école sont fixés par la grille commune de son réseau.';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists frais_config_verrou_reseau_trg on public.frais_scolarite_config;
create trigger frais_config_verrou_reseau_trg
  before insert or update or delete on public.frais_scolarite_config
  for each row execute function public.frais_config_verrou_reseau();

-- Pose la grille du réseau sur l'année courante d'une école. Interne.
create or replace function public.poser_grille_reseau(p_reseau uuid, p_etablissement uuid)
returns integer
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_annee uuid;
  g record;
  v_n integer := 0;
begin
  select id into v_annee from public.annees_scolaires where etablissement_id = p_etablissement and courante limit 1;
  if v_annee is null then return 0; end if;
  perform set_config('ecoshop.grille_reseau', '1', true);
  for g in select * from public.grilles_frais_reseau where reseau_id = p_reseau loop
    update public.frais_scolarite_config
       set montant_annuel = g.montant_annuel, frais_inscription = g.frais_inscription, fixe_par_reseau_id = p_reseau
     where etablissement_id = p_etablissement and annee_scolaire_id = v_annee
       and niveau_id is not distinct from g.niveau_id and deleted_at is null;
    if not found then
      insert into public.frais_scolarite_config
        (etablissement_id, annee_scolaire_id, niveau_id, montant_annuel, frais_inscription, fixe_par_reseau_id)
      values (p_etablissement, v_annee, g.niveau_id, g.montant_annuel, g.frais_inscription, p_reseau);
    end if;
    v_n := v_n + 1;
  end loop;
  perform set_config('ecoshop.grille_reseau', '', true);
  return v_n;
end;
$$;

-- Applique la grille : à toutes les écoles membres (pilotes du réseau), ou
-- à son école (direction d'une école membre qui adopte la grille).
create or replace function public.appliquer_grille_reseau(p_reseau uuid, p_etablissement uuid default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  e record;
  v_ecoles integer := 0;
  v_lignes integer := 0;
  v_n integer;
begin
  if not exists (select 1 from public.grilles_frais_reseau where reseau_id = p_reseau) then
    raise exception 'GRILLE_VIDE' using errcode = '23514';
  end if;
  if p_etablissement is null then
    if not public.pilote_reseau(p_reseau) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  else
    if not public.pilote_reseau(p_reseau) and not coalesce(public.est_direction(p_etablissement), false) then
      raise exception 'ACCES_REFUSE' using errcode = '42501';
    end if;
  end if;
  for e in select re.etablissement_id from public.reseaux_etablissements re
           where re.reseau_id = p_reseau and re.statut in ('membre', 'retrait_demande')
             and (p_etablissement is null or re.etablissement_id = p_etablissement) loop
    v_n := public.poser_grille_reseau(p_reseau, e.etablissement_id);
    if v_n > 0 then
      v_ecoles := v_ecoles + 1;
      v_lignes := v_lignes + v_n;
    end if;
  end loop;
  if p_etablissement is not null and v_ecoles = 0 then
    raise exception 'ECOLE_SANS_ANNEE_OU_HORS_RESEAU' using errcode = '23514';
  end if;
  return jsonb_build_object('ecoles', v_ecoles, 'lignes', v_lignes);
end;
$$;

-- Une école qui rejoint un réseau à grille commune la reçoit aussitôt.
create or replace function public.reseaux_etablissements_grille_trg()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.statut = 'membre' and old.statut is distinct from 'membre'
     and exists (select 1 from public.reseaux n where n.id = new.reseau_id and n.politique_frais = 'commune')
     and exists (select 1 from public.grilles_frais_reseau g where g.reseau_id = new.reseau_id) then
    perform public.poser_grille_reseau(new.reseau_id, new.etablissement_id);
  end if;
  return new;
end;
$$;

drop trigger if exists reseaux_etablissements_grille on public.reseaux_etablissements;
create trigger reseaux_etablissements_grille
  after update on public.reseaux_etablissements
  for each row execute function public.reseaux_etablissements_grille_trg();

-- Règles du réseau : Direction Générale seulement.
create or replace function public.parametrer_reseau(
  p_reseau uuid,
  p_politique_frais text,
  p_transferts_ouverts boolean,
  p_quitus_requis boolean,
  p_validation_reseau boolean,
  p_inscription_offerte boolean,
  p_dossier_partage boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_avant text;
  v_appliquee jsonb;
begin
  if coalesce(public.role_reseau(p_reseau), '') <> 'direction_generale' then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if p_politique_frais not in ('autonome', 'indicative', 'commune') then
    raise exception 'POLITIQUE_INCONNUE' using errcode = '22023';
  end if;
  if p_politique_frais = 'commune'
     and not exists (select 1 from public.grilles_frais_reseau where reseau_id = p_reseau) then
    raise exception 'GRILLE_VIDE' using errcode = '23514',
      hint = 'Enregistrer la grille du réseau avant de la rendre commune.';
  end if;
  select politique_frais into v_avant from public.reseaux where id = p_reseau for update;
  update public.reseaux
     set politique_frais = p_politique_frais,
         transferts_ouverts = coalesce(p_transferts_ouverts, transferts_ouverts),
         transfert_quitus_requis = coalesce(p_quitus_requis, transfert_quitus_requis),
         transfert_validation_reseau = coalesce(p_validation_reseau, transfert_validation_reseau),
         transfert_inscription_offerte = coalesce(p_inscription_offerte, transfert_inscription_offerte),
         transfert_dossier_partage = coalesce(p_dossier_partage, transfert_dossier_partage),
         regles_modifiees_par = auth.uid(), regles_modifiees_le = now()
   where id = p_reseau;
  if p_politique_frais = 'commune' and v_avant is distinct from 'commune' then
    v_appliquee := public.appliquer_grille_reseau(p_reseau);
  end if;
  return public.regles_reseau(p_reseau) || jsonb_build_object('grille_appliquee', v_appliquee);
end;
$$;

-- Grille du réseau, remplacée en entier. En grille commune, elle est
-- aussitôt reportée dans toutes les écoles membres.
create or replace function public.enregistrer_grille_reseau(p_reseau uuid, p_lignes jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  l jsonb;
  v_niveau uuid;
  v_politique text;
  v_appliquee jsonb;
begin
  if not public.pilote_reseau(p_reseau) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if jsonb_typeof(p_lignes) is distinct from 'array' then raise exception 'GRILLE_INVALIDE' using errcode = '22023'; end if;
  delete from public.grilles_frais_reseau where reseau_id = p_reseau;
  for l in select * from jsonb_array_elements(p_lignes) loop
    v_niveau := nullif(l ->> 'niveau_id', '')::uuid;
    if v_niveau is not null and not exists (select 1 from public.niveaux_educatifs where id = v_niveau) then
      raise exception 'NIVEAU_INCONNU' using errcode = '22023';
    end if;
    if coalesce((l ->> 'montant_annuel')::numeric, -1) < 0 or coalesce((l ->> 'frais_inscription')::numeric, 0) < 0 then
      raise exception 'MONTANT_INVALIDE' using errcode = '22023';
    end if;
    insert into public.grilles_frais_reseau (reseau_id, niveau_id, montant_annuel, frais_inscription, modifie_par)
    values (p_reseau, v_niveau, (l ->> 'montant_annuel')::numeric, coalesce((l ->> 'frais_inscription')::numeric, 0), auth.uid())
    on conflict (reseau_id, coalesce(niveau_id, '00000000-0000-0000-0000-000000000000'))
    do update set montant_annuel = excluded.montant_annuel, frais_inscription = excluded.frais_inscription;
  end loop;
  select politique_frais into v_politique from public.reseaux where id = p_reseau;
  if v_politique = 'commune' then
    if not exists (select 1 from public.grilles_frais_reseau where reseau_id = p_reseau) then
      raise exception 'GRILLE_VIDE' using errcode = '23514';
    end if;
    v_appliquee := public.appliquer_grille_reseau(p_reseau);
  end if;
  return jsonb_build_object('lignes', jsonb_array_length(p_lignes), 'grille_appliquee', v_appliquee);
end;
$$;

-- Règles et grille, lisibles par les responsables et les directions des
-- écoles concernées ; pour une école, tarifs actuels en regard.
create or replace function public.regles_reseau(p_reseau uuid, p_etablissement uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  n public.reseaux;
  v_annee uuid;
begin
  if not public.voit_reseau(p_reseau) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if p_etablissement is not null and not coalesce(public.est_direction(p_etablissement), false)
     and public.role_reseau(p_reseau) is null then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  select * into n from public.reseaux where id = p_reseau;
  if p_etablissement is not null then
    select id into v_annee from public.annees_scolaires where etablissement_id = p_etablissement and courante limit 1;
  end if;
  return jsonb_build_object(
    'reseau_id', n.id,
    'devise_code', n.devise_code,
    'politique_frais', n.politique_frais,
    'transferts_ouverts', n.transferts_ouverts,
    'quitus_requis', n.transfert_quitus_requis,
    'validation_reseau', n.transfert_validation_reseau,
    'inscription_offerte', n.transfert_inscription_offerte,
    'dossier_partage', n.transfert_dossier_partage,
    'modifiees_le', n.regles_modifiees_le,
    'pays_code', n.pays_code,
    -- Niveaux du pays du réseau, pour composer la grille.
    'niveaux', (select coalesce(jsonb_agg(jsonb_build_object('id', nv.id, 'nom', nv.nom, 'ordre', nv.ordre)
                   order by nv.ordre), '[]'::jsonb)
                from public.niveaux_educatifs nv where nv.pays_code = upper(n.pays_code)),
    'grille', (select coalesce(jsonb_agg(jsonb_build_object(
        'niveau_id', g.niveau_id, 'niveau', coalesce(nv.nom, 'Tous niveaux (par défaut)'), 'ordre', coalesce(nv.ordre, 0),
        'montant_annuel', g.montant_annuel, 'frais_inscription', g.frais_inscription,
        'tarif_ecole', case when v_annee is not null then
            (select f.montant_annuel from public.frais_scolarite_config f
              where f.etablissement_id = p_etablissement and f.annee_scolaire_id = v_annee
                and f.niveau_id is not distinct from g.niveau_id and f.deleted_at is null limit 1) end
      ) order by coalesce(nv.ordre, 0)), '[]'::jsonb)
      from public.grilles_frais_reseau g left join public.niveaux_educatifs nv on nv.id = g.niveau_id
      where g.reseau_id = p_reseau));
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Transferts d'élèves entre écoles du réseau
-- ---------------------------------------------------------------------------
alter table public.fiches_eleves
  add column if not exists fiche_origine_id uuid references public.fiches_eleves (id) on delete set null;

create table if not exists public.transferts_reseau (
  id uuid primary key,
  reseau_id uuid not null references public.reseaux (id) on delete cascade,
  fiche_origine_id uuid not null references public.fiches_eleves (id) on delete cascade,
  etablissement_origine_id uuid not null references public.etablissements (id) on delete cascade,
  etablissement_destination_id uuid not null references public.etablissements (id) on delete cascade,
  niveau_id uuid references public.niveaux_educatifs (id) on delete set null,
  statut text not null default 'en_attente_accueil'
    check (statut in ('a_valider_reseau', 'en_attente_accueil', 'transfere', 'refuse', 'annule')),
  motif text not null check (char_length(trim(motif)) between 3 and 500),
  solde_au_depart numeric(12, 2),
  inscription_offerte boolean not null default false,
  dossier jsonb,
  demande_par uuid not null references public.profiles (id),
  demande_le timestamptz not null default now(),
  valide_par uuid references public.profiles (id),
  valide_le timestamptz,
  decide_par uuid references public.profiles (id),
  decide_le timestamptz,
  motif_refus text,
  refuse_par text check (refuse_par in ('reseau', 'accueil')),
  fiche_destination_id uuid references public.fiches_eleves (id) on delete set null,
  inscription_destination_id uuid references public.inscriptions (id) on delete set null,
  constraint transferts_ecoles_differentes check (etablissement_origine_id <> etablissement_destination_id)
);
create index if not exists idx_transferts_origine on public.transferts_reseau (etablissement_origine_id, demande_le desc);
create index if not exists idx_transferts_destination on public.transferts_reseau (etablissement_destination_id, demande_le desc);
create index if not exists idx_transferts_reseau on public.transferts_reseau (reseau_id, demande_le desc);
-- Un seul transfert en cours par élève.
create unique index if not exists idx_transferts_un_en_cours
  on public.transferts_reseau (fiche_origine_id) where statut in ('a_valider_reseau', 'en_attente_accueil');

alter table public.transferts_reseau enable row level security;
revoke all on public.transferts_reseau from anon, authenticated;

-- Réseau actif commun aux deux écoles (membres l'une et l'autre).
create or replace function public.reseau_commun(p_a uuid, p_b uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select n.id from public.reseaux n
  join public.reseaux_etablissements a on a.reseau_id = n.id and a.etablissement_id = p_a and a.statut in ('membre', 'retrait_demande')
  join public.reseaux_etablissements b on b.reseau_id = n.id and b.etablissement_id = p_b and b.statut in ('membre', 'retrait_demande')
  where n.statut = 'actif'
  order by n.cree_le
  limit 1;
$$;

create or replace function public.notifier_transfert(p_transfert uuid, p_destinataires text, p_message text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.transferts_reseau;
  d uuid;
begin
  select * into t from public.transferts_reseau where id = p_transfert;
  if p_destinataires in ('accueil', 'tous') then
    for d in select * from public.directions_etablissement(t.etablissement_destination_id) loop
      perform public.notifier_push(t.etablissement_destination_id, d, 'reseau_transfert', p_message,
        jsonb_build_object('transfert_id', t.id));
    end loop;
  end if;
  if p_destinataires in ('depart', 'tous') then
    for d in select * from public.directions_etablissement(t.etablissement_origine_id) loop
      perform public.notifier_push(t.etablissement_origine_id, d, 'reseau_transfert', p_message,
        jsonb_build_object('transfert_id', t.id));
    end loop;
  end if;
  if p_destinataires = 'reseau' then
    for d in select r.profile_id from public.reseaux_responsables r
             where r.reseau_id = t.reseau_id and r.role in ('direction_generale', 'adjoint') loop
      perform public.notifier_push(t.etablissement_origine_id, d, 'reseau_transfert', p_message,
        jsonb_build_object('transfert_id', t.id));
    end loop;
  end if;
end;
$$;

-- Demande de transfert, par l'école de départ.
create or replace function public.demander_transfert_reseau(
  p_id uuid, p_fiche uuid, p_destination uuid, p_motif text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  f public.fiches_eleves;
  n public.reseaux;
  v_reseau uuid;
  v_insc record;
  v_solde numeric;
  v_existe public.transferts_reseau;
  v_dossier jsonb;
  v_statut text;
  v_dest text;
begin
  select * into v_existe from public.transferts_reseau where id = p_id;
  if found then
    if v_existe.fiche_origine_id <> p_fiche then raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505'; end if;
    return jsonb_build_object('id', p_id, 'statut', v_existe.statut, 'deja_recue', true);
  end if;

  select * into f from public.fiches_eleves where id = p_fiche and deleted_at is null;
  if not found then raise exception 'FICHE_INTROUVABLE' using errcode = 'P0002'; end if;
  if not coalesce(public.gere_inscriptions(f.etablissement_id), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_motif, ''))) < 3 then raise exception 'MOTIF_REQUIS' using errcode = '23514'; end if;

  v_reseau := public.reseau_commun(f.etablissement_id, p_destination);
  if v_reseau is null then raise exception 'ECOLES_HORS_MEME_RESEAU' using errcode = '23514'; end if;
  select * into n from public.reseaux where id = v_reseau;
  if not n.transferts_ouverts then raise exception 'TRANSFERTS_FERMES' using errcode = '23514'; end if;

  select i.id, i.classe_id, c.niveau_id, c.nom as classe, a.libelle as annee, i.annee_scolaire_id
    into v_insc
  from public.inscriptions i
  join public.classes c on c.id = i.classe_id
  join public.annees_scolaires a on a.id = i.annee_scolaire_id
  where i.fiche_eleve_id = p_fiche and i.deleted_at is null and i.statut in ('active', 'redoublante') and a.courante
  limit 1;
  if v_insc.id is null then raise exception 'ELEVE_NON_INSCRIT' using errcode = '23514'; end if;

  if exists (select 1 from public.transferts_reseau
             where fiche_origine_id = p_fiche and statut in ('a_valider_reseau', 'en_attente_accueil')) then
    raise exception 'TRANSFERT_DEJA_EN_COURS' using errcode = '23505';
  end if;

  select s.solde into v_solde from public.solde_scolarite(v_insc.id) s;
  if n.transfert_quitus_requis and coalesce(v_solde, 0) > 0 then
    raise exception 'SOLDE_IMPAYE' using errcode = '23514',
      detail = v_solde::text,
      hint = 'Le réseau exige des frais soldés avant un transfert.';
  end if;

  if n.transfert_dossier_partage then
    v_dossier := jsonb_build_object(
      'annee', v_insc.annee,
      'classe', v_insc.classe,
      'absences', (select count(*) from public.presences p where p.fiche_eleve_id = p_fiche
                     and p.annee_scolaire_id = v_insc.annee_scolaire_id and p.statut = 'absent' and p.deleted_at is null),
      'retards', (select count(*) from public.presences p where p.fiche_eleve_id = p_fiche
                     and p.annee_scolaire_id = v_insc.annee_scolaire_id and p.statut = 'retard' and p.deleted_at is null),
      'redoublant', f.redoublant,
      'nom_pere', f.nom_pere, 'nom_mere', f.nom_mere, 'quartier', f.quartier,
      'personne_urgence_nom', f.personne_urgence_nom, 'personne_urgence_telephone', f.personne_urgence_telephone);
  end if;

  v_statut := case when n.transfert_validation_reseau then 'a_valider_reseau' else 'en_attente_accueil' end;
  insert into public.transferts_reseau (id, reseau_id, fiche_origine_id, etablissement_origine_id, etablissement_destination_id,
    niveau_id, statut, motif, solde_au_depart, inscription_offerte, dossier, demande_par)
  values (p_id, v_reseau, p_fiche, f.etablissement_id, p_destination, v_insc.niveau_id, v_statut, trim(p_motif),
    v_solde, n.transfert_inscription_offerte, v_dossier, auth.uid());

  select nom into v_dest from public.etablissements where id = p_destination;
  if v_statut = 'a_valider_reseau' then
    perform public.notifier_transfert(p_id, 'reseau',
      format('Transfert à valider : %s %s vers %s.', f.prenom, f.nom, v_dest));
  else
    perform public.notifier_transfert(p_id, 'accueil',
      format('Demande de transfert : %s %s (%s) souhaite rejoindre votre école.', f.prenom, f.nom, v_insc.classe));
  end if;
  return jsonb_build_object('id', p_id, 'statut', v_statut, 'deja_recue', false, 'solde_au_depart', v_solde);
end;
$$;

-- Validation par la Direction Générale (si le réseau l'exige).
create or replace function public.valider_transfert_reseau(p_id uuid, p_accorder boolean, p_motif text default null)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.transferts_reseau;
  f public.fiches_eleves;
begin
  select * into t from public.transferts_reseau where id = p_id for update;
  if not found then raise exception 'TRANSFERT_INTROUVABLE' using errcode = 'P0002'; end if;
  if not public.pilote_reseau(t.reseau_id) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  -- Renvoi de la même décision (hors connexion) : déjà fait.
  if (p_accorder and t.statut in ('en_attente_accueil', 'transfere')) or (not p_accorder and t.statut = 'refuse') then
    return t.statut;
  end if;
  if t.statut <> 'a_valider_reseau' then raise exception 'TRANSFERT_DEJA_TRAITE' using errcode = '23514'; end if;
  if not p_accorder and char_length(trim(coalesce(p_motif, ''))) < 3 then
    raise exception 'MOTIF_REQUIS' using errcode = '23514';
  end if;
  select * into f from public.fiches_eleves where id = t.fiche_origine_id;
  if p_accorder then
    update public.transferts_reseau set statut = 'en_attente_accueil', valide_par = auth.uid(), valide_le = now()
     where id = p_id;
    perform public.notifier_transfert(p_id, 'accueil',
      format('Demande de transfert : %s %s souhaite rejoindre votre école (validée par le réseau).', f.prenom, f.nom));
    return 'en_attente_accueil';
  end if;
  update public.transferts_reseau
     set statut = 'refuse', refuse_par = 'reseau', motif_refus = trim(p_motif), valide_par = auth.uid(), valide_le = now()
   where id = p_id;
  perform public.notifier_transfert(p_id, 'depart',
    format('Transfert de %s %s refusé par le réseau : %s', f.prenom, f.nom, trim(p_motif)));
  return 'refuse';
end;
$$;

-- Réponse de l'école d'accueil. Accepté : le transfert est fait en une fois.
create or replace function public.repondre_transfert_reseau(
  p_id uuid, p_accepter boolean, p_classe uuid default null, p_motif text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.transferts_reseau;
  f public.fiches_eleves;
  v_annee uuid;
  v_classe public.classes;
  v_fiche uuid;
  v_inscription uuid;
  v_origine text;
  v_dest text;
  r record;
begin
  select * into t from public.transferts_reseau where id = p_id for update;
  if not found then raise exception 'TRANSFERT_INTROUVABLE' using errcode = 'P0002'; end if;
  if not coalesce(public.gere_inscriptions(t.etablissement_destination_id), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if (p_accepter and t.statut = 'transfere') or (not p_accepter and t.statut = 'refuse') then
    return jsonb_build_object('statut', t.statut, 'fiche_id', t.fiche_destination_id, 'deja_recue', true);
  end if;
  if t.statut <> 'en_attente_accueil' then raise exception 'TRANSFERT_DEJA_TRAITE' using errcode = '23514'; end if;

  select * into f from public.fiches_eleves where id = t.fiche_origine_id;
  select nom into v_origine from public.etablissements where id = t.etablissement_origine_id;
  select nom into v_dest from public.etablissements where id = t.etablissement_destination_id;

  if not p_accepter then
    if char_length(trim(coalesce(p_motif, ''))) < 3 then raise exception 'MOTIF_REQUIS' using errcode = '23514'; end if;
    update public.transferts_reseau
       set statut = 'refuse', refuse_par = 'accueil', motif_refus = trim(p_motif), decide_par = auth.uid(), decide_le = now()
     where id = p_id;
    perform public.notifier_transfert(p_id, 'depart',
      format('%s a refusé le transfert de %s %s : %s', v_dest, f.prenom, f.nom, trim(p_motif)));
    return jsonb_build_object('statut', 'refuse', 'deja_recue', false);
  end if;

  -- Classe de l'année courante de l'école d'accueil.
  select id into v_annee from public.annees_scolaires
   where etablissement_id = t.etablissement_destination_id and courante limit 1;
  if v_annee is null then raise exception 'ANNEE_COURANTE_ABSENTE' using errcode = '23514'; end if;
  select * into v_classe from public.classes
   where id = p_classe and etablissement_id = t.etablissement_destination_id and annee_scolaire_id = v_annee
     and deleted_at is null;
  if not found then raise exception 'CLASSE_INVALIDE' using errcode = '22023'; end if;

  -- Fiche à l'arrivée : identité et famille reprises, matricule de l'école.
  insert into public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, sexe, lieu_naissance,
    nationalite, nom_pere, nom_mere, quartier, personne_urgence_nom, personne_urgence_telephone,
    responsable_financier, redoublant, profile_id, lie_le, fiche_origine_id)
  values (t.etablissement_destination_id, public.generer_matricule(t.etablissement_destination_id), f.nom, f.prenom,
    f.date_naissance, f.sexe, f.lieu_naissance, f.nationalite, f.nom_pere, f.nom_mere, f.quartier,
    f.personne_urgence_nom, f.personne_urgence_telephone, f.responsable_financier, f.redoublant,
    f.profile_id, case when f.profile_id is not null then now() end, f.id)
  returning id into v_fiche;

  insert into public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
  values (t.etablissement_destination_id, v_fiche, v_classe.id, v_annee, 'active')
  returning id into v_inscription;

  -- Parents rattachés à l'école d'accueil ; compte élève aussi.
  for r in select * from public.relations_parent_eleve
           where fiche_eleve_id = f.id and deleted_at is null and statut = 'confirmee' loop
    insert into public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
    values (t.etablissement_destination_id, r.parent_profile_id, v_fiche, r.type_relation, 'confirmee', r.autorise)
    on conflict (parent_profile_id, fiche_eleve_id) do nothing;
    insert into public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
    values (r.parent_profile_id, t.etablissement_destination_id, 'parent')
    on conflict (profile_id, etablissement_id) do nothing;
    perform public.notifier_push(t.etablissement_destination_id, r.parent_profile_id, 'reseau_transfert',
      format('%s est maintenant inscrit(e) à %s (%s).', f.prenom, v_dest, v_classe.nom),
      jsonb_build_object('transfert_id', t.id));
  end loop;
  if f.profile_id is not null then
    insert into public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
    values (f.profile_id, t.etablissement_destination_id, 'eleve')
    on conflict (profile_id, etablissement_id) do nothing;
  end if;

  -- Départ : inscription retirée, fiche close.
  update public.inscriptions
     set statut = 'retiree', date_retrait = current_date, motif_retrait = format('Transfert vers %s', v_dest)
   where fiche_eleve_id = f.id and deleted_at is null and statut in ('active', 'redoublante');
  update public.fiches_eleves set statut = 'retire' where id = f.id;

  update public.transferts_reseau
     set statut = 'transfere', decide_par = auth.uid(), decide_le = now(),
         fiche_destination_id = v_fiche, inscription_destination_id = v_inscription
   where id = p_id;
  perform public.notifier_transfert(p_id, 'depart',
    format('%s %s a été accueilli(e) par %s : transfert terminé.', f.prenom, f.nom, v_dest));
  return jsonb_build_object('statut', 'transfere', 'fiche_id', v_fiche, 'inscription_id', v_inscription, 'deja_recue', false);
end;
$$;

-- Annulation par l'école de départ, tant que l'accueil n'a pas répondu.
create or replace function public.annuler_transfert_reseau(p_id uuid)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.transferts_reseau;
begin
  select * into t from public.transferts_reseau where id = p_id for update;
  if not found then raise exception 'TRANSFERT_INTROUVABLE' using errcode = 'P0002'; end if;
  if not coalesce(public.gere_inscriptions(t.etablissement_origine_id), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if t.statut = 'annule' then return 'annule'; end if;
  if t.statut not in ('a_valider_reseau', 'en_attente_accueil') then
    raise exception 'TRANSFERT_DEJA_TRAITE' using errcode = '23514';
  end if;
  update public.transferts_reseau set statut = 'annule', decide_par = auth.uid(), decide_le = now() where id = p_id;
  return 'annule';
end;
$$;

-- Transferts visibles : ceux d'une école (départs et arrivées) pour ses
-- gestionnaires, ou ceux d'un réseau pour ses responsables. Le dossier
-- n'est montré qu'à l'école d'accueil, au réseau et au départ.
create or replace function public.transferts_reseau_liste(p_reseau uuid default null, p_etablissement uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if p_reseau is null and p_etablissement is null then raise exception 'PARAMETRE_REQUIS' using errcode = '22023'; end if;
  if p_reseau is not null and public.role_reseau(p_reseau) is null and not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if p_etablissement is not null and not coalesce(public.gere_inscriptions(p_etablissement), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'reseau_id', t.reseau_id, 'statut', t.statut, 'motif', t.motif,
      'sens', case when p_etablissement is null then null
                   when t.etablissement_origine_id = p_etablissement then 'depart' else 'arrivee' end,
      'eleve', f.prenom || ' ' || f.nom, 'fiche_origine_id', t.fiche_origine_id,
      'date_naissance', f.date_naissance, 'niveau_id', t.niveau_id, 'niveau', nv.nom,
      'origine_id', t.etablissement_origine_id, 'origine', eo.nom,
      'destination_id', t.etablissement_destination_id, 'destination', ed.nom,
      'solde_au_depart', t.solde_au_depart, 'inscription_offerte', t.inscription_offerte,
      'dossier', t.dossier, 'demande_le', t.demande_le, 'decide_le', coalesce(t.decide_le, t.valide_le),
      'motif_refus', t.motif_refus, 'refuse_par', t.refuse_par, 'fiche_destination_id', t.fiche_destination_id
    ) order by (t.statut in ('a_valider_reseau', 'en_attente_accueil')) desc, t.demande_le desc), '[]'::jsonb)
    from (select * from public.transferts_reseau t0
          where (p_reseau is null or t0.reseau_id = p_reseau)
            and (p_etablissement is null or p_etablissement in (t0.etablissement_origine_id, t0.etablissement_destination_id))
          order by t0.demande_le desc limit 200) t
    join public.fiches_eleves f on f.id = t.fiche_origine_id
    join public.etablissements eo on eo.id = t.etablissement_origine_id
    join public.etablissements ed on ed.id = t.etablissement_destination_id
    left join public.niveaux_educatifs nv on nv.id = t.niveau_id);
end;
$$;

-- Écoles du même réseau vers lesquelles un élève peut partir, avec leurs
-- classes de l'année pour le niveau, et les règles qui s'appliquent.
create or replace function public.destinations_transfert(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not coalesce(public.gere_inscriptions(p_etablissement), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'etablissement_id', e.id, 'nom', e.nom, 'ville', e.ville, 'reseau_id', n.id, 'reseau', n.nom,
      'transferts_ouverts', n.transferts_ouverts, 'quitus_requis', n.transfert_quitus_requis,
      'validation_reseau', n.transfert_validation_reseau, 'inscription_offerte', n.transfert_inscription_offerte
    ) order by n.nom, e.nom), '[]'::jsonb)
    from public.reseaux_etablissements moi
    join public.reseaux n on n.id = moi.reseau_id and n.statut = 'actif'
    join public.reseaux_etablissements autre on autre.reseau_id = n.id and autre.statut in ('membre', 'retrait_demande')
         and autre.etablissement_id <> p_etablissement
    join public.etablissements e on e.id = autre.etablissement_id and e.deleted_at is null
    where moi.etablissement_id = p_etablissement and moi.statut in ('membre', 'retrait_demande'));
end;
$$;

-- Élèves de l'année que l'école peut faire partir, avec leur solde (la
-- règle « frais soldés » se voit avant de demander).
create or replace function public.eleves_transferables(p_etablissement uuid, p_texte text default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not coalesce(public.gere_inscriptions(p_etablissement), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(x order by x ->> 'nom', x ->> 'prenom'), '[]'::jsonb) from (
    select jsonb_build_object(
      'fiche_id', f.id, 'nom', f.nom, 'prenom', f.prenom, 'matricule', f.matricule, 'classe', c.nom,
      'solde', (select s.solde from public.solde_scolarite(i.id) s),
      'en_transfert', exists (select 1 from public.transferts_reseau t where t.fiche_origine_id = f.id
                                and t.statut in ('a_valider_reseau', 'en_attente_accueil'))) as x
    from public.inscriptions i
    join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
    join public.classes c on c.id = i.classe_id
    join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
    where i.etablissement_id = p_etablissement and i.deleted_at is null and i.statut in ('active', 'redoublante')
      and (coalesce(trim(p_texte), '') = ''
           or public.texte_recherche(f.nom || ' ' || f.prenom || ' ' || f.matricule) like '%' || public.texte_recherche(p_texte) || '%')
    order by f.nom, f.prenom
    limit 40) s);
end;
$$;

-- Classes de l'année courante de l'école d'accueil (choix à l'acceptation).
create or replace function public.classes_accueil_transfert(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  t public.transferts_reseau;
begin
  select * into t from public.transferts_reseau where id = p_id;
  if not found then raise exception 'TRANSFERT_INTROUVABLE' using errcode = 'P0002'; end if;
  if not coalesce(public.gere_inscriptions(t.etablissement_destination_id), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'classe_id', c.id, 'nom', c.nom, 'niveau_id', c.niveau_id, 'meme_niveau', c.niveau_id is not distinct from t.niveau_id,
      'capacite', c.capacite,
      'effectif', (select count(*) from public.inscriptions i where i.classe_id = c.id and i.deleted_at is null
                     and i.statut in ('active', 'redoublante'))
    ) order by (c.niveau_id is not distinct from t.niveau_id) desc, c.nom), '[]'::jsonb)
    from public.classes c
    join public.annees_scolaires a on a.id = c.annee_scolaire_id and a.courante
    where c.etablissement_id = t.etablissement_destination_id and c.deleted_at is null);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Droits
-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'public.appliquer_grille_reseau(uuid, uuid)',
    'public.parametrer_reseau(uuid, text, boolean, boolean, boolean, boolean, boolean)',
    'public.enregistrer_grille_reseau(uuid, jsonb)',
    'public.regles_reseau(uuid, uuid)',
    'public.demander_transfert_reseau(uuid, uuid, uuid, text)',
    'public.valider_transfert_reseau(uuid, boolean, text)',
    'public.repondre_transfert_reseau(uuid, boolean, uuid, text)',
    'public.annuler_transfert_reseau(uuid)',
    'public.transferts_reseau_liste(uuid, uuid)',
    'public.destinations_transfert(uuid)',
    'public.classes_accueil_transfert(uuid)',
    'public.eleves_transferables(uuid, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

revoke all on function public.poser_grille_reseau(uuid, uuid) from public, anon, authenticated;
revoke all on function public.reseau_frais_communs(uuid) from public, anon;
grant execute on function public.reseau_frais_communs(uuid) to authenticated;
revoke all on function public.reseau_commun(uuid, uuid) from public, anon, authenticated;
revoke all on function public.notifier_transfert(uuid, text, text) from public, anon, authenticated;
revoke all on function public.reseaux_etablissements_grille_trg() from public, anon, authenticated;
