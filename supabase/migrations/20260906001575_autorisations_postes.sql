-- ============================================================================
-- EcoShop — REG-26 : autorisations des postes approfondies
-- (directive du porteur de projet, 2026-10-28)
--
-- Modèle retenu (profils d'autorisations de Pronote) : chaque action
-- sensible de l'école a son droit, que la Direction coche poste par poste.
-- Jusqu'ici, plusieurs actions n'étaient possibles qu'à la Direction
-- elle-même : publier une annonce, masquer un message, proclamer les
-- résultats, régler Orange Money, acheter des crédits SMS, agréer un
-- vendeur, débloquer le code d'une personne. Elles deviennent déléguables.
--
--   1. Nouveaux droits, chacun **vérifié par le serveur** (aucun droit
--      décoratif) ; un repère « sensible » pour ceux qui touchent à l'argent,
--      aux comptes ou aux résultats.
--   2. Les fonctions concernées acceptent la Direction **ou** le droit :
--      seul leur contrôle d'accès change (remplacement ciblé, vérifié).
--   3. Modèles de poste enrichis et trois nouveaux modèles (responsable de
--      la communication, coordinateur pédagogique, gestionnaire des
--      comptes) ; les postes déjà créés depuis un modèle reçoivent les
--      nouveaux droits de leur modèle (la Direction peut les retirer).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Droits sensibles, nouveaux droits
-- ---------------------------------------------------------------------------
alter table public.permissions add column if not exists sensible boolean not null default false;

insert into public.permissions (code, domaine, libelle, description) values
  ('communication.annonce.publier', 'communication', 'Publier des annonces',
   'Écrire et publier les annonces de l''école (toute l''école, un niveau, une classe), par push et par SMS.'),
  ('communication.annonce.moderer', 'communication', 'Masquer une annonce',
   'Retirer une annonce publiée par erreur.'),
  ('communication.liaison.moderer', 'communication', 'Modérer le cahier de liaison',
   'Masquer un message déplacé du cahier de liaison.'),
  ('scolarite.proclamation.gerer', 'scolarite', 'Proclamer les résultats',
   'Proclamer les résultats d''une classe et fixer les mentions de fin d''année (définitif).'),
  ('paiement.mobile.gerer', 'finances', 'Régler Orange Money',
   'Enregistrer les identifiants marchands Orange Money de l''école.'),
  ('sms.credits.acheter', 'finances', 'Acheter des crédits SMS',
   'Commander des crédits SMS auprès de GSG.'),
  ('boutique.vendeur.agreer', 'boutique', 'Agréer les vendeurs',
   'Accepter ou refuser les vendeurs de la boutique de l''école.'),
  ('securite.code.debloquer', 'securite', 'Débloquer le code d''une personne',
   'Rendre l''accès à un membre qui a oublié son code (hors Direction).')
on conflict (code) do update
  set domaine = excluded.domaine, libelle = excluded.libelle, description = excluded.description;

-- Domaines plus clairs pour les droits existants.
update public.permissions set domaine = 'communication' where domaine = 'comm';
update public.permissions set libelle = 'Envoyer des notifications',
       description = 'Envoyer un message aux familles ou au personnel (push, e-mail, SMS selon les crédits).'
 where code = 'comm.notifier';
update public.permissions set libelle = 'Consulter les envois',
       description = 'Voir quels messages sont partis, à qui, et s''ils ont été lus.'
 where code = 'comm.voir_logs';

update public.permissions set sensible = true where code in (
  'scolarite.encaissement.gerer', 'scolarite.note.gerer', 'scolarite.bulletin.gerer',
  'scolarite.proclamation.gerer', 'comptabilite.valider', 'comptabilite.plan.gerer',
  'rh.paie.gerer', 'rh.contrat.gerer', 'etablissement.membre.gerer', 'etablissement.poste.gerer',
  'etablissement.invitation.gerer', 'audit.journal.lire', 'paiement.mobile.gerer',
  'securite.code.debloquer', 'sms.credits.acheter'
);

-- Le catalogue renvoie aussi le repère « sensible ».
drop function if exists public.catalogue_permissions();
create or replace function public.catalogue_permissions()
returns table (code text, domaine text, libelle text, description text, sensible boolean)
language sql stable security definer set search_path = public
as $$
  select code, domaine, libelle, description, sensible
    from public.permissions
   -- Droits techniques de la plateforme : jamais proposés aux postes d'une école.
   where domaine not in ('observabilite', 'marketplace')
   order by domaine, libelle;
$$;
grant execute on function public.catalogue_permissions() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Délégation : « Direction » devient « Direction ou droit »
-- ---------------------------------------------------------------------------
-- Remplace dans la définition de la fonction le contrôle
-- `coalesce(public.est_direction(X), false)` (ou `public.est_direction(X)`)
-- par `coalesce(public.a_permission(X, '<droit>'), false)`. a_permission
-- reconnaît déjà la Direction (migration 1570) : la Direction garde l'accès.
-- Échoue si le contrôle attendu n'est pas trouvé (fonction modifiée depuis).
create or replace function public.deleguer_controle_direction(p_fonction text, p_droit text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_oid oid;
  v_def text;
  v_nouvelle text;
begin
  select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = p_fonction;
  if v_oid is null then
    raise exception 'FONCTION_INTROUVABLE %', p_fonction;
  end if;
  v_def := pg_get_functiondef(v_oid);
  if position('a_permission(' in v_def) > 0 and position(p_droit in v_def) > 0 then
    return; -- déjà délégué (migration rejouée)
  end if;
  v_nouvelle := regexp_replace(
    v_def,
    'coalesce\(public\.est_direction\(([^()]+)\), false\)',
    'coalesce(public.a_permission(\1, ''' || p_droit || '''), false)',
    'g');
  if v_nouvelle = v_def then
    v_nouvelle := regexp_replace(
      v_def,
      'public\.est_direction\(([^()]+)\)',
      'coalesce(public.a_permission(\1, ''' || p_droit || '''), false)',
      'g');
  end if;
  if v_nouvelle = v_def then
    raise exception 'CONTROLE_INTROUVABLE % (%)', p_fonction, p_droit;
  end if;
  execute v_nouvelle;
end;
$$;
revoke all on function public.deleguer_controle_direction(text, text) from public, anon, authenticated;

select public.deleguer_controle_direction('publier_annonce', 'communication.annonce.publier');
select public.deleguer_controle_direction('annonces_etablissement', 'communication.annonce.publier');
select public.deleguer_controle_direction('portees_annonce', 'communication.annonce.publier');
select public.deleguer_controle_direction('masquer_annonce', 'communication.annonce.moderer');
select public.deleguer_controle_direction('masquer_message_liaison', 'communication.liaison.moderer');
select public.deleguer_controle_direction('proclamer_classe', 'scolarite.proclamation.gerer');
select public.deleguer_controle_direction('definir_mention_finale', 'scolarite.proclamation.gerer');
select public.deleguer_controle_direction('enregistrer_identifiants_orange_money', 'paiement.mobile.gerer');
select public.deleguer_controle_direction('initier_achat_credits_sms', 'sms.credits.acheter');
select public.deleguer_controle_direction('decider_agrement_vendeur_etablissement', 'boutique.vendeur.agreer');
select public.deleguer_controle_direction('personnes_debloquables', 'securite.code.debloquer');
select public.deleguer_controle_direction('debloquer_code_membre', 'securite.code.debloquer');

-- ---------------------------------------------------------------------------
-- 3. Modèles de poste
-- ---------------------------------------------------------------------------
insert into public.modeles_postes (code, nom, description, role, codes, ordre) values
  ('directeur_etudes', 'Directeur des études / censeur',
   'Classes, périodes, emploi du temps, évaluations, notes, bulletins, proclamation des résultats.', 'personnel',
   array['scolarite.classe.gerer', 'scolarite.periode.gerer', 'planification.administrer', 'planification.generer',
         'planification.consulter', 'scolarite.evaluation.gerer', 'scolarite.note.lire', 'scolarite.note.gerer',
         'scolarite.bulletin.gerer', 'scolarite.bulletin.lire', 'scolarite.appreciation.gerer',
         'scolarite.parametres.gerer', 'scolarite.proclamation.gerer', 'rh.enseignant.affecter',
         'rapports.consulter', 'rapports.generer', 'communication.annonce.publier'], 30),
  ('surveillant_general', 'Surveillant général / conseiller d''éducation',
   'Appel, absences, retards, sanctions, portail, cahier de liaison, modération des groupes.', 'personnel',
   array['scolarite.presence.gerer', 'scolarite.presence.lire', 'scolarite.sanction.gerer', 'scolarite.sanction.lire',
         'scolarite.evenement.gerer', 'portail.scanner', 'communication.groupe.moderer', 'scolarite.liaison.ecrire',
         'communication.liaison.moderer', 'planification.consulter'], 40),
  ('comptable', 'Comptable / économe / intendant',
   'Comptabilité (saisie, validation, clôture), lecture des encaissements, Orange Money, crédits SMS. Pas d''encaissement.',
   'personnel',
   array['comptabilite.lire', 'comptabilite.ecrire', 'comptabilite.valider', 'comptabilite.export',
         'scolarite.encaissement.lire', 'paiement.mobile.gerer', 'sms.credits.acheter'], 50),
  ('caissier', 'Caissier',
   'Encaissements de scolarité et reçus. Pas de comptabilité ni de clôture.', 'personnel',
   array['scolarite.encaissement.gerer', 'scolarite.encaissement.lire'], 60),
  ('secretaire', 'Secrétaire',
   'Inscriptions, fiches des élèves, liens avec les parents, annonces, invitations du personnel.', 'personnel',
   array['scolarite.inscription.gerer', 'scolarite.eleve.gerer', 'scolarite.relation.gerer',
         'communication.annonce.publier', 'comm.notifier', 'etablissement.membre.lire'], 70),
  ('responsable_communication', 'Responsable de la communication',
   'Annonces, notifications, suivi des envois, modération des messages et des groupes.', 'personnel',
   array['communication.annonce.publier', 'communication.annonce.moderer', 'communication.liaison.moderer',
         'communication.groupe.moderer', 'comm.notifier', 'comm.voir_logs'], 75),
  ('coordinateur_pedagogique', 'Coordinateur pédagogique / chef de département',
   'Lecture des notes, bulletins et absences de toutes les classes ; emploi du temps ; rapports.', 'personnel',
   array['scolarite.note.lire', 'scolarite.bulletin.lire', 'scolarite.presence.lire', 'planification.consulter',
         'rapports.consulter'], 77),
  ('gestionnaire_comptes', 'Gestionnaire des comptes (informatique)',
   'Invitations du personnel, liste des membres, déblocage des codes oubliés. Sans accès aux notes ni à l''argent.',
   'personnel',
   array['etablissement.invitation.gerer', 'etablissement.membre.lire', 'securite.code.debloquer'], 78)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description, role = excluded.role,
      codes = excluded.codes, ordre = excluded.ordre;

-- Nouveaux modèles : créés dans toutes les écoles (idempotent).
select public.creer_postes_par_defaut(id) from public.etablissements where deleted_at is null;

-- Postes déjà créés depuis un modèle : ils reçoivent les droits que leur
-- modèle a gagnés (ajout seulement, jamais de retrait ; séparation des
-- tâches respectée par le déclencheur).
insert into public.poste_permissions (poste_id, permission_code)
select po.id, c
  from public.postes po
  join public.modeles_postes m on m.code = po.modele_code
  cross join lateral unnest(m.codes) c
 where po.deleted_at is null
   and exists (select 1 from public.permissions where code = c)
   and not exists (select 1 from public.poste_permissions pp where pp.poste_id = po.id and pp.permission_code = c)
   -- Ne pas cumuler encaissement et comptabilité sur un poste modifié.
   and not (c in ('comptabilite.ecrire', 'comptabilite.valider')
            and exists (select 1 from public.poste_permissions pp
                         where pp.poste_id = po.id and pp.permission_code = 'scolarite.encaissement.gerer'))
   and not (c = 'scolarite.encaissement.gerer'
            and exists (select 1 from public.poste_permissions pp
                         where pp.poste_id = po.id and pp.permission_code in ('comptabilite.ecrire', 'comptabilite.valider')))
on conflict do nothing;
