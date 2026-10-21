-- ============================================================================
-- EcoShop — Encaissement de scolarité au guichet, d'abord hors connexion
--
-- Le geste quotidien du guichet (espèces) ne doit jamais attendre le réseau :
--   • l'encaissement saisi sans réseau porte la clé générée par l'appareil
--     (id), un numéro de reçu PROVISOIRE (PROV-<appareil>-0001) et l'heure
--     de saisie ; il est envoyé au retour du réseau, sans jamais créer de
--     doublon (même id : rien de nouveau) ;
--   • chaque encaissement reçoit désormais un NUMÉRO DE REÇU continu et sans
--     trou, par établissement et par année (SCO-2026-000001), attribué par
--     le serveur dans la transaction d'enregistrement (aucun numéro perdu si
--     elle échoue) ; le reçu définitif rappelle le provisoire ;
--   • les encaissements déjà enregistrés reçoivent leur numéro dans l'ordre
--     de saisie.
--
-- Migration idempotente.
-- ============================================================================

alter table public.encaissements_scolarite
  add column if not exists numero_recu text,
  add column if not exists numero_provisoire text,
  add column if not exists saisi_le_client timestamptz;

create table if not exists public.compteurs_recus_scolarite (
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee integer not null,
  dernier integer not null default 0,
  primary key (etablissement_id, annee)
);
alter table public.compteurs_recus_scolarite enable row level security;
revoke all on public.compteurs_recus_scolarite from anon, authenticated;

create or replace function public.prochain_numero_recu_scolarite(p_etablissement uuid, p_annee integer)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_n integer;
begin
  insert into public.compteurs_recus_scolarite (etablissement_id, annee, dernier)
  values (p_etablissement, p_annee, 1)
  on conflict (etablissement_id, annee) do update set dernier = public.compteurs_recus_scolarite.dernier + 1
  returning dernier into v_n;
  return 'SCO-' || p_annee || '-' || lpad(v_n::text, 6, '0');
end;
$$;

-- Numéro attribué à l'enregistrement, jamais choisi par le client ; l'heure
-- de saisie ne peut pas être dans le futur.
create or replace function public.encaissements_numeroter()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.numero_recu := public.prochain_numero_recu_scolarite(
    new.etablissement_id, extract(year from coalesce(new.date_paiement, current_date))::int);
  if new.saisi_le_client is not null and new.saisi_le_client > now() + interval '5 minutes' then
    new.saisi_le_client := now();
  end if;
  return new;
end;
$$;

drop trigger if exists encaissements_numeroter_trg on public.encaissements_scolarite;
create trigger encaissements_numeroter_trg
  before insert on public.encaissements_scolarite
  for each row execute procedure public.encaissements_numeroter();

-- Le numéro et le provisoire font partie de la piste d'audit : immuables.
create or replace function public.encaissements_numero_immuable()
returns trigger
language plpgsql set search_path = public
as $$
begin
  if new.numero_recu is distinct from old.numero_recu
     or new.numero_provisoire is distinct from old.numero_provisoire
     or new.saisi_le_client is distinct from old.saisi_le_client then
    raise exception 'ENCAISSEMENT_CHAMP_IMMUABLE' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists encaissements_numero_immuable_trg on public.encaissements_scolarite;
create trigger encaissements_numero_immuable_trg
  before update on public.encaissements_scolarite
  for each row execute procedure public.encaissements_numero_immuable();

-- Numérotation des encaissements existants, dans l'ordre de saisie.
do $$
declare
  r record;
begin
  alter table public.encaissements_scolarite disable trigger encaissements_numero_immuable_trg;
  alter table public.encaissements_scolarite disable trigger encaissements_verifie_immuable_trg;
  for r in
    select id, etablissement_id, date_paiement from public.encaissements_scolarite
    where numero_recu is null order by created_at, id
  loop
    update public.encaissements_scolarite
       set numero_recu = public.prochain_numero_recu_scolarite(r.etablissement_id, extract(year from r.date_paiement)::int)
     where id = r.id;
  end loop;
  alter table public.encaissements_scolarite enable trigger encaissements_verifie_immuable_trg;
  alter table public.encaissements_scolarite enable trigger encaissements_numero_immuable_trg;
end $$;

create unique index if not exists encaissements_numero_recu_unique
  on public.encaissements_scolarite (etablissement_id, numero_recu);

-- Enregistrement idempotent (guichet, en ligne ou rejoué depuis la file).
-- Le renvoi d'un encaissement déjà reçu ne touche à rien (et ne consomme
-- aucun numéro : on vérifie AVANT d'insérer). Droits : ceux de l'appelant
-- (RLS d'insertion, auteur imposé par le déclencheur existant).
create or replace function public.enregistrer_encaissement_scolarite(
  p_id uuid,
  p_etablissement uuid,
  p_fiche_eleve uuid,
  p_inscription uuid,
  p_type_frais public.type_frais_scolaire,
  p_montant numeric,
  p_moyen public.moyen_paiement,
  p_reference text,
  p_date date,
  p_numero_provisoire text default null,
  p_saisi_le timestamptz default null
)
returns jsonb
language plpgsql volatile security invoker set search_path = public
as $$
declare
  v_ligne public.encaissements_scolarite;
begin
  select * into v_ligne from public.encaissements_scolarite where id = p_id;
  if v_ligne.id is not null then
    if v_ligne.etablissement_id <> p_etablissement then
      raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
    end if;
    return to_jsonb(v_ligne) || jsonb_build_object('deja_recu', true);
  end if;

  insert into public.encaissements_scolarite (id, etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant,
                                             moyen_paiement, reference_paiement, date_paiement, numero_provisoire,
                                             saisi_le_client, saisi_par)
  values (p_id, p_etablissement, p_fiche_eleve, p_inscription, p_type_frais, p_montant, p_moyen,
          nullif(trim(p_reference), ''), coalesce(p_date, current_date), p_numero_provisoire, p_saisi_le, auth.uid())
  returning * into v_ligne;
  return to_jsonb(v_ligne) || jsonb_build_object('deja_recu', false);
end;
$$;

revoke all on function public.enregistrer_encaissement_scolarite(uuid, uuid, uuid, uuid, public.type_frais_scolaire, numeric,
  public.moyen_paiement, text, date, text, timestamptz) from public, anon;
grant execute on function public.enregistrer_encaissement_scolarite(uuid, uuid, uuid, uuid, public.type_frais_scolaire, numeric,
  public.moyen_paiement, text, date, text, timestamptz) to authenticated;

revoke all on function public.prochain_numero_recu_scolarite(uuid, integer) from public, anon, authenticated;
revoke all on function public.encaissements_numeroter() from public, anon, authenticated;
