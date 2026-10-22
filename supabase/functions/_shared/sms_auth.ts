// ============================================================================
// EcoShop — Codes de connexion par SMS Orange (Edge Function « envoyer_sms_auth »)
//
// Crochet « Send SMS » de Supabase Auth : les codes de connexion par
// téléphone partent par l'API SMS d'Orange Guinée au lieu de Twilio
// (fournisseur américain, environ 0,25 USD par code vers la Guinée, compte
// à part). Même contrat Orange que les SMS des écoles (REG-09).
//
// Appelée par Supabase Auth (verify_jwt = false), authentifiée par la
// signature « Standard Webhooks » ; doit répondre en moins de 5 secondes :
// 200 sans corps si le SMS est parti, sinon { error: { http_code, message } }
// dont le message est montré à l'utilisateur.
//
// Le code n'est jamais écrit dans les journaux.
//
// Variables d'environnement (secrets Supabase) :
//   SEND_SMS_HOOK_SECRETS     « v1,whsec_… » généré dans Authentication → Hooks
//   ORANGE_SMS_CLIENT_ID, ORANGE_SMS_CLIENT_SECRET (+ facultatifs, voir
//   _shared/orange_sms_client.ts)
// ============================================================================

import { configSmsOrangeDepuisEnv, envoyerSmsOrange, numeroInternational } from "./orange_sms_client.ts";
import { verifierAppelSigne } from "./standard_webhooks.ts";

interface AppelEnvoiSms {
  user?: { id?: string; phone?: string };
  sms?: { otp?: string };
}

/** Indicatifs servis par le contrat Orange SMS de GSG. */
const INDICATIFS_SERVIS = ["224"];

export function texteCode(code: string): string {
  // Alphabet GSM 7 bits (sans accents) : un seul SMS de 160 caractères.
  return `EcoShop : votre code de connexion est ${code}. Il expire dans 10 minutes. Ne le communiquez a personne.`;
}

function refus(http_code: number, message: string): Response {
  return new Response(JSON.stringify({ error: { http_code, message } }), {
    status: http_code,
    headers: { "Content-Type": "application/json" },
  });
}

export async function traiter(req: Request): Promise<Response> {
  if (req.method !== "POST") return refus(405, "Méthode non autorisée.");
  const secrets = Deno.env.get("SEND_SMS_HOOK_SECRETS");
  if (!secrets) return refus(500, "Envoi des codes SMS non configuré.");

  const corps = await req.text();
  if (!(await verifierAppelSigne(secrets, req.headers, corps))) {
    return refus(401, "Appel non authentifié.");
  }

  let appel: AppelEnvoiSms;
  try {
    appel = JSON.parse(corps) as AppelEnvoiSms;
  } catch {
    return refus(400, "Requête illisible.");
  }
  const code = appel.sms?.otp ?? "";
  const numero = numeroInternational(appel.user?.phone ?? "");
  if (!/^[0-9]{4,10}$/.test(code) || !numero) return refus(400, "Numéro de téléphone invalide.");
  if (!INDICATIFS_SERVIS.some((i) => numero.startsWith(i))) {
    return refus(400, "Les codes par SMS ne sont envoyés qu'aux numéros de Guinée : connectez-vous avec votre adresse e-mail.");
  }

  const config = configSmsOrangeDepuisEnv();
  if (!config) return refus(500, "Envoi des codes SMS non configuré.");

  const verdict = await envoyerSmsOrange(config, numero, texteCode(code));
  if (verdict.issue === "envoye") {
    console.log(JSON.stringify({ fn: "envoyer_sms_auth", issue: "envoye", indicatif: numero.slice(0, 3) }));
    return new Response(null, { status: 200 });
  }
  console.error(JSON.stringify({ fn: "envoyer_sms_auth", issue: verdict.issue, erreur: verdict.erreur }));
  return refus(
    verdict.issue === "definitif" ? 400 : 503,
    verdict.issue === "definitif"
      ? "Ce numéro ne peut pas recevoir de SMS."
      : "Le SMS n'a pas pu partir pour le moment. Réessayez dans une minute.",
  );
}

