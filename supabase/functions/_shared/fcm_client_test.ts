// Tests unitaires du client Firebase Cloud Messaging (REG-11) — faux serveur.
// Exécution : deno test --allow-env supabase/functions/_shared/fcm_client_test.ts
import { deepStrictEqual as assertEquals } from "node:assert/strict";
import { cible, type CompteServiceFcm, envoyerPush } from "./fcm_client.ts";

const FID = "cAbCdEfGhIjKlMnOpQrS_-";
const JETON = "dGhpc2lzYWxvbmd0b2tlbg:APA91bH" + "x".repeat(140);

Deno.test("identifiant d'installation (FID) envoyé dans `fid`, ancien jeton dans `token`", () => {
  assertEquals(cible(FID), { fid: FID });
  assertEquals(cible(JETON), { token: JETON });
});

async function compte(): Promise<CompteServiceFcm> {
  const paire = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", paire.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`;
  return { project_id: "ecoshop-test", client_email: "push@ecoshop-test.iam.gserviceaccount.com", private_key: pem };
}

function fauxServeur(reponse: (corps: Record<string, unknown>) => Response) {
  const corpsEnvoyes: Record<string, unknown>[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (entree: string | URL | Request, init?: RequestInit) => {
    const url = String(entree);
    if (url.startsWith("https://oauth2.googleapis.com/token")) {
      return new Response(JSON.stringify({ access_token: "acces", expires_in: 3600 }), { status: 200 });
    }
    const corps = JSON.parse(String(init?.body)) as Record<string, unknown>;
    corpsEnvoyes.push(corps);
    return reponse(corps);
  }) as typeof fetch;
  return { corpsEnvoyes, restaurer: () => (globalThis.fetch = original) };
}

Deno.test("envoi vers un FID : le message porte `fid` et le canal Android des alertes", async () => {
  const serveur = fauxServeur(() => new Response("{}", { status: 200 }));
  try {
    const verdict = await envoyerPush(await compte(), FID, "Arrivée à l'école", "Awa est arrivée à 7h42", { type: "pointage_arrivee" });
    assertEquals(verdict, { issue: "envoye" });
    const message = serveur.corpsEnvoyes[0].message as Record<string, unknown>;
    assertEquals(message.fid, FID);
    assertEquals("token" in message, false);
    assertEquals((message.android as Record<string, unknown>).notification, { channel_id: "ecoshop_alertes" });
  } finally {
    serveur.restaurer();
  }
});

Deno.test("téléphone désinscrit (UNREGISTERED) : identifiant à oublier", async () => {
  const serveur = fauxServeur(() =>
    new Response(JSON.stringify({ error: { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] } }), { status: 404 })
  );
  try {
    assertEquals(await envoyerPush(await compte(), FID, "t", "c", {}), { issue: "jeton_invalide" });
  } finally {
    serveur.restaurer();
  }
});

Deno.test("message mal formé (INVALID_ARGUMENT sans viser l'identifiant) : l'identifiant est gardé", async () => {
  const serveur = fauxServeur(() =>
    new Response(JSON.stringify({ error: { status: "INVALID_ARGUMENT", message: "Invalid value at 'message.data[0].value'" } }), { status: 400 })
  );
  try {
    assertEquals(await envoyerPush(await compte(), FID, "t", "c", {}), { issue: "temporaire", erreur: "FCM_400" });
  } finally {
    serveur.restaurer();
  }
});
