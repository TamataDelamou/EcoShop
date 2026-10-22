-- ============================================================================
-- EcoShop — M18 : transport scolaire (cahier v4.1, ch. 24)
--
-- 1. Circuits (véhicule, capacité, chauffeur, tarif annuel) et arrêts
--    ordonnés (repère, position, heures de passage matin et soir) — 24.1.
-- 2. Affectation d'un élève à un circuit et à son arrêt pour l'année — 24.2.
-- 3. Trajets : le chauffeur démarre un trajet (aller ou retour), signale
--    sa position, les arrêts passés ; scanne la carte QR de l'élève (la
--    même que le portail, REG-09) à la montée et à la descente — 24.3.
--    Familles prévenues par push : montée, descente, bus qui approche de
--    leur arrêt. En fin de trajet, la liste des enfants encore à bord est
--    rendue au chauffeur et signalée à la direction (aucun enfant oublié).
-- 4. Vie privée (34, rétention) : seule la DERNIÈRE position est gardée, et
--    seulement pendant le trajet ; elle est effacée à la fin du trajet. Le
--    parent ne voit la position que pendant un trajet en cours du circuit
--    de son enfant. Le chauffeur n'accède qu'à ses circuits (règle 24.3) :
--    nom, prénom, classe, arrêt et carte des élèves transportés.
-- 5. Facturation (24.4) : même circuit de paiement que la scolarité
--    (encaissements de type « transport ») ; le dû vient du tarif du circuit.
--
-- Hors connexion : trajet, positions, arrêts passés et scans gardés sur le
-- téléphone du chauffeur avec leur clé et l'heure réelle, rejoués dans
-- l'ordre ; le serveur reconnaît les clés (jamais de doublon). Un avis
-- rejoué plus de 15 minutes après les faits n'est plus envoyé aux familles
-- (il ne servirait plus à rien), mais l'événement est enregistré.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table if not exists public.circuits_transport (
  id uuid primary key,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  nom text not null check (char_length(trim(nom)) between 2 and 80),
  vehicule text,
  capacite integer check (capacite is null or capacite between 1 and 200),
  chauffeur_profile_id uuid references public.profiles (id) on delete set null,
  telephone_chauffeur text,
  tarif_annuel numeric(12, 2) not null default 0 check (tarif_annuel >= 0),
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_circuits_etab on public.circuits_transport (etablissement_id);
create index if not exists idx_circuits_chauffeur on public.circuits_transport (chauffeur_profile_id);

create table if not exists public.arrets_transport (
  id uuid primary key,
  circuit_id uuid not null references public.circuits_transport (id) on delete cascade,
  ordre integer not null check (ordre >= 1),
  nom text not null check (char_length(trim(nom)) between 2 and 80),
  repere text,
  latitude double precision check (latitude is null or latitude between -90 and 90),
  longitude double precision check (longitude is null or longitude between -180 and 180),
  heure_matin time,
  heure_soir time,
  actif boolean not null default true
);
create index if not exists idx_arrets_circuit on public.arrets_transport (circuit_id, ordre);

create table if not exists public.affectations_transport (
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  circuit_id uuid not null references public.circuits_transport (id) on delete cascade,
  arret_id uuid not null references public.arrets_transport (id) on delete restrict,
  affecte_par uuid references public.profiles (id),
  affecte_le timestamptz not null default now(),
  primary key (fiche_eleve_id, annee_scolaire_id)
);
create index if not exists idx_affectations_circuit on public.affectations_transport (circuit_id);

create table if not exists public.trajets_transport (
  id uuid primary key,
  circuit_id uuid not null references public.circuits_transport (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  sens text not null check (sens in ('aller', 'retour')),
  chauffeur_profile_id uuid not null references public.profiles (id),
  demarre_le timestamptz not null,
  termine_le timestamptz,
  latitude double precision,
  longitude double precision,
  position_le timestamptz,
  dernier_arret_ordre integer,
  dernier_arret_le timestamptz,
  restes_a_bord integer,
  created_at timestamptz not null default now()
);
create index if not exists idx_trajets_circuit on public.trajets_transport (circuit_id, demarre_le desc);
create unique index if not exists idx_trajets_un_en_cours
  on public.trajets_transport (circuit_id) where termine_le is null;

create table if not exists public.passages_arrets (
  trajet_id uuid not null references public.trajets_transport (id) on delete cascade,
  arret_id uuid not null references public.arrets_transport (id) on delete cascade,
  passe_le timestamptz not null,
  primary key (trajet_id, arret_id)
);

create table if not exists public.montees_transport (
  id uuid primary key,
  trajet_id uuid not null references public.trajets_transport (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  evenement text not null check (evenement in ('montee', 'descente')),
  arret_id uuid references public.arrets_transport (id) on delete set null,
  scanne_le timestamptz not null,
  recu_le timestamptz not null default now()
);
create index if not exists idx_montees_trajet on public.montees_transport (trajet_id, fiche_eleve_id, scanne_le);

drop trigger if exists circuits_set_updated_at on public.circuits_transport;
create trigger circuits_set_updated_at before update on public.circuits_transport
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Droits
-- ---------------------------------------------------------------------------
create or replace function public.gere_transport(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.est_direction(p_etablissement), false)
      or coalesce(public.a_permission(p_etablissement, 'transport.gerer'), false);
$$;

create or replace function public.conduit_circuit(p_circuit uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.circuits_transport c
                 where c.id = p_circuit and c.actif and c.chauffeur_profile_id = auth.uid());
$$;

alter table public.circuits_transport enable row level security;
alter table public.arrets_transport enable row level security;
alter table public.affectations_transport enable row level security;
alter table public.trajets_transport enable row level security;
alter table public.passages_arrets enable row level security;
alter table public.montees_transport enable row level security;

drop policy if exists circuits_select on public.circuits_transport;
create policy circuits_select on public.circuits_transport
  for select using (public.gere_transport(etablissement_id) or chauffeur_profile_id = auth.uid());
drop policy if exists arrets_select on public.arrets_transport;
create policy arrets_select on public.arrets_transport
  for select using (exists (select 1 from public.circuits_transport c where c.id = circuit_id
                            and (public.gere_transport(c.etablissement_id) or c.chauffeur_profile_id = auth.uid())));

-- Positions, montées, affectations : uniquement par les fonctions.
revoke all on public.trajets_transport, public.passages_arrets, public.montees_transport,
  public.affectations_transport from anon, authenticated;
revoke insert, update, delete on public.circuits_transport, public.arrets_transport from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Gestion des circuits (direction)
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_circuit_transport(
  p_id uuid, p_etablissement uuid, p_nom text, p_vehicule text, p_capacite integer, p_tarif_annuel numeric,
  p_chauffeur text default null, p_actif boolean default true)
returns jsonb
language plpgsql volatile security definer set search_path = public, auth
as $$
declare
  v_chauffeur uuid;
  v_tel text := regexp_replace(coalesce(p_chauffeur, ''), '[^0-9]', '', 'g');
  v_id text := lower(trim(coalesce(p_chauffeur, '')));
begin
  if not public.gere_transport(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if exists (select 1 from public.circuits_transport where id = p_id and etablissement_id <> p_etablissement) then
    raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
  end if;
  if v_id <> '' then
    if v_tel like '00%' then v_tel := substr(v_tel, 3); end if;
    if length(v_tel) = 9 and v_tel like '6%' then v_tel := '224' || v_tel; end if;
    select u.id into v_chauffeur from auth.users u
    where (v_id like '%@%' and lower(u.email) = v_id) or (v_id not like '%@%' and length(v_tel) >= 8 and u.phone = v_tel)
    limit 1;
    if v_chauffeur is null then raise exception 'COMPTE_CHAUFFEUR_INTROUVABLE' using errcode = 'P0002'; end if;
  end if;
  insert into public.circuits_transport (id, etablissement_id, nom, vehicule, capacite, tarif_annuel, chauffeur_profile_id,
                                         telephone_chauffeur, actif)
  values (p_id, p_etablissement, trim(p_nom), nullif(trim(coalesce(p_vehicule, '')), ''), p_capacite,
          coalesce(p_tarif_annuel, 0), v_chauffeur, nullif(v_tel, ''), coalesce(p_actif, true))
  on conflict (id) do update set nom = excluded.nom, vehicule = excluded.vehicule, capacite = excluded.capacite,
    tarif_annuel = excluded.tarif_annuel, chauffeur_profile_id = excluded.chauffeur_profile_id,
    telephone_chauffeur = excluded.telephone_chauffeur, actif = excluded.actif;
  -- Accès limité au transport (24.3) : le chauffeur est reconnu par son
  -- circuit seulement, jamais ajouté aux membres de l'établissement (il
  -- verrait sinon les fiches de tous les élèves).
  return jsonb_build_object('id', p_id, 'chauffeur_profile_id', v_chauffeur);
end;
$$;

-- Remplace la liste ordonnée des arrêts d'un circuit. Un arrêt où des élèves
-- sont affectés ne peut pas disparaître (il faut d'abord les réaffecter).
create or replace function public.enregistrer_arrets_transport(p_circuit uuid, p_arrets jsonb)
returns integer
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
  a jsonb;
  v_ordre integer := 0;
  v_ids uuid[] := '{}';
begin
  select etablissement_id into v_etab from public.circuits_transport where id = p_circuit;
  if v_etab is null or not public.gere_transport(v_etab) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  for a in select * from jsonb_array_elements(coalesce(p_arrets, '[]'::jsonb)) loop
    v_ordre := v_ordre + 1;
    if exists (select 1 from public.arrets_transport where id = (a ->> 'id')::uuid and circuit_id <> p_circuit) then
      raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
    end if;
    insert into public.arrets_transport (id, circuit_id, ordre, nom, repere, latitude, longitude, heure_matin, heure_soir, actif)
    values ((a ->> 'id')::uuid, p_circuit, v_ordre, trim(a ->> 'nom'), nullif(trim(coalesce(a ->> 'repere', '')), ''),
            (a ->> 'latitude')::double precision, (a ->> 'longitude')::double precision,
            (a ->> 'heure_matin')::time, (a ->> 'heure_soir')::time, true)
    on conflict (id) do update set ordre = excluded.ordre, nom = excluded.nom, repere = excluded.repere,
      latitude = excluded.latitude, longitude = excluded.longitude, heure_matin = excluded.heure_matin,
      heure_soir = excluded.heure_soir, actif = true;
    v_ids := v_ids || (a ->> 'id')::uuid;
  end loop;
  if exists (select 1 from public.affectations_transport af
             where af.circuit_id = p_circuit and not (af.arret_id = any (v_ids))) then
    raise exception 'ARRET_AVEC_ELEVES' using errcode = '23514';
  end if;
  update public.arrets_transport set actif = false, ordre = 1000 + ordre
   where circuit_id = p_circuit and not (id = any (v_ids));
  return v_ordre;
end;
$$;

create or replace function public.affecter_eleve_transport(p_fiche uuid, p_circuit uuid, p_arret uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_annee uuid;
  v_capacite integer;
begin
  select etablissement_id, capacite into v_etab, v_capacite from public.circuits_transport where id = p_circuit and actif;
  if v_etab is null or not public.gere_transport(v_etab) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if not exists (select 1 from public.fiches_eleves where id = p_fiche and etablissement_id = v_etab and deleted_at is null) then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  if not exists (select 1 from public.arrets_transport where id = p_arret and circuit_id = p_circuit and actif) then
    raise exception 'ARRET_INCONNU' using errcode = '23514';
  end if;
  select id into v_annee from public.annees_scolaires where etablissement_id = v_etab and courante limit 1;
  if v_annee is null then raise exception 'ANNEE_COURANTE_ABSENTE' using errcode = '23514'; end if;
  if v_capacite is not null and (select count(*) from public.affectations_transport
                                 where circuit_id = p_circuit and annee_scolaire_id = v_annee and fiche_eleve_id <> p_fiche) >= v_capacite then
    raise exception 'CIRCUIT_COMPLET' using errcode = '23514';
  end if;
  insert into public.affectations_transport (fiche_eleve_id, annee_scolaire_id, etablissement_id, circuit_id, arret_id, affecte_par)
  values (p_fiche, v_annee, v_etab, p_circuit, p_arret, auth.uid())
  on conflict (fiche_eleve_id, annee_scolaire_id) do update
    set circuit_id = excluded.circuit_id, arret_id = excluded.arret_id, affecte_par = excluded.affecte_par, affecte_le = now();
end;
$$;

create or replace function public.retirer_affectation_transport(p_fiche uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = p_fiche;
  if v_etab is null or not public.gere_transport(v_etab) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  delete from public.affectations_transport a
  using public.annees_scolaires an
  where a.fiche_eleve_id = p_fiche and an.id = a.annee_scolaire_id and an.courante;
end;
$$;

-- Recherche d'élèves de l'année courante (nom, prénom, matricule), avec leur
-- circuit actuel, pour les affecter.
create or replace function public.rechercher_eleves_transport(p_etablissement uuid, p_texte text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_q text := lower(trim(coalesce(p_texte, '')));
begin
  if not public.gere_transport(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if char_length(v_q) < 2 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(x order by x ->> 'nom', x ->> 'prenom') from (
      select jsonb_build_object('fiche_eleve_id', f.id, 'nom', f.nom, 'prenom', f.prenom, 'matricule', f.matricule,
               'classe', cl.nom,
               'circuit_id', af.circuit_id, 'arret_id', af.arret_id) as x
      from public.fiches_eleves f
      join public.inscriptions i on i.fiche_eleve_id = f.id and i.deleted_at is null and i.statut in ('active', 'redoublante')
      join public.annees_scolaires an on an.id = i.annee_scolaire_id and an.courante
      join public.classes cl on cl.id = i.classe_id
      left join public.affectations_transport af on af.fiche_eleve_id = f.id and af.annee_scolaire_id = an.id
      where f.etablissement_id = p_etablissement and f.deleted_at is null
        and (lower(f.nom || ' ' || f.prenom) like '%' || v_q || '%' or lower(f.prenom || ' ' || f.nom) like '%' || v_q || '%'
             or lower(f.matricule) = v_q)
      limit 30) s), '[]'::jsonb);
end;
$$;

-- Vue de la direction : circuits, arrêts, élèves affectés, trajet du jour,
-- facturation (tarif du circuit, payé en encaissements « transport »).
create or replace function public.transport_etablissement(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_annee uuid;
begin
  if not public.gere_transport(p_etablissement) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  select id into v_annee from public.annees_scolaires where etablissement_id = p_etablissement and courante limit 1;
  return jsonb_build_object(
    'circuits', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'nom', c.nom, 'vehicule', c.vehicule, 'capacite', c.capacite, 'tarif_annuel', c.tarif_annuel,
        'actif', c.actif, 'chauffeur_profile_id', c.chauffeur_profile_id, 'telephone_chauffeur', c.telephone_chauffeur,
        'chauffeur', (select trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')) from public.profiles p where p.id = c.chauffeur_profile_id),
        'arrets', coalesce((select jsonb_agg(jsonb_build_object(
            'id', a.id, 'ordre', a.ordre, 'nom', a.nom, 'repere', a.repere, 'latitude', a.latitude, 'longitude', a.longitude,
            'heure_matin', to_char(a.heure_matin, 'HH24:MI'), 'heure_soir', to_char(a.heure_soir, 'HH24:MI'),
            'eleves', (select count(*) from public.affectations_transport af where af.arret_id = a.id and af.annee_scolaire_id = v_annee))
            order by a.ordre) from public.arrets_transport a where a.circuit_id = c.id and a.actif), '[]'::jsonb),
        'eleves', coalesce((select jsonb_agg(jsonb_build_object(
            'fiche_eleve_id', f.id, 'nom', f.nom, 'prenom', f.prenom, 'arret_id', af.arret_id,
            'montant_du', c.tarif_annuel,
            'montant_paye', coalesce((select sum(es.montant) from public.encaissements_scolarite es
                                      join public.inscriptions i on i.id = es.inscription_id and i.annee_scolaire_id = v_annee
                                      where es.fiche_eleve_id = f.id and es.statut = 'valide' and es.type_frais = 'transport'), 0))
            order by f.nom, f.prenom)
          from public.affectations_transport af join public.fiches_eleves f on f.id = af.fiche_eleve_id
          where af.circuit_id = c.id and af.annee_scolaire_id = v_annee), '[]'::jsonb),
        'trajet_en_cours', (select jsonb_build_object('id', t.id, 'sens', t.sens, 'demarre_le', t.demarre_le,
                               'dernier_arret_ordre', t.dernier_arret_ordre, 'position_le', t.position_le,
                               'a_bord', public.nombre_a_bord(t.id))
                            from public.trajets_transport t where t.circuit_id = c.id and t.termine_le is null),
        'dernier_trajet', (select jsonb_build_object('sens', t.sens, 'demarre_le', t.demarre_le, 'termine_le', t.termine_le,
                              'restes_a_bord', t.restes_a_bord)
                           from public.trajets_transport t where t.circuit_id = c.id and t.termine_le is not null
                           order by t.termine_le desc limit 1)
      ) order by c.actif desc, c.nom)
      from public.circuits_transport c where c.etablissement_id = p_etablissement), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Trajets (chauffeur)
-- ---------------------------------------------------------------------------
-- Élèves à bord : dernier scan « montée » sans « descente » après.
create or replace function public.eleves_a_bord(p_trajet uuid)
returns table (fiche_eleve_id uuid)
language sql stable security definer set search_path = public
as $$
  select m.fiche_eleve_id from (
    select distinct on (fiche_eleve_id) fiche_eleve_id, evenement
    from public.montees_transport where trajet_id = p_trajet
    -- À la même seconde, la descente l'emporte (cas improbable, sans danger).
    order by fiche_eleve_id, scanne_le desc, (evenement = 'descente') desc, recu_le desc
  ) m where m.evenement = 'montee';
$$;

create or replace function public.nombre_a_bord(p_trajet uuid)
returns integer
language sql stable security definer set search_path = public
as $$
  select count(*)::int from public.eleves_a_bord(p_trajet);
$$;

-- Circuits du chauffeur, avec ce qu'il faut pour travailler sans réseau :
-- arrêts, élèves (nom, prénom, classe, arrêt) et cartes de ces élèves.
create or replace function public.mes_circuits_chauffeur()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'nom', c.nom, 'vehicule', c.vehicule, 'etablissement_id', c.etablissement_id,
    'etablissement', (select nom from public.etablissements where id = c.etablissement_id),
    'arrets', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'ordre', a.ordre, 'nom', a.nom, 'repere', a.repere, 'latitude', a.latitude, 'longitude', a.longitude,
        'heure_matin', to_char(a.heure_matin, 'HH24:MI'), 'heure_soir', to_char(a.heure_soir, 'HH24:MI')) order by a.ordre)
      from public.arrets_transport a where a.circuit_id = c.id and a.actif), '[]'::jsonb),
    'eleves', coalesce((select jsonb_agg(jsonb_build_object(
        'fiche_eleve_id', f.id, 'nom', f.nom, 'prenom', f.prenom, 'arret_id', af.arret_id, 'jeton', k.jeton,
        'classe', (select cl.nom from public.inscriptions i join public.classes cl on cl.id = i.classe_id
                   where i.fiche_eleve_id = f.id and i.annee_scolaire_id = af.annee_scolaire_id and i.deleted_at is null limit 1))
        order by f.nom, f.prenom)
      from public.affectations_transport af
      join public.annees_scolaires an on an.id = af.annee_scolaire_id and an.courante
      join public.fiches_eleves f on f.id = af.fiche_eleve_id and f.deleted_at is null
      left join public.cartes_eleves k on k.fiche_eleve_id = f.id
      where af.circuit_id = c.id), '[]'::jsonb),
    'trajet_en_cours', (select jsonb_build_object('id', t.id, 'sens', t.sens, 'demarre_le', t.demarre_le,
                           'dernier_arret_ordre', t.dernier_arret_ordre)
                        from public.trajets_transport t where t.circuit_id = c.id and t.termine_le is null)
  ) order by c.nom), '[]'::jsonb)
  from public.circuits_transport c where c.chauffeur_profile_id = auth.uid() and c.actif;
$$;

create or replace function public.demarrer_trajet(p_id uuid, p_circuit uuid, p_sens text, p_demarre_le timestamptz default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_existant public.trajets_transport;
begin
  if not public.conduit_circuit(p_circuit) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  select * into v_existant from public.trajets_transport where id = p_id;
  if found then
    if v_existant.circuit_id <> p_circuit then raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505'; end if;
    return jsonb_build_object('id', p_id, 'deja_recu', true);
  end if;
  select etablissement_id into v_etab from public.circuits_transport where id = p_circuit;
  -- Un trajet resté ouvert (téléphone éteint) est clos par le nouveau départ.
  update public.trajets_transport set termine_le = coalesce(p_demarre_le, now()), latitude = null, longitude = null,
         restes_a_bord = public.nombre_a_bord(id)
   where circuit_id = p_circuit and termine_le is null;
  insert into public.trajets_transport (id, circuit_id, etablissement_id, sens, chauffeur_profile_id, demarre_le)
  values (p_id, p_circuit, v_etab, p_sens, auth.uid(), least(coalesce(p_demarre_le, now()), now()));
  return jsonb_build_object('id', p_id, 'deja_recu', false);
end;
$$;

create or replace function public.signaler_position_trajet(p_trajet uuid, p_latitude double precision, p_longitude double precision,
                                                           p_le timestamptz default null)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.trajets_transport;
begin
  select * into t from public.trajets_transport where id = p_trajet;
  if not found or not public.conduit_circuit(t.circuit_id) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if t.termine_le is not null then return; end if;  -- position arrivée après la fin : ignorée
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'POSITION_INVALIDE' using errcode = '22023';
  end if;
  -- Seule la position la plus récente compte (renvois hors connexion dans le désordre).
  update public.trajets_transport set latitude = p_latitude, longitude = p_longitude,
         position_le = least(coalesce(p_le, now()), now())
   where id = p_trajet and (position_le is null or position_le <= least(coalesce(p_le, now()), now()));
end;
$$;

-- Avis aux familles d'un élève, en respectant leur choix (REG-09) et en
-- écartant les avis devenus inutiles (rejeu tardif).
create or replace function public.aviser_familles_transport(p_etab uuid, p_fiche uuid, p_type text, p_texte text,
                                                            p_quand timestamptz, p_variables jsonb)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  d uuid;
begin
  if now() - p_quand > interval '15 minutes' then return; end if;
  for d in select x from public.destinataires_eleve(p_fiche) x loop
    if coalesce((select arrivee_sortie from public.preferences_pointage where profile_id = d), true) then
      perform public.notifier_push(p_etab, d, p_type, p_texte, p_variables);
    end if;
  end loop;
end;
$$;

-- Arrêt passé : enregistré, puis avis « le bus approche » aux familles de
-- l'arrêt suivant du sens du trajet.
create or replace function public.passer_arret(p_trajet uuid, p_arret uuid, p_le timestamptz default null)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.trajets_transport;
  a public.arrets_transport;
  v_suivant public.arrets_transport;
  v_quand timestamptz := least(coalesce(p_le, now()), now());
  v_tz text;
  e record;
begin
  select * into t from public.trajets_transport where id = p_trajet;
  if not found or not public.conduit_circuit(t.circuit_id) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  select * into a from public.arrets_transport where id = p_arret and circuit_id = t.circuit_id;
  if not found then raise exception 'ARRET_INCONNU' using errcode = '23514'; end if;
  insert into public.passages_arrets (trajet_id, arret_id, passe_le) values (p_trajet, p_arret, v_quand)
  on conflict do nothing;
  if not found then return; end if;  -- déjà signalé (renvoi)
  update public.trajets_transport set dernier_arret_ordre = a.ordre, dernier_arret_le = v_quand
   where id = p_trajet and (dernier_arret_le is null or dernier_arret_le <= v_quand);
  if t.termine_le is not null then return; end if;

  select * into v_suivant from public.arrets_transport
  where circuit_id = t.circuit_id and actif
    and case when t.sens = 'aller' then ordre > a.ordre else ordre < a.ordre end
  order by case when t.sens = 'aller' then ordre else -ordre end
  limit 1;
  if v_suivant.id is null then return; end if;
  v_tz := public.fuseau_etablissement(t.etablissement_id);
  for e in select f.id, f.prenom from public.affectations_transport af
           join public.annees_scolaires an on an.id = af.annee_scolaire_id and an.courante
           join public.fiches_eleves f on f.id = af.fiche_eleve_id
           where af.arret_id = v_suivant.id loop
    perform public.aviser_familles_transport(t.etablissement_id, e.id, 'transport_approche',
      format('Le bus vient de passer « %s » (%s) : il arrive bientôt à l''arrêt « %s ».',
             a.nom, to_char(v_quand at time zone v_tz, 'HH24"h"MI'), v_suivant.nom),
      v_quand, jsonb_build_object('fiche_eleve_id', e.id, 'trajet_id', p_trajet, 'arret_id', v_suivant.id));
  end loop;
end;
$$;

-- Montée ou descente : carte QR de l'élève scannée par le chauffeur.
create or replace function public.enregistrer_montee(p_id uuid, p_trajet uuid, p_jeton text, p_evenement text,
                                                     p_arret uuid default null, p_scanne_le timestamptz default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.trajets_transport;
  f record;
  v_quand timestamptz := least(coalesce(p_scanne_le, now()), now());
  v_arret text;
  v_tz text;
  v_affecte boolean;
begin
  select * into t from public.trajets_transport where id = p_trajet;
  if not found or not public.conduit_circuit(t.circuit_id) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if p_evenement not in ('montee', 'descente') then raise exception 'EVENEMENT_INVALIDE' using errcode = '22023'; end if;

  select fe.id, fe.prenom, fe.nom into f
  from public.cartes_eleves k join public.fiches_eleves fe on fe.id = k.fiche_eleve_id
  where k.jeton = p_jeton and k.etablissement_id = t.etablissement_id and fe.deleted_at is null;
  if f.id is null then return jsonb_build_object('statut', 'carte_inconnue'); end if;

  if exists (select 1 from public.montees_transport where id = p_id) then
    return jsonb_build_object('statut', 'deja_recu', 'fiche_eleve_id', f.id, 'prenom', f.prenom, 'nom', f.nom);
  end if;
  insert into public.montees_transport (id, trajet_id, fiche_eleve_id, evenement, arret_id, scanne_le)
  values (p_id, p_trajet, f.id, p_evenement, p_arret, v_quand);

  v_affecte := exists (select 1 from public.affectations_transport af join public.annees_scolaires an
                       on an.id = af.annee_scolaire_id and an.courante
                       where af.fiche_eleve_id = f.id and af.circuit_id = t.circuit_id);
  select nom into v_arret from public.arrets_transport where id = p_arret;
  v_tz := public.fuseau_etablissement(t.etablissement_id);
  perform public.aviser_familles_transport(t.etablissement_id, f.id,
    case when p_evenement = 'montee' then 'transport_montee' else 'transport_descente' end,
    format('%s est %s le bus à %s%s.', f.prenom,
           case when p_evenement = 'montee' then 'monté(e) dans' else 'descendu(e) du' end,
           to_char(v_quand at time zone v_tz, 'HH24"h"MI'),
           coalesce(' (arrêt « ' || v_arret || ' »)', '')),
    v_quand, jsonb_build_object('fiche_eleve_id', f.id, 'trajet_id', p_trajet));
  return jsonb_build_object('statut', 'enregistre', 'fiche_eleve_id', f.id, 'prenom', f.prenom, 'nom', f.nom,
                            'hors_circuit', not v_affecte, 'a_bord', public.nombre_a_bord(p_trajet));
end;
$$;

-- Fin de trajet : position effacée ; enfants encore à bord rendus au
-- chauffeur et signalés à la direction.
create or replace function public.terminer_trajet(p_trajet uuid, p_termine_le timestamptz default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.trajets_transport;
  v_restes jsonb;
  v_n integer;
  v_circuit text;
  d uuid;
begin
  select * into t from public.trajets_transport where id = p_trajet for update;
  if not found or not public.conduit_circuit(t.circuit_id) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('fiche_eleve_id', f.id, 'prenom', f.prenom, 'nom', f.nom) order by f.nom), '[]'::jsonb),
         count(*)
    into v_restes, v_n
  from public.eleves_a_bord(p_trajet) b join public.fiches_eleves f on f.id = b.fiche_eleve_id;
  if t.termine_le is null then
    update public.trajets_transport
       set termine_le = least(coalesce(p_termine_le, now()), now()), latitude = null, longitude = null, restes_a_bord = v_n
     where id = p_trajet;
    if v_n > 0 then
      select nom into v_circuit from public.circuits_transport where id = t.circuit_id;
      for d in select x from public.directions_etablissement(t.etablissement_id) x loop
        perform public.notifier_push(t.etablissement_id, d, 'transport_a_bord',
          format('Fin du trajet « %s » : %s élève(s) toujours enregistré(s) à bord. Vérifiez le véhicule.', v_circuit, v_n),
          jsonb_build_object('trajet_id', p_trajet));
      end loop;
    end if;
  end if;
  return jsonb_build_object('restes_a_bord', v_restes);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Suivi par la famille (24.2, 24.3)
-- ---------------------------------------------------------------------------
create or replace function public.suivi_transport_enfant(p_fiche uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  af public.affectations_transport;
  c public.circuits_transport;
  t public.trajets_transport;
  v_tz text;
begin
  if not (coalesce(public.fiche_visible(p_fiche), false)
          or exists (select 1 from public.fiches_eleves f where f.id = p_fiche and public.gere_transport(f.etablissement_id))) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  select a.* into af from public.affectations_transport a
  join public.annees_scolaires an on an.id = a.annee_scolaire_id and an.courante
  where a.fiche_eleve_id = p_fiche;
  if not found then return jsonb_build_object('affecte', false); end if;
  select * into c from public.circuits_transport where id = af.circuit_id;
  select * into t from public.trajets_transport where circuit_id = c.id and termine_le is null;
  v_tz := public.fuseau_etablissement(c.etablissement_id);
  return jsonb_build_object(
    'affecte', true,
    'circuit', jsonb_build_object('id', c.id, 'nom', c.nom, 'vehicule', c.vehicule, 'telephone_chauffeur', c.telephone_chauffeur,
                                  'tarif_annuel', c.tarif_annuel),
    'arret_id', af.arret_id,
    'arrets', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'ordre', a.ordre, 'nom', a.nom, 'repere', a.repere,
        'heure_matin', to_char(a.heure_matin, 'HH24:MI'), 'heure_soir', to_char(a.heure_soir, 'HH24:MI'),
        'latitude', a.latitude, 'longitude', a.longitude) order by a.ordre)
      from public.arrets_transport a where a.circuit_id = c.id and a.actif), '[]'::jsonb),
    -- Position seulement pendant un trajet en cours (règle 24.3).
    'trajet_en_cours', case when t.id is null then null else jsonb_build_object(
        'sens', t.sens, 'demarre_le', t.demarre_le, 'latitude', t.latitude, 'longitude', t.longitude,
        'position_le', t.position_le, 'dernier_arret_ordre', t.dernier_arret_ordre, 'dernier_arret_le', t.dernier_arret_le,
        'a_bord', exists (select 1 from public.eleves_a_bord(t.id) b where b.fiche_eleve_id = p_fiche)) end,
    'aujourd_hui', coalesce((select jsonb_agg(jsonb_build_object('evenement', m.evenement, 'scanne_le', m.scanne_le,
                                  'arret', (select nom from public.arrets_transport where id = m.arret_id)) order by m.scanne_le)
      from public.montees_transport m join public.trajets_transport tt on tt.id = m.trajet_id
      where m.fiche_eleve_id = p_fiche and (m.scanne_le at time zone v_tz)::date = (now() at time zone v_tz)::date), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Droits d'exécution
-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'public.enregistrer_circuit_transport(uuid, uuid, text, text, integer, numeric, text, boolean)',
    'public.enregistrer_arrets_transport(uuid, jsonb)',
    'public.affecter_eleve_transport(uuid, uuid, uuid)',
    'public.retirer_affectation_transport(uuid)',
    'public.transport_etablissement(uuid)',
    'public.rechercher_eleves_transport(uuid, text)',
    'public.mes_circuits_chauffeur()',
    'public.demarrer_trajet(uuid, uuid, text, timestamptz)',
    'public.signaler_position_trajet(uuid, double precision, double precision, timestamptz)',
    'public.passer_arret(uuid, uuid, timestamptz)',
    'public.enregistrer_montee(uuid, uuid, text, text, uuid, timestamptz)',
    'public.terminer_trajet(uuid, timestamptz)',
    'public.suivi_transport_enfant(uuid)',
    'public.gere_transport(uuid)',
    'public.conduit_circuit(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

revoke all on function public.aviser_familles_transport(uuid, uuid, text, text, timestamptz, jsonb) from public, anon, authenticated;
revoke all on function public.eleves_a_bord(uuid) from public, anon, authenticated;
revoke all on function public.nombre_a_bord(uuid) from public, anon, authenticated;
