-- ============================================================================
-- EcoShop — Inscription en étapes (REG-18, partie B)
--
-- Ordre des écrans : espace (élève ou parent), nom et prénoms, vérification
-- de l'adresse (code ou Google), téléphone, code secret, récapitulatif.
--
-- L'espace et le nom saisis avant la vérification restent sur le téléphone.
-- Ils ne partent PAS avec la demande de code : Supabase crée le compte dès
-- cette demande, et une demande faite pour l'adresse d'un compte existant ne
-- doit jamais pouvoir le modifier. Ils sont appliqués après la vérification,
-- par `finaliser_inscription`, et seulement à un compte nouveau (rôle pas
-- encore fixé, inscription jamais finalisée). Pour un compte existant, la
-- fonction ne change rien et le dit.
--
-- Un compte dont l'adresse n'a jamais été vérifiée (inscription abandonnée
-- après la demande de code) est supprimé au bout de 24 h
-- (`purger_comptes_non_verifies`, tâche planifiée chaque heure).
-- ============================================================================

alter table public.profiles
  add column if not exists inscription_finalisee_le timestamptz;

comment on column public.profiles.inscription_finalisee_le is
  'REG-18 : date à laquelle l''espace et le nom choisis à l''inscription ont été appliqués. Null = compte jamais finalisé.';

-- Comptes existants : déjà en service.
update public.profiles
   set inscription_finalisee_le = created_at
 where role_racine is not null and inscription_finalisee_le is null;

-- Même protection que le rôle : jamais écrite par le client directement.
create or replace function public.profiles_protege_colonnes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.est_appel_service() then
    new.identifiant_ecoshop := old.identifiant_ecoshop;
    return new;
  end if;

  new.id                       := old.id;
  new.identifiant_canonique    := old.identifiant_canonique;
  new.identifiant_ecoshop      := old.identifiant_ecoshop;
  new.role_racine              := old.role_racine;
  new.statut_compte            := old.statut_compte;
  new.inscription_finalisee_le := old.inscription_finalisee_le;
  new.created_at               := old.created_at;
  new.deleted_at               := old.deleted_at;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Finalisation de l'inscription (après la vérification de l'adresse)
-- ---------------------------------------------------------------------------
-- Renvoie 'appliquee' (compte nouveau : espace et nom enregistrés) ou
-- 'compte_existant' (rien n'a changé).
create or replace function public.finaliser_inscription(
  p_espace public.role_racine,
  p_prenom text,
  p_nom text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profil record;
  v_prenom text := nullif(trim(regexp_replace(coalesce(p_prenom, ''), '\s+', ' ', 'g')), '');
  v_nom    text := nullif(trim(regexp_replace(coalesce(p_nom, ''), '\s+', ' ', 'g')), '');
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  if p_espace is null or p_espace not in ('eleve', 'parent') then
    raise exception 'ROLE_NON_AUTO_INSCRIPTIBLE' using errcode = '42501';
  end if;

  if v_prenom is null or v_nom is null
     or length(v_prenom) > 80 or length(v_nom) > 80
     or v_prenom ~ '[@0-9]' or v_nom ~ '[@0-9]' then
    raise exception 'NOM_INVALIDE' using errcode = '22023';
  end if;

  select role_racine, inscription_finalisee_le into v_profil
  from public.profiles
  where id = auth.uid() and deleted_at is null
  for update;

  if not found then
    raise exception 'PROFIL_INTROUVABLE' using errcode = 'P0002';
  end if;

  -- Compte déjà en service : jamais modifié par une inscription.
  if v_profil.role_racine is not null or v_profil.inscription_finalisee_le is not null then
    return 'compte_existant';
  end if;

  update public.profiles
     set role_racine = p_espace,
         prenom = v_prenom,
         nom = v_nom,
         inscription_finalisee_le = now()
   where id = auth.uid();

  return 'appliquee';
end;
$$;

comment on function public.finaliser_inscription(public.role_racine, text, text) is
  'REG-18 : applique espace et nom à un compte nouveau, après vérification de l''adresse. Ne modifie jamais un compte existant.';

revoke execute on function public.finaliser_inscription(public.role_racine, text, text) from public, anon;
grant execute on function public.finaliser_inscription(public.role_racine, text, text) to authenticated;

-- L'ancien choix du rôle (comptes créés avant REG-18) marque aussi le compte
-- comme finalisé.
create or replace function public.choisir_role_racine(p_role public.role_racine)
returns public.role_racine
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actuel public.role_racine;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  if p_role not in ('eleve', 'parent') then
    raise exception 'ROLE_NON_AUTO_INSCRIPTIBLE' using errcode = '42501';
  end if;

  select role_racine into v_actuel
  from public.profiles where id = auth.uid() and deleted_at is null
  for update;

  if not found then
    raise exception 'PROFIL_INTROUVABLE' using errcode = 'P0002';
  end if;

  if v_actuel is not null then
    raise exception 'ROLE_DEJA_DEFINI' using errcode = '23505';
  end if;

  update public.profiles
     set role_racine = p_role,
         inscription_finalisee_le = coalesce(inscription_finalisee_le, now())
   where id = auth.uid();
  return p_role;
end;
$$;

-- Nom et prénoms du compte connecté (personnel invité, comptes anciens sans
-- nom). Ne touche ni au rôle ni à l'espace.
create or replace function public.definir_mon_nom(p_prenom text, p_nom text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prenom text := nullif(trim(regexp_replace(coalesce(p_prenom, ''), '\s+', ' ', 'g')), '');
  v_nom    text := nullif(trim(regexp_replace(coalesce(p_nom, ''), '\s+', ' ', 'g')), '');
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if v_prenom is null or v_nom is null
     or length(v_prenom) > 80 or length(v_nom) > 80
     or v_prenom ~ '[@0-9]' or v_nom ~ '[@0-9]' then
    raise exception 'NOM_INVALIDE' using errcode = '22023';
  end if;
  update public.profiles set prenom = v_prenom, nom = v_nom
   where id = auth.uid() and deleted_at is null;
end;
$$;
revoke execute on function public.definir_mon_nom(text, text) from public, anon;
grant execute on function public.definir_mon_nom(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Comptes jamais vérifiés : supprimés au bout de 24 h
-- ---------------------------------------------------------------------------
-- Un compte est « jamais vérifié » quand Supabase l'a créé à la demande d'un
-- code mais que ce code n'a jamais été saisi : ni adresse ni téléphone
-- confirmés, aucune connexion, pas d'invitation en cours, aucun rôle.
create or replace function public.purger_comptes_non_verifies()
returns integer
language plpgsql volatile
security definer
set search_path = public, auth
as $$
declare
  v_nombre integer;
begin
  with cibles as (
    select u.id
    from auth.users u
    left join public.profiles p on p.id = u.id
    where u.created_at < now() - interval '24 hours'
      and u.email_confirmed_at is null
      and u.phone_confirmed_at is null
      and u.last_sign_in_at is null
      and u.invited_at is null
      and coalesce(u.is_sso_user, false) = false
      and (p.id is null or (p.role_racine is null and p.inscription_finalisee_le is null))
  )
  delete from auth.users u using cibles c where u.id = c.id;
  get diagnostics v_nombre = row_count;

  -- Essais de connexion par identifiant : inutiles au-delà d'un jour.
  delete from public.essais_connexion_identifiant where created_at < now() - interval '1 day';

  return v_nombre;
end;
$$;

comment on function public.purger_comptes_non_verifies() is
  'REG-18 : supprime les comptes dont l''adresse n''a jamais été vérifiée depuis plus de 24 h (inscriptions abandonnées). Tâche planifiée horaire.';

revoke execute on function public.purger_comptes_non_verifies() from public, anon, authenticated;
grant execute on function public.purger_comptes_non_verifies() to service_role;

-- Tâche planifiée (scripts/deployer_supabase.ps1) : contrôlée par
-- etat_mise_en_service().
create or replace function public.taches_planifiees_attendues()
returns table (nom text, role text)
language sql immutable set search_path = public
as $$
  values
    ('envoyer-notifications', 'Courriels et SMS (chaque minute)'),
    ('envoyer-push', 'Notifications push (chaque minute)'),
    ('relancer-paiements-orange-money', 'Paiements Orange Money restés en suspens (toutes les 5 min)'),
    ('detecter-absences-portail', 'Absences au portail (toutes les 10 min)'),
    ('expirer-offres-inscription', 'Places d''inscription non confirmées (chaque heure)'),
    ('purger-comptes-non-verifies', 'Inscriptions abandonnées depuis plus de 24 h (chaque heure)'),
    ('taches-quotidiennes', 'Décrochage et risque de réussite (chaque nuit)'),
    ('purger-notifications', 'Ménage des notifications de plus de 90 jours (chaque nuit)'),
    ('purger-historique-taches', 'Ménage de l''historique des tâches (chaque nuit)')
$$;
