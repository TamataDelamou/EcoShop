-- ============================================================================
-- EcoShop — M17 : bibliothèque physique (cahier v4.1, ch. 25)
--
-- 1. Catalogue (25.1) : livres (titre, auteurs, ISBN, éditeur, année,
--    catégorie, niveau, cote, résumé) consultables gratuitement par tous les
--    membres de l'établissement, avec la disponibilité ; jamais premium.
-- 2. Inventaire (25.4) : exemplaires numérotés (code LIV-000001 par école)
--    portant une étiquette QR ; état, retrait ; inventaire par scan qui
--    liste les exemplaires introuvables.
-- 3. Prêt et retour (25.2) par le personnel habilité (direction ou
--    permission « bibliotheque.gerer ») : carte QR de l'élève (la même
--    qu'au portail et au bus) puis étiquette du livre ; retour en scannant
--    le livre seul. Limite d'emprunts par élève, durée, renouvellements.
-- 4. Statuts automatiques (25.3) : « en retard » après l'échéance,
--    « perdu » après le délai de perte — calculés à chaque lecture, sans
--    action manuelle ; seuils paramétrables par établissement.
--    Relances (tâche de nuit) : veille de l'échéance, lendemain, une
--    semaine après. Pertes répétées d'un élève signalées à la vie scolaire,
--    sans sanction automatique (règle 25.3).
-- 5. Réservation d'un livre dont tous les exemplaires sont sortis : la
--    famille est prévenue au retour, l'exemplaire lui est gardé 3 jours.
--
-- Hors connexion : le guichet garde catalogue, exemplaires, cartes et prêts
-- en cours sur l'appareil ; prêts et retours rejoués avec leur clé et leur
-- heure réelle (un exemplaire prêté deux fois par deux guichets sans
-- réseau : le second prêt est refusé et expliqué).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table if not exists public.parametres_bibliotheque (
  etablissement_id uuid primary key references public.etablissements (id) on delete cascade,
  duree_pret_jours integer not null default 14 check (duree_pret_jours between 1 and 120),
  max_emprunts integer not null default 2 check (max_emprunts between 1 and 20),
  renouvellements_max integer not null default 1 check (renouvellements_max between 0 and 5),
  delai_perte_jours integer not null default 30 check (delai_perte_jours between 1 and 365),
  relances boolean not null default true,
  inventaire_depuis timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.livres (
  id uuid primary key,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  titre text not null check (char_length(trim(titre)) between 1 and 200),
  auteurs text,
  isbn text check (isbn is null or isbn ~ '^[0-9X]{10}([0-9]{3})?$'),
  editeur text,
  annee integer check (annee is null or annee between 1450 and 2100),
  categorie text,
  niveau text,
  cote text,
  resume text check (resume is null or char_length(resume) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists idx_livres_etab on public.livres (etablissement_id);

create table if not exists public.compteurs_exemplaires (
  etablissement_id uuid primary key references public.etablissements (id) on delete cascade,
  dernier integer not null default 0
);

create table if not exists public.exemplaires (
  id uuid primary key,
  livre_id uuid not null references public.livres (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  code text not null,
  etat text not null default 'bon' check (etat in ('neuf', 'bon', 'abime')),
  retire boolean not null default false,
  vu_inventaire_le timestamptz,
  created_at timestamptz not null default now(),
  constraint exemplaires_code_unique unique (etablissement_id, code)
);
create index if not exists idx_exemplaires_livre on public.exemplaires (livre_id);

create table if not exists public.emprunts (
  id uuid primary key,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  exemplaire_id uuid not null references public.exemplaires (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  emprunte_le timestamptz not null,
  echeance date not null,
  renouvellements integer not null default 0,
  rendu_le timestamptz,
  declare_perdu_le timestamptz,
  prete_par uuid references public.profiles (id),
  recu_par uuid references public.profiles (id),
  derniere_relance text,
  created_at timestamptz not null default now()
);
create unique index if not exists idx_emprunts_un_en_cours
  on public.emprunts (exemplaire_id) where rendu_le is null and declare_perdu_le is null;
create index if not exists idx_emprunts_eleve on public.emprunts (fiche_eleve_id, rendu_le);

create table if not exists public.reservations_livres (
  id uuid primary key default gen_random_uuid(),
  livre_id uuid not null references public.livres (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  demandee_par uuid references public.profiles (id),
  demandee_le timestamptz not null default now(),
  exemplaire_garde_id uuid references public.exemplaires (id) on delete set null,
  gardee_jusqu_au timestamptz,
  close_le timestamptz
);
create unique index if not exists idx_reservation_active
  on public.reservations_livres (livre_id, fiche_eleve_id) where close_le is null;

drop trigger if exists livres_set_updated_at on public.livres;
create trigger livres_set_updated_at before update on public.livres
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Droits et paramètres
-- ---------------------------------------------------------------------------
create or replace function public.gere_bibliotheque(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.est_direction(p_etablissement), false)
      or coalesce(public.a_permission(p_etablissement, 'bibliotheque.gerer'), false);
$$;

create or replace function public.parametres_biblio(p_etablissement uuid)
returns public.parametres_bibliotheque
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select p from public.parametres_bibliotheque p where p.etablissement_id = p_etablissement),
    (p_etablissement, 14, 2, 1, 30, true, null, now())::public.parametres_bibliotheque);
$$;

-- Statut d'un emprunt, calculé (25.3) : jamais besoin d'une action manuelle.
create or replace function public.statut_emprunt(e public.emprunts, p_delai_perte integer)
returns text
language sql stable set search_path = public
as $$
  select case
    when e.rendu_le is not null then 'rendu'
    when e.declare_perdu_le is not null then 'perdu'
    when current_date > e.echeance + p_delai_perte then 'perdu'
    when current_date > e.echeance then 'en_retard'
    else 'en_cours' end;
$$;

alter table public.parametres_bibliotheque enable row level security;
alter table public.livres enable row level security;
alter table public.exemplaires enable row level security;
alter table public.emprunts enable row level security;
alter table public.reservations_livres enable row level security;
alter table public.compteurs_exemplaires enable row level security;

-- Catalogue : tout membre de l'établissement (25.1, gratuit).
drop policy if exists livres_select on public.livres;
create policy livres_select on public.livres
  for select using (deleted_at is null and coalesce(public.est_membre_etab(etablissement_id), false));
drop policy if exists parametres_biblio_select on public.parametres_bibliotheque;
create policy parametres_biblio_select on public.parametres_bibliotheque
  for select using (coalesce(public.est_membre_etab(etablissement_id), false));

revoke all on public.exemplaires, public.emprunts, public.reservations_livres, public.compteurs_exemplaires
  from anon, authenticated;
revoke insert, update, delete on public.livres, public.parametres_bibliotheque from anon, authenticated;

create or replace function public.enregistrer_parametres_bibliotheque(
  p_etablissement uuid, p_duree integer, p_max integer, p_renouvellements integer, p_delai_perte integer, p_relances boolean)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not public.gere_bibliotheque(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  insert into public.parametres_bibliotheque (etablissement_id, duree_pret_jours, max_emprunts, renouvellements_max,
                                              delai_perte_jours, relances, updated_at)
  values (p_etablissement, p_duree, p_max, p_renouvellements, p_delai_perte, coalesce(p_relances, true), now())
  on conflict (etablissement_id) do update set duree_pret_jours = excluded.duree_pret_jours,
    max_emprunts = excluded.max_emprunts, renouvellements_max = excluded.renouvellements_max,
    delai_perte_jours = excluded.delai_perte_jours, relances = excluded.relances, updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Catalogue et exemplaires
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_livre(
  p_id uuid, p_etablissement uuid, p_titre text, p_auteurs text default null, p_isbn text default null,
  p_editeur text default null, p_annee integer default null, p_categorie text default null, p_niveau text default null,
  p_cote text default null, p_resume text default null, p_nouveaux_exemplaires integer default 0)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_isbn text := nullif(regexp_replace(upper(coalesce(p_isbn, '')), '[^0-9X]', '', 'g'), '');
  v_codes text[] := '{}';
  v_n integer;
  i integer;
begin
  if not public.gere_bibliotheque(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if exists (select 1 from public.livres where id = p_id and etablissement_id <> p_etablissement) then
    raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
  end if;
  if coalesce(p_nouveaux_exemplaires, 0) not between 0 and 200 then raise exception 'NOMBRE_EXEMPLAIRES_INVALIDE' using errcode = '22023'; end if;
  insert into public.livres (id, etablissement_id, titre, auteurs, isbn, editeur, annee, categorie, niveau, cote, resume)
  values (p_id, p_etablissement, trim(p_titre), nullif(trim(coalesce(p_auteurs, '')), ''), v_isbn,
          nullif(trim(coalesce(p_editeur, '')), ''), p_annee, nullif(trim(coalesce(p_categorie, '')), ''),
          nullif(trim(coalesce(p_niveau, '')), ''), nullif(trim(coalesce(p_cote, '')), ''), nullif(trim(coalesce(p_resume, '')), ''))
  on conflict (id) do update set titre = excluded.titre, auteurs = excluded.auteurs, isbn = excluded.isbn,
    editeur = excluded.editeur, annee = excluded.annee, categorie = excluded.categorie, niveau = excluded.niveau,
    cote = excluded.cote, resume = excluded.resume, deleted_at = null;

  for i in 1 .. coalesce(p_nouveaux_exemplaires, 0) loop
    insert into public.compteurs_exemplaires (etablissement_id, dernier) values (p_etablissement, 1)
    on conflict (etablissement_id) do update set dernier = public.compteurs_exemplaires.dernier + 1
    returning dernier into v_n;
    insert into public.exemplaires (id, livre_id, etablissement_id, code)
    values (gen_random_uuid(), p_id, p_etablissement, 'LIV-' || lpad(v_n::text, 6, '0'));
    v_codes := v_codes || ('LIV-' || lpad(v_n::text, 6, '0'));
  end loop;
  return jsonb_build_object('id', p_id, 'nouveaux_codes', to_jsonb(v_codes));
end;
$$;

create or replace function public.modifier_exemplaire(p_exemplaire uuid, p_etat text, p_retire boolean)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
begin
  select etablissement_id into v_etab from public.exemplaires where id = p_exemplaire;
  if v_etab is null or not public.gere_bibliotheque(v_etab) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if p_retire and exists (select 1 from public.emprunts where exemplaire_id = p_exemplaire and rendu_le is null and declare_perdu_le is null) then
    raise exception 'EXEMPLAIRE_EMPRUNTE' using errcode = '23514';
  end if;
  update public.exemplaires set etat = coalesce(p_etat, etat), retire = coalesce(p_retire, retire) where id = p_exemplaire;
end;
$$;

-- Catalogue lisible par tout membre : disponibilité, et pour l'élève ou ses
-- parents, sa réservation éventuelle.
create or replace function public.catalogue_bibliotheque(p_etablissement uuid, p_texte text default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_q text := lower(trim(coalesce(p_texte, '')));
begin
  if not coalesce(public.est_membre_etab(p_etablissement), false) and not public.gere_bibliotheque(p_etablissement) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(x order by x ->> 'titre') from (
    select jsonb_build_object(
      'id', l.id, 'titre', l.titre, 'auteurs', l.auteurs, 'isbn', l.isbn, 'editeur', l.editeur, 'annee', l.annee,
      'categorie', l.categorie, 'niveau', l.niveau, 'cote', l.cote, 'resume', l.resume,
      'exemplaires', (select count(*) from public.exemplaires e where e.livre_id = l.id and not e.retire),
      'disponibles', (select count(*) from public.exemplaires e where e.livre_id = l.id and not e.retire
                       and not exists (select 1 from public.emprunts m where m.exemplaire_id = e.id
                                       and m.rendu_le is null and m.declare_perdu_le is null)
                       and not exists (select 1 from public.reservations_livres r where r.exemplaire_garde_id = e.id
                                       and r.close_le is null and r.gardee_jusqu_au > now())),
      'reservations', (select count(*) from public.reservations_livres r where r.livre_id = l.id and r.close_le is null)
    ) as x
    from public.livres l
    where l.etablissement_id = p_etablissement and l.deleted_at is null
      and (v_q = '' or lower(l.titre || ' ' || coalesce(l.auteurs, '') || ' ' || coalesce(l.categorie, '') || ' '
                             || coalesce(l.isbn, '') || ' ' || coalesce(l.cote, '')) like '%' || v_q || '%')
    limit 300) s), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Guichet : données pour travailler sans réseau, prêt, retour
-- ---------------------------------------------------------------------------
create or replace function public.guichet_bibliotheque(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  par public.parametres_bibliotheque := public.parametres_biblio(p_etablissement);
begin
  if not public.gere_bibliotheque(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  return jsonb_build_object(
    'parametres', to_jsonb(par),
    'exemplaires', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'code', e.code, 'livre_id', l.id, 'titre', l.titre,
                       'cote', l.cote, 'etat', e.etat, 'retire', e.retire))
                     from public.exemplaires e join public.livres l on l.id = e.livre_id and l.deleted_at is null
                     where e.etablissement_id = p_etablissement), '[]'::jsonb),
    'cartes', coalesce((select jsonb_agg(jsonb_build_object('jeton', k.jeton, 'fiche_eleve_id', f.id, 'nom', f.nom,
                       'prenom', f.prenom, 'classe', c.nom))
                 from public.cartes_eleves k
                 join public.fiches_eleves f on f.id = k.fiche_eleve_id and f.deleted_at is null
                 join public.inscriptions i on i.fiche_eleve_id = f.id and i.deleted_at is null and i.statut in ('active', 'redoublante')
                 join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
                 join public.classes c on c.id = i.classe_id
                 where k.etablissement_id = p_etablissement), '[]'::jsonb),
    'emprunts', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'exemplaire_id', m.exemplaire_id,
                       'fiche_eleve_id', m.fiche_eleve_id, 'emprunte_le', m.emprunte_le, 'echeance', m.echeance,
                       'renouvellements', m.renouvellements, 'statut', public.statut_emprunt(m, par.delai_perte_jours)))
                   from public.emprunts m where m.etablissement_id = p_etablissement
                     and m.rendu_le is null and m.declare_perdu_le is null), '[]'::jsonb));
end;
$$;

create or replace function public.preter_exemplaire(p_id uuid, p_etablissement uuid, p_fiche uuid, p_code text,
                                                    p_le timestamptz default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  par public.parametres_bibliotheque := public.parametres_biblio(p_etablissement);
  ex public.exemplaires;
  v_quand timestamptz := least(coalesce(p_le, now()), now());
  v_existant public.emprunts;
  v_echeance date;
  v_en_cours integer;
  v_resa public.reservations_livres;
begin
  if not public.gere_bibliotheque(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  select * into v_existant from public.emprunts where id = p_id;
  if found then return jsonb_build_object('id', p_id, 'deja_recu', true, 'echeance', v_existant.echeance); end if;

  if not exists (select 1 from public.fiches_eleves where id = p_fiche and etablissement_id = p_etablissement and deleted_at is null) then
    raise exception 'ELEVE_INCONNU' using errcode = '23514';
  end if;
  select * into ex from public.exemplaires where etablissement_id = p_etablissement and code = upper(trim(p_code)) for update;
  if not found then raise exception 'EXEMPLAIRE_INCONNU' using errcode = '23514'; end if;
  if ex.retire then raise exception 'EXEMPLAIRE_RETIRE' using errcode = '23514'; end if;
  if exists (select 1 from public.emprunts where exemplaire_id = ex.id and rendu_le is null and declare_perdu_le is null) then
    raise exception 'EXEMPLAIRE_DEJA_PRETE' using errcode = '23514';
  end if;
  -- Exemplaire gardé pour une autre famille (réservation).
  select * into v_resa from public.reservations_livres
  where exemplaire_garde_id = ex.id and close_le is null and gardee_jusqu_au > now();
  if found and v_resa.fiche_eleve_id <> p_fiche then raise exception 'EXEMPLAIRE_RESERVE' using errcode = '23514'; end if;

  select count(*) into v_en_cours from public.emprunts
  where fiche_eleve_id = p_fiche and rendu_le is null and declare_perdu_le is null;
  if v_en_cours >= par.max_emprunts then raise exception 'LIMITE_EMPRUNTS' using errcode = '23514'; end if;

  v_echeance := (v_quand at time zone public.fuseau_etablissement(p_etablissement))::date + par.duree_pret_jours;
  insert into public.emprunts (id, etablissement_id, exemplaire_id, fiche_eleve_id, emprunte_le, echeance, prete_par)
  values (p_id, p_etablissement, ex.id, p_fiche, v_quand, v_echeance, auth.uid());
  update public.reservations_livres set close_le = now()
   where livre_id = ex.livre_id and fiche_eleve_id = p_fiche and close_le is null;
  update public.exemplaires set vu_inventaire_le = now() where id = ex.id;
  return jsonb_build_object('id', p_id, 'deja_recu', false, 'echeance', v_echeance,
    'titre', (select titre from public.livres where id = ex.livre_id));
end;
$$;

-- Retour : l'étiquette du livre suffit. Si le livre est réservé, la famille
-- suivante est prévenue et l'exemplaire lui est gardé 3 jours.
create or replace function public.rendre_exemplaire(p_etablissement uuid, p_code text, p_le timestamptz default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  ex public.exemplaires;
  m public.emprunts;
  v_resa public.reservations_livres;
  v_titre text;
  d uuid;
begin
  if not public.gere_bibliotheque(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  select * into ex from public.exemplaires where etablissement_id = p_etablissement and code = upper(trim(p_code));
  if not found then raise exception 'EXEMPLAIRE_INCONNU' using errcode = '23514'; end if;
  select titre into v_titre from public.livres where id = ex.livre_id;
  update public.exemplaires set vu_inventaire_le = now() where id = ex.id;

  select * into m from public.emprunts
  where exemplaire_id = ex.id and rendu_le is null
  order by emprunte_le desc limit 1 for update;
  if not found then return jsonb_build_object('statut', 'pas_emprunte', 'titre', v_titre); end if;
  -- Un livre déclaré perdu qui revient : rendu quand même.
  update public.emprunts set rendu_le = least(coalesce(p_le, now()), now()), recu_par = auth.uid() where id = m.id;

  select * into v_resa from public.reservations_livres
  where livre_id = ex.livre_id and close_le is null and exemplaire_garde_id is null
  order by demandee_le limit 1 for update;
  if found then
    update public.reservations_livres set exemplaire_garde_id = ex.id, gardee_jusqu_au = now() + interval '3 days'
     where id = v_resa.id;
    for d in select x from public.destinataires_eleve(v_resa.fiche_eleve_id) x loop
      perform public.notifier_push(p_etablissement, d, 'bibliotheque_reservation',
        format('Le livre « %s » est disponible à la bibliothèque : il est gardé 3 jours.', v_titre),
        jsonb_build_object('fiche_eleve_id', v_resa.fiche_eleve_id, 'livre_id', ex.livre_id));
    end loop;
  end if;
  return jsonb_build_object('statut', 'rendu', 'titre', v_titre, 'fiche_eleve_id', m.fiche_eleve_id,
    'en_retard', current_date > m.echeance, 'reserve', v_resa.id is not null);
end;
$$;

create or replace function public.renouveler_emprunt(p_emprunt uuid)
returns date
language plpgsql volatile security definer set search_path = public
as $$
declare
  m public.emprunts;
  par public.parametres_bibliotheque;
  v_echeance date;
begin
  select * into m from public.emprunts where id = p_emprunt for update;
  if not found or not public.gere_bibliotheque(m.etablissement_id) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  par := public.parametres_biblio(m.etablissement_id);
  if m.rendu_le is not null or m.declare_perdu_le is not null then raise exception 'EMPRUNT_CLOS' using errcode = '23514'; end if;
  if m.renouvellements >= par.renouvellements_max then raise exception 'RENOUVELLEMENTS_EPUISES' using errcode = '23514'; end if;
  if exists (select 1 from public.reservations_livres r join public.exemplaires e on e.livre_id = r.livre_id
             where e.id = m.exemplaire_id and r.close_le is null and r.fiche_eleve_id <> m.fiche_eleve_id) then
    raise exception 'LIVRE_RESERVE' using errcode = '23514';
  end if;
  v_echeance := greatest(m.echeance, current_date) + par.duree_pret_jours;
  update public.emprunts set echeance = v_echeance, renouvellements = renouvellements + 1, derniere_relance = null
   where id = p_emprunt;
  return v_echeance;
end;
$$;

create or replace function public.declarer_emprunt_perdu(p_emprunt uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
begin
  select etablissement_id into v_etab from public.emprunts where id = p_emprunt;
  if v_etab is null or not public.gere_bibliotheque(v_etab) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  update public.emprunts set declare_perdu_le = now() where id = p_emprunt and rendu_le is null;
end;
$$;

-- Réservation par l'élève ou ses parents, quand aucun exemplaire n'est libre.
create or replace function public.reserver_livre(p_livre uuid, p_fiche uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
begin
  select etablissement_id into v_etab from public.livres where id = p_livre and deleted_at is null;
  if v_etab is null then raise exception 'LIVRE_INCONNU' using errcode = 'P0002'; end if;
  if not (coalesce(public.fiche_visible(p_fiche), false) and not coalesce(public.est_personnel(v_etab), false)
          or public.gere_bibliotheque(v_etab)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if not exists (select 1 from public.fiches_eleves where id = p_fiche and etablissement_id = v_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  insert into public.reservations_livres (livre_id, fiche_eleve_id, demandee_par)
  values (p_livre, p_fiche, auth.uid())
  on conflict do nothing;
end;
$$;

-- Emprunts d'un élève (élève, parents, bibliothèque).
create or replace function public.emprunts_eleve(p_fiche uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etab uuid;
  par public.parametres_bibliotheque;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = p_fiche;
  if v_etab is null or not (coalesce(public.fiche_visible(p_fiche), false) or public.gere_bibliotheque(v_etab)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  par := public.parametres_biblio(v_etab);
  return jsonb_build_object(
    'emprunts', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'titre', l.titre, 'code', e.code,
        'emprunte_le', m.emprunte_le, 'echeance', m.echeance, 'rendu_le', m.rendu_le,
        'statut', public.statut_emprunt(m, par.delai_perte_jours)) order by m.emprunte_le desc)
      from public.emprunts m join public.exemplaires e on e.id = m.exemplaire_id join public.livres l on l.id = e.livre_id
      where m.fiche_eleve_id = p_fiche and m.emprunte_le > now() - interval '1 year'), '[]'::jsonb),
    'reservations', coalesce((select jsonb_agg(jsonb_build_object('livre_id', l.id, 'titre', l.titre,
        'prete', r.exemplaire_garde_id is not null, 'gardee_jusqu_au', r.gardee_jusqu_au))
      from public.reservations_livres r join public.livres l on l.id = r.livre_id
      where r.fiche_eleve_id = p_fiche and r.close_le is null), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Tableau de bord, inventaire
-- ---------------------------------------------------------------------------
create or replace function public.tableau_bibliotheque(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  par public.parametres_bibliotheque := public.parametres_biblio(p_etablissement);
begin
  if not public.gere_bibliotheque(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  return jsonb_build_object(
    'parametres', to_jsonb(par),
    'livres', (select count(*) from public.livres where etablissement_id = p_etablissement and deleted_at is null),
    'exemplaires', (select count(*) from public.exemplaires where etablissement_id = p_etablissement and not retire),
    'en_cours', (select count(*) from public.emprunts m where m.etablissement_id = p_etablissement
                 and public.statut_emprunt(m, par.delai_perte_jours) = 'en_cours'),
    'retards', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'titre', l.titre, 'code', e.code,
        'eleve', f.prenom || ' ' || f.nom, 'classe', (select c.nom from public.inscriptions i join public.classes c on c.id = i.classe_id
            join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante where i.fiche_eleve_id = f.id limit 1),
        'echeance', m.echeance, 'statut', public.statut_emprunt(m, par.delai_perte_jours)) order by m.echeance)
      from public.emprunts m join public.exemplaires e on e.id = m.exemplaire_id join public.livres l on l.id = e.livre_id
      join public.fiches_eleves f on f.id = m.fiche_eleve_id
      where m.etablissement_id = p_etablissement and public.statut_emprunt(m, par.delai_perte_jours) in ('en_retard', 'perdu')
        and m.declare_perdu_le is null), '[]'::jsonb),
    -- Règle 25.3 : pertes répétées signalées, sans sanction automatique.
    'pertes_repetees', coalesce((select jsonb_agg(jsonb_build_object('fiche_eleve_id', f.id, 'eleve', f.prenom || ' ' || f.nom,
        'pertes', x.n) order by x.n desc)
      from (select m.fiche_eleve_id, count(*) n from public.emprunts m where m.etablissement_id = p_etablissement
              and m.rendu_le is null and public.statut_emprunt(m, par.delai_perte_jours) = 'perdu'
            group by m.fiche_eleve_id having count(*) >= 2) x
      join public.fiches_eleves f on f.id = x.fiche_eleve_id), '[]'::jsonb),
    'plus_empruntes', coalesce((select jsonb_agg(jsonb_build_object('titre', y.titre, 'emprunts', y.n) order by y.n desc)
      from (select l.titre, count(*) n from public.emprunts m join public.exemplaires e on e.id = m.exemplaire_id
              join public.livres l on l.id = e.livre_id
            where m.etablissement_id = p_etablissement and m.emprunte_le > now() - interval '1 year'
            group by l.titre order by count(*) desc limit 10) y), '[]'::jsonb),
    'inventaire', case when par.inventaire_depuis is null then null else jsonb_build_object(
        'depuis', par.inventaire_depuis,
        'vus', (select count(*) from public.exemplaires e where e.etablissement_id = p_etablissement and not e.retire
                and e.vu_inventaire_le >= par.inventaire_depuis),
        'introuvables', coalesce((select jsonb_agg(jsonb_build_object('code', e.code, 'titre', l.titre, 'cote', l.cote) order by l.cote, e.code)
            from public.exemplaires e join public.livres l on l.id = e.livre_id
            where e.etablissement_id = p_etablissement and not e.retire
              and (e.vu_inventaire_le is null or e.vu_inventaire_le < par.inventaire_depuis)
              and not exists (select 1 from public.emprunts m where m.exemplaire_id = e.id and m.rendu_le is null)), '[]'::jsonb)) end);
end;
$$;

create or replace function public.commencer_inventaire_bibliotheque(p_etablissement uuid)
returns timestamptz
language plpgsql volatile security definer set search_path = public
as $$
declare
  par public.parametres_bibliotheque := public.parametres_biblio(p_etablissement);
begin
  if not public.gere_bibliotheque(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  insert into public.parametres_bibliotheque (etablissement_id, duree_pret_jours, max_emprunts, renouvellements_max,
                                              delai_perte_jours, relances, inventaire_depuis)
  values (p_etablissement, par.duree_pret_jours, par.max_emprunts, par.renouvellements_max, par.delai_perte_jours, par.relances, now())
  on conflict (etablissement_id) do update set inventaire_depuis = now();
  return now();
end;
$$;

create or replace function public.inventorier_exemplaire(p_etablissement uuid, p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  ex public.exemplaires;
begin
  if not public.gere_bibliotheque(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  update public.exemplaires set vu_inventaire_le = now()
   where etablissement_id = p_etablissement and code = upper(trim(p_code))
  returning * into ex;
  if not found then return jsonb_build_object('statut', 'inconnu'); end if;
  return jsonb_build_object('statut', 'vu', 'titre', (select titre from public.livres where id = ex.livre_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Relances (tâche de nuit) et réservations échues
-- ---------------------------------------------------------------------------
create or replace function public.relancer_emprunts_bibliotheque()
returns integer
language plpgsql volatile security definer set search_path = public
as $$
declare
  r record;
  d uuid;
  v_n integer := 0;
  v_etape text;
begin
  -- Réservations non retirées dans les 3 jours : l'exemplaire passe au suivant.
  update public.reservations_livres set close_le = now()
   where close_le is null and gardee_jusqu_au is not null and gardee_jusqu_au < now();

  for r in
    select m.*, l.titre, f.prenom, p.relances, p.delai_perte_jours,
           (now() at time zone public.fuseau_etablissement(m.etablissement_id))::date as aujourd_hui
    from public.emprunts m
    join public.exemplaires e on e.id = m.exemplaire_id
    join public.livres l on l.id = e.livre_id
    join public.fiches_eleves f on f.id = m.fiche_eleve_id
    left join public.parametres_bibliotheque p on p.etablissement_id = m.etablissement_id
    where m.rendu_le is null and m.declare_perdu_le is null
  loop
    if not coalesce(r.relances, true) then continue; end if;
    v_etape := case
      when r.aujourd_hui = r.echeance - 1 then 'veille'
      when r.aujourd_hui = r.echeance + 1 then 'retard'
      when r.aujourd_hui = r.echeance + 7 then 'retard_7'
      else null end;
    if v_etape is null or v_etape = r.derniere_relance then continue; end if;
    for d in select x from public.destinataires_eleve(r.fiche_eleve_id) x loop
      perform public.notifier_push(r.etablissement_id, d, 'bibliotheque_relance',
        case v_etape
          when 'veille' then format('Bibliothèque : « %s » est à rendre demain par %s.', r.titre, r.prenom)
          else format('Bibliothèque : « %s », emprunté par %s, devait être rendu le %s.', r.titre, r.prenom, to_char(r.echeance, 'DD/MM'))
        end,
        jsonb_build_object('fiche_eleve_id', r.fiche_eleve_id, 'emprunt_id', r.id));
    end loop;
    update public.emprunts set derniere_relance = v_etape where id = r.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- La tâche de nuit (kit de mise en service) inclut désormais les relances
-- de la bibliothèque.
create or replace function public.executer_taches_quotidiennes()
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  a record;
  v_alertes integer := 0;
  v_risques integer := 0;
  v_ecoles integer := 0;
  v_erreurs jsonb := '[]'::jsonb;
  v_n integer;
  v_relances integer := 0;
begin
  for a in
    select an.id, an.etablissement_id
    from public.annees_scolaires an
    join public.etablissements e on e.id = an.etablissement_id
    where an.courante and not an.cloturee and e.deleted_at is null and e.statut = 'actif'
  loop
    begin
      select count(*) into v_n from public.generer_alertes_decrochage(a.etablissement_id, a.id);
      v_alertes := v_alertes + v_n;
      select count(*) into v_n from public.materialiser_risque_reussite(a.etablissement_id, a.id);
      v_risques := v_risques + v_n;
      v_ecoles := v_ecoles + 1;
    exception when others then
      v_erreurs := v_erreurs || jsonb_build_object('etablissement', a.etablissement_id, 'erreur', sqlerrm);
    end;
  end loop;
  begin
    v_relances := public.relancer_emprunts_bibliotheque();
  exception when others then
    v_erreurs := v_erreurs || jsonb_build_object('bibliotheque', sqlerrm);
  end;
  return jsonb_build_object('ecoles', v_ecoles, 'alertes_decrochage', v_alertes,
                            'risques_reussite', v_risques, 'relances_bibliotheque', v_relances, 'erreurs', v_erreurs);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Droits d'exécution
-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'public.gere_bibliotheque(uuid)',
    'public.enregistrer_parametres_bibliotheque(uuid, integer, integer, integer, integer, boolean)',
    'public.enregistrer_livre(uuid, uuid, text, text, text, text, integer, text, text, text, text, integer)',
    'public.modifier_exemplaire(uuid, text, boolean)',
    'public.catalogue_bibliotheque(uuid, text)',
    'public.guichet_bibliotheque(uuid)',
    'public.preter_exemplaire(uuid, uuid, uuid, text, timestamptz)',
    'public.rendre_exemplaire(uuid, text, timestamptz)',
    'public.renouveler_emprunt(uuid)',
    'public.declarer_emprunt_perdu(uuid)',
    'public.reserver_livre(uuid, uuid)',
    'public.emprunts_eleve(uuid)',
    'public.tableau_bibliotheque(uuid)',
    'public.commencer_inventaire_bibliotheque(uuid)',
    'public.inventorier_exemplaire(uuid, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

revoke all on function public.relancer_emprunts_bibliotheque() from public, anon, authenticated;
grant execute on function public.relancer_emprunts_bibliotheque() to service_role;
revoke all on function public.executer_taches_quotidiennes() from public, anon, authenticated;
grant execute on function public.executer_taches_quotidiennes() to service_role;
revoke all on function public.parametres_biblio(uuid) from public, anon, authenticated;
revoke all on function public.statut_emprunt(public.emprunts, integer) from public, anon;
