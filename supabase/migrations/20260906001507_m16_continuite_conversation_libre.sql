-- ============================================================================
-- EcoShop — M16, complément sous-livrable 3/7 : continuité de conversation
-- ============================================================================
-- Écart trouvé après coup (voir ANALYSE_GLOBALE.md) : contrairement à la
-- source (`ai_chat_screen.dart`/`ai_service.dart`, ecoshop_flutter), qui
-- rouvre TOUJOURS la même conversation par rôle (`conversationId = 'default'`,
-- Firestore) — donc l'historique complet réapparaît à chaque ouverture —
-- l'implémentation initiale de `envoyer_message_ia` créait une nouvelle
-- ligne `ai_conversations` orpheline à chaque appel sans `conversationId`,
-- et l'écran Flutter ne rechargeait jamais d'historique. Corrigé ici :
-- une conversation LIBRE stable par (élève, établissement), jamais recréée.
--
-- Ne s'applique qu'au type 'libre' : les conversations 'risque_echec'
-- (déclenchement structuré direction) restent chacune une nouvelle ligne à
-- chaque analyse — comportement déjà voulu et documenté côté source elle-
-- même (« la conversation libre 'default' reste intacte, simplement plus
-- affichée » — pas de continuité réclamée pour celles-ci non plus).
-- ============================================================================

create unique index if not exists ai_conversations_libre_par_profil_etab
  on public.ai_conversations (profile_id, etablissement_id)
  where type = 'libre';

-- ---------------------------------------------------------------------------
-- Renvoie la conversation libre existante de l'appelant pour cet
-- établissement, ou en crée une si aucune n'existe encore. N'appelle jamais
-- Anthropic (contrairement à `envoyer_message_ia`) : c'est un pur
-- "get-or-create", appelé par le client à l'OUVERTURE de l'écran, avant tout
-- envoi de message, pour pouvoir recharger l'historique immédiatement.
-- ---------------------------------------------------------------------------
create or replace function public.obtenir_conversation_libre(p_etablissement_id uuid)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  select id into v_id
  from public.ai_conversations
  where profile_id = auth.uid()
    and etablissement_id = p_etablissement_id
    and type = 'libre'
  limit 1;

  if v_id is not null then
    return v_id;
  end if;

  insert into public.ai_conversations (etablissement_id, profile_id, type)
  values (p_etablissement_id, auth.uid(), 'libre')
  returning id into v_id;

  return v_id;
exception
  -- Course entre deux appels concurrents (ex. double-tap) : l'un des deux
  -- perd l'insertion sur l'index unique ci-dessus, relit simplement ce que
  -- l'autre a créé plutôt que d'échouer.
  when unique_violation then
    select id into v_id
    from public.ai_conversations
    where profile_id = auth.uid()
      and etablissement_id = p_etablissement_id
      and type = 'libre'
    limit 1;
    return v_id;
end;
$$;

revoke execute on function public.obtenir_conversation_libre(uuid) from public, anon;
grant execute on function public.obtenir_conversation_libre(uuid) to authenticated;

-- ============================================================================
-- Fin complément M16 3/7 — continuité de conversation.
-- ============================================================================
