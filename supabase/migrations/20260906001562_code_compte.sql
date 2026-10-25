-- ============================================================================
-- EcoShop — REG-22 partie A (serveur) : code du compte, appareils à vérifier
-- ============================================================================
-- Faille corrigée : la connexion (code e-mail ou Google) suffisait à ouvrir
-- un compte sur un nouveau téléphone. Le code secret à 6 chiffres n'était
-- connu que du téléphone d'origine.
--
-- Désormais :
--   • le code devient celui du COMPTE, le même sur tous les appareils, vérifié
--     par le serveur sur tout nouvel appareil (toute nouvelle connexion) ;
--   • empreinte bcrypt (coût 10) d'un HMAC-SHA256 du code par un « poivre »
--     rangé dans le coffre (Vault) : une copie de la base seule ne permet pas
--     d'essayer le million de codes hors ligne ;
--   • 5 codes faux : nouveaux appareils bloqués 1 h, puis 24 h ;
--   • code oublié : autorisation depuis un appareil connu (10 min),
--     récupération par e-mail (effective après 48 h, annulable), ou déblocage
--     à l'école (direction ; direction et fondateur : administrateur GSG) ;
--   • « Ce n'est pas moi » : la session est fermée et les nouveaux appareils
--     restent bloqués jusqu'au changement du code depuis un appareil connu
--     (ou récupération, ou déblocage) ;
--   • contrôle central AVANT CHAQUE REQUÊTE de l'API (`controle_requete`,
--     enregistrée comme `pgrst.db_pre_request`) : session déconnectée →
--     SESSION_REVOQUEE ; appareil pas encore vérifié → APPAREIL_A_VERIFIER,
--     sauf la liste fermée des fonctions de vérification. Même contrôle dans
--     les politiques des fichiers (Storage).
--
-- Interrupteurs (parametres_globaux, sans migration) :
--   • code_compte_obligatoire (faux à la livraison) : vérification des
--     nouveaux appareils ;
--   • controle_sessions (vrai) : refus des sessions déconnectées.
-- Un compte sans code serveur passe : la mise en service ne coupe personne.
-- ============================================================================

alter type public.type_entite_journal_audit add value if not exists 'code_compte';

-- ---------------------------------------------------------------------------
-- 1. Réglages et poivre
-- ---------------------------------------------------------------------------
insert into public.parametres_globaux (cle, valeur, description) values
  ('code_compte_obligatoire', 'false'::jsonb,
   'REG-22 : vrai = tout nouvel appareil doit être vérifié par le code du compte.'),
  ('controle_sessions', 'true'::jsonb,
   'REG-22 : vrai = une session déconnectée est refusée dès la requête suivante.')
on conflict (cle) do nothing;

-- Le poivre est créé une fois, au hasard, dans le coffre ; il n'apparaît
-- jamais dans le dépôt. Sa perte invaliderait tous les codes : il suit la
-- sauvegarde des secrets (docs/OPERATIONS.md).
do $$
begin
  if to_regclass('vault.secrets') is not null
     and not exists (select 1 from vault.secrets where name = 'poivre_code_compte') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'poivre_code_compte',
      'REG-22 : poivre des empreintes du code du compte. Ne jamais changer (tous les codes seraient perdus).');
  end if;
end $$;

create or replace function public.parametre_vrai(p_cle text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select valeur = 'true'::jsonb from public.parametres_globaux where cle = p_cle), false);
$$;

create or replace function public.empreinte_code_compte(p_code text, p_empreinte text default null)
returns text
language plpgsql stable security definer set search_path = public, extensions
as $$
declare v_poivre text;
begin
  select decrypted_secret into v_poivre from vault.decrypted_secrets where name = 'poivre_code_compte';
  if v_poivre is null then
    raise exception 'POIVRE_ABSENT' using errcode = 'P0001';
  end if;
  return extensions.crypt(encode(extensions.hmac(p_code, v_poivre, 'sha256'), 'hex'),
                          coalesce(p_empreinte, extensions.gen_salt('bf', 10)));
end;
$$;
revoke all on function public.empreinte_code_compte(text, text) from public, anon, authenticated;
revoke all on function public.parametre_vrai(text) from public, anon;

-- Mêmes règles que l'application (ReglesCode.verifierChoix), hors date de
-- naissance (non connue du serveur).
create or replace function public.code_compte_evident(p_code text)
returns text
language plpgsql immutable set search_path = public
as $$
declare
  v_ch int[];
  v_mont boolean := true;
  v_desc boolean := true;
  i int;
begin
  if p_code is null or p_code !~ '^\d{6}$' then
    return 'CODE_FORMAT';
  end if;
  if p_code = any (array['123123','112233','121212','696969','159753','147258','258369','102030','100200',
                         '131313','123321','654321','111222','777777','999999','000000','123456','012345',
                         '987654','246810','135790','520520','101010','202020','112211','010203','224466','147852']) then
    return 'CODE_EVIDENT';
  end if;
  select array_agg(substr(p_code, n, 1)::int order by n) into v_ch from generate_series(1, 6) n;
  if (select count(distinct x) from unnest(v_ch) x) <= 2 then
    return 'CODE_EVIDENT';
  end if;
  for i in 2..6 loop
    if v_ch[i] <> (v_ch[i - 1] + 1) % 10 then v_mont := false; end if;
    if v_ch[i] <> (v_ch[i - 1] + 9) % 10 then v_desc := false; end if;
  end loop;
  if v_mont or v_desc or substr(p_code, 1, 3) = substr(p_code, 4, 3) then
    return 'CODE_EVIDENT';
  end if;
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Tables (aucune écriture directe ; empreintes jamais lisibles)
-- ---------------------------------------------------------------------------
create table if not exists public.codes_compte (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  empreinte text not null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.essais_code_compte (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  echecs integer not null default 0,
  palier integer not null default 0,
  bloque_jusqu_a timestamptz,
  motif_blocage text check (motif_blocage is null or motif_blocage in ('echecs', 'pas_moi')),
  updated_at timestamptz not null default now()
);

create table if not exists public.sessions_appareils (
  session_id uuid primary key references auth.sessions (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  modele text,
  systeme text,
  version_application text,
  statut text not null default 'a_verifier' check (statut in ('a_verifier', 'approuvee')),
  methode text check (methode is null or methode in
    ('creation', 'existant', 'code', 'appareil_connu', 'recuperation', 'ecole')),
  approuvee_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_sessions_appareils_profile on public.sessions_appareils (profile_id);

create table if not exists public.demandes_appareil (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  type text not null check (type in ('approbation', 'recuperation', 'ecole')),
  -- Session qui demande (approbation, récupération) ; nulle pour l'école.
  session_id uuid references auth.sessions (id) on delete set null,
  modele text,
  statut text not null default 'en_attente'
    check (statut in ('en_attente', 'approuvee', 'refusee', 'annulee', 'utilisee', 'expiree')),
  -- approbation et école : limite ; récupération : date d'effet.
  echeance timestamptz not null,
  auteur_id uuid references public.profiles (id) on delete set null,
  etablissement_id uuid references public.etablissements (id) on delete set null,
  motif text,
  traitee_par_session uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_demandes_appareil_profile on public.demandes_appareil (profile_id, statut);
create unique index if not exists idx_demandes_appareil_recup_unique
  on public.demandes_appareil (profile_id) where type = 'recuperation' and statut = 'en_attente';

-- Jetons « Ce n'est pas moi » des courriels (empreinte seulement, usage unique).
create table if not exists public.jetons_pas_moi (
  empreinte text primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  session_id uuid,
  expire_le timestamptz not null,
  utilise_le timestamptz,
  created_at timestamptz not null default now()
);

alter table public.codes_compte enable row level security;
alter table public.essais_code_compte enable row level security;
alter table public.sessions_appareils enable row level security;
alter table public.demandes_appareil enable row level security;
alter table public.jetons_pas_moi enable row level security;
revoke all on public.codes_compte, public.essais_code_compte, public.jetons_pas_moi from public, anon, authenticated;
revoke insert, update, delete on public.sessions_appareils, public.demandes_appareil from public, anon, authenticated;
grant select on public.sessions_appareils, public.demandes_appareil to authenticated;

drop policy if exists sessions_appareils_select on public.sessions_appareils;
create policy sessions_appareils_select on public.sessions_appareils for select to authenticated
  using (profile_id = auth.uid());
drop policy if exists demandes_appareil_select on public.demandes_appareil;
create policy demandes_appareil_select on public.demandes_appareil for select to authenticated
  using (profile_id = auth.uid() or auteur_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3. Session courante
-- ---------------------------------------------------------------------------
create or replace function public.session_courante()
returns uuid
language sql stable set search_path = public
as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id', '')::uuid;
$$;

-- Vrai si la requête de l'appelant peut aller plus loin que la vérification.
-- Sert à controle_requete (API) et aux politiques des fichiers (Storage).
create or replace function public.session_autorisee()
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  v_session uuid;
  v_uid uuid;
begin
  if v_claims is null or v_claims ->> 'role' is distinct from 'authenticated' then
    return true;
  end if;
  v_uid := nullif(v_claims ->> 'sub', '')::uuid;
  v_session := nullif(v_claims ->> 'session_id', '')::uuid;
  if v_session is null or v_uid is null then
    return true;  -- jeton sans session (jamais délivré par la connexion)
  end if;

  if public.parametre_vrai('controle_sessions')
     and not exists (select 1 from auth.sessions s
                     where s.id = v_session and s.user_id = v_uid
                       and (s.not_after is null or s.not_after > now())) then
    return false;
  end if;

  if public.parametre_vrai('code_compte_obligatoire')
     and exists (select 1 from public.codes_compte c where c.profile_id = v_uid)
     and not exists (select 1 from public.sessions_appareils a
                     where a.session_id = v_session and a.statut = 'approuvee') then
    return false;
  end if;
  return true;
end;
$$;

-- Fonctions permises avant la vérification (liste fermée).
create or replace function public.fonctions_avant_verification()
returns text[]
language sql immutable
as $$
  select array['etat_appareil', 'enregistrer_appareil', 'verifier_code_compte',
               'demander_approbation_appareil', 'lancer_recuperation_code',
               'finaliser_recuperation_code'];
$$;

-- Avant chaque requête de l'API de données (tables et fonctions).
create or replace function public.controle_requete()
returns void
language plpgsql stable security definer set search_path = public
as $$
declare
  v_claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  v_session uuid := nullif(v_claims ->> 'session_id', '')::uuid;
  v_uid uuid := nullif(v_claims ->> 'sub', '')::uuid;
  v_chemin text := coalesce(current_setting('request.path', true), '');
begin
  if v_claims is null or v_claims ->> 'role' is distinct from 'authenticated'
     or v_session is null or v_uid is null then
    return;
  end if;

  if public.parametre_vrai('controle_sessions')
     and not exists (select 1 from auth.sessions s
                     where s.id = v_session and s.user_id = v_uid
                       and (s.not_after is null or s.not_after > now())) then
    raise exception 'SESSION_REVOQUEE' using errcode = '42501',
      hint = 'Cet appareil a été déconnecté. Reconnectez-vous.';
  end if;

  if public.parametre_vrai('code_compte_obligatoire')
     and exists (select 1 from public.codes_compte c where c.profile_id = v_uid)
     and not exists (select 1 from public.sessions_appareils a
                     where a.session_id = v_session and a.statut = 'approuvee')
     and coalesce(substring(v_chemin from '/rpc/([a-z_]+)/?$'), '') <> all (public.fonctions_avant_verification()) then
    raise exception 'APPAREIL_A_VERIFIER' using errcode = '42501',
      hint = 'Saisissez le code de votre compte pour utiliser ce nouvel appareil.';
  end if;
end;
$$;
revoke all on function public.controle_requete() from public, anon;
grant execute on function public.controle_requete() to authenticated, anon, authenticator;

alter role authenticator set pgrst.db_pre_request to 'public.controle_requete';
notify pgrst, 'reload config';

-- Fichiers : même contrôle dans chaque politique.
drop policy if exists logos_etablissements_insert on storage.objects;
create policy logos_etablissements_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'logos-etablissements' and public.dossier_logo_autorise(name) and public.session_autorisee());
drop policy if exists logos_etablissements_update on storage.objects;
create policy logos_etablissements_update on storage.objects for update to authenticated
  using (bucket_id = 'logos-etablissements' and public.dossier_logo_autorise(name) and public.session_autorisee())
  with check (bucket_id = 'logos-etablissements' and public.dossier_logo_autorise(name) and public.session_autorisee());
drop policy if exists logos_etablissements_delete on storage.objects;
create policy logos_etablissements_delete on storage.objects for delete to authenticated
  using (bucket_id = 'logos-etablissements' and public.dossier_logo_autorise(name) and public.session_autorisee());
drop policy if exists pieces_inscription_insert on storage.objects;
create policy pieces_inscription_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'pieces-inscription' and public.piece_inscription_deposable(name) and public.session_autorisee());
drop policy if exists pieces_inscription_update on storage.objects;
create policy pieces_inscription_update on storage.objects for update to authenticated
  using (bucket_id = 'pieces-inscription' and public.piece_inscription_deposable(name) and public.session_autorisee())
  with check (bucket_id = 'pieces-inscription' and public.piece_inscription_deposable(name) and public.session_autorisee());
drop policy if exists pieces_inscription_select on storage.objects;
create policy pieces_inscription_select on storage.objects for select to authenticated
  using (bucket_id = 'pieces-inscription' and public.piece_inscription_lisible(name) and public.session_autorisee());

-- ---------------------------------------------------------------------------
-- 4. Briques internes
-- ---------------------------------------------------------------------------
create or replace function public.courriel_compte(p_profile uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select email from auth.users where id = p_profile;
$$;
revoke all on function public.courriel_compte(uuid) from public, anon, authenticated;

-- Courriel lié au code du compte (file existante).
create or replace function public.prevenir_compte(p_profile uuid, p_modele text, p_cle text, p_donnees jsonb default '{}')
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare v_prenom text;
begin
  select nullif(trim(prenom), '') into v_prenom from public.profiles where id = p_profile;
  perform public.mettre_notification_en_file(p_modele, p_cle,
    jsonb_build_object('prenom', v_prenom, 'date', to_char(now() at time zone 'Africa/Conakry', 'DD/MM/YYYY à HH24 h MI'))
      || coalesce(p_donnees, '{}'::jsonb),
    public.courriel_compte(p_profile));
end;
$$;
revoke all on function public.prevenir_compte(uuid, text, text, jsonb) from public, anon, authenticated;

-- Notification sur les appareils connus (push + liste de l'application).
create or replace function public.prevenir_appareils(p_profile uuid, p_type text, p_contenu text, p_variables jsonb)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare v_etab uuid;
begin
  select coalesce(p.etablissement_actif_id,
                  (select m.etablissement_id from public.etablissements_membres m
                    where m.profile_id = p.id and m.actif and m.deleted_at is null limit 1),
                  (select f.etablissement_id from public.relations_parent_eleve r
                     join public.fiches_eleves f on f.id = r.fiche_eleve_id
                    where r.parent_profile_id = p.id and r.deleted_at is null limit 1))
    into v_etab
  from public.profiles p where p.id = p_profile;
  if v_etab is null then
    return;  -- l'invite s'affichera à l'ouverture (etat_appareil)
  end if;
  insert into public.notifications (etablissement_id, destinataire, type, canal, contenu, variables, statut)
  values (v_etab, p_profile, p_type, 'push', p_contenu, coalesce(p_variables, '{}'::jsonb), 'en_attente');
end;
$$;
revoke all on function public.prevenir_appareils(uuid, text, text, jsonb) from public, anon, authenticated;

-- Jeton « Ce n'est pas moi » (le clair ne part que dans le courriel).
create or replace function public.creer_jeton_pas_moi(p_profile uuid, p_session uuid)
returns text
language plpgsql volatile security definer set search_path = public, extensions
as $$
declare v_jeton text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  insert into public.jetons_pas_moi (empreinte, profile_id, session_id, expire_le)
  values (encode(extensions.digest(v_jeton, 'sha256'), 'hex'), p_profile, p_session, now() + interval '7 days');
  return v_jeton;
end;
$$;
revoke all on function public.creer_jeton_pas_moi(uuid, uuid) from public, anon, authenticated;

-- Approuve une session de l'appelant (ou d'un compte donné).
create or replace function public.approuver_session(p_session uuid, p_profile uuid, p_methode text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  insert into public.sessions_appareils (session_id, profile_id, statut, methode, approuvee_le)
  values (p_session, p_profile, 'approuvee', p_methode, now())
  on conflict (session_id) do update
    set statut = 'approuvee', methode = excluded.methode, approuvee_le = now(), updated_at = now();
end;
$$;
revoke all on function public.approuver_session(uuid, uuid, text) from public, anon, authenticated;

create or replace function public.session_approuvee(p_session uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.sessions_appareils a
                 where a.session_id = p_session and a.profile_id = auth.uid() and a.statut = 'approuvee');
$$;
revoke all on function public.session_approuvee(uuid) from public, anon;

-- Session réelle et en cours pour l'appelant ; sinon erreur.
create or replace function public.exiger_session()
returns uuid
language plpgsql stable security definer set search_path = public
as $$
declare v_session uuid := public.session_courante();
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '42501';
  end if;
  if v_session is null or not exists (select 1 from auth.sessions s where s.id = v_session and s.user_id = auth.uid()) then
    raise exception 'SESSION_INCONNUE' using errcode = '42501';
  end if;
  return v_session;
end;
$$;
revoke all on function public.exiger_session() from public, anon;

-- Nouveau code posé (récupération, école, changement) : version +1, blocages levés.
create or replace function public.poser_code_compte(p_profile uuid, p_code text)
returns integer
language plpgsql volatile security definer set search_path = public
as $$
declare v_refus text := public.code_compte_evident(p_code); v_version integer;
begin
  if v_refus is not null then
    raise exception '%', v_refus using errcode = '22023';
  end if;
  insert into public.codes_compte (profile_id, empreinte)
  values (p_profile, public.empreinte_code_compte(p_code))
  on conflict (profile_id) do update
    set empreinte = excluded.empreinte, version = public.codes_compte.version + 1, updated_at = now()
  returning version into v_version;
  insert into public.essais_code_compte (profile_id) values (p_profile)
  on conflict (profile_id) do update
    set echecs = 0, palier = 0, bloque_jusqu_a = null, motif_blocage = null, updated_at = now();
  return v_version;
end;
$$;
revoke all on function public.poser_code_compte(uuid, text) from public, anon, authenticated;

-- « Ce n'est pas moi » : ferme la session, bloque les nouveaux appareils.
create or replace function public.bloquer_pas_moi(p_profile uuid, p_session uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if p_session is not null then
    delete from auth.sessions where id = p_session and user_id = p_profile;
  end if;
  insert into public.essais_code_compte (profile_id, bloque_jusqu_a, motif_blocage)
  values (p_profile, 'infinity', 'pas_moi')
  on conflict (profile_id) do update
    set bloque_jusqu_a = 'infinity', motif_blocage = 'pas_moi', updated_at = now();
  update public.demandes_appareil set statut = 'refusee', updated_at = now()
   where profile_id = p_profile and type = 'approbation' and statut = 'en_attente';
  perform public.prevenir_compte(p_profile, 'code_compte_appareils_bloques',
    'appareils_bloques:' || p_profile || ':' || extract(epoch from now())::bigint,
    jsonb_build_object('motif', 'pas_moi'));
end;
$$;
revoke all on function public.bloquer_pas_moi(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Fonctions de l'application
-- ---------------------------------------------------------------------------

-- État de l'appareil courant (permise avant vérification).
create or replace function public.etat_appareil()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_code public.codes_compte;
  v_essais public.essais_code_compte;
  v_statut text;
  v_approuve boolean;
begin
  select * into v_code from public.codes_compte where profile_id = auth.uid();
  select * into v_essais from public.essais_code_compte where profile_id = auth.uid();
  select statut into v_statut from public.sessions_appareils where session_id = v_session;
  v_approuve := v_statut = 'approuvee';

  return jsonb_build_object(
    'obligatoire', public.parametre_vrai('code_compte_obligatoire'),
    'a_un_code', v_code.profile_id is not null,
    'version_code', v_code.version,
    'statut', coalesce(v_statut, 'non_enregistre'),
    'prenom', (select nullif(trim(prenom), '') from public.profiles where id = auth.uid()),
    'bloque_jusqu_a', case when v_essais.bloque_jusqu_a > now() then v_essais.bloque_jusqu_a end,
    'motif_blocage', case when v_essais.bloque_jusqu_a > now() then v_essais.motif_blocage end,
    'essais_restants', 5 - coalesce(v_essais.echecs, 0),
    -- Ce que l'appareil a demandé lui-même.
    'mes_demandes', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'type', d.type, 'statut', d.statut, 'echeance', d.echeance)
                       order by d.created_at desc)
      from public.demandes_appareil d
      where d.profile_id = auth.uid() and d.session_id = v_session
        and d.statut in ('en_attente', 'approuvee') and d.created_at > now() - interval '3 days'), '[]'::jsonb),
    -- Ce qu'un appareil connu doit voir : demandes d'autres appareils.
    'a_traiter', case when v_approuve then coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'type', d.type, 'modele', d.modele, 'echeance', d.echeance,
                                          'demande_le', d.created_at) order by d.created_at)
      from public.demandes_appareil d
      where d.profile_id = auth.uid() and d.statut = 'en_attente'
        and d.session_id is distinct from v_session
        and d.type in ('approbation', 'recuperation')
        and (d.type = 'recuperation' or d.echeance > now())), '[]'::jsonb) else '[]'::jsonb end);
end;
$$;

-- Après chaque connexion : décrit l'appareil (permise avant vérification).
create or replace function public.enregistrer_appareil(p_modele text, p_systeme text, p_version text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_a_code boolean := exists (select 1 from public.codes_compte where profile_id = auth.uid());
  v_nouveau boolean;
begin
  insert into public.sessions_appareils (session_id, profile_id, modele, systeme, version_application, statut, methode, approuvee_le)
  values (v_session, auth.uid(), left(p_modele, 80), left(p_systeme, 40), left(p_version, 20),
          case when v_a_code then 'a_verifier' else 'approuvee' end,
          case when v_a_code then null else 'existant' end,
          case when v_a_code then null else now() end)
  on conflict (session_id) do update
    set modele = excluded.modele, systeme = excluded.systeme, version_application = excluded.version_application,
        updated_at = now()
  returning (xmax = 0) into v_nouveau;

  -- Nouvelle connexion d'un compte qui a un code : courriel d'alerte avec
  -- le lien « Ce n'est pas moi ».
  if v_nouveau and v_a_code then
    perform public.prevenir_compte(auth.uid(), 'code_compte_nouvel_appareil', 'nouvel_appareil:' || v_session,
      jsonb_build_object('modele', coalesce(nullif(left(p_modele, 80), ''), 'Appareil inconnu'),
                         'jeton_pas_moi', public.creer_jeton_pas_moi(auth.uid(), v_session)));
  end if;
  return public.etat_appareil();
end;
$$;

-- Premier code du compte (création, ou compte existant qui reprend son code
-- local). Toutes les sessions ouvertes à cet instant deviennent connues.
create or replace function public.definir_code_compte(p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_refus text := public.code_compte_evident(p_code);
  v_cree timestamptz;
begin
  if exists (select 1 from public.codes_compte where profile_id = auth.uid()) then
    raise exception 'CODE_DEJA_DEFINI' using errcode = '23505';
  end if;
  if v_refus is not null then
    raise exception '%', v_refus using errcode = '22023';
  end if;
  perform public.poser_code_compte(auth.uid(), p_code);
  select created_at into v_cree from public.profiles where id = auth.uid();

  insert into public.sessions_appareils (session_id, profile_id, statut, methode, approuvee_le)
  select s.id, s.user_id, 'approuvee',
         case when s.id = v_session and v_cree > now() - interval '1 day' then 'creation' else 'existant' end, now()
  from auth.sessions s where s.user_id = auth.uid()
  on conflict (session_id) do update set statut = 'approuvee', methode = excluded.methode,
                                         approuvee_le = now(), updated_at = now();
  return public.etat_appareil();
end;
$$;

-- Nouvel appareil : vérifie le code. 5 échecs → bloqué 1 h, puis 24 h.
create or replace function public.verifier_code_compte(p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_code public.codes_compte;
  v_essais public.essais_code_compte;
begin
  select * into v_code from public.codes_compte where profile_id = auth.uid() for update;
  if v_code.profile_id is null then
    raise exception 'AUCUN_CODE' using errcode = 'P0002';
  end if;
  insert into public.essais_code_compte (profile_id) values (auth.uid()) on conflict (profile_id) do nothing;
  select * into v_essais from public.essais_code_compte where profile_id = auth.uid() for update;

  if v_essais.bloque_jusqu_a > now() then
    raise exception 'CODE_BLOQUE' using errcode = '42501',
      detail = jsonb_build_object('jusqu_a', v_essais.bloque_jusqu_a, 'motif', v_essais.motif_blocage)::text;
  end if;

  if public.empreinte_code_compte(p_code, v_code.empreinte) = v_code.empreinte then
    update public.essais_code_compte set echecs = 0, palier = 0, bloque_jusqu_a = null, motif_blocage = null,
           updated_at = now() where profile_id = auth.uid();
    perform public.approuver_session(v_session, auth.uid(), 'code');
    return jsonb_build_object('resultat', 'bon', 'version_code', v_code.version);
  end if;

  v_essais.echecs := v_essais.echecs + 1;
  if v_essais.echecs >= 5 then
    update public.essais_code_compte
       set echecs = 0, palier = v_essais.palier + 1, motif_blocage = 'echecs', updated_at = now(),
           bloque_jusqu_a = now() + case when v_essais.palier = 0 then interval '1 hour' else interval '24 hours' end
     where profile_id = auth.uid()
    returning * into v_essais;
    perform public.prevenir_compte(auth.uid(), 'code_compte_appareils_bloques',
      'appareils_bloques:' || auth.uid() || ':' || v_essais.palier,
      jsonb_build_object('motif', 'echecs', 'jusqu_a',
                         to_char(v_essais.bloque_jusqu_a at time zone 'Africa/Conakry', 'DD/MM/YYYY à HH24 h MI')));
    return jsonb_build_object('resultat', 'bloque', 'jusqu_a', v_essais.bloque_jusqu_a);
  end if;
  update public.essais_code_compte set echecs = v_essais.echecs, updated_at = now() where profile_id = auth.uid();
  return jsonb_build_object('resultat', 'faux', 'essais_restants', 5 - v_essais.echecs);
end;
$$;

-- Depuis un appareil vérifié, en ligne. Lève tout blocage (« Ce n'est pas moi » compris).
create or replace function public.changer_code_compte(p_ancien text, p_nouveau text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_code public.codes_compte;
  v_version integer;
begin
  if not public.session_approuvee(v_session) then
    raise exception 'APPAREIL_A_VERIFIER' using errcode = '42501';
  end if;
  select * into v_code from public.codes_compte where profile_id = auth.uid() for update;
  if v_code.profile_id is null then
    raise exception 'AUCUN_CODE' using errcode = 'P0002';
  end if;
  if public.empreinte_code_compte(p_ancien, v_code.empreinte) <> v_code.empreinte then
    raise exception 'CODE_FAUX' using errcode = '42501';
  end if;
  v_version := public.poser_code_compte(auth.uid(), p_nouveau);
  perform public.prevenir_compte(auth.uid(), 'code_compte_change', 'code_change:' || auth.uid() || ':' || v_version);
  return jsonb_build_object('version_code', v_version);
end;
$$;

-- Voie (a) : demander l'autorisation à un appareil connu (10 min).
create or replace function public.demander_approbation_appareil()
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_essais public.essais_code_compte;
  v_modele text;
  v_id uuid;
begin
  if not exists (select 1 from public.codes_compte where profile_id = auth.uid()) then
    raise exception 'AUCUN_CODE' using errcode = 'P0002';
  end if;
  select * into v_essais from public.essais_code_compte where profile_id = auth.uid();
  if v_essais.motif_blocage = 'pas_moi' and v_essais.bloque_jusqu_a > now() then
    raise exception 'CODE_BLOQUE' using errcode = '42501',
      detail = jsonb_build_object('jusqu_a', v_essais.bloque_jusqu_a, 'motif', 'pas_moi')::text;
  end if;
  if not exists (select 1 from public.sessions_appareils a
                 where a.profile_id = auth.uid() and a.statut = 'approuvee' and a.session_id <> v_session) then
    raise exception 'AUCUN_APPAREIL_CONNU' using errcode = 'P0002';
  end if;
  select modele into v_modele from public.sessions_appareils where session_id = v_session;

  -- Une demande à la fois par appareil : la précédente est remplacée.
  update public.demandes_appareil set statut = 'expiree', updated_at = now()
   where profile_id = auth.uid() and session_id = v_session and type = 'approbation' and statut = 'en_attente';
  insert into public.demandes_appareil (profile_id, type, session_id, modele, echeance)
  values (auth.uid(), 'approbation', v_session, v_modele, now() + interval '10 minutes')
  returning id into v_id;

  perform public.prevenir_appareils(auth.uid(), 'appareil_a_autoriser',
    'Un nouvel appareil veut ouvrir votre compte : ' || coalesce(v_modele, 'appareil inconnu') || '. Est-ce vous ?',
    jsonb_build_object('demande_id', v_id, 'modele', v_modele));
  return jsonb_build_object('id', v_id, 'echeance', now() + interval '10 minutes');
end;
$$;

-- Appareil connu : « Autoriser » (code ou empreinte confirmés sur place).
create or replace function public.approuver_appareil(p_demande uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_d public.demandes_appareil;
begin
  if not public.session_approuvee(v_session) then
    raise exception 'APPAREIL_A_VERIFIER' using errcode = '42501';
  end if;
  select * into v_d from public.demandes_appareil
   where id = p_demande and profile_id = auth.uid() and type = 'approbation' for update;
  if v_d.id is null then
    raise exception 'DEMANDE_INCONNUE' using errcode = 'P0002';
  end if;
  if v_d.statut <> 'en_attente' or v_d.echeance <= now() then
    raise exception 'DEMANDE_EXPIREE' using errcode = '22023';
  end if;
  if v_d.session_id is null or v_d.session_id = v_session
     or not exists (select 1 from auth.sessions where id = v_d.session_id) then
    raise exception 'DEMANDE_EXPIREE' using errcode = '22023';
  end if;
  update public.demandes_appareil set statut = 'approuvee', traitee_par_session = v_session, updated_at = now()
   where id = v_d.id;
  perform public.approuver_session(v_d.session_id, auth.uid(), 'appareil_connu');
end;
$$;

-- Appareil connu : « Ce n'est pas moi ».
create or replace function public.refuser_appareil(p_demande uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_d public.demandes_appareil;
begin
  if not public.session_approuvee(v_session) then
    raise exception 'APPAREIL_A_VERIFIER' using errcode = '42501';
  end if;
  select * into v_d from public.demandes_appareil
   where id = p_demande and profile_id = auth.uid() and type = 'approbation' for update;
  if v_d.id is null then
    raise exception 'DEMANDE_INCONNUE' using errcode = 'P0002';
  end if;
  if v_d.session_id = v_session then
    raise exception 'DEMANDE_INCONNUE' using errcode = 'P0002';
  end if;
  update public.demandes_appareil set statut = 'refusee', traitee_par_session = v_session, updated_at = now()
   where id = v_d.id;
  perform public.bloquer_pas_moi(auth.uid(), v_d.session_id);
end;
$$;

-- Voie (b) : récupération par e-mail, effective 48 h après, annulable.
create or replace function public.lancer_recuperation_code()
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_d public.demandes_appareil;
begin
  if not exists (select 1 from public.codes_compte where profile_id = auth.uid()) then
    raise exception 'AUCUN_CODE' using errcode = 'P0002';
  end if;
  select * into v_d from public.demandes_appareil
   where profile_id = auth.uid() and type = 'recuperation' and statut = 'en_attente';
  if v_d.id is not null then
    if v_d.session_id is distinct from v_session then
      raise exception 'RECUPERATION_EN_COURS' using errcode = '23505';
    end if;
    return jsonb_build_object('id', v_d.id, 'echeance', v_d.echeance);
  end if;
  insert into public.demandes_appareil (profile_id, type, session_id, modele, echeance)
  values (auth.uid(), 'recuperation', v_session,
          (select modele from public.sessions_appareils where session_id = v_session), now() + interval '48 hours')
  returning * into v_d;
  perform public.prevenir_compte(auth.uid(), 'code_compte_recuperation_lancee', 'recuperation_lancee:' || v_d.id,
    jsonb_build_object('fin', to_char(v_d.echeance at time zone 'Africa/Conakry', 'DD/MM/YYYY à HH24 h MI'),
                       'modele', coalesce(v_d.modele, 'Appareil inconnu')));
  perform public.prevenir_appareils(auth.uid(), 'recuperation_code_lancee',
    'Une récupération du code de votre compte a été lancée. Si ce n''est pas vous, annulez-la.',
    jsonb_build_object('demande_id', v_d.id));
  return jsonb_build_object('id', v_d.id, 'echeance', v_d.echeance);
end;
$$;

create or replace function public.annuler_recuperation(p_demande uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare v_session uuid := public.exiger_session();
begin
  if not public.session_approuvee(v_session) then
    raise exception 'APPAREIL_A_VERIFIER' using errcode = '42501';
  end if;
  update public.demandes_appareil set statut = 'annulee', traitee_par_session = v_session, updated_at = now()
   where id = p_demande and profile_id = auth.uid() and type = 'recuperation' and statut = 'en_attente';
  if not found then
    raise exception 'DEMANDE_INCONNUE' using errcode = 'P0002';
  end if;
end;
$$;

-- Nouveau code après récupération mûre (même appareil, 48 h écoulées) ou
-- déblocage à l'école en cours (30 min). L'appareil devient connu.
create or replace function public.finaliser_recuperation_code(p_nouveau text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_session uuid := public.exiger_session();
  v_d public.demandes_appareil;
  v_methode text;
  v_version integer;
begin
  select * into v_d from public.demandes_appareil
   where profile_id = auth.uid() and statut = 'en_attente'
     and ((type = 'ecole' and echeance > now())
       or (type = 'recuperation' and session_id = v_session and echeance <= now()))
   order by (type = 'ecole') desc, created_at desc
   limit 1
   for update;
  if v_d.id is null then
    if exists (select 1 from public.demandes_appareil
               where profile_id = auth.uid() and type = 'recuperation' and statut = 'en_attente'
                 and session_id = v_session) then
      raise exception 'RECUPERATION_TROP_TOT' using errcode = '22023';
    end if;
    raise exception 'AUCUNE_RECUPERATION' using errcode = 'P0002';
  end if;

  v_version := public.poser_code_compte(auth.uid(), p_nouveau);
  v_methode := case v_d.type when 'ecole' then 'ecole' else 'recuperation' end;
  update public.demandes_appareil set statut = 'utilisee', traitee_par_session = v_session, updated_at = now()
   where id = v_d.id;
  perform public.approuver_session(v_session, auth.uid(), v_methode);
  perform public.prevenir_compte(auth.uid(), 'code_compte_recuperation_terminee', 'recuperation_terminee:' || v_d.id,
    jsonb_build_object('voie', v_methode));
  return jsonb_build_object('version_code', v_version);
end;
$$;

-- Voie (c) : la direction débloque, la personne étant présente. Direction et
-- fondateur : administrateur GSG seulement. Jamais soi-même.
create or replace function public.debloquer_code_membre(p_compte uuid, p_motif text, p_etablissement uuid default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_gsg boolean := coalesce(public.est_admin_gsg(), false);
  v_cible_dirige boolean;
  v_lien boolean;
  v_id uuid;
begin
  perform public.exiger_session();
  if p_compte = auth.uid() then
    raise exception 'DEBLOCAGE_SOI_MEME' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_motif, ''))) < 5 then
    raise exception 'MOTIF_OBLIGATOIRE' using errcode = '22023';
  end if;
  if not exists (select 1 from public.codes_compte where profile_id = p_compte) then
    raise exception 'AUCUN_CODE' using errcode = 'P0002';
  end if;

  v_cible_dirige := exists (
    select 1 from public.etablissements_membres m
    where m.profile_id = p_compte and m.actif and m.deleted_at is null
      and m.role_dans_etablissement in ('direction', 'fondateur_reseau'))
    or exists (select 1 from public.profiles where id = p_compte and role_racine in ('direction', 'fondateur_reseau', 'admin_gsg'));

  if not v_gsg then
    if p_etablissement is null or not coalesce(public.est_direction(p_etablissement), false) then
      raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
    end if;
    if v_cible_dirige then
      raise exception 'DEBLOCAGE_DIRECTION_PAR_GSG' using errcode = '42501';
    end if;
    v_lien := exists (select 1 from public.etablissements_membres m
                      where m.profile_id = p_compte and m.etablissement_id = p_etablissement
                        and m.actif and m.deleted_at is null)
           or exists (select 1 from public.fiches_eleves f
                      where f.profile_id = p_compte and f.etablissement_id = p_etablissement and f.deleted_at is null)
           or exists (select 1 from public.relations_parent_eleve r
                        join public.fiches_eleves f on f.id = r.fiche_eleve_id
                      where r.parent_profile_id = p_compte and f.etablissement_id = p_etablissement
                        and r.statut = 'confirmee' and r.deleted_at is null);
    if not v_lien then
      raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
    end if;
  end if;

  update public.demandes_appareil set statut = 'expiree', updated_at = now()
   where profile_id = p_compte and type = 'ecole' and statut = 'en_attente';
  insert into public.demandes_appareil (profile_id, type, echeance, auteur_id, etablissement_id, motif)
  values (p_compte, 'ecole', now() + interval '30 minutes', auth.uid(), p_etablissement, trim(p_motif))
  returning id into v_id;

  perform public.enregistrer_audit(p_etablissement, 'code_compte', p_compte, 'deblocage', null,
    jsonb_build_object('motif', trim(p_motif), 'par_gsg', v_gsg, 'demande_id', v_id));
  return jsonb_build_object('id', v_id, 'echeance', now() + interval '30 minutes');
end;
$$;

-- Lien « Ce n'est pas moi » du courriel (Edge Function pas_moi, service_role).
create or replace function public.pas_moi_par_jeton(p_jeton text)
returns text
language plpgsql volatile security definer set search_path = public, extensions
as $$
declare v_j public.jetons_pas_moi;
begin
  select * into v_j from public.jetons_pas_moi
   where empreinte = encode(extensions.digest(coalesce(p_jeton, ''), 'sha256'), 'hex') for update;
  if v_j.empreinte is null or v_j.expire_le <= now() then
    return 'invalide';
  end if;
  if v_j.utilise_le is not null then
    return 'deja_fait';
  end if;
  update public.jetons_pas_moi set utilise_le = now() where empreinte = v_j.empreinte;
  perform public.bloquer_pas_moi(v_j.profile_id, v_j.session_id);
  return 'fait';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Droits
-- ---------------------------------------------------------------------------
revoke all on function public.etat_appareil() from public, anon;
revoke all on function public.enregistrer_appareil(text, text, text) from public, anon;
revoke all on function public.definir_code_compte(text) from public, anon;
revoke all on function public.verifier_code_compte(text) from public, anon;
revoke all on function public.changer_code_compte(text, text) from public, anon;
revoke all on function public.demander_approbation_appareil() from public, anon;
revoke all on function public.approuver_appareil(uuid) from public, anon;
revoke all on function public.refuser_appareil(uuid) from public, anon;
revoke all on function public.lancer_recuperation_code() from public, anon;
revoke all on function public.annuler_recuperation(uuid) from public, anon;
revoke all on function public.finaliser_recuperation_code(text) from public, anon;
revoke all on function public.debloquer_code_membre(uuid, text, uuid) from public, anon;
grant execute on function public.etat_appareil(), public.enregistrer_appareil(text, text, text),
  public.definir_code_compte(text), public.verifier_code_compte(text), public.changer_code_compte(text, text),
  public.demander_approbation_appareil(), public.approuver_appareil(uuid), public.refuser_appareil(uuid),
  public.lancer_recuperation_code(), public.annuler_recuperation(uuid), public.finaliser_recuperation_code(text),
  public.debloquer_code_membre(uuid, text, uuid) to authenticated;
revoke all on function public.pas_moi_par_jeton(text) from public, anon, authenticated;
grant execute on function public.pas_moi_par_jeton(text) to service_role;

-- ---------------------------------------------------------------------------
-- 7. Journal : la direction voit les déblocages de son école
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

  if v_row.etablissement_id is not null
     and public.droit(v_row.etablissement_id, array['audit.journal.lire']) then
    return true;
  end if;

  return case v_row.entite
    when 'inscription' then
      public.droit(v_row.etablissement_id, array['scolarite.inscription.gerer', 'scolarite.eleve.gerer'])
      or public.fiche_famille(v_row.fiche_eleve_id)
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
      coalesce(public.voit_encaissements(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'transaction_mobile_money' then
      coalesce(public.voit_encaissements(v_row.etablissement_id), false)
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
    when 'code_compte' then
      v_row.entite_id = auth.uid()
      or coalesce(public.est_direction(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    else false
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Contrôle de préparation : le poivre est dans le coffre
-- ---------------------------------------------------------------------------
create or replace function public.parametres_globaux_attendus()
returns setof text
language sql immutable set search_path = public
as $$
  values
    ('seuil_effectif_gratuit'), ('commission_marketplace_pct'), ('devise_defaut'),
    ('liaison_tentatives_max'), ('invitation_validite_jours'),
    ('bareme_licence_pro'), ('tarif_frais_ia_admin_annuel'),
    ('tarif_abonnement_premium_eleve_mensuel'), ('tarif_abonnement_premium_eleve_annuel'),
    ('quota_tuteur_ia_free_mensuel'), ('anti_rafale_ia'), ('poids_type_conversation_ia'),
    ('seuil_anomalie_usage_ia_quotidien'), ('duree_retention_journal_audit'),
    ('code_compte_obligatoire'), ('controle_sessions')
$$;

create or replace function public.etat_mise_en_service()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_controles jsonb := '[]'::jsonb;
  v_ok boolean;
  v_detail text;
  t record;
  v_present boolean;
  v_dernier text;
begin
  -- Un compte connecté doit être de l'équipe GSG ; sans compte, c'est le
  -- serveur (script de déploiement, service_role).
  if auth.uid() is not null and not public.est_admin_gsg() then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  -- Extensions
  for t in select unnest(array['pg_cron', 'pg_net']) as ext loop
    v_ok := exists (select 1 from pg_extension where extname = t.ext);
    v_controles := v_controles || jsonb_build_object('controle', 'Extension ' || t.ext, 'ok', v_ok,
      'detail', case when v_ok then 'activée' else 'à activer (Database → Extensions)' end);
  end loop;

  -- Tâches planifiées (lecture dynamique : pg_cron peut être absent)
  for t in select * from public.taches_planifiees_attendues() loop
    v_present := false; v_dernier := null;
    if to_regclass('cron.job') is not null then
      execute 'select exists (select 1 from cron.job where jobname = $1 and active)' into v_present using t.nom;
      if v_present and to_regclass('cron.job_run_details') is not null then
        execute 'select d.status || '' le '' || to_char(d.start_time at time zone ''UTC'', ''DD/MM HH24:MI'') || '' UTC''
                   from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                  where j.jobname = $1 order by d.start_time desc limit 1'
          into v_dernier using t.nom;
      end if;
    end if;
    v_controles := v_controles || jsonb_build_object('controle', 'Tâche « ' || t.nom || ' »', 'ok', v_present,
      'detail', t.role || case when v_present then coalesce(' — dernier passage : ' || v_dernier, ' — pas encore exécutée')
                               else ' — absente' end);
  end loop;

  -- Secrets rangés dans le coffre (présence seulement)
  for t in select unnest(array['ecoshop_url_projet', 'notifications_declencheur_secret', 'paiements_declencheur_secret',
                           'poivre_code_compte']) as nom loop
    v_present := false;
    if to_regclass('vault.secrets') is not null then
      execute 'select exists (select 1 from vault.secrets where name = $1)' into v_present using t.nom;
    end if;
    v_controles := v_controles || jsonb_build_object('controle', 'Coffre : ' || t.nom, 'ok', v_present,
      'detail', case when v_present then 'rangé' else 'absent' end);
  end loop;

  -- Administrateur GSG
  v_ok := exists (select 1 from public.profiles where role_racine = 'admin_gsg' and deleted_at is null);
  v_controles := v_controles || jsonb_build_object('controle', 'Administrateur GSG', 'ok', v_ok,
    'detail', case when v_ok then 'désigné' else 'à désigner (premier_admin.modele.sql)' end);

  -- Packs SMS
  select string_agg(code, ', ') into v_detail from public.packs_sms where actif and prix > 0;
  v_ok := v_detail is not null;
  v_controles := v_controles || jsonb_build_object('controle', 'Packs SMS en vente', 'ok', v_ok,
    'detail', coalesce(v_detail, 'aucun : fixer les prix (écran Crédits SMS GSG)'));

  -- Référentiel : pays proposés à la demande d'ouverture
  select string_agg(code_iso, ', ' order by code_iso) into v_detail
  from public.pays_pedagogiques where statut_deploiement = 'deploye';
  v_ok := v_detail is not null;
  v_controles := v_controles || jsonb_build_object('controle', 'Référentiel : pays ouverts', 'ok', v_ok,
    'detail', coalesce(v_detail, 'aucun : la demande d''ouverture n''a aucun pays à proposer'));

  -- Référentiel : chaque pays ouvert a ses cycles, niveaux et examens publiés
  select string_agg(p.code_iso || ' (' || concat_ws(', ',
           case when not exists (select 1 from public.cycles_educatifs c
                                 where c.pays_code = p.code_iso and c.statut = 'publie') then 'aucun cycle' end,
           case when not exists (select 1 from public.niveaux_educatifs n
                                 where n.pays_code = p.code_iso and n.statut = 'publie') then 'aucun niveau' end,
           case when not exists (select 1 from public.examens_nationaux x
                                 where x.pays_code = p.code_iso and x.statut = 'publie') then 'aucun examen' end) || ')',
         ', ' order by p.code_iso)
    into v_detail
  from public.pays_pedagogiques p
  where p.statut_deploiement = 'deploye'
    and (not exists (select 1 from public.cycles_educatifs c where c.pays_code = p.code_iso and c.statut = 'publie')
      or not exists (select 1 from public.niveaux_educatifs n where n.pays_code = p.code_iso and n.statut = 'publie')
      or not exists (select 1 from public.examens_nationaux x where x.pays_code = p.code_iso and x.statut = 'publie'));
  v_ok := v_detail is null
          and exists (select 1 from public.pays_pedagogiques where statut_deploiement = 'deploye');
  v_controles := v_controles || jsonb_build_object('controle', 'Référentiel : cycles, niveaux, examens', 'ok', v_ok,
    'detail', case
      when v_detail is not null then 'incomplet : ' || v_detail
      when not v_ok then 'vide : aucun pays ouvert'
      else (select count(*) || ' niveaux, ' from public.niveaux_educatifs where statut = 'publie')
           || (select count(*) || ' examens publiés' from public.examens_nationaux where statut = 'publie')
    end);

  -- Paramètres globaux
  select string_agg(a.cle, ', ' order by a.cle) into v_detail
  from public.parametres_globaux_attendus() as a(cle)
  where not exists (select 1 from public.parametres_globaux g where g.cle = a.cle);
  v_ok := v_detail is null;
  v_controles := v_controles || jsonb_build_object('controle', 'Paramètres globaux', 'ok', v_ok,
    'detail', case when v_ok then (select count(*) || ' réglages présents' from public.parametres_globaux)
                   else 'manquants : ' || v_detail end);

  return jsonb_build_object(
    'pret', not exists (select 1 from jsonb_array_elements(v_controles) c where not (c ->> 'ok')::boolean),
    'controles', v_controles);
end;
$$;
