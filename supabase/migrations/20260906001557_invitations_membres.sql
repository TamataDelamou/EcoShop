-- ============================================================================
-- EcoShop — Invitations du personnel et des vendeurs dans l'application
-- (REG-18, suite ; bloquant pour le pilote)
--
-- Jusqu'ici la table `invitations` et `accepter_invitation(jeton)` existaient,
-- mais rien ne permettait d'inviter depuis l'application, ni à l'invité de
-- voir son invitation : le jeton n'était envoyé nulle part.
--
--   1. La direction invite une adresse e-mail (voie privilégiée : un
--      courriel part aussitôt) ou un numéro de téléphone (aucun SMS : la
--      direction prévient la personne), avec un rôle et un poste.
--   2. Après sa connexion, l'invité voit les invitations adressées à ses
--      identifiants (`mes_invitations`) et les accepte ou les refuse
--      (`repondre_invitation`). Règle REG-16 : seul un identifiant **prouvé**
--      vaut ; un numéro simplement déclaré ne permet ni d'accepter ni de
--      refuser (sinon n'importe qui déclarerait le numéro d'un autre pour
--      refuser à sa place). Une adresse e-mail est prouvée par la connexion
--      elle-même ; un numéro, par l'école (« Numéros à confirmer »).
--   3. La direction suit ses invitations et peut en retirer une
--      (`invitations_etablissement`, `revoquer_invitation`) ; elle est
--      prévenue de chaque réponse.
--
-- `accepter_invitation(jeton)` reste en service (lien reçu), avec la même
-- règle, par la fonction interne commune `accepter_invitation_ligne`.
-- Migration idempotente.
-- ============================================================================

alter type public.statut_invitation add value if not exists 'refusee';

alter table public.invitations
  add column if not exists refusee_le timestamptz;

-- ---------------------------------------------------------------------------
-- 0. Normalisation de l'identifiant invité (e-mail en minuscules, E.164)
-- ---------------------------------------------------------------------------
create or replace function public.normaliser_identifiant_invitation(p text)
returns text
language plpgsql immutable
as $$
declare
  v text := trim(coalesce(p, ''));
begin
  if position('@' in v) > 0 then
    v := lower(v);
    return case when v ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then v end;
  end if;
  v := regexp_replace(v, '[\s.\-()]', '', 'g');
  return case when v ~ '^\+[1-9][0-9]{6,14}$' then v end;
end;
$$;

create or replace function public.gere_membres(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.est_direction(p_etablissement), false)
      or coalesce(public.a_permission(p_etablissement, 'etablissement.membre.gerer'), false);
$$;
revoke execute on function public.gere_membres(uuid) from public, anon;
grant execute on function public.gere_membres(uuid) to authenticated;

-- Libellé du rôle pour les messages.
create or replace function public.libelle_role_invitation(p_role public.role_racine)
returns text
language sql immutable
as $$
  select case p_role
    when 'enseignant' then 'Enseignant'
    when 'direction' then 'Direction et administration'
    when 'vendeur' then 'Vendeur'
    else p_role::text
  end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Inviter (direction)
-- ---------------------------------------------------------------------------
create or replace function public.inviter_membre(
  p_etablissement uuid,
  p_identifiant text,
  p_role public.role_racine,
  p_poste uuid default null
)
returns uuid
language plpgsql volatile
security definer
set search_path = public, extensions
as $$
declare
  v_ident text := public.normaliser_identifiant_invitation(p_identifiant);
  v_id uuid;
  v_ecole text;
  v_poste text;
  v_invite_par text;
  v_expire timestamptz := now() + interval '14 days';
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if not public.gere_membres(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('enseignant', 'direction', 'vendeur') then
    raise exception 'ROLE_NON_INVITABLE' using errcode = '22023';
  end if;
  if v_ident is null then
    raise exception 'IDENTIFIANT_INVALIDE' using errcode = '22023';
  end if;
  if p_poste is not null then
    select nom into v_poste from public.postes
     where id = p_poste and etablissement_id = p_etablissement and actif;
    if not found then
      raise exception 'POSTE_INVALIDE' using errcode = '22023';
    end if;
  end if;

  -- Déjà membre actif de cette école sous cet identifiant prouvé.
  if exists (
    select 1 from public.identifiants_comptes ic
    join public.etablissements_membres m on m.profile_id = ic.profile_id
    where ic.valeur = v_ident and ic.verifie_le is not null
      and m.etablissement_id = p_etablissement and m.actif and m.deleted_at is null
      and m.role_dans_etablissement = p_role::text
  ) then
    raise exception 'DEJA_MEMBRE' using errcode = '23505';
  end if;

  -- Une seule invitation en attente par personne et par école : la nouvelle
  -- remplace l'ancienne.
  update public.invitations
     set statut = 'revoquee'
   where etablissement_id = p_etablissement and identifiant_cible = v_ident and statut = 'en_attente';

  insert into public.invitations
    (etablissement_id, role_cible, poste_id, identifiant_cible, jeton_empreinte, invite_par, expire_le)
  values
    (p_etablissement, p_role, p_poste, v_ident,
     encode(digest(gen_random_bytes(32), 'sha256'), 'hex'), auth.uid(), v_expire)
  returning id into v_id;

  -- Courriel à l'invité (voie privilégiée). Par téléphone : aucun SMS, la
  -- direction prévient la personne.
  if position('@' in v_ident) > 0 then
    select nom into v_ecole from public.etablissements where id = p_etablissement;
    select nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), '') into v_invite_par
      from public.profiles p where p.id = auth.uid();
    perform public.mettre_notification_en_file(
      'invitation_membre',
      'invitation:' || v_id::text,
      jsonb_build_object(
        'nom_etablissement', v_ecole,
        'role', public.libelle_role_invitation(p_role),
        'poste', v_poste,
        'invite_par', v_invite_par,
        'adresse', v_ident,
        'expire_le', to_char(v_expire at time zone 'Africa/Conakry', 'DD/MM/YYYY')
      ),
      v_ident
    );
  end if;

  return v_id;
end;
$$;
revoke execute on function public.inviter_membre(uuid, text, public.role_racine, uuid) from public, anon;
grant execute on function public.inviter_membre(uuid, text, public.role_racine, uuid) to authenticated;

-- Postes actifs proposés dans le formulaire d'invitation.
create or replace function public.postes_invitables(p_etablissement uuid)
returns table (id uuid, nom text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.gere_membres(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return query select p.id, p.nom from public.postes p
    where p.etablissement_id = p_etablissement and p.actif order by p.nom;
end;
$$;
revoke execute on function public.postes_invitables(uuid) from public, anon;
grant execute on function public.postes_invitables(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Invitations du compte connecté
-- ---------------------------------------------------------------------------
-- En attente, non expirées, adressées à un identifiant du compte. `verifie`
-- faux : identifiant seulement déclaré, l'invitation est visible mais ne
-- peut être ni acceptée ni refusée avant la vérification par l'école.
create or replace function public.mes_invitations()
returns table (
  id uuid, etablissement_id uuid, etablissement text, role_cible text, poste text,
  invite_par text, identifiant text, par_telephone boolean, verifie boolean, expire_le timestamptz)
language sql stable security definer set search_path = public
as $$
  select i.id, i.etablissement_id, e.nom, i.role_cible::text, po.nom,
         nullif(trim(coalesce(pi.prenom, '') || ' ' || coalesce(pi.nom, '')), ''),
         i.identifiant_cible, position('@' in i.identifiant_cible) = 0,
         bool_or(ic.verifie_le is not null), i.expire_le
  from public.invitations i
  join public.identifiants_comptes ic on ic.valeur = i.identifiant_cible and ic.profile_id = auth.uid()
  join public.etablissements e on e.id = i.etablissement_id
  left join public.postes po on po.id = i.poste_id
  left join public.profiles pi on pi.id = i.invite_par
  where i.statut = 'en_attente' and i.expire_le > now()
  group by i.id, e.nom, po.nom, pi.prenom, pi.nom
  order by i.created_at desc;
$$;
revoke execute on function public.mes_invitations() from public, anon;
grant execute on function public.mes_invitations() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Acceptation (commune au jeton et à l'écran) et refus
-- ---------------------------------------------------------------------------
-- Interne : vérifie et applique l'acceptation de l'invitation verrouillée.
create or replace function public.accepter_invitation_ligne(p_invitation uuid)
returns uuid
language plpgsql volatile
security definer
set search_path = public
as $$
declare
  v_inv record;
  v_membre_id uuid;
begin
  select * into v_inv from public.invitations where id = p_invitation for update;
  if not found then
    raise exception 'INVITATION_INTROUVABLE' using errcode = 'P0002';
  end if;
  if v_inv.statut <> 'en_attente' then
    raise exception 'INVITATION_DEJA_TRAITEE' using errcode = '22023';
  end if;
  if v_inv.expire_le < now() then
    update public.invitations set statut = 'expiree' where id = v_inv.id;
    raise exception 'INVITATION_EXPIREE' using errcode = '22023';
  end if;
  perform public.verifier_destinataire_invitation(v_inv.identifiant_cible);

  insert into public.etablissements_membres
    (profile_id, etablissement_id, role_dans_etablissement, poste_id)
  values
    (auth.uid(), v_inv.etablissement_id, v_inv.role_cible::text, v_inv.poste_id)
  on conflict (profile_id, etablissement_id) do update
    set role_dans_etablissement = excluded.role_dans_etablissement,
        poste_id = excluded.poste_id,
        actif = true,
        deleted_at = null
  returning id into v_membre_id;

  update public.profiles
     set role_racine = v_inv.role_cible
   where id = auth.uid() and role_racine is null;

  update public.invitations
     set statut = 'acceptee', accepte_par = auth.uid(), accepte_le = now()
   where id = v_inv.id;

  perform public.prevenir_reponse_invitation(v_inv.id, true);
  return v_membre_id;
end;
$$;
revoke execute on function public.accepter_invitation_ligne(uuid) from public, anon, authenticated;

-- L'invitation est nominative : elle ne vaut que pour un compte qui a prouvé
-- détenir l'identifiant invité (règle REG-16).
create or replace function public.verifier_destinataire_invitation(p_identifiant text)
returns void
language plpgsql stable
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.identifiants_comptes
    where profile_id = auth.uid() and valeur = p_identifiant and verifie_le is not null
  ) then
    if exists (select 1 from public.identifiants_comptes
               where profile_id = auth.uid() and valeur = p_identifiant) then
      raise exception 'IDENTIFIANT_NON_VERIFIE' using errcode = '42501';
    end if;
    raise exception 'INVITATION_AUTRE_DESTINATAIRE' using errcode = '42501';
  end if;
end;
$$;
revoke execute on function public.verifier_destinataire_invitation(text) from public, anon, authenticated;

-- Prévient la personne qui a invité (notification de l'application).
create or replace function public.prevenir_reponse_invitation(p_invitation uuid, p_acceptee boolean)
returns void
language plpgsql volatile
security definer
set search_path = public
as $$
declare
  v_inv record;
  v_qui text;
begin
  select * into v_inv from public.invitations where id = p_invitation;
  if v_inv.invite_par is null then
    return;
  end if;
  select coalesce(nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), ''), v_inv.identifiant_cible)
    into v_qui from public.profiles p where p.id = auth.uid();
  insert into public.notifications (etablissement_id, destinataire, type, canal, contenu, variables, statut)
  values (v_inv.etablissement_id, v_inv.invite_par, 'invitation_reponse', 'push'::public.canal_notification,
          case when p_acceptee
               then format('%s a accepté votre invitation (%s).', v_qui, public.libelle_role_invitation(v_inv.role_cible))
               else format('%s a refusé votre invitation (%s).', v_qui, public.libelle_role_invitation(v_inv.role_cible)) end,
          jsonb_build_object('invitation_id', v_inv.id, 'acceptee', p_acceptee),
          'en_attente'::public.statut_notification);
end;
$$;
revoke execute on function public.prevenir_reponse_invitation(uuid, boolean) from public, anon, authenticated;

-- Lien reçu : même règle, même effet.
create or replace function public.accepter_invitation(p_jeton text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  select id into v_id from public.invitations
   where jeton_empreinte = encode(digest(p_jeton, 'sha256'), 'hex');
  if v_id is null then
    raise exception 'INVITATION_INTROUVABLE' using errcode = 'P0002';
  end if;
  return public.accepter_invitation_ligne(v_id);
end;
$$;
revoke execute on function public.accepter_invitation(text) from public, anon;
grant execute on function public.accepter_invitation(text) to authenticated;

-- Réponse depuis l'écran « Invitations ».
create or replace function public.repondre_invitation(p_invitation uuid, p_accepter boolean)
returns text
language plpgsql volatile
security definer
set search_path = public
as $$
declare
  v_inv record;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if coalesce(p_accepter, false) then
    perform public.accepter_invitation_ligne(p_invitation);
    return 'acceptee';
  end if;

  select * into v_inv from public.invitations where id = p_invitation for update;
  if not found then
    raise exception 'INVITATION_INTROUVABLE' using errcode = 'P0002';
  end if;
  -- Refuser exige aussi l'identifiant prouvé : sinon, déclarer le numéro
  -- d'un autre suffirait à refuser à sa place.
  perform public.verifier_destinataire_invitation(v_inv.identifiant_cible);
  if v_inv.statut <> 'en_attente' then
    raise exception 'INVITATION_DEJA_TRAITEE' using errcode = '22023';
  end if;
  update public.invitations set statut = 'refusee', refusee_le = now() where id = p_invitation;
  perform public.prevenir_reponse_invitation(p_invitation, false);
  return 'refusee';
end;
$$;
revoke execute on function public.repondre_invitation(uuid, boolean) from public, anon;
grant execute on function public.repondre_invitation(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Suivi par la direction
-- ---------------------------------------------------------------------------
create or replace function public.invitations_etablissement(p_etablissement uuid)
returns table (
  id uuid, identifiant text, role_cible text, poste text, statut text,
  cree_le timestamptz, expire_le timestamptz, repondue_le timestamptz, membre text)
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.gere_membres(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return query
  select i.id, i.identifiant_cible, i.role_cible::text, po.nom,
         case when i.statut = 'en_attente' and i.expire_le < now() then 'expiree' else i.statut::text end,
         i.created_at, i.expire_le, coalesce(i.accepte_le, i.refusee_le),
         nullif(trim(coalesce(pa.prenom, '') || ' ' || coalesce(pa.nom, '')), '')
  from public.invitations i
  left join public.postes po on po.id = i.poste_id
  left join public.profiles pa on pa.id = i.accepte_par
  where i.etablissement_id = p_etablissement
    and (i.statut = 'en_attente' or i.created_at > now() - interval '90 days')
  order by i.created_at desc;
end;
$$;
revoke execute on function public.invitations_etablissement(uuid) from public, anon;
grant execute on function public.invitations_etablissement(uuid) to authenticated;

create or replace function public.revoquer_invitation(p_invitation uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
begin
  select etablissement_id into v_etab from public.invitations where id = p_invitation for update;
  if v_etab is null or not public.gere_membres(v_etab) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.invitations set statut = 'revoquee' where id = p_invitation and statut = 'en_attente';
end;
$$;
revoke execute on function public.revoquer_invitation(uuid) from public, anon;
grant execute on function public.revoquer_invitation(uuid) to authenticated;
