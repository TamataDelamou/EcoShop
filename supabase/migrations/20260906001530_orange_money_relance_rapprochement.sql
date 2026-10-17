-- ============================================================================
-- EcoShop — REG-02 Orange Money Guinée, lot L7 : relance et rapprochement
-- (docs/REGISTRE.md REG-02)
--
-- 1. RELANCE — une notification Orange peut se perdre (réseau, panne). Une
--    Edge Function planifiée (relancer_paiements_orange_money) reprend les
--    transactions restées en cours et RE-INTERROGE Orange pour chacune :
--      • transactions_mobile_money_a_relancer() : candidates, jamais deux
--        fois la même en moins de 2 minutes (derniere_verification) ;
--      • une transaction sans jeton de paiement depuis 30 min n'a jamais
--        été présentée au payeur : abandonnée (aucun argent n'a bougé) ;
--      • une transaction toujours non confirmée par Orange 24 h après sa
--        création est close « echoue » avec un motif explicite — jamais
--        sans avoir réinterrogé Orange une dernière fois (Edge Function).
--
-- 2. RAPPROCHEMENT — rapprochement_mobile_money() : pour un établissement et
--    un jour, compare les paiements confirmés par Orange aux écritures
--    qu'ils ont produites (encaissements de scolarité, paiements
--    marketplace) et signale toute anomalie, pour contrôle avec le relevé
--    Orange Money. Réservé au personnel de l'établissement et à l'admin GSG.
--
-- Migration idempotente.
-- ============================================================================

alter table public.transactions_mobile_money
  add column if not exists derniere_verification timestamptz,
  add column if not exists nombre_verifications integer not null default 0;

create index if not exists idx_transactions_mm_en_cours
  on public.transactions_mobile_money (created_at)
  where statut in ('initie', 'en_attente');

-- ---------------------------------------------------------------------------
-- 1. Relance (service_role uniquement)
-- ---------------------------------------------------------------------------

-- Abandonne les initiations jamais présentées au payeur (pas de jeton de
-- paiement 30 min après la création) : l'appel à Orange a échoué en cours
-- de route, aucun paiement n'a pu être validé.
create or replace function public.abandonner_initiations_orphelines()
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_nombre integer;
begin
  update public.transactions_mobile_money
     set statut = 'echoue', message = 'INITIATION_INCOMPLETE', traite_le = now()
   where statut = 'initie'
     and pay_token is null
     and created_at < now() - interval '30 minutes';
  get diagnostics v_nombre = row_count;
  return v_nombre;
end;
$$;

-- Candidates à une nouvelle vérification auprès d'Orange. Les marque
-- immédiatement (derniere_verification) pour qu'un second passage
-- concurrent ne les reprenne pas. `a_expirer` = plus de 24 h : si Orange
-- ne confirme toujours pas, l'Edge Function clôt la transaction.
create or replace function public.transactions_mobile_money_a_relancer(p_limite integer default 50)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_resultat jsonb;
begin
  with candidates as (
    select t.id
    from public.transactions_mobile_money t
    where t.statut in ('initie', 'en_attente')
      and t.pay_token is not null
      and t.created_at < now() - interval '2 minutes'
      and (t.derniere_verification is null or t.derniere_verification < now() - interval '2 minutes')
    order by t.derniere_verification nulls first, t.created_at
    limit least(greatest(coalesce(p_limite, 50), 1), 200)
    for update skip locked
  ),
  marquees as (
    update public.transactions_mobile_money t
       set derniere_verification = now(),
           nombre_verifications = t.nombre_verifications + 1
      from candidates c
     where t.id = c.id
    returning t.id, t.sous_compte_id, t.reference_commande, t.montant, t.pay_token, t.created_at
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id,
           'sous_compte_id', m.sous_compte_id,
           'reference_commande', m.reference_commande,
           'montant', m.montant,
           'pay_token', m.pay_token,
           'a_expirer', m.created_at < now() - interval '24 hours'
         ) order by m.created_at), '[]'::jsonb)
    into v_resultat
  from marquees m;

  return v_resultat;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Rapprochement (personnel de l'établissement, admin GSG)
-- ---------------------------------------------------------------------------
create or replace function public.rapprochement_mobile_money(
  p_etablissement_id uuid,
  p_jour date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_debut timestamptz;
  v_fin timestamptz;
  v_fuseau text;
  v_resultat jsonb;
begin
  if not (coalesce(public.est_personnel(p_etablissement_id), false)
          or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  -- Le « jour » est celui de l'établissement (fuseau configuré), pas l'UTC.
  select coalesce(fuseau_horaire, 'Africa/Conakry') into v_fuseau
  from public.etablissements where id = p_etablissement_id;
  v_debut := (p_jour::timestamp at time zone v_fuseau);
  v_fin := ((p_jour + 1)::timestamp at time zone v_fuseau);

  with tx as (
    select t.*
    from public.transactions_mobile_money t
    where t.etablissement_id = p_etablissement_id
      and t.statut = 'reussi'
      and t.traite_le >= v_debut and t.traite_le < v_fin
  ),
  anomalies as (
    -- Paiement confirmé sans l'écriture attendue (ne devrait jamais arriver).
    select jsonb_build_object(
             'type', 'PAIEMENT_SANS_ECRITURE',
             'transaction_id', tx.id,
             'reference_operateur', tx.reference_operateur,
             'montant', tx.montant) as a
    from tx
    where (tx.objet = 'scolarite' and (tx.encaissement_id is null or not exists (
             select 1 from public.encaissements_scolarite e
             where e.id = tx.encaissement_id and e.statut = 'valide' and e.montant = tx.montant)))
       or (tx.objet = 'commande_marketplace' and (tx.paiement_id is null or not exists (
             select 1 from public.paiements p
             where p.id = tx.paiement_id and p.statut = 'reussi' and p.montant = tx.montant)))
    union all
    -- Encaissement « Orange Money » sans transaction confirmée correspondante
    -- (saisie manuelle portant une référence OM:, ou annulation à vérifier).
    select jsonb_build_object(
             'type', 'ENCAISSEMENT_OM_SANS_TRANSACTION',
             'encaissement_id', e.id,
             'reference_paiement', e.reference_paiement,
             'montant', e.montant)
    from public.encaissements_scolarite e
    where e.etablissement_id = p_etablissement_id
      and e.reference_paiement like 'OM:%'
      and e.created_at >= v_debut and e.created_at < v_fin
      and not exists (
        select 1 from public.transactions_mobile_money t2
        where t2.encaissement_id = e.id and t2.statut = 'reussi')
    union all
    -- Encaissement automatique annulé après coup : l'argent est pourtant
    -- arrivé chez Orange, à régulariser (remboursement ou ré-imputation).
    select jsonb_build_object(
             'type', 'ENCAISSEMENT_OM_ANNULE',
             'encaissement_id', e.id,
             'transaction_id', tx.id,
             'montant', e.montant)
    from tx
    join public.encaissements_scolarite e on e.id = tx.encaissement_id
    where e.statut = 'annule'
  )
  select jsonb_build_object(
    'jour', p_jour,
    'devise', (select devise_code from public.etablissements where id = p_etablissement_id),
    'confirmes', jsonb_build_object(
      'nombre', (select count(*) from tx),
      'montant', (select coalesce(sum(montant), 0) from tx),
      'scolarite', (select coalesce(sum(montant), 0) from tx where objet = 'scolarite'),
      'marketplace', (select coalesce(sum(montant), 0) from tx where objet = 'commande_marketplace')
    ),
    'non_aboutis', (
      select count(*) from public.transactions_mobile_money t
      where t.etablissement_id = p_etablissement_id and t.statut = 'echoue'
        and t.traite_le >= v_debut and t.traite_le < v_fin),
    'en_cours', (
      select count(*) from public.transactions_mobile_money t
      where t.etablissement_id = p_etablissement_id and t.statut in ('initie', 'en_attente')),
    'anomalies', (select coalesce(jsonb_agg(a), '[]'::jsonb) from anomalies)
  ) into v_resultat;

  return v_resultat;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Droits
-- ---------------------------------------------------------------------------
revoke all on function public.abandonner_initiations_orphelines() from public, anon, authenticated;
revoke all on function public.transactions_mobile_money_a_relancer(integer) from public, anon, authenticated;
grant execute on function public.abandonner_initiations_orphelines() to service_role;
grant execute on function public.transactions_mobile_money_a_relancer(integer) to service_role;

revoke all on function public.rapprochement_mobile_money(uuid, date) from public, anon;
grant execute on function public.rapprochement_mobile_money(uuid, date) to authenticated;
