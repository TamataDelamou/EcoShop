-- ============================================================================
-- EcoShop — Chantier Facturation/Quota IA — Étape (d) : quota Tuteur IA
-- (compteur d'interactions + anti-rafale + détection d'anomalie a
-- posteriori, §21.4/36.2). Dernière étape du chantier.
--
-- Découverte structurante, actée avant conception : `envoyer_message_ia`
-- (Edge Function, M16 3/7) N'ÉCRIT JAMAIS dans `ai_messages` -- c'est le
-- CLIENT qui insère lui-même le message utilisateur et la réponse
-- assistant après coup (division des responsabilités reprise de la
-- source). Une garde placée UNIQUEMENT côté Edge Function serait donc
-- contournable par un INSERT direct via PostgREST. La seule autorité
-- réelle et non contournable est un trigger `BEFORE INSERT` sur
-- `ai_messages` (s'applique quelle que soit la voie d'écriture) -- même
-- réflexe que la découverte sur l'autorité exclusive du webhook à l'étape
-- (b). L'appel côté Edge Function (ajouté à `envoyer_message_ia`) n'est
-- qu'un PRÉ-CONTRÔLE de confort : évite un appel Anthropic facturé pour
-- rien et une réponse affichée puis non enregistrable -- jamais l'autorité.
--
-- Les deux points d'appel (trigger + pré-contrôle Edge Function) invoquent
-- la MÊME fonction `verifier_quota_ia()` -- aucune logique dupliquée, donc
-- aucun risque de divergence entre les deux.
--
-- Frontière du quota : comparaison `compte >= limite` (bloque exactement le
-- message qui atteindrait la limite), jamais `compte >`. Le trigger étant
-- `BEFORE INSERT`, le compte lu est celui des messages DÉJÀ existants avant
-- le message en cours d'insertion -- sur un quota de 20 : le 19e message
-- voit un compte existant de 18 (autorisé), le 20e voit 19 (autorisé), le
-- 21e voit 20 (`20 >= 20` -> refusé). Testé explicitement en ce sens
-- (tests/rls/52).
--
-- Portée du plafond périodique -- UNIQUEMENT le Tuteur IA au sens strict du
-- cahier (élève, conversation `libre`, §21.4/36.2) :
--   • `type = 'risque_echec'` (Directeur-Adviser) : déjà gated par
--     `frais_ia_admin` (entitlement_actif, étape a), interactions
--     structurées (bouton, pas de texte libre) -- pas de plafond ici.
--   • `type = 'scan_exercice'` : décision déjà actée en M16 5/7 ("ACCÈS
--     OUVERT... aucune fondation de quota posée ici") -- non reconsidérée.
--   • Chat `libre` d'un enseignant/direction (futur "IA professeur",
--     §21.6, abonnement individuel séparé, pas encore construit) : pas de
--     plafond ici non plus, chantier distinct à venir.
-- Ces trois cas restent néanmoins soumis à l'anti-rafale ci-dessous, qui
-- est UNIVERSELLE (protection infra/coût, pas un levier de monétisation).
--
-- Abonnement Premium élève actif (`entitlement_premium_eleve_actif`,
-- étape c) : quota LEVÉ ENTIÈREMENT, jamais un second plafond plus haut --
-- le cahier dit explicitement "lève ce quota" (§21.4), pas "l'augmente".
--
-- "Compteur d'interactions pondéré" : le cahier ne précise aucune base de
-- pondération. Poids fixe = 1 pour tous les types aujourd'hui (décision
-- actée par le porteur de projet) -- le mécanisme (`poids_type_
-- conversation_ia` dans `parametres_globaux`) est prêt à différencier plus
-- tard sans toucher au code, mais rien ne différencie encore.
--
-- Anti-rafale : réutilise LITTÉRALEMENT le patron du chapitre 5
-- (`lier_compte_a_fiche`, M2, `tests/rls/04`) -- fenêtre glissante, compte
-- >= seuil -> exception, même SQLSTATE 54000 (`TROP_DE_TENTATIVES` ->
-- `TROP_DE_MESSAGES_IA`). Portée : par profil, toutes conversations
-- confondues (empêche de contourner la fenêtre en répartissant les
-- messages entre plusieurs types de conversation).
--
-- Détection d'anomalie a posteriori (`detecter_anomalies_usage_ia`), même
-- forme que `detecter_anomalies_comptables` (M14) : calcul à la demande,
-- lecture seule, n'écrit nulle part, JAMAIS de blocage -- purement
-- consultatif pour GSG/direction. Aucune notion de session/appareil : ne
-- détecte QUE le volume total de messages, jamais un partage de compte
-- (exigence explicite du porteur de projet). Amélioration délibérée par
-- rapport au précédent : garde interne `est_personnel(etablissement) or
-- est_admin_gsg()`, que `detecter_anomalies_comptables` n'a pas -- dette
-- notée pour aligner ce dernier plus tard, non traitée ici (hors périmètre
-- de cette étape).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Configuration (§30.4 -- rien codé en dur). Valeurs PLACEHOLDER, comme
--    à chaque étape de ce chantier, à remplacer par le porteur de projet
--    avant activation réelle.
-- ---------------------------------------------------------------------------
insert into public.parametres_globaux (cle, valeur, description) values
  (
    'quota_tuteur_ia_free_mensuel',
    '{"valeur": 20}'::jsonb,
    'PLACEHOLDER — quota fictif (20 interactions/mois). Plafond mensuel calendaire du Tuteur IA pour un élève FREE (non Premium), §21.4/36.2. Levé entièrement pour un élève avec abonnement Premium actif. À remplacer par le porteur de projet avant toute activation réelle.'
  )
on conflict (cle) do nothing;

insert into public.parametres_globaux (cle, valeur, description) values
  (
    'anti_rafale_ia',
    '{"max_messages": 10, "fenetre_minutes": 5}'::jsonb,
    'PLACEHOLDER — seuils fictifs. Anti-rafale universel (tous rôles/types de conversation IA confondus), même patron que le chapitre 5 (lier_compte_a_fiche) : fenêtre glissante, compte >= max_messages sur les fenetre_minutes dernières minutes -> refus temporaire. Protection infra/coût, pas un levier de monétisation. À affiner par le porteur de projet avant activation réelle.'
  )
on conflict (cle) do nothing;

insert into public.parametres_globaux (cle, valeur, description) values
  (
    'poids_type_conversation_ia',
    '{"libre": 1, "risque_echec": 1, "scan_exercice": 1}'::jsonb,
    'Poids par type de conversation IA pour le compteur d''interactions du quota Tuteur IA. Tous à 1 aujourd''hui (aucune base de pondération spécifiée par le cahier) -- mécanisme prêt à différencier plus tard sans changement de code, décision explicite du porteur de projet de ne pas trancher davantage pour l''instant.'
  )
on conflict (cle) do nothing;

insert into public.parametres_globaux (cle, valeur, description) values
  (
    'seuil_anomalie_usage_ia_quotidien',
    '{"valeur": 50}'::jsonb,
    'PLACEHOLDER — seuil fictif. Volume de messages IA (sender=user) en 24h au-delà duquel detecter_anomalies_usage_ia signale un profil pour revue humaine -- jamais un blocage automatique. À affiner par le porteur de projet avant activation réelle.'
  )
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Contrat unifié -- anti-rafale universel + plafond périodique Tuteur IA
--    (élève, conversation libre, FREE uniquement). SECURITY INVOKER
--    (délibéré, même discipline que les triggers _verifie_tenant
--    existants) : repose sur auth.uid(), jamais un profil arbitraire --
--    aucune élévation de privilège nécessaire, donc aucune ne doit exister.
-- ---------------------------------------------------------------------------
create or replace function public.verifier_quota_ia(
  p_etablissement_id uuid,
  p_type public.type_conversation_ia
)
returns void
language plpgsql
stable
set search_path = public
as $$
declare
  v_config jsonb;
  v_max_rafale int;
  v_fenetre_minutes int;
  v_count_rafale int;
  v_role public.role_ia;
  v_fiche uuid;
  v_poids jsonb;
  v_poids_type numeric;
  v_quota_free int;
  v_debut_mois timestamptz;
  v_compte_mois numeric;
begin
  -- Anti-rafale -- universel, tous rôles/types confondus.
  select valeur into v_config from public.parametres_globaux where cle = 'anti_rafale_ia';
  v_max_rafale := coalesce((v_config->>'max_messages')::int, 2147483647);
  v_fenetre_minutes := coalesce((v_config->>'fenetre_minutes')::int, 0);

  select count(*) into v_count_rafale
  from public.ai_messages m
  join public.ai_conversations c on c.id = m.conversation_id
  where c.profile_id = auth.uid()
    and m.sender = 'user'
    and m.created_at > now() - make_interval(mins => v_fenetre_minutes);

  if v_count_rafale >= v_max_rafale then
    raise exception 'TROP_DE_MESSAGES_IA' using errcode = '54000';
  end if;

  -- Plafond périodique -- UNIQUEMENT Tuteur IA (élève, conversation libre).
  if p_type = 'libre' then
    v_role := public.determiner_role_ia(p_etablissement_id);

    if v_role = 'eleve' then
      select id into v_fiche from public.fiches_eleves
      where profile_id = auth.uid() and etablissement_id = p_etablissement_id and deleted_at is null;

      -- Abonnement Premium actif -> quota LEVÉ entièrement (§21.4 : "lève
      -- ce quota", pas "l'augmente"), jamais un second plafond distinct.
      if v_fiche is not null and not coalesce(public.entitlement_premium_eleve_actif(v_fiche), false) then
        select (valeur->>'valeur')::int into v_quota_free
        from public.parametres_globaux where cle = 'quota_tuteur_ia_free_mensuel';

        select valeur into v_poids from public.parametres_globaux where cle = 'poids_type_conversation_ia';
        v_poids_type := coalesce((v_poids->>'libre')::numeric, 1);

        v_debut_mois := date_trunc('month', now());

        select coalesce(count(*), 0) * v_poids_type into v_compte_mois
        from public.ai_messages m
        join public.ai_conversations c on c.id = m.conversation_id
        where c.profile_id = auth.uid() and c.type = 'libre'
          and m.sender = 'user' and m.created_at >= v_debut_mois;

        if v_compte_mois >= coalesce(v_quota_free, 2147483647) then
          raise exception 'QUOTA_TUTEUR_IA_ATTEINT' using errcode = '22023';
        end if;
      end if;
    end if;
  end if;
end;
$$;

grant execute on function public.verifier_quota_ia(uuid, public.type_conversation_ia) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Trigger -- SEULE autorité réelle (voir en-tête). Ne s'applique qu'aux
--    messages `sender = 'user'` (une réponse assistant ne consomme jamais
--    de quota). SECURITY INVOKER : la lecture de ai_conversations est
--    naturellement soumise à la RLS de l'appelant -- si new.conversation_id
--    n'appartient pas à l'appelant, cette lecture ne renvoie rien (FOUND =
--    false) et la ligne est laissée passer ICI : la policy RLS
--    "ai_messages_insert_auteur" (vérification de propriété de la
--    conversation), qui s'applique juste après, refusera l'INSERT pour la
--    bonne raison -- pas la peine de dupliquer cette vérification ici.
-- ---------------------------------------------------------------------------
create or replace function public.ai_messages_verifie_quota()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_etablissement_id uuid;
  v_type public.type_conversation_ia;
begin
  if new.sender <> 'user' then
    return new;
  end if;

  select c.etablissement_id, c.type into v_etablissement_id, v_type
  from public.ai_conversations c
  where c.id = new.conversation_id;

  if not found then
    return new;
  end if;

  perform public.verifier_quota_ia(v_etablissement_id, v_type);

  return new;
end;
$$;

drop trigger if exists ai_messages_verifie_quota_trg on public.ai_messages;
create trigger ai_messages_verifie_quota_trg
  before insert on public.ai_messages
  for each row execute procedure public.ai_messages_verifie_quota();

-- ---------------------------------------------------------------------------
-- 4. Détection d'anomalie a posteriori -- même forme que
--    detecter_anomalies_comptables (M14) : lecture seule, à la demande,
--    n'écrit nulle part, jamais de blocage. Garde interne ajoutée
--    (amélioration délibérée par rapport au précédent, voir en-tête).
--    Aucune notion de session/appareil : ne signale qu'un volume, jamais un
--    partage de compte.
-- ---------------------------------------------------------------------------
create or replace function public.detecter_anomalies_usage_ia(p_etablissement_id uuid)
returns table (
  profile_id uuid,
  role_ia public.role_ia,
  nb_messages_24h bigint,
  anomalie text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (coalesce(public.est_personnel(p_etablissement_id), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  return query
  select c.profile_id,
         public.determiner_role_ia(p_etablissement_id, c.profile_id),
         count(*)::bigint,
         'volume_quotidien'::text
  from public.ai_messages m
  join public.ai_conversations c on c.id = m.conversation_id
  where c.etablissement_id = p_etablissement_id
    and m.sender = 'user'
    and m.created_at > now() - interval '24 hours'
  group by c.profile_id
  having count(*) >= coalesce((
    select (valeur->>'valeur')::int from public.parametres_globaux
    where cle = 'seuil_anomalie_usage_ia_quotidien'
  ), 2147483647);
end;
$$;

revoke all on function public.detecter_anomalies_usage_ia(uuid) from public, anon;
grant execute on function public.detecter_anomalies_usage_ia(uuid) to authenticated;

-- ============================================================================
-- Fin — Chantier Facturation/Quota IA, étape (d). Chantier clos.
-- ============================================================================
