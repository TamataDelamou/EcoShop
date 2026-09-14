-- ============================================================================
-- EcoShop — Correctif : classer_eleves_classe() peut faire échouer
-- injustement un appelant légitime (régression audit RPC, migration
-- 20260906001513).
--
-- Root cause, établie empiriquement (EXPLAIN + injection de diagnostics
-- temporaires, jamais par simple lecture de code) :
--
-- classer_eleves_classe() (D5, migration 20260906001510) joint
-- classes -> inscriptions -> fiches_eleves puis appelle
-- calculer_moyenne_eleve(f.id, ...) via un CROSS JOIN LATERAL, le filtre
-- `where c.id = p_classe` étant appliqué comme n'importe quel autre
-- prédicat de la clause WHERE -- PAS garanti d'être évalué AVANT le LATERAL.
-- Sur une table fiches_eleves de petite taille, le planificateur choisit un
-- Seq Scan complet de fiches_eleves (vérifié par EXPLAIN) et n'applique le
-- rapprochement avec la classe demandée qu'ENSUITE (Join Filter au niveau
-- du Nested Loop englobant) -- ce qui expose calculer_moyenne_eleve à TOUTE
-- fiche de la base, de N'IMPORTE QUEL autre établissement, avant même de
-- savoir si elle appartient à la classe demandée.
--
-- Avant l'audit RPC, calculer_moyenne_eleve() n'avait AUCUNE vérification de
-- permission : cette exposition était inoffensive (un calcul silencieux,
-- jeté ensuite par le filtre externe). Depuis l'audit (1513),
-- calculer_moyenne_eleve() lève PERMISSION_REFUSEE pour toute fiche hors du
-- périmètre de l'appelant -- la première fiche d'un AUTRE établissement
-- rencontrée par le Seq Scan fait donc échouer TOUTE la requête, y compris
-- pour un appelant parfaitement légitime sur SA PROPRE classe. Confirmé :
-- le comportement dépend du plan choisi par le planificateur (donc de la
-- taille des tables), pas de la légitimité de l'appelant -- un bug latent
-- de portée de requête, pas un problème d'autorisation.
--
-- Correctif : un CTE MATERIALIZED force Postgres à résoudre et filtrer
-- classes/inscriptions/fiches_eleves (dont le garde-fou est_personnel)
-- AVANT toute évaluation du LATERAL, quel que soit le plan choisi par
-- ailleurs -- une garantie structurelle, pas un espoir d'optimisation.
--
-- Portée : generer_bulletins_classe() délègue entièrement à
-- classer_eleves_classe(), donc ce seul correctif couvre aussi la
-- génération de bulletins. detail_bulletin_matieres() (migration
-- 20260906001511) vérifié à part : appelle calculer_moyenne_eleve() sur un
-- p_fiche scalaire fourni par l'appelant, jamais dérivé d'un balayage non
-- filtré -- pas la même classe de bug, non touché ici.
-- ============================================================================

create or replace function public.classer_eleves_classe(
  p_classe uuid,
  p_matiere uuid default null,
  p_periode uuid default null
)
returns table(fiche_eleve_id uuid, moyenne numeric, rang int)
language sql stable security definer set search_path = public
as $$
  with fiches_de_la_classe as materialized (
    select f.id as fiche_eleve_id
    from public.classes c
    join public.inscriptions i on i.classe_id = c.id and i.deleted_at is null and i.statut = 'active'
    join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
    where c.id = p_classe
      and public.est_personnel(c.etablissement_id)
  )
  select fc.fiche_eleve_id,
         m.moyenne,
         rank() over (order by m.moyenne desc)::int as rang
  from fiches_de_la_classe fc
  cross join lateral (
    select public.calculer_moyenne_eleve(fc.fiche_eleve_id, p_matiere, p_periode) as moyenne
  ) m
  where m.moyenne is not null
  order by m.moyenne desc;
$$;

grant execute on function public.classer_eleves_classe(uuid, uuid, uuid) to authenticated;

-- ============================================================================
-- Fin — correctif classer_eleves_classe().
-- ============================================================================
