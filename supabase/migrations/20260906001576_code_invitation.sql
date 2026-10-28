-- ============================================================================
-- EcoShop — REG-27 : code d'invitation à saisir
-- (décision du porteur de projet, 2026-10-28)
--
-- Jusqu'ici, une invitation ne s'acceptait qu'avec l'identifiant prouvé
-- auquel elle était adressée (l'adresse e-mail de connexion, ou un numéro
-- confirmé par l'école). Un enseignant sans e-mail, ou déjà inscrit avec
-- une autre adresse, ne pouvait pas l'accepter.
--
-- Désormais chaque invitation porte aussi un **code de 8 caractères**
-- (« K7Q2-M9XD », alphabet sans lettres ambiguës), que la Direction remet
-- elle-même à la personne (de vive voix, WhatsApp). Saisi par un compte
-- connecté, il accepte l'invitation :
--   • usage unique, valable jusqu'à l'expiration de l'invitation (14 jours) ;
--   • 5 essais manqués par heure et par compte au plus ;
--   • la Direction voit qui a accepté, et par quel moyen (code) ;
--   • un code ne donne jamais le rôle Direction (réservé à l'invitation
--     par identifiant prouvé, REG-22).
--
-- Migration idempotente.
-- ============================================================================

alter table public.invitations
  add column if not exists code text,
  add column if not exists accepte_par_code boolean not null default false;

create unique index if not exists idx_invitations_code_en_attente
  on public.invitations (code) where statut = 'en_attente' and code is not null;

-- Code : 8 caractères de l'alphabet de Crockford (sans I, L, O, U).
create or replace function public.nouveau_code_invitation()
returns text
language plpgsql volatile
set search_path = public, extensions
as $$
declare
  v_alpha text := public.crockford_alphabet();
  v_octets bytea;
  v_code text;
  i int;
begin
  loop
    v_octets := gen_random_bytes(8);
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alpha, (get_byte(v_octets, i) % 32) + 1, 1);
    end loop;
    exit when not exists (select 1 from public.invitations where code = v_code and statut = 'en_attente');
  end loop;
  return v_code;
end;
$$;
revoke all on function public.nouveau_code_invitation() from public, anon, authenticated;

create or replace function public.invitations_code_par_defaut()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.code is null and new.role_cible::text <> 'direction' then
    new.code := public.nouveau_code_invitation();
  end if;
  return new;
end $$;
drop trigger if exists invitations_code_par_defaut_trg on public.invitations;
create trigger invitations_code_par_defaut_trg before insert on public.invitations
  for each row execute function public.invitations_code_par_defaut();

-- Invitations en attente d'avant REG-27 : elles reçoivent leur code.
update public.invitations
   set code = public.nouveau_code_invitation()
 where statut = 'en_attente' and code is null and role_cible::text <> 'direction';

-- Saisie : majuscules, sans espace ni tiret ; O → 0, I et L → 1.
create or replace function public.normaliser_code_invitation(p text)
returns text language sql immutable as $$
  select translate(upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')), 'OIL', '011');
$$;

create table if not exists public.essais_code_invitation (
  id bigserial primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  essai_le timestamptz not null default now()
);
create index if not exists idx_essais_code_invitation on public.essais_code_invitation (profile_id, essai_le);
alter table public.essais_code_invitation enable row level security;

-- ---------------------------------------------------------------------------
-- Acceptation par code
-- ---------------------------------------------------------------------------
create or replace function public.accepter_invitation_par_code(p_code text)
returns jsonb
language plpgsql volatile
security definer
set search_path = public
as $$
declare
  v_code text := public.normaliser_code_invitation(p_code);
  v_inv record;
  v_ecole text;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if (select count(*) from public.essais_code_invitation
       where profile_id = auth.uid() and essai_le > now() - interval '1 hour') >= 5 then
    raise exception 'TROP_D_ESSAIS' using errcode = '42501';
  end if;
  if length(v_code) <> 8 then
    raise exception 'CODE_INVALIDE' using errcode = '22023';
  end if;

  select * into v_inv from public.invitations
   where code = v_code and statut = 'en_attente'
   for update;
  if not found then
    -- Essai manqué gardé (pas d'exception : elle annulerait l'enregistrement).
    insert into public.essais_code_invitation (profile_id) values (auth.uid());
    return jsonb_build_object('erreur', 'CODE_INCONNU');
  end if;
  if v_inv.expire_le < now() then
    update public.invitations set statut = 'expiree' where id = v_inv.id;
    raise exception 'INVITATION_EXPIREE' using errcode = '22023';
  end if;
  if v_inv.role_cible::text = 'direction' then
    raise exception 'CODE_INVALIDE' using errcode = '22023';
  end if;

  insert into public.etablissements_membres
    (profile_id, etablissement_id, role_dans_etablissement, poste_id)
  values
    (auth.uid(), v_inv.etablissement_id, v_inv.role_cible::text, v_inv.poste_id)
  on conflict (profile_id, etablissement_id) do update
    set role_dans_etablissement = excluded.role_dans_etablissement,
        poste_id = excluded.poste_id,
        actif = true,
        deleted_at = null;

  -- Compte neuf : le rôle de l'invitation. Compte existant (parent, élève…) :
  -- son rôle principal ne change pas ; il gagne un espace dans l'école.
  update public.profiles
     set role_racine = v_inv.role_cible
   where id = auth.uid() and role_racine is null;

  update public.invitations
     set statut = 'acceptee', accepte_par = auth.uid(), accepte_le = now(), accepte_par_code = true
   where id = v_inv.id;

  perform public.prevenir_reponse_invitation(v_inv.id, true);
  select nom into v_ecole from public.etablissements where id = v_inv.etablissement_id;
  return jsonb_build_object(
    'etablissement_id', v_inv.etablissement_id,
    'etablissement', v_ecole,
    'role', v_inv.role_cible::text
  );
end;
$$;
revoke all on function public.accepter_invitation_par_code(text) from public, anon;
grant execute on function public.accepter_invitation_par_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Suivi de la Direction : le code (en attente) et le moyen d'acceptation
-- ---------------------------------------------------------------------------
drop function if exists public.invitations_etablissement(uuid);
create or replace function public.invitations_etablissement(p_etablissement uuid)
returns table (
  id uuid, identifiant text, role_cible text, poste text, statut text,
  cree_le timestamptz, expire_le timestamptz, repondue_le timestamptz, membre text,
  code text, par_code boolean)
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
         nullif(trim(coalesce(pa.prenom, '') || ' ' || coalesce(pa.nom, '')), ''),
         case when i.statut = 'en_attente' and i.expire_le >= now() then i.code end,
         i.accepte_par_code
  from public.invitations i
  left join public.postes po on po.id = i.poste_id
  left join public.profiles pa on pa.id = i.accepte_par
  where i.etablissement_id = p_etablissement
    and (i.statut = 'en_attente' or i.created_at > now() - interval '90 days')
  order by i.created_at desc;
end;
$$;
grant execute on function public.invitations_etablissement(uuid) to authenticated;
