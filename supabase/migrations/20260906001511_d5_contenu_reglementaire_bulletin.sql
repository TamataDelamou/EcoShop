-- ============================================================================
-- EcoShop — D5 — Complément de contenu réglementaire du bulletin
--
-- Exigences spécifiées par le porteur de projet, absentes de la version
-- initiale de D5 (f8968e1) : pays + Ministère de tutelle en en-tête,
-- tableau par matière (secondaire uniquement), mention "non duplicata",
-- bloc signatures par cycle.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Ministère de tutelle + libellés de signature — au même emplacement que
-- le reste du référentiel pays (chapitre 6), ajustables par pays, pas par
-- établissement dans cette passe. Nullable / valeur par défaut résiliente :
-- une donnée manquante ne bloque jamais le rendu du document (même principe
-- que les champs de fusion du chapitre 18, différé mais réutilisé ici).
-- `ministere_tutelle` est une donnée neuve, distincte de
-- `organisme_examinateur` (organisme certificateur d'un examen, pas
-- l'autorité de tutelle administrative) — laissée NULL tant qu'une source
-- ministérielle fiable n'a pas été intégrée (pas de valeur inventée ici).
-- ---------------------------------------------------------------------------
alter table public.pays_pedagogiques
  add column if not exists ministere_tutelle text,
  add column if not exists signatures_bulletin jsonb not null default jsonb_build_object(
    'primaire', jsonb_build_object('signataire1', 'Directeur', 'signataire2', 'Maître de classe'),
    'college',  jsonb_build_object('signataire1', 'Proviseur', 'signataire2', 'Directeur des Études'),
    'lycee',    jsonb_build_object('signataire1', 'Proviseur', 'signataire2', 'Censeur')
  );

-- ---------------------------------------------------------------------------
-- 2. Téléphone ET email de l'employé (dette tracée depuis D2) — deux usages
-- distincts, pas interchangeables : le téléphone sert aux responsables
-- scolaires en interne (contact direct), jamais imprimé sur un document
-- distribué aux familles ; l'email est ce qui apparaît sur le bulletin
-- (tableau par matière, nom + email du professeur) — décision explicite du
-- porteur de projet, qui écarte la question de confidentialité que la
-- diffusion d'un numéro de téléphone à toute une classe aurait posée.
-- ---------------------------------------------------------------------------
alter table public.employes
  add column if not exists telephone text,
  add column if not exists email text;

-- ---------------------------------------------------------------------------
-- 3. Classification de cycle d'une classe — clé technique correcte pour
-- distinguer primaire/collège/lycée : le NIVEAU ISCED normalisé
-- (niveaux_educatifs.isced, 1/2/3), PAS le code du cycle
-- (cycles_educatifs.code), qui varie par pays (« college »/« moyen »/
-- « junior_high » désignent tous le même palier ISCED 2 — voir 6.4 du
-- cahier). Réservée au personnel de l'établissement de la classe.
-- Renvoie NULL si la classe n'a pas de niveau renseigné (dette pré-existante
-- : `classes.niveau_id` est nullable) ou si l'appelant n'est pas personnel —
-- les deux cas doivent se traduire par « pas de tableau par matière », un
-- appelant du tableau n'a pas à distinguer les deux causes.
-- ---------------------------------------------------------------------------
create or replace function public.classe_isced(p_classe uuid)
returns int
language sql stable security definer set search_path = public
as $$
  select n.isced
  from public.classes c
  left join public.niveaux_educatifs n on n.id = c.niveau_id
  where c.id = p_classe
    and coalesce(public.est_personnel(c.etablissement_id), false);
$$;

grant execute on function public.classe_isced(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Détail du bulletin par matière (secondaire uniquement — ISCED >= 2,
-- collège + lycée ; le primaire a un maître de classe unique, déjà couvert
-- par le bloc signatures) : matière, coefficient officiel du programme
-- (`programmes_matieres.coefficient`, distinct du coefficient par évaluation
-- utilisé par `calculer_moyenne_eleve`), moyenne de l'élève sur CETTE
-- matière (délègue à `calculer_moyenne_eleve`, déjà éprouvée — aucun
-- nouveau calcul de moyenne), nom et email de l'enseignant affecté (jamais
-- le téléphone — voir §2 : usage interne uniquement, non imprimé).
--
-- Silencieux plutôt que bloquant : classe sans niveau renseigné, cycle
-- primaire, ou appelant non personnel renvoient tous un ensemble vide (pas
-- d'erreur) — cohérent avec `classe_isced`.
-- ---------------------------------------------------------------------------
create or replace function public.detail_bulletin_matieres(
  p_fiche uuid,
  p_classe uuid,
  p_periode uuid default null
)
returns table(
  matiere text,
  coefficient int,
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

-- ============================================================================
-- Fin D5 — complément de contenu réglementaire du bulletin.
-- ============================================================================
