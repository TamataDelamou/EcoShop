// Tests : page « Ce n'est pas moi » (REG-22 A).
// Exécution : deno test --allow-env supabase/functions/pas_moi/pas_moi_test.ts
import { ok as assert, strictEqual as assertEquals } from "node:assert/strict";
import { traiter } from "./index.ts";
import { rendreCourriel } from "../_shared/modeles_courriel.ts";

const JETON = "a".repeat(48);

Deno.test("GET : page de confirmation, aucun appel au serveur (analyseurs de liens)", async () => {
  let appels = 0;
  const r = await traiter(new Request(`https://x/pas_moi?j=${JETON}`), () => { appels++; return Promise.resolve("fait"); });
  assertEquals(r.status, 200);
  assertEquals(appels, 0);
  const html = await r.text();
  assert(html.includes('method="post"'));
  assert(html.includes("Fermer cette connexion"));
});

Deno.test("POST : la connexion est fermée", async () => {
  let recu = "";
  const corps = new URLSearchParams({ j: JETON });
  const r = await traiter(new Request("https://x/pas_moi", { method: "POST", body: corps }),
    (j) => { recu = j; return Promise.resolve("fait"); });
  assertEquals(recu, JETON);
  assertEquals(r.status, 200);
  assert((await r.text()).includes("C'est noté"));
});

Deno.test("jeton mal formé ou expiré : refusé sans appel", async () => {
  let appels = 0;
  const appel = () => { appels++; return Promise.resolve("invalide"); };
  assertEquals((await traiter(new Request("https://x/pas_moi?j=<script>"), appel)).status, 400);
  const expire = await traiter(new Request("https://x/pas_moi", { method: "POST", body: new URLSearchParams({ j: JETON }) }), appel);
  assertEquals(expire.status, 410);
  assertEquals(appels, 1);
});

Deno.test("courriels du code du compte : rendus, sans code ni lien de connexion", () => {
  const ctx = { urlApplication: "https://app", adresseSupport: "contact@gsg.org", urlFonctions: "https://projet/functions/v1" };
  const nouvel = rendreCourriel("code_compte_nouvel_appareil", { prenom: "Awa", modele: "Tecno Spark 10", jeton_pas_moi: JETON }, ctx);
  assert(nouvel.html.includes(`https://projet/functions/v1/pas_moi?j=${JETON}`));
  assert(nouvel.texte.includes("Tecno Spark 10"));
  for (const m of ["code_compte_appareils_bloques", "code_compte_change", "code_compte_recuperation_lancee",
                   "code_compte_recuperation_terminee"]) {
    const r = rendreCourriel(m, { prenom: "Awa", motif: "pas_moi", fin: "27/10/2026 à 14 h 05" }, ctx);
    assert(r.sujet.length > 0 && r.texte.includes("Awa"), m);
    assert(!r.html.includes("<img"), m);
  }
  const sansUrl = rendreCourriel("code_compte_nouvel_appareil", { jeton_pas_moi: JETON }, { urlApplication: "a", adresseSupport: "b" });
  assert(!sansUrl.html.includes("pas_moi?j="), "sans adresse des fonctions : pas de lien cassé");
});
