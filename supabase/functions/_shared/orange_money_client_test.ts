// Tests unitaires du client Orange Money (REG-02, lot L2) — faux serveur.
// Exécution : deno test --allow-env supabase/functions/_shared/orange_money_client_test.ts
import { ok as assert, rejects, strictEqual as assertEquals } from "node:assert/strict";
import {
  consulterStatut,
  creerPaiement,
  empreinte,
  ErreurOrange,
  type IdentifiantsOrange,
  obtenirJeton,
  resultatDepuisStatut,
} from "./orange_money_client.ts";

const ID_TEST: IdentifiantsOrange = {
  client_id: "cid", client_secret: "csecret", merchant_key: "MK123", environnement: "test",
};

interface Appel { url: string; init: RequestInit }

function fauxServeur(reponses: Array<{ status?: number; corps: unknown }>) {
  const appels: Appel[] = [];
  const fetchImpl = ((url: string, init: RequestInit) => {
    appels.push({ url, init });
    const r = reponses.shift() ?? { status: 500, corps: {} };
    return Promise.resolve(new Response(JSON.stringify(r.corps), { status: r.status ?? 200 }));
  }) as unknown as typeof fetch;
  return { appels, fetchImpl };
}

Deno.test("statuts Orange traduits : seuls SUCCESS / FAILED / EXPIRED sont finaux", () => {
  assertEquals(resultatDepuisStatut("SUCCESS"), "reussi");
  assertEquals(resultatDepuisStatut("FAILED"), "echoue");
  assertEquals(resultatDepuisStatut("EXPIRED"), "echoue");
  assertEquals(resultatDepuisStatut("PENDING"), null);
  assertEquals(resultatDepuisStatut("INITIATED"), null);
  assertEquals(resultatDepuisStatut(""), null);
});

Deno.test("jeton OAuth : authentification Basic client_id:client_secret", async () => {
  const { appels, fetchImpl } = fauxServeur([{ corps: { access_token: "AT-1" } }]);
  assertEquals(await obtenirJeton(ID_TEST, { fetchImpl }), "AT-1");
  assert(appels[0].url.endsWith("/oauth/v3/token"));
  assertEquals((appels[0].init.headers as Record<string, string>).Authorization, "Basic " + btoa("cid:csecret"));
  assertEquals(appels[0].init.body, "grant_type=client_credentials");
});

Deno.test("création de paiement : bac à sable => segment dev et devise OUV", async () => {
  const { appels, fetchImpl } = fauxServeur([{
    corps: { payment_url: "https://pay/x", pay_token: "PT", notif_token: "NT" },
  }]);
  const p = await creerPaiement(ID_TEST, "AT-1", {
    referenceCommande: "ECOABC", montant: 500000, urlRetour: "r", urlAnnulation: "c", urlNotification: "n",
  }, { fetchImpl });
  assertEquals(p.urlPaiement, "https://pay/x");
  assert(appels[0].url.endsWith("/orange-money-webpay/dev/v1/webpayment"));
  const corps = JSON.parse(appels[0].init.body as string);
  assertEquals(corps.currency, "OUV");
  assertEquals(corps.merchant_key, "MK123");
  assertEquals(corps.order_id, "ECOABC");
  assertEquals(corps.amount, 500000);
  assertEquals(corps.notif_url, "n");
});

Deno.test("création de paiement : production => segment gn et devise GNF", async () => {
  const { appels, fetchImpl } = fauxServeur([{
    corps: { payment_url: "u", pay_token: "PT", notif_token: "NT" },
  }]);
  await creerPaiement({ ...ID_TEST, environnement: "production" }, "AT", {
    referenceCommande: "R", montant: 1, urlRetour: "r", urlAnnulation: "c", urlNotification: "n",
  }, { fetchImpl });
  assert(appels[0].url.endsWith("/orange-money-webpay/gn/v1/webpayment"));
  assertEquals(JSON.parse(appels[0].init.body as string).currency, "GNF");
});

Deno.test("réponse incomplète ou erreur HTTP : erreur typée, jamais le corps relayé", async () => {
  const incomplet = fauxServeur([{ corps: { payment_url: "u" } }]);
  await rejects(() => creerPaiement(ID_TEST, "AT", {
    referenceCommande: "R", montant: 1, urlRetour: "r", urlAnnulation: "c", urlNotification: "n",
  }, { fetchImpl: incomplet.fetchImpl }), (e: unknown) => e instanceof ErreurOrange && e.code === "ORANGE_REPONSE_INCOMPLETE");

  const http = fauxServeur([{ status: 401, corps: { message: "secret interne" } }]);
  await rejects(() => obtenirJeton(ID_TEST, { fetchImpl: http.fetchImpl }),
    (e: unknown) => e instanceof ErreurOrange && e.code === "ORANGE_HTTP_401" && !e.message.includes("secret"));
});

Deno.test("consultation du statut : order_id, montant et pay_token transmis", async () => {
  const { appels, fetchImpl } = fauxServeur([{ corps: { status: "SUCCESS", txnid: "MP123" } }]);
  const s = await consulterStatut(ID_TEST, "AT", { referenceCommande: "ECO1", montant: 75000, payToken: "PT" }, { fetchImpl });
  assertEquals(s.statut, "SUCCESS");
  assertEquals(s.referenceOperateur, "MP123");
  assert(appels[0].url.endsWith("/orange-money-webpay/dev/v1/transactionstatus"));
  assertEquals(JSON.parse(appels[0].init.body as string).pay_token, "PT");
});

Deno.test("empreinte SHA-256 déterministe (le notif_token n'est jamais stocké)", async () => {
  const a = await empreinte("NT");
  assertEquals(a, await empreinte("NT"));
  assert(a !== await empreinte("NT2"));
  assertEquals(a.length, 64);
});
