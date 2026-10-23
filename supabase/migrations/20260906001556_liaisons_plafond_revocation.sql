-- ============================================================================
-- EcoShop — Comptes multiples : protections à la liaison (REG-18, partie E)
--
-- Une adresse e-mail se crée en deux minutes : empêcher les comptes
-- multiples à l'inscription est illusoire. La protection se place à la
-- liaison d'un compte à une fiche d'élève :
--
--   1. la direction est prévenue (notification + liste dans son tableau de
--      bord) de chaque compte nouvellement lié à un élève de son école, et
--      peut révoquer la liaison ;
--   2. plafond de comptes parents par fiche, réglable par l'école (2 par
--      défaut ; le compte de l'élève est à part, un seul par fiche). Au-delà,
--      la liaison est créée « en attente » : elle ne donne aucun accès tant
--      que la direction ne l'a pas acceptée (`est_parent_confirme` exige
--      déjà statut = 'confirmee').
--
-- Une liaison révoquée ou refusée ne se reconfirme jamais seule : refaire
-- la liaison la remet « en attente » de la direction.
-- Rien ne change pour le personnel (invitation).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Réglage de l'école et suivi des liaisons
-- ---------------------------------------------------------------------------
alter table public.etablissements
  add column if not exists plafond_parents_par_fiche smallint not null default 2
    check (plafond_parents_par_fiche between 1 and 10);

comment on column public.etablissements.plafond_parents_par_fiche is
  'REG-18 : nombre de comptes parents confirmés par fiche d''élève. Au-delà, la liaison attend l''accord de la direction.';

alter table public.relations_parent_eleve
  add column if not exists liee_le timestamptz,
  add column if not exists decidee_par uuid references public.profiles (id) on delete set null,
  add column if not exists decidee_le timestamptz,
  add column if not exists revoquee_le timestamptz;

update public.relations_parent_eleve set liee_le = created_at where liee_le is null;

-- ---------------------------------------------------------------------------
-- 2. Notification de la direction
-- ---------------------------------------------------------------------------
create or replace function public.notifier_direction_liaison(
  p_etablissement uuid, p_fiche uuid, p_compte uuid, p_nature text, p_statut text, p_liaison uuid)
returns void
language plpgsql volatile
security definer
set search_path = public
as $$
declare
  v_eleve text;
  v_compte text;
  v_contenu text;
begin
  select trim(coalesce(f.prenom, '') || ' ' || coalesce(f.nom, '')) into v_eleve
  from public.fiches_eleves f where f.id = p_fiche;
  select coalesce(nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), ''), p.identifiant_ecoshop)
    into v_compte
  from public.profiles p where p.id = p_compte;

  v_contenu := case
    when p_statut = 'en_attente' then
      format('Compte parent en attente de votre accord pour %s (%s).', v_eleve, v_compte)
    when p_nature = 'eleve' then
      format('Compte élève lié à la fiche de %s (%s).', v_eleve, v_compte)
    else
      format('Nouveau compte parent lié à %s (%s).', v_eleve, v_compte)
  end;

  insert into public.notifications (etablissement_id, destinataire, type, canal, contenu, variables, statut)
  select distinct p_etablissement, m.profile_id, 'liaison_compte', 'push'::public.canal_notification, v_contenu,
         jsonb_build_object('nature', p_nature, 'statut', p_statut, 'liaison_id', p_liaison,
                            'fiche_eleve_id', p_fiche, 'compte_id', p_compte),
         'en_attente'::public.statut_notification
  from public.etablissements_membres m
  where m.etablissement_id = p_etablissement
    and m.role_dans_etablissement in ('direction', 'fondateur_reseau')
    and m.actif and m.deleted_at is null;
end;
$$;
revoke execute on function public.notifier_direction_liaison(uuid, uuid, uuid, text, text, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Liaison parent : plafond, attente, notification
-- ---------------------------------------------------------------------------
create or replace function public.lier_parent_a_fiche(
  p_matricule text,
  p_date_naissance date,
  p_type public.type_relation_parentale default 'parent'
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_fiche record;
  v_existante record;
  v_relation_id uuid;
  v_echecs int;
  v_confirmes int;
  v_statut public.statut_relation;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  if (select role_racine from public.profiles where id = auth.uid()) is distinct from 'parent' then
    raise exception 'ROLE_PARENT_REQUIS' using errcode = '42501';
  end if;

  select count(*) into v_echecs
  from public.tentatives_liaison
  where profile_id = auth.uid() and not reussie
    and created_at > now() - interval '1 hour';

  if v_echecs >= 5 then
    raise exception 'TROP_DE_TENTATIVES' using errcode = '54000';
  end if;

  select f.id, f.etablissement_id into v_fiche
  from public.fiches_eleves f
  where f.matricule = trim(p_matricule)
    and f.date_naissance = p_date_naissance
    and f.deleted_at is null
  limit 1;

  if v_fiche.id is null then
    insert into public.tentatives_liaison (profile_id, matricule_essaye, reussie)
    values (auth.uid(), trim(p_matricule), false);
    raise exception 'LIAISON_IMPOSSIBLE' using errcode = '42501';
  end if;

  insert into public.tentatives_liaison (profile_id, matricule_essaye, reussie)
  values (auth.uid(), trim(p_matricule), true);

  -- Plafond par fiche : verrou pour que deux liaisons simultanées ne le
  -- dépassent pas ensemble.
  perform 1 from public.fiches_eleves where id = v_fiche.id for update;

  select r.id, r.statut, r.autorise, r.deleted_at, r.revoquee_le into v_existante
  from public.relations_parent_eleve r
  where r.parent_profile_id = auth.uid() and r.fiche_eleve_id = v_fiche.id;

  -- Déjà lié et confirmé : rien à faire.
  if v_existante.id is not null and v_existante.statut = 'confirmee'
     and v_existante.autorise and v_existante.deleted_at is null then
    return v_existante.id;
  end if;

  -- Déjà en attente : la direction est déjà prévenue.
  if v_existante.id is not null and v_existante.statut = 'en_attente' and v_existante.deleted_at is null then
    return v_existante.id;
  end if;

  select count(*) into v_confirmes
  from public.relations_parent_eleve r
  where r.fiche_eleve_id = v_fiche.id
    and r.parent_profile_id <> auth.uid()
    and r.statut = 'confirmee' and r.autorise and r.deleted_at is null;

  v_statut := case
    -- Révoquée ou refusée par l'école : jamais reconfirmée seule.
    when v_existante.id is not null and (v_existante.revoquee_le is not null or v_existante.statut = 'refusee')
      then 'en_attente'
    when v_confirmes >= (select e.plafond_parents_par_fiche from public.etablissements e where e.id = v_fiche.etablissement_id)
      then 'en_attente'
    else 'confirmee'
  end;

  insert into public.relations_parent_eleve
    (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise, liee_le)
  values (v_fiche.etablissement_id, auth.uid(), v_fiche.id, p_type, v_statut, true, now())
  on conflict (parent_profile_id, fiche_eleve_id) do update
    set statut = excluded.statut, type_relation = excluded.type_relation,
        autorise = true, deleted_at = null, liee_le = now(),
        decidee_par = null, decidee_le = null
  returning id into v_relation_id;

  perform public.notifier_direction_liaison(v_fiche.etablissement_id, v_fiche.id, auth.uid(),
                                            'parent', v_statut::text, v_relation_id);
  return v_relation_id;
end $$;

revoke execute on function public.lier_parent_a_fiche(text, date, public.type_relation_parentale) from public, anon;
grant execute on function public.lier_parent_a_fiche(text, date, public.type_relation_parentale) to authenticated;

-- Statut de mes liaisons (écran du parent : « en attente de l'école »).
create or replace function public.statut_ma_liaison(p_relation uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select r.statut::text from public.relations_parent_eleve r
  where r.id = p_relation and r.parent_profile_id = auth.uid() and r.deleted_at is null;
$$;
revoke execute on function public.statut_ma_liaison(uuid) from public, anon;
grant execute on function public.statut_ma_liaison(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Liaison élève : notification de la direction
-- ---------------------------------------------------------------------------
create or replace function public.lier_compte_a_fiche(
  p_matricule text,
  p_date_naissance date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fiche_id uuid;
  v_etab     uuid;
  v_echecs   int;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  select count(*) into v_echecs
  from public.tentatives_liaison
  where profile_id = auth.uid()
    and not reussie
    and created_at > now() - interval '1 hour';

  if v_echecs >= 5 then
    raise exception 'TROP_DE_TENTATIVES' using errcode = '54000';
  end if;

  select id, etablissement_id into v_fiche_id, v_etab
  from public.fiches_eleves
  where matricule = trim(p_matricule)
    and date_naissance = p_date_naissance
    and profile_id is null
    and deleted_at is null
  limit 1;

  -- Réponse volontairement indifférenciée (pas d'oracle d'énumération).
  if v_fiche_id is null then
    insert into public.tentatives_liaison (profile_id, matricule_essaye, reussie)
    values (auth.uid(), trim(p_matricule), false);
    raise exception 'LIAISON_IMPOSSIBLE' using errcode = '42501';
  end if;

  update public.fiches_eleves
     set profile_id = auth.uid(), lie_le = now()
   where id = v_fiche_id;

  insert into public.tentatives_liaison (profile_id, matricule_essaye, reussie)
  values (auth.uid(), trim(p_matricule), true);

  insert into public.etablissements_membres
    (profile_id, etablissement_id, role_dans_etablissement)
  values (auth.uid(), v_etab, 'eleve')
  on conflict (profile_id, etablissement_id) do update
    set actif = true, deleted_at = null
    where public.etablissements_membres.role_dans_etablissement = 'eleve';

  perform public.notifier_direction_liaison(v_etab, v_fiche_id, auth.uid(), 'eleve', 'confirmee', v_fiche_id);
  return v_fiche_id;
end;
$$;
revoke execute on function public.lier_compte_a_fiche(text, date) from public, anon;
grant execute on function public.lier_compte_a_fiche(text, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Tableau de bord de la direction
-- ---------------------------------------------------------------------------
create or replace function public.gere_liaisons(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.est_direction(p_etablissement), false)
      or coalesce(public.a_permission(p_etablissement, 'scolarite.relation.gerer'), false);
$$;
revoke execute on function public.gere_liaisons(uuid) from public, anon;
grant execute on function public.gere_liaisons(uuid) to authenticated;

-- Liaisons récentes (p_jours) et toutes celles en attente.
create or replace function public.liaisons_comptes(p_etablissement uuid, p_jours integer default 30)
returns table (
  nature text, liaison_id uuid, fiche_eleve_id uuid, eleve text, compte_id uuid,
  compte text, identifiant_ecoshop text, statut text, liee_le timestamptz)
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.gere_liaisons(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return query
  select 'parent'::text, r.id, f.id, trim(coalesce(f.prenom, '') || ' ' || coalesce(f.nom, '')),
         p.id, trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), p.identifiant_ecoshop,
         case when r.revoquee_le is not null and r.statut <> 'en_attente' then 'revoquee' else r.statut::text end,
         r.liee_le
  from public.relations_parent_eleve r
  join public.fiches_eleves f on f.id = r.fiche_eleve_id
  join public.profiles p on p.id = r.parent_profile_id
  where r.etablissement_id = p_etablissement and r.deleted_at is null
    and (r.statut = 'en_attente' or r.liee_le > now() - make_interval(days => greatest(1, least(coalesce(p_jours, 30), 365))))
  union all
  select 'eleve'::text, f.id, f.id, trim(coalesce(f.prenom, '') || ' ' || coalesce(f.nom, '')),
         p.id, trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), p.identifiant_ecoshop,
         'confirmee'::text, f.lie_le
  from public.fiches_eleves f
  join public.profiles p on p.id = f.profile_id
  where f.etablissement_id = p_etablissement and f.deleted_at is null
    and f.lie_le > now() - make_interval(days => greatest(1, least(coalesce(p_jours, 30), 365)))
  order by 9 desc;
end;
$$;
revoke execute on function public.liaisons_comptes(uuid, integer) from public, anon;
grant execute on function public.liaisons_comptes(uuid, integer) to authenticated;

-- Accepter ou refuser une liaison parent en attente.
create or replace function public.decider_liaison_parent(p_relation uuid, p_accepter boolean)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  r record;
begin
  select * into r from public.relations_parent_eleve where id = p_relation and deleted_at is null for update;
  if not found or not public.gere_liaisons(r.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if r.statut <> 'en_attente' then
    raise exception 'LIAISON_DEJA_TRAITEE' using errcode = '22023';
  end if;

  update public.relations_parent_eleve
     set statut = case when coalesce(p_accepter, false) then 'confirmee'::public.statut_relation
                       else 'refusee'::public.statut_relation end,
         autorise = coalesce(p_accepter, false),
         revoquee_le = case when coalesce(p_accepter, false) then null else revoquee_le end,
         decidee_par = auth.uid(), decidee_le = now()
   where id = p_relation;

  insert into public.notifications (etablissement_id, destinataire, type, canal, contenu, variables, statut)
  values (r.etablissement_id, r.parent_profile_id, 'liaison_compte', 'push',
          case when coalesce(p_accepter, false)
               then 'L''école a accepté votre liaison : la scolarité de votre enfant est disponible.'
               else 'L''école n''a pas accepté votre liaison. Rapprochez-vous du secrétariat.' end,
          jsonb_build_object('liaison_id', r.id, 'statut', case when coalesce(p_accepter, false) then 'confirmee' else 'refusee' end),
          'en_attente');

  return case when coalesce(p_accepter, false) then 'confirmee' else 'refusee' end;
end;
$$;
revoke execute on function public.decider_liaison_parent(uuid, boolean) from public, anon;
grant execute on function public.decider_liaison_parent(uuid, boolean) to authenticated;

-- Révoquer une liaison parent : plus aucun accès, gardée pour l'historique.
create or replace function public.revoquer_liaison_parent(p_relation uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  r record;
begin
  select * into r from public.relations_parent_eleve where id = p_relation and deleted_at is null for update;
  if not found or not public.gere_liaisons(r.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.relations_parent_eleve
     set statut = 'refusee', autorise = false, revoquee_le = now(),
         decidee_par = auth.uid(), decidee_le = now()
   where id = p_relation;
end;
$$;
revoke execute on function public.revoquer_liaison_parent(uuid) from public, anon;
grant execute on function public.revoquer_liaison_parent(uuid) to authenticated;

-- Révoquer la liaison d'un compte élève : la fiche redevient libre (l'élève
-- la relie avec son matricule et sa date de naissance, la direction est
-- prévenue de nouveau).
create or replace function public.revoquer_liaison_eleve(p_fiche uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  f record;
begin
  select * into f from public.fiches_eleves where id = p_fiche and deleted_at is null for update;
  if not found or not public.gere_liaisons(f.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if f.profile_id is null then
    return;
  end if;

  update public.fiches_eleves set profile_id = null, lie_le = null where id = p_fiche;

  -- Plus membre de l'école s'il n'y a plus aucune fiche liée à ce compte.
  if not exists (select 1 from public.fiches_eleves
                 where profile_id = f.profile_id and etablissement_id = f.etablissement_id and deleted_at is null) then
    update public.etablissements_membres
       set actif = false
     where profile_id = f.profile_id and etablissement_id = f.etablissement_id
       and role_dans_etablissement = 'eleve';
  end if;
end;
$$;
revoke execute on function public.revoquer_liaison_eleve(uuid) from public, anon;
grant execute on function public.revoquer_liaison_eleve(uuid) to authenticated;

-- Plafond de comptes parents par fiche (direction).
create or replace function public.definir_plafond_parents(p_etablissement uuid, p_plafond integer)
returns integer
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not (coalesce(public.est_direction(p_etablissement), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_plafond is null or p_plafond < 1 or p_plafond > 10 then
    raise exception 'PLAFOND_INVALIDE' using errcode = '22023';
  end if;
  update public.etablissements set plafond_parents_par_fiche = p_plafond where id = p_etablissement;
  return p_plafond;
end;
$$;
revoke execute on function public.definir_plafond_parents(uuid, integer) from public, anon;
grant execute on function public.definir_plafond_parents(uuid, integer) to authenticated;

create or replace function public.plafond_parents(p_etablissement uuid)
returns integer
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.gere_liaisons(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return (select plafond_parents_par_fiche from public.etablissements where id = p_etablissement);
end;
$$;
revoke execute on function public.plafond_parents(uuid) from public, anon;
grant execute on function public.plafond_parents(uuid) to authenticated;
