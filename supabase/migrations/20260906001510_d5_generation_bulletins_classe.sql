-- ============================================================================
-- EcoShop — D5 — Génération des bulletins d'une classe entière (cahier §12.4)
--
-- Écart comblé : aucune brique de composition de bulletin n'existait nulle
-- part avant D5 (ni individuelle, ni de classe) — seule l'impression d'un
-- bulletin DÉJÀ existant était couverte (M15ter/export_pdf). La seule ligne
-- jamais écrite dans `bulletins` était un seed manuel de démo.
--
-- Porte la logique de `ecoshop_flutter` (NotesService.genererBulletin() +
-- calculerClassementClasse()) : moyenne + rang + effectif de classe. Le
-- calcul lui-même reste **côté serveur** (contrat M06 §5 — « aucune moyenne
-- n'est calculée côté client ») : `calculer_moyenne_eleve` existait déjà,
-- seul le classement (rang dans la classe) manquait — ajouté ici en RPC
-- dédiée plutôt que reproduit côté client, pour ne jamais violer ce contrat
-- déjà établi par M6.
--
-- L'écriture du bulletin lui-même (table `bulletins`) n'a pas besoin d'une
-- nouvelle RPC : la politique RLS `bulletins_ecriture_scolarite` (M6) permet
-- déjà l'upsert direct à quiconque détient `scolarite.bulletin.gerer` — le
-- client se contente de recopier les valeurs déjà calculées côté serveur
-- (moyenne, rang, effectif) dans `contenu`, sans aucun calcul.
--
-- Statut : la génération publie directement le bulletin (`statut = 'publie'`,
-- `publie_le = now()`) — la source (ecoshop_flutter) n'a jamais eu de cycle
-- brouillon/publication séparé pour les bulletins, un bulletin y est visible
-- dès sa génération. Le cycle brouillon/aperçu/publication du chapitre 18 est
-- hors périmètre D5 (différé, voir rapport d'écart) ; générer en `brouillon`
-- ici rendrait la fonctionnalité inutilisable (élève/parent ne voient jamais
-- un bulletin `brouillon, cf. RLS `bulletin_visible`) sans qu'aucune action
-- de publication n'existe pour l'en sortir — ce serait une régression par
-- rapport à la source, pas un simple choix par défaut.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Classement d'une classe : moyenne + rang de chaque élève, sur la période
-- (et matière) donnée. Réutilise `calculer_moyenne_eleve` (déjà éprouvée,
-- déjà couverte par les triggers/permissions M6) — n'invente aucun nouveau
-- calcul de moyenne, seulement le rang par tri décroissant.
--
-- Portée volontairement plus large que `calculer_moyenne_eleve` (une classe
-- entière, pas une seule fiche) : contrairement à cette dernière, réservée au
-- personnel de l'établissement de la classe (et non à tout `authenticated`)
-- — un élève/parent n'a pas besoin de voir le classement de ses camarades.
-- ---------------------------------------------------------------------------
create or replace function public.classer_eleves_classe(
  p_classe uuid,
  p_matiere uuid default null,
  p_periode uuid default null
)
returns table(fiche_eleve_id uuid, moyenne numeric, rang int)
language sql stable security definer set search_path = public
as $$
  select f.id as fiche_eleve_id,
         m.moyenne,
         rank() over (order by m.moyenne desc)::int as rang
  from public.classes c
  join public.inscriptions i on i.classe_id = c.id and i.deleted_at is null and i.statut = 'active'
  join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
  cross join lateral (
    select public.calculer_moyenne_eleve(f.id, p_matiere, p_periode) as moyenne
  ) m
  where c.id = p_classe
    and m.moyenne is not null
    and public.est_personnel(c.etablissement_id)
  order by m.moyenne desc;
$$;

grant execute on function public.classer_eleves_classe(uuid, uuid, uuid) to authenticated;

-- ============================================================================
-- Fin D5 — génération des bulletins de classe.
-- ============================================================================
