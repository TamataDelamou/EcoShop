// EcoShop — Edge Function « envoyer_sms_auth » : crochet « Send SMS » de
// Supabase Auth, codes de connexion par Orange SMS. Logique et
// documentation : ../_shared/sms_auth.ts.
import { traiter } from "../_shared/sms_auth.ts";

Deno.serve(traiter);
