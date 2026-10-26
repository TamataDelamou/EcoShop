-- ============================================================================
-- EcoShop — REG-22 suite : fiche élève restreinte, cahier de liaison ouvert
-- au surveillant général (décisions du porteur de projet, 2026-10-26)
-- ============================================================================
-- 1. Fiche élève complète (matricule, date et lieu de naissance, parents,
--    personne à prévenir, quartier…) : direction, secrétariat (inscriptions,
--    fiches, liens parents), surveillant général (absences, sanctions),
--    enseignants de la classe de l'élève, et la famille. Le reste du
--    personnel (agent du portail, chauffeur, bibliothécaire, caissier…) ne
--    voit que l'annuaire : nom, prénom, classe. Jamais le matricule ni la
--    date de naissance : ce sont les deux facteurs de la liaison parent ; un
--    chauffeur qui les lirait pourrait se relier à n'importe quel enfant.
--    Minimisation des données des mineurs (cahier §34.2). Aucune photo n'est
--    stockée aujourd'hui : l'annuaire la portera quand elle existera.
-- 2. Inscriptions (classe, statut, bourse ; ni matricule ni naissance) :
--    lisibles aussi par les postes qui en ont besoin (encaissements, notes).
-- 3. Cahier de liaison : le surveillant général écrit aux parents d'un
--    élève, mêmes règles que l'enseignant (mot rattaché à l'élève) ; chaque
--    mot écrit est désormais inscrit au journal d'audit.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Fiche complète
-- ---------------------------------------------------------------------------
create or replace function public.voit_fiche_complete(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.droit(public.etablissement_fiche(p_fiche), array[
           'scolarite.eleve.gerer', 'scolarite.inscription.gerer', 'scolarite.relation.gerer',
           'scolarite.presence.gerer', 'scolarite.sanction.gerer'])
      or public.enseigne_eleve(p_fiche);
$$;
grant execute on function public.voit_fiche_complete(uuid) to authenticated;

create or replace function public.fiche_visible(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.fiches_eleves f
    where f.id = p_fiche and f.deleted_at is null
      and (
        public.voit_fiche_complete(f.id)
        or f.profile_id = auth.uid()
        or public.est_parent_confirme(f.id)
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. Inscriptions
-- ---------------------------------------------------------------------------
drop policy if exists "inscriptions_select_visible" on public.inscriptions;
create policy "inscriptions_select_visible" on public.inscriptions for select using (
  public.fiche_visible(fiche_eleve_id)
  or public.voit_encaissements(etablissement_id)
  or public.voit_notes_classe(classe_id)
);

-- ---------------------------------------------------------------------------
-- 3. Annuaire limité, pour tout le personnel de l'école
-- ---------------------------------------------------------------------------
create or replace function public.annuaire_eleves(p_etablissement uuid, p_recherche text default null,
                                                  p_classe uuid default null)
returns table (fiche_id uuid, nom text, prenom text, classe_id uuid, classe text)
language plpgsql stable security definer set search_path = public
as $$
declare v_motif text := '%' || lower(trim(coalesce(p_recherche, ''))) || '%';
begin
  if not coalesce(public.est_personnel(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return query
  select f.id, f.nom, f.prenom, c.id, c.nom
    from public.fiches_eleves f
    left join public.inscriptions i on i.fiche_eleve_id = f.id and i.deleted_at is null
         and i.annee_scolaire_id = (select a.id from public.annees_scolaires a
                                     where a.etablissement_id = p_etablissement and a.courante limit 1)
    left join public.classes c on c.id = i.classe_id
   where f.etablissement_id = p_etablissement and f.deleted_at is null
     and (p_classe is null or c.id = p_classe)
     and lower(coalesce(f.nom, '') || ' ' || coalesce(f.prenom, '')) like v_motif
   order by c.nom nulls last, f.nom, f.prenom
   limit 300;
end;
$$;
revoke all on function public.annuaire_eleves(uuid, text, uuid) from public, anon;
grant execute on function public.annuaire_eleves(uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Cahier de liaison : le surveillant général
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('scolarite.liaison.ecrire', 'scolarite', 'Écrire aux parents (cahier de liaison)',
   'Mot aux parents d''un élève de l''école, comme l''enseignant de sa classe. Chaque mot est journalisé.')
on conflict (code) do nothing;

update public.modeles_postes
   set codes = codes || array['scolarite.liaison.ecrire']
 where code = 'surveillant_general' and not ('scolarite.liaison.ecrire' = any (codes));
insert into public.poste_permissions (poste_id, permission_code)
select p.id, 'scolarite.liaison.ecrire' from public.postes p
 where p.modele_code = 'surveillant_general' and p.deleted_at is null
on conflict do nothing;

create or replace function public.ecrit_liaison(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.fiches_eleves f
    where f.id = p_fiche and f.deleted_at is null
      and (coalesce(public.est_direction(f.etablissement_id), false)
           or (coalesce(public.est_personnel(f.etablissement_id), false)
               and coalesce(public.a_permission(f.etablissement_id, 'scolarite.liaison.ecrire'), false))
           or exists (
             select 1 from public.inscriptions i
             join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
             where i.fiche_eleve_id = f.id and i.statut = 'active' and i.deleted_at is null
               and public.est_enseignant_affecte(i.classe_id))));
$$;

create or replace function public.ecrire_mot_liaison(p_id uuid, p_fiche uuid, p_corps text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_eleve text;
  v_n integer := 0;
  d uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if public.message_liaison_deja_recu(p_id) then
    return jsonb_build_object('id', p_id, 'deja_recu', true);
  end if;
  if not public.ecrit_liaison(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_corps, ''))) < 1 then
    raise exception 'TEXTE_VIDE' using errcode = '22023';
  end if;
  select etablissement_id, prenom into v_etab, v_eleve from public.fiches_eleves where id = p_fiche;

  insert into public.messages_liaison (id, etablissement_id, fiche_eleve_id, auteur_id, corps)
  values (p_id, v_etab, p_fiche, auth.uid(), trim(p_corps));

  -- Journal : qui a écrit, au sujet de quel élève (le texte reste dans le cahier).
  perform public.enregistrer_audit(v_etab, 'mot_liaison', p_id, 'ecrit', null,
    jsonb_build_object('longueur', char_length(trim(p_corps))), p_fiche);

  for d in select * from public.parents_confirmes(p_fiche) loop
    perform public.notifier_push(v_etab, d, 'cahier_liaison',
      'Cahier de liaison de ' || coalesce(v_eleve, 'votre enfant') || ' : nouveau mot',
      jsonb_build_object('message_id', p_id, 'fiche_eleve_id', p_fiche));
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('id', p_id, 'deja_recu', false, 'parents', v_n);
end;
$$;
revoke execute on function public.ecrire_mot_liaison(uuid, uuid, text) from public, anon;
grant execute on function public.ecrire_mot_liaison(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Contrôles d'école des écritures : indépendants de ce que l'appelant voit
-- ---------------------------------------------------------------------------
-- Ces déclencheurs vérifient seulement que l'élève, la classe ou l'année
-- appartiennent à la même école que la ligne écrite. Exécutés avec les droits
-- de l'appelant, ils lisaient la fiche sous sa RLS : depuis la restriction
-- ci-dessus, un écrivain légitime qui ne voit pas la fiche complète (censeur
-- qui saisit des notes ou des bulletins, comptable pour un don) aurait été
-- refusé à tort. Ils ne renvoient aucune donnée.
alter function public.alertes_verifie_tenant() security definer;
alter function public.anomalies_verifie_tenant() security definer;
alter function public.appreciations_verifie_tenant() security definer;
alter function public.bulletins_verifie_tenant() security definer;
alter function public.dons_verifie_tenant() security definer;
alter function public.inscriptions_verifie_tenant() security definer;
alter function public.notes_verifie_tenant() security definer;
alter function public.presences_verifie_tenant() security definer;
alter function public.rapports_verifie_tenant() security definer;
alter function public.relations_verifie_tenant() security definer;
alter function public.retards_verifie_tenant() security definer;
alter function public.sanctions_verifie_tenant() security definer;
alter function public.statistiques_verifie_tenant() security definer;
