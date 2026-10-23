-- ============================================================================
-- EcoShop — Annonces de l'école (REG-19, lot 1)
--
-- Remplace le prototype local « Annonces » (rien ne partait au serveur).
--
--   1. La direction publie une annonce pour toute l'école, un niveau ou une
--      classe (texte seul). Clé fournie par l'appareil : une publication faite
--      sans réseau et renvoyée au retour du réseau n'est jamais dupliquée.
--   2. Destinataires figés à la publication : les parents **confirmés** et le
--      compte de chaque élève inscrit (année courante) dans la portée. Une
--      notification push part à chacun ; un SMS aux parents seulement si la
--      direction le demande et tant que l'école a des crédits SMS.
--   3. Chaque destinataire lit et confirme sa lecture ; la direction voit
--      combien de familles (un élève = une famille) ont lu.
--   4. Modération : la direction masque une annonce (motif obligatoire) ;
--      elle disparaît pour les familles, jamais supprimée, et l'action est
--      inscrite au journal d'audit (qui, quand, motif).
--
-- Aucune écriture directe : tout passe par les fonctions ci-dessous.
-- Migration idempotente.
-- ============================================================================

alter type public.type_entite_journal_audit add value if not exists 'annonce';

create table if not exists public.annonces_ecole (
  id uuid primary key,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  portee text not null check (portee in ('ecole', 'niveau', 'classe')),
  niveau_id uuid references public.niveaux_educatifs (id) on delete set null,
  classe_id uuid references public.classes (id) on delete set null,
  titre text not null check (char_length(trim(titre)) between 3 and 120),
  corps text not null check (char_length(trim(corps)) between 3 and 2000),
  importante boolean not null default false,
  par_sms boolean not null default false,
  publiee_par uuid not null references public.profiles (id),
  publiee_le timestamptz not null default now(),
  masquee_le timestamptz,
  masquee_par uuid references public.profiles (id),
  motif_masquage text,
  constraint annonces_portee_cible check (
    (portee = 'ecole' and niveau_id is null and classe_id is null)
    or (portee = 'niveau' and niveau_id is not null and classe_id is null)
    or (portee = 'classe' and classe_id is not null and niveau_id is null))
);
create index if not exists idx_annonces_ecole on public.annonces_ecole (etablissement_id, publiee_le desc);

-- Destinataires figés : un compte par élève concerné (le même parent avec
-- deux enfants a deux lignes, une par élève : « famille » = élève).
create table if not exists public.annonces_destinataires (
  annonce_id uuid not null references public.annonces_ecole (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  primary key (annonce_id, profile_id, fiche_eleve_id)
);
create index if not exists idx_annonces_dest_profil on public.annonces_destinataires (profile_id);

create table if not exists public.annonces_lectures (
  annonce_id uuid not null references public.annonces_ecole (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  lue_le timestamptz not null default now(),
  primary key (annonce_id, profile_id)
);

alter table public.annonces_ecole enable row level security;
alter table public.annonces_destinataires enable row level security;
alter table public.annonces_lectures enable row level security;

-- Contrôles d'accès hors RLS (SECURITY DEFINER) : les politiques des deux
-- tables ne se référencent pas l'une l'autre (pas de récursion).
create or replace function public.annonce_dirigee(p_annonce uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select public.est_direction(a.etablissement_id) from public.annonces_ecole a where a.id = p_annonce), false);
$$;

create or replace function public.annonce_recue(p_annonce uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.annonces_ecole a
    join public.annonces_destinataires d on d.annonce_id = a.id
    where a.id = p_annonce and a.masquee_le is null and d.profile_id = auth.uid());
$$;
revoke execute on function public.annonce_dirigee(uuid), public.annonce_recue(uuid) from public, anon;
grant execute on function public.annonce_dirigee(uuid), public.annonce_recue(uuid) to authenticated;

-- Lecture directe : la direction de l'école, ou un destinataire d'une
-- annonce non masquée. Aucune politique d'écriture : fonctions seulement.
drop policy if exists annonces_select on public.annonces_ecole;
create policy annonces_select on public.annonces_ecole for select using (
  public.annonce_dirigee(id) or public.annonce_recue(id));

drop policy if exists annonces_dest_select on public.annonces_destinataires;
create policy annonces_dest_select on public.annonces_destinataires for select using (
  profile_id = auth.uid() or public.annonce_dirigee(annonce_id));

drop policy if exists annonces_lectures_select on public.annonces_lectures;
create policy annonces_lectures_select on public.annonces_lectures for select using (
  profile_id = auth.uid() or public.annonce_dirigee(annonce_id));

revoke insert, update, delete on public.annonces_ecole, public.annonces_destinataires, public.annonces_lectures
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Publication
-- ---------------------------------------------------------------------------
create or replace function public.publier_annonce(
  p_id uuid,
  p_etablissement uuid,
  p_portee text,
  p_cible uuid,
  p_titre text,
  p_corps text,
  p_importante boolean default false,
  p_par_sms boolean default false
)
returns jsonb
language plpgsql volatile
security definer
set search_path = public
as $$
declare
  v_existe record;
  v_annee uuid;
  v_ecole text;
  v_familles integer;
  v_push integer := 0;
  v_sms integer := 0;
  v_sms_refuses integer := 0;
  d record;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  -- Renvoi d'une publication déjà reçue (réseau revenu) : rien ne repart.
  select etablissement_id, publiee_par into v_existe from public.annonces_ecole where id = p_id;
  if found then
    if v_existe.etablissement_id <> p_etablissement or v_existe.publiee_par <> auth.uid() then
      raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
    end if;
    return jsonb_build_object('id', p_id, 'deja_recue', true);
  end if;

  if p_portee not in ('ecole', 'niveau', 'classe') or (p_portee <> 'ecole' and p_cible is null) then
    raise exception 'PORTEE_INVALIDE' using errcode = '22023';
  end if;
  if p_portee = 'classe' and not exists (
      select 1 from public.classes c where c.id = p_cible and c.etablissement_id = p_etablissement and c.deleted_at is null) then
    raise exception 'PORTEE_INVALIDE' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_titre, ''))) < 3 or char_length(trim(coalesce(p_corps, ''))) < 3 then
    raise exception 'TEXTE_TROP_COURT' using errcode = '22023';
  end if;

  select id into v_annee from public.annees_scolaires
   where etablissement_id = p_etablissement and courante limit 1;

  insert into public.annonces_ecole
    (id, etablissement_id, portee, niveau_id, classe_id, titre, corps, importante, par_sms, publiee_par)
  values
    (p_id, p_etablissement, p_portee,
     case when p_portee = 'niveau' then p_cible end,
     case when p_portee = 'classe' then p_cible end,
     trim(p_titre), trim(p_corps), coalesce(p_importante, false), coalesce(p_par_sms, false), auth.uid());

  -- Élèves concernés : inscription active de l'année courante dans la portée.
  insert into public.annonces_destinataires (annonce_id, profile_id, fiche_eleve_id)
  select distinct p_id, dest.profile_id, f.id
  from public.inscriptions i
  join public.classes c on c.id = i.classe_id and c.deleted_at is null
  join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
  cross join lateral (
    select r.parent_profile_id as profile_id
    from public.relations_parent_eleve r
    where r.fiche_eleve_id = f.id and r.statut = 'confirmee' and r.autorise and r.deleted_at is null
    union
    select f.profile_id where f.profile_id is not null
  ) dest
  where i.etablissement_id = p_etablissement
    and i.statut = 'active' and i.deleted_at is null
    and (v_annee is null or i.annee_scolaire_id = v_annee)
    and (p_portee = 'ecole'
         or (p_portee = 'niveau' and c.niveau_id = p_cible)
         or (p_portee = 'classe' and c.id = p_cible));

  select count(distinct fiche_eleve_id) into v_familles from public.annonces_destinataires where annonce_id = p_id;
  if v_familles = 0 then
    raise exception 'AUCUN_DESTINATAIRE' using errcode = '22023';
  end if;

  select nom into v_ecole from public.etablissements where id = p_etablissement;
  for d in select distinct ad.profile_id from public.annonces_destinataires ad where ad.annonce_id = p_id loop
    perform public.notifier_push(p_etablissement, d.profile_id, 'annonce_ecole',
      case when p_importante then 'Important — ' else '' end || trim(p_titre),
      jsonb_build_object('annonce_id', p_id));
    v_push := v_push + 1;
  end loop;

  -- SMS : aux parents seulement, sur demande, tant qu'il reste des crédits.
  if coalesce(p_par_sms, false) then
    for d in
      select distinct ad.profile_id
      from public.annonces_destinataires ad
      join public.relations_parent_eleve r
        on r.parent_profile_id = ad.profile_id and r.fiche_eleve_id = ad.fiche_eleve_id
      where ad.annonce_id = p_id
    loop
      if public.envoyer_sms_etablissement(p_etablissement, d.profile_id,
           v_ecole || ' : ' || trim(p_titre) || '. Details dans EcoShop.',
           'annonce:' || p_id::text || ':' || d.profile_id::text) then
        v_sms := v_sms + 1;
      else
        v_sms_refuses := v_sms_refuses + 1;
      end if;
    end loop;
  end if;

  return jsonb_build_object('id', p_id, 'deja_recue', false, 'familles', v_familles,
    'notifications', v_push, 'sms', v_sms, 'sms_non_envoyes', v_sms_refuses);
end;
$$;
revoke execute on function public.publier_annonce(uuid, uuid, text, uuid, text, text, boolean, boolean) from public, anon;
grant execute on function public.publier_annonce(uuid, uuid, text, uuid, text, text, boolean, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Lecture
-- ---------------------------------------------------------------------------
-- Annonces reçues par le compte connecté (toutes écoles), non masquées.
create or replace function public.mes_annonces()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'etablissement_id', a.etablissement_id, 'etablissement', e.nom,
      'titre', a.titre, 'corps', a.corps, 'importante', a.importante, 'portee', a.portee,
      'classe', c.nom, 'niveau', n.nom, 'publiee_le', a.publiee_le,
      'lue', exists (select 1 from public.annonces_lectures l where l.annonce_id = a.id and l.profile_id = auth.uid())
    ) order by a.publiee_le desc), '[]'::jsonb)
  from public.annonces_ecole a
  join public.etablissements e on e.id = a.etablissement_id
  left join public.classes c on c.id = a.classe_id
  left join public.niveaux_educatifs n on n.id = a.niveau_id
  where a.masquee_le is null
    and exists (select 1 from public.annonces_destinataires d where d.annonce_id = a.id and d.profile_id = auth.uid());
$$;
revoke execute on function public.mes_annonces() from public, anon;
grant execute on function public.mes_annonces() to authenticated;

create or replace function public.marquer_annonce_lue(p_annonce uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if not exists (
      select 1 from public.annonces_ecole a
      join public.annonces_destinataires d on d.annonce_id = a.id and d.profile_id = auth.uid()
      where a.id = p_annonce and a.masquee_le is null) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  insert into public.annonces_lectures (annonce_id, profile_id) values (p_annonce, auth.uid())
  on conflict do nothing;
end;
$$;
revoke execute on function public.marquer_annonce_lue(uuid) from public, anon;
grant execute on function public.marquer_annonce_lue(uuid) to authenticated;

-- Annonces de l'école pour la direction, avec le nombre de familles qui ont
-- lu (au moins un parent ou l'élève) et les masquées.
create or replace function public.annonces_etablissement(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'etablissement_id', a.etablissement_id, 'titre', a.titre, 'corps', a.corps,
      'importante', a.importante, 'portee', a.portee, 'classe', c.nom, 'niveau', n.nom,
      'par_sms', a.par_sms, 'publiee_le', a.publiee_le,
      'familles', (select count(distinct d.fiche_eleve_id) from public.annonces_destinataires d where d.annonce_id = a.id),
      'familles_lues', (select count(distinct d.fiche_eleve_id) from public.annonces_destinataires d
                        join public.annonces_lectures l on l.annonce_id = d.annonce_id and l.profile_id = d.profile_id
                        where d.annonce_id = a.id),
      'masquee_le', a.masquee_le, 'motif_masquage', a.motif_masquage
    ) order by a.publiee_le desc), '[]'::jsonb)
    from (select * from public.annonces_ecole where etablissement_id = p_etablissement
          order by publiee_le desc limit 200) a
    left join public.classes c on c.id = a.classe_id
    left join public.niveaux_educatifs n on n.id = a.niveau_id);
end;
$$;
revoke execute on function public.annonces_etablissement(uuid) from public, anon;
grant execute on function public.annonces_etablissement(uuid) to authenticated;

-- Classes et niveaux de l'année courante, pour choisir la portée.
create or replace function public.portees_annonce(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_annee uuid;
begin
  if not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select id into v_annee from public.annees_scolaires where etablissement_id = p_etablissement and courante limit 1;
  return jsonb_build_object(
    'classes', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nom', c.nom) order by c.nom), '[]'::jsonb)
                from public.classes c
                where c.etablissement_id = p_etablissement and c.deleted_at is null and c.actif
                  and (v_annee is null or c.annee_scolaire_id = v_annee)),
    'niveaux', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', n.id, 'nom', n.nom)), '[]'::jsonb)
                from public.classes c join public.niveaux_educatifs n on n.id = c.niveau_id
                where c.etablissement_id = p_etablissement and c.deleted_at is null and c.actif
                  and (v_annee is null or c.annee_scolaire_id = v_annee)));
end;
$$;
revoke execute on function public.portees_annonce(uuid) from public, anon;
grant execute on function public.portees_annonce(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Modération
-- ---------------------------------------------------------------------------
create or replace function public.masquer_annonce(p_annonce uuid, p_motif text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  a record;
begin
  select * into a from public.annonces_ecole where id = p_annonce for update;
  if not found or not coalesce(public.est_direction(a.etablissement_id), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_motif, ''))) < 3 then
    raise exception 'MOTIF_REQUIS' using errcode = '22023';
  end if;
  if a.masquee_le is not null then
    return;
  end if;
  update public.annonces_ecole
     set masquee_le = now(), masquee_par = auth.uid(), motif_masquage = trim(p_motif)
   where id = p_annonce;
  perform public.enregistrer_audit(a.etablissement_id, 'annonce', a.id, 'masquee',
    jsonb_build_object('masquee', false),
    jsonb_build_object('masquee', true, 'motif', trim(p_motif), 'titre', a.titre));
end;
$$;
revoke execute on function public.masquer_annonce(uuid, text) from public, anon;
grant execute on function public.masquer_annonce(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Journal d'audit : l'entité « annonce » est visible par la direction
-- ---------------------------------------------------------------------------
create or replace function public.journal_audit_visible(p_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare v_row public.journal_audit;
begin
  select * into v_row from public.journal_audit where id = p_id;
  if v_row.id is null then
    return false;
  end if;

  return case v_row.entite
    when 'inscription' then
      public.fiche_visible(v_row.fiche_eleve_id)
    when 'sanction' then
      public.sanction_visible(v_row.entite_id)
    when 'conge' then
      exists (
        select 1 from public.conges c
        where c.id = v_row.entite_id
          and (public.est_employe_self(c.employe_id) or public.est_rh(c.etablissement_id))
      )
      or coalesce(public.est_admin_gsg(), false)
    when 'transaction_cinetpay' then
      coalesce(public.est_personnel(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'transaction_mobile_money' then
      coalesce(public.est_personnel(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'paiement_marketplace' then
      coalesce(public.est_membre_actif(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'commande_marketplace' then
      exists (
        select 1 from public.commandes c
        where c.id = v_row.entite_id and c.profile_id = auth.uid()
      )
      or coalesce(public.est_membre_actif(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'encaissement_scolarite' then
      public.encaissement_visible(v_row.entite_id)
    when 'abonnement_premium_eleve' then
      exists (
        select 1 from public.fiches_eleves f
        where f.id = v_row.fiche_eleve_id and f.profile_id = auth.uid()
      )
      or public.est_parent_confirme(v_row.fiche_eleve_id)
      or coalesce(public.est_admin_gsg(), false)
    when 'message_groupe' then
      public.moderateur_groupe(v_row.groupe_id)
    when 'annonce' then
      coalesce(public.est_direction(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    else false
  end;
end;
$$;
