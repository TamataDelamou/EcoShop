// ============================================================================
// EcoShop — Edge Function « analyser_usage_parent_ia » (M16, sous-livrable
// 4/7 — Parent IA, déclaration manuelle)
//
// Porté depuis ecoshop_flutter/functions/index.js →
// `analyserUsageParentIa`. Point d'entrée SÉCURISÉ et UNIQUE vers l'API
// Anthropic pour cette analyse — le client Flutter n'appelle JAMAIS Claude
// directement.
//
//   1. Appelle `preparer_declaration_usage_parent_ia` (SQL, SECURITY
//      DEFINER) — seule autorité qui vérifie la propriété de la fiche
//      (l'ÉLÈVE lui-même, jamais un parent), que PARENT IA est actif
//      (« pas de consentement = pas d'analyse »), et qui lit le score de
//      risque RÉUTILISÉ (`risque_reussite_actuel`, sous-1/7 — jamais un
//      second calcul).
//   2. Construit un message CHIFFRES AGRÉGÉS UNIQUEMENT (minutes, score) —
//      jamais un nom, un matricule ou une autre donnée nominative — et
//      appelle Claude UNE fois, avec le prompt technique interne dédié
//      (`PROMPT_ANALYSE_USAGE_PARENT_IA`, distinct des 3 personas
//      officiels).
//   3. Si l'IA juge l'usage excessif, appelle
//      `enregistrer_restriction_parent_ia` (SQL, SECURITY DEFINER — seule
//      autorité d'écriture sur `parent_ia_historique`/`notifications` pour
//      ce flux) pour écrire l'historique + la notification in-app.
//   4. Retourne uniquement { restrictionDeclenchee, message } — jamais les
//      chiffres bruts renvoyés par Claude tels quels, jamais une deuxième
//      source de vérité côté client.
// ============================================================================

import { appellerAnthropicApi, extraireTexte } from "../_shared/anthropic_client.ts";
import { PROMPT_ANALYSE_USAGE_PARENT_IA } from "../_shared/prompts.ts";
import { clientUtilisateur, entetesCors, reponseJson, requisEnv } from "../_shared/supabase_client.ts";

interface CorpsRequete {
  ficheEleveId?: string;
  appPrincipale?: string;
  minutes?: number;
}

interface AnalyseUsage {
  excessif: boolean;
  message: string | null;
  matiereARisque: string | null;
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
    const ficheEleveId = typeof corps.ficheEleveId === "string" ? corps.ficheEleveId : "";
    const appPrincipale = typeof corps.appPrincipale === "string" ? corps.appPrincipale : "";
    const minutes = typeof corps.minutes === "number" ? corps.minutes : NaN;

    if (!ficheEleveId || !appPrincipale || !Number.isFinite(minutes)) {
      return reponseJson(400, { error: "parametres_requis" }, origine);
    }

    const { client: supabase, jeton } = clientUtilisateur(req);
    const { data: userData, error: userError } = await supabase.auth.getUser(jeton);
    if (userError || !userData?.user) {
      return reponseJson(401, { error: "authentification_requise" }, origine);
    }

    const { data: preparation, error: preparationError } = await supabase.rpc(
      "preparer_declaration_usage_parent_ia",
      { p_fiche_eleve_id: ficheEleveId, p_app_principale: appPrincipale, p_minutes: minutes },
    );

    if (preparationError || !preparation) {
      return reponseJson(
        statutPour((preparationError as { code?: string } | null)?.code),
        { error: "declaration_refusee", detail: preparationError?.message },
        origine,
      );
    }

    const { app_principale: appConfirmee, minutes: minutesConfirmees, niveau_risque_echec: niveauRisque } =
      preparation as { app_principale: string; minutes: number; niveau_risque_echec: number };

    // ★ Chiffres agrégés UNIQUEMENT — jamais un nom, un matricule, une
    // classe ou tout autre identifiant envoyé à Anthropic ci-dessous.
    const messageAnalyse =
      `Temps d'usage total : ${minutesConfirmees} minutes. Détail par app : ` +
      `${JSON.stringify({ [appConfirmee]: minutesConfirmees })}. ` +
      `Score de risque d'échec scolaire : ${niveauRisque}/100. Source de la mesure : declaration_manuelle.`;

    const apiKey = requisEnv("ANTHROPIC_API_KEY");

    let data;
    try {
      data = await appellerAnthropicApi({
        apiKey,
        systemPrompt: PROMPT_ANALYSE_USAGE_PARENT_IA,
        messages: [{ role: "user", content: messageAnalyse }],
        maxTokens: 300,
      });
    } catch (erreurAppel) {
      console.error(JSON.stringify({
        fn: "analyser_usage_parent_ia",
        niveau: "error",
        message: "echec appel anthropic",
        detail: erreurAppel instanceof Error ? erreurAppel.message : String(erreurAppel),
      }));
      return reponseJson(502, { error: "erreur_assistant_ia" }, origine);
    }

    let analyse: AnalyseUsage;
    try {
      analyse = JSON.parse(extraireTexte(data.content));
    } catch {
      analyse = { excessif: false, message: null, matiereARisque: null };
    }

    if (analyse.excessif === true) {
      const { error: restrictionError } = await supabase.rpc("enregistrer_restriction_parent_ia", {
        p_fiche_eleve_id: ficheEleveId,
        p_app_principale: appConfirmee,
        p_minutes: minutesConfirmees,
        p_niveau_risque: niveauRisque,
        p_message: analyse.message,
        p_matiere: analyse.matiereARisque ?? null,
      });

      if (restrictionError) {
        console.error(JSON.stringify({
          fn: "analyser_usage_parent_ia",
          niveau: "error",
          message: "echec enregistrement restriction",
          detail: restrictionError.message,
        }));
        return reponseJson(
          statutPour((restrictionError as { code?: string }).code),
          { error: "enregistrement_refuse" },
          origine,
        );
      }
    }

    return reponseJson(200, {
      restrictionDeclenchee: analyse.excessif === true,
      message: analyse.message ?? null,
    }, origine);
  } catch (erreur) {
    console.error(JSON.stringify({
      fn: "analyser_usage_parent_ia",
      niveau: "error",
      message: "erreur inattendue",
      detail: erreur instanceof Error ? erreur.message : String(erreur),
    }));
    return reponseJson(500, { error: "erreur_interne" }, req.headers.get("origin"));
  }
});
