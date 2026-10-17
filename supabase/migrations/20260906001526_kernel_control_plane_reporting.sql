-- ============================================================================
-- EcoShop — KER-MUT K2/K3 : reporting vers le Control Plane du Kernel GSG
-- (docs/REGISTRE.md REG-01.2 / REG-01.3, contrat proposé :
--  docs/contrats/KERNEL_CONTROL_PLANE.md)
--
-- Fournit aux deux Edge Functions du Control Plane (kernel-export en
-- poussée, kernel-control-plane en lecture) les seules données qu'elles ont
-- le droit de lire, par des fonctions SECURITY DEFINER réservées au rôle
-- service_role. La garde repose UNIQUEMENT sur les droits EXECUTE (§5),
-- vérifiés avant le changement d'identité : un contrôle interne via
-- est_appel_service() serait inopérant, current_user valant déjà le
-- propriétaire dans le corps d'une fonction SECURITY DEFINER (même constat
-- que 20260906001515, point 8). Aucun rôle client (anon, authenticated) ne
-- peut les appeler.
--
--   1. kernel_export_curseurs  — position d'export par flux (reprise exacte
--                                après coupure réseau).
--   2. kernel_lecture()        — page ordonnée (created_at, id) d'un flux,
--                                données MINIMISÉES (cf. §2).
--   3. kernel_lot_export() / kernel_valider_lot() / kernel_signaler_echec()
--   4. kernel_metriques_cles() — instantané des indicateurs clés.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Curseurs d'export
-- ---------------------------------------------------------------------------
create table if not exists public.kernel_export_curseurs (
  flux text primary key check (flux in ('audit', 'metriques')),
  -- Dernière ligne acquittée par le Kernel (null = rien exporté encore).
  curseur_horodatage timestamptz,
  curseur_id text,
  lignes_exportees bigint not null default 0,
  derniere_reussite timestamptz,
  derniere_tentative timestamptz,
  derniere_erreur text
);

insert into public.kernel_export_curseurs (flux) values ('audit'), ('metriques')
on conflict (flux) do nothing;

alter table public.kernel_export_curseurs enable row level security;

-- Lecture réservée à l'admin GSG (supervision) ; aucune écriture client :
-- seules les fonctions SECURITY DEFINER ci-dessous modifient la table.
drop policy if exists kernel_export_curseurs_select on public.kernel_export_curseurs;
create policy kernel_export_curseurs_select on public.kernel_export_curseurs
  for select using (public.est_admin_gsg());

comment on table public.kernel_export_curseurs is
  'KER-MUT K2 : position d''export incrémental de chaque flux vers le Control Plane du Kernel GSG.';

-- ---------------------------------------------------------------------------
-- 2. Lecture paginée d'un flux — données minimisées
--
-- Audit : JAMAIS ancienne_valeur / nouvelle_valeur (peuvent contenir la
-- copie d'un message de groupe d'élèves mineurs, un statut boursier, un
-- montant nominatif). Ni fiche_eleve_id ni groupe_id : le Control Plane n'a
-- pas besoin de savoir QUEL élève, seulement qu'une action a eu lieu.
--
-- Délai de sécurité de 2 minutes : created_at vaut l'heure de DÉBUT de la
-- transaction ; une transaction longue peut être validée après une autre
-- plus récente. Ne lire que les lignes de plus de 2 minutes évite d'avancer
-- le curseur au-delà d'une ligne pas encore visible (elle serait perdue).
-- ---------------------------------------------------------------------------
create or replace function public.kernel_lecture(
  p_flux text,
  p_apres_horodatage timestamptz default null,
  p_apres_id text default null,
  p_limite integer default 500
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limite integer := least(greatest(coalesce(p_limite, 500), 1), 1000);
  v_borne timestamptz := now() - interval '2 minutes';
  v_lignes jsonb;
begin
  if p_flux = 'audit' then
    select coalesce(jsonb_agg(l order by l->>'horodatage', l->>'id'), '[]'::jsonb)
      into v_lignes
    from (
      select jsonb_build_object(
               'id', a.id::text,
               'horodatage', to_char(a.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
               'etablissement_id', a.etablissement_id,
               'entite', a.entite::text,
               'entite_id', a.entite_id,
               'champ', a.champ,
               'auteur_id', a.auteur_id,
               'origine', case when a.auteur_id is null then 'service' else 'utilisateur' end
             ) as l
      from public.journal_audit a
      where a.created_at < v_borne
        and (p_apres_horodatage is null
             or (a.created_at, a.id) > (p_apres_horodatage, p_apres_id::uuid))
      order by a.created_at, a.id
      limit v_limite
    ) s;

  elsif p_flux = 'metriques' then
    select coalesce(jsonb_agg(l order by (l->>'horodatage'), (l->>'id')::bigint), '[]'::jsonb)
      into v_lignes
    from (
      select jsonb_build_object(
               'id', m.id::text,
               'horodatage', to_char(m.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
               'etablissement_id', m.etablissement_id,
               'metrique', m.metrique,
               'valeur', m.valeur,
               'source', m.source,
               'contexte', m.contexte
             ) as l
      from public.journal_metriques m
      where m.created_at < v_borne
        and (p_apres_horodatage is null
             or (m.created_at, m.id) > (p_apres_horodatage, p_apres_id::bigint))
      order by m.created_at, m.id
      limit v_limite
    ) s;

  else
    raise exception 'KERNEL_FLUX_INCONNU: %', p_flux using errcode = '22023';
  end if;

  return v_lignes;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Export incrémental
-- ---------------------------------------------------------------------------
create or replace function public.kernel_lot_export(p_flux text, p_limite integer default 500)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c public.kernel_export_curseurs;
  v_lignes jsonb;
begin
  update public.kernel_export_curseurs
     set derniere_tentative = now()
   where flux = p_flux
  returning * into c;

  if not found then
    raise exception 'KERNEL_FLUX_INCONNU: %', p_flux using errcode = '22023';
  end if;

  v_lignes := public.kernel_lecture(p_flux, c.curseur_horodatage, c.curseur_id, p_limite);

  return jsonb_build_object(
    'flux', p_flux,
    'apres', jsonb_build_object('horodatage', c.curseur_horodatage, 'id', c.curseur_id),
    'lignes', v_lignes
  );
end;
$$;

-- Avance le curseur APRÈS acquittement du Kernel. Ne recule jamais : un
-- acquittement tardif d'un lot déjà dépassé est ignoré.
create or replace function public.kernel_valider_lot(
  p_flux text,
  p_horodatage timestamptz,
  p_id text,
  p_nb_lignes integer
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  update public.kernel_export_curseurs
     set curseur_horodatage = p_horodatage,
         curseur_id = p_id,
         lignes_exportees = lignes_exportees + greatest(coalesce(p_nb_lignes, 0), 0),
         derniere_reussite = now(),
         derniere_erreur = null
   where flux = p_flux
     and (curseur_horodatage is null
          or p_horodatage > curseur_horodatage
          -- départage à horodatage égal, dans le type réel de l'identifiant
          -- (uuid pour l'audit, bigint pour les métriques — jamais en texte,
          -- où '9' > '10').
          or (p_horodatage = curseur_horodatage
              and case p_flux
                    when 'audit' then p_id::uuid > curseur_id::uuid
                    else p_id::bigint > curseur_id::bigint
                  end));
end;
$$;

create or replace function public.kernel_signaler_echec(p_flux text, p_erreur text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  update public.kernel_export_curseurs
     set derniere_erreur = left(coalesce(p_erreur, 'erreur inconnue'), 500)
   where flux = p_flux;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Métriques clés — agrégats uniquement, aucune donnée nominative
-- ---------------------------------------------------------------------------
create or replace function public.kernel_metriques_cles()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_resultat jsonb;
begin
  select jsonb_build_object(
    'produit', 'ecoshop',
    'collecte_le', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'etablissements_actifs',
      (select count(*) from public.etablissements
        where statut = 'actif' and deleted_at is null),
    'comptes_actifs',
      (select count(*) from public.profiles
        where statut_compte = 'actif' and deleted_at is null),
    'comptes_par_role',
      (select coalesce(jsonb_object_agg(r, n), '{}'::jsonb) from (
         select coalesce(role_racine::text, 'non_defini') as r, count(*) as n
           from public.profiles
          where statut_compte = 'actif' and deleted_at is null
          group by 1) t),
    'inscriptions_annee_courante',
      (select count(*) from public.inscriptions i
         join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
        where i.deleted_at is null and i.statut in ('active', 'redoublante')),
    -- Montants regroupés par devise de l'établissement : jamais additionnés
    -- entre devises différentes.
    'encaissements_scolarite_30j',
      (select coalesce(jsonb_object_agg(devise, jsonb_build_object('nombre', n, 'montant', m)), '{}'::jsonb)
         from (select e2.devise_code as devise, count(*) as n, sum(e.montant) as m
                 from public.encaissements_scolarite e
                 join public.etablissements e2 on e2.id = e.etablissement_id
                where e.statut = 'valide'
                  and e.date_paiement >= current_date - 30
                group by 1) t),
    'transactions_paiement_30j',
      (select coalesce(jsonb_object_agg(statut, n), '{}'::jsonb)
         from (select statut::text as statut, count(*) as n
                 from public.transactions_cinetpay
                where created_at >= now() - interval '30 days'
                group by 1) t),
    'commandes_marketplace_30j',
      (select coalesce(jsonb_object_agg(statut, n), '{}'::jsonb)
         from (select statut::text as statut, count(*) as n
                 from public.commandes
                where deleted_at is null
                  and created_at >= now() - interval '30 days'
                group by 1) t),
    'sante_base', public.indicateurs_sante_base(),
    'export', (select coalesce(jsonb_object_agg(flux, jsonb_build_object(
                 'lignes_exportees', lignes_exportees,
                 'derniere_reussite', derniere_reussite,
                 'derniere_erreur', derniere_erreur)), '{}'::jsonb)
               from public.kernel_export_curseurs)
  ) into v_resultat;

  return v_resultat;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Droits : serveur uniquement
-- ---------------------------------------------------------------------------
revoke all on function public.kernel_lecture(text, timestamptz, text, integer) from public, anon, authenticated;
revoke all on function public.kernel_lot_export(text, integer) from public, anon, authenticated;
revoke all on function public.kernel_valider_lot(text, timestamptz, text, integer) from public, anon, authenticated;
revoke all on function public.kernel_signaler_echec(text, text) from public, anon, authenticated;
revoke all on function public.kernel_metriques_cles() from public, anon, authenticated;

grant execute on function public.kernel_lecture(text, timestamptz, text, integer) to service_role;
grant execute on function public.kernel_lot_export(text, integer) to service_role;
grant execute on function public.kernel_valider_lot(text, timestamptz, text, integer) to service_role;
grant execute on function public.kernel_signaler_echec(text, text) to service_role;
grant execute on function public.kernel_metriques_cles() to service_role;
