-- ============================================================================
-- EcoShop — Identifiant EcoShop (REG-18, partie D)
--
-- Chaque compte reçoit un identifiant court, lisible et propre à EcoShop
-- (jamais un identifiant GSG commun : l'ancien « GSG ID » a été retiré par
-- 20260906001527). Format EC-XXXX-XXC :
--   - 6 caractères tirés au hasard dans l'alphabet de Crockford (chiffres et
--     lettres sans I, L, O, U, qu'on confond à la lecture) ;
--   - 1 caractère de contrôle (Luhn mod 32) : une faute de frappe est
--     repérée sur le téléphone, sans rien demander au serveur.
-- Exemple : EC-7K4M-2Q9.
--
-- Attribué par le serveur à la création du profil, jamais modifiable par le
-- client, jamais réattribué : chaque valeur sortie reste inscrite dans
-- `identifiants_ecoshop_attribues`, même après suppression du compte.
--
-- L'identifiant n'est pas un secret. Avec lui, on peut demander un code de
-- connexion envoyé à l'adresse du compte (Edge Function
-- `connexion_identifiant`) ; la vérification par e-mail reste obligatoire.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Alphabet et caractère de contrôle
-- ---------------------------------------------------------------------------
create or replace function public.crockford_alphabet()
returns text
language sql immutable
as $$ select '0123456789ABCDEFGHJKMNPQRSTVWXYZ'::text $$;

-- Luhn mod 32 sur les caractères donnés (de droite à gauche, facteur 2 pour
-- le plus à droite). Repère toute substitution d'un caractère et la plupart
-- des inversions de deux caractères voisins.
create or replace function public.identifiant_ecoshop_controle(p_corps text)
returns text
language plpgsql immutable
as $$
declare
  v_alpha text := public.crockford_alphabet();
  v_facteur int := 2;
  v_somme int := 0;
  v_val int;
  v_ajout int;
  i int;
begin
  for i in reverse length(p_corps)..1 loop
    v_val := strpos(v_alpha, substr(p_corps, i, 1)) - 1;
    if v_val < 0 then
      raise exception 'CARACTERE_INVALIDE' using errcode = '22023';
    end if;
    v_ajout := v_facteur * v_val;
    v_facteur := case when v_facteur = 2 then 1 else 2 end;
    v_somme := v_somme + (v_ajout / 32) + (v_ajout % 32);
  end loop;
  return substr(v_alpha, ((32 - (v_somme % 32)) % 32) + 1, 1);
end;
$$;

-- Forme normalisée d'une saisie (majuscules, sans espaces ni tirets, O lu
-- comme 0, I et L lus comme 1), ou null si ce n'est pas un identifiant
-- valide (format ou caractère de contrôle).
create or replace function public.normaliser_identifiant_ecoshop(p_saisie text)
returns text
language plpgsql immutable
as $$
declare
  v text := upper(regexp_replace(coalesce(p_saisie, ''), '[\s\-]', '', 'g'));
  v_corps text;
begin
  v := translate(v, 'OIL', '011');
  -- Le préfixe « EC » est remis tel quel (le O de « EC » n'existe pas).
  if v !~ '^EC[0-9A-HJKMNP-TV-Z]{7}$' then
    return null;
  end if;
  v_corps := substr(v, 3, 6);
  if public.identifiant_ecoshop_controle(v_corps) <> substr(v, 9, 1) then
    return null;
  end if;
  return 'EC-' || substr(v, 3, 4) || '-' || substr(v, 7, 3);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Registre des identifiants sortis (jamais vidé)
-- ---------------------------------------------------------------------------
create table if not exists public.identifiants_ecoshop_attribues (
  valeur text primary key
    check (valeur ~ '^EC-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{3}$'),
  attribue_le timestamptz not null default now()
);
alter table public.identifiants_ecoshop_attribues enable row level security;
-- Aucune policy : ni lecture ni écriture depuis le client.

comment on table public.identifiants_ecoshop_attribues is
  'REG-18 : tout identifiant EcoShop déjà sorti. Jamais vidé, pour qu''un identifiant ne soit jamais réattribué.';

create or replace function public.generer_identifiant_ecoshop()
returns text
language plpgsql volatile
security definer
set search_path = public, extensions
as $$
declare
  v_alpha text := public.crockford_alphabet();
  v_octets bytea;
  v_corps text;
  v_valeur text;
  i int;
begin
  loop
    v_octets := gen_random_bytes(6);
    v_corps := '';
    for i in 0..5 loop
      -- 256 est un multiple de 32 : tirage sans biais.
      v_corps := v_corps || substr(v_alpha, (get_byte(v_octets, i) % 32) + 1, 1);
    end loop;
    v_valeur := 'EC-' || substr(v_corps, 1, 4) || '-' || substr(v_corps, 5, 2)
                || public.identifiant_ecoshop_controle(v_corps);
    insert into public.identifiants_ecoshop_attribues (valeur) values (v_valeur)
    on conflict (valeur) do nothing;
    if found then
      return v_valeur;
    end if;
  end loop;
end;
$$;
revoke execute on function public.generer_identifiant_ecoshop() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Colonne du profil, attribuée à la création
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists identifiant_ecoshop text;

create unique index if not exists profiles_identifiant_ecoshop_unique
  on public.profiles (identifiant_ecoshop);

create or replace function public.profiles_attribuer_identifiant_ecoshop()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.identifiant_ecoshop := public.generer_identifiant_ecoshop();
  return new;
end;
$$;

drop trigger if exists profiles_identifiant_ecoshop_trg on public.profiles;
create trigger profiles_identifiant_ecoshop_trg
  before insert on public.profiles
  for each row execute procedure public.profiles_attribuer_identifiant_ecoshop();

-- Comptes existants : identifiant attribué tout de suite.
update public.profiles
   set identifiant_ecoshop = public.generer_identifiant_ecoshop()
 where identifiant_ecoshop is null;

alter table public.profiles alter column identifiant_ecoshop set not null;

-- Jamais modifiable par le client (même protection que le rôle).
create or replace function public.profiles_protege_colonnes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.est_appel_service() then
    -- Même un appel serveur ne change pas l'identifiant attribué.
    new.identifiant_ecoshop := old.identifiant_ecoshop;
    return new;
  end if;

  new.id                     := old.id;
  new.identifiant_canonique  := old.identifiant_canonique;
  new.identifiant_ecoshop    := old.identifiant_ecoshop;
  new.role_racine            := old.role_racine;
  new.statut_compte          := old.statut_compte;
  new.created_at             := old.created_at;
  new.deleted_at             := old.deleted_at;
  return new;
end;
$$;

comment on column public.profiles.identifiant_ecoshop is
  'REG-18 : identifiant EcoShop (EC-XXXX-XXC), attribué par le serveur, jamais modifié ni réattribué. N''est pas un secret.';

-- ---------------------------------------------------------------------------
-- 4. Connexion avec l'identifiant (réservé à l'Edge Function)
-- ---------------------------------------------------------------------------
-- Adresse e-mail du compte actif portant cet identifiant, ou null.
create or replace function public.email_pour_identifiant_ecoshop(p_identifiant text)
returns text
language sql stable
security definer
set search_path = public, auth
as $$
  select lower(u.email)
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.identifiant_ecoshop = public.normaliser_identifiant_ecoshop(p_identifiant)
    and p.statut_compte = 'actif'
    and p.deleted_at is null
    and u.email is not null and u.email <> ''
  limit 1;
$$;
revoke execute on function public.email_pour_identifiant_ecoshop(text) from public, anon, authenticated;
grant execute on function public.email_pour_identifiant_ecoshop(text) to service_role;

-- Essais de connexion par identifiant : limite par identifiant et par
-- adresse réseau, que l'identifiant existe ou non.
create table if not exists public.essais_connexion_identifiant (
  id bigint generated always as identity primary key,
  cle text not null,
  nature text not null check (nature in ('envoi', 'verification')),
  created_at timestamptz not null default now()
);
create index if not exists essais_connexion_identifiant_cle_idx
  on public.essais_connexion_identifiant (cle, nature, created_at);
alter table public.essais_connexion_identifiant enable row level security;

-- Enregistre un essai et dit s'il est permis (moins de p_max essais de
-- cette nature pour cette clé dans les p_minutes dernières minutes).
create or replace function public.noter_essai_connexion_identifiant(
  p_cle text, p_nature text, p_minutes int, p_max int)
returns boolean
language plpgsql volatile
security definer
set search_path = public
as $$
declare
  v_nombre int;
begin
  perform pg_advisory_xact_lock(hashtext('essai:' || p_cle || ':' || p_nature));
  select count(*) into v_nombre
  from public.essais_connexion_identifiant
  where cle = p_cle and nature = p_nature
    and created_at > now() - make_interval(mins => p_minutes);
  if v_nombre >= p_max then
    return false;
  end if;
  insert into public.essais_connexion_identifiant (cle, nature) values (p_cle, p_nature);
  return true;
end;
$$;
revoke execute on function public.noter_essai_connexion_identifiant(text, text, int, int) from public, anon, authenticated;
grant execute on function public.noter_essai_connexion_identifiant(text, text, int, int) to service_role;
