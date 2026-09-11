// ============================================================================
// EcoShop — Edge Function « envoyer_message_ia » (M16, sous-livrable 3/7)
//
// Point d'entrée SÉCURISÉ et UNIQUE vers l'API IA externe (Claude) pour le
// chat libre — Tuteur-IA (élève), Prof-Assistant (enseignant),
// Directeur-Adviser (direction). Le client Flutter n'appelle JAMAIS
// Anthropic directement.
//
//   1. Vérifie l'authentification (JWT déjà vérifié par la plateforme,
//      verify_jwt = true, voir config.toml).
//   2. Détermine le VRAI rôle IA de l'utilisateur (`determiner_role_ia`,
//      SQL, jamais celui envoyé par le client — impossible à falsifier).
//   3. Sélectionne le prompt système correspondant (`_shared/prompts.ts`).
//   4. Si la conversation est groundée (`type = 'risque_echec'`,
//      `grounding = true`) ET que le rôle est `direction` : expose l'outil
//      de détail nominatif (couche 3) — re-vérifié à CHAQUE tour via la
//      conversation relue en base, jamais un flag envoyé par le client.
//   5. Appelle l'API Claude (boucle tool_use plafonnée à un seul
//      aller-retour supplémentaire — jamais de 3e appel, jamais de
//      fan-out multi-outils).
//   6. Retourne UNIQUEMENT le texte de réponse (+ le mapping pseudonyme→
//      identité, séparé, jamais transmis à Anthropic) — n'écrit JAMAIS
//      les messages dans `ai_messages` : c'est le CLIENT qui le fait
//      (même division des responsabilités que la source, voir
//      CHAT_IA_GROUNDING.md §4).
//
// La clé API (ANTHROPIC_API_KEY) est un secret Supabase, jamais exposée au
// client. Aucune clé réelle n'est nécessaire pour ce sous-livrable — voir
// `_shared/anthropic_client.ts` (ANTHROPIC_URL_OVERRIDE, dev/test local
// uniquement).
// ============================================================================

import {
  appellerAnthropicApi,
  extraireBlocsToolUse,
  extraireTexte,
} from "../_shared/anthropic_client.ts";
import { construirePayloadPseudonymise, type EleveARisqueBrut } from "../_shared/grounding_risque_echec.ts";
import {
  NOM_OUTIL_DETAIL_NOMINATIF_RISQUE_ECHEC,
  PROMPTS,
  SCHEMA_OUTIL_DETAIL_NOMINATIF_RISQUE_ECHEC,
} from "../_shared/prompts.ts";
import { clientUtilisateur, entetesCors, reponseJson, requisEnv } from "../_shared/supabase_client.ts";

interface CorpsRequete {
  conversationId?: string;
  etablissementId?: string;
  message?: string;
}

Deno.serve(async (req) => {
  const origine = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: entetesCors(origine) });
  }
  if (req.method !== "POST") {
    return reponseJson(405, { error: "methode_non_autorisee" }, origine);
  }

  try {
    const corps = (await req.json()) as CorpsRequete;
    const message = typeof corps.message === "string" ? corps.message.trim() : "";
    if (!message) {
      return reponseJson(400, { error: "message_requis" }, origine);
    }

    const { client: supabase, jeton } = clientUtilisateur(req);
    const { data: userData, error: userError } = await supabase.auth.getUser(jeton);
    if (userError || !userData?.user) {
      return reponseJson(401, { error: "authentification_requise" }, origine);
    }

    // --- Résolution de la conversation (existante ou nouvelle) ---
    let conversationId = corps.conversationId ?? null;
    let etablissementId = corps.etablissementId ?? null;
    let grounding = false;
    let typeConversation: "libre" | "risque_echec" = "libre";

    if (conversationId) {
      const { data: conv, error: convError } = await supabase
        .from("ai_conversations")
        .select("id, etablissement_id, type, grounding")
        .eq("id", conversationId)
        .single();

      if (convError || !conv) {
        return reponseJson(404, { error: "conversation_introuvable" }, origine);
      }
      etablissementId = conv.etablissement_id;
      grounding = conv.grounding;
      typeConversation = conv.type;
    } else {
      if (!etablissementId) {
        return reponseJson(400, { error: "etablissement_id_requis" }, origine);
      }
      const { data: nouvelle, error: creationError } = await supabase
        .from("ai_conversations")
        .insert({ etablissement_id: etablissementId, profile_id: userData.user.id })
        .select("id")
        .single();

      if (creationError || !nouvelle) {
        console.error(JSON.stringify({
          fn: "envoyer_message_ia",
          niveau: "error",
          message: "echec creation conversation",
          detail: creationError?.message,
        }));
        return reponseJson(500, { error: "erreur_interne" }, origine);
      }
      conversationId = nouvelle.id;
    }

    // --- Rôle IA réel — jamais celui du client ---
    const { data: role, error: roleError } = await supabase.rpc("determiner_role_ia", {
      p_etablissement_id: etablissementId,
    });
    if (roleError || !role) {
      return reponseJson(403, { error: "aucun_assistant_pour_ce_role" }, origine);
    }

    const systemPrompt = PROMPTS[role];
    if (!systemPrompt) {
      return reponseJson(403, { error: "aucun_assistant_pour_ce_role" }, origine);
    }

    // --- Historique court (10 derniers messages) ---
    const { data: historiqueBrut } = await supabase
      .from("ai_messages")
      .select("sender, content")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: false })
      .limit(10);

    const historique = (historiqueBrut ?? [])
      .reverse()
      .map((m) => ({ role: m.sender === "assistant" ? "assistant" : "user", content: m.content }));

    // --- Gating de l'outil de détail nominatif (couche 3) — DEUX
    //     conditions, jamais une confiance dans un champ client :
    //     rôle direction STRICT + grounding relu depuis la base ci-dessus. ---
    const outilActif = role === "direction" && grounding && typeConversation === "risque_echec";
    const tools = outilActif ? [SCHEMA_OUTIL_DETAIL_NOMINATIF_RISQUE_ECHEC] : undefined;

    const apiKey = requisEnv("ANTHROPIC_API_KEY");

    let data;
    try {
      data = await appellerAnthropicApi({
        apiKey,
        systemPrompt,
        tools,
        messages: [...historique, { role: "user", content: message }],
      });
    } catch (erreurAppel) {
      console.error(JSON.stringify({
        fn: "envoyer_message_ia",
        niveau: "error",
        message: "echec appel anthropic (premier tour)",
        detail: erreurAppel instanceof Error ? erreurAppel.message : String(erreurAppel),
      }));
      return reponseJson(502, { error: "erreur_assistant_ia" }, origine);
    }

    const blocsToolUse = extraireBlocsToolUse(data.content);
    let reply: string;
    let mappingPseudonymes: Record<string, unknown> | undefined;

    if (blocsToolUse.length === 0) {
      reply = extraireTexte(data.content);
    } else {
      // Un seul outil possible dans ce flux — jamais de fan-out multi-outils.
      const bloc = blocsToolUse[0];
      if (bloc.name !== NOM_OUTIL_DETAIL_NOMINATIF_RISQUE_ECHEC) {
        return reponseJson(500, { error: "outil_inconnu" }, origine);
      }

      const { data: brut, error: detailError } = await supabase.rpc(
        "obtenir_detail_risque_echec_interne",
        { p_conversation_id: conversationId },
      );
      if (detailError) {
        return reponseJson(403, { error: "detail_refuse" }, origine);
      }

      const { payloadAnthropic, mappingComplet } = construirePayloadPseudonymise(
        (brut ?? []) as EleveARisqueBrut[],
      );
      mappingPseudonymes = mappingComplet; // ★ JAMAIS envoyé à Anthropic ci-dessous.

      let data2;
      try {
        data2 = await appellerAnthropicApi({
          apiKey,
          systemPrompt,
          tools,
          messages: [
            ...historique,
            { role: "user", content: message },
            { role: "assistant", content: data.content },
            {
              role: "user",
              content: [
                { type: "tool_result", tool_use_id: bloc.id, content: JSON.stringify(payloadAnthropic) },
              ],
            },
          ],
        });
      } catch (erreurAppel) {
        console.error(JSON.stringify({
          fn: "envoyer_message_ia",
          niveau: "error",
          message: "echec appel anthropic (second tour, apres tool_result)",
          detail: erreurAppel instanceof Error ? erreurAppel.message : String(erreurAppel),
        }));
        return reponseJson(502, { error: "erreur_assistant_ia" }, origine);
      }
      // Plafond anti-boucle : un éventuel nouveau tool_use dans data2 est
      // ignoré — un seul aller-retour d'outil par tour.
      reply = extraireTexte(data2.content);
    }

    return reponseJson(200, {
      conversationId,
      reply,
      ...(mappingPseudonymes ? { mappingPseudonymes } : {}),
    }, origine);
  } catch (erreur) {
    console.error(JSON.stringify({
      fn: "envoyer_message_ia",
      niveau: "error",
      message: "erreur inattendue",
      detail: erreur instanceof Error ? erreur.message : String(erreur),
    }));
    return reponseJson(500, { error: "erreur_interne" }, req.headers.get("origin"));
  }
});
