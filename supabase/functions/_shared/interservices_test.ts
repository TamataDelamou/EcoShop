// Tests unitaires du module inter-services (KER-MUT K3).
// Exécution : deno test --allow-env supabase/functions/_shared/interservices_test.ts
// node:assert plutôt que jsr:@std/assert : aucune dépendance au registre JSR.
import { ok as assert, rejects, strictEqual as assertEquals } from "node:assert/strict";
import { exportJWK, generateKeyPair, type KeyLike, SignJWT } from "npm:jose@5.9.6";
import {
  AUDIENCE_KERNEL,
  chargerClePrivee,
  cleIdempotenceLot,
  egaliteTempsConstant,
  ErreurInterServices,
  jeuDeClesPublic,
  signerJetonSortant,
  verifierJetonEntrant,
} from "./interservices.ts";

const EMETTEUR_KERNEL = "https://kernel.gsg.test";

async function paireKernel() {
  return await generateKeyPair("ES256", { extractable: true });
}

async function jetonKernel(
  privee: KeyLike,
  surcharges: { aud?: string; scope?: string; duree?: number; iss?: string; alg?: string } = {},
) {
  const maintenant = Math.floor(Date.now() / 1000);
  return await new SignJWT({ scope: surcharges.scope ?? "ecoshop:lecture" })
    .setProtectedHeader({ alg: "ES256" })
    .setIssuer(surcharges.iss ?? EMETTEUR_KERNEL)
    .setAudience(surcharges.aud ?? "ecoshop")
    .setIssuedAt(maintenant)
    .setExpirationTime(maintenant + (surcharges.duree ?? 120))
    .setJti(crypto.randomUUID())
    .sign(privee);
}

async function codeErreur(promesse: Promise<unknown>): Promise<string> {
  try {
    await promesse;
  } catch (e) {
    if (e instanceof ErreurInterServices) return e.code;
    throw e;
  }
  throw new Error("aucune erreur levée");
}

Deno.test("jeton entrant valide accepté", async () => {
  const { publicKey, privateKey } = await paireKernel();
  const payload = await verifierJetonEntrant(await jetonKernel(privateKey), publicKey, {
    emetteur: EMETTEUR_KERNEL,
  });
  assertEquals(payload.iss, EMETTEUR_KERNEL);
});

Deno.test("jeton signé par une autre clé refusé", async () => {
  const kernel = await paireKernel();
  const intrus = await paireKernel();
  assertEquals(
    await codeErreur(verifierJetonEntrant(await jetonKernel(intrus.privateKey), kernel.publicKey, {
      emetteur: EMETTEUR_KERNEL,
    })),
    "JETON_INVALIDE",
  );
});

Deno.test("mauvaise audience refusée", async () => {
  const { publicKey, privateKey } = await paireKernel();
  assertEquals(
    await codeErreur(verifierJetonEntrant(await jetonKernel(privateKey, { aud: "autre-produit" }), publicKey, {
      emetteur: EMETTEUR_KERNEL,
    })),
    "JETON_INVALIDE",
  );
});

Deno.test("mauvais émetteur refusé", async () => {
  const { publicKey, privateKey } = await paireKernel();
  assertEquals(
    await codeErreur(verifierJetonEntrant(await jetonKernel(privateKey, { iss: "https://pirate" }), publicKey, {
      emetteur: EMETTEUR_KERNEL,
    })),
    "JETON_INVALIDE",
  );
});

Deno.test("jeton expiré refusé", async () => {
  const { publicKey, privateKey } = await paireKernel();
  const jeton = await jetonKernel(privateKey, { duree: 60 });
  assertEquals(
    await codeErreur(verifierJetonEntrant(jeton, publicKey, {
      emetteur: EMETTEUR_KERNEL,
      maintenant: new Date(Date.now() + 3600_000),
    })),
    "JETON_INVALIDE",
  );
});

Deno.test("jeton à durée de vie trop longue refusé", async () => {
  const { publicKey, privateKey } = await paireKernel();
  assertEquals(
    await codeErreur(verifierJetonEntrant(await jetonKernel(privateKey, { duree: 86400 }), publicKey, {
      emetteur: EMETTEUR_KERNEL,
    })),
    "JETON_TROP_LONG",
  );
});

Deno.test("scope absent refusé", async () => {
  const { publicKey, privateKey } = await paireKernel();
  assertEquals(
    await codeErreur(verifierJetonEntrant(await jetonKernel(privateKey, { scope: "autre:lecture" }), publicKey, {
      emetteur: EMETTEUR_KERNEL,
    })),
    "SCOPE_INSUFFISANT",
  );
});

Deno.test("jeton non signé (alg none) refusé", async () => {
  const { publicKey } = await paireKernel();
  const b64 = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  const maintenant = Math.floor(Date.now() / 1000);
  const jeton = `${b64({ alg: "none" })}.${
    b64({ iss: EMETTEUR_KERNEL, aud: "ecoshop", iat: maintenant, exp: maintenant + 60, jti: "x", scope: "ecoshop:lecture" })
  }.`;
  assertEquals(
    await codeErreur(verifierJetonEntrant(jeton, publicKey, { emetteur: EMETTEUR_KERNEL })),
    "JETON_INVALIDE",
  );
});

Deno.test("aller-retour sortant : signé par EcoShop, vérifiable avec le JWKS publié", async () => {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  const jwk = { ...(await exportJWK(privateKey)), kid: "ecoshop-2026-10" };
  const cle = await chargerClePrivee(JSON.stringify(jwk));

  const jwks = jeuDeClesPublic(cle);
  assertEquals(jwks.keys.length, 1);
  assert(!("d" in jwks.keys[0]), "la clé publiée ne doit jamais contenir la partie privée");

  const { importJWK, jwtVerify } = await import("npm:jose@5.9.6");
  const jeton = await signerJetonSortant(cle);
  const { payload, protectedHeader } = await jwtVerify(jeton, await importJWK(jwks.keys[0], "ES256"), {
    issuer: "ecoshop",
    audience: AUDIENCE_KERNEL,
  });
  assertEquals(protectedHeader.kid, "ecoshop-2026-10");
  assertEquals(payload.scope, "kernel:ingestion");
  assert((payload.exp as number) - (payload.iat as number) <= 60);
});

Deno.test("clé privée invalide ou sans kid refusée", async () => {
  await rejects(() => chargerClePrivee("pas du json"), ErreurInterServices);
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  const sansKid = await exportJWK(privateKey);
  assertEquals(await codeErreur(chargerClePrivee(JSON.stringify(sansKid))), "CLE_PRIVEE_SANS_KID");
  const { d: _d, ...publique } = sansKid;
  assertEquals(await codeErreur(chargerClePrivee(JSON.stringify({ ...publique, kid: "k" }))), "CLE_PRIVEE_INVALIDE");
});

Deno.test("clé d'idempotence déterministe et distincte par flux", async () => {
  const a = await cleIdempotenceLot("audit", "1", "9");
  assertEquals(a, await cleIdempotenceLot("audit", "1", "9"));
  assert(a !== await cleIdempotenceLot("metriques", "1", "9"));
  assertEquals(a.length, 64);
});

Deno.test("comparaison à temps constant", () => {
  assert(egaliteTempsConstant("secret", "secret"));
  assert(!egaliteTempsConstant("secret", "secreT"));
  assert(!egaliteTempsConstant("secret", "secret2"));
  assert(!egaliteTempsConstant("", "x"));
});
