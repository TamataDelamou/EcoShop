-- ============================================================================
-- EcoShop — REG-31 : suppression du compte par l'utilisateur, conditions
-- d'utilisation et confidentialité v1.0.
--
-- Google Play (règle « Suppression de compte », 2024) : toute application où
-- l'on crée un compte doit permettre de le supprimer depuis l'application et
-- depuis une page web (site GSG, /suppression-compte/).
--
-- Choix : ANONYMISATION, pas effacement de la ligne `profiles`. Plus de
-- cinquante tables y renvoient sans cascade (notes saisies, reçus, écritures
-- comptables, sanctions…) : ces pièces appartiennent à l'école ou doivent être
-- gardées (OHADA : 10 ans). Le compte perd tout ce qui identifie la personne
-- et tout accès ; les pièces restent, rattachées à un « Compte supprimé ».
--
-- Délai de réflexion : 7 jours. La tâche quotidienne `effectuer-suppressions-
-- comptes` traite les demandes échues et purge les traces de sécurité de plus
-- d'un an (promesse de la politique de confidentialité, §3.10).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Demandes de suppression
-- ---------------------------------------------------------------------------
create table if not exists public.demandes_suppression_compte (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  canal text not null default 'application' check (canal in ('application', 'web')),
  motif text check (motif is null or length(motif) <= 500),
  demandee_le timestamptz not null default now(),
  effective_le timestamptz not null,
  statut text not null default 'en_attente' check (statut in ('en_attente', 'annulee', 'effectuee')),
  traitee_le timestamptz,
  -- Ce que la tâche n'a pas pu faire (fichier de photo, schéma auth) : à
  -- reprendre à la main, la suppression des données publiques est faite.
  reste_a_faire text
);

create unique index if not exists idx_demandes_suppression_en_attente
  on public.demandes_suppression_compte (profile_id) where statut = 'en_attente';
create index if not exists idx_demandes_suppression_echeance
  on public.demandes_suppression_compte (effective_le) where statut = 'en_attente';

comment on table public.demandes_suppression_compte is
  'REG-31 : demandes de suppression de compte (application ou e-mail traité par GSG). Écriture par les fonctions ci-dessous uniquement.';

alter table public.demandes_suppression_compte enable row level security;

drop policy if exists "demandes_suppression_select" on public.demandes_suppression_compte;
create policy "demandes_suppression_select" on public.demandes_suppression_compte
  for select using (profile_id = auth.uid() or public.est_admin_gsg());
-- Aucune policy d'écriture : fonctions SECURITY DEFINER seulement.

-- ---------------------------------------------------------------------------
-- 2. Écoles dont l'appelant est la seule direction active
-- ---------------------------------------------------------------------------
create or replace function public.ecoles_direction_seule(p_profil uuid)
returns table (etablissement_id uuid, nom text)
language sql stable
security definer
set search_path = public
as $$
  select e.id, e.nom
  from public.etablissements_membres m
  join public.etablissements e on e.id = m.etablissement_id
  where m.profile_id = p_profil
    and m.actif
    and m.role_dans_etablissement = 'direction'
    and not exists (
      select 1 from public.etablissements_membres autre
      join public.profiles p on p.id = autre.profile_id
      where autre.etablissement_id = m.etablissement_id
        and autre.profile_id <> p_profil
        and autre.actif
        and autre.role_dans_etablissement = 'direction'
        and p.statut_compte = 'actif'
        and p.deleted_at is null
    );
$$;

revoke execute on function public.ecoles_direction_seule(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. État, demande, annulation (appelées par l'application)
-- ---------------------------------------------------------------------------
create or replace function public.etat_suppression_compte()
returns jsonb
language sql stable
security definer
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object('demandee', true, 'demandee_le', d.demandee_le, 'effective_le', d.effective_le)
       from public.demandes_suppression_compte d
      where d.profile_id = auth.uid() and d.statut = 'en_attente'),
    jsonb_build_object('demandee', false)
  );
$$;

create or replace function public.demander_suppression_compte(p_motif text default null)
returns jsonb
language plpgsql volatile
security definer
set search_path = public
as $$
declare
  v_profil uuid := auth.uid();
  v_ecoles jsonb;
  v_effective timestamptz;
begin
  if v_profil is null then
    raise exception 'NON_CONNECTE' using errcode = '42501';
  end if;

  -- Une école ne reste jamais sans direction : erreur rendue (pas levée)
  -- pour que l'application nomme les écoles concernées.
  select jsonb_agg(jsonb_build_object('id', etablissement_id, 'nom', nom))
    into v_ecoles
    from public.ecoles_direction_seule(v_profil);
  if v_ecoles is not null then
    return jsonb_build_object('erreur', 'DIRECTION_SEULE', 'ecoles', v_ecoles);
  end if;

  select effective_le into v_effective
    from public.demandes_suppression_compte
   where profile_id = v_profil and statut = 'en_attente';
  if v_effective is not null then
    return jsonb_build_object('effective_le', v_effective);
  end if;

  insert into public.demandes_suppression_compte (profile_id, canal, motif, effective_le)
  values (v_profil, 'application', nullif(trim(coalesce(p_motif, '')), ''), now() + interval '7 days')
  returning effective_le into v_effective;

  return jsonb_build_object('effective_le', v_effective);
end;
$$;

create or replace function public.annuler_suppression_compte()
returns boolean
language plpgsql volatile
security definer
set search_path = public
as $$
begin
  update public.demandes_suppression_compte
     set statut = 'annulee', traitee_le = now()
   where profile_id = auth.uid() and statut = 'en_attente';
  return found;
end;
$$;

revoke execute on function public.etat_suppression_compte() from public, anon;
revoke execute on function public.demander_suppression_compte(text) from public, anon;
revoke execute on function public.annuler_suppression_compte() from public, anon;
grant execute on function public.etat_suppression_compte() to authenticated;
grant execute on function public.demander_suppression_compte(text) to authenticated;
grant execute on function public.annuler_suppression_compte() to authenticated;

-- Demande reçue par e-mail (page web) : l'équipe GSG la saisit après avoir
-- vérifié l'identité ; même délai, même traitement.
create or replace function public.enregistrer_demande_suppression_web(p_profil uuid, p_motif text default null)
returns jsonb
language plpgsql volatile
security definer
set search_path = public
as $$
declare
  v_effective timestamptz;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if exists (select 1 from public.ecoles_direction_seule(p_profil)) then
    return jsonb_build_object('erreur', 'DIRECTION_SEULE');
  end if;
  insert into public.demandes_suppression_compte (profile_id, canal, motif, effective_le)
  values (p_profil, 'web', p_motif, now() + interval '7 days')
  on conflict (profile_id) where statut = 'en_attente' do nothing
  returning effective_le into v_effective;
  return jsonb_build_object('effective_le', v_effective);
end;
$$;

revoke execute on function public.enregistrer_demande_suppression_web(uuid, text) from public, anon;
grant execute on function public.enregistrer_demande_suppression_web(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Anonymisation d'un compte
-- ---------------------------------------------------------------------------
create or replace function public.anonymiser_compte(p_profil uuid)
returns text
language plpgsql volatile
security definer
set search_path = public, auth, storage
as $$
declare
  v_table text;
  v_reste text := null;
begin
  -- Accès et données propres à la personne : effacés.
  foreach v_table in array array[
    'identifiants_comptes', 'jetons_push', 'sessions_appareils', 'demandes_appareil',
    'preferences_canaux', 'preferences_pointage', 'codes_compte', 'essais_code_compte',
    'jetons_pas_moi', 'essais_code_invitation', 'paniers', 'ai_conversations',
    'annonces_destinataires', 'annonces_lectures', 'lectures_liaison',
    'lectures_circulaires_reseau', 'reseaux_responsables', 'demandes_adhesion'
  ] loop
    if to_regclass('public.' || v_table) is not null then
      execute format('delete from public.%I where profile_id = $1', v_table) using p_profil;
    end if;
  end loop;
  delete from public.notifications where destinataire = p_profil;

  -- Liens rompus, pièces de l'école gardées.
  update public.relations_parent_eleve
     set autorise = false, deleted_at = coalesce(deleted_at, now())
   where parent_profile_id = p_profil;
  update public.etablissements_membres set actif = false where profile_id = p_profil;
  update public.fiches_eleves set profile_id = null where profile_id = p_profil;
  if to_regclass('public.profils_publics') is not null then
    update public.profils_publics set profile_id = null where profile_id = p_profil;
  end if;

  -- Le profil devient « Compte supprimé ». L'identifiant EcoShop (EC-…)
  -- reste sur la ligne (le déclencheur `profiles_protege_colonnes` le fige)
  -- et dans `identifiants_ecoshop_attribues` : jamais réattribué ; seul, il
  -- ne désigne plus personne.
  update public.profiles
     set prenom = 'Compte',
         nom = 'supprimé',
         photo_chemin = null,
         identifiant_canonique = 'supprime:' || p_profil::text,
         etablissement_actif_id = null,
         statut_compte = 'supprime',
         deleted_at = coalesce(deleted_at, now()),
         updated_at = now()
   where id = p_profil;

  -- Photo de profil : Supabase peut refuser l'effacement direct d'un
  -- fichier (API Storage obligatoire) ; noté pour reprise.
  begin
    delete from storage.objects
     where bucket_id = 'photos-profils' and split_part(name, '/', 1) = p_profil::text;
  exception when others then
    v_reste := 'fichiers photos-profils/' || p_profil::text || '/ à effacer';
  end;

  -- Connexion : plus aucune session, plus aucune identité (Google, e-mail),
  -- compte banni sans limite, coordonnées effacées.
  begin
    delete from auth.sessions where user_id = p_profil;
    delete from auth.identities where user_id = p_profil;
    update auth.users
       set email = null,
           phone = null,
           encrypted_password = null,
           email_change = '',
           phone_change = '',
           raw_user_meta_data = '{}'::jsonb,
           raw_app_meta_data = jsonb_build_object('provider', 'supprime', 'providers', '[]'::jsonb),
           banned_until = 'infinity',
           deleted_at = now(),
           updated_at = now()
     where id = p_profil;
  exception when others then
    v_reste := concat_ws(' ; ', v_reste, 'auth.users à anonymiser (' || sqlerrm || ')');
  end;

  return v_reste;
end;
$$;

revoke execute on function public.anonymiser_compte(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Tâche quotidienne : demandes échues, traces de sécurité de plus d'un an
-- ---------------------------------------------------------------------------
create or replace function public.effectuer_suppressions_comptes()
returns integer
language plpgsql volatile
security definer
set search_path = public
as $$
declare
  v_demande record;
  v_nombre integer := 0;
begin
  for v_demande in
    select id, profile_id from public.demandes_suppression_compte
     where statut = 'en_attente' and effective_le <= now()
     order by effective_le
     for update skip locked
  loop
    -- Devenu seule direction pendant le délai (collègue parti) : reporté
    -- d'un jour, l'école doit d'abord nommer quelqu'un.
    if exists (select 1 from public.ecoles_direction_seule(v_demande.profile_id)) then
      update public.demandes_suppression_compte
         set effective_le = now() + interval '1 day',
             reste_a_faire = 'seule direction d''une école : suppression reportée'
       where id = v_demande.id;
      continue;
    end if;

    update public.demandes_suppression_compte
       set statut = 'effectuee',
           traitee_le = now(),
           reste_a_faire = public.anonymiser_compte(v_demande.profile_id)
     where id = v_demande.id;
    v_nombre := v_nombre + 1;
  end loop;

  -- Traces de sécurité : un an au plus.
  delete from public.tentatives_liaison where created_at < now() - interval '1 year';
  if to_regclass('public.essais_connexion_identifiant') is not null then
    delete from public.essais_connexion_identifiant where created_at < now() - interval '1 year';
  end if;
  delete from public.demandes_appareil
   where statut <> 'en_attente' and echeance < now() - interval '1 year';

  return v_nombre;
end;
$$;

revoke execute on function public.effectuer_suppressions_comptes() from public, anon, authenticated;

-- Liste des tâches attendues par etat_mise_en_service() (REG-12).
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
    ('purger-historique-taches', 'Ménage de l''historique des tâches (chaque nuit)'),
    ('effectuer-suppressions-comptes', 'Comptes à supprimer (délai de 7 jours échu) et traces de sécurité de plus d''un an (chaque nuit)')
$$;

-- ---------------------------------------------------------------------------
-- 6. Conditions d'utilisation v1.0 (remplacent le texte provisoire)
-- ---------------------------------------------------------------------------
-- Résumé lisible dans l'application ; le texte complet est sur le site de
-- GSG (boutons de l'écran des conditions).
update public.cgu_versions set est_courante = false
 where est_courante and numero_version <> '1.0';

insert into public.cgu_versions (parcours, numero_version, contenu, est_courante)
values
('complet', '1.0', $cgu$Bienvenue sur EcoShop.

Avant de commencer, voici l'essentiel de notre accord, en quelques lignes.

Votre compte
• Un compte par personne. Il peut avoir plusieurs rôles (parent et enseignant, par exemple), mais il ne se partage pas.
• Votre code secret reste secret : GSG ne vous le demandera jamais.
• Si quelqu'un essaie d'ouvrir votre compte, touchez « Ce n'est pas moi ».

Le respect, pour tous
• Pas d'insultes, de menaces ni de harcèlement.
• Une attention particulière aux enfants : pas de contact en dehors des cadres prévus par l'école.

L'école reste aux commandes
• Notes, absences, tarifs, remises et décisions relèvent de l'école. Pour corriger une information scolaire, adressez-vous à elle.
• Le personnel garde confidentielles les informations des élèves et des familles.

Paiements et boutique
• L'argent va directement à l'école ou au vendeur : GSG ne le détient jamais.
• Le vendeur répond de ses produits, de la livraison et des remboursements.

Vos données
• Nous ne vendons jamais vos données et n'affichons aucune publicité ciblée.
• Vous pouvez voir, corriger ou effacer vos données, et supprimer votre compte depuis Mon profil.

L'intelligence artificielle propose, une personne décide.

Le texte complet des conditions et de la politique de confidentialité est accessible par les boutons ci-dessous. Une question : contact@globalservicegroupe.com$cgu$, true),
('simplifie', '1.0', $cgu$Bienvenue sur EcoShop !

EcoShop te permet de suivre ta scolarité : tes notes, ton emploi du temps, les annonces de ton école.

Quelques règles simples :
• Ton compte est à toi seul. Ne donne ton code secret à personne, même pas à un ami.
• Sois respectueux avec tout le monde. Les insultes et les moqueries sont interdites.
• Si un message te met mal à l'aise, signale-le ou parles-en à un adulte de ton école ou à tes parents.
• L'assistant d'aide aux devoirs t'aide à comprendre, pas à copier.

Ce que nous faisons de tes informations :
• Ton école et tes parents voient ta scolarité. Personne d'autre.
• Nous ne vendons jamais tes informations et il n'y a pas de publicité.
• Tu peux demander à les corriger, avec l'aide de tes parents ou de ton école.

Le texte complet est accessible par les boutons ci-dessous. Une question : demande à tes parents ou écris à contact@globalservicegroupe.com$cgu$, true)
on conflict (parcours, numero_version) do nothing;
