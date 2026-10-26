-- ============================================================================
-- EcoShop — REG-22 partie C, étape 2 : postes du personnel
-- ============================================================================
-- 1. Rôle « personnel » (migration 1566) : administratif et technique, droits
--    venus UNIQUEMENT du poste. « direction » est réservé au fondateur et au
--    directeur. Invitation : poste obligatoire pour le personnel ; seule la
--    direction invite la direction.
-- 2. Codes de métier : portail.scanner (scanner les cartes, sans la gestion
--    des absences) ; comptabilite.valider (valider les pièces, clôturer les
--    périodes : séparé de la saisie). Le chauffeur n'a pas de code : il suit
--    le circuit qui lui est confié, et rien d'autre.
-- 3. Les 17 codes jamais vérifiés : 4 branchés (RH : congés, contrats,
--    fiches des employés en lecture, paie), 13 retirés.
-- 4. Modèles de postes (données de référence) ; postes créés pour chaque
--    école à sa création, rattrapés pour les écoles existantes ; poste
--    personnalisé à partir d'un modèle.
-- 5. Séparation des tâches : un poste ne cumule pas l'encaissement avec la
--    saisie ou la validation comptable.
-- 6. Faille d'élévation fermée : écrire directement dans postes,
--    poste_permissions ou etablissements_membres permettait à un membre doté
--    de « gérer les postes » de s'ajouter tout droit, et à un membre doté de
--    « gérer les membres » de se donner le rôle direction. Ces tables ne
--    s'écrivent plus que par les fonctions ci-dessous, réservées à la
--    direction.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Faille trouvée en testant les postes (antérieure à REG-22) : pour un
--    compte sans rôle racine (membre invité tout juste créé, compte neuf),
--    est_admin_gsg() valait NULL au lieu de faux. « faux ou NULL » donnant
--    NULL, et « if not NULL » ne levant rien, les contrôles construits sur
--    a_permission sans coalesce (gere_presences, gere_inscriptions, est_rh,
--    est_comptable…) laissaient passer : l'agent du portail lisait le
--    tableau des absences. Corrigé à la source.
-- ---------------------------------------------------------------------------
create or replace function public.est_admin_gsg()
returns boolean
language sql stable set search_path = public
as $$
  select coalesce(public.mon_role_racine() = 'admin_gsg', false);
$$;

-- ---------------------------------------------------------------------------
-- 1. Catalogue
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('portail.scanner', 'portail', 'Scanner les cartes au portail',
   'Entrées et sorties des élèves au portail, même sans réseau. Ne donne pas les absences.'),
  ('comptabilite.valider', 'comptabilite', 'Valider et clôturer',
   'Valider les pièces comptables et clôturer les périodes. Jamais avec l''encaissement.')
on conflict (code) do nothing;

-- Codes sans effet retirés (aucune fonction ne les vérifie).
delete from public.poste_permissions where permission_code in (
  'comm.voir_logs', 'comptabilite.export', 'comptabilite.plan.gerer', 'etablissement.invitation.gerer',
  'etablissement.membre.lire', 'marketplace.catalogue.lire', 'marketplace.commande.creer',
  'marketplace.profil_public.lier', 'marketplace.profil_public.lire', 'marketplace.souscompte.gerer',
  'observabilite.metriques.lire', 'observabilite.prediction.lire', 'observabilite.sante.lire');
delete from public.permissions where code in (
  'comm.voir_logs', 'comptabilite.export', 'comptabilite.plan.gerer', 'etablissement.invitation.gerer',
  'etablissement.membre.lire', 'marketplace.catalogue.lire', 'marketplace.commande.creer',
  'marketplace.profil_public.lier', 'marketplace.profil_public.lire', 'marketplace.souscompte.gerer',
  'observabilite.metriques.lire', 'observabilite.prediction.lire', 'observabilite.sante.lire');

-- ---------------------------------------------------------------------------
-- 2. Branchements
-- ---------------------------------------------------------------------------
create or replace function public.peut_scanner_portail(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.gere_presences(p_etablissement), false)
      or coalesce(public.a_permission(p_etablissement, 'portail.scanner'), false);
$$;

create or replace function public.est_comptable_validation(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.est_admin_gsg(), false)
      or coalesce(public.est_direction(p_etablissement), false)
      or coalesce(public.a_permission(p_etablissement, 'comptabilite.valider'), false);
$$;

create or replace function public.voit_employes(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.est_rh(p_etablissement), false)
      or coalesce(public.a_permission(p_etablissement, 'rh.employe.voir'), false);
$$;

grant execute on function public.peut_scanner_portail(uuid), public.est_comptable_validation(uuid),
  public.voit_employes(uuid) to authenticated;

drop policy if exists contrats_ecriture_rh on public.contrats;
create policy contrats_ecriture_rh on public.contrats for all
  using (public.est_rh(etablissement_id) or public.a_permission(etablissement_id, 'rh.contrat.gerer'))
  with check (public.est_rh(etablissement_id) or public.a_permission(etablissement_id, 'rh.contrat.gerer'));
drop policy if exists conges_validation_rh on public.conges;
create policy conges_validation_rh on public.conges for update
  using (public.est_rh(etablissement_id) or public.a_permission(etablissement_id, 'rh.conge.valider'));
drop policy if exists paie_select on public.paie_bulletins;
create policy paie_select on public.paie_bulletins for select
  using (public.est_rh(etablissement_id) or public.a_permission(etablissement_id, 'rh.paie.gerer')
         or public.est_employe_self(employe_id));
drop policy if exists paie_ecriture_rh on public.paie_bulletins;
create policy paie_ecriture_rh on public.paie_bulletins for all
  using (public.est_rh(etablissement_id) or public.a_permission(etablissement_id, 'rh.paie.gerer'))
  with check (public.est_rh(etablissement_id) or public.a_permission(etablissement_id, 'rh.paie.gerer'));

-- ---------------------------------------------------------------------------
-- 3. Modèles de postes
-- ---------------------------------------------------------------------------
create table if not exists public.modeles_postes (
  code text primary key check (code ~ '^[a-z_]{3,40}$'),
  nom text not null,
  description text not null,
  role text not null check (role in ('direction', 'enseignant', 'personnel')),
  codes text[] not null default '{}',
  ordre integer not null default 0
);
alter table public.modeles_postes enable row level security;
revoke insert, update, delete on public.modeles_postes from public, anon, authenticated;
grant select on public.modeles_postes to authenticated;
drop policy if exists modeles_postes_lecture on public.modeles_postes;
create policy modeles_postes_lecture on public.modeles_postes for select to authenticated using (true);

insert into public.modeles_postes (code, nom, description, role, codes, ordre) values
  ('fondateur', 'Fondateur / promoteur', 'Tous les droits ; nomme la direction. Actions journalisées.', 'direction', '{}', 10),
  ('directeur', 'Directeur / proviseur / principal', 'Tous les droits dans l''école.', 'direction', '{}', 20),
  ('directeur_etudes', 'Directeur des études / censeur', 'Classes, périodes, emploi du temps, évaluations, notes, bulletins.', 'personnel',
   array['scolarite.classe.gerer', 'scolarite.periode.gerer', 'planification.administrer', 'planification.generer',
         'scolarite.evaluation.gerer', 'scolarite.note.lire', 'scolarite.note.gerer', 'scolarite.bulletin.gerer',
         'scolarite.appreciation.gerer', 'scolarite.parametres.gerer', 'rh.enseignant.affecter', 'rapports.generer'], 30),
  ('surveillant_general', 'Surveillant général', 'Appel, absences, retards, sanctions, portail, modération des groupes.', 'personnel',
   array['scolarite.presence.gerer', 'scolarite.presence.lire', 'scolarite.sanction.gerer', 'scolarite.sanction.lire',
         'scolarite.evenement.gerer', 'portail.scanner', 'communication.groupe.moderer'], 40),
  ('comptable', 'Comptable / économe / intendant', 'Comptabilité (saisie, validation, clôture), lecture des encaissements. Pas d''encaissement.', 'personnel',
   array['comptabilite.lire', 'comptabilite.ecrire', 'comptabilite.valider', 'scolarite.encaissement.lire'], 50),
  ('caissier', 'Caissier', 'Encaissements de scolarité et reçus. Pas de comptabilité ni de clôture.', 'personnel',
   array['scolarite.encaissement.gerer', 'scolarite.encaissement.lire'], 60),
  ('secretaire', 'Secrétaire', 'Inscriptions, fiches des élèves, liens avec les parents.', 'personnel',
   array['scolarite.inscription.gerer', 'scolarite.eleve.gerer', 'scolarite.relation.gerer'], 70),
  ('enseignant', 'Enseignant', 'Ses classes : notes, appel, cahier de liaison (par affectation).', 'enseignant', '{}', 80),
  ('professeur_principal', 'Professeur principal', 'Comme l''enseignant, plus les bulletins et appréciations de sa classe (titulaire).', 'enseignant', '{}', 90),
  ('bibliothecaire', 'Bibliothécaire', 'Livres, prêts et retours.', 'personnel', array['bibliotheque.gerer'], 100),
  ('agent_portail', 'Agent du portail', 'Scanner les cartes au portail, rien d''autre.', 'personnel', array['portail.scanner'], 110),
  ('chauffeur', 'Chauffeur / convoyeur', 'Son circuit de transport seulement (par affectation au circuit).', 'personnel', '{}', 120)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description, role = excluded.role,
      codes = excluded.codes, ordre = excluded.ordre;

alter table public.postes add column if not exists modele_code text references public.modeles_postes (code);

-- Séparation des tâches, à chaque ajout de droit sur un poste.
create or replace function public.poste_permissions_separation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.permission_code = 'scolarite.encaissement.gerer'
      and exists (select 1 from public.poste_permissions
                  where poste_id = new.poste_id and permission_code in ('comptabilite.ecrire', 'comptabilite.valider')))
     or (new.permission_code in ('comptabilite.ecrire', 'comptabilite.valider')
      and exists (select 1 from public.poste_permissions
                  where poste_id = new.poste_id and permission_code = 'scolarite.encaissement.gerer')) then
    raise exception 'CUMUL_INTERDIT' using errcode = '23514',
      hint = 'Un même poste ne peut pas encaisser et tenir ou valider la comptabilité.';
  end if;
  return new;
end $$;
drop trigger if exists poste_permissions_separation_trg on public.poste_permissions;
create trigger poste_permissions_separation_trg before insert or update on public.poste_permissions
  for each row execute function public.poste_permissions_separation();

-- Postes par défaut d'une école (idempotent).
create or replace function public.creer_postes_par_defaut(p_etablissement uuid)
returns integer
language plpgsql volatile security definer set search_path = public
as $$
declare m record; v_poste uuid; v_n integer := 0;
begin
  for m in select * from public.modeles_postes order by ordre loop
    if exists (select 1 from public.postes where etablissement_id = p_etablissement and modele_code = m.code
               and deleted_at is null) then
      continue;
    end if;
    insert into public.postes (etablissement_id, nom, code, modele_code, description)
    values (p_etablissement, m.nom, upper(m.code), m.code, m.description)
    on conflict do nothing
    returning id into v_poste;
    if v_poste is null then
      continue;
    end if;
    insert into public.poste_permissions (poste_id, permission_code)
    select v_poste, c from unnest(m.codes) c where exists (select 1 from public.permissions where code = c);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
revoke all on function public.creer_postes_par_defaut(uuid) from public, anon, authenticated;

create or replace function public.etablissements_postes_par_defaut()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.creer_postes_par_defaut(new.id);
  return new;
end $$;
drop trigger if exists etablissements_postes_par_defaut_trg on public.etablissements;
create trigger etablissements_postes_par_defaut_trg after insert on public.etablissements
  for each row execute function public.etablissements_postes_par_defaut();

-- Rattrapage des écoles existantes.
select public.creer_postes_par_defaut(id) from public.etablissements;

-- ---------------------------------------------------------------------------
-- 4. Écritures réservées à la direction, par fonctions
-- ---------------------------------------------------------------------------
drop policy if exists postes_ecriture_direction on public.postes;
drop policy if exists poste_permissions_ecriture on public.poste_permissions;
drop policy if exists membres_ecriture_direction on public.etablissements_membres;
revoke insert, update, delete on public.postes, public.poste_permissions, public.etablissements_membres from anon, authenticated;

-- Catalogue en français, groupé par domaine (écran des postes).
create or replace function public.catalogue_permissions()
returns table (code text, domaine text, libelle text, description text)
language sql stable security definer set search_path = public
as $$
  select code, domaine, libelle, description from public.permissions order by domaine, libelle;
$$;

create or replace function public.postes_etablissement(p_etablissement uuid)
returns table (id uuid, nom text, modele_code text, description text, codes text[], membres integer, actif boolean)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not coalesce(public.gere_membres(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return query
  select p.id, p.nom, p.modele_code, p.description,
         coalesce(array(select pp.permission_code from public.poste_permissions pp where pp.poste_id = p.id
                        order by 1), '{}'),
         (select count(*)::int from public.etablissements_membres m
           where m.poste_id = p.id and m.actif and m.deleted_at is null),
         p.actif
    from public.postes p
   where p.etablissement_id = p_etablissement and p.deleted_at is null
   order by coalesce((select ordre from public.modeles_postes x where x.code = p.modele_code), 1000), p.nom;
end;
$$;

-- Vérifie et pose les droits d'un poste (codes connus, séparation des tâches).
create or replace function public.poser_droits_poste(p_poste uuid, p_codes text[])
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare v_inconnu text;
begin
  select c into v_inconnu from unnest(coalesce(p_codes, '{}')) c
   where not exists (select 1 from public.permissions where code = c) limit 1;
  if v_inconnu is not null then
    raise exception 'DROIT_INCONNU' using errcode = '22023', detail = v_inconnu;
  end if;
  if 'scolarite.encaissement.gerer' = any (p_codes)
     and (p_codes && array['comptabilite.ecrire', 'comptabilite.valider']) then
    raise exception 'CUMUL_INTERDIT' using errcode = '23514',
      hint = 'Un même poste ne peut pas encaisser et tenir ou valider la comptabilité.';
  end if;
  delete from public.poste_permissions where poste_id = p_poste and permission_code <> all (coalesce(p_codes, '{}'));
  insert into public.poste_permissions (poste_id, permission_code)
  select p_poste, c from unnest(coalesce(p_codes, '{}')) c
  on conflict do nothing;
end;
$$;
revoke all on function public.poser_droits_poste(uuid, text[]) from public, anon, authenticated;

-- Poste personnalisé à partir d'un modèle (direction seulement).
create or replace function public.creer_poste(p_etablissement uuid, p_modele text, p_nom text, p_codes text[])
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare v_id uuid;
begin
  if not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_nom, ''))) < 2 then
    raise exception 'NOM_OBLIGATOIRE' using errcode = '22023';
  end if;
  if p_modele is not null and not exists (select 1 from public.modeles_postes where code = p_modele) then
    raise exception 'MODELE_INCONNU' using errcode = '22023';
  end if;
  insert into public.postes (etablissement_id, nom, modele_code, description)
  values (p_etablissement, trim(p_nom), p_modele, (select description from public.modeles_postes where code = p_modele))
  returning id into v_id;
  perform public.poser_droits_poste(v_id, p_codes);
  return v_id;
end;
$$;

create or replace function public.modifier_poste(p_poste uuid, p_nom text, p_codes text[], p_actif boolean default true)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.postes where id = p_poste and deleted_at is null;
  if v_etab is null or not coalesce(public.est_direction(v_etab), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_nom, ''))) < 2 then
    raise exception 'NOM_OBLIGATOIRE' using errcode = '22023';
  end if;
  if not coalesce(p_actif, true) and exists (select 1 from public.etablissements_membres
                                              where poste_id = p_poste and actif and deleted_at is null) then
    raise exception 'POSTE_OCCUPE' using errcode = '23514';
  end if;
  update public.postes set nom = trim(p_nom), actif = coalesce(p_actif, true), updated_at = now() where id = p_poste;
  perform public.poser_droits_poste(p_poste, p_codes);
end;
$$;

-- Fiche d'un membre : liste du personnel de l'école.
create or replace function public.membres_personnel(p_etablissement uuid)
returns table (profile_id uuid, nom_complet text, role text, poste_id uuid, poste text, actif boolean)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not coalesce(public.gere_membres(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return query
  select m.profile_id, trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), m.role_dans_etablissement,
         m.poste_id, po.nom, m.actif
    from public.etablissements_membres m
    join public.profiles p on p.id = m.profile_id
    left join public.postes po on po.id = m.poste_id
   where m.etablissement_id = p_etablissement and m.deleted_at is null
     and m.role_dans_etablissement not in ('eleve', 'parent')
   order by m.role_dans_etablissement, 2;
end;
$$;

-- Changer le rôle ou le poste d'un membre (direction seulement ; jamais
-- soi-même).
create or replace function public.modifier_membre(p_etablissement uuid, p_compte uuid, p_role text, p_poste uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare v_ancien record;
begin
  if not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_compte = auth.uid() then
    raise exception 'MODIFICATION_SOI_MEME' using errcode = '42501';
  end if;
  if p_role not in ('direction', 'enseignant', 'personnel') then
    raise exception 'ROLE_INVALIDE' using errcode = '22023';
  end if;
  if p_role = 'personnel' and p_poste is null then
    raise exception 'POSTE_OBLIGATOIRE' using errcode = '22023';
  end if;
  if p_poste is not null and not exists (select 1 from public.postes where id = p_poste
                                         and etablissement_id = p_etablissement and actif and deleted_at is null) then
    raise exception 'POSTE_INVALIDE' using errcode = '22023';
  end if;
  select role_dans_etablissement, poste_id into v_ancien from public.etablissements_membres
   where profile_id = p_compte and etablissement_id = p_etablissement and deleted_at is null
     and role_dans_etablissement not in ('eleve', 'parent', 'fondateur_reseau');
  if not found then
    raise exception 'MEMBRE_INCONNU' using errcode = 'P0002';
  end if;
  update public.etablissements_membres set role_dans_etablissement = p_role, poste_id = p_poste
   where profile_id = p_compte and etablissement_id = p_etablissement;
  perform public.enregistrer_audit(p_etablissement, 'membre', p_compte, 'role_poste',
    jsonb_build_object('role', v_ancien.role_dans_etablissement, 'poste', v_ancien.poste_id),
    jsonb_build_object('role', p_role, 'poste', p_poste));
end;
$$;

create or replace function public.libelle_role_invitation(p_role public.role_racine)
returns text
language sql immutable set search_path = public
as $$
  select case p_role::text
    when 'enseignant' then 'Enseignant'
    when 'direction' then 'Direction'
    when 'personnel' then 'Personnel administratif et technique'
    when 'vendeur' then 'Vendeur'
    else p_role::text
  end;
$$;

revoke all on function public.catalogue_permissions() from public, anon;
revoke all on function public.postes_etablissement(uuid) from public, anon;
revoke all on function public.creer_poste(uuid, text, text, text[]) from public, anon;
revoke all on function public.modifier_poste(uuid, text, text[], boolean) from public, anon;
revoke all on function public.membres_personnel(uuid) from public, anon;
revoke all on function public.modifier_membre(uuid, uuid, text, uuid) from public, anon;
grant execute on function public.catalogue_permissions(), public.postes_etablissement(uuid),
  public.creer_poste(uuid, text, text, text[]), public.modifier_poste(uuid, text, text[], boolean),
  public.membres_personnel(uuid), public.modifier_membre(uuid, uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Fonctions reprises (contrôle d'entrée seul modifié)
-- ---------------------------------------------------------------------------

-- enregistrer_pointage (reprise de 20260906001546_pointage_portail_sms.sql)
create or replace function public.enregistrer_pointage(
  p_id uuid,
  p_etablissement uuid,
  p_jeton text,
  p_sens text,
  p_scanne_le timestamptz,
  p_appareil text default null
)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_tz text := public.fuseau_etablissement(p_etablissement);
  v_scanne timestamptz := least(coalesce(p_scanne_le, now()), now());
  v_jour date;
  v_heure time;
  k public.cartes_eleves;
  f public.fiches_eleves;
  v_classe text;
  par public.parametres_pointage;
  v_retard boolean := false;
  v_premier boolean;
  v_dest uuid;
  v_texte text;
  v_transmis text := '';
  v_sms integer := 0;
begin
  if not public.peut_scanner_portail(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_sens not in ('arrivee', 'sortie') then
    raise exception 'SENS_INVALIDE' using errcode = '22023';
  end if;

  if exists (select 1 from public.pointages_portail where id = p_id) then
    return jsonb_build_object('statut', 'deja_recu');
  end if;

  select * into k from public.cartes_eleves
   where jeton = regexp_replace(coalesce(p_jeton, ''), '^ECO1\.', '') and etablissement_id = p_etablissement;
  if k.fiche_eleve_id is null then
    return jsonb_build_object('statut', 'carte_inconnue');
  end if;
  select * into f from public.fiches_eleves where id = k.fiche_eleve_id;
  select c.nom into v_classe from public.inscriptions i join public.classes c on c.id = i.classe_id
   join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
   where i.fiche_eleve_id = f.id and i.deleted_at is null limit 1;

  v_jour := (v_scanne at time zone v_tz)::date;
  v_heure := (v_scanne at time zone v_tz)::time;
  select * into par from public.parametres_pointage where etablissement_id = p_etablissement;

  -- Même élève, même sens, moins de 2 minutes : double passage de la carte.
  if exists (select 1 from public.pointages_portail
             where fiche_eleve_id = f.id and sens = p_sens and abs(extract(epoch from scanne_le - v_scanne)) < 120) then
    return jsonb_build_object('statut', 'doublon', 'nom', f.nom, 'prenom', f.prenom, 'classe', v_classe);
  end if;

  v_premier := not exists (select 1 from public.pointages_portail
                           where fiche_eleve_id = f.id and jour = v_jour and sens = p_sens);
  if p_sens = 'arrivee' and par.etablissement_id is not null then
    v_retard := v_heure > par.heure_limite_arrivee;
  end if;

  insert into public.pointages_portail (id, etablissement_id, fiche_eleve_id, sens, jour, scanne_le, en_retard,
                                        appareil_id, saisi_par)
  values (p_id, p_etablissement, f.id, p_sens, v_jour, v_scanne, v_retard, p_appareil, auth.uid());

  if p_appareil is not null then
    insert into public.etats_portail (etablissement_id, appareil_id, derniere_synchro)
    values (p_etablissement, p_appareil, now())
    on conflict (etablissement_id, appareil_id) do update set derniere_synchro = greatest(public.etats_portail.derniere_synchro, now());
  end if;

  -- Avis aux familles : seulement pour un scan du jour (un scan resté
  -- plusieurs jours sur un téléphone sans réseau ne réveille personne).
  if par.etablissement_id is not null and par.actif and v_jour = (now() at time zone v_tz)::date and v_premier then
    if now() - v_scanne > interval '10 minutes' then
      v_transmis := format(' (transmis à %s)', to_char(now() at time zone v_tz, 'HH24"h"MI'));
    end if;

    if p_sens = 'arrivee' and par.notifier_arrivee_sortie then
      v_texte := format('%s est arrivé(e) à l''école à %s%s%s.', f.prenom, to_char(v_heure, 'HH24"h"MI'),
                        case when v_retard then ', en retard' else '' end, v_transmis);
      for v_dest in select d from public.destinataires_eleve(f.id) d loop
        if coalesce((select arrivee_sortie from public.preferences_pointage where profile_id = v_dest), true) then
          perform public.notifier_push(p_etablissement, v_dest, 'pointage_arrivee', v_texte,
            jsonb_build_object('fiche_eleve_id', f.id, 'jour', v_jour, 'retard', v_retard));
        end if;
      end loop;
    elsif p_sens = 'sortie' then
      if v_heure < par.heure_fin_cours
         and not exists (select 1 from public.autorisations_sortie where fiche_eleve_id = f.id and jour = v_jour) then
        -- Sortie anticipée sans autorisation : alerte (push, et SMS si choisi).
        insert into public.alertes_presence (etablissement_id, fiche_eleve_id, jour, type)
        values (p_etablissement, f.id, v_jour, 'sortie_anticipee')
        on conflict (fiche_eleve_id, jour, type) do nothing;
        if found then
          v_texte := format('Attention : %s est sorti(e) de l''école à %s, avant la fin des cours, sans autorisation%s.',
                            f.prenom, to_char(v_heure, 'HH24"h"MI'), v_transmis);
          for v_dest in select d from public.destinataires_eleve(f.id) d loop
            perform public.notifier_push(p_etablissement, v_dest, 'alerte_sortie_anticipee', v_texte,
              jsonb_build_object('fiche_eleve_id', f.id, 'jour', v_jour));
            if par.sms_sortie_anticipee
               and public.envoyer_sms_etablissement(p_etablissement, v_dest, v_texte,
                     format('sortie:%s:%s:%s', f.id, v_jour, v_dest)) then
              v_sms := v_sms + 1;
            end if;
          end loop;
          update public.alertes_presence set sms_envoyes = v_sms
           where fiche_eleve_id = f.id and jour = v_jour and type = 'sortie_anticipee';
        end if;
      elsif par.notifier_arrivee_sortie then
        v_texte := format('%s est sorti(e) de l''école à %s%s.', f.prenom, to_char(v_heure, 'HH24"h"MI'), v_transmis);
        for v_dest in select d from public.destinataires_eleve(f.id) d loop
          if coalesce((select arrivee_sortie from public.preferences_pointage where profile_id = v_dest), true) then
            perform public.notifier_push(p_etablissement, v_dest, 'pointage_sortie', v_texte,
              jsonb_build_object('fiche_eleve_id', f.id, 'jour', v_jour));
          end if;
        end loop;
      end if;
    end if;
  end if;

  return jsonb_build_object('statut', 'enregistre', 'nom', f.nom, 'prenom', f.prenom, 'classe', v_classe,
                            'en_retard', v_retard, 'heure', to_char(v_heure, 'HH24:MI'));
end;
$$;

-- cartes_portail (reprise de 20260906001546_pointage_portail_sms.sql)
create or replace function public.cartes_portail(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.peut_scanner_portail(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'parametres', (select to_jsonb(p) from public.parametres_pointage p where p.etablissement_id = p_etablissement),
    'fuseau', public.fuseau_etablissement(p_etablissement),
    'cartes', coalesce((
      select jsonb_agg(jsonb_build_object('jeton', k.jeton, 'fiche_eleve_id', f.id, 'nom', f.nom, 'prenom', f.prenom,
                                          'classe', c.nom))
      from public.cartes_eleves k
      join public.fiches_eleves f on f.id = k.fiche_eleve_id and f.deleted_at is null
      join public.inscriptions i on i.fiche_eleve_id = f.id and i.deleted_at is null and i.statut in ('active', 'redoublante')
      join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
      join public.classes c on c.id = i.classe_id
      where k.etablissement_id = p_etablissement), '[]'::jsonb));
end;
$$;

-- signaler_portail (reprise de 20260906001546_pointage_portail_sms.sql)
create or replace function public.signaler_portail(p_etablissement uuid, p_appareil text, p_en_attente integer default 0)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not public.peut_scanner_portail(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if coalesce(p_en_attente, 0) > 0 then
    return;
  end if;
  insert into public.etats_portail (etablissement_id, appareil_id, derniere_synchro)
  values (p_etablissement, p_appareil, now())
  on conflict (etablissement_id, appareil_id) do update set derniere_synchro = now();
end;
$$;

-- cloturer_periode (reprise de 20260906001535_pieces_exercices_clotures.sql)
create or replace function public.cloturer_periode(p_etablissement uuid, p_jusqu_au date)
returns date
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  x public.exercices_comptables;
begin
  if not coalesce(public.est_comptable_validation(p_etablissement), false) then
    raise exception 'COMPTABLE_VALIDATION_REQUIS' using errcode = '42501';
  end if;
  x := public.exercice_ouvert_pour(p_etablissement, p_jusqu_au);
  if x.id is null then
    raise exception 'AUCUN_EXERCICE_OUVERT' using errcode = '55000';
  end if;
  if x.cloture_jusqu_au is not null and p_jusqu_au <= x.cloture_jusqu_au then
    raise exception 'PERIODE_DEJA_CLOTUREE' using errcode = '55000';
  end if;
  if exists (select 1 from public.pieces_comptables
              where exercice_id = x.id and statut = 'brouillard' and date_piece <= p_jusqu_au) then
    raise exception 'BROUILLARDS_EN_ATTENTE' using errcode = '55000';
  end if;
  update public.exercices_comptables set cloture_jusqu_au = p_jusqu_au where id = x.id;
  return p_jusqu_au;
end;
$$;

-- valider_piece (reprise de 20260906001535_pieces_exercices_clotures.sql)
create or replace function public.valider_piece(p_piece_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  p public.pieces_comptables;
  v_nb integer;
  v_debit numeric;
  v_credit numeric;
begin
  select * into p from public.pieces_comptables where id = p_piece_id for update;
  if p.id is null then
    raise exception 'PIECE_INTROUVABLE' using errcode = '22023';
  end if;
  if not coalesce(public.est_comptable_validation(p.etablissement_id), false) then
    raise exception 'COMPTABLE_VALIDATION_REQUIS' using errcode = '42501';
  end if;
  if p.statut = 'validee' then
    raise exception 'PIECE_VALIDEE_IMMUABLE' using errcode = '42501';
  end if;
  if not exists (select 1 from public.exercices_comptables where id = p.exercice_id and statut = 'ouvert')
     or public.date_comptable_figee(p.etablissement_id, p.date_piece) then
    raise exception 'PERIODE_CLOTUREE' using errcode = '55000';
  end if;

  select count(*), coalesce(sum(debit), 0), coalesce(sum(credit), 0)
    into v_nb, v_debit, v_credit
    from public.lignes_pieces_comptables where piece_id = p_piece_id;
  if v_nb < 2 or v_debit <> v_credit or v_debit = 0 then
    raise exception 'PIECE_DESEQUILIBREE' using errcode = '23514';
  end if;

  return public.numeroter_et_valider_piece(p_piece_id, auth.uid());
end;
$$;

-- conges_verifie_validation (reprise de 20260906001513_qa_prelancement_audit_rpc.sql)
create or replace function public.conges_verifie_validation()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.statut in ('valide', 'refuse') then
    if auth.uid() is not null and not coalesce(public.est_rh(new.etablissement_id) or public.a_permission(new.etablissement_id, 'rh.conge.valider'), false) then
      raise exception 'VALIDATION_RH_REQUISE' using errcode = '42501';
    end if;
    new.valide_par := coalesce(new.valide_par, auth.uid());
    new.date_validation := coalesce(new.date_validation, now());
  end if;
  return new;
end $$;

-- conge_visible (reprise de 20260906000800_m8_rh_personnel.sql)
create or replace function public.conge_visible(p_conge uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.conges c
    join public.employes e on e.id = c.employe_id
    where c.id = p_conge and c.deleted_at is null
      and (public.est_rh(c.etablissement_id) or public.a_permission(c.etablissement_id, 'rh.conge.valider') or e.profile_id = auth.uid())
  );
$$;

-- contrat_visible (reprise de 20260906000800_m8_rh_personnel.sql)
create or replace function public.contrat_visible(p_contrat uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.contrats c
    join public.employes e on e.id = c.employe_id
    where c.id = p_contrat and c.deleted_at is null
      and (public.est_rh(c.etablissement_id) or public.a_permission(c.etablissement_id, 'rh.contrat.gerer') or e.profile_id = auth.uid())
  );
$$;

-- employe_visible (reprise de 20260906000800_m8_rh_personnel.sql)
create or replace function public.employe_visible(p_employe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.employes e
    where e.id = p_employe and e.deleted_at is null
      and (public.voit_employes(e.etablissement_id) or e.profile_id = auth.uid())
  );
$$;

-- inviter_membre (reprise de 20260906001557_invitations_membres.sql)
create or replace function public.inviter_membre(
  p_etablissement uuid,
  p_identifiant text,
  p_role public.role_racine,
  p_poste uuid default null
)
returns uuid
language plpgsql volatile
security definer
set search_path = public, extensions
as $$
declare
  v_ident text := public.normaliser_identifiant_invitation(p_identifiant);
  v_id uuid;
  v_ecole text;
  v_poste text;
  v_invite_par text;
  v_expire timestamptz := now() + interval '14 days';
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;
  if not public.gere_membres(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_role is null or p_role::text not in ('enseignant', 'direction', 'vendeur', 'personnel') then
    raise exception 'ROLE_NON_INVITABLE' using errcode = '22023';
  end if;
  -- REG-22 : seule la direction invite la direction ; le personnel reçoit
  -- toujours un poste (ses droits n'en viennent que de lui).
  if p_role::text = 'direction' and not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_role::text = 'personnel' and p_poste is null then
    raise exception 'POSTE_OBLIGATOIRE' using errcode = '22023';
  end if;
  if v_ident is null then
    raise exception 'IDENTIFIANT_INVALIDE' using errcode = '22023';
  end if;
  if p_poste is not null then
    select nom into v_poste from public.postes
     where id = p_poste and etablissement_id = p_etablissement and actif;
    if not found then
      raise exception 'POSTE_INVALIDE' using errcode = '22023';
    end if;
  end if;

  -- Déjà membre actif de cette école sous cet identifiant prouvé.
  if exists (
    select 1 from public.identifiants_comptes ic
    join public.etablissements_membres m on m.profile_id = ic.profile_id
    where ic.valeur = v_ident and ic.verifie_le is not null
      and m.etablissement_id = p_etablissement and m.actif and m.deleted_at is null
      and m.role_dans_etablissement = p_role::text
  ) then
    raise exception 'DEJA_MEMBRE' using errcode = '23505';
  end if;

  -- Une seule invitation en attente par personne et par école : la nouvelle
  -- remplace l'ancienne.
  update public.invitations
     set statut = 'revoquee'
   where etablissement_id = p_etablissement and identifiant_cible = v_ident and statut = 'en_attente';

  insert into public.invitations
    (etablissement_id, role_cible, poste_id, identifiant_cible, jeton_empreinte, invite_par, expire_le)
  values
    (p_etablissement, p_role, p_poste, v_ident,
     encode(digest(gen_random_bytes(32), 'sha256'), 'hex'), auth.uid(), v_expire)
  returning id into v_id;

  -- Courriel à l'invité (voie privilégiée). Par téléphone : aucun SMS, la
  -- direction prévient la personne.
  if position('@' in v_ident) > 0 then
    select nom into v_ecole from public.etablissements where id = p_etablissement;
    select nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), '') into v_invite_par
      from public.profiles p where p.id = auth.uid();
    perform public.mettre_notification_en_file(
      'invitation_membre',
      'invitation:' || v_id::text,
      jsonb_build_object(
        'nom_etablissement', v_ecole,
        'role', public.libelle_role_invitation(p_role),
        'poste', v_poste,
        'invite_par', v_invite_par,
        'adresse', v_ident,
        'expire_le', to_char(v_expire at time zone 'Africa/Conakry', 'DD/MM/YYYY')
      ),
      v_ident
    );
  end if;

  return v_id;
end;
$$;

-- journal_audit_visible (reprise de 20260906001562_code_compte.sql)
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
    when 'membre' then
      coalesce(public.est_direction(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    when 'code_compte' then
      v_row.entite_id = auth.uid()
      or coalesce(public.est_direction(v_row.etablissement_id), false)
      or coalesce(public.est_admin_gsg(), false)
    else false
  end;
end;
$$;
