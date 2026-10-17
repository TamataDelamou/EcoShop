// Tests unitaires : modèles de courriels + client Brevo (REG-04) — faux serveur.
// Exécution : deno test --allow-env supabase/functions/_shared/courriel_test.ts
import { ok as assert, strictEqual as assertEquals, throws } from "node:assert/strict";
import { corpsRequeteBrevo, type ConfigBrevo, envoyerCourrielBrevo, URL_BREVO_COURRIEL } from "./brevo_client.ts";
import { echapperHtml, ModeleInconnu, rendreCourriel } from "./modeles_courriel.ts";

const CTX = { urlApplication: "https://globalservicegroupe.com", adresseSupport: "contact@globalservicegroupe.com" };
const DONNEES = {
  prenom: "Mariama", nom_etablissement: "École Bambino Emmaüs", ville: "Conakry", pays: "Guinée", reference: "AB12CD34",
};
const CONFIG: ConfigBrevo = {
  cleApi: "xkeysib-test",
  expediteur: { email: "ne-pas-repondre@globalservicegroupe.com", nom: "EcoShop" },
  repondreA: "contact@globalservicegroupe.com",
};
const MESSAGE = { destinataire: "a@b.org", sujet: "S", html: "<p>h</p>", texte: "t", cleIdempotence: "demande_recue:1" };

function fauxServeur(status: number, corps: unknown) {
  const appels: Array<{ url: string; init: RequestInit }> = [];
  const fetchImpl = ((url: string, init: RequestInit) => {
    appels.push({ url, init });
    return Promise.resolve(new Response(JSON.stringify(corps), { status }));
  }) as unknown as typeof fetch;
  return { appels, fetchImpl };
}

Deno.test("les quatre modèles se rendent avec sujet, HTML et version texte", () => {
  for (const m of ["demande_etablissement_recue", "demande_etablissement_acceptee", "demande_etablissement_refusee", "demande_etablissement_a_traiter"]) {
    const r = rendreCourriel(m, { ...DONNEES, motif: "Pièce manquante", effectif_estime: 320 }, CTX);
    assert(r.sujet.includes("École Bambino Emmaüs"), m);
    assert(r.html.startsWith("<!doctype html>"), m);
    assert(r.html.includes('lang="fr"'), m);
    assert(r.texte.includes("AB12CD34"), `${m} : référence dans la version texte`);
    assert(!r.html.includes("<img"), `${m} : aucune image distante ni pixel de suivi`);
  }
});

Deno.test("le refus affiche le motif ; l'acceptation propose d'ouvrir l'application", () => {
  const refus = rendreCourriel("demande_etablissement_refusee", { ...DONNEES, motif: "Autorisation illisible" }, CTX);
  assert(refus.texte.includes("Autorisation illisible"));
  const accepte = rendreCourriel("demande_etablissement_acceptee", DONNEES, CTX);
  assert(accepte.html.includes('href="https://globalservicegroupe.com"'));
  assert(accepte.texte.includes("Ouvrir EcoShop : https://globalservicegroupe.com"));
});

Deno.test("salutation sans prénom : « Bonjour, »", () => {
  const r = rendreCourriel("demande_etablissement_recue", { ...DONNEES, prenom: null }, CTX);
  assert(r.texte.includes("Bonjour,"));
});

Deno.test("les données saisies sont échappées (pas d'injection HTML) et le sujet n'a pas de saut de ligne", () => {
  const r = rendreCourriel("demande_etablissement_recue", {
    ...DONNEES, nom_etablissement: "<script>alert(1)</script>\r\nBcc: x@y.z",
  }, CTX);
  assert(!r.html.includes("<script>"));
  assert(r.html.includes("&lt;script&gt;"));
  assert(!/[\r\n]/.test(r.sujet));
  assertEquals(echapperHtml(`"'&`), "&quot;&#39;&amp;");
});

Deno.test("modèle inconnu : erreur dédiée (échec définitif côté file)", () => {
  throws(() => rendreCourriel("inconnu", {}, CTX), ModeleInconnu);
});

Deno.test("requête Brevo : expéditeur, destinataire, texte + HTML, clé d'idempotence, répondre-à", () => {
  const c = corpsRequeteBrevo(CONFIG, MESSAGE) as Record<string, any>;
  assertEquals(c.sender.email, "ne-pas-repondre@globalservicegroupe.com");
  assertEquals(c.to[0].email, "a@b.org");
  assertEquals(c.textContent, "t");
  assertEquals(c.htmlContent, "<p>h</p>");
  assertEquals(c.headers.IdempotencyKey, "demande_recue:1");
  assertEquals(c.replyTo.email, "contact@globalservicegroupe.com");
  assertEquals(c.headers["X-Sib-Sandbox"], undefined);
  const sable = corpsRequeteBrevo({ ...CONFIG, bacASable: true }, MESSAGE) as Record<string, any>;
  assertEquals(sable.headers["X-Sib-Sandbox"], "drop");
});

Deno.test("201 : envoyé, identifiant conservé, clé API dans l'en-tête api-key", async () => {
  const { appels, fetchImpl } = fauxServeur(201, { messageId: "<id-1@brevo>" });
  const v = await envoyerCourrielBrevo(CONFIG, MESSAGE, fetchImpl);
  assertEquals(v.issue, "envoye");
  assertEquals(v.issue === "envoye" && v.identifiant, "<id-1@brevo>");
  assertEquals(appels[0].url, URL_BREVO_COURRIEL);
  assertEquals((appels[0].init.headers as Record<string, string>)["api-key"], "xkeysib-test");
});

Deno.test("classement des erreurs : 429/5xx temporaires, 401 alerte de configuration, 400 définitif", async () => {
  assertEquals((await envoyerCourrielBrevo(CONFIG, MESSAGE, fauxServeur(429, {}).fetchImpl)).issue, "temporaire");
  assertEquals((await envoyerCourrielBrevo(CONFIG, MESSAGE, fauxServeur(503, {}).fetchImpl)).issue, "temporaire");
  const v401 = await envoyerCourrielBrevo(CONFIG, MESSAGE, fauxServeur(401, { code: "unauthorized", message: "Key not found" }).fetchImpl);
  assertEquals(v401.issue, "temporaire");
  assert(v401.issue === "temporaire" && v401.alerteConfiguration === true);
  const v400 = await envoyerCourrielBrevo(CONFIG, MESSAGE, fauxServeur(400, { code: "invalid_parameter", message: "email is not valid" }).fetchImpl);
  assertEquals(v400.issue, "definitif");
  assert(v400.issue === "definitif" && v400.erreur.includes("invalid_parameter"));
});

Deno.test("panne réseau : temporaire, aucune exception", async () => {
  const fetchImpl = (() => Promise.reject(new TypeError("connexion refusée"))) as unknown as typeof fetch;
  const v = await envoyerCourrielBrevo(CONFIG, MESSAGE, fetchImpl);
  assertEquals(v.issue, "temporaire");
});
