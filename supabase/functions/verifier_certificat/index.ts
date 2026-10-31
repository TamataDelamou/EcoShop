// ============================================================================
// EcoShop — vérification publique d'un certificat de maîtrise (REG-38 E2a,
// cahier 23.3)
//
// GET /verifier_certificat            → formulaire (saisir le code)
// GET /verifier_certificat?code=GSG-… → résultat : authentique, révoqué ou
//                                        inconnu
//
// Publique (verify_jwt = false) : un tiers (école, employeur, organisateur
// d'un concours) vérifie sans créer de compte. Page HTML sans script ; ne
// montre que ce qui est écrit sur le certificat (prénom et initiale).
// ============================================================================

import { clientService } from "../_shared/supabase_client.ts";

const ENTETES = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'",
};

export function echapper(v: string): string {
  return v.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

export function codeValide(c: string | null): c is string {
  return !!c && /^GSG-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}$/.test(c.trim().toUpperCase());
}

function page(titre: string, corps: string, statut = 200): Response {
  const html = `<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${echapper(titre)} — EcoShop</title>
<style>body{font-family:system-ui,sans-serif;margin:0;background:#f5f7f6;color:#1F2933}
main{max-width:520px;margin:40px auto;padding:24px;background:#fff;border-radius:12px}
h1{font-size:22px;color:#0B6E4F}p,dd{line-height:1.5}dt{font-weight:700;margin-top:8px}dd{margin:0}
input{font-size:18px;padding:12px;width:100%;box-sizing:border-box;border:1px solid #9AA5B1;border-radius:8px;text-transform:uppercase}
button{margin-top:12px;background:#0B6E4F;color:#fff;border:0;border-radius:8px;padding:14px 20px;font-size:16px;width:100%}
.ko{color:#B42318}</style></head>
<body><main><h1>${echapper(titre)}</h1>${corps}
<p style="font-size:13px;color:#52606D">Certificat d'entraînement délivré sur EcoShop (Global Service Groupe) : il valorise un parcours de révision ou un concours, ce n'est pas un diplôme ni un résultat officiel d'examen.</p>
</main></body></html>`;
  return new Response(html, { status: statut, headers: ENTETES });
}

const FORMULAIRE = `<p>Saisissez le code inscrit sur le certificat.</p>
<form method="get"><input name="code" placeholder="GSG-XXXX-XXXX-XXXX" required maxlength="18" autocomplete="off">
<button type="submit">Vérifier</button></form>`;

export interface Resultat {
  valide: boolean;
  inconnu?: boolean;
  revoque?: boolean;
  code?: string;
  titre?: string;
  titulaire?: string;
  mention?: string;
  reussite?: number;
  rang?: number | null;
  participants?: number | null;
  delivre_par?: string;
  delivre_le?: string;
}

export function rendre(r: Resultat): Response {
  if (r.inconnu) {
    return page("Certificat introuvable", `<p class="ko">Aucun certificat ne porte ce code.</p>${FORMULAIRE}`, 404);
  }
  const date = r.delivre_le ? new Date(r.delivre_le).toLocaleDateString("fr-FR", { timeZone: "UTC" }) : "";
  const details = `<dl>
<dt>Titulaire</dt><dd>${echapper(r.titulaire ?? "")}</dd>
<dt>Concours</dt><dd>${echapper(r.titre ?? "")}</dd>
<dt>Mention</dt><dd>${echapper(r.mention ?? "")} (${r.reussite ?? 0} % de réussite)</dd>
${r.rang ? `<dt>Rang</dt><dd>${r.rang}${r.participants ? ` sur ${r.participants}` : ""}</dd>` : ""}
<dt>Délivré par</dt><dd>${echapper(r.delivre_par ?? "")}, le ${echapper(date)}</dd>
<dt>Code</dt><dd>${echapper(r.code ?? "")}</dd></dl>`;
  return r.revoque
    ? page("Certificat révoqué", `<p class="ko">Ce certificat a été annulé par son émetteur.</p>${details}`, 410)
    : page("Certificat authentique", details);
}

export async function traiter(req: Request, verifier: (code: string) => Promise<Resultat | null>): Promise<Response> {
  if (req.method !== "GET") return new Response("Méthode non permise", { status: 405 });
  const code = new URL(req.url).searchParams.get("code");
  if (code === null || code.trim() === "") return page("Vérifier un certificat", FORMULAIRE);
  if (!codeValide(code)) return page("Code invalide", `<p class="ko">Ce code n'a pas le bon format.</p>${FORMULAIRE}`, 400);
  const r = await verifier(code.trim().toUpperCase());
  if (!r) return page("Service indisponible", "<p>Réessayez dans un instant.</p>", 503);
  return rendre(r);
}

if (import.meta.main) {
  Deno.serve((req) =>
    traiter(req, async (code) => {
      const { data, error } = await clientService().rpc("verifier_certificat", { p_code: code });
      if (error) {
        console.error(JSON.stringify({ fn: "verifier_certificat", message: error.message }));
        return null;
      }
      return data as Resultat;
    })
  );
}
