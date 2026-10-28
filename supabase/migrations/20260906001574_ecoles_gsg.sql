-- ============================================================================
-- EcoShop — REG-23 : Administration GSG — écoles confirmées et tableau de
-- bord par école (retour du porteur de projet, 2026-10-28 : « dans
-- administration, je n'ai pas vu la page qui liste les écoles confirmées,
-- leurs renseignements et un tableau de bord spécifique : nombre d'élèves,
-- utilisation… »)
--
--   • gsg_ecoles() : toutes les écoles en service, avec leurs
--     renseignements (demande d'origine, direction) et leurs chiffres clés.
--   • gsg_tableau_ecole(p_etablissement) : fiche complète d'une école —
--     effectifs, comptes, activité des 30 derniers jours jour par jour,
--     finances, crédits SMS, mise en route.
--
-- Réservées à l'Administrateur GSG. Aucun montant n'est additionné entre
-- devises différentes : chaque école a sa devise.
-- ============================================================================

create or replace function public.gsg_ecoles()
returns table (
  id uuid,
  nom text,
  slug text,
  pays_code text,
  ville text,
  devise_code text,
  statut text,
  logo_chemin text,
  couleur_identite text,
  slogan text,
  cree_le timestamptz,
  valide_le timestamptz,
  telephone text,
  email text,
  direction text,
  eleves integer,
  classes integer,
  personnel integer,
  parents integer,
  comptes_actifs_30j integer,
  derniere_activite timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  return query
  select e.id, e.nom, e.slug, e.pays_code, e.ville, e.devise_code, e.statut,
         e.logo_chemin, e.couleur_identite, e.slogan, e.created_at,
         d.traitee_le, d.telephone, d.email,
         (select string_agg(nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), ''), ', ')
            from public.etablissements_membres m
            join public.profiles p on p.id = m.profile_id
           where m.etablissement_id = e.id and m.actif and m.deleted_at is null
             and m.role_dans_etablissement = 'direction'),
         (select count(*)::int from public.inscriptions i
            join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
           where i.etablissement_id = e.id and i.deleted_at is null
             and i.statut in ('active', 'redoublante')),
         (select count(*)::int from public.classes c
            join public.annees_scolaires a on a.id = c.annee_scolaire_id and a.courante
           where c.etablissement_id = e.id and c.deleted_at is null and c.actif),
         (select count(*)::int from public.etablissements_membres m
           where m.etablissement_id = e.id and m.actif and m.deleted_at is null
             and m.role_dans_etablissement not in ('eleve', 'parent')),
         (select count(distinct r.parent_profile_id)::int from public.relations_parent_eleve r
           where r.etablissement_id = e.id and r.deleted_at is null),
         (select count(distinct m.profile_id)::int
            from public.etablissements_membres m
            join auth.sessions s on s.user_id = m.profile_id
           where m.etablissement_id = e.id and m.actif and m.deleted_at is null
             and coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at) >= now() - interval '30 days'),
         (select max(coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at))
            from public.etablissements_membres m
            join auth.sessions s on s.user_id = m.profile_id
           where m.etablissement_id = e.id and m.actif and m.deleted_at is null)
    from public.etablissements e
    left join lateral (
      select de.traitee_le, de.telephone, de.email
        from public.demandes_etablissement de
       where de.etablissement_id = e.id and de.statut = 'acceptee'
       order by de.traitee_le desc nulls last
       limit 1
    ) d on true
   where e.deleted_at is null
   order by e.nom;
end;
$$;
revoke all on function public.gsg_ecoles() from public, anon;
grant execute on function public.gsg_ecoles() to authenticated;

create or replace function public.gsg_tableau_ecole(p_etablissement uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_etab public.etablissements;
  v_annee public.annees_scolaires;
  v_resultat jsonb;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  select * into v_etab from public.etablissements where id = p_etablissement and deleted_at is null;
  if v_etab.id is null then
    raise exception 'ETABLISSEMENT_INTROUVABLE' using errcode = '22023';
  end if;
  select * into v_annee from public.annees_scolaires
   where etablissement_id = p_etablissement
   order by courante desc, date_debut desc limit 1;

  select jsonb_build_object(
    'annee', v_annee.libelle,
    'demande', (select jsonb_build_object(
                   'demandeur', nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), ''),
                   'telephone', de.telephone, 'email', de.email, 'adresse', de.adresse,
                   'effectif_estime', de.effectif_estime, 'numero_autorisation', de.numero_autorisation,
                   'deposee_le', de.created_at, 'validee_le', de.traitee_le)
                  from public.demandes_etablissement de
                  left join public.profiles p on p.id = de.demandeur_id
                 where de.etablissement_id = p_etablissement and de.statut = 'acceptee'
                 order by de.traitee_le desc nulls last limit 1),
    'effectifs', jsonb_build_object(
       'eleves', (select count(*) from public.inscriptions
                   where annee_scolaire_id = v_annee.id and deleted_at is null and statut in ('active', 'redoublante')),
       'fiches', (select count(*) from public.fiches_eleves where etablissement_id = p_etablissement and deleted_at is null),
       'eleves_avec_compte', (select count(*) from public.fiches_eleves
                               where etablissement_id = p_etablissement and deleted_at is null and profile_id is not null),
       'classes', (select count(*) from public.classes
                    where annee_scolaire_id = v_annee.id and deleted_at is null and actif),
       'parents', (select count(distinct parent_profile_id) from public.relations_parent_eleve
                    where etablissement_id = p_etablissement and deleted_at is null),
       'par_role', (select coalesce(jsonb_object_agg(role_dans_etablissement, n), '{}'::jsonb)
                      from (select role_dans_etablissement, count(*) n from public.etablissements_membres
                             where etablissement_id = p_etablissement and actif and deleted_at is null
                             group by 1) t)),
    'utilisation', jsonb_build_object(
       'comptes_actifs_7j', (select count(distinct m.profile_id) from public.etablissements_membres m
                              join auth.sessions s on s.user_id = m.profile_id
                             where m.etablissement_id = p_etablissement and m.actif and m.deleted_at is null
                               and coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at) >= now() - interval '7 days'),
       'comptes_actifs_30j', (select count(distinct m.profile_id) from public.etablissements_membres m
                              join auth.sessions s on s.user_id = m.profile_id
                             where m.etablissement_id = p_etablissement and m.actif and m.deleted_at is null
                               and coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at) >= now() - interval '30 days'),
       'appels_30j', (select count(*) from public.presences
                       where etablissement_id = p_etablissement and created_at >= now() - interval '30 days'),
       'notes_30j', (select count(*) from public.notes
                      where etablissement_id = p_etablissement and created_at >= now() - interval '30 days'),
       'pointages_30j', (select count(*) from public.pointages_portail
                          where etablissement_id = p_etablissement and scanne_le >= now() - interval '30 days'),
       'annonces_30j', (select count(*) from public.annonces_ecole
                         where etablissement_id = p_etablissement and publiee_le >= now() - interval '30 days'),
       'encaissements_30j', (select count(*) from public.encaissements_scolarite
                              where etablissement_id = p_etablissement and statut = 'valide'
                                and date_paiement >= current_date - 30),
       -- Actions par jour (appels, notes, pointages, reçus), 30 derniers jours.
       'par_jour', (select coalesce(jsonb_agg(jsonb_build_object('jour', j.jour, 'actions', j.n) order by j.jour), '[]'::jsonb)
                      from (
                        select d::date as jour,
                               (select count(*) from public.presences where etablissement_id = p_etablissement and created_at::date = d::date)
                             + (select count(*) from public.notes where etablissement_id = p_etablissement and created_at::date = d::date)
                             + (select count(*) from public.pointages_portail where etablissement_id = p_etablissement and jour = d::date)
                             + (select count(*) from public.encaissements_scolarite where etablissement_id = p_etablissement and created_at::date = d::date)
                               as n
                          from generate_series(current_date - 29, current_date, interval '1 day') d
                      ) j)),
    'finances', jsonb_build_object(
       'devise', v_etab.devise_code,
       'encaisse_30j', (select coalesce(sum(montant), 0) from public.encaissements_scolarite
                         where etablissement_id = p_etablissement and statut = 'valide'
                           and date_paiement >= current_date - 30),
       'encaisse_annee', (select coalesce(sum(e.montant), 0) from public.encaissements_scolarite e
                           join public.inscriptions i on i.id = e.inscription_id
                          where e.etablissement_id = p_etablissement and e.statut = 'valide'
                            and i.annee_scolaire_id = v_annee.id),
       'paiements_mobiles_30j', (select count(*) from public.transactions_mobile_money
                                  where etablissement_id = p_etablissement and created_at >= now() - interval '30 days'),
       'credits_sms', (select solde from public.credits_sms where etablissement_id = p_etablissement)),
    'configuration', public.etat_configuration_gsg(p_etablissement)
  ) into v_resultat;
  return v_resultat;
end;
$$;
revoke all on function public.gsg_tableau_ecole(uuid) from public, anon;
grant execute on function public.gsg_tableau_ecole(uuid) to authenticated;

-- Mise en route vue par GSG : même contenu que l'écran de la Direction,
-- sans son contrôle d'accès (réservé ici à l'Administrateur GSG, qui passe
-- déjà le contrôle de `etat_configuration_etablissement` via a_permission).
create or replace function public.etat_configuration_gsg(p_etablissement uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  return public.etat_configuration_etablissement(p_etablissement);
end;
$$;
revoke all on function public.etat_configuration_gsg(uuid) from public, anon;
grant execute on function public.etat_configuration_gsg(uuid) to authenticated;
