-- ============================================================================
-- EcoShop — Chantier "bloquant lancement" item 2/4 : verrou définitif des
-- notes après proclamation + mention admis(e)/recalé(e) pour les classes
-- d'examen (cahier §12.3, §12.4, §7.3).
--
-- Écart assumé par rapport à la réponse de cadrage du porteur de projet :
-- `est_niveau_examinateur` NE devient PAS éditable par la Direction. C'est un
-- attribut du référentiel pédagogique CEDEAO (niveaux_educatifs, M4), table
-- PARTAGÉE par tous les établissements d'un même pays — aucune policy RLS
-- d'écriture n'existe sur cette table (seule une policy select existe,
-- migration 20260906000400). Rendre ce champ éditable par la Direction d'un
-- établissement lui permettrait de modifier le statut "classe d'examen" pour
-- TOUS les établissements du pays. Écriture réservée service/migration, comme
-- le reste de ce référentiel, jusqu'à ce qu'un CMS admin_contenu existe.
--
-- Repêchage / seuil paramétrable / conseil de classe : hors périmètre, dette
-- déjà tracée séparément dans ANALYSE_GLOBALE.md (non datée) — la mention
-- finale est donc un champ SAISI, jamais calculé.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Classe d'examen — attribut hérité du pays_niveau (§7.3).
-- ---------------------------------------------------------------------------
alter table public.niveaux_educatifs
  add column if not exists est_niveau_examinateur boolean not null default false;

comment on column public.niveaux_educatifs.est_niveau_examinateur is
  'Cahier §7.3 — une classe est "classe d''examen" si son niveau porte true. Écriture réservée service/migration (référentiel CEDEAO partagé, aucune policy RLS d''écriture sur niveaux_educatifs).';

create or replace function public.classe_est_examen(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(n.est_niveau_examinateur, false)
  from public.classes c
  left join public.niveaux_educatifs n on n.id = c.niveau_id
  where c.id = p_classe and c.deleted_at is null;
$$;

comment on function public.classe_est_examen(uuid) is
  'Vrai si la classe hérite du statut "classe d''examen" de son niveau (§7.3). SECURITY DEFINER : niveaux_educatifs n''est lisible que pour les niveaux publiés, la classe peut référencer un niveau non publié entre-temps.';

grant execute on function public.classe_est_examen(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Mention finale admis(e)/recalé(e) — saisie manuelle par la Direction.
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.mention_finale as enum ('admis', 'recale');
exception when duplicate_object then null;
end $$;

alter table public.inscriptions
  add column if not exists mention_finale public.mention_finale,
  add column if not exists mention_definie_le timestamptz,
  add column if not exists mention_definie_par uuid references public.profiles (id) on delete set null;

-- ---------------------------------------------------------------------------
-- 3. Proclamation — événement définitif par (classe, année scolaire).
-- ---------------------------------------------------------------------------
create table if not exists public.proclamations_classes (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  classe_id uuid not null references public.classes (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  proclamee_par uuid not null references public.profiles (id) on delete restrict,
  proclamee_le timestamptz not null default now(),
  constraint proclamations_classe_annee_unique unique (classe_id, annee_scolaire_id)
);

comment on table public.proclamations_classes is
  'Cahier §12.3 — événement définitif et immuable par (classe, année). Aucune policy UPDATE/DELETE : une fois posée, une proclamation ne peut jamais être retirée, y compris par admin_gsg.';

alter table public.proclamations_classes enable row level security;

-- Lecture seule côté RLS ; toute création passe par proclamer_classe() ci-
-- dessous, jamais un INSERT direct. Aucune policy update/delete n'existe : le
-- déni est donc total et définitif pour tous les rôles, y compris
-- Administrateur GSG (deny-by-default de Postgres en l'absence de policy).
drop policy if exists "proclamations_select" on public.proclamations_classes;
create policy "proclamations_select" on public.proclamations_classes
  for select using (public.est_personnel(etablissement_id) or public.est_admin_gsg());

create or replace function public.classe_est_proclamee(p_classe uuid, p_annee uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.proclamations_classes pc
    where pc.classe_id = p_classe and pc.annee_scolaire_id = p_annee
  );
$$;

grant execute on function public.classe_est_proclamee(uuid, uuid) to authenticated;

-- Saisie de la mention finale — réservée à la Direction (est_direction, pas
-- a_permission : ce droit n'est pas configurable par poste). Bloquée dès que
-- la classe est déjà proclamée, sans aucune exception.
create or replace function public.definir_mention_finale(
  p_inscription uuid,
  p_mention public.mention_finale
)
returns public.inscriptions
language plpgsql security definer set search_path = public
as $$
declare
  v_etablissement uuid;
  v_classe uuid;
  v_annee uuid;
  v_row public.inscriptions;
begin
  select etablissement_id, classe_id, annee_scolaire_id
    into v_etablissement, v_classe, v_annee
  from public.inscriptions
  where id = p_inscription and deleted_at is null;

  if v_etablissement is null then
    raise exception 'INSCRIPTION_INTROUVABLE' using errcode = '23514';
  end if;

  -- coalesce(..., false) : est_direction() peut renvoyer NULL si l'appelant
  -- n'a pas encore de role_racine choisi (cf. discipline actée à l'audit RPC
  -- de septembre, migration 20260906001513) — un simple `if not ...` en
  -- plpgsql laisserait alors passer l'appel silencieusement.
  if not coalesce(public.est_direction(v_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  if not public.classe_est_examen(v_classe) then
    raise exception 'CLASSE_NON_EXAMEN' using errcode = '23514';
  end if;

  if public.classe_est_proclamee(v_classe, v_annee) then
    raise exception 'CLASSE_DEJA_PROCLAMEE' using errcode = '42501';
  end if;

  update public.inscriptions
    set mention_finale = p_mention,
        mention_definie_le = now(),
        mention_definie_par = auth.uid()
  where id = p_inscription
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.definir_mention_finale(uuid, public.mention_finale) to authenticated;

-- Proclamation — verrouille définitivement la classe pour l'année. Pour les
-- classes d'examen, exige que tous les élèves actifs portent déjà une
-- mention (§12.4).
create or replace function public.proclamer_classe(
  p_classe uuid,
  p_annee uuid
)
returns public.proclamations_classes
language plpgsql security definer set search_path = public
as $$
declare
  v_etablissement uuid;
  v_manquantes int;
  v_row public.proclamations_classes;
begin
  select etablissement_id into v_etablissement
  from public.classes
  where id = p_classe and deleted_at is null and annee_scolaire_id = p_annee;

  if v_etablissement is null then
    raise exception 'CLASSE_INTROUVABLE' using errcode = '23514';
  end if;

  if not coalesce(public.est_direction(v_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  if public.classe_est_proclamee(p_classe, p_annee) then
    raise exception 'CLASSE_DEJA_PROCLAMEE' using errcode = '42501';
  end if;

  if public.classe_est_examen(p_classe) then
    select count(*) into v_manquantes
    from public.inscriptions i
    where i.classe_id = p_classe and i.annee_scolaire_id = p_annee
      and i.statut = 'active' and i.deleted_at is null
      and i.mention_finale is null;

    if v_manquantes > 0 then
      raise exception 'MENTION_MANQUANTE' using errcode = '23514';
    end if;
  end if;

  insert into public.proclamations_classes (etablissement_id, classe_id, annee_scolaire_id, proclamee_par)
  values (v_etablissement, p_classe, p_annee, auth.uid())
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.proclamer_classe(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Verrou total sur la saisie de notes, y compris pour l'Administrateur
--    GSG : aucune clause a_permission/est_admin_gsg dans ce garde-fou, c'est
--    volontaire — la proclamation ferme l'accès à TOUT le monde.
-- ---------------------------------------------------------------------------
create or replace function public.peut_saisir_notes(p_eval uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.evaluations e
    where e.id = p_eval and e.deleted_at is null and e.statut <> 'cloturee'
      and not public.classe_est_proclamee(e.classe_id, e.annee_scolaire_id)
      and (
        public.a_permission(e.etablissement_id, 'scolarite.note.gerer')
        or e.enseignant_profile_id = auth.uid()
      )
  );
$$;

comment on function public.peut_saisir_notes(uuid) is
  'Cahier §12.3 — verrouille par évaluation (statut cloturee) ET par proclamation de la classe/année (classe_est_proclamee), sans aucune exception admin_gsg dans cette dernière clause.';

-- ---------------------------------------------------------------------------
-- 5. Régénération de bulletins bloquée après proclamation (sinon le contenu
--    pourrait être réécrit après le verrou, contournant le point 4) — et
--    affichage de la mention finale pour les classes d'examen.
-- ---------------------------------------------------------------------------
create or replace function public.generer_bulletins_classe(
  p_classe uuid,
  p_annee uuid,
  p_periode uuid default null,
  p_type public.type_bulletin default 'trimestriel'
)
returns setof public.bulletins
language plpgsql security definer set search_path = public
as $$
declare
  v_etablissement uuid;
begin
  select etablissement_id into v_etablissement from public.classes where id = p_classe;
  if v_etablissement is null then
    raise exception 'CLASSE_INTROUVABLE' using errcode = '23514';
  end if;

  if not coalesce(public.a_permission(v_etablissement, 'scolarite.bulletin.gerer'), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  if public.classe_est_proclamee(p_classe, p_annee) then
    raise exception 'CLASSE_DEJA_PROCLAMEE' using errcode = '42501';
  end if;

  if p_periode is null then
    return query
    insert into public.bulletins
      (etablissement_id, annee_scolaire_id, periode_id, classe_id, fiche_eleve_id, type, statut, contenu, genere_le, publie_le)
    select v_etablissement, p_annee, null, p_classe, c.fiche_eleve_id, p_type, 'publie',
           jsonb_build_object(
             'moyenne_generale', c.moyenne, 'rang', c.rang, 'effectif_classe', count(*) over (),
             'mention_finale', i.mention_finale
           ),
           now(), now()
    from public.classer_eleves_classe(p_classe, null, null) c
    join public.inscriptions i on i.fiche_eleve_id = c.fiche_eleve_id and i.classe_id = p_classe
    on conflict (fiche_eleve_id, type) where periode_id is null
    do update set
      annee_scolaire_id = excluded.annee_scolaire_id,
      classe_id = excluded.classe_id,
      statut = excluded.statut,
      contenu = excluded.contenu,
      genere_le = excluded.genere_le,
      publie_le = excluded.publie_le
    returning *;
  else
    return query
    insert into public.bulletins
      (etablissement_id, annee_scolaire_id, periode_id, classe_id, fiche_eleve_id, type, statut, contenu, genere_le, publie_le)
    select v_etablissement, p_annee, p_periode, p_classe, c.fiche_eleve_id, p_type, 'publie',
           jsonb_build_object(
             'moyenne_generale', c.moyenne, 'rang', c.rang, 'effectif_classe', count(*) over (),
             'mention_finale', i.mention_finale
           ),
           now(), now()
    from public.classer_eleves_classe(p_classe, null, p_periode) c
    join public.inscriptions i on i.fiche_eleve_id = c.fiche_eleve_id and i.classe_id = p_classe
    on conflict (fiche_eleve_id, periode_id, type) where periode_id is not null
    do update set
      annee_scolaire_id = excluded.annee_scolaire_id,
      classe_id = excluded.classe_id,
      statut = excluded.statut,
      contenu = excluded.contenu,
      genere_le = excluded.genere_le,
      publie_le = excluded.publie_le
    returning *;
  end if;
end;
$$;

-- ============================================================================
-- Fin — verrou définitif des notes + mention finale.
-- ============================================================================
