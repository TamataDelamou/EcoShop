-- ============================================================================
-- EcoShop — M16 — Sous-livrable 3/7 : Edge Functions IA + Tuteur IA /
-- Directeur-Adviser
--
-- Porte l'architecture de ecoshop_flutter/CHAT_IA_GROUNDING.md (3 couches) :
--   1. Déclenchement structuré (bouton, pas de texte libre) ;
--   2. Réponse groundée — chiffres réels injectés dans un seul appel
--      Anthropic, sans outil ;
--   3. Détail nominatif optionnel — tool_use Anthropic, pseudonymisation
--      stricte, mapping pseudonyme→identité jamais transmis à Anthropic.
--
-- Le principe source « le client n'appelle jamais l'API IA en direct » se
-- traduit ici par : le client n'écrit JAMAIS lui-même les champs de
-- gating (`grounding`/`cible_type`/`cible_id`) sur `ai_conversations` — ce
-- correctif de sécurité (trouvé APRÈS coup côté source, cf.
-- CHAT_IA_GROUNDING.md §6) est construit ICI DÈS LA CONCEPTION : la policy
-- d'INSERT cliente force `grounding = false`/cibles nulles ; seule la
-- fonction SECURITY DEFINER `preparer_analyse_risque_echec` (jamais
-- appelable directement par le client — c'est l'Edge Function
-- `demarrer_analyse_risque_echec` qui l'appelle pour le compte de
-- l'utilisateur authentifié) peut poser ces champs.
--
-- Aucune nouvelle formule de risque : consomme `risque_reussite_actuel`/
-- `materialiser_risque_reussite` (sous-livrable 1/7) — seuil 0.6 identique.
--
-- Hors périmètre, documenté (voir rapport de ce sous-livrable) : le
-- rapport « échéances de paiement » (second type de conversation groundée
-- côté source) — extension future de la même infra, pas un écart oublié.
-- Le ciblage `cible_type = 'eleve'` n'est pas non plus exposé (même limite
-- déjà documentée côté source).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.role_ia as enum ('eleve', 'enseignant', 'direction');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.type_conversation_ia as enum ('libre', 'risque_echec');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 1. Conversations IA — une conversation appartient à SON auteur, jamais
--    partagée entre membres du personnel (même sémantique que
--    /utilisateurs/{uid}/ai_conversations côté source).
-- ---------------------------------------------------------------------------
create table if not exists public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  type public.type_conversation_ia not null default 'libre',
  grounding boolean not null default false,
  cible_type text check (cible_type in ('etablissement', 'classe')),
  cible_id uuid,
  created_at timestamptz not null default now(),
  constraint ai_conversations_cible_coherente check (
    (cible_type is null and cible_id is null)
    or (cible_type = 'etablissement' and cible_id is null)
    or (cible_type = 'classe' and cible_id is not null)
  )
);

-- ---------------------------------------------------------------------------
-- 2. Messages — immuables une fois créés (même discipline que la source :
--    historique jamais modifié après coup).
-- ---------------------------------------------------------------------------
create table if not exists public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.ai_conversations (id) on delete cascade,
  sender text not null check (sender in ('user', 'assistant')),
  content text not null check (length(content) > 0),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 3. Rôle IA réel — jamais celui envoyé par le client, toujours recalculé
--    ici à partir de l'appartenance réelle à l'établissement. Retourne
--    NULL si l'appelant n'a aucun rôle IA pour cet établissement (ex.
--    parent — Parent IA est un mécanisme séparé, pas un persona de chat,
--    voir sous-livrable 4/7) : le chat lui reste alors fermé, même
--    comportement que la source (`PROMPTS[role]` absent → accès refusé).
-- ---------------------------------------------------------------------------
-- `p_profile_id` par défaut `auth.uid()` (évalué à chaque appel) pour tous
-- les appels existants ; explicite dans le garde-fou tenant ci-dessous
-- (validation d'une LIGNE, jamais de la session appelante — même
-- distinction que partout ailleurs dans ce schéma, ex. `ENSEIGNANT_NON_MEMBRE`).
create or replace function public.determiner_role_ia(
  p_etablissement_id uuid,
  p_profile_id uuid default auth.uid()
)
returns public.role_ia
language sql stable security definer set search_path = public
as $$
  select case
    when exists (
      select 1 from public.etablissements_membres m
      where m.profile_id = p_profile_id
        and m.etablissement_id = p_etablissement_id
        and m.role_dans_etablissement in ('direction', 'fondateur_reseau')
        and m.actif and m.deleted_at is null
    ) then 'direction'::public.role_ia
    when exists (
      select 1 from public.etablissements_membres m
      where m.profile_id = p_profile_id
        and m.etablissement_id = p_etablissement_id
        and m.role_dans_etablissement = 'enseignant'
        and m.actif and m.deleted_at is null
    ) then 'enseignant'::public.role_ia
    when exists (
      select 1 from public.fiches_eleves f
      where f.profile_id = p_profile_id
        and f.etablissement_id = p_etablissement_id
        and f.deleted_at is null
    ) then 'eleve'::public.role_ia
    else null
  end;
$$;

grant execute on function public.determiner_role_ia(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Garde-fou tenant — l'auteur doit avoir un rôle IA réel dans
--    l'établissement déclaré ; une cible « classe » doit appartenir au
--    même établissement.
-- ---------------------------------------------------------------------------
create or replace function public.ai_conversations_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  if public.determiner_role_ia(new.etablissement_id, new.profile_id) is null then
    raise exception 'PROFILE_SANS_ROLE_IA' using errcode = '23514';
  end if;

  if new.cible_type = 'classe' then
    select etablissement_id into v_etab from public.classes where id = new.cible_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists ai_conversations_verifie_tenant_trg on public.ai_conversations;
create trigger ai_conversations_verifie_tenant_trg
  before insert on public.ai_conversations
  for each row execute procedure public.ai_conversations_verifie_tenant();

-- ---------------------------------------------------------------------------
-- 5. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;

-- Lecture : uniquement l'auteur (pas de partage entre personnel, même
-- sémantique que la source).
drop policy if exists "ai_conversations_select_auteur" on public.ai_conversations;
create policy "ai_conversations_select_auteur" on public.ai_conversations
  for select using (profile_id = auth.uid());

-- Écriture cliente : UNIQUEMENT une conversation libre, sans grounding ni
-- cible — ★ correctif de sécurité source (CHAT_IA_GROUNDING.md §6)
-- construit ICI dès la conception, jamais après coup. Les champs de
-- gating ne sont posés QUE par `preparer_analyse_risque_echec`
-- (SECURITY DEFINER, contourne cette policy en tant que propriétaire de
-- la table — jamais par un INSERT client direct).
drop policy if exists "ai_conversations_insert_libre" on public.ai_conversations;
create policy "ai_conversations_insert_libre" on public.ai_conversations
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and type = 'libre'
    and grounding = false
    and cible_type is null
    and cible_id is null
  );

-- Aucune policy update/delete : conversations immuables une fois créées,
-- même discipline que la source.

-- Messages : lecture/écriture réservées à l'auteur de la conversation
-- parente, jamais de modification/suppression après création.
drop policy if exists "ai_messages_select_auteur" on public.ai_messages;
create policy "ai_messages_select_auteur" on public.ai_messages
  for select using (
    exists (
      select 1 from public.ai_conversations c
      where c.id = conversation_id and c.profile_id = auth.uid()
    )
  );

drop policy if exists "ai_messages_insert_auteur" on public.ai_messages;
create policy "ai_messages_insert_auteur" on public.ai_messages
  for insert to authenticated
  with check (
    sender in ('user', 'assistant')
    and exists (
      select 1 from public.ai_conversations c
      where c.id = conversation_id and c.profile_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 6. Couche 2 — déclenchement de l'analyse groundée « risque d'échec ».
--    Résout la cible RÉELLEMENT (jamais une confiance dans le sélecteur
--    client), rafraîchit la source unique (`materialiser_risque_reussite`,
--    sous-livrable 1/7), calcule l'agrégat, crée la conversation. Ne fait
--    AUCUN appel Anthropic (Postgres ne fait pas de HTTP sortant ici) —
--    c'est l'Edge Function `demarrer_analyse_risque_echec` qui, après avoir
--    reçu ce résultat, construit le message synthétique et appelle
--    Anthropic UNE fois, sans outil (couche 2 stricte, pas de tool_use).
-- ---------------------------------------------------------------------------
create or replace function public.preparer_analyse_risque_echec(
  p_etablissement_id uuid,
  p_cible_type text,
  p_cible_id uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_annee uuid;
  v_classe_nom text;
  v_effectif int;
  v_eleves_a_risque int;
  v_conversation_id uuid;
  v_label text;
begin
  if public.determiner_role_ia(p_etablissement_id) is distinct from 'direction'::public.role_ia then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  if p_cible_type not in ('etablissement', 'classe') then
    raise exception 'CIBLE_INVALIDE' using errcode = '22023';
  end if;
  if p_cible_type = 'classe' and p_cible_id is null then
    raise exception 'CIBLE_INVALIDE' using errcode = '22023';
  end if;
  if p_cible_type = 'etablissement' and p_cible_id is not null then
    raise exception 'CIBLE_INVALIDE' using errcode = '22023';
  end if;

  select id into v_annee from public.annees_scolaires
  where etablissement_id = p_etablissement_id and courante
  limit 1;
  if v_annee is null then
    raise exception 'ANNEE_COURANTE_INTROUVABLE' using errcode = '22023';
  end if;

  if p_cible_type = 'classe' then
    select nom into v_classe_nom from public.classes
    where id = p_cible_id and etablissement_id = p_etablissement_id and deleted_at is null;
    if v_classe_nom is null then
      raise exception 'CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
    v_label := 'la classe ' || v_classe_nom;
  else
    v_label := 'l''établissement';
  end if;

  select count(distinct i.fiche_eleve_id) into v_effectif
  from public.inscriptions i
  where i.annee_scolaire_id = v_annee and i.statut = 'active' and i.deleted_at is null
    and (p_cible_type = 'etablissement' or i.classe_id = p_cible_id);

  -- Rafraîchit la source unique avant de compter — jamais un second calcul.
  perform public.materialiser_risque_reussite(p_etablissement_id, v_annee);

  select count(*) into v_eleves_a_risque
  from public.statistiques_agregats sa
  join public.inscriptions i
    on i.fiche_eleve_id = sa.fiche_eleve_id and i.annee_scolaire_id = sa.annee_scolaire_id
  where sa.etablissement_id = p_etablissement_id and sa.annee_scolaire_id = v_annee
    and sa.type_agregat = 'risque_reussite' and sa.valeur_numeric >= 0.6
    and i.statut = 'active' and i.deleted_at is null
    and (p_cible_type = 'etablissement' or i.classe_id = p_cible_id);

  insert into public.ai_conversations
    (etablissement_id, profile_id, type, grounding, cible_type, cible_id)
  values
    (p_etablissement_id, auth.uid(), 'risque_echec', true, p_cible_type, p_cible_id)
  returning id into v_conversation_id;

  return jsonb_build_object(
    'conversation_id', v_conversation_id,
    'effectif', v_effectif,
    'eleves_a_risque', v_eleves_a_risque,
    'cible_label', v_label
  );
end;
$$;

revoke execute on function public.preparer_analyse_risque_echec(uuid, text, uuid) from public, anon;
grant execute on function public.preparer_analyse_risque_echec(uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Couche 3 — détail nominatif. Re-vérifie TOUT à chaque appel (jamais
--    une confiance dans une validation faite une seule fois à la création
--    de la conversation) : propriété de la conversation, grounding actif,
--    type risque_echec, rôle direction toujours réel dans l'établissement.
--    Retourne les données RÉELLES (nom/matricule) — la pseudonymisation
--    elle-même (tri déterministe, whitelist par objet littéral, jamais de
--    spread) est construite côté Edge Function (TypeScript), pas ici —
--    ce canal n'ouvre aucun accès nouveau : une direction peut déjà lire
--    ces mêmes champs sur `fiches_eleves` de son établissement.
-- ---------------------------------------------------------------------------
create or replace function public.obtenir_detail_risque_echec_interne(p_conversation_id uuid)
returns table (
  fiche_id uuid,
  matricule text,
  nom text,
  prenom text,
  classe_id uuid,
  score numeric
)
language plpgsql security definer set search_path = public
as $$
declare
  v_conv record;
begin
  select * into v_conv from public.ai_conversations c
  where c.id = p_conversation_id and c.profile_id = auth.uid();

  if v_conv is null then
    raise exception 'CONVERSATION_INTROUVABLE' using errcode = '42501';
  end if;
  if not v_conv.grounding or v_conv.type <> 'risque_echec' then
    raise exception 'OUTIL_NON_DISPONIBLE' using errcode = '42501';
  end if;
  if public.determiner_role_ia(v_conv.etablissement_id) is distinct from 'direction'::public.role_ia then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  return query
  select f.id, f.matricule, f.nom, f.prenom, i.classe_id, sa.valeur_numeric
  from public.statistiques_agregats sa
  join public.inscriptions i
    on i.fiche_eleve_id = sa.fiche_eleve_id and i.annee_scolaire_id = sa.annee_scolaire_id
  join public.fiches_eleves f on f.id = sa.fiche_eleve_id
  where sa.etablissement_id = v_conv.etablissement_id
    and sa.type_agregat = 'risque_reussite' and sa.valeur_numeric >= 0.6
    and i.statut = 'active' and i.deleted_at is null and f.deleted_at is null
    and (v_conv.cible_type = 'etablissement' or i.classe_id = v_conv.cible_id)
    and sa.annee_scolaire_id = (
      select id from public.annees_scolaires
      where etablissement_id = v_conv.etablissement_id and courante
      limit 1
    )
  order by f.matricule;
end;
$$;

revoke execute on function public.obtenir_detail_risque_echec_interne(uuid) from public, anon;
grant execute on function public.obtenir_detail_risque_echec_interne(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Index
-- ---------------------------------------------------------------------------
create index if not exists idx_ai_conversations_profile on public.ai_conversations (profile_id, created_at desc);
create index if not exists idx_ai_messages_conversation on public.ai_messages (conversation_id, created_at);

-- ============================================================================
-- Fin patch M16 — infrastructure Edge Functions IA.
-- ============================================================================
