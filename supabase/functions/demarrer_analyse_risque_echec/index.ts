// ============================================================================
// EcoShop — Edge Function « demarrer_analyse_risque_echec » (M16,
// sous-livrable 3/7)
//
// Couche 1→2 du grounding Directeur-Adviser (voir CHAT_IA_GROUNDING.md
// côté source) : déclenchée par un bouton structuré ("Analyser le risque
// d'échec — établissement ou classe précise"), JAMAIS par du texte libre.
//
//   1. Appelle `preparer_analyse_risque_echec` (SQL, SECURITY DEFINER) —
//      seule autorité qui vérifie le rôle direction, résout la cible
//      RÉELLEMENT, rafraîchit la source unique du score de risque
//      (sous-livrable 1/7) et crée la conversation groundée (les champs
//      `grounding`/`cible_type`/`cible_id` ne sont JAMAIS posés par un
//      appel client direct — voir la policy RLS `ai_conversations_insert_
//      libre`, migration 20260906001506).
//   2. Construit un message synthétique — CHIFFRES RÉELS UNIQUEMENT,
//      jamais un texte libre côté client — et appelle Claude UNE fois,
//      SANS outil (couche 2 stricte, le détail nominatif n'est exposé que
//      sur demande explicite d'un tour ultérieur, voir
//      `envoyer_message_ia`).
//   3. Retourne le texte + le libellé de cible — n'écrit JAMAIS les
//      messages dans `ai_messages` : c'est le CLIENT qui écrit le message
//      "user" synthétique COURT (ex. "Analyse du risque d'échec — la
//      classe 6e A") puis la réponse assistant, même division des
//      responsabilités que `envoyer_message_ia`/la source.
// ============================================================================

import { appellerAnthropicApi, extraireTexte } from "../_shared/anthropic_client.ts";
import { PROMPTS } from "../_shared/prompts.ts";
import { clientUtilisateur, entetesCors, reponseJson, requisEnv } from "../_shared/supabase_client.ts";

interface CorpsRequete {
  etablissementId?: string;
  cibleType?: string;
  cibleId?: string;
}

/** Mappe un SQLSTATE Postgres vers un statut HTTP raisonnable — jamais 500
 * par défaut pour une erreur de validation/autorisation attendue. */
function statutPour(sqlstate: string | undefined): number {
  switch (sqlstate) {
    case "42501":
      return 403;
    case "22023":
    case "23514":
      return 400;
    default:
      return 500;
  }
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
    const etablissementId = typeof corps.etablissementId === "string" ? corps.etablissementId : "";
    const cibleType = typeof corps.cibleType === "string" ? corps.cibleType : "";
    const cibleId = typeof corps.cibleId === "string" ? corps.cibleId : null;

    if (!etablissementId || !cibleType) {
      return reponseJson(400, { error: "parametres_requis" }, origine);
    }

    const { client: supabase, jeton } = clientUtilisateur(req);
    const { data: userData, error: userError } = await supabase.auth.getUser(jeton);
    if (userError || !userData?.user) {
      return reponseJson(401, { error: "authentification_requise" }, origine);
    }

    const { data: resultat, error: preparationError } = await supabase.rpc(
      "preparer_analyse_risque_echec",
      { p_etablissement_id: etablissementId, p_cible_type: cibleType, p_cible_id: cibleId },
    );

    if (preparationError || !resultat) {
      return reponseJson(
        statutPour((preparationError as { code?: string } | null)?.code),
        { error: "analyse_refusee", detail: preparationError?.message },
        origine,
      );
    }

    const { conversation_id: conversationId, effectif, eleves_a_risque: elevesARisque, cible_label: cibleLabel } =
      resultat as {
        conversation_id: string;
        effectif: number;
        eleves_a_risque: number;
        cible_label: string;
      };

    const messageSynthetique =
      `Analyse du risque d'échec pour ${cibleLabel}. ` +
      `Effectif : ${effectif}. ` +
      `Élèves à risque d'échec (score de risque ≥ 0,6) : ${elevesARisque}.`;

    const apiKey = requisEnv("ANTHROPIC_API_KEY");

    let data;
    try {
      data = await appellerAnthropicApi({
        apiKey,
        systemPrompt: PROMPTS.direction,
        messages: [{ role: "user", content: messageSynthetique }],
      });
    } catch (erreurAppel) {
      console.error(JSON.stringify({
        fn: "demarrer_analyse_risque_echec",
        niveau: "error",
        message: "echec appel anthropic",
        detail: erreurAppel instanceof Error ? erreurAppel.message : String(erreurAppel),
      }));
      return reponseJson(502, { error: "erreur_assistant_ia" }, origine);
    }

    const reply = extraireTexte(data.content);

    return reponseJson(200, {
      conversationId,
      reply,
      cibleLabel,
      effectif,
      elevesARisque,
    }, origine);
  } catch (erreur) {
    console.error(JSON.stringify({
      fn: "demarrer_analyse_risque_echec",
      niveau: "error",
      message: "erreur inattendue",
      detail: erreur instanceof Error ? erreur.message : String(erreur),
    }));
    return reponseJson(500, { error: "erreur_interne" }, req.headers.get("origin"));
  }
});
