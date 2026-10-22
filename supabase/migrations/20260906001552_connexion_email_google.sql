-- ============================================================================
-- EcoShop — Connexion par e-mail et Google, téléphone au profil (REG-16)
--
-- Décision GSG (octobre 2026) : les codes de connexion par SMS sont
-- suspendus (coût d'un SMS par connexion). On se connecte par e-mail : code
-- reçu par courriel, ou bouton Google qui reprend le compte déjà présent sur
-- le téléphone. Le numéro est demandé une fois connecté, pour compléter le
-- profil.
--
-- Un numéro saisi ainsi n'est vérifié par personne : il reste « déclaré ».
-- Il ne donne donc aucun droit (accepter une invitation adressée à ce
-- numéro, par exemple) et n'empêche pas son vrai titulaire de le déclarer à
-- son tour. Il devient « vérifié » quand l'école le confirme en présence du
-- parent, gratuitement, ou plus tard par un code SMS si GSG le rouvre.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Identifiants : unicité réservée aux identifiants vérifiés
-- ---------------------------------------------------------------------------
alter table public.identifiants_comptes
  add column if not exists mode_verification text
    check (mode_verification in ('code', 'google', 'ecole')),
  add column if not exists verifie_par uuid references public.profiles (id) on delete set null;

alter table public.identifiants_comptes drop constraint if exists identifiants_valeur_unique;

create unique index if not exists identifiants_valeur_verifiee_unique
  on public.identifiants_comptes (valeur)
  where verifie_le is not null;

create unique index if not exists identifiants_profil_valeur_unique
  on public.identifiants_comptes (profile_id, valeur);

create index if not exists identifiants_valeur_idx on public.identifiants_comptes (valeur);

comment on column public.identifiants_comptes.verifie_le is
  'Null = identifiant déclaré, jamais prouvé : il ne donne aucun droit. Seul un identifiant vérifié est unique.';

-- Les identifiants créés à l'inscription l'ont été par un code ou un compte
-- Google : ils sont prouvés.
update public.identifiants_comptes
   set mode_verification = 'code'
 where canonique and verifie_le is not null and mode_verification is null;

-- ---------------------------------------------------------------------------
-- 2. Nouveau compte : prénom et nom repris de Google
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_valeur text;
  v_type   public.type_identifiant;
  v_meta   jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_prenom text;
  v_nom    text;
  v_complet text;
  v_mode   text := 'code';
begin
  if new.phone is not null and new.phone <> '' then
    -- auth.users.phone est stocké sans le « + » : on rétablit la forme E.164.
    v_valeur := case when left(new.phone, 1) = '+' then new.phone else '+' || new.phone end;
    v_type := 'telephone';
  elsif new.email is not null and new.email <> '' then
    v_valeur := lower(new.email);
    v_type := 'email';
  else
    v_valeur := 'uid:' || new.id::text;
    v_type := null;
  end if;

  -- Google transmet given_name / family_name ; d'autres fournisseurs
  -- seulement full_name ou name. On ne garde que du texte raisonnable.
  v_prenom := nullif(left(trim(v_meta ->> 'given_name'), 80), '');
  v_nom    := nullif(left(trim(v_meta ->> 'family_name'), 80), '');
  if v_prenom is null and v_nom is null then
    v_complet := nullif(trim(coalesce(v_meta ->> 'full_name', v_meta ->> 'name')), '');
    if v_complet is not null and v_complet !~ '@' then
      v_prenom := left(split_part(v_complet, ' ', 1), 80);
      v_nom := nullif(left(trim(substr(v_complet, length(split_part(v_complet, ' ', 1)) + 1)), 80), '');
    end if;
  end if;
  if coalesce(new.raw_app_meta_data ->> 'provider', '') = 'google' then
    v_mode := 'google';
  end if;

  insert into public.profiles (id, identifiant_canonique, prenom, nom)
  values (new.id, v_valeur, v_prenom, v_nom)
  on conflict (id) do nothing;

  if v_type is not null then
    insert into public.identifiants_comptes
      (profile_id, type_identifiant, valeur, canonique, verifie_le, mode_verification)
    values (new.id, v_type, v_valeur, true, now(), v_mode)
    on conflict (valeur) where verifie_le is not null do nothing;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Mon numéro de téléphone
-- ---------------------------------------------------------------------------
create or replace function public.mon_telephone()
returns table (telephone text, verifie boolean, verifie_le timestamptz, mode_verification text)
language sql
stable
security definer
set search_path = public
as $$
  select ic.valeur, ic.verifie_le is not null, ic.verifie_le, ic.mode_verification
  from public.identifiants_comptes ic
  where ic.profile_id = auth.uid() and ic.type_identifiant = 'telephone'
  order by ic.verifie_le desc nulls last, ic.created_at desc
  limit 1;
$$;

-- Déclare (ou remplace) le numéro du compte connecté. Un seul numéro
-- déclaré à la fois ; un numéro déjà vérifié du compte reste en place.
create or replace function public.declarer_mon_telephone(p_telephone text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_tel text := regexp_replace(coalesce(p_telephone, ''), '[\s.\-()]', '', 'g');
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if v_tel !~ '^\+[1-9][0-9]{6,14}$' then
    raise exception 'TELEPHONE_INVALIDE' using errcode = '22023';
  end if;

  -- Déjà le mien (déclaré ou vérifié) : rien à faire.
  if exists (select 1 from public.identifiants_comptes
             where profile_id = auth.uid() and valeur = v_tel) then
    return jsonb_build_object('telephone', v_tel,
      'verifie', exists (select 1 from public.identifiants_comptes
                         where profile_id = auth.uid() and valeur = v_tel and verifie_le is not null));
  end if;

  -- Prouvé par un autre compte : on le dit, sans révéler lequel.
  if exists (select 1 from public.identifiants_comptes
             where valeur = v_tel and verifie_le is not null) then
    raise exception 'TELEPHONE_DEJA_UTILISE' using errcode = '23505';
  end if;

  delete from public.identifiants_comptes
   where profile_id = auth.uid() and type_identifiant = 'telephone'
     and verifie_le is null and not canonique;

  insert into public.identifiants_comptes (profile_id, type_identifiant, valeur, canonique)
  values (auth.uid(), 'telephone', v_tel, false);

  return jsonb_build_object('telephone', v_tel, 'verifie', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Confirmation du numéro par l'école, en présence du parent
-- ---------------------------------------------------------------------------
-- Personnes de l'école (parents liés, personnel) dont le numéro n'est que
-- déclaré.
create or replace function public.telephones_a_confirmer(p_etablissement uuid)
returns table (profile_id uuid, prenom text, nom text, telephone text, enfants text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not coalesce(public.gere_inscriptions(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return query
  with personnes as (
    select r.parent_profile_id as pid
    from public.relations_parent_eleve r
    where r.etablissement_id = p_etablissement and r.deleted_at is null and r.statut = 'confirmee'
    union
    select m.profile_id
    from public.etablissements_membres m
    where m.etablissement_id = p_etablissement and m.actif and m.deleted_at is null
  )
  select p.id, p.prenom, p.nom, ic.valeur,
         (select string_agg(f.prenom || ' ' || f.nom, ', ' order by f.prenom)
            from public.relations_parent_eleve r
            join public.fiches_eleves f on f.id = r.fiche_eleve_id and f.deleted_at is null
           where r.parent_profile_id = p.id and r.etablissement_id = p_etablissement
             and r.deleted_at is null)
  from personnes x
  join public.profiles p on p.id = x.pid and p.deleted_at is null
  join public.identifiants_comptes ic
    on ic.profile_id = p.id and ic.type_identifiant = 'telephone' and ic.verifie_le is null
  where not exists (select 1 from public.identifiants_comptes v
                    where v.profile_id = p.id and v.type_identifiant = 'telephone'
                      and v.verifie_le is not null)
  order by p.nom nulls last, p.prenom;
end;
$$;

-- L'agent a vu le parent et son téléphone (appel ou message de test) : le
-- numéro devient vérifié. Le numéro transmis doit être celui déclaré, pour
-- qu'un agent ne puisse pas attribuer un numéro de son choix.
create or replace function public.confirmer_telephone(
  p_etablissement uuid,
  p_profil uuid,
  p_telephone text
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_tel text := regexp_replace(coalesce(p_telephone, ''), '[\s.\-()]', '', 'g');
  v_id uuid;
begin
  if not coalesce(public.gere_inscriptions(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.relations_parent_eleve r
     where r.parent_profile_id = p_profil and r.etablissement_id = p_etablissement and r.deleted_at is null
    union all
    select 1 from public.etablissements_membres m
     where m.profile_id = p_profil and m.etablissement_id = p_etablissement and m.deleted_at is null
  ) then
    raise exception 'PERSONNE_HORS_ETABLISSEMENT' using errcode = '42501';
  end if;

  select id into v_id from public.identifiants_comptes
   where profile_id = p_profil and valeur = v_tel and type_identifiant = 'telephone'
   for update;
  if v_id is null then
    raise exception 'TELEPHONE_NON_DECLARE' using errcode = '22023';
  end if;

  if exists (select 1 from public.identifiants_comptes
             where valeur = v_tel and verifie_le is not null and profile_id <> p_profil) then
    raise exception 'TELEPHONE_DEJA_UTILISE' using errcode = '23505';
  end if;

  update public.identifiants_comptes
     set verifie_le = coalesce(verifie_le, now()),
         mode_verification = coalesce(mode_verification, 'ecole'),
         verifie_par = coalesce(verifie_par, auth.uid())
   where id = v_id;

  -- Les autres comptes qui avaient seulement déclaré ce numéro le perdent.
  delete from public.identifiants_comptes
   where valeur = v_tel and profile_id <> p_profil and verifie_le is null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Une invitation ne vaut que pour un identifiant prouvé
-- ---------------------------------------------------------------------------
create or replace function public.accepter_invitation(p_jeton text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_inv record;
  v_membre_id uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  select * into v_inv
  from public.invitations
  where jeton_empreinte = encode(digest(p_jeton, 'sha256'), 'hex')
  for update;

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

  -- L'invitation est nominative : elle ne vaut que pour le destinataire,
  -- et seulement si ce compte a prouvé détenir cet identifiant (un numéro
  -- simplement déclaré au profil ne suffit pas).
  if not exists (
    select 1 from public.identifiants_comptes
    where profile_id = auth.uid() and valeur = v_inv.identifiant_cible and verifie_le is not null
  ) then
    if exists (select 1 from public.identifiants_comptes
               where profile_id = auth.uid() and valeur = v_inv.identifiant_cible) then
      raise exception 'IDENTIFIANT_NON_VERIFIE' using errcode = '42501';
    end if;
    raise exception 'INVITATION_AUTRE_DESTINATAIRE' using errcode = '42501';
  end if;

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

  return v_membre_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Fast-track d'inscription : titulaire vérifié d'abord
-- ---------------------------------------------------------------------------
create or replace function public.rechercher_enfants_par_telephone_parent(
  p_etablissement uuid,
  p_telephone text
)
returns setof public.fiches_eleves
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_parents uuid[];
begin
  if not coalesce(public.a_permission(p_etablissement, 'scolarite.inscription.gerer'), false)
     and not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  -- Le titulaire vérifié du numéro s'il existe ; sinon les comptes qui l'ont
  -- déclaré (l'agent voit alors chaque enfant et reconnaît la famille).
  select array_agg(ic.profile_id) into v_parents
  from public.identifiants_comptes ic
  where ic.type_identifiant = 'telephone' and ic.valeur = trim(p_telephone) and ic.verifie_le is not null;

  if v_parents is null then
    select array_agg(ic.profile_id) into v_parents
    from public.identifiants_comptes ic
    where ic.type_identifiant = 'telephone' and ic.valeur = trim(p_telephone);
  end if;

  if v_parents is null then
    return;
  end if;

  return query
  select f.*
  from public.fiches_eleves f
  join public.relations_parent_eleve r on r.fiche_eleve_id = f.id
  where r.parent_profile_id = any (v_parents)
    and r.etablissement_id = p_etablissement
    and r.statut = 'confirmee'
    and r.autorise
    and r.deleted_at is null
    and f.deleted_at is null
  order by f.nom, f.prenom;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Droits
-- ---------------------------------------------------------------------------
revoke execute on function public.mon_telephone() from public, anon;
revoke execute on function public.declarer_mon_telephone(text) from public, anon;
revoke execute on function public.telephones_a_confirmer(uuid) from public, anon;
revoke execute on function public.confirmer_telephone(uuid, uuid, text) from public, anon;
revoke execute on function public.accepter_invitation(text) from public, anon;
revoke execute on function public.rechercher_enfants_par_telephone_parent(uuid, text) from public, anon;
grant execute on function public.mon_telephone() to authenticated;
grant execute on function public.declarer_mon_telephone(text) to authenticated;
grant execute on function public.telephones_a_confirmer(uuid) to authenticated;
grant execute on function public.confirmer_telephone(uuid, uuid, text) to authenticated;
grant execute on function public.accepter_invitation(text) to authenticated;
grant execute on function public.rechercher_enfants_par_telephone_parent(uuid, text) to authenticated;
