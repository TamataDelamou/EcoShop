-- ============================================================================
-- EcoShop — D6 — Perception des frais par classe & fast-track d'inscription
--
-- Périmètre (cadrage porteur de projet, dernier module de la Phase D) :
--
--   1. Perception par classe (cahier ch.17 — silence du cahier sur ce point
--      précis, ce n'est PAS un rattrapage d'écart : vérifié aussi absent du
--      prototype source `ecoshop_flutter`, cf. rapport d'écart). Nouvel
--      écran de CONSULTATION, accessible depuis EcranDetailClasse comme le
--      bouton Bulletins de D5 : liste des élèves de la classe avec leur
--      solde. Aucune nouvelle RPC de liste n'est nécessaire côté classe —
--      `inscriptions_de_classe` (déjà exposée) et `solde_scolarite` par
--      inscription (déjà exposée, M15quater) suffisent ; la seule chose que
--      cette migration touche pour ce point est le CORRECTIF ci-dessous.
--      Périmètre volontairement limité à la consultation + navigation vers
--      l'encaissement individuel existant, jamais une saisie groupée
--      (décision explicite : une saisie financière groupée est plus risquée
--      qu'une génération de document groupée, et rien ne la demande).
--
--   2. Fast-track d'inscription (cahier §7.1, vrai écart cahier celui-là) :
--      recherche d'un ou plusieurs enfants par le numéro de téléphone du
--      PARENT, avec sélection RÉELLE quand plusieurs enfants partagent ce
--      numéro. Le prototype source lui-même ne résolvait jamais ce cas
--      (`eleves.first`, TODO explicite jamais levé) ; corrigé ici plutôt que
--      reproduit. La recherche par matricule existante reste une option
--      secondaire, sans régression pour ceux qui l'utilisent déjà. Une fois
--      l'enfant identifié, le flux de réinscription (alertes + choix de
--      classe + `creer_reinscription`) reste strictement inchangé.
--
-- Correctif de sécurité trouvé EN CONSTRUISANT le point 1 (pas une dérive de
-- périmètre : `solde_scolarite` est la fonction que ce module s'apprête à
-- exposer pour la première fois à l'échelle d'une classe ENTIÈRE, donc à
-- creuser avant de l'exploiter plus largement — même discipline qu'en D5
-- avec `a_permission` NULL non bloquant) :
--
--   `solde_scolarite(p_inscription_id)` (M15quater, 20260906001501) n'avait
--   AUCUNE vérification d'autorisation malgré `security definer` : tout
--   compte authentifié pouvait lire le solde de N'IMPORTE QUELLE inscription
--   de N'IMPORTE QUEL établissement en connaissant seulement son UUID — une
--   fuite financière inter-établissements, jamais détectée jusqu'ici faute
--   d'appelant qui l'exerçait au-delà d'un seul enfant déjà visible à
--   l'écran (`EcranEncaissementScolarite`, ouvert depuis une fiche déjà
--   filtrée par `fiche_visible`). Corrigé en appliquant EXACTEMENT la même
--   frontière que la policy SELECT de `encaissements_scolarite`
--   (`est_personnel(etablissement_id) or fiche_visible(fiche_eleve_id)`,
--   20260906001502) — pas une nouvelle règle inventée, la même déjà
--   retenue pour la même donnée sur la table adjacente.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Correctif — solde_scolarite exigeait déjà un id précis pour être
-- appelée ; elle n'en vérifiait jamais le droit d'accès. Conversion en
-- plpgsql (nécessaire pour le contrôle de flux), calcul inchangé.
-- ---------------------------------------------------------------------------
create or replace function public.solde_scolarite(p_inscription_id uuid)
returns table(montant_du numeric, montant_paye numeric, solde numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_etablissement uuid;
  v_fiche uuid;
begin
  select i.etablissement_id, i.fiche_eleve_id
    into v_etablissement, v_fiche
  from public.inscriptions i
  where i.id = p_inscription_id;

  if v_etablissement is null then
    raise exception 'INSCRIPTION_INTROUVABLE' using errcode = '23514';
  end if;

  if not coalesce(public.est_personnel(v_etablissement), false)
     and not coalesce(public.fiche_visible(v_fiche), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return query
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
end;
$$;

grant execute on function public.solde_scolarite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Fast-track d'inscription — recherche par téléphone du parent (§7.1),
-- fratrie complète renvoyée (jamais un seul enfant pris arbitrairement, à la
-- différence du prototype source). Même frontière d'autorisation que
-- `creer_reinscription`/l'écriture d'inscription : gestion de la scolarité,
-- ou direction.
-- ---------------------------------------------------------------------------
create or replace function public.rechercher_enfants_par_telephone_parent(
  p_etablissement uuid,
  p_telephone text
)
returns setof public.fiches_eleves
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_parent_profile uuid;
begin
  if not coalesce(public.a_permission(p_etablissement, 'scolarite.inscription.gerer'), false)
     and not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  -- Le numéro doit déjà être normalisé E.164 par l'appelant (même règle que
  -- l'OTP, ch. 5.4.1) : un format invalide ne correspond simplement à aucun
  -- identifiant stocké et renvoie un ensemble vide, pas une erreur.
  select ic.profile_id into v_parent_profile
  from public.identifiants_comptes ic
  where ic.type_identifiant = 'telephone' and ic.valeur = trim(p_telephone);

  if v_parent_profile is null then
    return;
  end if;

  return query
  select f.*
  from public.fiches_eleves f
  join public.relations_parent_eleve r on r.fiche_eleve_id = f.id
  where r.parent_profile_id = v_parent_profile
    and r.etablissement_id = p_etablissement
    and r.statut = 'confirmee'
    and r.autorise
    and r.deleted_at is null
    and f.deleted_at is null
  order by f.nom, f.prenom;
end;
$$;

grant execute on function public.rechercher_enfants_par_telephone_parent(uuid, text) to authenticated;
