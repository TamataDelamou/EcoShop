// ============================================================================
// EcoShop — client CinetPay brut PARTAGÉ (Facturation/Quota IA, étape (b))
//
// SEUL point d'appel sortant réel vers l'API CinetPay dans tout ce projet —
// même discipline que `_shared/anthropic_client.ts` (M16) : un point d'appel
// HTTP unique, jamais dupliqué, jamais appelé directement depuis le client
// Flutter. Toute la logique interne (recalcul du montant, vérification de
// signature, idempotence, dispatch entitlement) vit côté SQL
// (migration 20260906001515) et ne dépend PAS de ce module — elle est déjà
// entièrement testée (tests/rls/50) avec des paiements/webhooks SIMULÉS,
// sans le moindre identifiant CinetPay réel.
//
// ⚠️ Aucun identifiant CinetPay (test/sandbox) disponible au moment de
// l'écriture. Champs/endpoint documentés au mieux de la connaissance
// actuelle (API Checkout v2) -- À REVÉRIFIER contre la documentation
// CinetPay en vigueur et tester avec un compte marchand réel avant toute
// mise en production (même avertissement que CINETPAY.md §4 dans
// ecoshop_flutter, la référence fonctionnelle de ce module).
//
// `CINETPAY_URL_OVERRIDE` (variable d'env, PAS un secret) : point
// d'extension UNIQUEMENT pour le développement/test local, redirige l'appel
// vers un faux serveur HTTP simulant l'API CinetPay — jamais utilisé en
// production. Même mécanisme qu'ANTHROPIC_URL_OVERRIDE (M16).
// ============================================================================

const CINETPAY_URL_DEFAUT = "https://api-checkout.cinetpay.com/v2/payment";

function resoudreUrlCinetpay(): string {
  return Deno.env.get("CINETPAY_URL_OVERRIDE") || CINETPAY_URL_DEFAUT;
}

export interface OptionsInitiationCinetpay {
  apiKey: string;
  siteId: string;
  transactionId: string;
  montant: number;
  devise: string;
  description: string;
  notifyUrl: string;
  returnUrl: string;
  /** Injectable pour les tests — remplace `fetch` global, jamais utilisé en production. */
  fetchImpl?: typeof fetch;
}

export interface ReponseInitiationCinetpay {
  url_paiement: string;
  reference_cinetpay?: string;
  [cle: string]: unknown;
}

/**
 * Initie un paiement CinetPay et renvoie l'URL de paiement Checkout.
 * Ne recalcule RIEN : `montant` doit déjà être le montant recalculé serveur
 * (voir `initier_transaction_cinetpay`, SQL) — cette fonction ne fait que
 * relayer l'appel HTTP, jamais de logique métier ici.
 */
export async function initierPaiementCinetpayReel(
  options: OptionsInitiationCinetpay,
): Promise<ReponseInitiationCinetpay> {
  const { apiKey, siteId, transactionId, montant, devise, description, notifyUrl, returnUrl, fetchImpl } = options;
  const executerFetch = fetchImpl ?? fetch;

  const response = await executerFetch(resoudreUrlCinetpay(), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      apikey: apiKey,
      site_id: siteId,
      transaction_id: transactionId,
      amount: montant,
      currency: devise,
      description,
      notify_url: notifyUrl,
      return_url: returnUrl,
      channels: "ALL",
    }),
  });

  if (!response.ok) {
    const errTxt = await response.text();
    console.error(JSON.stringify({
      fn: "cinetpay_client",
      niveau: "error",
      message: "erreur API CinetPay (initiation)",
      detail: errTxt,
    }));
    throw new Error("Erreur lors de l'initiation du paiement CinetPay.");
  }

  const data = await response.json();
  const urlPaiement = data?.data?.payment_url ?? data?.url_paiement;
  if (!urlPaiement) {
    console.error(JSON.stringify({
      fn: "cinetpay_client",
      niveau: "error",
      message: "reponse CinetPay sans url de paiement",
      detail: JSON.stringify(data),
    }));
    throw new Error("Réponse CinetPay inattendue (aucune URL de paiement).");
  }

  return { url_paiement: urlPaiement, reference_cinetpay: data?.data?.payment_token };
}
