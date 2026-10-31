// Exécution : deno test --allow-env supabase/functions/verifier_certificat/verifier_certificat_test.ts
import { ok as assert, strictEqual as assertEquals } from "node:assert/strict";
import { codeValide, rendre, traiter } from "./index.ts";

Deno.test("format du code", () => {
  assertEquals(codeValide("GSG-AB2C-DE3F-GH4J"), true);
  assertEquals(codeValide(" gsg-ab2c-de3f-gh4j "), true);
  assertEquals(codeValide("GSG-0000-1111-OOOO"), false); // 0, 1, O, I exclus
  assertEquals(codeValide("<script>"), false);
});

Deno.test("certificat authentique : prénom et initiale seulement", async () => {
  const r = rendre({
    valide: true, code: "GSG-AB2C-DE3F-GH4J", titre: "Olympiade", titulaire: "Awa B.", mention: "Excellence",
    reussite: 95, rang: 1, participants: 40, delivre_par: "Global Service Groupe", delivre_le: "2026-11-02T10:00:00Z",
  });
  assertEquals(r.status, 200);
  const html = await r.text();
  assert((html).includes("Certificat authentique"));
  assert((html).includes("Awa B."));
  assert((html).includes("1 sur 40"));
});

Deno.test("inconnu, révoqué, formulaire, échappement", async () => {
  assertEquals(rendre({ valide: false, inconnu: true }).status, 404);
  assertEquals(rendre({ valide: false, revoque: true, titulaire: "A" }).status, 410);
  const vide = await traiter(new Request("https://x/verifier_certificat"), () => Promise.resolve(null));
  assert((await vide.text()).includes("<form"));
  const injection = rendre({ valide: true, titulaire: "<b>x</b>", titre: "t" });
  assert((await injection.text()).includes("&lt;b&gt;x&lt;/b&gt;"));
});
