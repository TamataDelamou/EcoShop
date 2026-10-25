// ============================================================================
// EcoShop — lien « Ce n'est pas moi » du courriel « Nouvel appareil » (REG-22 A)
//
// GET  /pas_moi?j=<jeton>  → page de confirmation (aucun effet) : les
//      messageries ouvrent souvent les liens d'un courriel pour les analyser ;
//      un simple GET ne doit donc jamais fermer une session.
// POST /pas_moi (j=<jeton>) → ferme la connexion signalée et bloque les
//      nouveaux appareils (RPC pas_moi_par_jeton, réservée à service_role).
//
// Publique (verify_jwt = false) : le jeton à usage unique, valable 7 jours,
// est la seule preuve ; seule son empreinte est en base.
// ============================================================================

import { clientService } from "../_shared/supabase_client.ts";

const ENTETES = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'",
};

function echapper(v: string): string {
  return v.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

export function page(titre: string, corps: string, statut = 200): Response {
  const html = `<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${echapper(titre)} — EcoShop</title>
<style>body{font-family:system-ui,sans-serif;margin:0;background:#f5f7f6;color:#1F2933}
main{max-width:480px;margin:40px auto;padding:24px;background:#fff;border-radius:12px}
h1{font-size:22px;color:#0B6E4F}p{line-height:1.5}button{background:#B42318;color:#fff;border:0;
border-radius:8px;padding:14px 20px;font-size:16px;width:100%}</style></head>
<body><main><h1>${echapper(titre)}</h1>${corps}</main></body></html>`;
  return new Response(html, { status: statut, headers: ENTETES });
}

export function jetonValide(j: string | null): j is string {
  return !!j && /^[0-9a-f]{48}$/.test(j);
}

export async function traiter(req: Request, appelerRpc: (jeton: string) => Promise<string>): Promise<Response> {
  const url = new URL(req.url);
  if (req.method === "GET") {
    const j = url.searchParams.get("j");
    if (!jetonValide(j)) {
      return page("Lien invalide", "<p>Ce lien n'est pas valable. Ouvrez EcoShop sur votre téléphone habituel.</p>", 400);
    }
    return page("Ce n'est pas vous ?",
      `<p>Un nouvel appareil s'est connecté à votre compte EcoShop. Si ce n'est pas vous, confirmez ci-dessous :
cette connexion sera fermée et aucun nouvel appareil ne pourra entrer tant que vous n'aurez pas changé le code
de votre compte depuis votre téléphone habituel.</p>
<form method="post"><input type="hidden" name="j" value="${echapper(j)}">
<button type="submit">Fermer cette connexion</button></form>
<p>Si c'est bien vous, fermez simplement cette page.</p>`);
  }
  if (req.method === "POST") {
    const form = await req.formData().catch(() => null);
    const j = form?.get("j")?.toString() ?? null;
    if (!jetonValide(j)) {
      return page("Lien invalide", "<p>Ce lien n'est pas valable.</p>", 400);
    }
    const resultat = await appelerRpc(j);
    switch (resultat) {
      case "fait":
        return page("C'est noté",
          "<p>La connexion est fermée et les nouveaux appareils sont bloqués. Changez maintenant le code de votre compte depuis votre téléphone habituel (Mon profil › Sécurité).</p>");
      case "deja_fait":
        return page("Déjà pris en compte", "<p>Ce signalement a déjà été enregistré.</p>");
      default:
        return page("Lien expiré", "<p>Ce lien n'est plus valable (7 jours, usage unique). Ouvrez EcoShop sur votre téléphone habituel et changez le code de votre compte.</p>", 410);
    }
  }
  return new Response("Méthode non permise", { status: 405 });
}

if (import.meta.main) {
  Deno.serve((req) =>
    traiter(req, async (jeton) => {
      const { data, error } = await clientService().rpc("pas_moi_par_jeton", { p_jeton: jeton });
      if (error) {
        console.error("pas_moi_par_jeton", error.message);
        return "invalide";
      }
      return String(data);
    })
  );
}
