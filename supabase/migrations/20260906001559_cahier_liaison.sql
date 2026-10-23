-- ============================================================================
-- EcoShop — Cahier de liaison (REG-19, lot 2)
--
-- Remplace le prototype local « Cahier de liaison » (rien ne partait).
--
--   1. L'enseignant affecté à la classe de l'élève (année courante) ou la
--      direction de l'école écrit un mot au sujet d'un élève. Chaque message
--      reste rattaché à cet élève.
--   2. Seuls les parents **confirmés** de cet élève le voient (ni l'élève, ni
--      un parent en attente, ni une autre famille, ni une autre école). Ils
--      confirment la lecture (la « signature » du cahier papier) et peuvent
--      répondre en texte ; le personnel autorisé peut répondre aussi.
--   3. Notification push : aux parents pour un message du personnel ; à
--      l'auteur du mot pour une réponse d'un parent.
--   4. Modération : la direction masque un message (raison obligatoire) ;
--      il disparaît pour les parents, jamais supprimé, et l'action est
--      inscrite au journal d'audit.
--
-- Clés fournies par l'appareil (écriture sans réseau, renvoi sans doublon).
-- Aucune écriture directe : fonctions seulement. Migration idempotente.
-- ============================================================================

alter type public.type_entite_journal_audit add value if not exists 'mot_liaison';

create table if not exists public.messages_liaison (
  id uuid primary key,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  -- Null : mot qui ouvre un fil ; sinon réponse à ce mot.
  mot_id uuid references public.messages_liaison (id) on delete cascade,
  auteur_id uuid not null references public.profiles (id),
  auteur_parent boolean not null default false,
  corps text not null check (char_length(trim(corps)) between 1 and 2000),
  cree_le timestamptz not null default now(),
  masque_le timestamptz,
  masque_par uuid references public.profiles (id),
  motif_masquage text
);
create index if not exists idx_liaison_fiche on public.messages_liaison (fiche_eleve_id, cree_le desc);
create index if not exists idx_liaison_mot on public.messages_liaison (mot_id) where mot_id is not null;

create table if not exists public.lectures_liaison (
  message_id uuid not null references public.messages_liaison (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  lu_le timestamptz not null default now(),
  primary key (message_id, profile_id)
);

alter table public.messages_liaison enable row level security;
alter table public.lectures_liaison enable row level security;
revoke insert, update, delete on public.messages_liaison, public.lectures_liaison from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Droits
-- ---------------------------------------------------------------------------
-- Personnel qui peut écrire au sujet de l'élève : direction de son école, ou
-- enseignant affecté à sa classe de l'année courante.
create or replace function public.ecrit_liaison(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.fiches_eleves f
    where f.id = p_fiche and f.deleted_at is null
      and (coalesce(public.est_direction(f.etablissement_id), false)
           or exists (
             select 1 from public.inscriptions i
             join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
             where i.fiche_eleve_id = f.id and i.statut = 'active' and i.deleted_at is null
               and public.est_enseignant_affecte(i.classe_id))));
$$;

-- Lit le fil : personnel autorisé (tout, masqués compris) ou parent confirmé
-- (messages non masqués).
create or replace function public.liaison_visible(p_message uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.messages_liaison m
    where m.id = p_message
      and (public.ecrit_liaison(m.fiche_eleve_id)
           or (m.masque_le is null and public.est_parent_confirme(m.fiche_eleve_id))));
$$;
revoke execute on function public.ecrit_liaison(uuid), public.liaison_visible(uuid) from public, anon;
grant execute on function public.ecrit_liaison(uuid), public.liaison_visible(uuid) to authenticated;

drop policy if exists liaison_select on public.messages_liaison;
create policy liaison_select on public.messages_liaison for select using (public.liaison_visible(id));

drop policy if exists liaison_lectures_select on public.lectures_liaison;
create policy liaison_lectures_select on public.lectures_liaison for select using (
  profile_id = auth.uid()
  or exists (select 1 from public.messages_liaison m where m.id = message_id and public.ecrit_liaison(m.fiche_eleve_id)));

-- ---------------------------------------------------------------------------
-- 2. Écrire, répondre
-- ---------------------------------------------------------------------------
create or replace function public.parents_confirmes(p_fiche uuid)
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select r.parent_profile_id from public.relations_parent_eleve r
  where r.fiche_eleve_id = p_fiche and r.statut = 'confirmee' and r.autorise and r.deleted_at is null;
$$;
revoke execute on function public.parents_confirmes(uuid) from public, anon, authenticated;

-- Renvoi d'un message déjà reçu (même clé) : rien ne repart.
create or replace function public.message_liaison_deja_recu(p_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_auteur uuid;
begin
  select auteur_id into v_auteur from public.messages_liaison where id = p_id;
  if not found then
    return false;
  end if;
  if v_auteur <> auth.uid() then
    raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
  end if;
  return true;
end;
$$;
revoke execute on function public.message_liaison_deja_recu(uuid) from public, anon, authenticated;

create or replace function public.ecrire_mot_liaison(p_id uuid, p_fiche uuid, p_corps text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_eleve text;
  v_n integer := 0;
  d uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if public.message_liaison_deja_recu(p_id) then
    return jsonb_build_object('id', p_id, 'deja_recu', true);
  end if;
  if not public.ecrit_liaison(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_corps, ''))) < 1 then
    raise exception 'TEXTE_VIDE' using errcode = '22023';
  end if;
  select etablissement_id, prenom into v_etab, v_eleve from public.fiches_eleves where id = p_fiche;

  insert into public.messages_liaison (id, etablissement_id, fiche_eleve_id, auteur_id, corps)
  values (p_id, v_etab, p_fiche, auth.uid(), trim(p_corps));

  for d in select * from public.parents_confirmes(p_fiche) loop
    perform public.notifier_push(v_etab, d, 'cahier_liaison',
      'Cahier de liaison de ' || coalesce(v_eleve, 'votre enfant') || ' : nouveau mot',
      jsonb_build_object('message_id', p_id, 'fiche_eleve_id', p_fiche));
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('id', p_id, 'deja_recu', false, 'parents', v_n);
end;
$$;
revoke execute on function public.ecrire_mot_liaison(uuid, uuid, text) from public, anon;
grant execute on function public.ecrire_mot_liaison(uuid, uuid, text) to authenticated;

create or replace function public.repondre_liaison(p_id uuid, p_mot uuid, p_corps text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  m record;
  v_parent boolean;
  v_eleve text;
  d uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if public.message_liaison_deja_recu(p_id) then
    return jsonb_build_object('id', p_id, 'deja_recu', true);
  end if;
  select * into m from public.messages_liaison where id = p_mot and mot_id is null;
  if not found then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  v_parent := public.est_parent_confirme(m.fiche_eleve_id);
  if not v_parent and not public.ecrit_liaison(m.fiche_eleve_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if v_parent and m.masque_le is not null then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_corps, ''))) < 1 then
    raise exception 'TEXTE_VIDE' using errcode = '22023';
  end if;

  insert into public.messages_liaison (id, etablissement_id, fiche_eleve_id, mot_id, auteur_id, auteur_parent, corps)
  values (p_id, m.etablissement_id, m.fiche_eleve_id, p_mot, auth.uid(), v_parent, trim(p_corps));

  select prenom into v_eleve from public.fiches_eleves where id = m.fiche_eleve_id;
  if v_parent then
    -- Réponse d'un parent : l'auteur du mot est prévenu.
    if m.auteur_id <> auth.uid() then
      perform public.notifier_push(m.etablissement_id, m.auteur_id, 'cahier_liaison',
        'Cahier de liaison de ' || coalesce(v_eleve, 'l''élève') || ' : réponse d''un parent',
        jsonb_build_object('message_id', p_id, 'mot_id', p_mot, 'fiche_eleve_id', m.fiche_eleve_id));
    end if;
  else
    for d in select * from public.parents_confirmes(m.fiche_eleve_id) loop
      perform public.notifier_push(m.etablissement_id, d, 'cahier_liaison',
        'Cahier de liaison de ' || coalesce(v_eleve, 'votre enfant') || ' : nouvelle réponse',
        jsonb_build_object('message_id', p_id, 'mot_id', p_mot, 'fiche_eleve_id', m.fiche_eleve_id));
    end loop;
  end if;
  return jsonb_build_object('id', p_id, 'deja_recu', false);
end;
$$;
revoke execute on function public.repondre_liaison(uuid, uuid, text) from public, anon;
grant execute on function public.repondre_liaison(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Lire, confirmer la lecture
-- ---------------------------------------------------------------------------
-- Fil d'un élève : mots (récents d'abord) et leurs réponses (dans l'ordre).
-- Parent confirmé : messages non masqués ; personnel autorisé : tout, avec le
-- nombre de parents qui ont confirmé la lecture.
create or replace function public.cahier_liaison(p_fiche uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_personnel boolean := public.ecrit_liaison(p_fiche);
  v_parents integer;
begin
  if not v_personnel and not public.est_parent_confirme(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select count(*) into v_parents from public.parents_confirmes(p_fiche);
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id, 'fiche_eleve_id', m.fiche_eleve_id, 'corps', m.corps, 'cree_le', m.cree_le,
        'auteur', public.nom_profil(m.auteur_id), 'de_moi', m.auteur_id = auth.uid(),
        'masque_le', m.masque_le, 'motif_masquage', case when v_personnel then m.motif_masquage end,
        'lu', exists (select 1 from public.lectures_liaison l where l.message_id = m.id and l.profile_id = auth.uid()),
        'lectures', case when v_personnel then (select count(*) from public.lectures_liaison l where l.message_id = m.id
                                                and l.profile_id in (select * from public.parents_confirmes(p_fiche))) end,
        'parents', case when v_personnel then v_parents end,
        'reponses', (select coalesce(jsonb_agg(jsonb_build_object(
              'id', r.id, 'corps', r.corps, 'cree_le', r.cree_le, 'auteur', public.nom_profil(r.auteur_id),
              'de_moi', r.auteur_id = auth.uid(), 'auteur_parent', r.auteur_parent,
              'masque_le', r.masque_le, 'motif_masquage', case when v_personnel then r.motif_masquage end
            ) order by r.cree_le), '[]'::jsonb)
            from public.messages_liaison r
            where r.mot_id = m.id and (v_personnel or r.masque_le is null))
      ) order by m.cree_le desc), '[]'::jsonb)
    from public.messages_liaison m
    where m.fiche_eleve_id = p_fiche and m.mot_id is null and (v_personnel or m.masque_le is null));
end;
$$;
revoke execute on function public.cahier_liaison(uuid) from public, anon;
grant execute on function public.cahier_liaison(uuid) to authenticated;

-- Nom affiché d'un compte (prénom nom).
create or replace function public.nom_profil(p_profil uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), '') from public.profiles p where p.id = p_profil;
$$;
revoke execute on function public.nom_profil(uuid) from public, anon, authenticated;

create or replace function public.confirmer_lecture_liaison(p_message uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if not exists (select 1 from public.messages_liaison m
                 where m.id = p_message and m.masque_le is null and public.est_parent_confirme(m.fiche_eleve_id)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  insert into public.lectures_liaison (message_id, profile_id) values (p_message, auth.uid())
  on conflict do nothing;
end;
$$;
revoke execute on function public.confirmer_lecture_liaison(uuid) from public, anon;
grant execute on function public.confirmer_lecture_liaison(uuid) to authenticated;

-- Élèves du cahier pour le compte connecté : ses enfants (parent confirmé),
-- ou les élèves sur lesquels il peut écrire dans cette école (personnel),
-- avec le nombre de messages non lus pour un parent et de réponses de
-- parents des 7 derniers jours pour le personnel.
create or replace function public.eleves_cahier_liaison(p_etablissement uuid default null)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(x order by x ->> 'classe', x ->> 'nom'), '[]'::jsonb) from (
    select jsonb_build_object(
      'fiche_eleve_id', f.id, 'nom', trim(coalesce(f.prenom, '') || ' ' || coalesce(f.nom, '')),
      'classe', (select c.nom from public.inscriptions i join public.classes c on c.id = i.classe_id
                 join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
                 where i.fiche_eleve_id = f.id and i.statut = 'active' and i.deleted_at is null limit 1),
      'etablissement_id', f.etablissement_id,
      'a_lire', case when public.est_parent_confirme(f.id) then
          (select count(*) from public.messages_liaison m
           where m.fiche_eleve_id = f.id and m.masque_le is null and not m.auteur_parent
             and not exists (select 1 from public.lectures_liaison l where l.message_id = m.id and l.profile_id = auth.uid()))
        else
          (select count(*) from public.messages_liaison m
           where m.fiche_eleve_id = f.id and m.auteur_parent and m.cree_le > now() - interval '7 days')
        end) as x
    from public.fiches_eleves f
    where f.deleted_at is null
      and ((p_etablissement is null and public.est_parent_confirme(f.id))
           or (p_etablissement is not null and f.etablissement_id = p_etablissement and public.ecrit_liaison(f.id)))
  ) s;
$$;
revoke execute on function public.eleves_cahier_liaison(uuid) from public, anon;
grant execute on function public.eleves_cahier_liaison(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Modération
-- ---------------------------------------------------------------------------
create or replace function public.masquer_message_liaison(p_message uuid, p_motif text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  m record;
begin
  select * into m from public.messages_liaison where id = p_message for update;
  if not found or not coalesce(public.est_direction(m.etablissement_id), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_motif, ''))) < 3 then
    raise exception 'MOTIF_REQUIS' using errcode = '22023';
  end if;
  if m.masque_le is not null then
    return;
  end if;
  update public.messages_liaison
     set masque_le = now(), masque_par = auth.uid(), motif_masquage = trim(p_motif)
   where id = p_message;
  perform public.enregistrer_audit(m.etablissement_id, 'mot_liaison', m.id, 'masque',
    jsonb_build_object('masque', false),
    jsonb_build_object('masque', true, 'motif', trim(p_motif), 'reponse', m.mot_id is not null),
    m.fiche_eleve_id);
end;
$$;
revoke execute on function public.masquer_message_liaison(uuid, text) from public, anon;
grant execute on function public.masquer_message_liaison(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Journal d'audit : « mot_liaison » visible par la direction
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
    when 'mot_liaison' then
      coalesce(public.est_direction(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    else false
  end;
end;
$$;
