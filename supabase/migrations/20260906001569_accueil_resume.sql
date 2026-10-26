-- ============================================================================
-- EcoShop — REG-21 : accueil en pastilles, compteurs « À faire » et badges
-- ============================================================================
-- Un seul appel par ouverture de l'accueil (l'application garde la dernière
-- réponse : affichée hors connexion, mise à jour au retour du réseau).
-- Chaque compteur n'est calculé que si le rôle ou le poste de l'appelant y
-- donne droit (mêmes règles que les écrans) ; sinon il est absent.
-- ============================================================================

create or replace function public.accueil_resume(p_etablissement uuid, p_fiche uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_res jsonb := '{}'::jsonb;
  v_fiche uuid := p_fiche;
  v_annee uuid;
  v_n integer;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUISE' using errcode = '42501';
  end if;
  select id into v_annee from public.annees_scolaires where etablissement_id = p_etablissement and courante limit 1;

  -- Élève : sa propre fiche. Parent : l'enfant demandé, s'il est le sien.
  if v_fiche is null then
    select id into v_fiche from public.fiches_eleves
     where profile_id = v_uid and etablissement_id = p_etablissement and deleted_at is null limit 1;
  elsif not coalesce(public.fiche_famille(v_fiche), false) then
    v_fiche := null;
  end if;

  if not (coalesce(public.est_personnel(p_etablissement), false) or v_fiche is not null) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  -- Pour tous : annonces reçues non lues, mots du cahier non lus.
  select count(*) into v_n from public.annonces_ecole a
    join public.annonces_destinataires d on d.annonce_id = a.id and d.profile_id = v_uid
   where a.etablissement_id = p_etablissement and a.masquee_le is null
     and not exists (select 1 from public.annonces_lectures l where l.annonce_id = a.id and l.profile_id = v_uid);
  v_res := v_res || jsonb_build_object('annonces_non_lues', v_n);

  select count(*) into v_n from public.messages_liaison m
   where m.etablissement_id = p_etablissement and m.masque_le is null and m.auteur_id <> v_uid
     and m.cree_le > now() - interval '60 days'
     and (m.fiche_eleve_id = v_fiche or (coalesce(public.est_personnel(p_etablissement), false)
                                          and public.ecrit_liaison(m.fiche_eleve_id) and m.auteur_parent))
     and not exists (select 1 from public.lectures_liaison l where l.message_id = m.id and l.profile_id = v_uid);
  v_res := v_res || jsonb_build_object('cahier_non_lu', v_n);

  -- Direction et postes concernés.
  if coalesce(public.gere_liaisons(p_etablissement), false) then
    select count(*) into v_n from public.relations_parent_eleve
     where etablissement_id = p_etablissement and statut = 'en_attente' and deleted_at is null;
    v_res := v_res || jsonb_build_object('liaisons_a_valider', v_n);
  end if;
  if coalesce(public.gere_inscriptions(p_etablissement), false) then
    select count(*) into v_n from public.telephones_a_confirmer(p_etablissement);
    v_res := v_res || jsonb_build_object('numeros_a_confirmer', v_n);
    select count(*) into v_n from public.demandes_inscription
     where etablissement_id = p_etablissement and statut in ('soumise', 'incomplete', 'a_examiner');
    v_res := v_res || jsonb_build_object('dossiers_inscription', v_n);
  end if;
  if coalesce(public.voit_encaissements(p_etablissement), false) then
    select count(*) into v_n from public.retards_paiement(p_etablissement);
    v_res := v_res || jsonb_build_object('familles_en_retard', v_n);
  end if;
  if coalesce(public.est_direction(p_etablissement), false)
     or coalesce(public.droit(p_etablissement, array['scolarite.presence.lire', 'scolarite.presence.gerer',
                                                    'scolarite.sanction.lire', 'scolarite.sanction.gerer']), false) then
    select count(*) into v_n from public.alertes_decrochage
     where etablissement_id = p_etablissement and statut = 'ouverte' and deleted_at is null;
    v_res := v_res || jsonb_build_object('alertes_ouvertes', v_n);
  end if;

  -- Enseignant : appels du jour à faire, évaluations à compléter.
  if exists (select 1 from public.affectations_enseignants
              where enseignant_profile_id = v_uid and etablissement_id = p_etablissement and deleted_at is null) then
    select count(distinct e.classe_id) into v_n from public.emplois_du_temps e
     where e.etablissement_id = p_etablissement and e.enseignant_profile_id = v_uid and e.deleted_at is null
       and e.annee_scolaire_id = v_annee and e.jour_semaine = extract(isodow from current_date)::int
       and not exists (select 1 from public.presences p
                        where p.classe_id = e.classe_id and p.date_presence = current_date and p.deleted_at is null);
    v_res := v_res || jsonb_build_object('appels_a_faire', v_n);
    select count(*) into v_n from public.evaluations
     where enseignant_profile_id = v_uid and etablissement_id = p_etablissement and statut = 'brouillon'
       and deleted_at is null;
    v_res := v_res || jsonb_build_object('notes_a_saisir', v_n);
  end if;

  -- Élève ou enfant : nouvelles notes, livres à rendre, tranche échue.
  if v_fiche is not null then
    select count(*) into v_n from public.notes n join public.evaluations e on e.id = n.evaluation_id
     where n.fiche_eleve_id = v_fiche and n.deleted_at is null and e.deleted_at is null
       and e.statut in ('publiee', 'cloturee') and coalesce(e.publie_le, e.updated_at) > now() - interval '7 days';
    v_res := v_res || jsonb_build_object('nouvelles_notes', v_n);
    select count(*) into v_n from public.emprunts
     where fiche_eleve_id = v_fiche and rendu_le is null and declare_perdu_le is null
       and echeance <= current_date + 3;
    v_res := v_res || jsonb_build_object('livres_a_rendre', v_n);
    -- Tranche échue de cet élève seulement (même calcul que retards_paiement).
    select count(*) into v_n
      from public.inscriptions i, lateral public.solde_scolarite(i.id) s
     where i.fiche_eleve_id = v_fiche and i.annee_scolaire_id = v_annee and i.deleted_at is null
       and i.statut in ('active', 'redoublante') and not coalesce(i.boursier, false)
       and round(s.montant_du * coalesce((
             select sum(c.pourcentage) from public.paliers_paiement_config c
              where c.etablissement_id = p_etablissement and c.annee_scolaire_id = v_annee
                and c.deleted_at is null and c.date_limite is not null and c.date_limite < current_date), 0) / 100)
           - s.montant_paye > 0;
    v_res := v_res || jsonb_build_object('tranches_a_payer', v_n);
  end if;

  return v_res;
end;
$$;

-- Cours du jour : enseignant (les siens), élève (sa classe), parent (la
-- classe de l'enfant demandé).
create or replace function public.mon_aujourdhui(p_etablissement uuid, p_fiche uuid default null)
returns table (heure_debut time, heure_fin time, matiere text, classe text, salle text, enseignant text)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche uuid := p_fiche;
  v_classe uuid;
  v_annee uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUISE' using errcode = '42501';
  end if;
  select id into v_annee from public.annees_scolaires where etablissement_id = p_etablissement and courante limit 1;
  if v_fiche is null then
    select id into v_fiche from public.fiches_eleves
     where profile_id = v_uid and etablissement_id = p_etablissement and deleted_at is null limit 1;
  elsif not coalesce(public.fiche_famille(v_fiche), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if v_fiche is not null then
    select classe_id into v_classe from public.inscriptions
     where fiche_eleve_id = v_fiche and annee_scolaire_id = v_annee and deleted_at is null limit 1;
  elsif not coalesce(public.est_personnel(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return query
  select e.heure_debut, e.heure_fin, pm.nom, c.nom, s.nom,
         nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), '')
    from public.emplois_du_temps e
    join public.classes c on c.id = e.classe_id
    left join public.programmes_matieres pm on pm.id = e.programme_matiere_id
    left join public.salles s on s.id = e.salle_id
    left join public.profiles p on p.id = e.enseignant_profile_id
   where e.etablissement_id = p_etablissement and e.annee_scolaire_id = v_annee and e.deleted_at is null
     and e.jour_semaine = extract(isodow from current_date)::int
     and ((v_classe is not null and e.classe_id = v_classe)
          or (v_fiche is null and e.enseignant_profile_id = v_uid))
   order by e.heure_debut;
end;
$$;

revoke all on function public.accueil_resume(uuid, uuid) from public, anon;
revoke all on function public.mon_aujourdhui(uuid, uuid) from public, anon;
grant execute on function public.accueil_resume(uuid, uuid), public.mon_aujourdhui(uuid, uuid) to authenticated;
