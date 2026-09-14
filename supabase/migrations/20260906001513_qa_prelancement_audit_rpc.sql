-- ============================================================================
-- EcoShop — QA pré-lancement — Audit sécurité RPC (volet complet, toutes RPC)
--
-- Contexte : suite à la trouvaille D6 (solde_scolarite sans vérification
-- d'autorisation depuis M15quater), balayage systématique de TOUTES les RPC
-- du projet (pas seulement celles autour de M15quater), pour deux classes de
-- défaut :
--   (a) absence totale de vérification d'autorisation ;
--   (b) vérification présente mais contournable silencieusement — l'anti-
--       patron `IF NOT public.a_permission(...)` (ou toute fonction dérivée :
--       `est_rh`/`est_comptable`/`est_comptable_ecriture`/`est_comm`/
--       `est_admin_gsg`) sans `coalesce(..., false)`. Confirmé : ces fonctions
--       PEUVENT renvoyer NULL — pas seulement false — dès que l'appelant n'a
--       encore aucun `role_racine` choisi (état NORMAL de tout compte fraîche-
--       ment authentifié, cf. `profiles.role_racine` : « null tant que le
--       rôle n'est pas choisi »). `IF NULL THEN` ne déclenche jamais la
--       branche en PL/pgSQL (contrairement à une clause RLS USING/WITH CHECK,
--       où Postgres traite NULL comme un refus automatique) — c'est
--       exactement l'anti-patron déjà corrigé et documenté en D5
--       (generer_bulletins_classe) et D6 (solde_scolarite).
--
-- Rapport complet : voir la synthèse remise au porteur de projet. Chaque
-- correctif ci-dessous réutilise la frontière d'autorisation DÉJÀ VALIDÉE
-- pour une fonction équivalente du même domaine — aucun nouveau patron
-- d'autorisation n'est inventé.
--
-- Migration idempotente. Non poussée tant que le rapport n'est pas approuvé.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. CRITIQUE — calculer_moyenne_eleve / calculer_moyenne_classe (M6)
--
-- Aucune vérification d'autorisation : tout compte authentifié pouvait lire
-- la moyenne (donnée personnelle scolaire) de N'IMPORTE QUELLE fiche/classe
-- de N'IMPORTE QUEL établissement en connaissant seulement son UUID —
-- exactement la même famille de fuite que D6 (solde_scolarite), mais sur les
-- notes plutôt que sur les paiements. Corrigé avec la frontière déjà
-- retenue pour cette exacte donnée ailleurs dans M6 (`note_visible`,
-- `bulletin_visible`) et déjà validée par D6 (`solde_scolarite`) :
-- `est_personnel(etablissement) OR fiche_visible/classe_visible`.
--
-- `auth.uid() is not null and` conservé : ces deux fonctions sont appelées en
-- chaîne interne par des fonctions déjà `service_role`-only (M7
-- `calculer_score_decrochage`→`materialiser_risque_reussite`/
-- `generer_alertes_decrochage`), où `auth.uid()` est NULL (pas de session
-- utilisateur) — même garde déjà en place partout ailleurs dans le projet où
-- une fonction sert à la fois un appel client direct et une chaîne serveur
-- (ex. `est_rh`/`est_comm` en M8/M9).
-- ---------------------------------------------------------------------------
create or replace function public.calculer_moyenne_eleve(
  p_fiche uuid,
  p_matiere uuid default null,
  p_periode uuid default null
)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etablissement uuid;
begin
  select etablissement_id into v_etablissement from public.fiches_eleves where id = p_fiche;

  if v_etablissement is not null
     and auth.uid() is not null
     and not coalesce(public.est_personnel(v_etablissement), false)
     and not coalesce(public.fiche_visible(p_fiche), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return (
    select case
      when sum(e.coefficient) is null or sum(e.coefficient) = 0 then null
      else round((sum(n.valeur / e.bareme * e.coefficient) / sum(e.coefficient)) * 20, 2)
    end
    from public.notes n
    join public.evaluations e on e.id = n.evaluation_id
    where n.fiche_eleve_id = p_fiche
      and n.deleted_at is null and e.deleted_at is null
      and not n.absent
      and e.statut <> 'brouillon'
      and (p_matiere is null or e.programme_matiere_id = p_matiere)
      and (p_periode is null or e.periode_id = p_periode)
  );
end;
$$;

create or replace function public.calculer_moyenne_classe(
  p_classe uuid,
  p_matiere uuid default null,
  p_periode uuid default null
)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etablissement uuid;
begin
  select etablissement_id into v_etablissement from public.classes where id = p_classe;

  if v_etablissement is not null
     and auth.uid() is not null
     and not coalesce(public.est_personnel(v_etablissement), false)
     and not coalesce(public.classe_visible(p_classe), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return (
    select round(avg(m), 2)
    from (
      select public.calculer_moyenne_eleve(f.id, p_matiere, p_periode) as m
      from public.classes c
      join public.inscriptions i on i.classe_id = c.id and i.deleted_at is null and i.statut = 'active'
      join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
      where c.id = p_classe
    ) moyennes
    where m is not null
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. CRITIQUE — Comptabilité (M14) : journal, grand livre, balance,
-- génération de balance (ÉCRITURE), export, et les 4 fonctions IA
-- comptables — AUCUNE des 9 fonctions ne vérifiait quoi que ce soit, malgré
-- `est_comptable`/`est_comptable_ecriture` et les permissions
-- `comptabilite.lire`/`comptabilite.ecrire` déjà prévues et déjà utilisées
-- par les policies RLS des tables sous-jacentes (`plans_comptables`,
-- `journaux`, `ecritures_comptables`, `balances`) — ces fonctions
-- `security definer` contournent cette RLS, donc rien ne protégeait
-- l'appel direct. Tout compte authentifié pouvait lire le journal, le grand
-- livre, la balance et les prévisions de trésorerie complets de N'IMPORTE
-- QUEL établissement, et `generer_balance` pouvait ÉCRIRE dans `balances`
-- pour n'importe quel établissement.
--
-- Corrigé avec la frontière déjà validée sur les mêmes tables (policies
-- `plans_comptables_select`/`ecritures_select` : `est_comptable` ; policies
-- `*_write` : `est_comptable_ecriture`). `auth.uid() is not null and`
-- nécessaire : ces 9 fonctions sont accordées à `service_role` en plus de
-- `authenticated` (export/rapports depuis une Edge Function serveur).
-- `balance_comptable` accepte aussi `est_comptable_ecriture` en repli : elle
-- est appelée en interne par `generer_balance` (qui n'a déjà vérifié que le
-- droit d'ÉCRITURE), et un compte comptable en écriture doit pouvoir lire le
-- résultat qu'il vient de générer.
-- ---------------------------------------------------------------------------
create or replace function public.journal_comptable(
  p_etablissement uuid, p_journal uuid, p_debut date, p_fin date)
returns table (
  date_ecriture date,
  libelle text,
  compte_debit text,
  compte_credit text,
  montant numeric,
  piece_justificative text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  select e.date_ecriture, e.libelle, d.code, c.code, e.montant, e.piece_justificative
  from public.ecritures_comptables e
  join public.plans_comptables d on d.id = e.compte_debit_id
  join public.plans_comptables c on c.id = e.compte_credit_id
  where e.etablissement_id = p_etablissement
    and e.journal_id = p_journal
    and e.deleted_at is null
    and e.date_ecriture between p_debut and p_fin
  order by e.date_ecriture, e.created_at;
end;
$$;

create or replace function public.grand_livre(
  p_etablissement uuid, p_compte uuid, p_debut date, p_fin date)
returns table (
  date_ecriture date,
  libelle text,
  piece_justificative text,
  sens text,
  montant numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  select e.date_ecriture, e.libelle, e.piece_justificative, 'debit', e.montant
  from public.ecritures_comptables e
  where e.etablissement_id = p_etablissement
    and e.compte_debit_id = p_compte
    and e.deleted_at is null
    and e.date_ecriture between p_debut and p_fin
  union all
  select e.date_ecriture, e.libelle, e.piece_justificative, 'credit', e.montant
  from public.ecritures_comptables e
  where e.etablissement_id = p_etablissement
    and e.compte_credit_id = p_compte
    and e.deleted_at is null
    and e.date_ecriture between p_debut and p_fin
  order by date_ecriture;
end;
$$;

create or replace function public.balance_comptable(p_etablissement uuid, p_date date)
returns table (
  compte_id uuid,
  code text,
  intitule text,
  total_debit numeric,
  total_credit numeric,
  solde_debit numeric,
  solde_credit numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and not coalesce(public.est_comptable(p_etablissement), false)
     and not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  with mouvements as (
    select compte_debit_id as compte_id, montant as debit, 0::numeric as credit
    from public.ecritures_comptables
    where etablissement_id = p_etablissement and deleted_at is null and date_ecriture <= p_date
    union all
    select compte_credit_id as compte_id, 0::numeric, montant
    from public.ecritures_comptables
    where etablissement_id = p_etablissement and deleted_at is null and date_ecriture <= p_date
  )
  select pc.id, pc.code, pc.intitule,
         coalesce(sum(m.debit), 0)  as total_debit,
         coalesce(sum(m.credit), 0) as total_credit,
         greatest(coalesce(sum(m.debit),0) - coalesce(sum(m.credit),0), 0) as solde_debit,
         greatest(coalesce(sum(m.credit),0) - coalesce(sum(m.debit),0), 0) as solde_credit
  from public.plans_comptables pc
  left join mouvements m on m.compte_id = pc.id
  where pc.etablissement_id = p_etablissement and pc.deleted_at is null
  group by pc.id, pc.code, pc.intitule
  order by pc.code;
end;
$$;

create or replace function public.generer_balance(p_etablissement uuid, p_date date)
returns setof public.balances
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;

  insert into public.balances (etablissement_id, compte_id, date_balance, solde_debit, solde_credit)
  select p_etablissement, b.compte_id, p_date, b.solde_debit, b.solde_credit
  from public.balance_comptable(p_etablissement, p_date) b
  on conflict (compte_id, date_balance) do update
    set solde_debit = excluded.solde_debit,
        solde_credit = excluded.solde_credit;

  return query
    select * from public.balances
    where etablissement_id = p_etablissement and date_balance = p_date
    order by compte_id;
end;
$$;

create or replace function public.exporter_journal_json(
  p_etablissement uuid, p_journal uuid, p_debut date, p_fin date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return (
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    from (select * from public.journal_comptable(p_etablissement, p_journal, p_debut, p_fin)) r
  );
end;
$$;

create or replace function public.detecter_anomalies_comptables(p_etablissement uuid)
returns table (
  ecriture_id uuid,
  date_ecriture date,
  libelle text,
  montant numeric,
  anomalie text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  select e.id, e.date_ecriture, e.libelle, e.montant,
         case when e.montant >= 10000000 then 'montant_eleve' else 'double_saisie' end
  from public.ecritures_comptables e
  where e.etablissement_id = p_etablissement
    and e.deleted_at is null
    and ( e.montant >= 10000000
          or exists (
            select 1 from public.ecritures_comptables e2
            where e2.etablissement_id = p_etablissement
              and e2.id <> e.id
              and e2.compte_debit_id = e.compte_debit_id
              and e2.compte_credit_id = e.compte_credit_id
              and e2.montant = e.montant
              and e2.date_ecriture = e.date_ecriture
              and e2.deleted_at is null
          )
        )
  order by e.date_ecriture desc;
end;
$$;

create or replace function public.predire_tresorerie(p_etablissement uuid, p_jours int default 30)
returns table (jour date, solde_projete numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  with flux as (
    select e.date_ecriture as jour,
           coalesce(sum(e.montant) filter (where d.type in ('banque','caisse')), 0)
         - coalesce(sum(e.montant) filter (where c.type in ('banque','caisse')), 0) as net
    from public.ecritures_comptables e
    join public.plans_comptables d on d.id = e.compte_debit_id
    join public.plans_comptables c on c.id = e.compte_credit_id
    where e.etablissement_id = p_etablissement and e.deleted_at is null
      and e.date_ecriture >= current_date - 30
    group by 1
  ),
  solde_actuel as (
    select coalesce(sum(e.montant) filter (where d.type in ('banque','caisse')), 0)
         - coalesce(sum(e.montant) filter (where c.type in ('banque','caisse')), 0) as s
    from public.ecritures_comptables e
    join public.plans_comptables d on d.id = e.compte_debit_id
    join public.plans_comptables c on c.id = e.compte_credit_id
    where e.etablissement_id = p_etablissement and e.deleted_at is null
  ),
  moyenne as (select coalesce(avg(net), 0) as m from flux),
  series as (
    select generate_series(current_date, current_date + p_jours, '1 day')::date as jour
  )
  select s.jour,
         (select s from solde_actuel) + (select m from moyenne) * (row_number() over (order by s.jour)) as solde_projete
  from series s
  order by s.jour;
end;
$$;

create or replace function public.recommander_ecritures(p_etablissement uuid)
returns table (
  libelle text,
  compte_debit text,
  compte_credit text,
  montant numeric,
  mois_distincts bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  select e.libelle, d.code, c.code, max(e.montant),
         count(distinct date_trunc('month', e.date_ecriture)) as mois_distincts
  from public.ecritures_comptables e
  join public.plans_comptables d on d.id = e.compte_debit_id
  join public.plans_comptables c on c.id = e.compte_credit_id
  where e.etablissement_id = p_etablissement and e.deleted_at is null
  group by e.libelle, d.code, c.code
  having count(distinct date_trunc('month', e.date_ecriture)) >= 2
  order by mois_distincts desc;
end;
$$;

create or replace function public.analyser_tendances(p_etablissement uuid, p_mois int default 12)
returns table (mois date, total_charges numeric, total_produits numeric, solde_net numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comptable(p_etablissement), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;

  return query
  select date_trunc('month', e.date_ecriture)::date as mois,
         coalesce(sum(e.montant) filter (where d.type = 'charge'), 0)  as total_charges,
         coalesce(sum(e.montant) filter (where c.type = 'produit'), 0) as total_produits,
         coalesce(sum(e.montant) filter (where c.type = 'produit'), 0)
       - coalesce(sum(e.montant) filter (where d.type = 'charge'), 0)  as solde_net
  from public.ecritures_comptables e
  join public.plans_comptables d on d.id = e.compte_debit_id
  join public.plans_comptables c on c.id = e.compte_credit_id
  where e.etablissement_id = p_etablissement and e.deleted_at is null
    and e.date_ecriture >= (date_trunc('month', current_date) - make_interval(months => p_mois))
  group by 1
  order by 1;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. CRITIQUE — analyse_comportement / calculer_score_decrochage /
-- recommander_sanction_educative (M7)
--
-- AUCUNE vérification : tout compte authentifié pouvait lire les absences,
-- retards, sanctions actives, score de décrochage et recommandation
-- disciplinaire de N'IMPORTE QUEL élève (mineur) de N'IMPORTE QUEL
-- établissement. Corrigé avec la frontière déjà retenue pour cette exacte
-- donnée ailleurs dans le module (`presence_visible`/`sanction_visible` :
-- `est_personnel(etablissement) OR fiche_visible`).
--
-- `auth.uid() is not null and` nécessaire pour `analyse_comportement` et
-- `calculer_score_decrochage` : appelées en interne par
-- `generer_alertes_decrochage`/`materialiser_risque_reussite`
-- (`service_role` uniquement, `auth.uid()` NULL). `recommander_sanction_
-- educative` n'a aucun appelant serveur connu, même garde ajoutée par
-- cohérence avec ses deux fonctions sœurs du même trio descriptif/
-- prédictif/prescriptif.
-- ---------------------------------------------------------------------------
create or replace function public.analyse_comportement(p_fiche uuid, p_annee uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etablissement uuid;
begin
  select etablissement_id into v_etablissement from public.fiches_eleves where id = p_fiche;

  if v_etablissement is not null
     and auth.uid() is not null
     and not coalesce(public.est_personnel(v_etablissement), false)
     and not coalesce(public.fiche_visible(p_fiche), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'absences_non_justifiees',
      (select count(*) from public.presences
       where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
         and statut = 'absent' and not justifie and deleted_at is null),
    'absences_justifiees',
      (select count(*) from public.presences
       where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
         and statut = 'absent' and justifie and deleted_at is null),
    'retards_non_justifies',
      (select count(*) from public.retards
       where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
         and not justifie and deleted_at is null),
    'retards_justifies',
      (select count(*) from public.retards
       where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
         and justifie and deleted_at is null),
    'retard_moyen_minutes',
      (select round(coalesce(avg(minutes_retard), 0), 1) from public.retards
       where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee and deleted_at is null),
    'sanctions_actives',
      (select count(*) from public.sanctions
       where fiche_eleve_id = p_fiche and statut in ('notifiee', 'executee') and deleted_at is null)
  );
end;
$$;

create or replace function public.calculer_score_decrochage(p_fiche uuid, p_annee uuid)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etablissement uuid;
  v_taux_abs numeric := 0;
  v_retards numeric := 0;
  v_moyenne numeric;
  v_score numeric;
begin
  select etablissement_id into v_etablissement from public.fiches_eleves where id = p_fiche;

  if v_etablissement is not null
     and auth.uid() is not null
     and not coalesce(public.est_personnel(v_etablissement), false)
     and not coalesce(public.fiche_visible(p_fiche), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  select count(*) filter (where statut = 'absent' and not justifie)::numeric
       / nullif(count(*), 0)
    into v_taux_abs
  from public.presences
  where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee and deleted_at is null;

  select count(*) into v_retards
  from public.retards
  where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
    and not justifie and deleted_at is null;

  select public.calculer_moyenne_eleve(p_fiche, null, null) into v_moyenne;

  v_score := 0.5 * coalesce(v_taux_abs, 0)
           + 0.2 * least(coalesce(v_retards, 0) / 10.0, 1)
           + case
               when v_moyenne is null then 0.15
               else 0.3 * greatest(1 - v_moyenne / 20.0, 0)
             end;

  return round(greatest(least(v_score, 1), 0), 4);
end;
$$;

create or replace function public.recommander_sanction_educative(p_fiche uuid, p_annee uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etablissement uuid;
  v_abs int;
  v_ret int;
  v_moyenne numeric;
begin
  select etablissement_id into v_etablissement from public.fiches_eleves where id = p_fiche;

  if v_etablissement is not null
     and auth.uid() is not null
     and not coalesce(public.est_personnel(v_etablissement), false)
     and not coalesce(public.fiche_visible(p_fiche), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  select count(*) into v_abs from public.presences
  where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
    and statut = 'absent' and not justifie and deleted_at is null;

  select count(*) into v_ret from public.retards
  where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
    and not justifie and deleted_at is null;

  select public.calculer_moyenne_eleve(p_fiche, null, null) into v_moyenne;

  return jsonb_build_object(
    'type_recommande', case
      when v_abs >= 5 then 'entretien_famille_et_tutorat'
      when v_ret >= 8 then 'suivi_ponctualite'
      when v_moyenne is not null and v_moyenne < 8 then 'soutien_scolaire'
      else 'aucune'
    end,
    'niveau_priorite', case when v_abs >= 5 then 'eleve' when v_ret >= 8 then 'moyen' else 'faible' end,
    'motif', jsonb_build_object('absences_non_justifiees', v_abs, 'retards_non_justifies', v_ret, 'moyenne', v_moyenne),
    'non_punitif', true,
    'a_valider_par', 'direction_ou_conseil_classe'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. CRITIQUE — verifications_reinscription (M15quater)
--
-- AUCUNE vérification propre : `sanction_active` et `boursier_precedent`
-- n'étaient protégés par RIEN — tout compte authentifié apprenait si
-- N'IMPORTE QUEL élève avait une sanction disciplinaire active, en
-- connaissant seulement son UUID (`p_annee_precedente_id` n'a même pas
-- besoin d'être réel pour ce champ). `impaye` n'était protégé
-- qu'accidentellement par le `raise` interne de `solde_scolarite` (D6) — et
-- ce chemin est lui-même contournable en passant un `p_annee_precedente_id`
-- ne correspondant à aucune inscription réelle (l'EXISTS ne parcourt alors
-- aucune ligne, `solde_scolarite` n'est jamais appelée).
--
-- Corrigé avec EXACTEMENT la même frontière que `creer_reinscription`/
-- `creer_inscription_nouvel_eleve` (fonctions du même flux, appelées juste
-- avant/après par le même personnel) : `a_permission(...'scolarite.
-- inscription.gerer') OR est_direction(...)`.
-- ---------------------------------------------------------------------------
create or replace function public.verifications_reinscription(p_fiche_eleve_id uuid, p_annee_precedente_id uuid)
returns table(impaye boolean, sanction_active boolean, boursier_precedent boolean)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = p_fiche_eleve_id;
  if v_etab is null then
    raise exception 'FICHE_INTROUVABLE' using errcode = '23514';
  end if;

  if not (coalesce(public.a_permission(v_etab, 'scolarite.inscription.gerer'), false)
          or coalesce(public.est_direction(v_etab), false)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return query
  select
    exists (
      select 1 from public.inscriptions i
      where i.fiche_eleve_id = p_fiche_eleve_id and i.annee_scolaire_id = p_annee_precedente_id and i.deleted_at is null
        and (select solde from public.solde_scolarite(i.id)) > 0
    ),
    exists (
      select 1 from public.sanctions s
      where s.fiche_eleve_id = p_fiche_eleve_id and s.deleted_at is null and s.statut in ('notifiee', 'executee')
    ),
    exists (
      select 1 from public.inscriptions i
      where i.fiche_eleve_id = p_fiche_eleve_id and i.annee_scolaire_id = p_annee_precedente_id
        and i.deleted_at is null and i.boursier
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. CRITIQUE — creer_inscription_nouvel_eleve / creer_reinscription
-- (M15quater) : anti-patron NULL, exactement le patron décrit en 2(b).
--
-- `IF NOT (a_permission(...) OR est_direction(...))` : si `a_permission`
-- renvoie NULL (compte sans `role_racine` choisi) ET `est_direction` est
-- false, `NULL OR false = NULL`, `NOT NULL = NULL`, la levée d'exception ne
-- se déclenche jamais. Écriture non autorisée : création de fiche élève +
-- inscription pour N'IMPORTE QUEL établissement, par un compte qui vient
-- tout juste de s'authentifier sans avoir encore choisi de rôle.
-- ---------------------------------------------------------------------------
create or replace function public.creer_inscription_nouvel_eleve(
  p_etablissement uuid,
  p_nom text,
  p_prenom text,
  p_date_naissance date,
  p_classe_id uuid,
  p_annee_scolaire_id uuid,
  p_sexe text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_classe_etab uuid;
  v_slug text;
  v_prefixe text;
  v_compteur int;
  v_matricule text;
  v_fiche_id uuid;
begin
  if not (coalesce(public.a_permission(p_etablissement, 'scolarite.inscription.gerer'), false)
          or coalesce(public.est_direction(p_etablissement), false)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  select etablissement_id into v_classe_etab from public.classes where id = p_classe_id;
  if v_classe_etab is distinct from p_etablissement then
    raise exception 'CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select slug into v_slug from public.etablissements where id = p_etablissement;
  v_prefixe := upper(left(regexp_replace(coalesce(v_slug, 'ecs'), '[^a-zA-Z0-9]', '', 'g'), 4));

  select count(*) into v_compteur from public.fiches_eleves where etablissement_id = p_etablissement;
  v_matricule := v_prefixe || '-' || lpad((v_compteur + 1)::text, 5, '0');

  insert into public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, sexe)
  values (p_etablissement, v_matricule, p_nom, p_prenom, p_date_naissance, p_sexe)
  returning id into v_fiche_id;

  insert into public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
  values (p_etablissement, v_fiche_id, p_classe_id, p_annee_scolaire_id, 'active');

  return v_fiche_id;
end;
$$;

create or replace function public.creer_reinscription(
  p_fiche_eleve_id uuid,
  p_classe_id uuid,
  p_annee_scolaire_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_etab uuid;
  v_inscription_id uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = p_fiche_eleve_id;
  if v_etab is null then
    raise exception 'FICHE_INTROUVABLE' using errcode = '23514';
  end if;

  if not (coalesce(public.a_permission(v_etab, 'scolarite.inscription.gerer'), false)
          or coalesce(public.est_direction(v_etab), false)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  insert into public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
  values (v_etab, p_fiche_eleve_id, p_classe_id, p_annee_scolaire_id, 'active')
  returning id into v_inscription_id;

  return v_inscription_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. CRITIQUE — M8 RH : anti-patron NULL via est_rh (même patron que #5).
--
-- `est_rh(etab) = est_direction(etab) OR a_permission(etab, 'rh.employe.
-- gerer')` peut renvoyer NULL (a_permission NULL, est_direction false).
-- Chaque `IF auth.uid() IS NOT NULL AND NOT public.est_rh(...)` ci-dessous
-- est déjà la bonne garde pour `auth.uid()` — il ne manquait que le
-- `coalesce` sur `est_rh(...)`. Impact : données RH/salariales personnelles
-- (effectifs, masse salariale, score de turnover, recommandation de
-- formation, planning de remplacement) de N'IMPORTE QUEL établissement,
-- lisibles par un compte qui vient de s'authentifier sans rôle choisi.
-- ---------------------------------------------------------------------------
create or replace function public.conges_verifie_validation()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.statut in ('valide', 'refuse') then
    if auth.uid() is not null and not coalesce(public.est_rh(new.etablissement_id), false) then
      raise exception 'VALIDATION_RH_REQUISE' using errcode = '42501';
    end if;
    new.valide_par := coalesce(new.valide_par, auth.uid());
    new.date_validation := coalesce(new.date_validation, now());
  end if;
  return new;
end $$;

create or replace function public.analyser_effectifs(p_etablissement uuid)
returns table (
  categorie text,
  effectif bigint,
  anciennete_moyenne_jours numeric,
  masse_salariale_base numeric
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_rh(p_etablissement), false) then
    raise exception 'RH_REQUIS' using errcode = '42501';
  end if;

  return query
  select e.categorie,
         count(*)::bigint,
         round(avg(current_date - e.date_embauche), 1),
         coalesce(sum(c.salaire_base), 0)
  from public.employes e
  left join lateral (
    select c.salaire_base
    from public.contrats c
    where c.employe_id = e.id and c.deleted_at is null and c.actif
      and (c.date_fin is null or c.date_fin >= current_date)
    order by c.date_debut desc
    limit 1
  ) c on true
  where e.etablissement_id = p_etablissement and e.deleted_at is null
  group by e.categorie
  order by e.categorie;
end $$;

create or replace function public.calculer_score_turnover(p_employe uuid)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_profile uuid;
  v_embauche date;
  v_charge int;
  v_abs_injustifiees int;
  v_abs_maladie int;
  v_risk_abs numeric;
  v_risk_anciennete numeric;
  v_risk_charge numeric;
  v_risk_contrat numeric;
  v_type public.type_contrat;
  v_fin date;
begin
  select etablissement_id, profile_id, date_embauche
    into v_etab, v_profile, v_embauche
  from public.employes where id = p_employe and deleted_at is null;

  if v_etab is null then
    raise exception 'EMPLOYE_INTROUVABLE' using errcode = 'P0002';
  end if;

  if auth.uid() is not null and not coalesce(public.est_rh(v_etab), false) and auth.uid() <> v_profile then
    raise exception 'RH_REQUIS' using errcode = '42501';
  end if;

  select count(*) into v_abs_injustifiees
  from public.absences_personnel
  where employe_id = p_employe and type = 'injustifiee'
    and date_absence >= current_date - 180 and deleted_at is null;

  select count(*) into v_abs_maladie
  from public.conges
  where employe_id = p_employe and type = 'maladie' and statut = 'valide'
    and date_fin >= current_date - 180 and deleted_at is null;

  v_risk_abs := least(1.0, (v_abs_injustifiees * 2 + v_abs_maladie) / 10.0);

  v_risk_anciennete := case
    when current_date - v_embauche < 365 then 1.0
    when current_date - v_embauche < 730 then 0.6
    else 0.2
  end;

  v_charge := public.charge_horaire(p_employe);
  v_risk_charge := case
    when v_charge = 0 then 0.3
    when v_charge > 30 then 1.0
    when v_charge >= 20 then 0.5
    else 0.1
  end;

  select c.type, c.date_fin into v_type, v_fin
  from public.contrats c
  where c.employe_id = p_employe and c.deleted_at is null and c.actif
    and (c.date_fin is null or c.date_fin >= current_date)
  order by c.date_debut desc limit 1;

  v_risk_contrat := case
    when v_type is null then 0.9
    when v_type = 'cdi' then 0.1
    when v_type in ('cdd', 'vacataire') and v_fin is not null and v_fin <= current_date + 90 then 1.0
    else 0.5
  end;

  return round(greatest(0.0, least(1.0,
    0.4 * v_risk_abs + 0.2 * v_risk_anciennete + 0.2 * v_risk_charge + 0.2 * v_risk_contrat
  ))::numeric, 2);
end $$;

create or replace function public.recommander_formation(p_employe uuid, p_annee uuid)
returns table (programme_matiere_id uuid, code text, libelle text, raison text)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_profile uuid;
  v_pays text;
begin
  select e.etablissement_id, e.profile_id, et.pays_code
    into v_etab, v_profile, v_pays
  from public.employes e
  join public.etablissements et on et.id = e.etablissement_id
  where e.id = p_employe and e.deleted_at is null;

  if v_etab is null then
    raise exception 'EMPLOYE_INTROUVABLE' using errcode = 'P0002';
  end if;

  if auth.uid() is not null and not coalesce(public.est_rh(v_etab), false) and auth.uid() <> v_profile then
    raise exception 'RH_REQUIS' using errcode = '42501';
  end if;

  return query
  select m.id, m.code, m.nom,
         'Matière du référentiel non couverte par l''enseignant'
  from public.programmes_matieres m
  join public.programmes_officiels p on p.id = m.programme_id
  where p.pays_code = v_pays
    and m.statut = 'publie'
    and m.id not in (
      select a.programme_matiere_id
      from public.affectations_enseignants a
      where a.enseignant_profile_id = v_profile
        and a.annee_scolaire_id = p_annee
        and a.programme_matiere_id is not null
        and a.deleted_at is null
    )
  order by m.code;
end $$;

create or replace function public.optimiser_remplacements(p_etablissement uuid, p_date date)
returns table (
  employe_absent_id uuid,
  absent_matricule text,
  remplacant_id uuid,
  remplacant_matricule text
)
language plpgsql stable security definer set search_path = public
as $$
declare
  r record;
begin
  if auth.uid() is not null and not coalesce(public.est_rh(p_etablissement), false) then
    raise exception 'RH_REQUIS' using errcode = '42501';
  end if;

  for r in
    select e.id as employe_id, e.matricule
    from public.employes e
    where e.etablissement_id = p_etablissement
      and e.categorie = 'enseignant'
      and e.statut = 'actif'
      and e.deleted_at is null
      and (
        exists (
          select 1 from public.absences_personnel a
          where a.employe_id = e.id and a.date_absence = p_date and a.deleted_at is null
        )
        or exists (
          select 1 from public.conges c
          where c.employe_id = e.id and c.statut = 'valide' and c.deleted_at is null
            and p_date between c.date_debut and c.date_fin
        )
      )
  loop
    return query
    select r.employe_id, r.matricule, cand.id, cand.matricule
    from (
      select e.id, e.matricule, public.charge_horaire(e.id) as charge
      from public.employes e
      where e.etablissement_id = p_etablissement
        and e.categorie = 'enseignant'
        and e.statut = 'actif'
        and e.deleted_at is null
        and e.id <> r.employe_id
        and not exists (
          select 1 from public.absences_personnel a
          where a.employe_id = e.id and a.date_absence = p_date and a.deleted_at is null
        )
        and not exists (
          select 1 from public.conges c
          where c.employe_id = e.id and c.statut = 'valide' and c.deleted_at is null
            and p_date between c.date_debut and c.date_fin
        )
      order by charge asc, e.matricule asc
      limit 1
    ) cand;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 7. MOYEN — charge_horaire (M8) : aucune vérification (catégorie a).
-- Fuite RH mineure (charge horaire hebdomadaire) de n'importe quel employé
-- de n'importe quel établissement. Corrigé avec la frontière déjà retenue
-- pour cette même donnée (`employe_visible`/`contrat_visible`/
-- `conge_visible` : `est_rh(etablissement) OR profile_id = auth.uid()`).
-- Appelée en interne par `calculer_score_turnover`/`optimiser_remplacements`
-- ci-dessus (déjà RH-vérifiés) : aucune régression attendue.
-- ---------------------------------------------------------------------------
create or replace function public.charge_horaire(p_employe uuid)
returns int
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_profile uuid;
begin
  select etablissement_id, profile_id into v_etab, v_profile
  from public.employes where id = p_employe and deleted_at is null;

  if v_etab is not null
     and auth.uid() is not null
     and not coalesce(public.est_rh(v_etab), false)
     and auth.uid() <> v_profile then
    raise exception 'RH_REQUIS' using errcode = '42501';
  end if;

  return (
    select coalesce(sum(a.volume_horaire_hebdo), 0)::int
    from public.employes e
    join public.affectations_enseignants a on a.enseignant_profile_id = e.profile_id
    where e.id = p_employe and a.deleted_at is null
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. MOYEN — M9 : anti-patron NULL via est_comm (même patron que #5/#6).
-- `notifications_verifie_ecriture` : la garde d'immutabilité des champs
-- protégés (canal/contenu/type/destinataire/etablissement) ne se déclenchait
-- jamais pour un destinataire sans rôle choisi (auto-modification de sa
-- propre notification). `analyser_envois` : statistiques d'engagement
-- (taux de lecture par canal) de n'importe quel établissement lisibles par
-- un tel compte.
-- ---------------------------------------------------------------------------
create or replace function public.notifications_verifie_ecriture()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.date_lecture is distinct from old.date_lecture and new.date_lecture is not null then
    if auth.uid() is not null and auth.uid() <> new.destinataire then
      raise exception 'LECTURE_DESTINATAIRE' using errcode = '42501';
    end if;
  end if;

  if auth.uid() is not null and not coalesce(public.est_comm(new.etablissement_id), false) then
    if new.canal is distinct from old.canal
       or new.contenu is distinct from old.contenu
       or new.type is distinct from old.type
       or new.destinataire is distinct from old.destinataire
       or new.etablissement_id is distinct from old.etablissement_id then
      raise exception 'MODIFICATION_NON_AUTORISEE' using errcode = '42501';
    end if;
  end if;

  return new;
end $$;

create or replace function public.analyser_envois(p_etablissement uuid, p_debut date, p_fin date)
returns table (canal text, nb_envoyes bigint, nb_lus bigint, taux_lecture numeric)
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_comm(p_etablissement), false) then
    raise exception 'COMM_REQUIS' using errcode = '42501';
  end if;

  return query
  select n.canal::text,
         count(*)::bigint,
         count(n.date_lecture)::bigint,
         round((count(n.date_lecture)::numeric / nullif(count(*), 0)), 2)
  from public.notifications n
  where n.etablissement_id = p_etablissement
    and n.deleted_at is null
    and n.created_at::date between p_debut and p_fin
  group by n.canal
  order by n.canal::text;
end $$;

-- ---------------------------------------------------------------------------
-- 9. ÉLEVÉ — detecter_anomalies_commandes (M13) : aucune vérification.
-- Fuite commerciale/financière (montants de commandes, paiements en
-- attente) de n'importe quel établissement. Corrigé avec la frontière déjà
-- retenue sur les MÊMES tables (`commandes_select`/`paiements_select` :
-- `est_membre_actif(etablissement)`). `auth.uid() is not null and`
-- nécessaire : accordée à `service_role` en plus de `authenticated`.
-- ---------------------------------------------------------------------------
create or replace function public.detecter_anomalies_commandes(p_etablissement uuid)
returns table (
  commande_id uuid,
  reference text,
  montant_total numeric,
  paiements_en_attente bigint,
  anomalie text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_membre_actif(p_etablissement), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  return query
  select c.id,
         c.reference,
         c.montant_total,
         (select count(*) from public.paiements p
           where p.commande_id = c.id and p.statut = 'en_attente') as paiements_en_attente,
         case
           when c.montant_total > 1000000 then 'montant_eleve'
           else 'paiement_attente_multiple'
         end as anomalie
  from public.commandes c
  where c.etablissement_id = p_etablissement
    and c.deleted_at is null
    and (c.montant_total > 1000000
         or (select count(*) from public.paiements p
              where p.commande_id = c.id and p.statut = 'en_attente') > 1);
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. MOYEN — M12 : predire_pics_charge (aucune vérification, fuite
-- pédagogique/absentéisme agrégée inter-établissement) et
-- indicateurs_sante_base (aucune vérification, métadonnées d'infrastructure
-- exposées à tout compte authentifié au lieu du seul Administrateur GSG —
-- les codes permission `observabilite.sante.lire`/`observabilite.
-- prediction.lire` existaient déjà dans le catalogue sans jamais être
-- vérifiés). Frontière : `est_personnel` pour la première (comme M10/M11 sur
-- des données équivalentes), `est_admin_gsg` pour la seconde (donnée
-- supra-établissement, pas de notion d'établissement à vérifier — même
-- rôle que pour les autres opérations plateforme, ex. `commercants_insert`).
-- `auth.uid() is not null and` nécessaire : les deux sont accordées à
-- `service_role` en plus de `authenticated`.
-- ---------------------------------------------------------------------------
create or replace function public.indicateurs_sante_base()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ADMIN_GSG_REQUIS' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'collecte_le', now(),
    'taille_base', pg_size_pretty(pg_database_size(current_database())),
    'connexions_actives', (select count(*) from pg_stat_activity where state = 'active'),
    'connexions_totales', (select count(*) from pg_stat_activity),
    'transactions_en_attente', (select count(*) from pg_stat_activity where state = 'idle in transaction'),
    'uptime', (select extract(epoch from (now() - pg_postmaster_start_time()))::bigint)
  );
end;
$$;

create or replace function public.predire_pics_charge(p_etablissement uuid, p_annee uuid)
returns table (
  semaine date,
  nb_evaluations bigint,
  nb_examens bigint,
  absences_30j bigint,
  niveau_charge text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_personnel(p_etablissement), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  return query
  with eval as (
    select date_trunc('week', e.date_evaluation)::date as semaine,
           count(*) as nb_evaluations,
           count(*) filter (where e.type in ('examen_blanc', 'controle')) as nb_examens
    from public.evaluations e
    where e.etablissement_id = p_etablissement
      and e.annee_scolaire_id = p_annee
      and e.deleted_at is null
      and e.date_evaluation >= current_date
    group by 1
  ),
  abs as (
    select date_trunc('week', p.date_presence)::date as semaine,
           count(*) as absences
    from public.presences p
    where p.etablissement_id = p_etablissement
      and p.annee_scolaire_id = p_annee
      and p.deleted_at is null
      and p.statut = 'absent'
      and p.date_presence >= current_date - interval '30 days'
    group by 1
  )
  select coalesce(e.semaine, a.semaine) as semaine,
         coalesce(e.nb_evaluations, 0) as nb_evaluations,
         coalesce(e.nb_examens, 0) as nb_examens,
         coalesce(a.absences, 0) as absences_30j,
         case
           when coalesce(e.nb_examens, 0) >= 2 then 'critique'
           when coalesce(e.nb_evaluations, 0) >= 4 or coalesce(a.absences, 0) >= 10 then 'eleve'
           else 'normal'
         end as niveau_charge
  from eval e
  full join abs a using (semaine)
  order by 1;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. MOYEN — predire_presence (M7) : aucune vérification (donnée agrégée,
-- taux de présence attendu, inter-établissement). Frontière : `est_personnel`
-- (comme le reste du trio M7).
-- ---------------------------------------------------------------------------
create or replace function public.predire_presence(p_etab uuid, p_date date)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.est_personnel(p_etab), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  return greatest(least(
    coalesce((
      select avg(case when statut = 'present' then 1.0 else 0.0 end)
      from public.presences
      where etablissement_id = p_etab and deleted_at is null
    ), 0.9)
    - coalesce((
      select sum(impact_presence) from public.evenements_scolaires
      where etablissement_id = p_etab
        and p_date between date_debut and date_fin
        and deleted_at is null
    ), 0),
  1), 0);
end;
$$;

-- ============================================================================
-- Fin — QA pré-lancement, volet sécurité RPC.
-- ============================================================================
