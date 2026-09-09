-- ============================================================================
-- EcoShop — M15quater — Inscription, réinscription & encaissement de scolarité
--
-- Périmètre (cf. docs/AUDIT_ECOSHOP_FLUTTER.md, points 3/4/6/7 de la liste de
-- recommandations, et docs/contrats/M15quater_inscription_encaissement.md) :
--   • Création d'inscription (nouvel élève), avec génération serveur du
--     matricule et détection de double inscription inter-établissements.
--   • Réinscription annuelle, avec vérifications informatives (impayés,
--     sanction active, statut boursier précédent).
--   • Statut boursier annuel, avec traçabilité qui/quand.
--   • Champs administratifs complémentaires de la fiche élève.
--   • Paramètres établissement : tarifs par niveau, paliers de paiement.
--   • Encaissement de scolarité : entité dédiée, jamais une écriture
--     comptable générale (cf. retrait du reçu PDF de M15ter) — liée
--     explicitement à `fiche_eleve_id`/`inscription_id`, avec calcul serveur
--     du solde (montant dû − montant payé), jamais côté client.
--
-- Principes (cohérents avec M1/M5/M7) : `etablissement_id` dénormalisé sur
-- chaque table + trigger `*_verifie_tenant` ; écritures financières via
-- INSERT direct + RLS (comme `ecritures_comptables`, M14), jamais de
-- confiance sur un champ transmis par le client pour l'auteur ou le solde ;
-- soft-delete/soft-cancel systématique, jamais de suppression physique.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.type_frais_scolaire as enum ('scolarite', 'inscription', 'cantine', 'transport', 'autre');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.moyen_paiement as enum ('especes', 'mobile_money', 'virement', 'cheque', 'autre');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_encaissement as enum ('valide', 'annule');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Enrichissement du dossier élève (champs administratifs, cf. audit M4/M5)
-- ---------------------------------------------------------------------------
alter table public.fiches_eleves add column if not exists numero_classe int check (numero_classe > 0);
alter table public.fiches_eleves add column if not exists nom_pere text;
alter table public.fiches_eleves add column if not exists nom_mere text;
alter table public.fiches_eleves add column if not exists quartier text;
alter table public.fiches_eleves add column if not exists personne_urgence_nom text;
alter table public.fiches_eleves add column if not exists personne_urgence_telephone text;
alter table public.fiches_eleves add column if not exists redoublant boolean not null default false;

-- ---------------------------------------------------------------------------
-- 2. Statut boursier (annuel, par inscription — jamais permanent sur la fiche)
-- ---------------------------------------------------------------------------
alter table public.inscriptions add column if not exists boursier boolean not null default false;
alter table public.inscriptions add column if not exists boursier_modifie_par uuid references public.profiles (id);
alter table public.inscriptions add column if not exists boursier_modifie_le timestamptz;

create or replace function public.inscriptions_verifie_boursier()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.boursier is distinct from old.boursier then
    new.boursier_modifie_par := auth.uid();
    new.boursier_modifie_le := now();
  end if;
  return new;
end $$;

drop trigger if exists inscriptions_verifie_boursier_trg on public.inscriptions;
create trigger inscriptions_verifie_boursier_trg
  before update on public.inscriptions
  for each row execute procedure public.inscriptions_verifie_boursier();

-- ---------------------------------------------------------------------------
-- 3. Paramètres établissement — tarifs par niveau et paliers de paiement
-- ---------------------------------------------------------------------------

-- Tarif par niveau (niveau_id null = tarif par défaut de l'établissement).
create table if not exists public.frais_scolarite_config (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  niveau_id uuid references public.niveaux_educatifs (id) on delete cascade,
  montant_annuel numeric(12, 2) not null check (montant_annuel >= 0),
  frais_inscription numeric(12, 2) not null default 0 check (frais_inscription >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists frais_config_etab_annee_niveau_unique
  on public.frais_scolarite_config (etablissement_id, annee_scolaire_id, coalesce(niveau_id, '00000000-0000-0000-0000-000000000000'))
  where deleted_at is null;

drop trigger if exists frais_config_set_updated_at on public.frais_scolarite_config;
create trigger frais_config_set_updated_at
  before update on public.frais_scolarite_config
  for each row execute procedure public.set_updated_at();

-- Paliers de paiement (ex. « 3 tranches » : 40 % / 30 % / 30 %) — la somme
-- des pourcentages actifs d'un (établissement, année) ne doit jamais dépasser
-- 100 (elle peut être < 100 pendant la construction de la configuration).
create table if not exists public.paliers_paiement_config (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  nom text not null,
  pourcentage numeric(5, 2) not null check (pourcentage > 0 and pourcentage <= 100),
  ordre int not null check (ordre > 0),
  date_limite date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint paliers_ordre_unique unique (etablissement_id, annee_scolaire_id, ordre)
);

drop trigger if exists paliers_config_set_updated_at on public.paliers_paiement_config;
create trigger paliers_config_set_updated_at
  before update on public.paliers_paiement_config
  for each row execute procedure public.set_updated_at();

create or replace function public.paliers_verifie_somme()
returns trigger language plpgsql set search_path = public as $$
declare
  v_etab uuid := coalesce(new.etablissement_id, old.etablissement_id);
  v_annee uuid := coalesce(new.annee_scolaire_id, old.annee_scolaire_id);
  v_somme numeric;
begin
  select coalesce(sum(pourcentage), 0) into v_somme
  from public.paliers_paiement_config
  where etablissement_id = v_etab and annee_scolaire_id = v_annee and deleted_at is null;

  if v_somme > 100 then
    raise exception 'PALIERS_SOMME_DEPASSE_100' using errcode = '23514';
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists paliers_verifie_somme_trg on public.paliers_paiement_config;
create trigger paliers_verifie_somme_trg
  after insert or update on public.paliers_paiement_config
  for each row execute procedure public.paliers_verifie_somme();

-- ---------------------------------------------------------------------------
-- 4. Encaissement de scolarité — entité dédiée (jamais une écriture générale)
-- ---------------------------------------------------------------------------
create table if not exists public.encaissements_scolarite (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  inscription_id uuid not null references public.inscriptions (id) on delete cascade,
  type_frais public.type_frais_scolaire not null default 'scolarite',
  montant numeric(12, 2) not null check (montant > 0),
  moyen_paiement public.moyen_paiement not null default 'especes',
  reference_paiement text,
  date_paiement date not null default current_date,
  saisi_par uuid not null references public.profiles (id),
  statut public.statut_encaissement not null default 'valide',
  motif_annulation text,
  annule_par uuid references public.profiles (id),
  annule_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists encaissements_inscription_idx on public.encaissements_scolarite (inscription_id);
create index if not exists encaissements_fiche_idx on public.encaissements_scolarite (fiche_eleve_id);

drop trigger if exists encaissements_set_updated_at on public.encaissements_scolarite;
create trigger encaissements_set_updated_at
  before update on public.encaissements_scolarite
  for each row execute procedure public.set_updated_at();

-- Cohérence multi-tenant + auteur imposé serveur (jamais transmis par le
-- client) — même discipline que sanctions_verifie_tenant (M7).
create or replace function public.encaissements_verifie_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_etab uuid; v_etab_insc uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab_insc from public.inscriptions where id = new.inscription_id;
  if v_etab_insc is distinct from new.etablissement_id then
    raise exception 'INSCRIPTION_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  if not exists (
    select 1 from public.inscriptions i
    where i.id = new.inscription_id and i.fiche_eleve_id = new.fiche_eleve_id and i.deleted_at is null
  ) then
    raise exception 'INSCRIPTION_FICHE_INCOHERENTE' using errcode = '23514';
  end if;

  if tg_op = 'INSERT' then
    new.saisi_par := auth.uid();
  end if;

  return new;
end $$;

drop trigger if exists encaissements_verifie_tenant_trg on public.encaissements_scolarite;
create trigger encaissements_verifie_tenant_trg
  before insert or update on public.encaissements_scolarite
  for each row execute procedure public.encaissements_verifie_tenant();

-- Un encaissement validé est un fait comptable : seule l'annulation
-- (statut + motif + qui + quand) peut changer après coup, jamais le montant,
-- le moyen ou la date — intégrité de la piste d'audit.
create or replace function public.encaissements_verifie_immuable()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.montant is distinct from old.montant
     or new.moyen_paiement is distinct from old.moyen_paiement
     or new.date_paiement is distinct from old.date_paiement
     or new.fiche_eleve_id is distinct from old.fiche_eleve_id
     or new.inscription_id is distinct from old.inscription_id
     or new.etablissement_id is distinct from old.etablissement_id
     or new.saisi_par is distinct from old.saisi_par then
    raise exception 'ENCAISSEMENT_CHAMP_IMMUABLE' using errcode = '23514';
  end if;
  if new.statut = 'annule' and old.statut = 'valide' and (new.motif_annulation is null or length(trim(new.motif_annulation)) = 0) then
    raise exception 'ANNULATION_MOTIF_REQUIS' using errcode = '23514';
  end if;
  if new.statut = 'annule' and old.statut = 'annule' then
    raise exception 'ENCAISSEMENT_DEJA_ANNULE' using errcode = '23514';
  end if;
  if new.statut = 'annule' and old.statut = 'valide' then
    new.annule_par := auth.uid();
    new.annule_le := now();
  end if;
  return new;
end $$;

drop trigger if exists encaissements_verifie_immuable_trg on public.encaissements_scolarite;
create trigger encaissements_verifie_immuable_trg
  before update on public.encaissements_scolarite
  for each row execute procedure public.encaissements_verifie_immuable();

-- ---------------------------------------------------------------------------
-- 5. Helpers de droits et de visibilité (SECURITY DEFINER)
-- ---------------------------------------------------------------------------

create or replace function public.encaissement_visible(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.encaissements_scolarite e
    where e.id = p_id
      and (public.est_personnel(e.etablissement_id) or public.fiche_visible(e.fiche_eleve_id))
  );
$$;

-- ---------------------------------------------------------------------------
-- 6. Calcul serveur du solde — jamais côté client (ch. 34)
-- ---------------------------------------------------------------------------
create or replace function public.solde_scolarite(p_inscription_id uuid)
returns table(montant_du numeric, montant_paye numeric, solde numeric)
language sql stable security definer set search_path = public
as $$
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
$$;

grant execute on function public.encaissement_visible(uuid) to authenticated;
grant execute on function public.solde_scolarite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. RPC — création d'inscription, réinscription, détection de doublon
-- ---------------------------------------------------------------------------

-- Détection de double inscription (règle absolue : ne renvoie qu'un
-- booléen, jamais les données de l'établissement concurrent — protège la
-- confidentialité inter-établissement tout en donnant le signal attendu).
create or replace function public.verifier_doublon_eleve(p_nom text, p_prenom text, p_date_naissance date)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.fiches_eleves f
    join public.inscriptions i on i.fiche_eleve_id = f.id and i.deleted_at is null and i.statut = 'active'
    where lower(trim(f.nom)) = lower(trim(p_nom))
      and lower(trim(f.prenom)) = lower(trim(p_prenom))
      and f.date_naissance = p_date_naissance
      and f.deleted_at is null
  );
$$;

grant execute on function public.verifier_doublon_eleve(text, text, date) to authenticated;

-- Création d'un nouvel élève + sa première inscription. Matricule généré
-- serveur (préfixe = slug établissement, compteur séquentiel) — limite
-- connue : le compteur n'est pas verrouillé contre une double exécution
-- strictement simultanée (risque de collision extrêmement rare, rattrapé
-- par la contrainte unique `fiches_matricule_unique`) ; à revoir si un
-- usage à très haute concurrence de saisie le justifie.
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
  if not (public.a_permission(p_etablissement, 'scolarite.inscription.gerer') or public.est_direction(p_etablissement)) then
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

grant execute on function public.creer_inscription_nouvel_eleve(uuid, text, text, date, uuid, uuid, text) to authenticated;

-- Vérifications informatives avant réinscription (le client les affiche à
-- l'utilisateur avant confirmation — pas un blocage serveur absolu, cohérent
-- avec le comportement documenté côté source : des alertes, pas des refus).
create or replace function public.verifications_reinscription(p_fiche_eleve_id uuid, p_annee_precedente_id uuid)
returns table(impaye boolean, sanction_active boolean, boursier_precedent boolean)
language sql stable security definer set search_path = public
as $$
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
$$;

grant execute on function public.verifications_reinscription(uuid, uuid) to authenticated;

-- Réinscription : nouvelle ligne d'inscription pour une fiche existante.
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

  if not (public.a_permission(v_etab, 'scolarite.inscription.gerer') or public.est_direction(v_etab)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  insert into public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
  values (v_etab, p_fiche_eleve_id, p_classe_id, p_annee_scolaire_id, 'active')
  returning id into v_inscription_id;

  return v_inscription_id;
end;
$$;

grant execute on function public.creer_reinscription(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.frais_scolarite_config enable row level security;
alter table public.paliers_paiement_config enable row level security;
alter table public.encaissements_scolarite enable row level security;

-- Paramètres financiers : lecture par toute personne concernée par
-- l'établissement (personnel, élève, parent — transparence sur les tarifs) ;
-- écriture réservée à la permission dédiée ou à la direction.
drop policy if exists "frais_config_select_concernes" on public.frais_scolarite_config;
create policy "frais_config_select_concernes" on public.frais_scolarite_config
  for select using (public.concerne_etablissement(etablissement_id));

drop policy if exists "frais_config_ecriture_gestion" on public.frais_scolarite_config;
create policy "frais_config_ecriture_gestion" on public.frais_scolarite_config
  for all
  using (public.a_permission(etablissement_id, 'scolarite.parametres.gerer') or public.est_direction(etablissement_id))
  with check (public.a_permission(etablissement_id, 'scolarite.parametres.gerer') or public.est_direction(etablissement_id));

drop policy if exists "paliers_config_select_concernes" on public.paliers_paiement_config;
create policy "paliers_config_select_concernes" on public.paliers_paiement_config
  for select using (public.concerne_etablissement(etablissement_id));

drop policy if exists "paliers_config_ecriture_gestion" on public.paliers_paiement_config;
create policy "paliers_config_ecriture_gestion" on public.paliers_paiement_config
  for all
  using (public.a_permission(etablissement_id, 'scolarite.parametres.gerer') or public.est_direction(etablissement_id))
  with check (public.a_permission(etablissement_id, 'scolarite.parametres.gerer') or public.est_direction(etablissement_id));

-- Encaissements : lecture par visibilité (personnel, élève concerné, parent
-- confirmé) ; création par la permission dédiée ou la direction ; mise à
-- jour (annulation uniquement, cf. trigger d'immutabilité) même périmètre ;
-- AUCUNE policy DELETE — un encaissement ne se supprime jamais, il s'annule.
drop policy if exists "encaissements_select_visible" on public.encaissements_scolarite;
create policy "encaissements_select_visible" on public.encaissements_scolarite
  for select using (public.encaissement_visible(id));

drop policy if exists "encaissements_insert_gestion" on public.encaissements_scolarite;
create policy "encaissements_insert_gestion" on public.encaissements_scolarite
  for insert to authenticated
  with check (public.a_permission(etablissement_id, 'scolarite.encaissement.gerer') or public.est_direction(etablissement_id));

drop policy if exists "encaissements_update_annulation" on public.encaissements_scolarite;
create policy "encaissements_update_annulation" on public.encaissements_scolarite
  for update
  using (public.a_permission(etablissement_id, 'scolarite.encaissement.gerer') or public.est_direction(etablissement_id))
  with check (public.a_permission(etablissement_id, 'scolarite.encaissement.gerer') or public.est_direction(etablissement_id));
