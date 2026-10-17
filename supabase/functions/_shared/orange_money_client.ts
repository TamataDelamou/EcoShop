// ============================================================================
// EcoShop — client Orange Money Web Payment (REG-02, lot L2)
//
// SEUL point d'appel sortant vers l'API Orange Money dans tout le projet —
// même discipline que _shared/cinetpay_client.ts. Aucune logique métier ici :
// montant, droits et idempotence vivent côté SQL (migration 20260906001529).
//
// ⚠️ Contrat de l'API Orange Money Web Payment documenté au mieux de la
// connaissance publique (jeton OAuth « client credentials », création d'un
// paiement, consultation du statut). Chemins exacts, code pays guinéen,
// devise du bac à sable et format de la notification : À CONFIRMER sur la
// documentation remise par Orange Guinée avec l'accès au bac à sable. Tous
// ces points sont regroupés dans CONFIG_ORANGE ci-dessous pour être corrigés
// en un seul endroit.
//
// `ORANGE_MONEY_URL_OVERRIDE` (variable d'environnement, PAS un secret) :
// redirige vers un faux serveur pour le développement et les tests, jamais
// en production — même mécanisme que CINETPAY_URL_OVERRIDE.
// ============================================================================

export type Environnement = "test" | "production";

export interface IdentifiantsOrange {
  client_id: string;
  client_secret: string;
  merchant_key: string;
  environnement: Environnement;
}

/** Points susceptibles d'évoluer après lecture de la doc Orange Guinée. */
export const CONFIG_ORANGE = {
  urlBase: "https://api.orange.com",
  cheminJeton: "/oauth/v3/token",
  /** Segment pays du chemin Web Payment : bac à sable vs Guinée. */
  segmentPays: { test: "dev", production: "gn" } as Record<Environnement, string>,
  /** Devise transmise à Orange : devise fictive en bac à sable, GNF en prod. */
  devise: { test: "OUV", production: "GNF" } as Record<Environnement, string>,
};

export type StatutOrange = "INITIATED" | "PENDING" | "EXPIRED" | "SUCCESS" | "FAILED" | string;

/** Traduction d'un statut Orange en résultat EcoShop (null = pas encore final). */
export function resultatDepuisStatut(statut: StatutOrange): "reussi" | "echoue" | null {
  switch ((statut ?? "").toUpperCase()) {
    case "SUCCESS":
      return "reussi";
    case "FAILED":
    case "EXPIRED":
      return "echoue";
    default:
      return null;
  }
}

export class ErreurOrange extends Error {
  constructor(public readonly code: string, public readonly statutHttp?: number) {
    super(code);
    this.name = "ErreurOrange";
  }
}

function base(): string {
  return (Deno.env.get("ORANGE_MONEY_URL_OVERRIDE") || CONFIG_ORANGE.urlBase).replace(/\/+$/, "");
}

function cheminWebPay(env: Environnement, action: "webpayment" | "transactionstatus"): string {
  return `/orange-money-webpay/${CONFIG_ORANGE.segmentPays[env]}/v1/${action}`;
}

export interface Dependances {
  fetchImpl?: typeof fetch;
  delaiMs?: number;
}

async function appel(
  url: string,
  init: RequestInit,
  { fetchImpl, delaiMs }: Dependances,
): Promise<Record<string, unknown>> {
  const res = await (fetchImpl ?? fetch)(url, {
    ...init,
    signal: AbortSignal.timeout(delaiMs ?? 15000),
  });
  const texte = await res.text();
  if (!res.ok) {
    // Le corps n'est jamais relayé à l'appelant : il peut contenir des détails internes.
    throw new ErreurOrange("ORANGE_HTTP_" + res.status, res.status);
  }
  try {
    return JSON.parse(texte);
  } catch {
    throw new ErreurOrange("ORANGE_REPONSE_ILLISIBLE", res.status);
  }
}

/** Jeton d'accès OAuth 2 (client credentials). */
export async function obtenirJeton(id: IdentifiantsOrange, deps: Dependances = {}): Promise<string> {
  const json = await appel(`${base()}${CONFIG_ORANGE.cheminJeton}`, {
    method: "POST",
    headers: {
      Authorization: "Basic " + btoa(`${id.client_id}:${id.client_secret}`),
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: "grant_type=client_credentials",
  }, deps);
  const jeton = json.access_token;
  if (typeof jeton !== "string" || !jeton) throw new ErreurOrange("ORANGE_JETON_ABSENT");
  return jeton;
}

export interface DemandePaiement {
  referenceCommande: string;
  montant: number;
  urlRetour: string;
  urlAnnulation: string;
  urlNotification: string;
  reference?: string;
}

export interface PaiementCree {
  urlPaiement: string;
  payToken: string;
  notifToken: string;
}

/** Crée un paiement Web Payment ; renvoie l'URL où rediriger le payeur. */
export async function creerPaiement(
  id: IdentifiantsOrange,
  jeton: string,
  demande: DemandePaiement,
  deps: Dependances = {},
): Promise<PaiementCree> {
  const json = await appel(`${base()}${cheminWebPay(id.environnement, "webpayment")}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${jeton}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      merchant_key: id.merchant_key,
      currency: CONFIG_ORANGE.devise[id.environnement],
      order_id: demande.referenceCommande,
      amount: demande.montant,
      return_url: demande.urlRetour,
      cancel_url: demande.urlAnnulation,
      notif_url: demande.urlNotification,
      lang: "fr",
      reference: demande.reference ?? "EcoShop",
    }),
  }, deps);

  const urlPaiement = json.payment_url;
  const payToken = json.pay_token;
  const notifToken = json.notif_token;
  if (typeof urlPaiement !== "string" || typeof payToken !== "string" || typeof notifToken !== "string") {
    throw new ErreurOrange("ORANGE_REPONSE_INCOMPLETE");
  }
  return { urlPaiement, payToken, notifToken };
}

/** Statut d'un paiement, interrogé directement chez Orange (seule source crue). */
export async function consulterStatut(
  id: IdentifiantsOrange,
  jeton: string,
  requete: { referenceCommande: string; montant: number; payToken: string },
  deps: Dependances = {},
): Promise<{ statut: StatutOrange; referenceOperateur: string | null }> {
  const json = await appel(`${base()}${cheminWebPay(id.environnement, "transactionstatus")}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${jeton}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      order_id: requete.referenceCommande,
      amount: requete.montant,
      pay_token: requete.payToken,
    }),
  }, deps);
  return {
    statut: String(json.status ?? ""),
    referenceOperateur: typeof json.txnid === "string" ? json.txnid : null,
  };
}

/** Empreinte SHA-256 (hex) — le notif_token n'est jamais stocké en clair. */
export async function empreinte(valeur: string): Promise<string> {
  const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(valeur));
  return Array.from(new Uint8Array(h)).map((o) => o.toString(16).padStart(2, "0")).join("");
}
