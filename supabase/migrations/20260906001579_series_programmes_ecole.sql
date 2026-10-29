-- ============================================================================
-- EcoShop — REG-33 : séries du lycée, programmes de l'école, moyenne générale
-- pondérée par les coefficients des matières.
--
-- Recherche (registre REG-33) :
--   • Guinée : séries SM, SE, SS du Baccalauréat unique ; lycée en trois ans
--     (11e, 12e, Terminale). Aucune grille officielle de coefficients
--     publiée en ligne : aucune valeur n'est inventée ici.
--   • Sénégal (L1, L1a, L2, L'1, L'2, S1-S5, T1, T2, G), Côte d'Ivoire (A, C,
--     D…), Ghana (tronc commun + matières par programme) : une série couvre
--     plusieurs niveaux, et les matières changent selon la série.
--   • Pronote : l'établissement définit ses matières (services) et leurs
--     coefficients ; la moyenne générale pondère les moyennes de matières.
--
-- Changements :
--   1. une série couvre plusieurs niveaux (`filieres_niveaux`) ;
--   2. coefficients décimaux et nature de la matière (tronc commun,
--      spécialité, option) ;
--   3. programmes de l'école : copie ajustable du programme officiel, ou
--      matières créées par l'école tant que le programme national n'est pas
--      publié (cas de la Guinée en production) ;
--   4. moyenne générale = moyenne des moyennes de matières pondérée par leurs
--      coefficients (avant : toutes les évaluations mêlées) ;
--   5. séries guinéennes SM, SE, SS, sans coefficients.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Une série couvre plusieurs niveaux
-- ---------------------------------------------------------------------------
alter table public.filieres_educatives
  add column if not exists cycle_id uuid references public.cycles_educatifs (id) on delete cascade,
  add column if not exists ordre int not null default 0;

create table if not exists public.filieres_niveaux (
  filiere_id uuid not null references public.filieres_educatives (id) on delete cascade,
  niveau_id uuid not null references public.niveaux_educatifs (id) on delete cascade,
  primary key (filiere_id, niveau_id)
);
create index if not exists idx_filieres_niveaux_niveau on public.filieres_niveaux (niveau_id);

comment on table public.filieres_niveaux is
  'REG-33 : niveaux où une série est proposée (ex. SM en 11e, 12e et Terminale). Écriture par migration (référentiel partagé).';

-- Séries existantes rattachées à un seul niveau : reprises.
insert into public.filieres_niveaux (filiere_id, niveau_id)
select id, niveau_id from public.filieres_educatives where niveau_id is not null
on conflict do nothing;

alter table public.filieres_niveaux enable row level security;
drop policy if exists "filieres_niveaux_select" on public.filieres_niveaux;
create policy "filieres_niveaux_select" on public.filieres_niveaux
  for select using (
    exists (select 1 from public.filieres_educatives f where f.id = filiere_id and f.statut = 'publie')
  );

-- ---------------------------------------------------------------------------
-- 2. Coefficients décimaux, nature de la matière
-- ---------------------------------------------------------------------------
-- Le bulletin renvoyait le coefficient en entier : recréé plus bas.
drop function if exists public.detail_bulletin_matieres(uuid, uuid, uuid);

alter table public.programmes_matieres
  alter column coefficient type numeric(5,2) using coefficient::numeric(5,2),
  add column if not exists nature text not null default 'tronc_commun'
    check (nature in ('tronc_commun', 'specialite', 'option'));

comment on column public.programmes_matieres.coefficient is
  'Coefficient de la matière dans la moyenne générale (décimal : 0,5 ; 1,5…). Null = 1.';
comment on column public.programmes_matieres.nature is
  'REG-33 : tronc commun, spécialité (propre à la série) ou option. Affichage et organisation ; le calcul utilise le coefficient.';

-- ---------------------------------------------------------------------------
-- 3. Programmes de l'école
-- ---------------------------------------------------------------------------
alter table public.programmes_officiels
  add column if not exists etablissement_id uuid references public.etablissements (id) on delete cascade,
  add column if not exists source_id uuid references public.programmes_officiels (id) on delete set null;

comment on column public.programmes_officiels.etablissement_id is
  'REG-33 : null = programme national (référentiel GSG) ; renseigné = programme de cette école (copie ajustée, ou créé par l''école).';

-- Un code par pays pour le national, par école pour les écoles.
alter table public.programmes_officiels drop constraint if exists programmes_pays_code_version_unique;
create unique index if not exists idx_programmes_code_unique
  on public.programmes_officiels (pays_code, coalesce(etablissement_id, '00000000-0000-0000-0000-000000000000'::uuid), code, version);
-- Un seul programme d'école par niveau et série.
create unique index if not exists idx_programmes_ecole_niveau_filiere
  on public.programmes_officiels (etablissement_id, niveau_id, coalesce(filiere_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where etablissement_id is not null and statut <> 'archive';

-- Écoles des enfants du compte (le parent n'est pas membre de l'école).
create or replace function public.ecoles_de_mes_enfants()
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select distinct r.etablissement_id
  from public.relations_parent_eleve r
  where r.parent_profile_id = auth.uid()
    and r.statut = 'confirmee' and r.autorise and r.deleted_at is null;
$$;
revoke execute on function public.ecoles_de_mes_enfants() from public, anon;
grant execute on function public.ecoles_de_mes_enfants() to authenticated;

-- Lecture : national publié pour tous ; programme d'école pour ses membres,
-- les parents de ses élèves et GSG.
create or replace function public.programme_lisible(p_programme uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.programmes_officiels p
    where p.id = p_programme
      and (
        (p.etablissement_id is null and p.statut = 'publie')
        or (p.etablissement_id is not null and p.statut <> 'archive' and (
              p.etablissement_id in (select public.mes_etablissements())
              or p.etablissement_id in (select public.ecoles_de_mes_enfants())
              or coalesce(public.est_admin_gsg(), false)))
      )
  );
$$;
grant execute on function public.programme_lisible(uuid) to authenticated, anon;

drop policy if exists "programmes_select_publie" on public.programmes_officiels;
create policy "programmes_select_publie" on public.programmes_officiels
  for select using (public.programme_lisible(id));

drop policy if exists "matieres_select_publie" on public.programmes_matieres;
create policy "matieres_select_publie" on public.programmes_matieres
  for select using (statut <> 'archive' and public.programme_lisible(programme_id));

-- Qui ajuste le programme de l'école : la direction, ou un poste qui gère les
-- paramètres de la scolarité (directeur des études / censeur).
create or replace function public.gere_programme_ecole(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.est_direction(p_etablissement), false)
      or coalesce(public.a_permission(p_etablissement, 'scolarite.parametres.gerer'), false);
$$;
grant execute on function public.gere_programme_ecole(uuid) to authenticated;

-- Programme de l'école pour un niveau et une série : créé à la demande,
-- copie du programme national s'il existe (matières, coefficients, heures),
-- vide sinon. Renvoie son identifiant.
create or replace function public.adopter_programme_ecole(
  p_etablissement uuid,
  p_niveau uuid,
  p_filiere uuid default null
)
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_id uuid;
  v_source record;
  v_niveau record;
begin
  if not public.gere_programme_ecole(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  select id into v_id from public.programmes_officiels
   where etablissement_id = p_etablissement and niveau_id = p_niveau
     and filiere_id is not distinct from p_filiere and statut <> 'archive';
  if v_id is not null then
    return v_id;
  end if;

  select n.id, n.pays_code, n.code, n.nom into v_niveau from public.niveaux_educatifs n where n.id = p_niveau;
  if v_niveau.id is null then
    raise exception 'NIVEAU_INCONNU' using errcode = '22023';
  end if;

  -- Programme national de la série, sinon du niveau.
  select p.* into v_source from public.programmes_officiels p
   where p.etablissement_id is null and p.statut = 'publie' and p.niveau_id = p_niveau
     and (p.filiere_id = p_filiere or p.filiere_id is null)
   order by (p.filiere_id is null), p.version desc
   limit 1;

  insert into public.programmes_officiels
    (pays_code, niveau_id, filiere_id, code, nom, version, statut, etablissement_id, source_id)
  values (
    v_niveau.pays_code, p_niveau, p_filiere,
    'ecole-' || v_niveau.code || coalesce('-' || (select code from public.filieres_educatives where id = p_filiere), ''),
    coalesce(v_source.nom, v_niveau.nom || coalesce(' ' || (select code from public.filieres_educatives where id = p_filiere), '')),
    1, 'publie', p_etablissement, v_source.id)
  returning id into v_id;

  if v_source.id is not null then
    insert into public.programmes_matieres (programme_id, code, nom, coefficient, volume_horaire_annuel, ordre, statut, nature)
    select v_id, m.code, m.nom, m.coefficient, m.volume_horaire_annuel, m.ordre, 'publie', m.nature
    from public.programmes_matieres m
    where m.programme_id = v_source.id and m.statut = 'publie';
  end if;

  return v_id;
end;
$$;

-- Ajouter ou modifier une matière du programme de l'école.
create or replace function public.enregistrer_matiere_ecole(
  p_programme uuid,
  p_nom text,
  p_coefficient numeric default null,
  p_volume_annuel int default null,
  p_nature text default 'tronc_commun',
  p_matiere uuid default null,
  p_ordre int default null
)
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_ecole uuid;
  v_id uuid;
  v_code text;
begin
  select etablissement_id into v_ecole from public.programmes_officiels where id = p_programme;
  if v_ecole is null or not public.gere_programme_ecole(v_ecole) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if nullif(trim(coalesce(p_nom, '')), '') is null then
    raise exception 'NOM_REQUIS' using errcode = '22023';
  end if;
  if p_coefficient is not null and (p_coefficient <= 0 or p_coefficient > 99) then
    raise exception 'COEFFICIENT_INVALIDE' using errcode = '22023';
  end if;

  if p_matiere is not null then
    update public.programmes_matieres
       set nom = trim(p_nom), coefficient = p_coefficient, volume_horaire_annuel = p_volume_annuel,
           nature = coalesce(p_nature, nature), ordre = coalesce(p_ordre, ordre), statut = 'publie'
     where id = p_matiere and programme_id = p_programme
    returning id into v_id;
    if v_id is null then
      raise exception 'MATIERE_INCONNUE' using errcode = '22023';
    end if;
    return v_id;
  end if;

  v_code := left(regexp_replace(lower(trim(p_nom)), '[^a-z0-9]+', '-', 'g'), 40);
  if exists (select 1 from public.programmes_matieres where programme_id = p_programme and code = v_code) then
    v_code := v_code || '-' || substr(gen_random_uuid()::text, 1, 4);
  end if;
  insert into public.programmes_matieres (programme_id, code, nom, coefficient, volume_horaire_annuel, ordre, statut, nature)
  values (p_programme, v_code, trim(p_nom), p_coefficient, p_volume_annuel,
          coalesce(p_ordre, (select coalesce(max(ordre), 0) + 1 from public.programmes_matieres where programme_id = p_programme)),
          'publie', coalesce(p_nature, 'tronc_commun'))
  returning id into v_id;
  return v_id;
end;
$$;

-- Retirer une matière : archivée (notes et cours passés gardent leur nom).
create or replace function public.retirer_matiere_ecole(p_matiere uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_ecole uuid;
begin
  select p.etablissement_id into v_ecole
    from public.programmes_matieres m join public.programmes_officiels p on p.id = m.programme_id
   where m.id = p_matiere;
  if v_ecole is null or not public.gere_programme_ecole(v_ecole) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.programmes_matieres set statut = 'archive' where id = p_matiere;
end;
$$;

revoke execute on function public.adopter_programme_ecole(uuid, uuid, uuid) from public, anon;
revoke execute on function public.enregistrer_matiere_ecole(uuid, text, numeric, int, text, uuid, int) from public, anon;
revoke execute on function public.retirer_matiere_ecole(uuid) from public, anon;
grant execute on function public.adopter_programme_ecole(uuid, uuid, uuid) to authenticated;
grant execute on function public.enregistrer_matiere_ecole(uuid, text, numeric, int, text, uuid, int) to authenticated;
grant execute on function public.retirer_matiere_ecole(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Moyenne générale pondérée par les coefficients des matières
-- ---------------------------------------------------------------------------
-- Une matière : moyenne de ses évaluations (coefficient et barème propres),
-- comme avant. Toutes matières : moyenne des moyennes de matières, pondérée
-- par leur coefficient (1 s'il n'est pas renseigné) ; les évaluations sans
-- matière comptent ensemble pour une matière de coefficient 1.
create or replace function public.moyenne_eleve_interne(
  p_fiche uuid,
  p_matiere uuid default null,
  p_periode uuid default null
)
returns numeric
language sql stable security definer set search_path = public
as $$
  with notes_retenues as (
    select e.programme_matiere_id as matiere, n.valeur, e.bareme, e.coefficient
    from public.notes n
    join public.evaluations e on e.id = n.evaluation_id
    where n.fiche_eleve_id = p_fiche
      and n.deleted_at is null and e.deleted_at is null
      and not n.absent
      and e.statut <> 'brouillon'
      and (p_matiere is null or e.programme_matiere_id = p_matiere)
      and (p_periode is null or e.periode_id = p_periode)
  ),
  par_matiere as (
    select r.matiere,
           sum(r.valeur / r.bareme * r.coefficient) / nullif(sum(r.coefficient), 0) * 20 as moyenne,
           coalesce(max(pm.coefficient), 1) as coef
    from notes_retenues r
    left join public.programmes_matieres pm on pm.id = r.matiere
    group by r.matiere
  )
  select case
    when p_matiere is not null then (select round(moyenne, 2) from par_matiere)
    else (select round(sum(moyenne * coef) / nullif(sum(coef), 0), 2) from par_matiere where moyenne is not null)
  end;
$$;
revoke execute on function public.moyenne_eleve_interne(uuid, uuid, uuid) from public, anon, authenticated;

-- Bulletin : coefficient décimal.
create or replace function public.detail_bulletin_matieres(
  p_fiche uuid,
  p_classe uuid,
  p_periode uuid default null
)
returns table(
  matiere text,
  coefficient numeric,
  moyenne numeric,
  enseignant_nom text,
  enseignant_email text
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_isced int;
  v_etablissement uuid;
begin
  v_isced := public.classe_isced(p_classe);
  if v_isced is null or v_isced < 2 then
    return;
  end if;

  select etablissement_id into v_etablissement from public.classes where id = p_classe;

  return query
  select pm.nom,
         pm.coefficient,
         public.calculer_moyenne_eleve(p_fiche, pm.id, p_periode),
         nullif(trim(concat(pr.prenom, ' ', pr.nom)), ''),
         e.email
  from public.affectations_enseignants a
  join public.programmes_matieres pm on pm.id = a.programme_matiere_id
  join public.profiles pr on pr.id = a.enseignant_profile_id
  left join public.employes e on e.profile_id = a.enseignant_profile_id and e.etablissement_id = v_etablissement
  where a.classe_id = p_classe
    and a.deleted_at is null
    and a.programme_matiere_id is not null
  order by pm.ordre, pm.nom;
end;
$$;
grant execute on function public.detail_bulletin_matieres(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Séries du lycée guinéen (Baccalauréat unique) — sans coefficients
-- ---------------------------------------------------------------------------
-- Proposées en 11e, 12e et Terminale : chaque lycée choisit la série de
-- chacune de ses classes (tronc commun : pas de série).
insert into public.filieres_educatives (pays_code, cycle_id, code, nom, description, statut, ordre)
select 'GN', c.id, v.code, v.nom, v.description, 'publie', v.ordre
from (values
  ('SM', 'Sciences mathématiques', 'Série du Baccalauréat unique : dominante mathématiques et physique.', 1),
  ('SE', 'Sciences expérimentales', 'Série du Baccalauréat unique : dominante biologie, chimie et physique.', 2),
  ('SS', 'Sciences sociales', 'Série du Baccalauréat unique : dominante lettres, philosophie, histoire et géographie.', 3)
) as v(code, nom, description, ordre)
join public.cycles_educatifs c on c.pays_code = 'GN' and c.code = 'lycee'
on conflict (pays_code, code) do update
  set nom = excluded.nom, description = excluded.description, cycle_id = excluded.cycle_id,
      ordre = excluded.ordre, statut = 'publie';

insert into public.filieres_niveaux (filiere_id, niveau_id)
select f.id, n.id
from public.filieres_educatives f
join public.niveaux_educatifs n on n.pays_code = 'GN' and n.code in ('11e', '12e', 'Terminale')
where f.pays_code = 'GN' and f.code in ('SM', 'SE', 'SS')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 6. Recommandations de formation (RH) : programmes nationaux et ceux de
--    l'école seulement, jamais ceux d'une autre école.
-- ---------------------------------------------------------------------------
do $$
declare
  v_def text := pg_get_functiondef('public.recommander_formation(uuid, uuid)'::regprocedure);
  v_ancien constant text := 'where p.pays_code = v_pays';
  v_nouveau constant text := 'where p.pays_code = v_pays and (p.etablissement_id is null or p.etablissement_id = v_etab)';
begin
  if position(v_nouveau in v_def) > 0 then
    return;
  end if;
  if position(v_ancien in v_def) = 0 then
    raise exception 'REG-33 : filtre pays introuvable dans recommander_formation';
  end if;
  execute replace(v_def, v_ancien, v_nouveau);
end $$;

-- ---------------------------------------------------------------------------
-- 7. Mise en route : niveaux (et séries) des classes, et ceux sans matières
-- ---------------------------------------------------------------------------
create or replace function public.matieres_disponibles(p_etablissement uuid, p_niveau uuid, p_filiere uuid)
returns integer
language sql stable security definer set search_path = public
as $$
  -- Programme de l'école d'abord (série, puis niveau), sinon national.
  select coalesce((
    select count(m.*)::int
    from public.programmes_officiels p
    join public.programmes_matieres m on m.programme_id = p.id and m.statut = 'publie'
    where p.id = (
      select p2.id from public.programmes_officiels p2
      where p2.niveau_id = p_niveau and p2.statut <> 'archive'
        and (p2.filiere_id is not distinct from p_filiere or p2.filiere_id is null)
        and (p2.etablissement_id = p_etablissement or (p2.etablissement_id is null and p2.statut = 'publie'))
      order by (p2.etablissement_id is null), (p2.filiere_id is null), p2.version desc
      limit 1)
  ), 0);
$$;
revoke execute on function public.matieres_disponibles(uuid, uuid, uuid) from public, anon, authenticated;

do $$
declare
  v_def text := pg_get_functiondef('public.etat_configuration_etablissement(uuid)'::regprocedure);
  v_ancien constant text := E'\n  ) into v_resultat;';
  v_nouveau constant text := E',\n    -- REG-33 : niveaux et séries des classes ; ceux qui n''ont encore aucune matière.\n'
    || E'    ''niveaux_classes'', (select count(*) from (select distinct niveau_id, filiere_id from public.classes\n'
    || E'                      where annee_scolaire_id = v_annee.id and deleted_at is null and actif and niveau_id is not null) t),\n'
    || E'    ''niveaux_sans_matieres'', (select count(*) from (select distinct niveau_id, filiere_id from public.classes\n'
    || E'                      where annee_scolaire_id = v_annee.id and deleted_at is null and actif and niveau_id is not null) t\n'
    || E'                      where public.matieres_disponibles(p_etablissement, t.niveau_id, t.filiere_id) = 0)\n'
    || E'  ) into v_resultat;';
begin
  if position('niveaux_sans_matieres' in v_def) > 0 then
    return;
  end if;
  if position(v_ancien in v_def) = 0 then
    raise exception 'REG-33 : fin de etat_configuration_etablissement introuvable';
  end if;
  execute replace(v_def, v_ancien, v_nouveau);
end $$;
