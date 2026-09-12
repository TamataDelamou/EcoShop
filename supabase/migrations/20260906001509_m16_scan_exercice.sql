-- ============================================================================
-- EcoShop — M16 — Sous-livrable 5/7 : Scan et résolution d'exercice
-- (cahier §21.5)
-- ============================================================================
-- Fonctionnalité ENTIÈREMENT NOUVELLE — absente d'ecoshop_flutter (absorbée
-- du module M14 d'EduRéussite, jamais portée depuis la source EcoShop) : voir
-- ANALYSE_GLOBALE.md, section M16 5/7, "N/A — nouvelle fonctionnalité".
--
-- Flux respecté à la lettre (cahier §21.5) : photo → reconnaissance de texte
-- → identification matière/chapitre → analyse du problème → proposition de
-- méthode → guidage progressif → correction finale détaillée.
--
-- Choix d'architecture actés avec l'utilisateur avant codage (voir rapport de
-- ce sous-livrable) :
--   1. Caméra/OCR : reconnaissance de texte 100% EMBARQUÉE sur l'appareil
--      (Google ML Kit Text Recognition, hors ligne par construction — aucun
--      modèle téléchargé à la demande). Conséquence structurante ICI : LA
--      PHOTO NE QUITTE JAMAIS L'APPAREIL — seul le TEXTE reconnu (déjà du
--      texte, jamais une image) est envoyé au serveur/à Anthropic. Protection
--      mineur strictement supérieure à ce qu'imposait le cahier littéral
--      (aucun stockage Supabase Storage nécessaire, donc aucune fuite
--      possible de la photo elle-même) — même philosophie de minimisation
--      des données que Parent IA (4/7, chiffres agrégés uniquement).
--   2. Chapitre : reste une INFÉRENCE LIBRE de l'IA, affichée à l'écran,
--      JAMAIS persistée dans une table de référentiel — aucune table
--      `chapitres_matieres` n'existe dans le M4 (référentiel pédagogique) ;
--      en créer une sans contenu curaté derrière serait une fausse promesse
--      de structure (décision explicite de l'utilisateur). Par cohérence, la
--      MATIÈRE identifiée par l'IA est traitée de la même façon (texte libre,
--      `matiere_libelle`), plutôt qu'un rattachement FK fragile à
--      `programmes_matieres` (M4) — cette table est scopée par programme
--      officiel/examen, pas conçue comme un référentiel de classification
--      libre pour une sortie IA. Dette explicite, à reprendre quand le futur
--      module référentiel pédagogique/CMS (cahier, pas encore construit)
--      posera une vraie notion de chapitre pour les leçons et la banque de
--      questions.
--   3. Garde-fou réponse finale : AUCUN mécanisme structurel nouveau — même
--      discipline que le Tuteur-IA conversationnel (3/7, PROMPTS.eleve
--      règle 1) : l'interdiction de donner la solution brute avant d'être
--      passé par méthode+guidage, sauf demande EXPLICITE ET RÉPÉTÉE de
--      l'élève, est portée par le PROMPT SYSTÈME (`_shared/prompts.ts`),
--      appliquée par le modèle à partir de l'historique de conversation
--      qu'il reçoit déjà à chaque tour (même mécanisme qu'`envoyer_message_
--      ia`, aucun compteur serveur ajouté — ce serait une duplication d'un
--      contrôle qui n'existe nulle part ailleurs dans ce module).
--   4. Facturation : ACCÈS OUVERT pour cette passe, comme 3/7 actuellement —
--      aucune fondation d'abonné/quota posée ici (décision explicite,
--      chantier transversal distinct).
--   5. Hors ligne : la reconnaissance de texte elle-même fonctionne déjà hors
--      ligne (ML Kit, embarqué) ; l'analyse IA profonde exige une connexion —
--      côté client, une tentative hors ligne est mise en file par le MÊME
--      mécanisme de synchronisation différée que le reste de la plateforme
--      (ch. 34, `sync_queue`/`SyncEngine`, voir `sync_composition.dart`),
--      jamais un second mécanisme parallèle. Rien à modéliser ici côté SQL :
--      le rejeu appelle exactement la même Edge Function qu'un appel en
--      ligne normal.
--
-- Réutilise intégralement l'infrastructure IA du sous-livrable 3/7
-- (`ai_conversations`/`ai_messages`, `determiner_role_ia`, RLS, le trigger de
-- garde-fou tenant, `envoyer_message_ia`) — un nouveau type de conversation
-- ('scan_exercice') est ajouté, jamais une table de conversation parallèle.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Nouveau type de conversation IA.
-- ---------------------------------------------------------------------------
alter type public.type_conversation_ia add value if not exists 'scan_exercice';

-- ---------------------------------------------------------------------------
-- 1. Table `scan_exercices` — une ligne par photo scannée, jamais la photo
--    elle-même (voir point 1 ci-dessus) : uniquement le texte déjà reconnu
--    sur l'appareil, et l'identification matière/chapitre inférée par l'IA.
--    Écriture réservée aux fonctions SECURITY DEFINER ci-dessous, aucune
--    policy insert/update/delete cliente — même discipline que
--    `parent_ia_config`/`parent_ia_historique` (4/7).
-- ---------------------------------------------------------------------------
create table if not exists public.scan_exercices (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null unique references public.ai_conversations (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  -- Texte libre, jamais un FK vers programmes_matieres/une table chapitres —
  -- voir point 2 ci-dessus.
  matiere_libelle text,
  chapitre_libelle text,
  -- Texte reconnu sur l'appareil (ML Kit) — jamais la photo, voir point 1.
  texte_extrait text not null check (length(texte_extrait) > 0),
  -- Consentement explicite, capturé et prouvé À CHAQUE scan (donnée scolaire
  -- d'un mineur) — pas un simple bouton d'activation persistant comme
  -- Parent IA (aucun concept de verrou d'engagement ici), un consentement par
  -- exercice photographié.
  consentement boolean not null,
  created_at timestamptz not null default now(),
  constraint scan_exercices_consentement_requis check (consentement)
);

comment on table public.scan_exercices is
  'Scan et résolution d''exercice (M16 5/7, cahier §21.5) — jamais la photo elle-même (OCR embarqué côté client), écriture réservée à preparer_scan_exercice/renseigner_identification_scan_exercice (SECURITY DEFINER).';

create index if not exists idx_scan_exercices_fiche
  on public.scan_exercices (fiche_eleve_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 2. Garde-fou tenant — ★ SECURITY DEFINER dès la conception (leçon du
--    trigger `parent_ia_config_verifie_tenant`, 4/7, test 43 : un trigger
--    non-security-definer qui lit `fiches_eleves` — table étroitement
--    protégée par RLS — exécute son SELECT sous les droits de l'appelant, ce
--    qui masque un vrai rejet RLS (42501) derrière un faux 23514 quand
--    l'appelant ne peut pas voir la fiche ciblée). Vérifie que la fiche
--    appartient bien au même profil/établissement que la conversation
--    parente — une cohérence déjà garantie par construction dans
--    `preparer_scan_exercice` ci-dessous, mais revérifiée ici pour toute
--    autre voie d'écriture future sur cette table.
-- ---------------------------------------------------------------------------
create or replace function public.scan_exercices_verifie_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_conv record;
  v_fiche record;
begin
  select id, type, profile_id, etablissement_id into v_conv
  from public.ai_conversations where id = new.conversation_id;

  if v_conv is null or v_conv.type <> 'scan_exercice' then
    raise exception 'CONVERSATION_INVALIDE' using errcode = '23514';
  end if;

  select profile_id, etablissement_id into v_fiche
  from public.fiches_eleves where id = new.fiche_eleve_id;

  if v_fiche is null
     or v_fiche.profile_id is distinct from v_conv.profile_id
     or v_fiche.etablissement_id is distinct from v_conv.etablissement_id then
    raise exception 'FICHE_INCOHERENTE' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists scan_exercices_verifie_tenant_trg on public.scan_exercices;
create trigger scan_exercices_verifie_tenant_trg
  before insert or update on public.scan_exercices
  for each row execute procedure public.scan_exercices_verifie_tenant();

-- ---------------------------------------------------------------------------
-- 3. Row Level Security — lecture réservée à l'auteur de la conversation
--    (l'élève lui-même) ; aucune policy insert/update/delete cliente.
-- ---------------------------------------------------------------------------
alter table public.scan_exercices enable row level security;

drop policy if exists "scan_exercices_select_auteur" on public.scan_exercices;
create policy "scan_exercices_select_auteur" on public.scan_exercices
  for select using (
    exists (
      select 1 from public.ai_conversations c
      where c.id = conversation_id and c.profile_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 4. Démarrage d'un scan — SEUL point d'écriture initial. Vérifie le rôle IA
--    réel (élève uniquement — cette fonctionnalité est un outil élève, ni
--    enseignant ni direction), le consentement explicite, la propriété
--    réelle de la fiche (jamais une fiche d'autrui), crée la conversation
--    'scan_exercice' ET la ligne `scan_exercices` en une seule transaction.
--    Ne fait AUCUN appel Anthropic (couche SQL pure, comme `preparer_
--    analyse_risque_echec`/`preparer_declaration_usage_parent_ia`) — c'est
--    l'Edge Function `demarrer_scan_exercice` qui s'en charge ensuite.
-- ---------------------------------------------------------------------------
create or replace function public.preparer_scan_exercice(
  p_etablissement_id uuid,
  p_fiche_eleve_id uuid,
  p_texte_extrait text,
  p_consentement boolean
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_conversation_id uuid;
  v_scan_id uuid;
  v_fiche_ok boolean;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  if public.determiner_role_ia(p_etablissement_id) is distinct from 'eleve'::public.role_ia then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  if p_consentement is not true then
    raise exception 'CONSENTEMENT_REQUIS' using errcode = '22023';
  end if;

  if p_texte_extrait is null or length(trim(p_texte_extrait)) = 0 then
    raise exception 'TEXTE_VIDE' using errcode = '22023';
  end if;

  select exists (
    select 1 from public.fiches_eleves
    where id = p_fiche_eleve_id
      and etablissement_id = p_etablissement_id
      and profile_id = auth.uid()
      and deleted_at is null
  ) into v_fiche_ok;

  if not v_fiche_ok then
    raise exception 'FICHE_INTROUVABLE' using errcode = '42501';
  end if;

  insert into public.ai_conversations (etablissement_id, profile_id, type)
  values (p_etablissement_id, auth.uid(), 'scan_exercice')
  returning id into v_conversation_id;

  insert into public.scan_exercices (conversation_id, fiche_eleve_id, texte_extrait, consentement)
  values (v_conversation_id, p_fiche_eleve_id, trim(p_texte_extrait), p_consentement)
  returning id into v_scan_id;

  return jsonb_build_object('conversation_id', v_conversation_id, 'scan_id', v_scan_id);
end;
$$;

revoke execute on function public.preparer_scan_exercice(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.preparer_scan_exercice(uuid, uuid, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Renseigne l'identification matière/chapitre après le premier appel
--    Anthropic — appelée par l'Edge Function `demarrer_scan_exercice` pour
--    le compte de l'utilisateur authentifié (jamais par le client
--    directement, mais re-vérifie quand même la propriété : même discipline
--    que `obtenir_detail_risque_echec_interne`, jamais une confiance dans le
--    fait que `preparer_scan_exercice` l'ait déjà vérifié un instant plus
--    tôt).
-- ---------------------------------------------------------------------------
create or replace function public.renseigner_identification_scan_exercice(
  p_scan_id uuid,
  p_matiere_libelle text,
  p_chapitre_libelle text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_proprietaire uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  select c.profile_id into v_proprietaire
  from public.scan_exercices s
  join public.ai_conversations c on c.id = s.conversation_id
  where s.id = p_scan_id;

  if v_proprietaire is distinct from auth.uid() then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  update public.scan_exercices
  set matiere_libelle = nullif(trim(coalesce(p_matiere_libelle, '')), ''),
      chapitre_libelle = nullif(trim(coalesce(p_chapitre_libelle, '')), '')
  where id = p_scan_id;
end;
$$;

revoke execute on function public.renseigner_identification_scan_exercice(uuid, text, text) from public, anon;
grant execute on function public.renseigner_identification_scan_exercice(uuid, text, text) to authenticated;

-- ============================================================================
-- Fin M16 5/7 — Scan et résolution d'exercice.
-- ============================================================================
