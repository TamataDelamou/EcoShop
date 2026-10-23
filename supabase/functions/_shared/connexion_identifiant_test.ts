// Tests de la connexion avec l'identifiant EcoShop (REG-18 D).
// Exécution : deno test supabase/functions/_shared/connexion_identifiant_test.ts
import { deepStrictEqual as assertEquals, ok as assert } from "node:assert/strict";
import { caractereControle, type Dependances, masquerAdresse, normaliserIdentifiant, traiter } from "./connexion_identifiant.ts";

const COMPTE = "EC-7K4M-2QM"; // contrôle calculé à la main : 7K4M2Q -> M

function dependances(options: { verifie?: boolean } = {}) {
  const essais = new Map<string, number>();
  const envois: string[] = [];
  const attentes: number[] = [];
  const enCours: Promise<unknown>[] = [];
  const d: Dependances = {
    emailPour: async (id) => (id === COMPTE ? "awa.bah@gmail.com" : null),
    noterEssai: async (cle, nature, _minutes, max) => {
      const k = `${cle}|${nature}`;
      const n = essais.get(k) ?? 0;
      if (n >= max) return false;
      essais.set(k, n + 1);
      return true;
    },
    envoyerCode: async (email) => {
      envois.push(email);
    },
    verifierCode: async (_email, code) => (options.verifie !== false && code === "123456" ? { access_token: "a", refresh_token: "r" } : null),
    cleMasque: "cle-test",
    attendre: async (ms) => {
      attentes.push(ms);
    },
    enArrierePlan: (tache) => {
      enCours.push(tache);
    },
    maintenant: () => 0,
  };
  return { d, envois, attentes, enCours };
}

Deno.test("caractère de contrôle : même calcul que la base", () => {
  assertEquals(caractereControle("7K4M2Q"), "M");
});

Deno.test("normalisation : minuscules, espaces, O/I/L ; contrôle faux refusé", () => {
  assertEquals(normaliserIdentifiant("ec 7k4m 2qm"), COMPTE);
  assertEquals(normaliserIdentifiant("EC-7K4M-2Q9"), null);
  assertEquals(normaliserIdentifiant("awa@gmail.com"), null);
});

Deno.test("adresse masquée", () => {
  assertEquals(masquerAdresse("awa.bah@gmail.com"), "a•••@gmail.com");
});

Deno.test("envoi : identifiant existant -> code envoyé, adresse masquée", async () => {
  const { d, envois } = dependances();
  const r = await traiter({ action: "envoyer", identifiant: "ec-7k4m-2qm" }, "1.2.3.4", d);
  assertEquals(r.statut, 200);
  assertEquals(r.corps.adresseMasquee, "a•••@gmail.com");
  assertEquals(envois, ["awa.bah@gmail.com"]);
});

Deno.test("envoi : identifiant inconnu -> même forme de réponse, aucun envoi, adresse stable", async () => {
  const { d, envois, attentes } = dependances();
  const inconnu = `EC-ABCD-EF${caractereControle("ABCDEF")}`;
  const r1 = await traiter({ action: "envoyer", identifiant: inconnu }, "1.2.3.4", d);
  const r2 = await traiter({ action: "envoyer", identifiant: inconnu }, "1.2.3.4", d);
  assertEquals(r1.statut, 200);
  assertEquals(Object.keys(r1.corps).sort(), ["adresseMasquee", "success"]);
  assert(/^[a-z]•••@[a-z.]+$/.test(String(r1.corps.adresseMasquee)));
  assertEquals(r1.corps.adresseMasquee, r2.corps.adresseMasquee);
  assertEquals(envois, []);
  assert(attentes.length === 2, "délai minimum appliqué aussi aux identifiants inconnus");
});

Deno.test("envoi : refus de Supabase (limite) -> même réponse qu'un envoi réussi", async () => {
  const { d } = dependances();
  d.envoyerCode = async () => {
    throw new Error("otp 429");
  };
  const r = await traiter({ action: "envoyer", identifiant: COMPTE }, "1.2.3.4", d);
  assertEquals(r.statut, 200);
  assertEquals(r.corps.adresseMasquee, "a•••@gmail.com");
});

Deno.test("envoi : 5 par identifiant et par heure, existant ou non", async () => {
  const { d } = dependances();
  for (let i = 0; i < 5; i++) {
    assertEquals((await traiter({ action: "envoyer", identifiant: COMPTE }, `ip${i}`, d)).statut, 200);
  }
  assertEquals((await traiter({ action: "envoyer", identifiant: COMPTE }, "ip9", d)).corps.error, "TROP_DE_TENTATIVES");
});

Deno.test("vérification : bon code -> session ; mauvais code ou identifiant inconnu -> même erreur", async () => {
  const { d } = dependances();
  const bon = await traiter({ action: "verifier", identifiant: COMPTE, code: "123456" }, "1.2.3.4", d);
  assertEquals(bon.statut, 200);
  assertEquals((bon.corps.session as Record<string, unknown>).access_token, "a");
  const faux = await traiter({ action: "verifier", identifiant: COMPTE, code: "000000" }, "1.2.3.4", d);
  const inconnu = await traiter({ action: "verifier", identifiant: `EC-ABCD-EF${caractereControle("ABCDEF")}`, code: "123456" }, "1.2.3.4", d);
  assertEquals(faux.corps, inconnu.corps);
  assertEquals(faux.corps.error, "OTP_EXPIRED");
});

Deno.test("vérification : 10 essais par identifiant en 15 min", async () => {
  const { d } = dependances();
  for (let i = 0; i < 10; i++) {
    await traiter({ action: "verifier", identifiant: COMPTE, code: "000000" }, `ip${i}`, d);
  }
  const r = await traiter({ action: "verifier", identifiant: COMPTE, code: "123456" }, "ip99", d);
  assertEquals(r.corps.error, "TROP_DE_TENTATIVES");
});

Deno.test("saisie qui n'est pas un identifiant : refusée sans rien interroger", async () => {
  const { d, envois } = dependances();
  const r = await traiter({ action: "envoyer", identifiant: "EC-7K4M-2Q9" }, "1.2.3.4", d);
  assertEquals(r.corps.error, "IDENTIFIANT_INVALIDE");
  assertEquals(envois, []);
});
