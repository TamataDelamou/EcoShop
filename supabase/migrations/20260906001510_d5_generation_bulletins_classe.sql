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
-- Écriture du bulletin — RPC dédiée `generer_bulletins_classe`, PAS un upsert
-- direct depuis le client comme prévu initialement : les deux index uniques
-- ci-dessous sont partiels (`where periode_id is [not] null`), et PostgREST
-- construit un `ON CONFLICT (colonnes)` SANS le prédicat de l'index partiel
-- — Postgres refuse alors d'inférer l'index (`42P10 : there is no unique or
-- exclusion constraint matching the ON CONFLICT specification`), y compris
-- pour la toute première génération, jamais seulement la régénération.
-- Vérifié empiriquement par un appel REST réel contre l'instance locale
-- avant correction (les deux variantes periode_id NULL et NOT NULL
-- échouent), pas supposé. La RPC exécute l'INSERT ... ON CONFLICT en SQL
-- brut, où le prédicat peut être précisé explicitement — seul endroit où
-- Postgres peut réellement cibler ces index partiels. Répond aussi à la
-- régénération après correction (cahier §12.3 : une note reste modifiable
-- par le responsable jusqu'à la proclamation de fin d'année) : rejouer la
-- RPC met à jour EN PLACE le même bulletin (même clé fiche/période/type),
-- jamais un doublon.
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

-- ---------------------------------------------------------------------------
-- Génère (ou régénère) les bulletins d'une classe entière pour une période
-- donnée (ou l'année entière si p_periode est NULL) : un bulletin par élève
-- classé par classer_eleves_classe(), écrit en une seule instruction
-- (atomique). La permission est vérifiée explicitement ici (comme
-- creer_inscription_nouvel_eleve, lier_parent_a_fiche…) : SECURITY DEFINER
-- contourne délibérément la RLS de la table pour pouvoir cibler l'index
-- partiel correct dans ON CONFLICT — l'autorité n'est donc plus la policy
-- RLS `bulletins_ecriture_scolarite` (laissée en place pour d'éventuelles
-- écritures directes futures, ex. correction manuelle d'une appréciation)
-- mais ce contrôle explicite.
--
-- Deux branches (periode_id NULL ou NOT NULL) : une seule instruction ne
-- peut porter qu'un seul prédicat ON CONFLICT, et l'appel porte toujours sur
-- UNE période (ou aucune) pour toute la classe — jamais un mélange.
create or replace function public.generer_bulletins_classe(
  p_classe uuid,
  p_annee uuid,
  p_periode uuid default null,
  p_type public.type_bulletin default 'trimestriel'
)
returns setof public.bulletins
language plpgsql security definer set search_path = public
as $$
declare
  v_etablissement uuid;
begin
  select etablissement_id into v_etablissement from public.classes where id = p_classe;
  if v_etablissement is null then
    raise exception 'CLASSE_INTROUVABLE' using errcode = '23514';
  end if;

  -- coalesce(..., false) : a_permission() peut renvoyer NULL (pas seulement
  -- false) quand l'appelant n'a encore aucun role_racine choisi — un simple
  -- `if not ...` laisserait alors passer l'appel silencieusement (IF NULL
  -- ne déclenche jamais la branche en PL/pgSQL), contrairement à une clause
  -- RLS USING/WITH CHECK où Postgres traite NULL comme refusé
  -- automatiquement. Vérifié empiriquement : sans ce coalesce, un compte
  -- étranger obtenait un tableau vide (200 OK) au lieu d'un refus explicite.
  if not coalesce(public.a_permission(v_etablissement, 'scolarite.bulletin.gerer'), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  if p_periode is null then
    return query
    insert into public.bulletins
      (etablissement_id, annee_scolaire_id, periode_id, classe_id, fiche_eleve_id, type, statut, contenu, genere_le, publie_le)
    select v_etablissement, p_annee, null, p_classe, c.fiche_eleve_id, p_type, 'publie',
           jsonb_build_object('moyenne_generale', c.moyenne, 'rang', c.rang, 'effectif_classe', count(*) over ()),
           now(), now()
    from public.classer_eleves_classe(p_classe, null, null) c
    on conflict (fiche_eleve_id, type) where periode_id is null
    do update set
      annee_scolaire_id = excluded.annee_scolaire_id,
      classe_id = excluded.classe_id,
      statut = excluded.statut,
      contenu = excluded.contenu,
      genere_le = excluded.genere_le,
      publie_le = excluded.publie_le
    returning *;
  else
    return query
    insert into public.bulletins
      (etablissement_id, annee_scolaire_id, periode_id, classe_id, fiche_eleve_id, type, statut, contenu, genere_le, publie_le)
    select v_etablissement, p_annee, p_periode, p_classe, c.fiche_eleve_id, p_type, 'publie',
           jsonb_build_object('moyenne_generale', c.moyenne, 'rang', c.rang, 'effectif_classe', count(*) over ()),
           now(), now()
    from public.classer_eleves_classe(p_classe, null, p_periode) c
    on conflict (fiche_eleve_id, periode_id, type) where periode_id is not null
    do update set
      annee_scolaire_id = excluded.annee_scolaire_id,
      classe_id = excluded.classe_id,
      statut = excluded.statut,
      contenu = excluded.contenu,
      genere_le = excluded.genere_le,
      publie_le = excluded.publie_le
    returning *;
  end if;
end;
$$;

grant execute on function public.generer_bulletins_classe(uuid, uuid, uuid, public.type_bulletin) to authenticated;

-- ============================================================================
-- Fin D5 — génération des bulletins de classe.
-- ============================================================================
