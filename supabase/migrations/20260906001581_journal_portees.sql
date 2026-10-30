-- ============================================================================
-- EcoShop — REG-35 lot 3 : synchronisation par différences
-- ============================================================================
-- L'amorçage (lot 2) relisait toutes les données d'un espace, même
-- inchangées. Ici, le serveur tient un journal minimal : pour chaque
-- « portée » (une école, une classe, un élève), la date de sa dernière
-- modification. Le téléphone demande en une requête lesquelles de ses
-- portées ont changé depuis sa dernière lecture, et ne relit que celles-là.
--
-- Références : le curseur « lastPulledAt » de WatermelonDB, les « buckets »
-- de PowerSync (un groupe de lignes synchronisé d'un bloc, repris là où il
-- s'était arrêté). Granularité retenue : la portée et non la ligne, parce que
-- les copies du téléphone sont des réponses d'écran (liste des élèves d'une
-- classe…) — une portée modifiée = ses écrans à relire.
--
-- Suppressions : un déclencheur AFTER DELETE marque la portée, qui est
-- relue en entier : la ligne supprimée disparaît de la copie, sans tombstone.
--
-- Piège évité : une transaction commencée avant une lecture mais validée
-- après garde une date antérieure à la lecture. `portees_modifiees` compare
-- donc avec une marge de 10 minutes (au prix d'une relecture de trop).
-- ============================================================================

create table if not exists public.journal_portees (
  portee text not null check (portee in ('etablissement', 'classe', 'fiche')),
  portee_id uuid not null,
  -- Pas de clé étrangère : la suppression en cascade d'une école marque ses
  -- portées pendant qu'elle disparaît.
  etablissement_id uuid not null,
  modifie_le timestamptz not null default clock_timestamp(),
  primary key (portee, portee_id)
);

comment on table public.journal_portees is
  'REG-35 lot 3 — dernière modification par portée (école, classe, élève), lue par portees_modifiees.';

-- Aucun accès direct : seulement par les fonctions ci-dessous.
alter table public.journal_portees enable row level security;
revoke all on public.journal_portees from anon, authenticated;

create or replace function public.marquer_portee(p_portee text, p_id uuid, p_etablissement uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.journal_portees (portee, portee_id, etablissement_id, modifie_le)
  values (p_portee, p_id, p_etablissement, clock_timestamp())
  on conflict (portee, portee_id) do update
    set modifie_le = excluded.modifie_le, etablissement_id = excluded.etablissement_id
    -- Une saisie de 40 notes dans une transaction : une seule mise à jour.
    where public.journal_portees.modifie_le < now();
$$;

revoke all on function public.marquer_portee(text, uuid, uuid) from public, anon, authenticated;

-- Déclencheur générique. Arguments : « portee:colonne », par exemple
-- 'classe:classe_id', 'fiche:fiche_eleve_id', 'etablissement:etablissement_id'.
-- L'ancienne valeur est aussi marquée quand elle change (élève changé de
-- classe : les deux classes sont à relire).
create or replace function public.tg_journal_portees()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_arg text;
  v_portee text;
  v_colonne text;
  v_nouv jsonb;
  v_anc jsonb;
begin
  if tg_op <> 'DELETE' then
    v_nouv := to_jsonb(new);
  end if;
  if tg_op <> 'INSERT' then
    v_anc := to_jsonb(old);
  end if;

  foreach v_arg in array tg_argv loop
    v_portee := split_part(v_arg, ':', 1);
    v_colonne := split_part(v_arg, ':', 2);

    if v_nouv is not null and v_nouv ->> v_colonne is not null then
      perform public.marquer_portee(v_portee, (v_nouv ->> v_colonne)::uuid, (v_nouv ->> 'etablissement_id')::uuid);
    end if;

    if v_anc is not null and v_anc ->> v_colonne is not null
       and (v_nouv is null or (v_nouv ->> v_colonne) is distinct from (v_anc ->> v_colonne)) then
      perform public.marquer_portee(v_portee, (v_anc ->> v_colonne)::uuid, (v_anc ->> 'etablissement_id')::uuid);
    end if;
  end loop;

  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Branchement : ce que l'amorçage lit d'avance, par portée.
-- ---------------------------------------------------------------------------

-- École : annuaire (années, périodes, classes), personnel, encaissements,
-- tarifs, agenda, annonces.
drop trigger if exists trg_journal_portees on public.annees_scolaires;
create trigger trg_journal_portees after insert or update or delete on public.annees_scolaires
  for each row execute function public.tg_journal_portees('etablissement:etablissement_id');

drop trigger if exists trg_journal_portees on public.periodes_scolaires;
create trigger trg_journal_portees after insert or update or delete on public.periodes_scolaires
  for each row execute function public.tg_journal_portees('etablissement:etablissement_id');

drop trigger if exists trg_journal_portees on public.classes;
create trigger trg_journal_portees after insert or update or delete on public.classes
  for each row execute function public.tg_journal_portees('etablissement:etablissement_id');

drop trigger if exists trg_journal_portees on public.employes;
create trigger trg_journal_portees after insert or update or delete on public.employes
  for each row execute function public.tg_journal_portees('etablissement:etablissement_id');

drop trigger if exists trg_journal_portees on public.frais_scolarite_config;
create trigger trg_journal_portees after insert or update or delete on public.frais_scolarite_config
  for each row execute function public.tg_journal_portees('etablissement:etablissement_id');

drop trigger if exists trg_journal_portees on public.evenements_agenda;
create trigger trg_journal_portees after insert or update or delete on public.evenements_agenda
  for each row execute function public.tg_journal_portees('etablissement:etablissement_id');

drop trigger if exists trg_journal_portees on public.annonces_ecole;
create trigger trg_journal_portees after insert or update or delete on public.annonces_ecole
  for each row execute function public.tg_journal_portees('etablissement:etablissement_id');

drop trigger if exists trg_journal_portees on public.encaissements_scolarite;
create trigger trg_journal_portees after insert or update or delete on public.encaissements_scolarite
  for each row execute function public.tg_journal_portees('etablissement:etablissement_id', 'fiche:fiche_eleve_id');

-- Classe : élèves inscrits, enseignants, emploi du temps, évaluations.
drop trigger if exists trg_journal_portees on public.inscriptions;
create trigger trg_journal_portees after insert or update or delete on public.inscriptions
  for each row execute function public.tg_journal_portees('classe:classe_id', 'fiche:fiche_eleve_id');

drop trigger if exists trg_journal_portees on public.affectations_enseignants;
create trigger trg_journal_portees after insert or update or delete on public.affectations_enseignants
  for each row execute function public.tg_journal_portees('classe:classe_id');

drop trigger if exists trg_journal_portees on public.emplois_du_temps;
create trigger trg_journal_portees after insert or update or delete on public.emplois_du_temps
  for each row execute function public.tg_journal_portees('classe:classe_id');

drop trigger if exists trg_journal_portees on public.evaluations;
create trigger trg_journal_portees after insert or update or delete on public.evaluations
  for each row execute function public.tg_journal_portees('classe:classe_id');

-- Élève : sa fiche (nom affiché partout), notes, appréciations, bulletins,
-- absences, retards, sanctions, cahier de liaison.
drop trigger if exists trg_journal_portees on public.fiches_eleves;
create trigger trg_journal_portees after insert or update or delete on public.fiches_eleves
  for each row execute function public.tg_journal_portees('fiche:id');

drop trigger if exists trg_journal_portees on public.notes;
create trigger trg_journal_portees after insert or update or delete on public.notes
  for each row execute function public.tg_journal_portees('fiche:fiche_eleve_id');

drop trigger if exists trg_journal_portees on public.appreciations;
create trigger trg_journal_portees after insert or update or delete on public.appreciations
  for each row execute function public.tg_journal_portees('fiche:fiche_eleve_id');

drop trigger if exists trg_journal_portees on public.bulletins;
create trigger trg_journal_portees after insert or update or delete on public.bulletins
  for each row execute function public.tg_journal_portees('fiche:fiche_eleve_id');

drop trigger if exists trg_journal_portees on public.presences;
create trigger trg_journal_portees after insert or update or delete on public.presences
  for each row execute function public.tg_journal_portees('fiche:fiche_eleve_id');

drop trigger if exists trg_journal_portees on public.retards;
create trigger trg_journal_portees after insert or update or delete on public.retards
  for each row execute function public.tg_journal_portees('fiche:fiche_eleve_id');

drop trigger if exists trg_journal_portees on public.sanctions;
create trigger trg_journal_portees after insert or update or delete on public.sanctions
  for each row execute function public.tg_journal_portees('fiche:fiche_eleve_id');

drop trigger if exists trg_journal_portees on public.messages_liaison;
create trigger trg_journal_portees after insert or update or delete on public.messages_liaison
  for each row execute function public.tg_journal_portees('fiche:fiche_eleve_id');

-- ---------------------------------------------------------------------------
-- Lecture : quelles portées ont changé ?
-- ---------------------------------------------------------------------------
-- Entrée : [{"portee": "classe", "id": "…", "depuis": "2026-10-30T14:00:00Z"}, …]
-- (au plus 2 000 portées). Sortie :
--   {"maintenant": <heure du serveur>, "modifiees": [{"portee", "id"}, …]}
-- « maintenant » est pris au début de l'appel : le téléphone l'enregistre
-- comme date de lecture des portées qu'il relit ensuite.
-- Une portée absente du journal n'a pas changé depuis sa création. Seules
-- les portées des écoles qui concernent l'appelant sont examinées (seule une
-- date est révélée, jamais le contenu).
create or replace function public.portees_modifiees(p_portees jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with demandes as (
    select d ->> 'portee' as portee,
           (d ->> 'id')::uuid as portee_id,
           (d ->> 'depuis')::timestamptz as depuis
    from jsonb_array_elements(coalesce(p_portees, '[]'::jsonb)) d
    where jsonb_typeof(d) = 'object' and d ? 'id' and d ? 'depuis'
    limit 2000
  ),
  ecoles as (
    select distinct j.etablissement_id
    from demandes d
    join public.journal_portees j on j.portee = d.portee and j.portee_id = d.portee_id
  ),
  autorisees as (
    select e.etablissement_id from ecoles e where public.concerne_etablissement(e.etablissement_id)
  )
  select jsonb_build_object(
    'maintenant', now(),
    'modifiees', coalesce((
      select jsonb_agg(jsonb_build_object('portee', d.portee, 'id', d.portee_id))
      from demandes d
      join public.journal_portees j on j.portee = d.portee and j.portee_id = d.portee_id
      join autorisees a on a.etablissement_id = j.etablissement_id
      where j.modifie_le > d.depuis - interval '10 minutes'
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.portees_modifiees(jsonb) from public, anon;
grant execute on function public.portees_modifiees(jsonb) to authenticated;
