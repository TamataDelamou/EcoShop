-- ============================================================================
-- EcoShop — Patch de sécurité M9 — Messagerie de groupe scolaire supervisée
--
-- Contexte : l'audit d'écart fonctionnel (docs/AUDIT_ECOSHOP_FLUTTER.md §0.1)
-- a constaté que la messagerie de groupe scolaire d'ecoshop_flutter (source)
-- imposait 7 règles absolues de protection des mineurs au niveau des règles
-- Firestore elles-mêmes (création serveur uniquement, adulte permanent non
-- retirable, zéro message privé élève↔élève, zéro accès parent, texte seul,
-- modération réservée au personnel, soft-delete uniquement) — et que la
-- cible EcoShop n'avait AUCUNE table serveur pour cette fonctionnalité (le
-- module M9 livré ne couvre que les notifications) : le prototype client
-- local ne portait aucun de ces garde-fous et fuitait même entre comptes
-- successifs sur un même appareil (cf. patch client, session_logout.dart).
--
-- Ce patch construit le schéma serveur manquant avec RLS dès la création
-- (jamais de fenêtre « table sans RLS »), conformément aux 7 règles source :
--   1. Création réservée à un adulte affecté à la classe (enseignant/
--      direction) — jamais un élève.
--   2. Le créateur reste membre à vie du groupe (adulte permanent,
--      colonne immuable après création).
--   3. Aucune messagerie privée : tout message vit dans un groupe de classe ;
--      aucune table de conversation 1-à-1 n'est créée ici.
--   4. Aucun accès parent : l'appartenance est dérivée strictement des
--      inscriptions élève et affectations enseignant — jamais des relations
--      parent↔élève (`relations_parent_eleve` n'intervient nulle part ici).
--   5. Texte seul : `messages_groupe` ne porte AUCUNE colonne pièce jointe/
--      URL — l'absence de colonne est une garantie plus forte qu'une
--      contrainte applicative contournable.
--   6. Modération réservée au personnel : seul un modérateur (créateur,
--      enseignant affecté, ou permission dédiée) peut faire transiter le
--      statut d'un groupe ou soft-supprimer un message.
--   7. Soft-delete uniquement : aucune policy DELETE n'est créée sur
--      `groupes_discussion`, `messages_groupe` ni `signalements_message` —
--      la suppression physique est impossible depuis le client, quel que
--      soit le rôle (y compris direction).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.statut_groupe_discussion as enum ('active', 'suspendue', 'archivee');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_signalement as enum ('ouvert', 'traite', 'rejete');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Groupes de discussion — un groupe supervisé par classe et année scolaire
-- ---------------------------------------------------------------------------
create table if not exists public.groupes_discussion (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  classe_id uuid not null references public.classes (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  nom text not null,
  enseignant_createur_id uuid not null references public.profiles (id),
  statut public.statut_groupe_discussion not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Un seul groupe actif par classe et par année (groupe de classe unique).
create unique index if not exists groupes_discussion_classe_annee_actif_unique
  on public.groupes_discussion (classe_id, annee_scolaire_id)
  where deleted_at is null;

drop trigger if exists groupes_discussion_set_updated_at on public.groupes_discussion;
create trigger groupes_discussion_set_updated_at
  before update on public.groupes_discussion
  for each row execute procedure public.set_updated_at();

-- Cohérence multi-tenant (même garde que M7 presences_verifie_tenant) : la
-- classe doit appartenir à l'établissement et à l'année pointés.
-- SECURITY DEFINER : un acteur sans visibilité RLS sur `classes`/
-- `annees_scolaires` (ex. un non-membre tentant une insertion frauduleuse)
-- doit tout de même être correctement rejeté par CETTE vérification plutôt
-- que par un contournement dû à un lookup RLS-filtré renvoyant NULL.
create or replace function public.groupes_discussion_verifie_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_etab uuid; v_annee uuid;
begin
  select etablissement_id, annee_scolaire_id into v_etab, v_annee
    from public.classes where id = new.classe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  if v_annee is distinct from new.annee_scolaire_id then
    raise exception 'CLASSE_AUTRE_ANNEE' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists groupes_discussion_verifie_tenant_trg on public.groupes_discussion;
create trigger groupes_discussion_verifie_tenant_trg
  before insert or update on public.groupes_discussion
  for each row execute procedure public.groupes_discussion_verifie_tenant();

-- Règle absolue #2 : le créateur (adulte permanent) et le rattachement
-- classe/établissement/année ne sont jamais modifiables après création —
-- seuls `statut`/`nom`/`updated_at`/`deleted_at` peuvent changer.
create or replace function public.groupes_discussion_verifie_immuable()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.enseignant_createur_id is distinct from old.enseignant_createur_id
     or new.classe_id is distinct from old.classe_id
     or new.etablissement_id is distinct from old.etablissement_id
     or new.annee_scolaire_id is distinct from old.annee_scolaire_id then
    raise exception 'GROUPE_CHAMP_IMMUABLE' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists groupes_discussion_verifie_immuable_trg on public.groupes_discussion;
create trigger groupes_discussion_verifie_immuable_trg
  before update on public.groupes_discussion
  for each row execute procedure public.groupes_discussion_verifie_immuable();

-- ---------------------------------------------------------------------------
-- 2. Messages — texte seul (règle absolue #5 : pas de colonne pièce jointe)
-- ---------------------------------------------------------------------------
create table if not exists public.messages_groupe (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  groupe_id uuid not null references public.groupes_discussion (id) on delete cascade,
  auteur_id uuid not null references public.profiles (id),
  contenu text not null check (char_length(contenu) between 1 and 2000),
  created_at timestamptz not null default now(),
  supprime boolean not null default false,
  supprime_par_id uuid references public.profiles (id),
  date_suppression timestamptz
);

create index if not exists messages_groupe_groupe_idx on public.messages_groupe (groupe_id, created_at);

-- Le groupe doit être actif pour accueillir un nouveau message (repli en
-- lecture seule dès qu'il est suspendu/archivé/supprimé).
-- SECURITY DEFINER : un non-membre ne voit pas le groupe via `groupes_select_
-- membre` (RLS) — sans ce mode, ce lookup renverrait NULL pour un non-membre
-- et déclencherait la mauvaise erreur (23514) avant même que la policy
-- d'INSERT (42501) n'ait la chance de rejeter la tentative.
create or replace function public.messages_groupe_verifie_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_etab uuid; v_statut public.statut_groupe_discussion; v_deleted timestamptz;
begin
  select etablissement_id, statut, deleted_at into v_etab, v_statut, v_deleted
    from public.groupes_discussion where id = new.groupe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'GROUPE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' and (v_deleted is not null or v_statut <> 'active') then
    raise exception 'GROUPE_INACTIF' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists messages_groupe_verifie_tenant_trg on public.messages_groupe;
create trigger messages_groupe_verifie_tenant_trg
  before insert or update on public.messages_groupe
  for each row execute procedure public.messages_groupe_verifie_tenant();

-- Règle absolue #7 (volet immutabilité) : un message n'est jamais réécrit,
-- seul le triplet de soft-delete peut changer après coup.
create or replace function public.messages_groupe_verifie_immuable()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.contenu is distinct from old.contenu
     or new.auteur_id is distinct from old.auteur_id
     or new.groupe_id is distinct from old.groupe_id
     or new.etablissement_id is distinct from old.etablissement_id
     or new.created_at is distinct from old.created_at then
    raise exception 'MESSAGE_CHAMP_IMMUABLE' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists messages_groupe_verifie_immuable_trg on public.messages_groupe;
create trigger messages_groupe_verifie_immuable_trg
  before update on public.messages_groupe
  for each row execute procedure public.messages_groupe_verifie_immuable();

-- ---------------------------------------------------------------------------
-- 3. Signalements — collection dédiée, jamais supprimable (règle absolue #7)
-- ---------------------------------------------------------------------------
create table if not exists public.signalements_message (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  message_id uuid not null references public.messages_groupe (id) on delete cascade,
  signale_par_id uuid not null references public.profiles (id),
  motif text not null check (char_length(motif) between 1 and 500),
  statut public.statut_signalement not null default 'ouvert',
  traite_par_id uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  traite_at timestamptz
);

create index if not exists signalements_message_message_idx on public.signalements_message (message_id);

-- SECURITY DEFINER : même raison que ci-dessus (lookup fiable indépendamment
-- de la visibilité RLS de l'acteur sur `messages_groupe`).
create or replace function public.signalements_verifie_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.messages_groupe where id = new.message_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'SIGNALEMENT_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists signalements_verifie_tenant_trg on public.signalements_message;
create trigger signalements_verifie_tenant_trg
  before insert on public.signalements_message
  for each row execute procedure public.signalements_verifie_tenant();

-- Un signalement n'est jamais réécrit dans son fond, seul son traitement
-- (statut/traite_par_id/traite_at) peut changer.
create or replace function public.signalements_verifie_immuable()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.message_id is distinct from old.message_id
     or new.signale_par_id is distinct from old.signale_par_id
     or new.motif is distinct from old.motif
     or new.etablissement_id is distinct from old.etablissement_id then
    raise exception 'SIGNALEMENT_CHAMP_IMMUABLE' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists signalements_verifie_immuable_trg on public.signalements_message;
create trigger signalements_verifie_immuable_trg
  before update on public.signalements_message
  for each row execute procedure public.signalements_verifie_immuable();

-- ---------------------------------------------------------------------------
-- 4. Helpers de droits (SECURITY DEFINER — jamais de récursion RLS)
-- ---------------------------------------------------------------------------

-- Règle absolue #4 : appartenance dérivée strictement de l'affectation
-- enseignant ou de l'inscription élève — jamais d'une relation parentale
-- (aucune référence à `relations_parent_eleve` dans cette fonction).
create or replace function public.membre_groupe(p_groupe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.groupes_discussion g
    where g.id = p_groupe and g.deleted_at is null
      and (
        g.enseignant_createur_id = auth.uid()
        or public.est_enseignant_affecte(g.classe_id)
        or exists (
          select 1 from public.inscriptions i
          join public.fiches_eleves f on f.id = i.fiche_eleve_id
          where i.classe_id = g.classe_id
            and i.annee_scolaire_id = g.annee_scolaire_id
            and i.deleted_at is null
            and f.profile_id = auth.uid()
            and f.deleted_at is null
        )
        or public.a_permission(g.etablissement_id, 'communication.groupe.moderer')
      )
  );
$$;

-- Règle absolue #6 : modération réservée au personnel (créateur, enseignant
-- affecté à la classe, ou permission dédiée) — jamais un élève.
create or replace function public.moderateur_groupe(p_groupe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.groupes_discussion g
    where g.id = p_groupe and g.deleted_at is null
      and (
        g.enseignant_createur_id = auth.uid()
        or public.est_enseignant_affecte(g.classe_id)
        or public.a_permission(g.etablissement_id, 'communication.groupe.moderer')
      )
  );
$$;

create or replace function public.moderateur_du_message(p_message uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.messages_groupe m
    where m.id = p_message and public.moderateur_groupe(m.groupe_id)
  );
$$;

create or replace function public.membre_du_message(p_message uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.messages_groupe m
    where m.id = p_message and public.membre_groupe(m.groupe_id)
  );
$$;

grant execute on function public.membre_groupe(uuid) to authenticated;
grant execute on function public.moderateur_groupe(uuid) to authenticated;
grant execute on function public.moderateur_du_message(uuid) to authenticated;
grant execute on function public.membre_du_message(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.groupes_discussion enable row level security;
alter table public.messages_groupe enable row level security;
alter table public.signalements_message enable row level security;

-- Groupes : lecture par les membres ; création par un adulte affecté à la
-- classe (règle absolue #1 — jamais un élève) ; mise à jour (statut/nom)
-- par un modérateur ; AUCUNE policy DELETE (règle absolue #7).
drop policy if exists "groupes_select_membre" on public.groupes_discussion;
create policy "groupes_select_membre" on public.groupes_discussion
  for select using (public.membre_groupe(id));

drop policy if exists "groupes_insert_adulte_affecte" on public.groupes_discussion;
create policy "groupes_insert_adulte_affecte" on public.groupes_discussion
  for insert to authenticated
  with check (
    enseignant_createur_id = auth.uid()
    and (public.est_enseignant_affecte(classe_id) or public.est_direction(etablissement_id))
  );

drop policy if exists "groupes_update_moderateur" on public.groupes_discussion;
create policy "groupes_update_moderateur" on public.groupes_discussion
  for update using (public.moderateur_groupe(id)) with check (public.moderateur_groupe(id));

-- Messages : lecture par les membres du groupe ; création par un membre pour
-- son propre compte (jamais au nom d'autrui) ; mise à jour réservée à la
-- modération (soft-delete, règle absolue #6) ; AUCUNE policy DELETE.
drop policy if exists "messages_select_membre" on public.messages_groupe;
create policy "messages_select_membre" on public.messages_groupe
  for select using (public.membre_groupe(groupe_id));

drop policy if exists "messages_insert_membre" on public.messages_groupe;
create policy "messages_insert_membre" on public.messages_groupe
  for insert to authenticated
  with check (auteur_id = auth.uid() and public.membre_groupe(groupe_id));

drop policy if exists "messages_update_moderation" on public.messages_groupe;
create policy "messages_update_moderation" on public.messages_groupe
  for update
  using (public.moderateur_groupe(groupe_id))
  with check (public.moderateur_groupe(groupe_id));

-- Signalements : un membre peut signaler un message qu'il peut voir ; seule
-- la modération peut consulter/traiter ; AUCUNE policy DELETE (append-only).
drop policy if exists "signalements_insert_membre" on public.signalements_message;
create policy "signalements_insert_membre" on public.signalements_message
  for insert to authenticated
  with check (signale_par_id = auth.uid() and public.membre_du_message(message_id));

drop policy if exists "signalements_select_moderation" on public.signalements_message;
create policy "signalements_select_moderation" on public.signalements_message
  for select using (public.moderateur_du_message(message_id));

drop policy if exists "signalements_update_moderation" on public.signalements_message;
create policy "signalements_update_moderation" on public.signalements_message
  for update
  using (public.moderateur_du_message(message_id))
  with check (public.moderateur_du_message(message_id));
