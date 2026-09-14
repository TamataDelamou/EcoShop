-- ============================================================================
-- EcoShop — Correctif complémentaire : même classe de bug que
-- classer_eleves_classe() (migration 20260906001516), trouvée par le
-- balayage demandé après coup : calculer_moyenne_classe() souffre du MÊME
-- défaut, sans même utiliser le mot-clé LATERAL.
--
-- calculer_moyenne_classe() (redéfinie par l'audit RPC, migration
-- 20260906001513) calcule sa moyenne de classe via une sous-requête
-- corrélée :
--
--   select public.calculer_moyenne_eleve(f.id, p_matiere, p_periode) as m
--   from public.classes c
--   join public.inscriptions i on i.classe_id = c.id and ...
--   join public.fiches_eleves f on f.id = i.fiche_eleve_id and ...
--   where c.id = p_classe
--
-- Exactement le même défaut structurel que classer_eleves_classe() : rien
-- ne garantit que `where c.id = p_classe` soit évalué par le
-- planificateur AVANT l'appel à calculer_moyenne_eleve() pour CHAQUE fiche
-- du JOIN classes×inscriptions×fiches_eleves -- la classe de bug n'est
-- donc pas spécifique au mot-clé LATERAL, comme suspecté : toute
-- sous-requête corrélée appelant une fonction à autorisation interne, sans
-- garantie que le filtre de portée s'applique avant, y est exposée.
--
-- calculer_moyenne_classe() est elle-même directement exposée au client
-- (grant à authenticated depuis M6) : un enseignant/la direction consultant
-- la moyenne de sa PROPRE classe pouvait donc, comme pour
-- classer_eleves_classe(), se voir refuser l'accès si le planificateur
-- choisissait un Seq Scan de fiches_eleves rencontrant d'abord une fiche
-- d'un AUTRE établissement.
--
-- Même correctif structurel : CTE MATERIALIZED forçant la résolution/
-- filtrage AVANT tout appel à calculer_moyenne_eleve(), indépendamment du
-- plan choisi.
-- ============================================================================

create or replace function public.calculer_moyenne_classe(
  p_classe uuid,
  p_matiere uuid default null,
  p_periode uuid default null
)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etablissement uuid;
begin
  select etablissement_id into v_etablissement from public.classes where id = p_classe;

  if v_etablissement is not null
     and auth.uid() is not null
     and not coalesce(public.est_personnel(v_etablissement), false)
     and not coalesce(public.classe_visible(p_classe), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return (
    with fiches_de_la_classe as materialized (
      select f.id as fiche_eleve_id
      from public.classes c
      join public.inscriptions i on i.classe_id = c.id and i.deleted_at is null and i.statut = 'active'
      join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
      where c.id = p_classe
    )
    select round(avg(m), 2)
    from (
      select public.calculer_moyenne_eleve(fc.fiche_eleve_id, p_matiere, p_periode) as m
      from fiches_de_la_classe fc
    ) moyennes
    where m is not null
  );
end;
$$;

grant execute on function public.calculer_moyenne_classe(uuid, uuid, uuid) to authenticated;

-- ============================================================================
-- Fin — correctif calculer_moyenne_classe().
-- ============================================================================
