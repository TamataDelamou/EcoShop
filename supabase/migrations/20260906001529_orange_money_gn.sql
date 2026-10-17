-- ============================================================================
-- EcoShop — REG-02 Orange Money Guinée, lot L1 (2/2) : schéma et RPC
-- (docs/REGISTRE.md REG-02, docs/propositions/REG-02_MOBILE_MONEY.md,
--  validé par le porteur de projet le 2026-10-17)
--
-- Circuit ÉTABLISSEMENT (modèle AssoShop) : chaque établissement encaisse
-- sur SON PROPRE compte marchand Orange Money ; GSG ne détient jamais les
-- fonds. Deux usages branchés :
--   • scolarite            — un paiement réussi crée l'encaissement de
--                            scolarité correspondant (donc le reçu PDF) ;
--   • commande_marketplace — un paiement réussi crée la ligne `paiements`
--                            (port agnostique M13) et passe la commande en
--                            « payee ».
--
-- Même discipline que la brique CinetPay (20260906001515) :
--   1. identifiants marchands dans une table SANS AUCUNE policy (deny-all
--      pour tout rôle client, y compris en lecture) ; seuls service_role et
--      les fonctions SECURITY DEFINER y accèdent ;
--   2. montant TOUJOURS recalculé ou borné côté serveur, jamais celui du
--      client seul ;
--   3. la notification de l'opérateur n'est jamais crue sur parole : l'Edge
--      Function reconfirme le statut auprès d'Orange avant d'appeler
--      traiter_resultat_mobile_money() ;
--   4. idempotence par bascule atomique sous verrou (SELECT … FOR UPDATE) :
--      une notification rejouée ne crédite jamais deux fois ;
--   5. frontière service_role par GRANT/REVOKE uniquement (est_appel_service()
--      est inopérant dans une fonction SECURITY DEFINER, cf. 1515 point 8).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Identifiants marchands par sous-compte — deny-all
-- ---------------------------------------------------------------------------
create table if not exists public.secrets_sous_comptes_marchands (
  sous_compte_id uuid primary key
    references public.sous_comptes_marchands (id) on delete cascade,
  -- { "client_id", "client_secret", "merchant_key", "environnement" }
  identifiants jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.secrets_sous_comptes_marchands enable row level security;
-- Aucune policy : illisible et non modifiable par anon/authenticated.

revoke all on public.secrets_sous_comptes_marchands from anon, authenticated;

drop trigger if exists secrets_sous_comptes_set_updated_at on public.secrets_sous_comptes_marchands;
create trigger secrets_sous_comptes_set_updated_at
  before update on public.secrets_sous_comptes_marchands
  for each row execute function public.set_updated_at();

comment on table public.secrets_sous_comptes_marchands is
  'REG-02 : identifiants marchands opérateur (Orange Money…) PAR établissement. '
  'Aucune policy RLS : jamais lisibles par un client. Écriture via '
  'enregistrer_identifiants_orange_money(), lecture via '
  'lire_identifiants_sous_compte() (service_role uniquement).';

-- ---------------------------------------------------------------------------
-- 2. Transactions mobile money (circuit établissement)
-- ---------------------------------------------------------------------------
create table if not exists public.transactions_mobile_money (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  sous_compte_id uuid not null references public.sous_comptes_marchands (id) on delete restrict,
  fournisseur public.type_fournisseur_paiement not null,
  objet text not null check (objet in ('scolarite', 'commande_marketplace')),
  inscription_id uuid references public.inscriptions (id) on delete restrict,
  commande_id uuid references public.commandes (id) on delete restrict,
  initiateur_id uuid not null references public.profiles (id),
  montant numeric(12, 2) not null check (montant > 0),
  devise text not null,
  -- Référence transmise à l'opérateur (order_id) : courte, unique, sans
  -- donnée personnelle.
  reference_commande text not null unique,
  statut public.statut_paiement not null default 'initie',
  pay_token text,
  -- Empreinte SHA-256 du notif_token renvoyé par l'opérateur : le jeton
  -- lui-même n'est jamais stocké (la ligne est lisible par le payeur).
  empreinte_jeton_notification text,
  reference_operateur text,
  message text,
  encaissement_id uuid references public.encaissements_scolarite (id),
  paiement_id uuid references public.paiements (id),
  traite_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transactions_mm_cible_coherente check (
    (objet = 'scolarite' and inscription_id is not null and commande_id is null)
    or (objet = 'commande_marketplace' and commande_id is not null and inscription_id is null)
  )
);

create index if not exists idx_transactions_mm_etab on public.transactions_mobile_money (etablissement_id);
create index if not exists idx_transactions_mm_initiateur on public.transactions_mobile_money (initiateur_id);
create index if not exists idx_transactions_mm_inscription on public.transactions_mobile_money (inscription_id) where inscription_id is not null;
create index if not exists idx_transactions_mm_commande on public.transactions_mobile_money (commande_id) where commande_id is not null;

drop trigger if exists transactions_mm_set_updated_at on public.transactions_mobile_money;
create trigger transactions_mm_set_updated_at
  before update on public.transactions_mobile_money
  for each row execute function public.set_updated_at();

alter table public.transactions_mobile_money enable row level security;

-- Lecture : le payeur, le personnel de l'établissement, l'admin GSG.
-- Aucune écriture directe : RPC uniquement.
drop policy if exists transactions_mm_select on public.transactions_mobile_money;
create policy transactions_mm_select on public.transactions_mobile_money
  for select using (
    initiateur_id = auth.uid()
    or coalesce(public.est_personnel(etablissement_id), false)
    or coalesce(public.est_admin_gsg(), false)
  );

revoke insert, update, delete on public.transactions_mobile_money from anon, authenticated;

-- Journalisation (§34.3) — même patron que transactions_cinetpay.
create or replace function public.transactions_mm_audit_statut()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.statut is distinct from new.statut then
    perform public.enregistrer_audit(
      new.etablissement_id, 'transaction_mobile_money', new.id, 'statut',
      to_jsonb(old.statut), to_jsonb(new.statut)
    );
  end if;
  return new;
end $$;

drop trigger if exists transactions_mm_audit_statut_trg on public.transactions_mobile_money;
create trigger transactions_mm_audit_statut_trg
  after update on public.transactions_mobile_money
  for each row execute procedure public.transactions_mm_audit_statut();

-- Visibilité de la nouvelle entité dans le journal d'audit : personnel de
-- l'établissement et admin GSG (même règle que transaction_cinetpay).
create or replace function public.journal_audit_visible(p_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare v_row public.journal_audit;
begin
  select * into v_row from public.journal_audit where id = p_id;
  if v_row.id is null then
    return false;
  end if;

  return case v_row.entite
    when 'inscription' then
      public.fiche_visible(v_row.fiche_eleve_id)
    when 'sanction' then
      public.sanction_visible(v_row.entite_id)
    when 'conge' then
      exists (
        select 1 from public.conges c
        where c.id = v_row.entite_id
          and (public.est_employe_self(c.employe_id) or public.est_rh(c.etablissement_id))
      )
      or coalesce(public.est_admin_gsg(), false)
    when 'transaction_cinetpay' then
      coalesce(public.est_personnel(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'transaction_mobile_money' then
      coalesce(public.est_personnel(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'paiement_marketplace' then
      coalesce(public.est_membre_actif(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'commande_marketplace' then
      exists (
        select 1 from public.commandes c
        where c.id = v_row.entite_id and c.profile_id = auth.uid()
      )
      or coalesce(public.est_membre_actif(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'encaissement_scolarite' then
      public.encaissement_visible(v_row.entite_id)
    when 'abonnement_premium_eleve' then
      exists (
        select 1 from public.fiches_eleves f
        where f.id = v_row.fiche_eleve_id and f.profile_id = auth.uid()
      )
      or public.est_parent_confirme(v_row.fiche_eleve_id)
      or coalesce(public.est_admin_gsg(), false)
    when 'message_groupe' then
      public.moderateur_groupe(v_row.groupe_id)
    else false
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Encaissement créé par le serveur (paiement en ligne confirmé)
--
-- encaissements_verifie_tenant() imposait saisi_par := auth.uid(), qui est
-- NULL pour un traitement serveur (notification opérateur) et violerait la
-- contrainte NOT NULL. Un client authentifié a TOUJOURS un auth.uid() non
-- nul : le repli sur la valeur fournie ne s'applique donc qu'aux écritures
-- serveur (traiter_resultat_mobile_money(), qui y place le payeur). Aucun
-- client ne peut ainsi usurper saisi_par.
-- ---------------------------------------------------------------------------
create or replace function public.encaissements_verifie_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_etab uuid; v_etab_insc uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab_insc from public.inscriptions where id = new.inscription_id;
  if v_etab_insc is distinct from new.etablissement_id then
    raise exception 'INSCRIPTION_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  if not exists (
    select 1 from public.inscriptions i
    where i.id = new.inscription_id and i.fiche_eleve_id = new.fiche_eleve_id and i.deleted_at is null
  ) then
    raise exception 'INSCRIPTION_FICHE_INCOHERENTE' using errcode = '23514';
  end if;

  if tg_op = 'INSERT' then
    new.saisi_par := coalesce(auth.uid(), new.saisi_par);
  end if;

  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Activation par l'établissement : identifiants Orange Money
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_identifiants_orange_money(
  p_etablissement_id uuid,
  p_client_id text,
  p_client_secret text,
  p_merchant_key text,
  p_environnement text default 'test',
  p_libelle text default 'Orange Money'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sous_compte uuid;
begin
  if not (coalesce(public.est_direction(p_etablissement_id), false)
          or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if p_environnement not in ('test', 'production') then
    raise exception 'ENVIRONNEMENT_INVALIDE' using errcode = '22023';
  end if;
  if coalesce(trim(p_client_id), '') = '' or coalesce(trim(p_client_secret), '') = ''
     or coalesce(trim(p_merchant_key), '') = '' then
    raise exception 'IDENTIFIANTS_INCOMPLETS' using errcode = '22023';
  end if;

  select id into v_sous_compte
  from public.sous_comptes_marchands
  where etablissement_id = p_etablissement_id
    and fournisseur = 'orange_money_gn'
    and deleted_at is null;

  if v_sous_compte is null then
    insert into public.sous_comptes_marchands (etablissement_id, fournisseur, libelle, reference_compte, actif)
    values (p_etablissement_id, 'orange_money_gn', p_libelle,
            -- identifiant PUBLIC affichable : jamais un secret
            'OM-' || right(regexp_replace(p_merchant_key, '\s', '', 'g'), 4), true)
    returning id into v_sous_compte;
  else
    update public.sous_comptes_marchands
       set actif = true, libelle = p_libelle,
           reference_compte = 'OM-' || right(regexp_replace(p_merchant_key, '\s', '', 'g'), 4)
     where id = v_sous_compte;
  end if;

  insert into public.secrets_sous_comptes_marchands (sous_compte_id, identifiants)
  values (v_sous_compte, jsonb_build_object(
    'client_id', p_client_id, 'client_secret', p_client_secret,
    'merchant_key', p_merchant_key, 'environnement', p_environnement))
  on conflict (sous_compte_id) do update set identifiants = excluded.identifiants;

  return v_sous_compte;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Initiation (appelée par l'Edge Function avec le JWT du payeur)
-- ---------------------------------------------------------------------------
create or replace function public.initier_transaction_mobile_money(
  p_objet text,
  p_cible_id uuid,
  p_montant numeric default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_etab uuid;
  v_fiche uuid;
  v_montant numeric(12, 2);
  v_solde numeric;
  v_devise text;
  v_sous_compte uuid;
  v_commande public.commandes;
  v_tx public.transactions_mobile_money;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUISE' using errcode = '42501';
  end if;

  if p_objet = 'scolarite' then
    select i.etablissement_id, i.fiche_eleve_id into v_etab, v_fiche
    from public.inscriptions i
    where i.id = p_cible_id and i.deleted_at is null;
    if v_etab is null then
      raise exception 'INSCRIPTION_INTROUVABLE' using errcode = '22023';
    end if;
    -- Payeur : l'élève lui-même ou un parent confirmé et autorisé. Le
    -- personnel saisit les paiements au guichet (encaissement manuel).
    if not (exists (select 1 from public.fiches_eleves f where f.id = v_fiche and f.profile_id = v_uid)
            or public.est_parent_confirme(v_fiche)) then
      raise exception 'ACCES_REFUSE' using errcode = '42501';
    end if;

    select solde into v_solde from public.solde_scolarite(p_cible_id);
    v_montant := coalesce(p_montant, v_solde);
    if v_montant is null or v_montant <= 0 then
      raise exception 'RIEN_A_PAYER' using errcode = '22023';
    end if;
    if v_montant > v_solde then
      raise exception 'MONTANT_SUPERIEUR_AU_SOLDE' using errcode = '22023';
    end if;

  elsif p_objet = 'commande_marketplace' then
    select * into v_commande from public.commandes
    where id = p_cible_id and deleted_at is null;
    if v_commande.id is null then
      raise exception 'COMMANDE_INTROUVABLE' using errcode = '22023';
    end if;
    if v_commande.profile_id <> v_uid then
      raise exception 'ACCES_REFUSE' using errcode = '42501';
    end if;
    if v_commande.statut not in ('brouillon', 'confirmee') then
      raise exception 'COMMANDE_NON_PAYABLE' using errcode = '22023';
    end if;
    v_etab := v_commande.etablissement_id;
    -- Montant de la commande, jamais celui du client.
    v_montant := v_commande.montant_total + v_commande.montant_frais;
    if v_montant <= 0 then
      raise exception 'RIEN_A_PAYER' using errcode = '22023';
    end if;
  else
    raise exception 'OBJET_INCONNU' using errcode = '22023';
  end if;

  -- Une seule transaction en cours par cible : évite les doubles paiements.
  if exists (
    select 1 from public.transactions_mobile_money t
    where (t.inscription_id = p_cible_id or t.commande_id = p_cible_id)
      and t.statut in ('initie', 'en_attente')
      and t.created_at > now() - interval '30 minutes'
  ) then
    raise exception 'PAIEMENT_DEJA_EN_COURS' using errcode = '55000';
  end if;

  select s.id into v_sous_compte
  from public.sous_comptes_marchands s
  join public.secrets_sous_comptes_marchands sec on sec.sous_compte_id = s.id
  where s.etablissement_id = v_etab
    and s.fournisseur = 'orange_money_gn'
    and s.actif and s.deleted_at is null;
  if v_sous_compte is null then
    raise exception 'ORANGE_MONEY_NON_ACTIVE' using errcode = '55000';
  end if;

  select devise_code into v_devise from public.etablissements where id = v_etab;
  if v_devise = 'GNF' and v_montant <> trunc(v_montant) then
    raise exception 'MONTANT_GNF_ENTIER_REQUIS' using errcode = '22023';
  end if;

  insert into public.transactions_mobile_money (
    etablissement_id, sous_compte_id, fournisseur, objet,
    inscription_id, commande_id, initiateur_id, montant, devise, reference_commande
  ) values (
    v_etab, v_sous_compte, 'orange_money_gn', p_objet,
    case when p_objet = 'scolarite' then p_cible_id end,
    case when p_objet = 'commande_marketplace' then p_cible_id end,
    v_uid, v_montant, v_devise,
    'ECO' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 17))
  )
  returning * into v_tx;

  return jsonb_build_object(
    'transaction_id', v_tx.id,
    'reference_commande', v_tx.reference_commande,
    'montant', v_tx.montant,
    'devise', v_tx.devise,
    'sous_compte_id', v_tx.sous_compte_id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Fonctions serveur (service_role uniquement)
-- ---------------------------------------------------------------------------
create or replace function public.lire_identifiants_sous_compte(p_sous_compte_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select identifiants from public.secrets_sous_comptes_marchands
  where sous_compte_id = p_sous_compte_id;
$$;

create or replace function public.finaliser_initiation_mobile_money(
  p_transaction_id uuid,
  p_pay_token text,
  p_empreinte_jeton_notification text
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  update public.transactions_mobile_money
     set pay_token = p_pay_token,
         empreinte_jeton_notification = p_empreinte_jeton_notification
   where id = p_transaction_id and statut = 'initie';
  if not found then
    raise exception 'TRANSACTION_NON_INITIEE' using errcode = '55000';
  end if;
end;
$$;

-- Marque l'échec de l'appel d'initiation chez l'opérateur (aucun argent
-- n'a bougé) pour libérer la cible.
create or replace function public.abandonner_initiation_mobile_money(p_transaction_id uuid, p_message text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  update public.transactions_mobile_money
     set statut = 'echoue', message = left(p_message, 500), traite_le = now()
   where id = p_transaction_id and statut = 'initie' and pay_token is null;
end;
$$;

create or replace function public.lire_transaction_mobile_money_serveur(p_transaction_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', t.id, 'statut', t.statut, 'montant', t.montant, 'devise', t.devise,
    'reference_commande', t.reference_commande, 'pay_token', t.pay_token,
    'empreinte_jeton_notification', t.empreinte_jeton_notification,
    'sous_compte_id', t.sous_compte_id
  )
  from public.transactions_mobile_money t
  where t.id = p_transaction_id;
$$;

-- Seule autorité de crédit. Appelée par l'Edge Function APRÈS
-- reconfirmation du statut auprès de l'opérateur. Idempotente.
create or replace function public.traiter_resultat_mobile_money(
  p_transaction_id uuid,
  p_resultat text,               -- 'reussi' | 'echoue'
  p_montant_confirme numeric,
  p_reference_operateur text,
  p_message text default null
)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_tx public.transactions_mobile_money;
  v_fiche uuid;
  v_encaissement uuid;
  v_paiement uuid;
begin
  if p_resultat not in ('reussi', 'echoue') then
    raise exception 'RESULTAT_INVALIDE' using errcode = '22023';
  end if;

  select * into v_tx from public.transactions_mobile_money
  where id = p_transaction_id
  for update;

  if v_tx.id is null then
    raise exception 'TRANSACTION_INTROUVABLE' using errcode = '22023';
  end if;
  if v_tx.statut not in ('initie', 'en_attente') then
    return 'deja_traitee';
  end if;

  if p_resultat = 'echoue' then
    update public.transactions_mobile_money
       set statut = 'echoue', message = left(p_message, 500),
           reference_operateur = coalesce(p_reference_operateur, reference_operateur),
           traite_le = now()
     where id = v_tx.id;
    return 'echoue';
  end if;

  if p_montant_confirme is distinct from v_tx.montant then
    update public.transactions_mobile_money
       set statut = 'echoue', message = 'ECART_MONTANT',
           reference_operateur = p_reference_operateur, traite_le = now()
     where id = v_tx.id;
    return 'ecart_montant';
  end if;

  if v_tx.objet = 'scolarite' then
    select fiche_eleve_id into v_fiche from public.inscriptions where id = v_tx.inscription_id;
    insert into public.encaissements_scolarite (
      etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant,
      moyen_paiement, reference_paiement, date_paiement, saisi_par
    ) values (
      v_tx.etablissement_id, v_fiche, v_tx.inscription_id, 'scolarite', v_tx.montant,
      'mobile_money', 'OM:' || coalesce(p_reference_operateur, v_tx.reference_commande),
      current_date, v_tx.initiateur_id
    )
    returning id into v_encaissement;
  else
    insert into public.paiements (
      etablissement_id, commande_id, sous_compte_id, fournisseur, montant,
      statut, reference_fournisseur, message
    ) values (
      v_tx.etablissement_id, v_tx.commande_id, v_tx.sous_compte_id, v_tx.fournisseur,
      v_tx.montant, 'reussi', p_reference_operateur, 'Orange Money'
    )
    returning id into v_paiement;

    update public.commandes set statut = 'payee' where id = v_tx.commande_id;
  end if;

  update public.transactions_mobile_money
     set statut = 'reussi', reference_operateur = p_reference_operateur,
         encaissement_id = v_encaissement, paiement_id = v_paiement,
         traite_le = now()
   where id = v_tx.id;

  return 'reussi';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Droits
-- ---------------------------------------------------------------------------
revoke all on function public.enregistrer_identifiants_orange_money(uuid, text, text, text, text, text) from public, anon;
grant execute on function public.enregistrer_identifiants_orange_money(uuid, text, text, text, text, text) to authenticated;

revoke all on function public.initier_transaction_mobile_money(text, uuid, numeric) from public, anon;
grant execute on function public.initier_transaction_mobile_money(text, uuid, numeric) to authenticated;

revoke all on function public.lire_identifiants_sous_compte(uuid) from public, anon, authenticated;
revoke all on function public.finaliser_initiation_mobile_money(uuid, text, text) from public, anon, authenticated;
revoke all on function public.abandonner_initiation_mobile_money(uuid, text) from public, anon, authenticated;
revoke all on function public.lire_transaction_mobile_money_serveur(uuid) from public, anon, authenticated;
revoke all on function public.traiter_resultat_mobile_money(uuid, text, numeric, text, text) from public, anon, authenticated;
revoke all on function public.transactions_mm_audit_statut() from public, anon, authenticated;

grant execute on function public.lire_identifiants_sous_compte(uuid) to service_role;
grant execute on function public.finaliser_initiation_mobile_money(uuid, text, text) to service_role;
grant execute on function public.abandonner_initiation_mobile_money(uuid, text) to service_role;
grant execute on function public.lire_transaction_mobile_money_serveur(uuid) to service_role;
grant execute on function public.traiter_resultat_mobile_money(uuid, text, numeric, text, text) to service_role;
