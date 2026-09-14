-- ============================================================================
-- EcoShop — Chantier Facturation/Quota IA — Étape (c) : Abonnement Premium
-- élève (moteur de révision, §17.7/17.8/21.4/36.2), premier flux INDIVIDUEL
-- (par élève, jamais par établissement) branché sur la brique CinetPay
-- générique de l'étape (b).
--
-- Différence de forme assumée par rapport à l'étape (a) : pas de cycle
-- année scolaire (contrairement à licence_pro/frais_ia_admin) -- un verrou
-- simple "actif jusqu'à telle date" (abonnements_premium_eleve.expire_le),
-- mensuel ou annuel au choix (§17.7), renouvelé manuellement (aucune
-- récurrence automatique dans ce chantier, même règle que les deux autres
-- flux). Patron repris du modèle individuel déjà éprouvé côté
-- ecoshop_flutter, pas du modèle par-année-scolaire de l'étape (a).
--
-- Distinction structurelle posée dès le schéma, jamais laissée à la seule
-- discipline applicative : payeur (transactions_cinetpay.initiateur_id,
-- auth.uid() de qui règle -- élève OU parent, §36.2) et bénéficiaire
-- (transactions_cinetpay.beneficiaire_fiche_eleve_id, l'élève dont
-- l'entitlement est débloqué) sont deux colonnes distinctes, jamais l'une
-- déduite de l'autre. Contrainte CHECK transactions_cinetpay_coherence
-- verrouille la forme selon le type -- proposée en revue au-delà de ce qui
-- avait été explicitement demandé, actée par le porteur de projet.
--
-- Visibilité de l'entitlement (table + fonction) : l'élève lui-même
-- (fiches_eleves.profile_id = auth.uid()), un parent confirmé
-- (est_parent_confirme, M5), ou l'admin GSG -- délibérément PAS
-- est_personnel(etablissement) : ceci reste une affaire entre l'élève/son
-- parent et la plateforme, pas une donnée de gestion de l'établissement.
-- Paiement direct par l'élève lui-même (même mineur) explicitement autorisé
-- par le porteur de projet, conforme au cahier (§21.4/36.2) -- aucune
-- restriction d'âge ajoutée ici.
--
-- Cohérence maintenue avec les deux flux existants (même discipline anti-
-- garde-composite actée à l'étape (b)) : calcul/upsert extrait dans une
-- fonction privée SANS vérification d'autorisation propre (revoke all from
-- public, anon, authenticated), appelée après SA PROPRE garde par la RPC
-- admin manuelle (enregistrer_paiement_abonnement_premium_eleve,
-- est_admin_gsg(), conservée pour la même capacité de support/rattrapage
-- que licence_pro/frais_ia_admin) et par traiter_webhook_cinetpay (déjà
-- réservée à service_role depuis l'étape (b), aucun changement de garde
-- nécessaire là -- seule une nouvelle branche de dispatch est ajoutée).
--
-- initier_transaction_cinetpay est restructurée (pas simplement complétée) :
-- la garde et la résolution d'année scolaire, valables uniquement pour les
-- deux types établissement, migrent À L'INTÉRIEUR de leur branche du CASE ;
-- une nouvelle branche abonnement_premium_eleve porte sa propre garde
-- (élève lui-même OU parent confirmé) et son propre calcul de montant.
-- Signature étendue par DEUX paramètres optionnels en fin de liste
-- (p_beneficiaire_fiche_eleve, p_formule) -- la fonction existante est
-- explicitement DROP puis recréée (jamais laissée cohabiter en overload
-- avec l'ancienne signature à 3 paramètres, qui resterait sinon divergente
-- et jamais appelée par les nouveaux clients).
--
-- Hors périmètre de cette étape (tracé, pas construit ici) : aucun
-- branchement des fonctionnalités débloquées par l'entitlement (chapitres
-- 14/15/21, quota IA élevé) -- même discipline que le chapitre 18 pour
-- l'étape (a). Aucun flux de remboursement (statut_paiement a déjà
-- 'rembourse' depuis M13, mais rien ne l'écrit ici).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Type fermé pour la périodicité -- même discipline que
--    type_entitlement_etablissement/type_objet_paye_cinetpay : un enum
--    classique, contrôlé par GSG.
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.formule_abonnement_premium_eleve as enum ('mensuel', 'annuel');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 2. Entitlement -- une ligne par élève, mise à jour en place (verrou
--    simple), jamais une ligne par période comme licence_pro/frais_ia_admin
--    (pas de cycle année scolaire pour ce flux, §17.7).
-- ---------------------------------------------------------------------------
create table if not exists public.abonnements_premium_eleve (
  id uuid primary key default gen_random_uuid(),
  fiche_eleve_id uuid not null unique references public.fiches_eleves (id) on delete cascade,
  formule public.formule_abonnement_premium_eleve not null,
  expire_le timestamptz not null,
  montant_dernier_paiement numeric(12, 2) not null check (montant_dernier_paiement >= 0),
  date_dernier_paiement timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists abonnements_premium_eleve_set_updated_at on public.abonnements_premium_eleve;
create trigger abonnements_premium_eleve_set_updated_at
  before update on public.abonnements_premium_eleve
  for each row execute function public.set_updated_at();

alter table public.abonnements_premium_eleve enable row level security;

-- Visibilité : élève lui-même, parent confirmé, admin GSG -- délibérément
-- PAS est_personnel(etablissement), voir en-tête.
drop policy if exists "abonnements_premium_eleve_select" on public.abonnements_premium_eleve;
create policy "abonnements_premium_eleve_select" on public.abonnements_premium_eleve
  for select using (
    exists (
      select 1 from public.fiches_eleves f
      where f.id = fiche_eleve_id and f.profile_id = auth.uid()
    )
    or public.est_parent_confirme(fiche_eleve_id)
    or coalesce(public.est_admin_gsg(), false)
  );

-- Écriture TOUJOURS refusée au client -- RPC dédiées uniquement, même règle
-- que les deux autres tables d'entitlement (étape a).
drop policy if exists "abonnements_premium_eleve_no_direct_write" on public.abonnements_premium_eleve;
create policy "abonnements_premium_eleve_no_direct_write" on public.abonnements_premium_eleve
  for all using (false) with check (false);

-- ---------------------------------------------------------------------------
-- 3. Configuration (§30.4 -- rien codé en dur). Valeurs PLACEHOLDER, comme
--    à l'étape (a), à remplacer par le porteur de projet avant activation.
-- ---------------------------------------------------------------------------
insert into public.parametres_globaux (cle, valeur, description) values
  (
    'tarif_abonnement_premium_eleve_mensuel',
    '{"valeur": 1}'::jsonb,
    'PLACEHOLDER — montant fictif (1 GNF). Abonnement Premium élève, formule mensuelle (§17.7/36.2). À remplacer par le porteur de projet avant toute activation réelle.'
  )
on conflict (cle) do nothing;

insert into public.parametres_globaux (cle, valeur, description) values
  (
    'tarif_abonnement_premium_eleve_annuel',
    '{"valeur": 1}'::jsonb,
    'PLACEHOLDER — montant fictif (1 GNF). Abonnement Premium élève, formule annuelle (§17.7/36.2). À remplacer par le porteur de projet avant toute activation réelle.'
  )
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Contrat d'entitlement unifié -- même patron qu'entitlement_actif() de
--    l'étape (a) : la fonction vérifie elle-même sa propre visibilité avant
--    de renvoyer son booléen (security definer, sans quoi elle
--    contournerait la RLS de la table ci-dessus).
-- ---------------------------------------------------------------------------
create or replace function public.entitlement_premium_eleve_actif(p_fiche_eleve uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (
    exists (
      select 1 from public.fiches_eleves f
      where f.id = p_fiche_eleve and f.profile_id = auth.uid()
    )
    or public.est_parent_confirme(p_fiche_eleve)
    or coalesce(public.est_admin_gsg(), false)
  ) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  return coalesce((
    select expire_le > now() from public.abonnements_premium_eleve
    where fiche_eleve_id = p_fiche_eleve
  ), false);
end;
$$;

grant execute on function public.entitlement_premium_eleve_actif(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Calcul/upsert privé -- AUCUNE vérification d'autorisation ici (jamais
--    grantée à un rôle client), partagée par la RPC admin manuelle et le
--    webhook, chacun après SA PROPRE garde (même discipline qu'à l'étape b,
--    aucun OR combiné). Renouvellement anticipé n'écrase jamais du temps
--    déjà payé : la nouvelle échéance part du plus tardif de (maintenant,
--    échéance actuelle), jamais de la seule date du jour.
-- ---------------------------------------------------------------------------
create or replace function public.appliquer_paiement_abonnement_premium_eleve(
  p_fiche_eleve uuid,
  p_formule public.formule_abonnement_premium_eleve,
  p_montant numeric
)
returns public.abonnements_premium_eleve
language plpgsql
set search_path = public
as $$
declare
  v_row public.abonnements_premium_eleve;
  v_duree interval;
begin
  if not exists (select 1 from public.fiches_eleves where id = p_fiche_eleve) then
    raise exception 'FICHE_ELEVE_INTROUVABLE' using errcode = '23514';
  end if;

  if p_montant is null or p_montant < 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;

  v_duree := case p_formule when 'mensuel' then interval '1 month' else interval '1 year' end;

  insert into public.abonnements_premium_eleve (
    fiche_eleve_id, formule, expire_le, montant_dernier_paiement, date_dernier_paiement
  )
  values (
    p_fiche_eleve, p_formule, now() + v_duree, p_montant, now()
  )
  on conflict (fiche_eleve_id) do update
    set formule = excluded.formule,
        expire_le = greatest(now(), public.abonnements_premium_eleve.expire_le) + v_duree,
        montant_dernier_paiement = excluded.montant_dernier_paiement,
        date_dernier_paiement = excluded.date_dernier_paiement
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.appliquer_paiement_abonnement_premium_eleve(
  uuid, public.formule_abonnement_premium_eleve, numeric
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. RPC admin manuelle -- réservée à est_admin_gsg(), conservée pour la
--    même capacité de support/rattrapage manuel que licence_pro/
--    frais_ia_admin (étape a).
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_paiement_abonnement_premium_eleve(
  p_fiche_eleve uuid,
  p_formule public.formule_abonnement_premium_eleve,
  p_montant numeric
)
returns public.abonnements_premium_eleve
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ADMIN_GSG_REQUIS' using errcode = '42501';
  end if;

  return public.appliquer_paiement_abonnement_premium_eleve(p_fiche_eleve, p_formule, p_montant);
end;
$$;

grant execute on function public.enregistrer_paiement_abonnement_premium_eleve(
  uuid, public.formule_abonnement_premium_eleve, numeric
) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. transactions_cinetpay -- deux colonnes nullables pour le flux
--    individuel, jamais l'une déduite de l'autre (voir en-tête). Contrainte
--    CHECK verrouillant la forme selon le type -- proposée en revue,
--    conservée sur décision du porteur de projet.
-- ---------------------------------------------------------------------------
alter table public.transactions_cinetpay
  add column if not exists beneficiaire_fiche_eleve_id uuid references public.fiches_eleves (id) on delete cascade,
  add column if not exists formule public.formule_abonnement_premium_eleve;

alter table public.transactions_cinetpay
  drop constraint if exists transactions_cinetpay_coherence;
alter table public.transactions_cinetpay
  add constraint transactions_cinetpay_coherence check (
    (type_objet_paye = 'abonnement_premium_eleve'
       and etablissement_id is null
       and beneficiaire_fiche_eleve_id is not null
       and formule is not null)
    or
    (type_objet_paye <> 'abonnement_premium_eleve'
       and beneficiaire_fiche_eleve_id is null
       and formule is null)
  );

create index if not exists idx_transactions_cinetpay_beneficiaire
  on public.transactions_cinetpay (beneficiaire_fiche_eleve_id);

-- Policy select étendue au payeur -- dette actée à l'étape (b), soldée ici.
-- Ne couvre PAS le bénéficiaire si distinct du payeur (parent payeur) :
-- visibilité du ledger (qui a payé) et visibilité de l'entitlement qui en
-- résulte (entitlement_premium_eleve_actif, point 4) répondent à deux
-- questions différentes, actée comme telle par le porteur de projet.
drop policy if exists "transactions_cinetpay_select" on public.transactions_cinetpay;
create policy "transactions_cinetpay_select" on public.transactions_cinetpay
  for select using (
    coalesce(public.est_personnel(etablissement_id), false)
    or coalesce(public.est_admin_gsg(), false)
    or initiateur_id = auth.uid()
  );

-- ---------------------------------------------------------------------------
-- 8. initier_transaction_cinetpay -- restructurée, pas simplement complétée
--    (voir en-tête). DROP explicite de l'ancienne signature à 3 paramètres :
--    CREATE OR REPLACE avec des paramètres ajoutés créerait un second
--    overload divergent plutôt que de remplacer l'existant, puisque la
--    liste de types change -- jamais deux copies de cette logique.
-- ---------------------------------------------------------------------------
drop function if exists public.initier_transaction_cinetpay(public.type_objet_paye_cinetpay, uuid, uuid);

create or replace function public.initier_transaction_cinetpay(
  p_type_objet_paye public.type_objet_paye_cinetpay,
  p_etablissement uuid,
  p_annee_scolaire uuid default null,
  p_beneficiaire_fiche_eleve uuid default null,
  p_formule public.formule_abonnement_premium_eleve default null
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
  v_contexte jsonb := '{}'::jsonb;
  v_row public.transactions_cinetpay;
  v_etablissement uuid := p_etablissement;
  v_beneficiaire uuid := p_beneficiaire_fiche_eleve;
  v_formule public.formule_abonnement_premium_eleve := p_formule;
begin
  case p_type_objet_paye
    when 'licence_pro_etablissement', 'frais_ia_admin_etablissement' then
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

      -- Flux établissement : jamais de bénéficiaire/formule individuels.
      v_beneficiaire := null;
      v_formule := null;

      if p_type_objet_paye = 'licence_pro_etablissement' then
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
      else
        if coalesce((
          select paye from public.etablissements_frais_ia_admin
          where etablissement_id = p_etablissement and annee_scolaire_id = v_annee
        ), false) then
          raise exception 'DEJA_PAYE' using errcode = '22023';
        end if;

        select (valeur->>'valeur')::numeric into v_montant
        from public.parametres_globaux where cle = 'tarif_frais_ia_admin_annuel';

        v_contexte := jsonb_build_object('annee_scolaire_id', v_annee);
      end if;

    when 'abonnement_premium_eleve' then
      if p_beneficiaire_fiche_eleve is null or p_formule is null then
        raise exception 'PARAMETRES_ABONNEMENT_MANQUANTS' using errcode = '22023';
      end if;

      -- Garde : l'élève bénéficiaire lui-même (même mineur, autorisé
      -- explicitement par le porteur de projet -- §21.4/36.2) OU un parent
      -- confirmé de CETTE fiche. Un inexistant p_beneficiaire_fiche_eleve
      -- échoue ici naturellement (exists/est_parent_confirme renvoient
      -- faux), sans exposer d'oracle d'existence distinct.
      if not (
        exists (
          select 1 from public.fiches_eleves f
          where f.id = p_beneficiaire_fiche_eleve and f.profile_id = auth.uid()
        )
        or public.est_parent_confirme(p_beneficiaire_fiche_eleve)
      ) then
        raise exception 'ACCES_REFUSE' using errcode = '42501';
      end if;

      -- Flux individuel : jamais d'établissement ni d'année scolaire.
      v_etablissement := null;
      v_annee := null;

      select (valeur->>'valeur')::numeric into v_montant
      from public.parametres_globaux
      where cle = case p_formule
        when 'mensuel' then 'tarif_abonnement_premium_eleve_mensuel'
        else 'tarif_abonnement_premium_eleve_annuel'
      end;

      v_contexte := jsonb_build_object('formule', p_formule);

    else
      raise exception 'TYPE_NON_SUPPORTE' using errcode = '0A000';
  end case;

  insert into public.transactions_cinetpay (
    type_objet_paye, etablissement_id, initiateur_id, contexte, montant_attendu,
    beneficiaire_fiche_eleve_id, formule
  )
  values (
    p_type_objet_paye, v_etablissement, auth.uid(), v_contexte, v_montant,
    v_beneficiaire, v_formule
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.initier_transaction_cinetpay(
  public.type_objet_paye_cinetpay, uuid, uuid, uuid, public.formule_abonnement_premium_eleve
) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. traiter_webhook_cinetpay -- une branche de dispatch supplémentaire,
--    AUCUN changement à la garde/signature/idempotence/écart de montant
--    déjà en place (étape b) : c'est exactement ce qui rend la brique
--    générique.
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
    when 'abonnement_premium_eleve' then
      perform public.appliquer_paiement_abonnement_premium_eleve(
        v_transaction.beneficiaire_fiche_eleve_id, v_transaction.formule, v_transaction.montant_confirme
      );
  end case;

  return v_transaction;
end;
$$;

revoke all on function public.traiter_webhook_cinetpay(uuid, text, numeric, text, jsonb) from public, anon, authenticated;
grant execute on function public.traiter_webhook_cinetpay(uuid, text, numeric, text, jsonb) to service_role;

-- ============================================================================
-- Fin — Chantier Facturation/Quota IA, étape (c).
-- ============================================================================
