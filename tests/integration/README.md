# Tests d'intégration (M12)

Complément aux tests RLS pgTAP (`tests/rls/01→27`), les tests d'intégration
vérifient la **cohérence inter-modules** du socle M0→M12 sans modifier les données.

## Contenu

| Fichier | Type | Vérifie |
|---|---|---|
| `audit_coherence.sql` | Audit SQL (lecture seule) | Tables, intégrité référentielle, RLS, fonctions transverses/IA, catalogue de permissions |

## Exécution

```bash
# Variable d'environnement : chaîne de connexion PostgreSQL du projet
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/integration/audit_coherence.sql
```

## Verdict

| Résultat | Signification |
|---|---|
| `0 KO → GO` | Le socle est cohérent, le déploiement peut continuer |
| `>0 KO → NO-GO` | Corriger les contrôles en échec avant déploiement |

L'audit est **non destructif** et **idempotent** : il peut être rejoué à volonté
(et intégré au pipeline CI/CD, cf. `.github/workflows/ci.yml`).

## Extension

Pour ajouter un contrôle :

1. Ouvrir `audit_coherence.sql`.
2. Ajouter une ligne `insert into _audit_m12 values (...)` dans la catégorie idoine.
3. Relancer l'audit : le résumé recalculera automatiquement `total / ok / ko / verdict`.
