-- EcoShop — Journalisation et audit (§34.3), périmètre tranché par le porteur
--
-- Cinq points en périmètre (base fonctionnelle déjà existante) :
--   1. Statut boursier (7.2)                         -> inscriptions.boursier
--   2. Sanction, y compris levée/annulation (19.1)    -> sanctions.statut
--   3. Congé, CHAQUE transition (8.5)                 -> conges.statut
--   4. Statuts de paiement (17.8), hors remboursement -> 4 tables (transactions_
--      cinetpay, paiements, commandes, encaissements_scolarite) + abonnements_
--      premium_eleve (renouvellement, même famille de mutation-en-place)
--   5. Copie horodatée d'un message signalé (20.4)    -> signalements_message
--
-- Sept points + le sous-cas remboursement sont une dette explicite, différée
-- à leur propre chantier de fonctionnalité de base (rien construit ici, même
-- partiellement) : contenu pédagogique (30.5), historique de templates (18.5),
-- suppression/anonymisation de compte, paramètres globaux (30.4), révocation
-- de session (5.5/30.6), notes après remontée (12.3), saisie par substitution
-- (7.5), remboursement CinetPay.
--
-- Table générique unique (précédent : entitlement_actif/transactions_cinetpay)
-- plutôt que des tables dédiées par fonctionnalité : aucune des 9 entités ne
-- justifie une structure propre (même quintuplet auteur/date/ancienne/nouvelle
-- valeur partout), et l'extension future des 7 points différés se fait par
-- ALTER TYPE ... ADD VALUE, jamais une nouvelle table.
--
-- Immutabilité stricte : aucune policy insert/update/delete pour quiconque,
-- y compris l'établissement concerné et l'auteur lui-même. Écriture exclusive
-- via enregistrer_audit(), SECURITY DEFINER, révoquée de public/anon/
-- authenticated (jamais un endpoint RPC direct). Les triggers par table
-- appelants sont eux-mêmes SECURITY DEFINER : enregistrer_audit() étant
-- révoquée pour les rôles clients, un trigger en droits d'appelant (comme
-- _verifie_tenant ailleurs dans ce dépôt) échouerait dès qu'un utilisateur
-- authenticated déclenche l'UPDATE source (ex. RH validant un congé). Sûr
-- ici via auth.uid() (JWT), pas current_user — la distinction qui piège
-- est_appel_service() dans une fonction elle-même SECURITY DEFINER (étape b
-- de la facturation) ne s'applique pas à auth.uid().
--
-- Visibilité PAR ENTITÉ, jamais une règle uniforme : la vérification directe
-- des policies actuelles a mis en évidence deux régressions de confidentialité
-- qu'une règle unique est_personnel()/est_admin_gsg() aurait introduites
-- (conges_select est en réalité est_employe_self/est_rh, plus étroit ;
-- signalements_select_moderation est restreint aux modérateurs du groupe,
-- bien plus étroit) et deux asymétries plus douces dans l'autre sens
-- (sanctions/inscriptions incluent l'élève/parent via fiche_visible ;
-- commandes inclut l'acheteur). journal_audit_visible() délègue donc, pour
-- chaque entité, à la règle de visibilité DÉJÀ établie sur la table source
-- (réutilisation directe de sanction_visible/encaissement_visible/
-- fiche_visible/moderateur_groupe quand la fonction existe déjà).
--
-- Rétention configurable (§34.2, jamais codée en dur) : parametres_globaux.
-- duree_retention_journal_audit. Valeur PLACEHOLDER (5 ans), comme à chaque
-- étape de la facturation, à trancher par le porteur avant activation. Aucun
-- job de purge automatique ici : aucune infra cron n'existe dans ce dépôt ;
-- §34.2 exige une durée définie et documentée, pas nécessairement déjà
-- appliquée. Ajout du job en dette, pour quand une infra cron existera.

-- ---------------------------------------------------------------------------
-- 1. Enum extensible des entités auditées
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.type_entite_journal_audit as enum (
    'inscription',
    'sanction',
    'conge',
    'transaction_cinetpay',
    'paiement_marketplace',
    'commande_marketplace',
    'encaissement_scolarite',
    'abonnement_premium_eleve',
    'message_groupe'
  );
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 2. Table générique
-- ---------------------------------------------------------------------------
create table if not exists public.journal_audit (
  id uuid primary key default gen_random_uuid(),
  -- nullable : null pour transaction_cinetpay/abonnement_premium_eleve du
  -- flux individuel Premium élève (etablissement_id est déjà nullable sur
  -- transactions_cinetpay pour ce même flux ; abonnements_premium_eleve n'a
  -- même pas de colonne etablissement_id -- confirmé aux étapes b/c).
  etablissement_id uuid references public.etablissements (id) on delete cascade,
  entite public.type_entite_journal_audit not null,
  entite_id uuid not null,
  -- dénormalisés : utilisés par journal_audit_visible() et par les requêtes
  -- « historique de cet élève »/« historique de ce groupe », jamais recalculés
  -- depuis nouvelle_valeur (même leçon qu'à l'étape c : un identifiant utilisé
  -- pour l'autorisation doit être une colonne, jamais seulement du JSON).
  fiche_eleve_id uuid references public.fiches_eleves (id) on delete set null,
  groupe_id uuid references public.groupes_discussion (id) on delete set null,
  champ text not null,
  ancienne_valeur jsonb,
  nouvelle_valeur jsonb not null,
  -- null = origine service_role/webhook, jamais un humain identifiable.
  auteur_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_journal_audit_entite on public.journal_audit (entite, entite_id);
create index if not exists idx_journal_audit_etablissement on public.journal_audit (etablissement_id);
create index if not exists idx_journal_audit_fiche on public.journal_audit (fiche_eleve_id) where fiche_eleve_id is not null;
create index if not exists idx_journal_audit_groupe on public.journal_audit (groupe_id) where groupe_id is not null;

alter table public.journal_audit enable row level security;

-- ---------------------------------------------------------------------------
-- 3. Visibilité par entité — délègue à la règle déjà établie sur la table
--    source, jamais une règle inventée.
-- ---------------------------------------------------------------------------
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

grant execute on function public.journal_audit_visible(uuid) to authenticated;

drop policy if exists "journal_audit_select_visible" on public.journal_audit;
create policy "journal_audit_select_visible" on public.journal_audit
  for select using (public.journal_audit_visible(id));

-- Immutabilité : aucune policy insert/update/delete pour quiconque, y compris
-- l'établissement concerné (même patron que transactions_cinetpay_no_direct_
-- write). Seule enregistrer_audit() écrit, en SECURITY DEFINER.
drop policy if exists "journal_audit_no_direct_write" on public.journal_audit;
create policy "journal_audit_no_direct_write" on public.journal_audit
  for all using (false) with check (false);

-- ---------------------------------------------------------------------------
-- 4. Capture partagée — jamais appelable directement par un client.
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_audit(
  p_etablissement_id uuid,
  p_entite public.type_entite_journal_audit,
  p_entite_id uuid,
  p_champ text,
  p_ancienne_valeur jsonb,
  p_nouvelle_valeur jsonb,
  p_fiche_eleve_id uuid default null,
  p_groupe_id uuid default null
) returns void
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.journal_audit (
    etablissement_id, entite, entite_id, fiche_eleve_id, groupe_id,
    champ, ancienne_valeur, nouvelle_valeur, auteur_id
  ) values (
    p_etablissement_id, p_entite, p_entite_id, p_fiche_eleve_id, p_groupe_id,
    p_champ, p_ancienne_valeur, p_nouvelle_valeur, auth.uid()
  );
end;
$$;

revoke all on function public.enregistrer_audit(
  uuid, public.type_entite_journal_audit, uuid, text, jsonb, jsonb, uuid, uuid
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Triggers par table source — SECURITY DEFINER (enregistrer_audit() est
--    révoquée des rôles clients ; un trigger en droits d'appelant échouerait
--    dès qu'un utilisateur authenticated déclenche l'UPDATE source).
-- ---------------------------------------------------------------------------

-- 5.1 Inscriptions — statut boursier (7.2).
create or replace function public.inscriptions_audit_boursier()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.boursier is distinct from new.boursier then
    perform public.enregistrer_audit(
      new.etablissement_id, 'inscription', new.id, 'boursier',
      to_jsonb(old.boursier), to_jsonb(new.boursier), new.fiche_eleve_id, null
    );
  end if;
  return new;
end $$;

drop trigger if exists inscriptions_audit_boursier_trg on public.inscriptions;
create trigger inscriptions_audit_boursier_trg
  after update on public.inscriptions
  for each row execute procedure public.inscriptions_audit_boursier();

-- 5.2 Sanctions — statut, y compris la symétrie levée/annulation aujourd'hui
--     non tracée par sanctions_verifie_validation() (celle-ci ne capture que
--     la validation d'origine IA). Le mécanisme générique suffit : aucune
--     colonne symétrique n'est ajoutée sur sanctions elle-même.
create or replace function public.sanctions_audit_statut()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.statut is distinct from new.statut then
    perform public.enregistrer_audit(
      new.etablissement_id, 'sanction', new.id, 'statut',
      to_jsonb(old.statut), to_jsonb(new.statut), new.fiche_eleve_id, null
    );
  end if;
  return new;
end $$;

drop trigger if exists sanctions_audit_statut_trg on public.sanctions;
create trigger sanctions_audit_statut_trg
  after update on public.sanctions
  for each row execute procedure public.sanctions_audit_statut();

-- 5.3 Congés — CHAQUE transition (le bug coalesce() de conges_verifie_
--     validation, qui ne capture que la PREMIÈRE validation sur valide_par/
--     date_validation, n'est pas corrigé ici : hors périmètre. Le journal,
--     lui, capture chaque transition indépendamment de ce bug).
create or replace function public.conges_audit_statut()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.statut is distinct from new.statut then
    perform public.enregistrer_audit(
      new.etablissement_id, 'conge', new.id, 'statut',
      to_jsonb(old.statut), to_jsonb(new.statut)
    );
  end if;
  return new;
end $$;

drop trigger if exists conges_audit_statut_trg on public.conges;
create trigger conges_audit_statut_trg
  after update on public.conges
  for each row execute procedure public.conges_audit_statut();

-- 5.4 Paiements — statuts, sur les 4 tables où la transition existe
--     réellement aujourd'hui. Remboursement ('rembourse') explicitement
--     exclu : ce flux n'existe nulle part dans le code (confirmé à l'état
--     des lieux) ; rien n'est construit pour l'anticiper.
create or replace function public.transactions_cinetpay_audit_statut()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.statut is distinct from new.statut then
    perform public.enregistrer_audit(
      new.etablissement_id, 'transaction_cinetpay', new.id, 'statut',
      to_jsonb(old.statut), to_jsonb(new.statut)
    );
  end if;
  return new;
end $$;

drop trigger if exists transactions_cinetpay_audit_statut_trg on public.transactions_cinetpay;
create trigger transactions_cinetpay_audit_statut_trg
  after update on public.transactions_cinetpay
  for each row execute procedure public.transactions_cinetpay_audit_statut();

create or replace function public.paiements_audit_statut()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.statut is distinct from new.statut then
    perform public.enregistrer_audit(
      new.etablissement_id, 'paiement_marketplace', new.id, 'statut',
      to_jsonb(old.statut), to_jsonb(new.statut)
    );
  end if;
  return new;
end $$;

drop trigger if exists paiements_audit_statut_trg on public.paiements;
create trigger paiements_audit_statut_trg
  after update on public.paiements
  for each row execute procedure public.paiements_audit_statut();

create or replace function public.commandes_audit_statut()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.statut is distinct from new.statut then
    perform public.enregistrer_audit(
      new.etablissement_id, 'commande_marketplace', new.id, 'statut',
      to_jsonb(old.statut), to_jsonb(new.statut)
    );
  end if;
  return new;
end $$;

drop trigger if exists commandes_audit_statut_trg on public.commandes;
create trigger commandes_audit_statut_trg
  after update on public.commandes
  for each row execute procedure public.commandes_audit_statut();

create or replace function public.encaissements_audit_statut()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.statut is distinct from new.statut then
    perform public.enregistrer_audit(
      new.etablissement_id, 'encaissement_scolarite', new.id, 'statut',
      to_jsonb(old.statut), to_jsonb(new.statut), new.fiche_eleve_id, null
    );
  end if;
  return new;
end $$;

drop trigger if exists encaissements_audit_statut_trg on public.encaissements_scolarite;
create trigger encaissements_audit_statut_trg
  after update on public.encaissements_scolarite
  for each row execute procedure public.encaissements_audit_statut();

-- Abonnements Premium élève : pas de colonne « statut » au sens strict, mais
-- la même mutation-en-place sans trace identifiée à l'état des lieux (une
-- ligne réutilisée à chaque renouvellement, jamais un historique). Guard sur
-- expire_le ; capture aussi montant/formule pour reconstituer le changement.
create or replace function public.abonnements_premium_eleve_audit_renouvellement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.expire_le is distinct from new.expire_le then
    perform public.enregistrer_audit(
      null, 'abonnement_premium_eleve', new.id, 'renouvellement',
      jsonb_build_object(
        'expire_le', old.expire_le,
        'montant_dernier_paiement', old.montant_dernier_paiement,
        'formule', old.formule
      ),
      jsonb_build_object(
        'expire_le', new.expire_le,
        'montant_dernier_paiement', new.montant_dernier_paiement,
        'formule', new.formule
      ),
      new.fiche_eleve_id, null
    );
  end if;
  return new;
end $$;

drop trigger if exists abonnements_premium_eleve_audit_renouvellement_trg on public.abonnements_premium_eleve;
create trigger abonnements_premium_eleve_audit_renouvellement_trg
  after update on public.abonnements_premium_eleve
  for each row execute procedure public.abonnements_premium_eleve_audit_renouvellement();

-- 5.5 Signalement de message — copie horodatée indépendante (20.4). Une VRAIE
--     copie, pas une FK vers messages_groupe : messages_groupe est en
--     'on delete cascade' depuis etablissements, et le contenu y est déjà
--     verrouillé/soft-delete-only côté M9 -- mais une purge future à un autre
--     niveau ne doit jamais pouvoir effacer la preuve. Lookup en SECURITY
--     DEFINER : même raison que signalements_verifie_tenant() juste au-dessus
--     dans le M9 patch -- un lookup soumis à la RLS de l'appelant risquerait
--     de renvoyer une ligne vide si un cas futur permet de signaler un
--     message hors de la visibilité RLS immédiate du signalant, corrompant
--     silencieusement la copie plutôt que d'échouer bruyamment.
create or replace function public.signalements_audit_copie_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_message public.messages_groupe;
begin
  select * into v_message from public.messages_groupe where id = new.message_id;
  perform public.enregistrer_audit(
    new.etablissement_id, 'message_groupe', new.message_id, 'signalement_copie',
    null,
    jsonb_build_object(
      'contenu', v_message.contenu,
      'auteur_id', v_message.auteur_id,
      'created_at', v_message.created_at,
      'signalement_id', new.id,
      'motif_signalement', new.motif
    ),
    null, v_message.groupe_id
  );
  return new;
end $$;

drop trigger if exists signalements_audit_copie_message_trg on public.signalements_message;
create trigger signalements_audit_copie_message_trg
  after insert on public.signalements_message
  for each row execute procedure public.signalements_audit_copie_message();

-- ---------------------------------------------------------------------------
-- 6. Rétention (§34.2 -- rien codé en dur). Valeur PLACEHOLDER, à trancher
--    par le porteur avant activation, comme à chaque étape de la facturation.
-- ---------------------------------------------------------------------------
insert into public.parametres_globaux (cle, valeur, description) values
  (
    'duree_retention_journal_audit',
    '{"jours": 1825}'::jsonb,
    'Durée de conservation du journal d''audit (§34.2), en jours. PLACEHOLDER (5 ans) -- à trancher par le porteur avant activation. Aucun job de purge automatique n''existe encore (aucune infra cron dans ce dépôt) ; cette valeur documente la durée requise par §34.2, indépendamment de son application effective.'
  )
on conflict (cle) do nothing;
