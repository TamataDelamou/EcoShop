-- ============================================================================
-- EcoShop — Données de référence livrées en production
--
-- Défaut constaté en production : à la demande d'ouverture d'établissement,
-- le champ « Pays » était vide. Le référentiel pédagogique et les paramètres
-- globaux n'étaient remplis que par des fichiers seed (seed.sql,
-- seed_referentiel_pedagogique.sql), que `supabase db push` n'applique
-- jamais. Cette migration livre ce qui est indispensable au fonctionnement ;
-- les seeds ne gardent que les données de démonstration (écoles, élèves,
-- comptes fictifs, programme et filières d'exemple).
--
-- Contenu :
--   1. Les 4 familles de systèmes éducatifs (invariant du modèle M4).
--   2. Guinée complète : préscolaire, primaire, collège, lycée (16 niveaux,
--      Petite section → Terminale) et examens CEE, BEPC, Bac.
--   3. Sénégal et Ghana, tels que déjà décrits dans le dépôt (primaire →
--      fin du secondaire, examens). Leur préscolaire n'est pas décrit : il
--      n'est pas inventé ici.
--   4. Les niveaux d'examen (est_niveau_examinateur) : sans eux, aucune
--      classe n'est « classe d'examen » (mention admis/recalé impossible).
--   5. Les paramètres globaux de seed.sql (dont seuil_effectif_gratuit, lu
--      par la facturation : absent, toute école est comptée payante).
--   6. Contrôle de préparation : référentiel et paramètres non vides.
--
-- Idempotente : clés naturelles + on conflict do nothing. Une valeur déjà
-- présente (modifiée par le back-office) n'est jamais écrasée.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Préscolaire : grade_level_normalise <= 0
--
-- La grille normalisée garde 1 = première année du primaire dans tous les
-- pays (comparaison inter-pays inchangée). Le préscolaire se place avant :
-- Grande section = 0, Moyenne section = -1, Petite section = -2 ;
-- niveau_suivant() (grade + 1) mène donc de la Grande section au CP1.
-- ---------------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in
    select con.conname
    from pg_constraint con
    where con.conrelid = 'public.niveaux_educatifs'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) like '%grade_level_normalise%'
  loop
    execute format('alter table public.niveaux_educatifs drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.niveaux_educatifs
  add constraint niveaux_grade_level_normalise_check check (grade_level_normalise >= -3);

comment on column public.niveaux_educatifs.grade_level_normalise is
  'Clé de comparaison inter-pays, jamais affichée : 1 = première année du primaire ; préscolaire de -3 à 0 (Grande section = 0).';

-- ---------------------------------------------------------------------------
-- 1. Systèmes éducatifs
-- ---------------------------------------------------------------------------
insert into public.systemes_educatifs (code, nom, description) values
  ('francophone_cfa',  'Francophone (CFA)',  'Systèmes francophones de la zone CFA : BEPC/BAC, CFEE/BFEM/DEF'),
  ('anglophone_waec',  'Anglophone (WAEC)',  'Systèmes anglophones adossés au WAEC : BECE/WASSCE'),
  ('lusophone',        'Lusophone',          'Systèmes lusophones (Guinée-Bissau, Cap-Vert)'),
  ('arabophone_mixte', 'Arabophone / mixte', 'Systèmes arabophones ou mixtes (Mauritanie)')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Pays (langue = code ISO 639-1, recopié dans etablissements.langue_code
--    à la validation d'une demande d'ouverture)
-- ---------------------------------------------------------------------------
insert into public.pays_pedagogiques
  (code_iso, nom, type_systeme, langue_enseignement_principale, organisme_examinateur, devise_code, statut_deploiement)
values
  ('GN', 'Guinée',  'francophone_cfa', 'fr', 'Ministère de l''Enseignement Pré-Universitaire', 'GNF', 'deploye'),
  ('SN', 'Sénégal', 'francophone_cfa', 'fr', 'Office du Bac / Ministère de l''Éducation nationale', 'XOF', 'deploye'),
  ('GH', 'Ghana',   'anglophone_waec', 'en', 'WAEC (West African Examinations Council)', 'GHS', 'deploye')
on conflict (code_iso) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Cycles
-- ---------------------------------------------------------------------------
insert into public.cycles_educatifs
  (pays_code, code, nom, ordre, age_min, age_max, duree_annees, isced_min, isced_max, statut)
select v.pays, v.code, v.nom, v.ordre, v.age_min, v.age_max, v.duree, v.isc_min, v.isc_max, 'publie'
from (values
  ('GN', 'prescolaire', 'Préscolaire',  0,  3,  5, 3, 0, 0),
  ('GN', 'primaire',    'Primaire',     1,  6, 11, 6, 1, 1),
  ('GN', 'college',     'Collège',      2, 12, 15, 4, 2, 2),
  ('GN', 'lycee',       'Lycée',        3, 16, 18, 3, 3, 3),
  ('SN', 'primaire',    'Primaire',     1,  6, 11, 6, 1, 1),
  ('SN', 'moyen',       'Moyen',        2, 12, 15, 4, 2, 2),
  ('SN', 'secondaire',  'Secondaire',   3, 16, 18, 3, 3, 3),
  ('GH', 'primary',     'Primary',      1,  6, 11, 6, 1, 1),
  ('GH', 'junior_high', 'Junior High',  2, 12, 14, 3, 2, 2),
  ('GH', 'senior_high', 'Senior High',  3, 15, 17, 3, 3, 3)
) as v(pays, code, nom, ordre, age_min, age_max, duree, isc_min, isc_max)
on conflict (pays_code, code) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Niveaux (examinateur = dernière année d'un cycle sanctionné par un
--    examen national)
-- ---------------------------------------------------------------------------
insert into public.niveaux_educatifs
  (cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre, est_niveau_examinateur, statut)
select c.id, v.pays, v.code, v.nom, v.grade, v.isced, v.ordre, v.examen, 'publie'
from (values
  -- Guinée : préscolaire (-2 → 0), primaire (1-6), collège (7-10), lycée (11-13)
  ('GN', 'prescolaire', 'PS',  'Petite section',                -2, 0, 1, false),
  ('GN', 'prescolaire', 'MS',  'Moyenne section',               -1, 0, 2, false),
  ('GN', 'prescolaire', 'GS',  'Grande section',                 0, 0, 3, false),
  ('GN', 'primaire', 'CP1', 'Cours Préparatoire 1ère année',     1, 1, 1, false),
  ('GN', 'primaire', 'CP2', 'Cours Préparatoire 2ème année',     2, 1, 2, false),
  ('GN', 'primaire', 'CE1', 'Cours Élémentaire 1ère année',      3, 1, 3, false),
  ('GN', 'primaire', 'CE2', 'Cours Élémentaire 2ème année',      4, 1, 4, false),
  ('GN', 'primaire', 'CM1', 'Cours Moyen 1ère année',            5, 1, 5, false),
  ('GN', 'primaire', 'CM2', 'Cours Moyen 2ème année',            6, 1, 6, true),
  ('GN', 'college',  '7e',  'Septième année',                    7, 2, 1, false),
  ('GN', 'college',  '8e',  'Huitième année',                    8, 2, 2, false),
  ('GN', 'college',  '9e',  'Neuvième année',                    9, 2, 3, false),
  ('GN', 'college',  '10e', 'Dixième année',                    10, 2, 4, true),
  ('GN', 'lycee',    '11e', 'Onzième année',                    11, 3, 1, false),
  ('GN', 'lycee',    '12e', 'Douzième année',                   12, 3, 2, false),
  ('GN', 'lycee',    'Terminale', 'Terminale',                  13, 3, 3, true),
  -- Sénégal : primaire (1-6), moyen (7-10), secondaire (11-13)
  ('SN', 'primaire',   'CI',   'Cours d''Initiation',            1, 1, 1, false),
  ('SN', 'primaire',   'CP',   'Cours Préparatoire',             2, 1, 2, false),
  ('SN', 'primaire',   'CE1',  'Cours Élémentaire 1ère année',   3, 1, 3, false),
  ('SN', 'primaire',   'CE2',  'Cours Élémentaire 2ème année',   4, 1, 4, false),
  ('SN', 'primaire',   'CM1',  'Cours Moyen 1ère année',         5, 1, 5, false),
  ('SN', 'primaire',   'CM2',  'Cours Moyen 2ème année',         6, 1, 6, true),
  ('SN', 'moyen',      '6e',   'Sixième',                        7, 2, 1, false),
  ('SN', 'moyen',      '5e',   'Cinquième',                      8, 2, 2, false),
  ('SN', 'moyen',      '4e',   'Quatrième',                      9, 2, 3, false),
  ('SN', 'moyen',      '3e',   'Troisième',                     10, 2, 4, true),
  ('SN', 'secondaire', '2nde', 'Seconde',                       11, 3, 1, false),
  ('SN', 'secondaire', '1ere', 'Première',                      12, 3, 2, false),
  ('SN', 'secondaire', 'Terminale', 'Terminale',                13, 3, 3, true),
  -- Ghana : primary (1-6), JHS (7-9), SHS (10-12)
  ('GH', 'primary',     'P1',   'Primary 1',                     1, 1, 1, false),
  ('GH', 'primary',     'P2',   'Primary 2',                     2, 1, 2, false),
  ('GH', 'primary',     'P3',   'Primary 3',                     3, 1, 3, false),
  ('GH', 'primary',     'P4',   'Primary 4',                     4, 1, 4, false),
  ('GH', 'primary',     'P5',   'Primary 5',                     5, 1, 5, false),
  ('GH', 'primary',     'P6',   'Primary 6',                     6, 1, 6, false),
  ('GH', 'junior_high', 'JHS1', 'Junior High School 1',          7, 2, 1, false),
  ('GH', 'junior_high', 'JHS2', 'Junior High School 2',          8, 2, 2, false),
  ('GH', 'junior_high', 'JHS3', 'Junior High School 3',          9, 2, 3, true),
  ('GH', 'senior_high', 'SHS1', 'Senior High School 1',         10, 3, 1, false),
  ('GH', 'senior_high', 'SHS2', 'Senior High School 2',         11, 3, 2, false),
  ('GH', 'senior_high', 'SHS3', 'Senior High School 3',         12, 3, 3, true)
) as v(pays, cycle, code, nom, grade, isced, ordre, examen)
join public.cycles_educatifs c on c.pays_code = v.pays and c.code = v.cycle
on conflict (pays_code, code) do nothing;

-- ---------------------------------------------------------------------------
-- 5. Examens nationaux
-- ---------------------------------------------------------------------------
insert into public.examens_nationaux
  (pays_code, cycle_id, code, nom, organisme, mois_session, periodicite, statut)
select v.pays, c.id, v.code, v.nom, v.organisme, v.mois, 'annuelle', 'publie'
from (values
  ('GN', 'primaire',    'CEE',    'Certificat d''Études Élémentaires',                  'Ministère',     6),
  ('GN', 'college',     'BEPC',   'Brevet d''Études du Premier Cycle',                  'Ministère',     6),
  ('GN', 'lycee',       'BAC',    'Baccalauréat unique',                                'Ministère',     6),
  ('SN', 'primaire',    'CFEE',   'Certificat de Fin d''Études Élémentaires',           'Ministère',     6),
  ('SN', 'moyen',       'BFEM',   'Brevet de Fin d''Études Moyennes',                   'Office du Bac', 7),
  ('SN', 'secondaire',  'BAC',    'Baccalauréat',                                       'Office du Bac', 7),
  ('GH', 'junior_high', 'BECE',   'Basic Education Certificate Examination',            'WAEC',          6),
  ('GH', 'senior_high', 'WASSCE', 'West African Senior School Certificate Examination', 'WAEC',          8)
) as v(pays, cycle, code, nom, organisme, mois)
join public.cycles_educatifs c on c.pays_code = v.pays and c.code = v.cycle
on conflict (pays_code, code) do nothing;

-- ---------------------------------------------------------------------------
-- 6. Paramètres globaux (jusqu'ici dans seed.sql seulement)
-- ---------------------------------------------------------------------------
insert into public.parametres_globaux (cle, valeur, description) values
  ('seuil_effectif_gratuit',     '{"valeur": 100}',   'Effectif en deçà duquel la licence de base est gratuite'),
  ('commission_marketplace_pct', '{"valeur": 3}',     'Commission GSG sur chaque vente marketplace (jamais sur la scolarité)'),
  ('devise_defaut',              '{"valeur": "GNF"}', 'Devise par défaut des établissements'),
  ('liaison_tentatives_max',     '{"valeur": 5}',     'Tentatives de liaison compte↔fiche par heure'),
  ('invitation_validite_jours',  '{"valeur": 14}',    'Durée de validité d''une invitation')
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------------
-- 7. Contrôle de préparation : référentiel et paramètres non vides
-- ---------------------------------------------------------------------------

-- Paramètres globaux attendus (livrés par les migrations).
create or replace function public.parametres_globaux_attendus()
returns setof text
language sql immutable set search_path = public
as $$
  values
    ('seuil_effectif_gratuit'), ('commission_marketplace_pct'), ('devise_defaut'),
    ('liaison_tentatives_max'), ('invitation_validite_jours'),
    ('bareme_licence_pro'), ('tarif_frais_ia_admin_annuel'),
    ('tarif_abonnement_premium_eleve_mensuel'), ('tarif_abonnement_premium_eleve_annuel'),
    ('quota_tuteur_ia_free_mensuel'), ('anti_rafale_ia'), ('poids_type_conversation_ia'),
    ('seuil_anomalie_usage_ia_quotidien'), ('duree_retention_journal_audit')
$$;

revoke all on function public.parametres_globaux_attendus() from public, anon;
grant execute on function public.parametres_globaux_attendus() to authenticated, service_role;

create or replace function public.etat_mise_en_service()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_controles jsonb := '[]'::jsonb;
  v_ok boolean;
  v_detail text;
  t record;
  v_present boolean;
  v_dernier text;
begin
  -- Un compte connecté doit être de l'équipe GSG ; sans compte, c'est le
  -- serveur (script de déploiement, service_role).
  if auth.uid() is not null and not public.est_admin_gsg() then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  -- Extensions
  for t in select unnest(array['pg_cron', 'pg_net']) as ext loop
    v_ok := exists (select 1 from pg_extension where extname = t.ext);
    v_controles := v_controles || jsonb_build_object('controle', 'Extension ' || t.ext, 'ok', v_ok,
      'detail', case when v_ok then 'activée' else 'à activer (Database → Extensions)' end);
  end loop;

  -- Tâches planifiées (lecture dynamique : pg_cron peut être absent)
  for t in select * from public.taches_planifiees_attendues() loop
    v_present := false; v_dernier := null;
    if to_regclass('cron.job') is not null then
      execute 'select exists (select 1 from cron.job where jobname = $1 and active)' into v_present using t.nom;
      if v_present and to_regclass('cron.job_run_details') is not null then
        execute 'select d.status || '' le '' || to_char(d.start_time at time zone ''UTC'', ''DD/MM HH24:MI'') || '' UTC''
                   from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                  where j.jobname = $1 order by d.start_time desc limit 1'
          into v_dernier using t.nom;
      end if;
    end if;
    v_controles := v_controles || jsonb_build_object('controle', 'Tâche « ' || t.nom || ' »', 'ok', v_present,
      'detail', t.role || case when v_present then coalesce(' — dernier passage : ' || v_dernier, ' — pas encore exécutée')
                               else ' — absente' end);
  end loop;

  -- Secrets rangés dans le coffre (présence seulement)
  for t in select unnest(array['ecoshop_url_projet', 'notifications_declencheur_secret', 'paiements_declencheur_secret']) as nom loop
    v_present := false;
    if to_regclass('vault.secrets') is not null then
      execute 'select exists (select 1 from vault.secrets where name = $1)' into v_present using t.nom;
    end if;
    v_controles := v_controles || jsonb_build_object('controle', 'Coffre : ' || t.nom, 'ok', v_present,
      'detail', case when v_present then 'rangé' else 'absent' end);
  end loop;

  -- Administrateur GSG
  v_ok := exists (select 1 from public.profiles where role_racine = 'admin_gsg' and deleted_at is null);
  v_controles := v_controles || jsonb_build_object('controle', 'Administrateur GSG', 'ok', v_ok,
    'detail', case when v_ok then 'désigné' else 'à désigner (premier_admin.modele.sql)' end);

  -- Packs SMS
  select string_agg(code, ', ') into v_detail from public.packs_sms where actif and prix > 0;
  v_ok := v_detail is not null;
  v_controles := v_controles || jsonb_build_object('controle', 'Packs SMS en vente', 'ok', v_ok,
    'detail', coalesce(v_detail, 'aucun : fixer les prix (écran Crédits SMS GSG)'));

  -- Référentiel : pays proposés à la demande d'ouverture
  select string_agg(code_iso, ', ' order by code_iso) into v_detail
  from public.pays_pedagogiques where statut_deploiement = 'deploye';
  v_ok := v_detail is not null;
  v_controles := v_controles || jsonb_build_object('controle', 'Référentiel : pays ouverts', 'ok', v_ok,
    'detail', coalesce(v_detail, 'aucun : la demande d''ouverture n''a aucun pays à proposer'));

  -- Référentiel : chaque pays ouvert a ses cycles, niveaux et examens publiés
  select string_agg(p.code_iso || ' (' || concat_ws(', ',
           case when not exists (select 1 from public.cycles_educatifs c
                                 where c.pays_code = p.code_iso and c.statut = 'publie') then 'aucun cycle' end,
           case when not exists (select 1 from public.niveaux_educatifs n
                                 where n.pays_code = p.code_iso and n.statut = 'publie') then 'aucun niveau' end,
           case when not exists (select 1 from public.examens_nationaux x
                                 where x.pays_code = p.code_iso and x.statut = 'publie') then 'aucun examen' end) || ')',
         ', ' order by p.code_iso)
    into v_detail
  from public.pays_pedagogiques p
  where p.statut_deploiement = 'deploye'
    and (not exists (select 1 from public.cycles_educatifs c where c.pays_code = p.code_iso and c.statut = 'publie')
      or not exists (select 1 from public.niveaux_educatifs n where n.pays_code = p.code_iso and n.statut = 'publie')
      or not exists (select 1 from public.examens_nationaux x where x.pays_code = p.code_iso and x.statut = 'publie'));
  v_ok := v_detail is null
          and exists (select 1 from public.pays_pedagogiques where statut_deploiement = 'deploye');
  v_controles := v_controles || jsonb_build_object('controle', 'Référentiel : cycles, niveaux, examens', 'ok', v_ok,
    'detail', case
      when v_detail is not null then 'incomplet : ' || v_detail
      when not v_ok then 'vide : aucun pays ouvert'
      else (select count(*) || ' niveaux, ' from public.niveaux_educatifs where statut = 'publie')
           || (select count(*) || ' examens publiés' from public.examens_nationaux where statut = 'publie')
    end);

  -- Paramètres globaux
  select string_agg(a.cle, ', ' order by a.cle) into v_detail
  from public.parametres_globaux_attendus() as a(cle)
  where not exists (select 1 from public.parametres_globaux g where g.cle = a.cle);
  v_ok := v_detail is null;
  v_controles := v_controles || jsonb_build_object('controle', 'Paramètres globaux', 'ok', v_ok,
    'detail', case when v_ok then (select count(*) || ' réglages présents' from public.parametres_globaux)
                   else 'manquants : ' || v_detail end);

  return jsonb_build_object(
    'pret', not exists (select 1 from jsonb_array_elements(v_controles) c where not (c ->> 'ok')::boolean),
    'controles', v_controles);
end;
$$;

revoke all on function public.etat_mise_en_service() from public, anon;
grant execute on function public.etat_mise_en_service() to authenticated, service_role;
