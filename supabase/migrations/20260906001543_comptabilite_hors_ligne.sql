-- ============================================================================
-- EcoShop — REG-03, lot C7 : la comptabilité d'abord hors connexion
--
-- Côté serveur, deux garanties pour les saisies faites sans réseau puis
-- rejouées au retour de la connexion (bonne pratique des caisses hors
-- ligne : clé unique générée par l'appareil, dédoublonnage au serveur) :
--   • dons : `enregistrer_don` accepte l'identifiant fourni par l'appareil
--     (p_id) ; un second envoi renvoie le reçu déjà attribué au lieu d'en
--     créer un autre. Le numéro provisoire imprimé hors connexion
--     (PROV-…) est conservé à côté du numéro définitif, sans trou, attribué
--     à la réception ;
--   • pièces : `enregistrer_piece_hors_ligne` crée ou met à jour un
--     brouillard sous l'identifiant de l'appareil ; une pièce déjà validée
--     n'est jamais touchée. La validation (qui numérote) reste en ligne.
--
-- Migration idempotente.
-- ============================================================================

alter table public.dons add column if not exists numero_provisoire text
  check (numero_provisoire is null or char_length(numero_provisoire) <= 40);
alter table public.dons add column if not exists saisi_le_client timestamptz;

-- La nouvelle signature remplace l'ancienne (paramètres ajoutés en fin).
drop function if exists public.enregistrer_don(uuid, numeric, text, text, date, uuid, uuid, uuid, text, text, boolean);

create or replace function public.enregistrer_don(
  p_etablissement uuid,
  p_montant numeric,
  p_nature text default 'don',
  p_moyen text default 'especes',
  p_date date default current_date,
  p_donateur_id uuid default null,
  p_affectation_id uuid default null,
  p_fiche_eleve_id uuid default null,
  p_reference text default null,
  p_commentaire text default null,
  p_anonyme boolean default false,
  p_id uuid default null,
  p_numero_provisoire text default null,
  p_saisi_le timestamptz default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_annee integer := extract(year from coalesce(p_date, current_date))::int;
  v_numero integer;
  v_id uuid;
  v_recu text;
  a public.affectations_dons;
begin
  if not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  -- Rejeu d'une saisie hors connexion : la clé fournie par l'appareil rend
  -- l'envoi idempotent (jamais deux reçus pour un même don).
  if p_id is not null and exists (select 1 from public.dons where id = p_id) then
    if not exists (select 1 from public.dons where id = p_id and etablissement_id = p_etablissement) then
      raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
    end if;
    return (select jsonb_build_object(
              'id', d.id, 'numero_recu', d.numero_recu, 'numero_provisoire', d.numero_provisoire, 'deja_recu', true,
              'comptabilise', exists (select 1 from public.pieces_comptables
                                       where source_type = 'don' and source_id = d.id and origine = 'automatique'),
              'incident', (select code from public.incidents_comptabilisation
                            where source_type = 'don' and source_id = d.id and not resolu limit 1))
              from public.dons d where d.id = p_id);
  end if;
  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;
  if p_nature is null or p_nature not in ('don', 'legs', 'denier_culte', 'quete', 'mecenat', 'parrainage', 'autre') then
    raise exception 'NATURE_INVALIDE' using errcode = '22023';
  end if;
  if p_date is null or p_date > current_date then
    raise exception 'DATE_DON_FUTURE' using errcode = '22023';
  end if;
  if p_donateur_id is not null and not exists (
       select 1 from public.donateurs where id = p_donateur_id and etablissement_id = p_etablissement and deleted_at is null) then
    raise exception 'DONATEUR_INCONNU' using errcode = '22023';
  end if;
  if p_affectation_id is not null then
    select * into a from public.affectations_dons where id = p_affectation_id and etablissement_id = p_etablissement;
    if a.id is null then
      raise exception 'AFFECTATION_INCONNUE' using errcode = '22023';
    end if;
    if not a.active then
      raise exception 'AFFECTATION_CLOSE' using errcode = '22023';
    end if;
  end if;
  if p_fiche_eleve_id is not null and not exists (
       select 1 from public.fiches_eleves where id = p_fiche_eleve_id and etablissement_id = p_etablissement) then
    raise exception 'ELEVE_INCONNU' using errcode = '22023';
  end if;

  -- Numéro de reçu continu par établissement et par année.
  insert into public.compteurs_recus_dons (etablissement_id, annee, dernier)
  values (p_etablissement, v_annee, 1)
  on conflict (etablissement_id, annee) do update set dernier = compteurs_recus_dons.dernier + 1
  returning dernier into v_numero;
  v_recu := 'REC-' || v_annee || '-' || lpad(v_numero::text, 6, '0');

  insert into public.dons
    (id, etablissement_id, numero_recu, donateur_id, nature, moyen_paiement, montant, date_don, affectation_id,
     fiche_eleve_id, reference_paiement, commentaire, anonyme, saisi_par, numero_provisoire, saisi_le_client)
  values (coalesce(p_id, gen_random_uuid()), p_etablissement, v_recu, p_donateur_id, p_nature, p_moyen::public.moyen_paiement,
          round(p_montant, 2), p_date, p_affectation_id, p_fiche_eleve_id, nullif(trim(p_reference), ''),
          nullif(trim(p_commentaire), ''), coalesce(p_anonyme, false), auth.uid(),
          nullif(trim(p_numero_provisoire), ''), p_saisi_le)
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'numero_recu', v_recu,
    'numero_provisoire', nullif(trim(p_numero_provisoire), ''),
    'deja_recu', false,
    'comptabilise', exists (select 1 from public.pieces_comptables
                             where source_type = 'don' and source_id = v_id and origine = 'automatique'),
    'incident', (select code from public.incidents_comptabilisation
                  where source_type = 'don' and source_id = v_id and not resolu limit 1));
exception
  when invalid_text_representation then
    raise exception 'MOYEN_INVALIDE' using errcode = '22023';
end;
$$;


-- Le reçu définitif rappelle le numéro provisoire qu'il remplace.
create or replace function public.recu_don(p_don_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d public.dons;
begin
  select * into d from public.dons where id = p_don_id;
  if d.id is null or not coalesce(public.est_comptable(d.etablissement_id), false) then
    raise exception 'COMPTABLE_REQUIS' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'id', d.id,
    'numero_recu', d.numero_recu,
    'numero_provisoire', d.numero_provisoire,
    'date_don', d.date_don,
    'montant', d.montant,
    'nature', d.nature,
    'moyen_paiement', d.moyen_paiement,
    'reference_paiement', d.reference_paiement,
    'statut', d.statut,
    'motif_annulation', d.motif_annulation,
    'anonyme', d.anonyme,
    'affectation', (select a.libelle from public.affectations_dons a where a.id = d.affectation_id),
    'eleve', (select nullif(trim(f.prenom || ' ' || f.nom), '') from public.fiches_eleves f where f.id = d.fiche_eleve_id),
    'donateur', (select jsonb_build_object('nom', o.nom, 'prenom', o.prenom, 'type', o.type, 'adresse', o.adresse,
                                           'telephone', o.telephone, 'email', o.email)
                   from public.donateurs o where o.id = d.donateur_id),
    'saisi_par', (select nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), '')
                    from public.profiles p where p.id = d.saisi_par));
end;
$$;

-- Brouillard créé ou mis à jour sous l'identifiant fourni par l'appareil.
create or replace function public.enregistrer_piece_hors_ligne(
  p_id uuid,
  p_etablissement uuid,
  p_journal uuid,
  p_date date,
  p_libelle text,
  p_lignes jsonb,
  p_piece_justificative text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  p public.pieces_comptables;
  x public.exercices_comptables;
begin
  if not coalesce(public.est_comptable_ecriture(p_etablissement), false) then
    raise exception 'COMPTABLE_ECRITURE_REQUIS' using errcode = '42501';
  end if;
  if p_id is null then
    raise exception 'CLE_REQUISE' using errcode = '22023';
  end if;
  select * into p from public.pieces_comptables where id = p_id;
  if p.id is not null and p.etablissement_id <> p_etablissement then
    raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
  end if;
  -- Déjà validée (envoyée puis validée en ligne) : rien à refaire.
  if p.id is not null and p.statut = 'validee' then
    return jsonb_build_object('id', p.id, 'statut', 'validee', 'reference', p.reference, 'deja_validee', true);
  end if;
  if p.id is null then
    x := public.exercice_ouvert_pour(p_etablissement, p_date);
    if x.id is null then
      raise exception 'AUCUN_EXERCICE_OUVERT' using errcode = '55000';
    end if;
    insert into public.pieces_comptables (id, etablissement_id, exercice_id, journal_id, date_piece, libelle, cree_par)
    values (p_id, p_etablissement, x.id, p_journal, p_date, coalesce(nullif(trim(p_libelle), ''), '—'), auth.uid());
  end if;
  perform public.enregistrer_piece(p_etablissement, p_journal, p_date, p_libelle, p_lignes, p_piece_justificative, p_id);
  return jsonb_build_object('id', p_id, 'statut', 'brouillard', 'deja_validee', false);
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.enregistrer_don(uuid, numeric, text, text, date, uuid, uuid, uuid, text, text, boolean, uuid, text, timestamptz)',
    'public.enregistrer_piece_hors_ligne(uuid, uuid, uuid, date, text, jsonb, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;
