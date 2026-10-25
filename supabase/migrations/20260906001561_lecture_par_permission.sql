-- ============================================================================
-- EcoShop — REG-22 partie C, étape 1 : lecture par permission
-- ============================================================================
-- Faille corrigée : `est_personnel` vaut pour tout membre qui n'est ni élève
-- ni parent (agent du portail, chauffeur, bibliothécaire…). De nombreuses
-- fonctions et politiques ne demandaient rien d'autre pour ouvrir les notes,
-- bulletins, absences, sanctions, encaissements, soldes, risques de
-- décrochage, rapports et le journal d'audit. Pire : `fiche_visible` et
-- `classe_visible` répondent vrai pour tout le personnel, si bien que la
-- branche « famille » des contrôles (`… or fiche_visible(...)`) ouvrait aussi
-- tout au personnel.
--
-- Désormais, côté personnel, l'accès vient de l'un de ces trois motifs :
--   1. la direction de l'école (`est_direction`) : tout, comme avant ;
--   2. une permission de lecture (ou de gestion) du domaine, par le poste ;
--   3. l'enseignement : enseignant affecté à la classe, ou titulaire.
-- Côté famille : l'élève lui-même ou un parent confirmé et autorisé
-- (`fiche_famille`), jamais plus `fiche_visible`.
--
-- Hors champ, inchangé (annuaire, organisation) : fiches, inscriptions,
-- classes, périodes, affectations, emplois du temps, salles, agenda,
-- campagnes d'inscription, état des licences.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Nouveaux codes de lecture
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('scolarite.note.lire', 'scolarite', 'Lire les notes',
   'Notes, évaluations, moyennes et classements de toutes les classes.'),
  ('scolarite.bulletin.lire', 'scolarite', 'Lire les bulletins',
   'Bulletins, appréciations et proclamations de toutes les classes.'),
  ('scolarite.presence.lire', 'scolarite', 'Lire les absences et retards',
   'Appels, absences et retards de tous les élèves.'),
  ('scolarite.sanction.lire', 'scolarite', 'Lire les sanctions',
   'Sanctions et suivi du comportement de tous les élèves.'),
  ('scolarite.encaissement.lire', 'scolarite', 'Lire les encaissements',
   'Reçus de scolarité, soldes et paiements mobiles de l''école.'),
  ('audit.journal.lire', 'audit', 'Lire le journal d''audit',
   'Historique des actions sensibles de l''école.')
on conflict (code) do nothing;

-- Codes déjà vérifiés par le serveur mais absents du catalogue : aucun poste
-- ne pouvait les recevoir (un caissier devait être invité comme direction).
insert into public.permissions (code, domaine, libelle, description) values
  ('scolarite.encaissement.gerer', 'scolarite', 'Encaisser la scolarité',
   'Enregistrer les paiements de scolarité et délivrer les reçus.'),
  ('scolarite.parametres.gerer', 'scolarite', 'Régler la scolarité',
   'Paramètres de scolarité de l''école (frais, échéances, règles).'),
  ('bibliotheque.gerer', 'bibliotheque', 'Gérer la bibliothèque',
   'Livres, prêts, retours et réservations.'),
  ('transport.gerer', 'transport', 'Gérer le transport scolaire',
   'Circuits, arrêts, véhicules et abonnements au transport.'),
  ('communication.groupe.moderer', 'communication', 'Modérer les groupes',
   'Modérer les messages des groupes de l''école.')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Briques
-- ---------------------------------------------------------------------------

-- Vrai si l'appelant est la direction de l'école, ou un membre du personnel
-- dont le poste porte l'un des codes. L'administrateur GSG n'est pas compris :
-- chaque contrôle l'ajoute explicitement là où il l'était déjà.
create or replace function public.droit(p_etablissement uuid, p_codes text[])
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.est_direction(p_etablissement), false)
      or (coalesce(public.est_personnel(p_etablissement), false)
          and exists (
            select 1 from public.mes_permissions(p_etablissement) c
            where c = any (p_codes)
          ));
$$;

-- L'élève lui-même, ou un parent confirmé et autorisé.
create or replace function public.fiche_famille(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.fiches_eleves f
    where f.id = p_fiche and f.deleted_at is null
      and (f.profile_id = auth.uid() or public.est_parent_confirme(f.id))
  );
$$;

-- Un élève de la classe est de la famille de l'appelant.
create or replace function public.classe_famille(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.inscriptions i
    where i.classe_id = p_classe and i.deleted_at is null
      and public.fiche_famille(i.fiche_eleve_id)
  );
$$;

-- Enseignant affecté à la classe, ou titulaire, toujours membre actif.
create or replace function public.enseigne_classe(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.classes c
    where c.id = p_classe and c.deleted_at is null
      and coalesce(public.est_personnel(c.etablissement_id), false)
      and (
        c.enseignant_principal_id = auth.uid()
        or exists (
          select 1 from public.affectations_enseignants a
          where a.classe_id = c.id and a.enseignant_profile_id = auth.uid()
            and a.deleted_at is null
        )
      )
  );
$$;

-- Titulaire (professeur principal) de la classe.
create or replace function public.titulaire_classe(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.classes c
    where c.id = p_classe and c.deleted_at is null
      and coalesce(public.est_personnel(c.etablissement_id), false)
      and (
        c.enseignant_principal_id = auth.uid()
        or exists (
          select 1 from public.affectations_enseignants a
          where a.classe_id = c.id and a.enseignant_profile_id = auth.uid()
            and a.role_affectation = 'titulaire' and a.deleted_at is null
        )
      )
  );
$$;

create or replace function public.enseigne_eleve(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.inscriptions i
    where i.fiche_eleve_id = p_fiche and i.deleted_at is null
      and public.enseigne_classe(i.classe_id)
  );
$$;

create or replace function public.titulaire_eleve(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.inscriptions i
    where i.fiche_eleve_id = p_fiche and i.deleted_at is null
      and public.titulaire_classe(i.classe_id)
  );
$$;

-- Établissement d'une fiche (sans contrôle : sert aux briques ci-dessous).
create or replace function public.etablissement_fiche(p_fiche uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select etablissement_id from public.fiches_eleves where id = p_fiche;
$$;

create or replace function public.etablissement_classe(p_classe uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select etablissement_id from public.classes where id = p_classe;
$$;

-- ---------------------------------------------------------------------------
-- 3. Droits par domaine, côté personnel
-- ---------------------------------------------------------------------------

-- Notes, évaluations, moyennes, classements. Les postes « rapports » y ont
-- accès : leurs analyses d'école recalculent les moyennes de chaque élève.
create or replace function public.voit_notes_classe(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.droit(public.etablissement_classe(p_classe), array[
           'scolarite.note.lire', 'scolarite.note.gerer',
           'scolarite.bulletin.lire', 'scolarite.bulletin.gerer',
           'rapports.consulter', 'rapports.generer', 'rapports.administrer'])
      or public.enseigne_classe(p_classe);
$$;

create or replace function public.voit_notes_eleve(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.droit(public.etablissement_fiche(p_fiche), array[
           'scolarite.note.lire', 'scolarite.note.gerer',
           'scolarite.bulletin.lire', 'scolarite.bulletin.gerer',
           'rapports.consulter', 'rapports.generer', 'rapports.administrer'])
      or public.enseigne_eleve(p_fiche);
$$;

-- Bulletins, appréciations, proclamations.
create or replace function public.voit_bulletins_classe(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.droit(public.etablissement_classe(p_classe), array[
           'scolarite.bulletin.lire', 'scolarite.bulletin.gerer',
           'scolarite.appreciation.gerer'])
      or public.titulaire_classe(p_classe);
$$;

-- Absences, retards (lecture).
create or replace function public.voit_presences_eleve(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.droit(public.etablissement_fiche(p_fiche), array[
           'scolarite.presence.lire', 'scolarite.presence.gerer'])
      or public.enseigne_eleve(p_fiche);
$$;

-- Sanctions et comportement.
create or replace function public.voit_sanctions_eleve(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.droit(public.etablissement_fiche(p_fiche), array[
           'scolarite.sanction.lire', 'scolarite.sanction.gerer']);
$$;

-- Suivi de l'élève : risque de décrochage, alertes, analyse du comportement.
-- Vie scolaire (absences, sanctions), études (notes), rapports, ou titulaire.
create or replace function public.voit_suivi_eleve(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.droit(public.etablissement_fiche(p_fiche), array[
           'scolarite.presence.lire', 'scolarite.presence.gerer',
           'scolarite.sanction.lire', 'scolarite.sanction.gerer',
           'scolarite.note.lire',
           'rapports.consulter', 'rapports.generer', 'rapports.administrer'])
      or public.titulaire_eleve(p_fiche);
$$;

create or replace function public.voit_suivi_classe(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.droit(public.etablissement_classe(p_classe), array[
           'scolarite.presence.lire', 'scolarite.presence.gerer',
           'scolarite.sanction.lire', 'scolarite.sanction.gerer',
           'scolarite.note.lire',
           'rapports.consulter', 'rapports.generer', 'rapports.administrer'])
      or public.titulaire_classe(p_classe);
$$;

-- Encaissements, soldes, paiements mobiles.
create or replace function public.voit_encaissements(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.droit(p_etablissement, array[
           'scolarite.encaissement.lire', 'scolarite.encaissement.gerer',
           'comptabilite.lire']);
$$;

-- Rapports, indicateurs, recommandations, anomalies.
create or replace function public.voit_rapports(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.droit(p_etablissement, array[
           'rapports.consulter', 'rapports.generer', 'rapports.administrer']);
$$;

grant execute on function public.droit(uuid, text[]) to authenticated;
grant execute on function public.fiche_famille(uuid) to authenticated;
grant execute on function public.classe_famille(uuid) to authenticated;
grant execute on function public.enseigne_classe(uuid) to authenticated;
grant execute on function public.titulaire_classe(uuid) to authenticated;
grant execute on function public.enseigne_eleve(uuid) to authenticated;
grant execute on function public.titulaire_eleve(uuid) to authenticated;
grant execute on function public.voit_notes_classe(uuid) to authenticated;
grant execute on function public.voit_notes_eleve(uuid) to authenticated;
grant execute on function public.voit_bulletins_classe(uuid) to authenticated;
grant execute on function public.voit_presences_eleve(uuid) to authenticated;
grant execute on function public.voit_sanctions_eleve(uuid) to authenticated;
grant execute on function public.voit_suivi_eleve(uuid) to authenticated;
grant execute on function public.voit_suivi_classe(uuid) to authenticated;
grant execute on function public.voit_encaissements(uuid) to authenticated;
grant execute on function public.voit_rapports(uuid) to authenticated;
-- Lecture brute d'identifiants : pas d'appel direct par les clients.
revoke execute on function public.etablissement_fiche(uuid) from public, anon, authenticated;
revoke execute on function public.etablissement_classe(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Fonctions de visibilité (politiques des tables)
-- ---------------------------------------------------------------------------
create or replace function public.note_visible(p_note uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.notes n
    join public.evaluations e on e.id = n.evaluation_id
    where n.id = p_note and n.deleted_at is null and e.deleted_at is null
      and (
        public.voit_notes_classe(e.classe_id)
        or e.enseignant_profile_id = auth.uid()
        or (e.statut in ('publiee', 'cloturee') and public.fiche_famille(n.fiche_eleve_id))
      )
  );
$$;

create or replace function public.evaluation_visible(p_eval uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.evaluations e
    where e.id = p_eval and e.deleted_at is null
      and (
        public.voit_notes_classe(e.classe_id)
        or e.enseignant_profile_id = auth.uid()
        or (e.statut in ('publiee', 'cloturee') and public.classe_famille(e.classe_id))
      )
  );
$$;

create or replace function public.bulletin_visible(p_bul uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.bulletins b
    where b.id = p_bul and b.deleted_at is null
      and (
        public.voit_bulletins_classe(b.classe_id)
        or (b.statut = 'publie' and public.fiche_famille(b.fiche_eleve_id))
      )
  );
$$;

create or replace function public.appreciation_visible(p_app uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.appreciations a
    where a.id = p_app and a.deleted_at is null
      and (
        a.redige_par = auth.uid()
        or public.droit(a.etablissement_id, array[
             'scolarite.bulletin.lire', 'scolarite.bulletin.gerer',
             'scolarite.appreciation.gerer'])
        or public.enseigne_eleve(a.fiche_eleve_id)
        or public.fiche_famille(a.fiche_eleve_id)
      )
  );
$$;

create or replace function public.presence_visible(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.presences pr
    where pr.id = p_id and pr.deleted_at is null
      and (
        pr.saisi_par = auth.uid()
        or public.droit(pr.etablissement_id, array[
             'scolarite.presence.lire', 'scolarite.presence.gerer'])
        or public.enseigne_classe(pr.classe_id)
        or public.fiche_famille(pr.fiche_eleve_id)
      )
  );
$$;

create or replace function public.retard_visible(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.retards r
    where r.id = p_id and r.deleted_at is null
      and (
        r.saisi_par = auth.uid()
        or public.voit_presences_eleve(r.fiche_eleve_id)
        or public.fiche_famille(r.fiche_eleve_id)
      )
  );
$$;

create or replace function public.sanction_visible(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.sanctions s
    where s.id = p_id and s.deleted_at is null
      and (
        s.decisionnaire_id = auth.uid()
        or public.voit_sanctions_eleve(s.fiche_eleve_id)
        or public.fiche_famille(s.fiche_eleve_id)
      )
  );
$$;

create or replace function public.alerte_visible(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.alertes_decrochage a
    where a.id = p_id and a.deleted_at is null
      and (
        public.voit_suivi_eleve(a.fiche_eleve_id)
        or (a.statut = 'transmise' and public.fiche_famille(a.fiche_eleve_id))
      )
  );
$$;

create or replace function public.encaissement_visible(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.encaissements_scolarite e
    where e.id = p_id
      and (public.voit_encaissements(e.etablissement_id) or public.fiche_famille(e.fiche_eleve_id))
  );
$$;

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

  -- Poste d'audit : tout le journal de son école.
  if v_row.etablissement_id is not null
     and public.droit(v_row.etablissement_id, array['audit.journal.lire']) then
    return true;
  end if;

  return case v_row.entite
    when 'inscription' then
      public.droit(v_row.etablissement_id, array['scolarite.inscription.gerer', 'scolarite.eleve.gerer'])
      or public.fiche_famille(v_row.fiche_eleve_id)
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
      coalesce(public.voit_encaissements(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'transaction_mobile_money' then
      coalesce(public.voit_encaissements(v_row.etablissement_id), false)
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
    when 'annonce' then
      coalesce(public.est_direction(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'mot_liaison' then
      coalesce(public.est_direction(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    else false
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Politiques des tables
-- ---------------------------------------------------------------------------
drop policy if exists "evaluations_select_visible" on public.evaluations;
-- Condition écrite sur les colonnes de la ligne, jamais via evaluation_visible(id) :
-- une fonction qui relit la table ne voit pas la ligne qu'un INSERT … RETURNING
-- vient de créer (piège corrigé en 1503).
create policy "evaluations_select_visible" on public.evaluations for select using (
  public.voit_notes_classe(classe_id)
  or enseignant_profile_id = auth.uid()
  or (statut in ('publiee', 'cloturee') and public.classe_famille(classe_id))
);

drop policy if exists "encaissements_select_visible" on public.encaissements_scolarite;
create policy "encaissements_select_visible" on public.encaissements_scolarite for select using (
  public.voit_encaissements(etablissement_id) or public.fiche_famille(fiche_eleve_id)
);

drop policy if exists "proclamations_select" on public.proclamations_classes;
create policy "proclamations_select" on public.proclamations_classes for select using (
  public.voit_bulletins_classe(classe_id) or coalesce(public.est_admin_gsg(), false)
);

drop policy if exists "statistiques_select" on public.statistiques_agregats;
create policy "statistiques_select" on public.statistiques_agregats for select using (
  public.voit_rapports(etablissement_id)
  or (fiche_eleve_id is not null and (
        public.voit_notes_eleve(fiche_eleve_id)
        or public.voit_suivi_eleve(fiche_eleve_id)
        or public.fiche_famille(fiche_eleve_id)))
  or (fiche_eleve_id is null and classe_id is not null and public.voit_notes_classe(classe_id))
);

drop policy if exists rapports_select on public.rapports;
create policy rapports_select on public.rapports for select to authenticated using (
  public.voit_rapports(etablissement_id)
  or (fiche_eleve_id is not null and public.fiche_famille(fiche_eleve_id))
);

drop policy if exists indicateurs_select on public.indicateurs_cles;
create policy indicateurs_select on public.indicateurs_cles for select to authenticated using (
  public.voit_rapports(etablissement_id)
);

drop policy if exists recos_select on public.recommandations_strategiques;
create policy recos_select on public.recommandations_strategiques for select to authenticated using (
  public.voit_rapports(etablissement_id)
);

drop policy if exists anomalies_select on public.anomalies_statistiques;
create policy anomalies_select on public.anomalies_statistiques for select to authenticated using (
  public.voit_rapports(etablissement_id)
);

drop policy if exists "transactions_cinetpay_select" on public.transactions_cinetpay;
create policy "transactions_cinetpay_select" on public.transactions_cinetpay for select using (
  coalesce(public.voit_encaissements(etablissement_id), false)
  or coalesce(public.est_admin_gsg(), false)
  or initiateur_id = auth.uid()
);

drop policy if exists transactions_mm_select on public.transactions_mobile_money;
create policy transactions_mm_select on public.transactions_mobile_money for select using (
  initiateur_id = auth.uid()
  or coalesce(public.voit_encaissements(etablissement_id), false)
  or coalesce(public.est_admin_gsg(), false)
);

-- Retards : la vie scolaire, ou l'enseignant de l'élève pour ses propres
-- saisies (avant : tout membre du personnel pour ses propres saisies).
drop policy if exists "retards_ecriture_personnel" on public.retards;
create policy "retards_ecriture_personnel" on public.retards for all using (
  public.droit(etablissement_id, array['scolarite.presence.gerer'])
  or (saisi_par = auth.uid() and public.enseigne_eleve(fiche_eleve_id))
) with check (
  public.droit(etablissement_id, array['scolarite.presence.gerer'])
  or (saisi_par = auth.uid() and public.enseigne_eleve(fiche_eleve_id))
);

-- Moyenne brute d'un élève, sans contrôle : sert aux calculs internes (score
-- de décrochage, recommandation éducative) dont l'appelant a le droit de voir
-- le résultat, mais pas forcément les notes elles-mêmes (vie scolaire).
-- Jamais appelable par un client.
create or replace function public.moyenne_eleve_interne(
  p_fiche uuid,
  p_matiere uuid default null,
  p_periode uuid default null
)
returns numeric
language sql stable security definer set search_path = public
as $$
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
    and (p_periode is null or e.periode_id = p_periode);
$$;
revoke execute on function public.moyenne_eleve_interne(uuid, uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Fonctions de calcul et d'analyse (contrôle d'entrée réécrit, corps repris
--    à l'identique de leur dernière version)
-- ---------------------------------------------------------------------------

-- analyse_comportement (reprise de 20260906001513_qa_prelancement_audit_rpc.sql)
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
     and not coalesce(public.voit_suivi_eleve(p_fiche), false)
     and not coalesce(public.fiche_famille(p_fiche), false) then
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

-- calculer_moyenne_eleve (reprise de 20260906001513_qa_prelancement_audit_rpc.sql)
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
     and not coalesce(public.voit_notes_eleve(p_fiche), false)
     and not coalesce(public.fiche_famille(p_fiche), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return public.moyenne_eleve_interne(p_fiche, p_matiere, p_periode);
end;
$$;

-- calculer_score_decrochage (reprise de 20260906001513_qa_prelancement_audit_rpc.sql)
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
     and not coalesce(public.voit_suivi_eleve(p_fiche), false)
     and not coalesce(public.fiche_famille(p_fiche), false) then
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

  select public.moyenne_eleve_interne(p_fiche, null, null) into v_moyenne;

  v_score := 0.5 * coalesce(v_taux_abs, 0)
           + 0.2 * least(coalesce(v_retards, 0) / 10.0, 1)
           + case
               when v_moyenne is null then 0.15
               else 0.3 * greatest(1 - v_moyenne / 20.0, 0)
             end;

  return round(greatest(least(v_score, 1), 0), 4);
end;
$$;

-- recommander_sanction_educative (reprise de 20260906001513_qa_prelancement_audit_rpc.sql)
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
     and not coalesce(public.voit_sanctions_eleve(p_fiche), false)
     and not coalesce(public.fiche_famille(p_fiche), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  select count(*) into v_abs from public.presences
  where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
    and statut = 'absent' and not justifie and deleted_at is null;

  select count(*) into v_ret from public.retards
  where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
    and not justifie and deleted_at is null;

  select public.moyenne_eleve_interne(p_fiche, null, null) into v_moyenne;

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

-- calculer_moyenne_classe (reprise de 20260906001517_fix_calculer_moyenne_classe_scoping.sql)
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
     and not coalesce(public.voit_notes_classe(p_classe), false)
     and not coalesce(public.classe_famille(p_classe), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return (
    with fiches_de_la_classe as materialized (
      select f.id as fiche_eleve_id
      from public.classes c
      join public.inscriptions i on i.classe_id = c.id and i.deleted_at is null and i.statut = 'active'
      join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
      where c.id = p_classe
    )
    select round(avg(m), 2)
    from (
      select public.calculer_moyenne_eleve(fc.fiche_eleve_id, p_matiere, p_periode) as m
      from fiches_de_la_classe fc
    ) moyennes
    where m is not null
  );
end;
$$;

-- classer_eleves_classe (reprise de 20260906001516_fix_classer_eleves_classe_scoping.sql)
create or replace function public.classer_eleves_classe(
  p_classe uuid,
  p_matiere uuid default null,
  p_periode uuid default null
)
returns table(fiche_eleve_id uuid, moyenne numeric, rang int)
language sql stable security definer set search_path = public
as $$
  with fiches_de_la_classe as materialized (
    select f.id as fiche_eleve_id
    from public.classes c
    join public.inscriptions i on i.classe_id = c.id and i.deleted_at is null and i.statut = 'active'
    join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
    where c.id = p_classe
      and public.voit_notes_classe(c.id)
  )
  select fc.fiche_eleve_id,
         m.moyenne,
         rank() over (order by m.moyenne desc)::int as rang
  from fiches_de_la_classe fc
  cross join lateral (
    select public.calculer_moyenne_eleve(fc.fiche_eleve_id, p_matiere, p_periode) as moyenne
  ) m
  where m.moyenne is not null
  order by m.moyenne desc;
$$;

-- risque_reussite_actuel (reprise de 20260906001504_m16_materialisation_risque_reussite.sql)
create or replace function public.risque_reussite_actuel(p_fiche uuid)
returns numeric
language sql stable security definer set search_path = public
as $$
  select sa.valeur_numeric
  from public.statistiques_agregats sa
  join public.annees_scolaires an on an.id = sa.annee_scolaire_id
  where sa.fiche_eleve_id = p_fiche
    and sa.type_agregat = 'risque_reussite'
    and an.courante
    and (public.voit_suivi_eleve(sa.fiche_eleve_id) or public.fiche_famille(sa.fiche_eleve_id))
  order by sa.calcule_le desc
  limit 1;
$$;

-- risque_classe (reprise de 20260906001000_m10_rapports_statistiques.sql)
create or replace function public.risque_classe(p_classe uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_etab uuid; v_annee uuid; v_effectif int;
  v_reussite numeric; v_absenteisme numeric; v_alertes int;
  v_score numeric; v_niveau text;
begin
  select c.etablissement_id, c.annee_scolaire_id into v_etab, v_annee
  from public.classes c where c.id = p_classe and c.deleted_at is null;

  if v_etab is null or not coalesce(public.voit_suivi_classe(p_classe), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  select count(*) into v_effectif
  from public.inscriptions i
  where i.classe_id = p_classe and i.statut = 'active' and i.deleted_at is null;

  select case when count(*) = 0 then 0
              else count(*) filter (where n.valeur / e.bareme >= 0.5)::numeric / count(*)::numeric end
  into v_reussite
  from public.notes n
  join public.evaluations e on e.id = n.evaluation_id
  where e.classe_id = p_classe and n.deleted_at is null and e.deleted_at is null
    and n.absent = false and n.valeur is not null;

  select case when count(*) = 0 then 0
              else count(*) filter (where p.statut <> 'present')::numeric / count(*)::numeric end
  into v_absenteisme
  from public.presences p
  where p.classe_id = p_classe and p.deleted_at is null;

  select count(*) into v_alertes
  from public.alertes_decrochage a
  where a.etablissement_id = v_etab and a.annee_scolaire_id = v_annee
    and a.statut in ('ouverte', 'transmise') and a.deleted_at is null
    and exists (
      select 1 from public.inscriptions i
      where i.fiche_eleve_id = a.fiche_eleve_id and i.classe_id = p_classe and i.deleted_at is null
    );

  v_score := round(
    0.50 * v_absenteisme
    + 0.30 * (1 - v_reussite)
    + 0.20 * least(1.0, v_alertes::numeric / greatest(v_effectif, 1)::numeric),
    4);
  v_niveau := case when v_score >= 0.6 then 'eleve' when v_score >= 0.35 then 'moyen' else 'faible' end;

  return jsonb_build_object(
    'classe_id', p_classe,
    'effectif', v_effectif,
    'taux_reussite', round(v_reussite, 4),
    'taux_absenteisme', round(v_absenteisme, 4),
    'alertes_decrochage', v_alertes,
    'score_risque', v_score,
    'niveau_risque', v_niveau
  );
end $$;

-- solde_scolarite (reprise de 20260906001512_d6_perception_classe_et_fasttrack_inscription.sql)
create or replace function public.solde_scolarite(p_inscription_id uuid)
returns table(montant_du numeric, montant_paye numeric, solde numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_etablissement uuid;
  v_fiche uuid;
begin
  select i.etablissement_id, i.fiche_eleve_id
    into v_etablissement, v_fiche
  from public.inscriptions i
  where i.id = p_inscription_id;

  if v_etablissement is null then
    raise exception 'INSCRIPTION_INTROUVABLE' using errcode = '23514';
  end if;

  if not coalesce(public.voit_encaissements(v_etablissement), false)
     and not coalesce(public.fiche_famille(v_fiche), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return query
  with insc as (
    select i.id, i.etablissement_id, i.annee_scolaire_id, c.niveau_id
    from public.inscriptions i
    join public.classes c on c.id = i.classe_id
    where i.id = p_inscription_id
  ),
  tarif as (
    select coalesce(
      (select f.montant_annuel from public.frais_scolarite_config f, insc
       where f.etablissement_id = insc.etablissement_id and f.annee_scolaire_id = insc.annee_scolaire_id
         and f.niveau_id = insc.niveau_id and f.deleted_at is null limit 1),
      (select f.montant_annuel from public.frais_scolarite_config f, insc
       where f.etablissement_id = insc.etablissement_id and f.annee_scolaire_id = insc.annee_scolaire_id
         and f.niveau_id is null and f.deleted_at is null limit 1),
      0
    ) as montant
  ),
  paye as (
    select coalesce(sum(montant), 0) as total
    from public.encaissements_scolarite
    where inscription_id = p_inscription_id and statut = 'valide' and type_frais = 'scolarite'
  )
  select tarif.montant, paye.total, tarif.montant - paye.total
  from tarif, paye;
end;
$$;

-- rapprochement_mobile_money (reprise de 20260906001530_orange_money_relance_rapprochement.sql)
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
  if not (coalesce(public.voit_encaissements(p_etablissement_id), false)
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

-- consolider_indicateurs_etablissement (reprise de 20260906001505_m16_banniere_eleves_a_risque.sql)
create or replace function public.consolider_indicateurs_etablissement(p_etab uuid, p_annee uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_effectifs numeric; v_reussite numeric; v_absenteisme numeric;
  v_turnover numeric; v_masse numeric; v_engagement numeric;
  v_eleves_a_risque numeric;
  v_d date; v_f date;
begin
  if not coalesce(public.voit_rapports(p_etab), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  select date_debut, date_fin into v_d, v_f from public.annees_scolaires where id = p_annee;

  select count(*) into v_effectifs
  from public.inscriptions i
  where i.etablissement_id = p_etab and i.annee_scolaire_id = p_annee
    and i.statut = 'active' and i.deleted_at is null;

  select case when count(*) = 0 then 0
              else count(*) filter (where n.valeur / e.bareme >= 0.5)::numeric / count(*)::numeric end
  into v_reussite
  from public.notes n
  join public.evaluations e on e.id = n.evaluation_id
  where n.etablissement_id = p_etab and e.annee_scolaire_id = p_annee
    and n.deleted_at is null and e.deleted_at is null
    and n.absent = false and n.valeur is not null;

  select case when count(*) = 0 then 0
              else count(*) filter (where p.statut <> 'present')::numeric / count(*)::numeric end
  into v_absenteisme
  from public.presences p
  where p.etablissement_id = p_etab and p.annee_scolaire_id = p_annee and p.deleted_at is null;

  select case when count(*) = 0 then 0
              else count(*) filter (where emp.statut in ('demissionnaire','suspendu','retraite'))::numeric / count(*)::numeric end
  into v_turnover
  from public.employes emp
  where emp.etablissement_id = p_etab and emp.deleted_at is null;

  select coalesce(sum(pb.net), 0) into v_masse
  from public.paie_bulletins pb
  where pb.etablissement_id = p_etab and pb.deleted_at is null
    and pb.periode_debut between v_d and v_f;

  select case when count(*) = 0 then 0
              else count(*) filter (where n.date_lecture is not null)::numeric / count(*)::numeric end
  into v_engagement
  from public.notifications n
  where n.etablissement_id = p_etab and n.deleted_at is null
    and n.date_envoi is not null
    and n.date_envoi::date between v_d and v_f;

  -- ★ AJOUTÉ (M16, sous-livrable 2/7) : rafraîchit d'abord la source unique
  -- (statistiques_agregats.risque_reussite), puis compte au seuil 0.6 —
  -- jamais un second calcul parallèle à calculer_score_decrochage.
  perform public.materialiser_risque_reussite(p_etab, p_annee);

  select count(*) into v_eleves_a_risque
  from public.statistiques_agregats sa
  where sa.etablissement_id = p_etab and sa.annee_scolaire_id = p_annee
    and sa.type_agregat = 'risque_reussite'
    and sa.valeur_numeric >= 0.6;

  insert into public.indicateurs_cles (etablissement_id, annee_scolaire_id, code, valeur_numeric, calcule_le, version)
  values
    (p_etab, p_annee, 'effectifs',          v_effectifs,       now(), 1),
    (p_etab, p_annee, 'taux_reussite',      v_reussite,        now(), 1),
    (p_etab, p_annee, 'absentisme',         v_absenteisme,     now(), 1),
    (p_etab, p_annee, 'turnover',           v_turnover,        now(), 1),
    (p_etab, p_annee, 'masse_salariale',    v_masse,           now(), 1),
    (p_etab, p_annee, 'engagement_parents', v_engagement,      now(), 1),
    (p_etab, p_annee, 'eleves_a_risque',    v_eleves_a_risque, now(), 1)
  on conflict (etablissement_id, annee_scolaire_id, code) where periode_id is null and classe_id is null
  do update set valeur_numeric = excluded.valeur_numeric,
                calcule_le = now(),
                version = public.indicateurs_cles.version + 1;

  return 7;
end $$;

-- detecter_anomalies (reprise de 20260906001000_m10_rapports_statistiques.sql)
create or replace function public.detecter_anomalies(p_etab uuid, p_annee uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_total int := 0;
  v_cnt int;
begin
  if not coalesce(public.voit_rapports(p_etab), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  -- Notes : écart > 2 écarts-types à la moyenne de l'évaluation, ou > barème.
  for r in
    select e.id, e.bareme, e.classe_id, avg(n.valeur) as moyenne, stddev_pop(n.valeur) as ecart_type
    from public.evaluations e
    join public.notes n on n.evaluation_id = e.id
    where e.etablissement_id = p_etab and e.annee_scolaire_id = p_annee
      and e.deleted_at is null and n.deleted_at is null and n.absent = false
    group by e.id, e.bareme, e.classe_id
    having count(n.valeur) >= 3
  loop
    insert into public.anomalies_statistiques
      (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, type, severite,
       description, valeur_observee, valeur_attendue, ecart, contexte, signature, statut, detectee_le)
    select n.etablissement_id, p_annee, r.classe_id, n.fiche_eleve_id, 'note',
           case when n.valeur > r.bareme then 'elevee' else 'moyenne' end,
           'Note aberrante : écart statistique à la moyenne de l''évaluation ou dépassement du barème.',
           n.valeur, round(r.moyenne, 2),
           round(abs(n.valeur - r.moyenne), 2),
           jsonb_build_object('evaluation_id', r.id, 'moyenne', round(r.moyenne,2),
                              'ecart_type', round(coalesce(r.ecart_type,0),2), 'bareme', r.bareme),
           md5(p_annee::text || ':note:' || n.fiche_eleve_id::text || ':' || r.id::text),
           'ouverte', now()
    from public.notes n
    where n.evaluation_id = r.id and n.deleted_at is null and n.absent = false and n.valeur is not null
      and (n.valeur > r.bareme or abs(n.valeur - r.moyenne) > 2 * coalesce(r.ecart_type, 0))
    on conflict (etablissement_id, signature) do nothing;
    get diagnostics v_cnt = row_count;
    v_total := v_total + v_cnt;
  end loop;

  -- Absences : taux individuel > 30 % sur l'année (au moins 5 séances).
  for r in
    select i.fiche_eleve_id as fiche, i.classe_id as classe,
           count(*) as total,
           count(*) filter (where p.statut <> 'present') as absences
    from public.presences p
    join public.inscriptions i on i.fiche_eleve_id = p.fiche_eleve_id
                              and i.annee_scolaire_id = p_annee and i.statut = 'active' and i.deleted_at is null
    where p.etablissement_id = p_etab and p.annee_scolaire_id = p_annee and p.deleted_at is null
    group by i.fiche_eleve_id, i.classe_id
    having count(*) >= 5
       and count(*) filter (where p.statut <> 'present')::numeric / count(*)::numeric > 0.3
  loop
    insert into public.anomalies_statistiques
      (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, type, severite,
       description, valeur_observee, valeur_attendue, ecart, contexte, signature, statut, detectee_le)
    values
      (p_etab, p_annee, r.classe, r.fiche, 'absence', 'elevee',
       'Absentéisme individuel excessif (taux > 30 %).',
       round(r.absences::numeric / r.total::numeric, 4), 0.30,
       round(r.absences::numeric / r.total::numeric - 0.30, 4),
       jsonb_build_object('total_seances', r.total, 'absences', r.absences),
       md5(p_annee::text || ':absence:' || r.fiche::text),
       'ouverte', now())
    on conflict (etablissement_id, signature) do nothing;
    get diagnostics v_cnt = row_count;
    v_total := v_total + v_cnt;
  end loop;

  return v_total;
end $$;

-- generer_resume_executif (reprise de 20260906001000_m10_rapports_statistiques.sql)
create or replace function public.generer_resume_executif(p_etab uuid, p_annee uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_libelle text;
  v_effectifs numeric; v_reussite numeric; v_absenteisme numeric;
  v_turnover numeric; v_masse numeric; v_engagement numeric;
  v_recos text := ''; v_nb int := 0; r record; v_resume text;
begin
  if not coalesce(public.voit_rapports(p_etab), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  select libelle into v_libelle from public.annees_scolaires where id = p_annee;
  perform public.consolider_indicateurs_etablissement(p_etab, p_annee);

  select coalesce(valeur_numeric, 0) into v_effectifs  from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'effectifs';
  select coalesce(valeur_numeric, 0) into v_reussite   from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'taux_reussite';
  select coalesce(valeur_numeric, 0) into v_absenteisme from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'absentisme';
  select coalesce(valeur_numeric, 0) into v_turnover   from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'turnover';
  select coalesce(valeur_numeric, 0) into v_masse      from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'masse_salariale';
  select coalesce(valeur_numeric, 0) into v_engagement from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'engagement_parents';

  for r in
    select titre from public.recommandations_strategiques
    where etablissement_id = p_etab and annee_scolaire_id = p_annee
      and statut in ('proposee', 'validee')
    order by case priorite when 'haute' then 0 when 'moyenne' then 1 else 2 end, cree_le desc
    limit 3
  loop
    if v_nb > 0 then v_recos := v_recos || ' ; '; end if;
    v_recos := v_recos || r.titre;
    v_nb := v_nb + 1;
  end loop;

  v_resume := 'Résumé exécutif — ' || coalesce(v_libelle, 'année scolaire') || E'\n'
    || 'Effectifs : ' || v_effectifs || ' élèves inscrits.' || E'\n'
    || 'Taux de réussite : ' || round(v_reussite * 100, 1) || ' %.' || E'\n'
    || 'Absentéisme : ' || round(v_absenteisme * 100, 1) || ' %.' || E'\n'
    || 'Turn-over RH : ' || round(v_turnover * 100, 1) || ' %.' || E'\n'
    || 'Masse salariale : ' || v_masse || '.' || E'\n'
    || 'Engagement des parents (taux d''ouverture) : ' || round(v_engagement * 100, 1) || ' %.' || E'\n';

  if v_nb > 0 then
    v_resume := v_resume || 'Recommandations : ' || v_recos || '.';
  else
    v_resume := v_resume || 'Aucune recommandation stratégique en attente.';
  end if;

  return v_resume;
end $$;

-- recommander_actions (reprise de 20260906001000_m10_rapports_statistiques.sql)
create or replace function public.recommander_actions(p_etab uuid, p_annee uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  r record; v_score numeric; v_type text; v_priorite text; v_titre text; v_desc text;
begin
  if not coalesce(public.voit_rapports(p_etab), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  for r in
    select id from public.classes c
    where c.etablissement_id = p_etab and c.annee_scolaire_id = p_annee
      and c.actif and c.deleted_at is null
  loop
    select (public.risque_classe(r.id)->>'score_risque')::numeric into v_score;

    if v_score >= 0.6 then
      v_type := 'tutorat'; v_priorite := 'haute';
      v_titre := 'Plan de tutorat et de renforcement pour la classe à risque';
      v_desc := 'Score de risque élevé (' || round(v_score,2)
             || '). Séances de renforcement et suivi tutorat ciblé des élèves fragiles.';
    elsif v_score >= 0.35 then
      v_type := 'renforcement'; v_priorite := 'moyenne';
      v_titre := 'Renforcement pédagogique de la classe';
      v_desc := 'Score de risque moyen (' || round(v_score,2)
             || '). Consolider les acquis et surveiller l''assiduité.';
    else
      continue;
    end if;

    insert into public.recommandations_strategiques
      (etablissement_id, annee_scolaire_id, classe_id, type, titre, description,
       justification, priorite, statut, cree_le)
    values
      (p_etab, p_annee, r.id, v_type, v_titre, v_desc,
       jsonb_build_object('score_risque', v_score, 'classe_id', r.id),
       v_priorite, 'proposee', now())
    on conflict (etablissement_id, annee_scolaire_id, classe_id, type)
      where classe_id is not null do nothing;
  end loop;

  return (select count(*) from public.recommandations_strategiques
          where etablissement_id = p_etab and annee_scolaire_id = p_annee);
end $$;

-- recommander_seances (reprise de 20260906001100_m11_planification_agenda.sql)
create or replace function public.recommander_seances(p_etab uuid, p_annee uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  r record; v_reussite numeric; v_absenteisme numeric;
begin
  if not coalesce(public.droit(p_etab, array['planification.consulter', 'planification.administrer', 'planification.generer']), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  for r in
    select c.id as classe, c.enseignant_principal_id as prof
    from public.classes c
    where c.etablissement_id = p_etab and c.annee_scolaire_id = p_annee
      and c.actif and c.deleted_at is null and c.enseignant_principal_id is not null
  loop
    select case when count(*) = 0 then 0
                else count(*) filter (where n.valeur / e.bareme >= 0.5)::numeric / count(*)::numeric end
    into v_reussite
    from public.notes n
    join public.evaluations e on e.id = n.evaluation_id
    where e.classe_id = r.classe and n.deleted_at is null and e.deleted_at is null and n.absent = false;

    select case when count(*) = 0 then 0
                else count(*) filter (where p.statut <> 'present')::numeric / count(*)::numeric end
    into v_absenteisme
    from public.presences p
    where p.classe_id = r.classe and p.deleted_at is null;

    if v_absenteisme > 0.2 or v_reussite < 0.6 then
      insert into public.progression_pedagogique
        (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, seance, objectifs, statut, date_prevue)
      values (p_etab, p_annee, r.classe, r.prof, 'Séance de rattrapage',
              'Consolider les acquis (difficultés détectées en M6/M7)', 'proposee', current_date + 7)
      on conflict (etablissement_id, annee_scolaire_id, classe_id)
        where statut = 'proposee' do nothing;
    end if;
  end loop;

  return (select count(*) from public.progression_pedagogique
          where etablissement_id = p_etab and annee_scolaire_id = p_annee and statut = 'proposee');
end $$;

-- detecter_anomalies_usage_ia (reprise de 20260906001520_facturation_quota_tuteur_ia.sql)
create or replace function public.detecter_anomalies_usage_ia(p_etablissement_id uuid)
returns table (
  profile_id uuid,
  role_ia public.role_ia,
  nb_messages_24h bigint,
  anomalie text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (coalesce(public.voit_rapports(p_etablissement_id), false) or coalesce(public.est_admin_gsg(), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  return query
  select c.profile_id,
         public.determiner_role_ia(p_etablissement_id, c.profile_id),
         count(*)::bigint,
         'volume_quotidien'::text
  from public.ai_messages m
  join public.ai_conversations c on c.id = m.conversation_id
  where c.etablissement_id = p_etablissement_id
    and m.sender = 'user'
    and m.created_at > now() - interval '24 hours'
  group by c.profile_id
  having count(*) >= coalesce((
    select (valeur->>'valeur')::int from public.parametres_globaux
    where cle = 'seuil_anomalie_usage_ia_quotidien'
  ), 2147483647);
end;
$$;

-- detecter_anomalies_commandes (reprise de 20260906001513_qa_prelancement_audit_rpc.sql)
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
  if auth.uid() is not null and not coalesce(public.droit(p_etablissement, array['marketplace.paiement.lire', 'marketplace.commande.lire', 'rapports.consulter']), false) then
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

-- predire_pics_charge (reprise de 20260906001513_qa_prelancement_audit_rpc.sql)
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
  if auth.uid() is not null and not coalesce(public.voit_rapports(p_etablissement) or public.droit(p_etablissement, array['planification.consulter', 'planification.administrer', 'planification.generer']), false) then
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

-- predire_presence (reprise de 20260906001513_qa_prelancement_audit_rpc.sql)
create or replace function public.predire_presence(p_etab uuid, p_date date)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is not null and not coalesce(public.voit_rapports(p_etab) or public.droit(p_etab, array['scolarite.presence.lire', 'scolarite.presence.gerer']), false) then
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

-- initier_transaction_cinetpay (reprise de 20260906001519_facturation_abonnement_premium_eleve.sql)
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
      if not (coalesce(public.droit(p_etablissement, array['comptabilite.ecrire']), false) or coalesce(public.est_admin_gsg(), false)) then
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
