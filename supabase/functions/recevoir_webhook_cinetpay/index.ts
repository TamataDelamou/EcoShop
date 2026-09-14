// ============================================================================
// EcoShop — Edge Function « recevoir_webhook_cinetpay »
// (Facturation/Quota IA, étape (b) : brique CinetPay générique)
//
// Point d'entrée HTTP appelé DIRECTEMENT par les serveurs CinetPay — jamais
// de JWT Supabase (verify_jwt = false, voir config.toml). La signature
// CinetPay est la SEULE barrière, et elle est vérifiée côté SQL
// (`traiter_webhook_cinetpay`, migration 20260906001515), pas ici : cette
// fonction ne fait qu'extraire les champs de la requête CinetPay et les
// relayer, en service_role, à la SEULE autorité de crédit. Toute la logique
// (recalcul, idempotence, dispatch entitlement) est déjà testée (tests/rls/50)
// avec des webhooks SIMULÉS.
//
// ⚠️ Noms de champs du payload CinetPay (cpm_trans_id, cpm_amount,
// payment_method) et header de signature (x-token) documentés au mieux de
// la connaissance actuelle, en l'absence de tout compte marchand réel — à
// REVÉRIFIER contre la documentation CinetPay en vigueur avant mise en
// production (même avertissement que _shared/cinetpay_client.ts).
// ============================================================================

import { clientService, entetesCors, reponseJson } from "../_shared/supabase_client.ts";

const STATUT_PAR_ERRCODE: Record<string, number> = {
  "42501": 401, // signature invalide
  "23514": 404, // transaction introuvable
  "55000": 503, // CinetPay non configuré côté EcoShop
};

Deno.serve(async (req) => {
  const origine = req.headers.get("origin");

  if (req.method !== "POST") {
    return reponseJson(405, { error: "methode_non_autorisee" }, origine);
  }

  try {
    const corps = await req.json().catch(() => ({} as Record<string, unknown>));
    const signature = req.headers.get("x-token");

    const transactionId = (corps.cpm_trans_id ?? corps.transaction_id) as string | undefined;
    const montant = (corps.cpm_amount ?? corps.amount) as number | undefined;
    const moyen = (corps.payment_method ?? corps.cpm_payment_config) as string | undefined;

    if (!transactionId || montant === undefined) {
      return reponseJson(400, { error: "payload_incomplet" }, origine);
    }

    const service = clientService();
    const { data, error } = await service
      .rpc("traiter_webhook_cinetpay", {
        p_transaction_id: transactionId,
        p_signature: signature,
        p_montant: montant,
        p_moyen: moyen ?? null,
        p_payload: corps,
      })
      .single();

    if (error) {
      console.error(JSON.stringify({
        fn: "recevoir_webhook_cinetpay",
        niveau: "error",
        message: "webhook CinetPay refuse",
        detail: error.message,
      }));
      const statut = STATUT_PAR_ERRCODE[error.code ?? ""] ?? 500;
      return reponseJson(statut, { error: error.message }, origine);
    }

    // Toujours 200 pour un webhook effectivement traité, même si le résultat
    // métier est 'echoue' (écart de montant) — CinetPay n'a pas besoin de
    // rejouer un webhook qui a été correctement reçu et arbitré.
    return reponseJson(200, { statut: data?.statut }, origine);
  } catch (erreur) {
    console.error(JSON.stringify({
      fn: "recevoir_webhook_cinetpay",
      niveau: "error",
      message: "erreur inattendue",
      detail: erreur instanceof Error ? erreur.message : String(erreur),
    }));
    return reponseJson(500, { error: "erreur_interne" }, req.headers.get("origin"));
  }
});
