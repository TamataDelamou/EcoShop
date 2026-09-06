# M8 — RH & Personnel

> Module de gestion des ressources humaines de l'établissement, intégré à la
> scolarité (affectations M5, absences M7, référentiel M4). Validation humaine
> systématique des décisions RH ; l'IA ne produit que des signaux d'aide.

## 1. Périmètre fonctionnel

- **Employés** : dossier RH adossé au compte (`profiles`), rattaché à un
  établissement. Catégories : `enseignant`, `administratif`, `direction`,
  `personnel`. Matricule unique par établissement.
- **Contrats** : `cdi`, `cdd`, `vacataire`, `stage`, `prestataire` ; dates,
  salaire de base, renouvellement automatique.
- **Congés** : `annuel`, `maladie`, `maternite`, `exceptionnel`, `sans_solde`.
  Cycle demande → validation → historique. L'employé dépose ; RH/direction
  valide (jamais d'auto-validation).
- **Absences personnel** : pointage des absences (justifiées ou non), distinct
  des congés planifiés. Alimente le risque de turn-over.
- **Paie légère** : bulletin = base + primes − retenues = net, sans fiscalité
  complexe (délibérément hors périmètre). Le net est toujours recalculé côté
  serveur (trigger), le client ne fait jamais foi sur le montant.

## 2. Modèle de données (migration `20260906000800_m8_rh_personnel.sql`)

| Table | Rôle | Points clés |
|---|---|---|
| `employes` | Dossier RH | `profile_id` (compte), `matricule`, `categorie`, `date_embauche`, `statut` |
| `contrats` | Contrat de travail | `type`, `date_debut`/`date_fin` (null = CDI), `salaire_base`, `actif` |
| `conges` | Demandes de congé | `statut` (`demande`/`valide`/`refuse`), `valide_par`, `date_validation` |
| `absences_personnel` | Pointage d'absences | `date_absence`, `type`, `justifie` — unique (employé, date) |
| `paie_bulletins` | Bulletins de paie | `base`/`primes`/`retenues`/`net`, `statut` (`brouillon`/`valide`/`paye`) |

### Garde-fous (triggers)

- **Multi-tenant** : chaque table vérifie que l'employé/contrat référencé
  appartient au même `etablissement_id` (pattern `membres_verifie_tenant`).
- **Employé = membre actif** : un dossier employé ne peut être créé que pour un
  compte membre actif de l'établissement.
- **Validation humaine des congés** : passer une demande en `valide`/`refuse`
  exige `est_rh()` (ou l'exécution serveur) ; l'employé ne peut créer que des
  `demande`.
- **Net recalculé** : `net = base + primes − retenues`, refus si négatif.

## 3. IA — trois niveaux (cohérents M6/M7)

| Niveau | Fonction | Description |
|---|---|---|
| Descriptive | `analyser_effectifs(etab)` | Effectifs, ancienneté moyenne, masse salariale par catégorie |
| Prédictive | `calculer_score_turnover(employe)` | Score 0-1 croisant absences (×2 si injustifiées), ancienneté, charge (M5) et type/fin de contrat |
| Prescriptive | `recommander_formation(employe, annee)` | Matières du référentiel M4 du pays non encore enseignées |
| Prescriptive | `optimiser_remplacements(etab, date)` | Pour chaque enseignant absent, propose le remplaçant actif le moins chargé |

**Pondération du turn-over** : 0.4 absences + 0.2 ancienneté + 0.2 charge +
0.2 contrat. Les seuils (ancienneté < 1 an, charge > 30 h, CDD/vacataire fini
sous 90 jours) sont des constantes de migration, ajustables par établissement.

**Règle éthique** : ces fonctions sont réservées à RH/direction (ou au serveur)
et ne produisent que des **signaux d'aide à la décision** ; aucune action RH
(décision, sanction, validation) n'est automatisée.

## 4. RLS & visibilité

- **RH/direction** (`est_rh`) : lecture et écriture de tous les dossiers,
  contrats, absences et paie de l'établissement ; validation des congés.
- **Employé** : lecture de son propre dossier, de ses contrats, congés et
  bulletins ; dépôt et retrait de ses propres demandes (statut `demande`).
- **Isolation multi-tenant** : aucun dossier visible hors établissement
  (helpers `employe_visible`, `contrat_visible`, `conge_visible`).

## 5. Hors-ligne

- **Consultation** : dossiers employés, contrats et soldes de congés en cache
  local (Drift), comme le référentiel M4.
- **Synchronisation des demandes de congé** : la demande est créée en cache
  puis poussée (LWW sur `created_at` + `device_id`), conformément à la
  stratégie `sync_queue` du socle. La validation reste strictement serveur.

## 6. Plan de tests

- `16_m8_rh_visibilite.sql` : direction voit tout, employé son dossier et son
  bulletin, écriture interdite à l'employé, isolation multi-tenant.
- `17_m8_conges_validation.sql` : dépôt, interdiction de dépôt pour autrui et
  d'auto-validation, validation par la direction, retrait d'une demande.
- `18_m8_ia_rh.sql` : score de turn-over exact (0.88 / 0.12), effectifs,
  recommandation de formation (matière non couverte), remplacement proposé.

Exécution (session Docker) : `pg_prove -d "$DB" tests/rls/16_m8_rh_visibilite.sql`
etc. — détail complet dans `docs/SESSION_VALIDATION_TECHNIQUE.md`.

## 7. Permissions introduites

| Code | Libellé |
|---|---|
| `rh.employe.voir` | Consulter les dossiers employés |
| `rh.employe.gerer` | Gérer les employés et saisir les absences |
| `rh.contrat.gerer` | Gérer les contrats |
| `rh.conge.valider` | Valider les congés |
| `rh.paie.gerer` | Gérer la paie |
