-- ============================================================================
-- EcoShop — Chantier Facturation/Quota IA — Étape (b) : brique CinetPay
-- générique (initiation -> recalcul serveur -> webhook seule autorité de
-- crédit -> verrou d'idempotence -> dispatch entitlement).
--
-- Patron fonctionnel de référence : ecoshop_flutter/CINETPAY.md (Firebase).
-- Portée ici avec TROIS déviations assumées, actées par le porteur de
-- projet avant écriture (même discipline que la déviation annees_scolaires
-- de l'étape a) :
--
--   1. Secret de vérification de signature — PAS dans parametres_globaux
--      (cette table est documentée "lecture publique" dans core_schema :
--      y stocker un secret le exposerait à tout compte authentifié). Nouvelle
--      table public.parametres_secrets_integration, RLS activée SANS AUCUNE
--      policy (deny-all pour tout rôle client, y compris en lecture -- seul
--      service_role, qui contourne RLS, y accède). Trouvaille actée par le
--      porteur de projet comme la bonne correction, pas une lacune du
--      cadrage initial.
--
--   2. Idempotence par flip atomique Postgres (UPDATE ... WHERE statut =
--      'initie' sous verrou SELECT ... FOR UPDATE) plutôt que le document-
--      verrou séparé de CINETPAY.md (nécessaire côté Firestore, qui n'a pas
--      de vraies transactions SQL). Amélioration assumée, actée par le
--      porteur de projet.
--
--   3. Pas de garde composite (est_admin_gsg() OR est_appel_service()) pour
--      partager la logique de crédit entre la RPC admin manuelle et le
--      webhook automatique -- risque d'angle mort déjà identifié ailleurs
--      dans ce projet. La logique de calcul/upsert est extraite dans des
--      fonctions privées SANS vérification d'autorisation propre (revoke
--      all from public, anon, authenticated -- jamais grantées à un rôle
--      client), appelées CHACUNE après sa propre garde simple par
--      enregistrer_paiement_licence_pro (est_admin_gsg()) et par
--      traiter_webhook_cinetpay (GRANT réservé à service_role -- PAS
--      est_appel_service(), voir point 8 : cette fonction est elle-même
--      SECURITY DEFINER, current_user y vaut déjà son propriétaire, donc
--      est_appel_service() y répondrait toujours vrai quel que soit
--      l'appelant réel -- constaté empiriquement en testant cette
--      migration, corrigé avant push).
--
-- Correction supplémentaire actée : la branche licence_pro_etablissement de
-- traiter_webhook_cinetpay recompte l'effectif réel EN DIRECT au moment du
-- crédit (compter_effectif_actif), jamais la valeur effectif_a_l_initiation
-- simplement portée dans contexte -- un webhook peut arriver après un délai,
-- cette valeur peut être périmée. Même règle que le recompte d'effectif en
-- direct déjà annoncé (hors périmètre) dans la migration de l'étape (a),
-- appliquée ici de bout en bout pour de vrai.
--
-- Type d'objet payé limité aux DEUX flux réellement branchés aujourd'hui
-- (licence_pro_etablissement, frais_ia_admin_etablissement) -- même
-- discipline que l'étape (a). abonnement_premium_eleve (étape c) et
-- scolarite (chapitre 17) s'ajouteront plus tard par ALTER TYPE ... ADD
-- VALUE + une nouvelle branche dans les CASE ci-dessous, jamais une
-- réécriture des Edge Functions ou de la table.
--
-- Hors périmètre explicite de cette étape (pas construit ici) :
--   • Portefeuille établissement / frais de payout CinetPay -- pertinent
--     seulement pour le chapitre 17 (scolarité), qui n'est pas câblé.
--   • public.paiements / type_fournisseur_paiement('cinetpay') de M13
--     (marketplace) -- sous-comptes CinetPay PAR établissement, modèle
--     bénéficiaire différent (CINETPAY.md §5 documente déjà cette
--     séparation : voie 'commande_marketplace' entièrement à part). Cette
--     brique-ci sert les paiements collectés PAR GSG directement.
--   • Point ouvert noté pour l'étape (c) : la policy select de
--     transactions_cinetpay devra gagner "or initiateur_id = auth.uid()"
--     quand des transactions individuelles apparaîtront -- pas anticipé
--     ici.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Type fermé, extensible par ALTER TYPE ... ADD VALUE plus tard (même
-- discipline que type_entitlement_etablissement, étape a).
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.type_objet_paye_cinetpay as enum (
    'licence_pro_etablissement',
    'frais_ia_admin_etablissement'
  );
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 1. Configuration NON PUBLIQUE — déviation 1 ci-dessus. RLS activée, aucune
-- policy créée : deny-all pour authenticated/anon, y compris en lecture.
-- Seul service_role (Edge Functions, contourne RLS) y accède.
-- ---------------------------------------------------------------------------
create table if not exists public.parametres_secrets_integration (
  cle text primary key,
  valeur jsonb not null,
  description text,
  updated_at timestamptz not null default now()
);

alter table public.parametres_secrets_integration enable row level security;

drop trigger if exists parametres_secrets_set_updated_at on public.parametres_secrets_integration;
create trigger parametres_secrets_set_updated_at
  before update on public.parametres_secrets_integration
  for each row execute function public.set_updated_at();

-- PLACEHOLDER — aucun identifiant CinetPay (test/sandbox) disponible à ce
-- jour. Tant que secret_verification_webhook est null,
-- traiter_webhook_cinetpay refuse tout webhook (CINETPAY_NON_CONFIGURE) --
-- prêt à recevoir les vrais identifiants sans changement de code.
insert into public.parametres_secrets_integration (cle, valeur, description) values (
  'cinetpay_config',
  '{"environnement": "test", "api_key": null, "site_id": null, "secret_verification_webhook": null, "notify_url": null}'::jsonb,
  'PLACEHOLDER -- à remplacer par le porteur de projet avant toute activation réelle. Table non exposée en lecture au client (voir migration 20260906001515).'
)
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Ledger générique de transaction CinetPay.
-- ---------------------------------------------------------------------------
create table if not exists public.transactions_cinetpay (
  id uuid primary key default gen_random_uuid(),
  type_objet_paye public.type_objet_paye_cinetpay not null,
  etablissement_id uuid references public.etablissements (id) on delete cascade,
  initiateur_id uuid not null references public.profiles (id),
  contexte jsonb not null default '{}'::jsonb,
  montant_attendu numeric(12, 2) not null check (montant_attendu >= 0),
  devise text not null default 'GNF',
  statut public.statut_paiement not null default 'initie',
  reference_cinetpay text,
  moyen_paiement text,
  montant_confirme numeric(12, 2),
  payload_webhook jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_transactions_cinetpay_etab on public.transactions_cinetpay (etablissement_id);

drop trigger if exists transactions_cinetpay_set_updated_at on public.transactions_cinetpay;
create trigger transactions_cinetpay_set_updated_at
  before update on public.transactions_cinetpay
  for each row execute function public.set_updated_at();

alter table public.transactions_cinetpay enable row level security;

-- Lecture : personnel de l'établissement concerné + admin GSG (même règle
-- que licence_pro/frais_ia_admin, étape a). Point noté pour l'étape (c),
-- pas construit ici : gagner "or initiateur_id = auth.uid()" quand des
-- transactions individuelles apparaîtront.
drop policy if exists "transactions_cinetpay_select" on public.transactions_cinetpay;
create policy "transactions_cinetpay_select" on public.transactions_cinetpay
  for select using (
    coalesce(public.est_personnel(etablissement_id), false) or coalesce(public.est_admin_gsg(), false)
  );

-- Écriture TOUJOURS refusée au client — seules les fonctions ci-dessous
-- (initier_transaction_cinetpay, finaliser_initiation_cinetpay,
-- traiter_webhook_cinetpay), toutes SECURITY DEFINER, écrivent ici.
drop policy if exists "transactions_cinetpay_no_direct_write" on public.transactions_cinetpay;
create policy "transactions_cinetpay_no_direct_write" on public.transactions_cinetpay
  for all using (false) with check (false);

-- ---------------------------------------------------------------------------
-- 3. Effectif réel, recompté EN DIRECT — source unique, jamais un champ
-- précalculé (même requête canonique que demarrer_analyse_risque_echec,
-- M16). Usage interne uniquement : exposer un comptage d'effectif d'un
-- établissement arbitraire à tout compte authentifié serait une fuite
-- mineure inter-établissements, sans justification puisque rien côté
-- client n'en a besoin aujourd'hui.
--
-- ⚠️ `revoke ... from public` seul est INSUFFISANT dans ce projet : les
-- privilèges par défaut de ce projet Supabase accordent EXECUTE à
-- `authenticated` à la création de la fonction (constaté empiriquement en
-- testant cette migration -- un premier essai avec seulement
-- "from public" laissait `authenticated` appeler ces fonctions
-- directement). `anon, authenticated` doivent être révoqués explicitement,
-- comme le fait déjà generer_alertes_decrochage (M7).
-- ---------------------------------------------------------------------------
create or replace function public.compter_effectif_actif(p_etablissement uuid, p_annee_scolaire uuid)
returns int
language sql
stable
set search_path = public
as $$
  select count(distinct i.fiche_eleve_id)::int
  from public.inscriptions i
  where i.etablissement_id = p_etablissement
    and i.annee_scolaire_id = p_annee_scolaire
    and i.statut = 'active'
    and i.deleted_at is null;
$$;

revoke all on function public.compter_effectif_actif(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Calcul/upsert privés — extraits de l'étape (a), partagés par la RPC
-- admin manuelle ET le webhook automatique, chacun après SA PROPRE garde
-- (déviation 3 ci-dessus : jamais un OR combiné). revoke all from public :
-- aucune vérification d'autorisation ici, ces fonctions ne sont JAMAIS
-- appelables directement par un client.
-- ---------------------------------------------------------------------------
create or replace function public.appliquer_paiement_licence_pro(
  p_etablissement uuid,
  p_annee_scolaire uuid,
  p_effectif int,
  p_montant numeric
)
returns public.etablissements_licence_pro
language plpgsql
set search_path = public
as $$
declare
  v_row public.etablissements_licence_pro;
  v_tranche_cible int;
begin
  if not exists (
    select 1 from public.annees_scolaires
    where id = p_annee_scolaire and etablissement_id = p_etablissement
  ) then
    raise exception 'ANNEE_SCOLAIRE_INCOHERENTE' using errcode = '23514';
  end if;

  if p_effectif is null or p_effectif < 0 then
    raise exception 'EFFECTIF_INVALIDE' using errcode = '22023';
  end if;

  if p_montant is null or p_montant < 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;

  v_tranche_cible := public.calculer_tranche_pro(p_effectif);

  insert into public.etablissements_licence_pro (
    etablissement_id, annee_scolaire_id, tranche_actuelle,
    montant_total_paye_periode, effectif_au_dernier_paiement, date_dernier_paiement
  )
  values (
    p_etablissement, p_annee_scolaire, v_tranche_cible,
    p_montant, p_effectif, now()
  )
  on conflict (etablissement_id, annee_scolaire_id) do update
    set tranche_actuelle = greatest(public.etablissements_licence_pro.tranche_actuelle, v_tranche_cible),
        montant_total_paye_periode = public.etablissements_licence_pro.montant_total_paye_periode + excluded.montant_total_paye_periode,
        effectif_au_dernier_paiement = excluded.effectif_au_dernier_paiement,
        date_dernier_paiement = excluded.date_dernier_paiement
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.appliquer_paiement_licence_pro(uuid, uuid, int, numeric) from public, anon, authenticated;

create or replace function public.appliquer_paiement_frais_ia_admin(
  p_etablissement uuid,
  p_annee_scolaire uuid,
  p_montant numeric
)
returns public.etablissements_frais_ia_admin
language plpgsql
set search_path = public
as $$
declare
  v_row public.etablissements_frais_ia_admin;
begin
  if not exists (
    select 1 from public.annees_scolaires
    where id = p_annee_scolaire and etablissement_id = p_etablissement
  ) then
    raise exception 'ANNEE_SCOLAIRE_INCOHERENTE' using errcode = '23514';
  end if;

  if p_montant is null or p_montant < 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;

  insert into public.etablissements_frais_ia_admin (
    etablissement_id, annee_scolaire_id, paye, montant_paye, date_paiement
  )
  values (p_etablissement, p_annee_scolaire, true, p_montant, now())
  on conflict (etablissement_id, annee_scolaire_id) do update
    set paye = true,
        montant_paye = excluded.montant_paye,
        date_paiement = excluded.date_paiement
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.appliquer_paiement_frais_ia_admin(uuid, uuid, numeric) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. RPC admin manuelle — réécrites pour appeler la logique partagée,
-- signature INCHANGÉE (aucun impact sur le test RLS 49 existant).
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_paiement_licence_pro(
  p_etablissement uuid,
  p_annee_scolaire uuid,
  p_effectif_constate int,
  p_montant numeric
)
returns public.etablissements_licence_pro
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ADMIN_GSG_REQUIS' using errcode = '42501';
  end if;

  return public.appliquer_paiement_licence_pro(p_etablissement, p_annee_scolaire, p_effectif_constate, p_montant);
end;
$$;

create or replace function public.enregistrer_paiement_frais_ia_admin(
  p_etablissement uuid,
  p_annee_scolaire uuid,
  p_montant numeric
)
returns public.etablissements_frais_ia_admin
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ADMIN_GSG_REQUIS' using errcode = '42501';
  end if;

  return public.appliquer_paiement_frais_ia_admin(p_etablissement, p_annee_scolaire, p_montant);
end;
$$;

grant execute on function public.enregistrer_paiement_licence_pro(uuid, uuid, int, numeric) to authenticated;
grant execute on function public.enregistrer_paiement_frais_ia_admin(uuid, uuid, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Initiation — authentifiée, recalcule le montant SERVEUR (jamais une
-- valeur du client). Même garde d'accès qu'entitlement_actif : personnel de
-- l'établissement concerné (c'est lui qui paie) ou admin GSG.
-- ---------------------------------------------------------------------------
create or replace function public.initier_transaction_cinetpay(
  p_type_objet_paye public.type_objet_paye_cinetpay,
  p_etablissement uuid,
  p_annee_scolaire uuid default null
)
returns public.transactions_cinetpay
language plpgsql
security definer
set search_path = public
as $$
declare
  v_annee uuid;
  v_effectif int;
  v_tranche int;
  v_deja_paye numeric;
  v_montant numeric;
  v_contexte jsonb;
  v_row public.transactions_cinetpay;
begin
  if not (coalesce(public.est_personnel(p_etablissement), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  v_annee := coalesce(
    p_annee_scolaire,
    (select id from public.annees_scolaires where etablissement_id = p_etablissement and courante)
  );

  if v_annee is null or not exists (
    select 1 from public.annees_scolaires where id = v_annee and etablissement_id = p_etablissement
  ) then
    raise exception 'ANNEE_SCOLAIRE_INCOHERENTE' using errcode = '23514';
  end if;

  case p_type_objet_paye
    when 'licence_pro_etablissement' then
      v_effectif := public.compter_effectif_actif(p_etablissement, v_annee);
      v_tranche := public.calculer_tranche_pro(v_effectif);

      select montant_total_paye_periode into v_deja_paye
      from public.etablissements_licence_pro
      where etablissement_id = p_etablissement and annee_scolaire_id = v_annee;

      v_montant := greatest(public.calculer_montant_cumule_pro(v_tranche) - coalesce(v_deja_paye, 0), 0);

      if v_montant <= 0 then
        raise exception 'AUCUN_MONTANT_DU' using errcode = '22023';
      end if;

      v_contexte := jsonb_build_object('annee_scolaire_id', v_annee, 'effectif_a_l_initiation', v_effectif);

    when 'frais_ia_admin_etablissement' then
      if coalesce((
        select paye from public.etablissements_frais_ia_admin
        where etablissement_id = p_etablissement and annee_scolaire_id = v_annee
      ), false) then
        raise exception 'DEJA_PAYE' using errcode = '22023';
      end if;

      select (valeur->>'valeur')::numeric into v_montant
      from public.parametres_globaux where cle = 'tarif_frais_ia_admin_annuel';

      v_contexte := jsonb_build_object('annee_scolaire_id', v_annee);

    else
      raise exception 'TYPE_NON_SUPPORTE' using errcode = '0A000';
  end case;

  insert into public.transactions_cinetpay (
    type_objet_paye, etablissement_id, initiateur_id, contexte, montant_attendu
  )
  values (
    p_type_objet_paye, p_etablissement, auth.uid(), v_contexte, v_montant
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.initier_transaction_cinetpay(public.type_objet_paye_cinetpay, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Finalisation d'initiation — réservée au serveur (Edge Function, après
-- le SEUL appel sortant réel vers l'API CinetPay). N'affecte jamais statut
-- ni montant_attendu.
--
-- ⚠️ Frontière d'accès : GRANT/REVOKE au niveau Postgres (ci-dessous), PAS
-- un contrôle interne via est_appel_service(). Cette fonction est elle-même
-- SECURITY DEFINER : à l'intérieur de son corps, current_user vaut déjà le
-- propriétaire (postgres), donc est_appel_service() y répondrait TOUJOURS
-- vrai, quel que soit l'appelant réel -- constaté empiriquement en testant
-- cette migration (le garde-fou interne ne bloquait jamais). C'est
-- précisément l'usage prévu d'est_appel_service() ailleurs dans ce dépôt :
-- reconnaître depuis l'INTÉRIEUR d'une RPC de confiance déjà validée qu'on
-- peut traverser une AUTRE protection (trigger anti-escalade, policy RLS
-- d'une table tierce) -- pas décider qui a le droit d'appeler la RPC
-- elle-même. Ici, le filtre correct est le REVOKE/GRANT natif de Postgres,
-- vérifié par le moteur AVANT même d'entrer dans la fonction -- même
-- patron que generer_alertes_decrochage (M7), aucune vérification interne.
-- ---------------------------------------------------------------------------
create or replace function public.finaliser_initiation_cinetpay(
  p_transaction_id uuid,
  p_reference_cinetpay text
)
returns public.transactions_cinetpay
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.transactions_cinetpay;
begin
  update public.transactions_cinetpay
  set reference_cinetpay = p_reference_cinetpay, updated_at = now()
  where id = p_transaction_id and statut = 'initie'
  returning * into v_row;

  if v_row is null then
    raise exception 'TRANSACTION_INTROUVABLE_OU_DEJA_TRAITEE' using errcode = '23514';
  end if;

  return v_row;
end;
$$;

revoke all on function public.finaliser_initiation_cinetpay(uuid, text) from public, anon, authenticated;
grant execute on function public.finaliser_initiation_cinetpay(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 8. Webhook — SEULE autorité de crédit. Point d'entrée public sans JWT
-- Supabase (CinetPay appelle en direct) : côté Postgres, la frontière
-- d'accès est le GRANT/REVOKE ci-dessous (service_role uniquement, jamais
-- un contrôle interne via est_appel_service() -- même remarque que pour
-- finaliser_initiation_cinetpay au point 7 : cette fonction est elle-même
-- SECURITY DEFINER, current_user y vaut déjà le propriétaire). Côté HTTP
-- (Edge Function), la signature CinetPay est la SEULE barrière -- vérifiée
-- ICI en SQL (et non dans l'Edge Function en Deno) pour
-- rester testable par pgTAP comme le reste du dépôt -- aucune suite de
-- tests Deno n'existe dans ce projet, jamais une garde non vérifiée
-- empiriquement.
--
-- ⚠️ Construction du message à signer (transaction_id:montant:moyen) :
-- PLACEHOLDER documenté au mieux de la connaissance actuelle, en l'absence
-- de tout identifiant/doc CinetPay réel (voir CINETPAY.md §4, même
-- avertissement que la référence). Isolé dans un seul bloc pour n'être
-- qu'un seul endroit à corriger le jour venu, sans toucher au reste.
--
-- Idempotence : SELECT ... FOR UPDATE verrouille la ligne avant de décider
-- -- un rejeu concurrent (retry réseau, double notification CinetPay)
-- attend le verrou puis constate statut <> 'initie' et repart sans rien
-- créditer une seconde fois.
--
-- Écart montant confirmé vs montant_attendu (recalculé à l'initiation) :
-- statut 'echoue', JAMAIS un crédit silencieux sur un montant inattendu.
-- Un statut 'echoue' est terminal (aucun rejeu ultérieur ne peut plus faire
-- basculer cette transaction sur 'reussi') -- correction manuelle par les
-- RPC admin_gsg existantes si besoin, jamais une réouverture automatique.
-- ---------------------------------------------------------------------------
create or replace function public.traiter_webhook_cinetpay(
  p_transaction_id uuid,
  p_signature text,
  p_montant numeric,
  p_moyen text,
  p_payload jsonb default '{}'::jsonb
)
returns public.transactions_cinetpay
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
  v_message text;
  v_signature_attendue text;
  v_transaction public.transactions_cinetpay;
  v_annee uuid;
  v_effectif int;
begin
  select valeur ->> 'secret_verification_webhook' into v_secret
  from public.parametres_secrets_integration
  where cle = 'cinetpay_config';

  if v_secret is null or v_secret = '' then
    raise exception 'CINETPAY_NON_CONFIGURE' using errcode = '55000';
  end if;

  v_message := p_transaction_id::text || ':' || p_montant::text || ':' || coalesce(p_moyen, '');
  v_signature_attendue := encode(extensions.hmac(v_message::bytea, v_secret::bytea, 'sha256'), 'hex');

  if p_signature is null or p_signature <> v_signature_attendue then
    raise exception 'SIGNATURE_INVALIDE' using errcode = '42501';
  end if;

  select * into v_transaction
  from public.transactions_cinetpay
  where id = p_transaction_id
  for update;

  if v_transaction is null then
    raise exception 'TRANSACTION_INTROUVABLE' using errcode = '23514';
  end if;

  -- Idempotence : déjà traitée (rejeu CinetPay) -> no-op, jamais un second crédit.
  if v_transaction.statut <> 'initie' then
    return v_transaction;
  end if;

  if p_montant is distinct from v_transaction.montant_attendu then
    update public.transactions_cinetpay
    set statut = 'echoue', montant_confirme = p_montant, moyen_paiement = p_moyen,
        payload_webhook = p_payload, updated_at = now()
    where id = p_transaction_id
    returning * into v_transaction;

    return v_transaction;
  end if;

  update public.transactions_cinetpay
  set statut = 'reussi', montant_confirme = p_montant, moyen_paiement = p_moyen,
      payload_webhook = p_payload, updated_at = now()
  where id = p_transaction_id
  returning * into v_transaction;

  v_annee := (v_transaction.contexte ->> 'annee_scolaire_id')::uuid;

  case v_transaction.type_objet_paye
    when 'licence_pro_etablissement' then
      -- Recompte EN DIRECT, jamais effectif_a_l_initiation (peut être
      -- périmé si le webhook arrive après un délai) -- correction actée.
      v_effectif := public.compter_effectif_actif(v_transaction.etablissement_id, v_annee);
      perform public.appliquer_paiement_licence_pro(
        v_transaction.etablissement_id, v_annee, v_effectif, v_transaction.montant_confirme
      );
    when 'frais_ia_admin_etablissement' then
      perform public.appliquer_paiement_frais_ia_admin(
        v_transaction.etablissement_id, v_annee, v_transaction.montant_confirme
      );
  end case;

  return v_transaction;
end;
$$;

revoke all on function public.traiter_webhook_cinetpay(uuid, text, numeric, text, jsonb) from public, anon, authenticated;
grant execute on function public.traiter_webhook_cinetpay(uuid, text, numeric, text, jsonb) to service_role;

-- ============================================================================
-- Fin — Chantier Facturation/Quota IA, étape (b).
-- ============================================================================
