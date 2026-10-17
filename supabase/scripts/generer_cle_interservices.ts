// Génère la paire de clés inter-services EcoShop ↔ Kernel GSG (KER-MUT K3).
//
//   deno run supabase/scripts/generer_cle_interservices.ts
//
// Affiche :
//   1. la clé PRIVÉE (JWK) à placer dans le secret Supabase
//      KERNEL_INTERSERVICES_CLE_PRIVEE_JWK — ne jamais la committer ;
//   2. la clé PUBLIQUE, pour information (elle est de toute façon servie par
//      /kernel-control-plane/jwks.json).
import { exportJWK, generateKeyPair } from "npm:jose@5.9.6";

const { publicKey, privateKey } = await generateKeyPair("ES256", { extractable: true });
const kid = `ecoshop-${new Date().toISOString().slice(0, 10)}`;
const prive = { ...(await exportJWK(privateKey)), kid, alg: "ES256", use: "sig" };
const publique = { ...(await exportJWK(publicKey)), kid, alg: "ES256", use: "sig" };

console.log("# Secret KERNEL_INTERSERVICES_CLE_PRIVEE_JWK (confidentiel) :");
console.log(JSON.stringify(prive));
console.log("\n# Clé publique (diffusable) :");
console.log(JSON.stringify(publique));
