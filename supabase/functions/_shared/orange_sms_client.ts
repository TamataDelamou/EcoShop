// ============================================================================
// EcoShop — Client SMS Orange (API « SMS Africa & Middle East », Guinée)
// REG-09 : SMS achetés par les établissements (crédits revendus par GSG).
//
//   • Jeton : POST https://api.orange.com/oauth/v3/token
//     (Authorization: Basic base64(client_id:client_secret),
//      grant_type=client_credentials) — valable 1 heure, gardé en mémoire.
//   • Envoi : POST https://api.orange.com/smsmessaging/v1/outbound/
//     tel%3A%2B{expéditeur}/requests ; expéditeur de la Guinée : 2240000 ;
//     nom d'expéditeur (11 caractères max) seulement s'il est validé par
//     Orange, sinon l'API répond 400.
//
// Variables d'environnement (secrets Supabase, JAMAIS dans le dépôt) :
//   ORANGE_SMS_CLIENT_ID, ORANGE_SMS_CLIENT_SECRET   (obligatoires)
//   ORANGE_SMS_EXPEDITEUR       défaut 2240000 (Guinée)
//   ORANGE_SMS_NOM_EXPEDITEUR   facultatif, validé par Orange
//   ORANGE_SMS_URL              facultatif (simulation en local)
// ============================================================================

export interface ConfigSmsOrange {
  clientId: string;
  clientSecret: string;
  expediteur: string;
  nomExpediteur?: string;
  urlBase: string;
}

export type VerdictSms =
  | { issue: "envoye"; identifiant: string }
  | { issue: "temporaire"; erreur: string; alerteConfiguration?: boolean }
  | { issue: "definitif"; erreur: string };

export function configSmsOrangeDepuisEnv(): ConfigSmsOrange | null {
  const clientId = Deno.env.get("ORANGE_SMS_CLIENT_ID");
  const clientSecret = Deno.env.get("ORANGE_SMS_CLIENT_SECRET");
  if (!clientId || !clientSecret) return null;
  return {
    clientId,
    clientSecret,
    expediteur: (Deno.env.get("ORANGE_SMS_EXPEDITEUR") ?? "2240000").replace(/[^0-9]/g, ""),
    nomExpediteur: Deno.env.get("ORANGE_SMS_NOM_EXPEDITEUR") || undefined,
    urlBase: Deno.env.get("ORANGE_SMS_URL") ?? "https://api.orange.com",
  };
}

let jetonEnCache: { valeur: string; expireA: number } | null = null;

async function jeton(config: ConfigSmsOrange, forcer = false): Promise<string> {
  if (!forcer && jetonEnCache && jetonEnCache.expireA > Date.now() + 60_000) return jetonEnCache.valeur;
  const reponse = await fetch(`${config.urlBase}/oauth/v3/token`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${config.clientId}:${config.clientSecret}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: "grant_type=client_credentials",
  });
  if (!reponse.ok) throw new ErreurJetonOrange(reponse.status);
  const corps = await reponse.json() as { access_token: string; expires_in?: number };
  jetonEnCache = { valeur: corps.access_token, expireA: Date.now() + (corps.expires_in ?? 3600) * 1000 };
  return corps.access_token;
}

export class ErreurJetonOrange extends Error {
  constructor(readonly statut: number) {
    super(`JETON_ORANGE_${statut}`);
  }
}

/** Numéro au format international sans « + » ni « 00 » (ex. 224620000000). */
export function numeroInternational(numero: string): string | null {
  let n = numero.replace(/[^0-9]/g, "");
  if (n.startsWith("00")) n = n.slice(2);
  if (n.length === 9 && n.startsWith("6")) n = `224${n}`; // mobile guinéen saisi sans indicatif
  return n.length >= 10 && n.length <= 15 ? n : null;
}

export async function envoyerSmsOrange(config: ConfigSmsOrange, destinataire: string, message: string): Promise<VerdictSms> {
  const numero = numeroInternational(destinataire);
  if (!numero) return { issue: "definitif", erreur: "NUMERO_INVALIDE" };

  const corps = {
    outboundSMSMessageRequest: {
      address: `tel:+${numero}`,
      senderAddress: `tel:+${config.expediteur}`,
      ...(config.nomExpediteur ? { senderName: config.nomExpediteur } : {}),
      outboundSMSTextMessage: { message },
    },
  };
  const url = `${config.urlBase}/smsmessaging/v1/outbound/${encodeURIComponent(`tel:+${config.expediteur}`)}/requests`;

  for (let essai = 0; essai < 2; essai++) {
    let acces: string;
    try {
      acces = await jeton(config, essai > 0);
    } catch (e) {
      if (e instanceof ErreurJetonOrange && (e.statut === 400 || e.statut === 401 || e.statut === 403)) {
        return { issue: "temporaire", erreur: e.message, alerteConfiguration: true };
      }
      return { issue: "temporaire", erreur: "ORANGE_INJOIGNABLE" };
    }

    let reponse: Response;
    try {
      reponse = await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${acces}`, "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(corps),
      });
    } catch {
      return { issue: "temporaire", erreur: "ORANGE_INJOIGNABLE" };
    }

    if (reponse.status === 201 || reponse.ok) {
      const lu = await reponse.json().catch(() => ({})) as { outboundSMSMessageRequest?: { resourceURL?: string } };
      const ressource = lu.outboundSMSMessageRequest?.resourceURL ?? reponse.headers.get("Location") ?? "";
      return { issue: "envoye", identifiant: ressource.split("/").pop() ?? "" };
    }
    if (reponse.status === 401 && essai === 0) {
      jetonEnCache = null; // jeton expiré : on le renouvelle une fois
      continue;
    }
    const detail = (await reponse.text().catch(() => "")).slice(0, 200);
    if (reponse.status === 403) {
      // Contrat épuisé ou expiré chez Orange : à régler par GSG.
      return { issue: "temporaire", erreur: `ORANGE_403 ${detail}`, alerteConfiguration: true };
    }
    if (reponse.status === 429 || reponse.status >= 500) {
      return { issue: "temporaire", erreur: `ORANGE_${reponse.status}` };
    }
    return { issue: "definitif", erreur: `ORANGE_${reponse.status} ${detail}` };
  }
  return { issue: "temporaire", erreur: "ORANGE_JETON_REFUSE", alerteConfiguration: true };
}
