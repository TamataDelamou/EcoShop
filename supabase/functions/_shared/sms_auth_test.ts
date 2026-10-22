// Tests du crochet d'envoi des codes de connexion par SMS Orange.
// Exécution : deno test --allow-env supabase/functions/_shared/sms_auth_test.ts
import { deepStrictEqual as assertEquals, ok as assert } from "node:assert/strict";
import { signer, verifierAppelSigne } from "./standard_webhooks.ts";
import { texteCode, traiter } from "./sms_auth.ts";

const CLE = crypto.getRandomValues(new Uint8Array(32));
const SECRET = `v1,whsec_${btoa(String.fromCharCode(...CLE))}`;

async function appel(corps: unknown, options: { secret?: Uint8Array<ArrayBuffer>; decalage?: number } = {}): Promise<Request> {
  const texte = JSON.stringify(corps);
  const id = "msg_test";
  const t = String(Math.floor(Date.now() / 1000) + (options.decalage ?? 0));
  const signature = await signer(options.secret ?? CLE, id, t, texte);
  return new Request("http://localhost/envoyer_sms_auth", {
    method: "POST",
    headers: { "webhook-id": id, "webhook-timestamp": t, "webhook-signature": `v1,${signature}` },
    body: texte,
  });
}

function fauxOrange(statut = 201) {
  const envois: Record<string, unknown>[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (entree: string | URL | Request, init?: RequestInit) => {
    const url = String(entree);
    if (url.endsWith("/oauth/v3/token")) {
      return new Response(JSON.stringify({ access_token: "jeton", expires_in: 3600 }), { status: 200 });
    }
    envois.push(JSON.parse(String(init?.body)));
    return new Response(JSON.stringify({ outboundSMSMessageRequest: { resourceURL: "x/abc" } }), { status: statut });
  }) as typeof fetch;
  return { envois, restaurer: () => (globalThis.fetch = original) };
}

function configurer() {
  Deno.env.set("SEND_SMS_HOOK_SECRETS", `v1,whsec_${btoa("ancienne-cle-de-rotation-32-oct!")}|${SECRET}`);
  Deno.env.set("ORANGE_SMS_CLIENT_ID", "id");
  Deno.env.set("ORANGE_SMS_CLIENT_SECRET", "secret");
  Deno.env.set("ORANGE_SMS_URL", "https://orange.test");
}

Deno.test("signature valide (deuxième secret de la rotation) acceptée ; trafiquée ou ancienne refusée", async () => {
  const corps = '{"a":1}';
  const t = String(Math.floor(Date.now() / 1000));
  const sig = await signer(CLE, "m1", t, corps);
  const entetes = (s: string, ts = t) => new Headers({ "webhook-id": "m1", "webhook-timestamp": ts, "webhook-signature": `v1,${s}` });
  assert(await verifierAppelSigne(`autre|${SECRET}`, entetes(sig), corps));
  assert(!(await verifierAppelSigne(SECRET, entetes(sig), '{"a":2}')));
  assert(!(await verifierAppelSigne(SECRET, entetes(sig, String(Number(t) - 600)), corps)));
});

Deno.test("code envoyé par Orange au numéro guinéen, réponse 200 sans corps", async () => {
  configurer();
  const orange = fauxOrange();
  try {
    const r = await traiter(await appel({ user: { id: "u1", phone: "224620123456" }, sms: { otp: "482913" } }));
    assertEquals(r.status, 200);
    assertEquals(await r.text(), "");
    const demande = orange.envois[0].outboundSMSMessageRequest as Record<string, unknown>;
    assertEquals(demande.address, "tel:+224620123456");
    assertEquals((demande.outboundSMSTextMessage as Record<string, string>).message, texteCode("482913"));
    assert(texteCode("482913").length <= 160, "un seul SMS");
  } finally {
    orange.restaurer();
  }
});

Deno.test("appel non signé refusé sans rien envoyer", async () => {
  configurer();
  const orange = fauxOrange();
  try {
    const r = await traiter(await appel({ user: { phone: "224620123456" }, sms: { otp: "111111" } }, { secret: new Uint8Array(32) }));
    assertEquals(r.status, 401);
    assertEquals(orange.envois.length, 0);
  } finally {
    orange.restaurer();
  }
});

Deno.test("numéro hors Guinée : message clair, pas d'envoi", async () => {
  configurer();
  const orange = fauxOrange();
  try {
    const r = await traiter(await appel({ user: { phone: "+33612345678" }, sms: { otp: "111111" } }));
    assertEquals(r.status, 400);
    const corps = await r.json() as { error: { message: string } };
    assert(corps.error.message.includes("adresse e-mail"));
    assertEquals(orange.envois.length, 0);
  } finally {
    orange.restaurer();
  }
});

Deno.test("Orange indisponible : refus temporaire lisible (503)", async () => {
  configurer();
  const orange = fauxOrange(503);
  try {
    const r = await traiter(await appel({ user: { phone: "224620123456" }, sms: { otp: "111111" } }));
    assertEquals(r.status, 503);
  } finally {
    orange.restaurer();
  }
});
