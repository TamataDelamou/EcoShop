// ============================================================================
// EcoShop — Edge Function « demarrer_scan_exercice » (M16, sous-livrable 5/7
// — Scan et résolution d'exercice, cahier §21.5)
//
// Fonctionnalité ENTIÈREMENT NOUVELLE (absorbée du module M14 d'EduRéussite),
// sans équivalent côté source EcoShop — voir ANALYSE_GLOBALE.md.
//
//   1. Reçoit UNIQUEMENT le texte déjà reconnu sur l'appareil de l'élève
//      (ML Kit, embarqué) — jamais une photo/image : voir la migration
//      `20260906001509`, point 1 (minimisation des données d'un mineur,
//      strictement supérieure à ce qu'imposait le cahier littéral).
//   2. Appelle `preparer_scan_exercice` (SQL, SECURITY DEFINER) — seule
//      autorité qui vérifie le rôle élève réel, le consentement explicite,
//      la propriété de la fiche, et qui crée la conversation + la ligne
//      `scan_exercices`.
//   3. Appelle Claude UNE fois avec `PROMPT_SCAN_EXERCICE_IDENTIFICATION`
//      (JSON strict : matière/chapitre inférés + première réponse de
//      guidage — jamais la solution brute dès ce tour, voir le prompt).
//   4. Persiste l'identification via `renseigner_identification_scan_
//      exercice` (best-effort : un échec ici n'invalide jamais la réponse de
//      guidage déjà générée et utile à l'élève — juste loggé).
//   5. Retourne { conversationId, matiere, chapitre, reply } — n'écrit
//      JAMAIS dans `ai_messages` : c'est le CLIENT qui écrit le message
//      "user" (texte extrait) puis la réponse assistant, même division des
//      responsabilités que `envoyer_message_ia`/`demarrer_analyse_risque_
//      echec`. Les tours suivants de guidage passent par `envoyer_message_
//      ia` (persona "Scan-Exercice", voir son patch dans ce sous-livrable).
// ============================================================================

import { appellerAnthropicApi, extraireTexte } from "../_shared/anthropic_client.ts";
import { PROMPT_SCAN_EXERCICE_IDENTIFICATION } from "../_shared/prompts.ts";
import { clientUtilisateur, entetesCors, reponseJson, requisEnv } from "../_shared/supabase_client.ts";

interface CorpsRequete {
  etablissementId?: string;
  ficheEleveId?: string;
  texteExtrait?: string;
  consentement?: boolean;
}

interface IdentificationExercice {
  matiere: string | null;
  chapitre: string | null;
  reponse: string;
}

/** Mappe un SQLSTATE Postgres vers un statut HTTP raisonnable. */
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
    const ficheEleveId = typeof corps.ficheEleveId === "string" ? corps.ficheEleveId : "";
    const texteExtrait = typeof corps.texteExtrait === "string" ? corps.texteExtrait.trim() : "";
    const consentement = corps.consentement === true;

    if (!etablissementId || !ficheEleveId || !texteExtrait) {
      return reponseJson(400, { error: "parametres_requis" }, origine);
    }

    const { client: supabase, jeton } = clientUtilisateur(req);
    const { data: userData, error: userError } = await supabase.auth.getUser(jeton);
    if (userError || !userData?.user) {
      return reponseJson(401, { error: "authentification_requise" }, origine);
    }

    const { data: preparation, error: preparationError } = await supabase.rpc("preparer_scan_exercice", {
      p_etablissement_id: etablissementId,
      p_fiche_eleve_id: ficheEleveId,
      p_texte_extrait: texteExtrait,
      p_consentement: consentement,
    });

    if (preparationError || !preparation) {
      return reponseJson(
        statutPour((preparationError as { code?: string } | null)?.code),
        { error: "scan_refuse", detail: preparationError?.message },
        origine,
      );
    }

    const { conversation_id: conversationId, scan_id: scanId } = preparation as {
      conversation_id: string;
      scan_id: string;
    };

    const apiKey = requisEnv("ANTHROPIC_API_KEY");

    let data;
    try {
      data = await appellerAnthropicApi({
        apiKey,
        systemPrompt: PROMPT_SCAN_EXERCICE_IDENTIFICATION,
        messages: [{ role: "user", content: texteExtrait }],
      });
    } catch (erreurAppel) {
      console.error(JSON.stringify({
        fn: "demarrer_scan_exercice",
        niveau: "error",
        message: "echec appel anthropic",
        detail: erreurAppel instanceof Error ? erreurAppel.message : String(erreurAppel),
      }));
      return reponseJson(502, { error: "erreur_assistant_ia" }, origine);
    }

    let identification: IdentificationExercice;
    try {
      identification = JSON.parse(extraireTexte(data.content));
    } catch {
      // Repli robuste : le texte brut reste utile à l'élève même si le
      // format JSON attendu n'a pas été respecté par le modèle.
      identification = { matiere: null, chapitre: null, reponse: extraireTexte(data.content) };
    }

    const { error: identificationError } = await supabase.rpc("renseigner_identification_scan_exercice", {
      p_scan_id: scanId,
      p_matiere_libelle: identification.matiere,
      p_chapitre_libelle: identification.chapitre,
    });
    if (identificationError) {
      // Non bloquant — voir en-tête de fichier : la réponse de guidage reste
      // valable même si l'étiquette matière/chapitre n'a pas pu être écrite.
      console.error(JSON.stringify({
        fn: "demarrer_scan_exercice",
        niveau: "error",
        message: "echec enregistrement identification",
        detail: identificationError.message,
      }));
    }

    return reponseJson(200, {
      conversationId,
      matiere: identification.matiere,
      chapitre: identification.chapitre,
      reply: identification.reponse,
    }, origine);
  } catch (erreur) {
    console.error(JSON.stringify({
      fn: "demarrer_scan_exercice",
      niveau: "error",
      message: "erreur inattendue",
      detail: erreur instanceof Error ? erreur.message : String(erreur),
    }));
    return reponseJson(500, { error: "erreur_interne" }, req.headers.get("origin"));
  }
});
