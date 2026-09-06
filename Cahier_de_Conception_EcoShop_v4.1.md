**GLOBAL SERVICE GROUPE**

**CAHIER DE CONCEPTION**

**ECOSHOP**

*Gestion globale des établissements scolaires, marketplace scolaire intégrée & moteur de révision et de réussite aux examens*

Application mobile (Android / iOS) et Windows --- développée sous Flutter

**Version 4.1 --- Authentification native Supabase fédérée par GSG ID (GSG Platform Kernel) et cadre financier & contractuel marketplace (AssoShop)**

Fusion intégrale du cahier de conception EcoShop v2.0 et du cahier de conception EduRéussite

Référentiel pédagogique multi-pays (CEDEAO) --- Authentification native Supabase Auth fédérée GSG ID (SMS / WhatsApp / E-mail) --- Moteur de révision, préparation aux examens et intelligence artificielle

*Document rédigé selon le principe : à chaque point commun entre les deux cahiers sources, la conception la plus pertinente est retenue*

*Révision 4.0 --- le chapitre 5 (Authentification) est intégralement reconstruit sur le modèle d\'authentification natif Supabase Auth commun au portefeuille GSG, avec fédération d\'identité GSG ID conforme au GSG Platform Kernel v3.0. Document autosuffisant : aucune lecture croisée du cahier Kernel n\'est nécessaire.*

*Révision 4.1 --- mise en cohérence du chapitre 5 avec l\'addendum de normalisation E.164 du modèle d\'authentification portefeuille (26/08/2026) ; intégration au chapitre 27 du cadre financier et contractuel marketplace AssoShop (sous-comptes établissement, absence de portefeuille vendeur, compte auxiliaire, règlement différé, convention vendeur-établissement), avec réconciliation explicite du panier mono-vendeur retenu en lieu et place du panier multi-vendeur de la révision précédente.*

# **SOMMAIRE**

[**SOMMAIRE**](#sommaire)

[**1. Introduction**](#introduction)

[**1.1 Contexte et positionnement**](#contexte-et-positionnement)

[**1.2 Méthode de fusion : juger en faveur du plus pertinent**](#méthode-de-fusion-juger-en-faveur-du-plus-pertinent)

[**1.3 Deux composantes historiques, un même écosystème**](#deux-composantes-historiques-un-même-écosystème)

[**1.4 Objectifs du document**](#objectifs-du-document)

[**2. Présentation générale de EcoShop**](#présentation-générale-de-ecoshop)

[**2.1 Vision produit**](#vision-produit)

[**2.2 Public cible**](#public-cible)

[**2.3 Modèle de déploiement**](#modèle-de-déploiement)

[**2.4 Principe de gratuité progressive**](#principe-de-gratuité-progressive)

[**2.5 Restrictions du mode gratuit**](#restrictions-du-mode-gratuit)

[**3. Étude de marché et positionnement --- moteur de révision et de réussite**](#étude-de-marché-et-positionnement-moteur-de-révision-et-de-réussite)

[**3.1 Panorama concurrentiel condensé**](#panorama-concurrentiel-condensé)

[**3.2 Axes de différenciation retenus**](#axes-de-différenciation-retenus)

[**4. Gestion des rôles et des profils**](#gestion-des-rôles-et-des-profils)

[**4.1 Modèle à deux niveaux : rôle racine et poste déclaré**](#modèle-à-deux-niveaux-rôle-racine-et-poste-déclaré)

[**4.2 Rôles racines**](#rôles-racines)

[**4.3 Élève supervisé (primaire et Maternelle)**](#élève-supervisé-primaire-et-maternelle)

[**4.4 Rôles de plateforme : Administrateur GSG et Administrateur de contenu pédagogique**](#rôles-de-plateforme-administrateur-gsg-et-administrateur-de-contenu-pédagogique)

[**4.5 Postes déclarés sous le rôle « Direction »**](#postes-déclarés-sous-le-rôle-direction)

[**4.6 Déclaration des niveaux et création dynamique des postes**](#déclaration-des-niveaux-et-création-dynamique-des-postes)

[**4.7 Principes transversaux de permission**](#principes-transversaux-de-permission)

[**5. Authentification, identité fédérée et sécurité des comptes**](#authentification-identité-fédérée-et-sécurité-des-comptes)

[**5.1 Vue d\'ensemble du parcours de compte**](#vue-densemble-du-parcours-de-compte)

[**5.2 Inscription auto-service (Élève, Parent)**](#inscription-auto-service-élève-parent)

[**5.3 Onboarding des rôles à privilège**](#onboarding-des-rôles-à-privilège)

[**5.4 Authentification native Supabase Auth --- architecture cible**](#authentification-native-supabase-auth-architecture-cible)

[**5.4.1 Principe général : deux entrées, quatre canaux**](#principe-général-deux-entrées-quatre-canaux)

[**5.4.2 Branche Téléphone --- SMS et WhatsApp**](#branche-téléphone-sms-et-whatsapp)

[**5.4.3 Branche E-mail --- Magic Link et code OTP**](#branche-e-mail-magic-link-et-code-otp)

[**5.4.4 Unicité du compte et liaison multi-canal**](#unicité-du-compte-et-liaison-multi-canal)

[**5.4.5 Configuration côté tableau de bord Supabase**](#configuration-côté-tableau-de-bord-supabase)

[**5.5 Identité fédérée GSG ID (GSG Platform Kernel)**](#identité-fédérée-gsg-id-gsg-platform-kernel)

[**5.6 Table profiles, rôle racine et Custom Access Token Hook**](#table-profiles-rôle-racine-et-custom-access-token-hook)

[**5.7 Session et multi-appareils**](#session-et-multi-appareils)

[**5.8 Récupération de compte**](#récupération-de-compte)

[**5.9 Liaison compte ↔ fiche existante**](#liaison-compte-fiche-existante)

[**5.10 Sécurité, conformité et points de vigilance**](#sécurité-conformité-et-points-de-vigilance)

[**5.11 Intégration au GSG Platform Kernel --- synthèse**](#intégration-au-gsg-platform-kernel-synthèse)

[**6. Référentiel pédagogique multi-pays**](#référentiel-pédagogique-multi-pays)

[**6.1 Principe de conception : découplage référentiel / contenu versionné**](#principe-de-conception-découplage-référentiel-contenu-versionné)

[**6.2 Schéma relationnel du référentiel structurel**](#schéma-relationnel-du-référentiel-structurel)

[**6.3 Deux chaînes de hiérarchie distinctes**](#deux-chaînes-de-hiérarchie-distinctes)

[**6.4 Référentiel des 16 pays de la CEDEAO**](#référentiel-des-16-pays-de-la-cedeao)

[**6.5 Trajectoire d\'extension géographique**](#trajectoire-dextension-géographique)

[**6.6 Non-régression, isolation et gouvernance du référentiel**](#non-régression-isolation-et-gouvernance-du-référentiel)

[**7. Module --- Gestion administrative et scolarité**](#module-gestion-administrative-et-scolarité)

[**7.1 Inscription et réinscription**](#inscription-et-réinscription)

[**7.2 Échéances de paiement et statut boursier**](#échéances-de-paiement-et-statut-boursier)

[**7.3 Classes, cycles, filières et années académiques**](#classes-cycles-filières-et-années-académiques)

[**7.4 Historique scolaire**](#historique-scolaire)

[**7.5 Gestion des tuteurs, import/export et assistance à la saisie**](#gestion-des-tuteurs-importexport-et-assistance-à-la-saisie)

[**7.6 Identification des élèves**](#identification-des-élèves)

[**7.7 Spécificités par tranche d\'âge : renvoi au module académique**](#spécificités-par-tranche-dâge-renvoi-au-module-académique)

[**8. Module --- Gestion du personnel (RH)**](#module-gestion-du-personnel-rh)

[**8.1 Enseignants**](#enseignants)

[**8.2 Personnel administratif et d\'encadrement**](#personnel-administratif-et-dencadrement)

[**8.3 Dossier personnel et liaison de compte**](#dossier-personnel-et-liaison-de-compte)

[**8.4 Contrats**](#contrats)

[**8.5 Congés**](#congés)

[**8.6 Salaires, primes et avances**](#salaires-primes-et-avances)

[**9. Module --- Gestion académique et pédagogique**](#module-gestion-académique-et-pédagogique)

[**9.1 Programmes et organisation**](#programmes-et-organisation)

[**9.2 Suivi pédagogique**](#suivi-pédagogique)

[**9.3 Moteur de contenu pédagogique (cours et leçons)**](#moteur-de-contenu-pédagogique-cours-et-leçons)

[**9.4 Ressources pédagogiques et pédagogie avancée (e-learning)**](#ressources-pédagogiques-et-pédagogie-avancée-e-learning)

[**9.5 Assistant IA d\'apprentissage**](#assistant-ia-dapprentissage)

[**9.6 Spécificités de conception pour le primaire (CP1 à CE2)**](#spécificités-de-conception-pour-le-primaire-cp1-à-ce2)

[**9.7 Espace Maternelle --- Éveil préscolaire**](#espace-maternelle-éveil-préscolaire)

[**9.7.1 Fonctionnalités clés**](#fonctionnalités-clés)

[**9.7.2 Règles de gestion**](#règles-de-gestion)

[**10. Module --- Moteur de questions**](#module-moteur-de-questions)

[**10.1 Métadonnées et structuration**](#métadonnées-et-structuration)

[**10.2 Types de questions et niveaux de difficulté**](#types-de-questions-et-niveaux-de-difficulté)

[**10.3 Signalement et qualité**](#signalement-et-qualité)

[**11. Module --- Quiz, entraînement et mode examen**](#module-quiz-entraînement-et-mode-examen)

[**11.1 Quiz et entraînement**](#quiz-et-entraînement)

[**11.2 Mode Examen**](#mode-examen)

[**12. Module --- Notes, évaluations officielles et bulletins**](#module-notes-évaluations-officielles-et-bulletins)

[**12.1 Saisie des notes**](#saisie-des-notes)

[**12.2 Rythme des compositions : un modèle déclaratif**](#rythme-des-compositions-un-modèle-déclaratif)

[**12.3 Cycle de verrouillage des notes**](#cycle-de-verrouillage-des-notes)

[**12.4 Génération des bulletins et export PDF**](#génération-des-bulletins-et-export-pdf)

[**12.5 Absences et sanctions**](#absences-et-sanctions)

[**12.6 Notes officielles et résultats d\'entraînement : une distinction stricte**](#notes-officielles-et-résultats-dentraînement-une-distinction-stricte)

[**12.7 Risque d\'échec et statistiques**](#risque-déchec-et-statistiques)

[**13. Module --- Préparation aux examens nationaux et concours**](#module-préparation-aux-examens-nationaux-et-concours)

[**13.1 Principe : un espace par examen, rattaché au référentiel**](#principe-un-espace-par-examen-rattaché-au-référentiel)

[**13.2 Contenu d\'un espace de préparation**](#contenu-dun-espace-de-préparation)

[**13.3 Cas particulier de l\'examen de fin de primaire**](#cas-particulier-de-lexamen-de-fin-de-primaire)

[**13.4 Règles de gestion**](#règles-de-gestion-1)

[**13.5 Articulation avec les autres modules**](#articulation-avec-les-autres-modules)

[**14. Module --- Analyse des compétences et moteur de recommandation**](#module-analyse-des-compétences-et-moteur-de-recommandation)

[**14.1 Profil de maîtrise par compétence**](#profil-de-maîtrise-par-compétence)

[**14.2 Moteur de recommandation**](#moteur-de-recommandation)

[**14.3 Articulation avec les autres modules**](#articulation-avec-les-autres-modules-1)

[**15. Module --- Répétition espacée et planificateur intelligent**](#module-répétition-espacée-et-planificateur-intelligent)

[**15.1 Répétition espacée**](#répétition-espacée)

[**15.2 Planificateur intelligent**](#planificateur-intelligent)

[**15.3 Articulation avec les autres modules**](#articulation-avec-les-autres-modules-2)

[**16. Module --- Emploi du temps**](#module-emploi-du-temps)

[**16.1 Grille horaire**](#grille-horaire)

[**16.2 Calendrier scolaire et activités**](#calendrier-scolaire-et-activités)

[**16.3 Séances récurrentes**](#séances-récurrentes)

[**16.4 Séances ponctuelles et annulations**](#séances-ponctuelles-et-annulations)

[**16.5 Détection de conflit**](#détection-de-conflit)

[**16.6 Consultation par rôle et notifications**](#consultation-par-rôle-et-notifications)

[**17. Module --- Gestion financière et comptable**](#module-gestion-financière-et-comptable)

[**17.1 Paiement libre et progressif**](#paiement-libre-et-progressif)

[**17.2 Modes d\'encaissement**](#modes-dencaissement)

[**17.3 Reçus et impression**](#reçus-et-impression)

[**17.4 Cahier journal et solde élève**](#cahier-journal-et-solde-élève)

[**17.5 Comptabilité de l\'établissement**](#comptabilité-de-létablissement)

[**17.6 Portefeuille établissement et distribution de fin d\'année**](#portefeuille-établissement-et-distribution-de-fin-dannée)

[**17.7 Abonnements et frais plateforme**](#abonnements-et-frais-plateforme)

[**17.8 Traçabilité des transactions et activation des abonnements**](#traçabilité-des-transactions-et-activation-des-abonnements)

[**18. Documents officiels et espace de personnalisation des templates**](#documents-officiels-et-espace-de-personnalisation-des-templates)

[**18.1 Principe : un espace de personnalisation dédié par établissement**](#principe-un-espace-de-personnalisation-dédié-par-établissement)

[**18.2 Documents concernés**](#documents-concernés)

[**18.3 Éléments personnalisables**](#éléments-personnalisables)

[**18.4 Champs de fusion dynamiques**](#champs-de-fusion-dynamiques)

[**18.5 Cycle de vie d\'un template : brouillon, aperçu, publication**](#cycle-de-vie-dun-template-brouillon-aperçu-publication)

[**18.6 Accès et permissions**](#accès-et-permissions)

[**18.7 Accès réservé au mode payant**](#accès-réservé-au-mode-payant)

[**18.8 Moteur de génération unique**](#moteur-de-génération-unique)

[**19. Module --- Vie scolaire et services complémentaires**](#module-vie-scolaire-et-services-complémentaires)

[**19.1 Discipline et sanctions**](#discipline-et-sanctions)

[**19.2 Infrastructures et matériel**](#infrastructures-et-matériel)

[**19.3 Services complémentaires paramétrables**](#services-complémentaires-paramétrables)

[**19.4 Logistique et discipline au retrait marketplace**](#logistique-et-discipline-au-retrait-marketplace)

[**20. Module --- Communication**](#module-communication)

[**20.1 Communication interne**](#communication-interne)

[**20.2 Centre de notifications**](#centre-de-notifications)

[**20.3 Groupes de discussion**](#groupes-de-discussion)

[**20.4 Signalement et modération**](#signalement-et-modération)

[**21. Module --- Intelligence artificielle**](#module-intelligence-artificielle)

[**21.1 Chat IA --- Directeur-Adviser**](#chat-ia-directeur-adviser)

[**21.2 Parent IA**](#parent-ia)

[**21.3 Analyse des performances et prédiction du risque d\'échec**](#analyse-des-performances-et-prédiction-du-risque-déchec)

[**21.4 Abonnement IA élève --- Tuteur IA**](#abonnement-ia-élève-tuteur-ia)

[**21.5 Scan et résolution d\'exercice**](#scan-et-résolution-dexercice)

[**21.6 Abonnement IA professeur**](#abonnement-ia-professeur)

[**21.7 Autres usages de l\'IA**](#autres-usages-de-lia)

[**22. Module --- Gamification et engagement**](#module-gamification-et-engagement)

[**22.1 Points d\'expérience (XP)**](#points-dexpérience-xp)

[**22.2 Niveaux progressifs et badges**](#niveaux-progressifs-et-badges)

[**22.3 Classements et gamification non comparative**](#classements-et-gamification-non-comparative)

[**22.4 Articulation avec les autres modules**](#articulation-avec-les-autres-modules-3)

[**23. Module --- Compétitions, classements et certificats**](#module-compétitions-classements-et-certificats)

[**23.1 Classements multi-échelles**](#classements-multi-échelles)

[**23.2 Concours privés et événements de compétition**](#concours-privés-et-événements-de-compétition)

[**23.3 Certificat de maîtrise**](#certificat-de-maîtrise)

[**23.4 Lutte contre la fraude au classement**](#lutte-contre-la-fraude-au-classement)

[**24. Module --- Transport scolaire**](#module-transport-scolaire)

[**24.1 Circuits et arrêts**](#circuits-et-arrêts)

[**24.2 Affectation d\'élèves**](#affectation-délèves)

[**24.3 Suivi en direct**](#suivi-en-direct)

[**24.4 Facturation transport**](#facturation-transport)

[**25. Module --- Bibliothèque physique**](#module-bibliothèque-physique)

[**25.1 Catalogue de livres**](#catalogue-de-livres)

[**25.2 Emprunt et retour**](#emprunt-et-retour)

[**25.3 Statuts automatiques**](#statuts-automatiques)

[**25.4 Gestion d\'inventaire**](#gestion-dinventaire)

[**26. Module --- Bibliothèque numérique et flashcards**](#module-bibliothèque-numérique-et-flashcards)

[**26.1 Contenu de la bibliothèque numérique**](#contenu-de-la-bibliothèque-numérique)

[**26.2 Flashcards**](#flashcards)

[**26.3 Révision audio téléchargeable**](#révision-audio-téléchargeable)

[**26.4 Règle de gestion**](#règle-de-gestion)

[**27. Module --- Marketplace (EcoShop Market)**](#module-marketplace-ecoshop-market)

[**27.1 Concept : marketplace scolaire contrôlée**](#concept-marketplace-scolaire-contrôlée)

[**27.2 Gestion des vendeurs**](#gestion-des-vendeurs)

[**27.3 Catalogue de produits**](#catalogue-de-produits)

[**27.4 Expérience d\'achat**](#expérience-dachat)

[**27.5 Livraison et SLA**](#livraison-et-sla)

[**27.6 Réception et remise des colis**](#réception-et-remise-des-colis)

[**27.7 Gestion des stocks et commandes abandonnées**](#gestion-des-stocks-et-commandes-abandonnées)

[**27.8 Modèle économique de la marketplace**](#modèle-économique-de-la-marketplace)

[**27.9 Sécurité, traçabilité, litiges et fonctionnalités avancées**](#sécurité-traçabilité-litiges-et-fonctionnalités-avancées)

[**27.10 Tableaux de bord**](#tableaux-de-bord)

[**28. Établissements indépendants et réseaux d\'établissements**](#établissements-indépendants-et-réseaux-détablissements)

[**28.1 Établissements indépendants (hébergement multi-établissements)**](#établissements-indépendants-hébergement-multi-établissements)

[**28.2 Réseaux d\'établissements**](#réseaux-détablissements)

[**28.3 Création, invitation et annuaire**](#création-invitation-et-annuaire)

[**28.4 Retrait et dissolution**](#retrait-et-dissolution)

[**28.5 Tableau de bord réseau**](#tableau-de-bord-réseau)

[**28.6 Règle d\'unicité d\'inscription, valable pour tous**](#règle-dunicité-dinscription-valable-pour-tous)

[**29. Module --- Reporting et tableaux de bord**](#module-reporting-et-tableaux-de-bord)

[**29.1 Tableau de bord Directeur**](#tableau-de-bord-directeur)

[**29.2 Alertes proactives**](#alertes-proactives)

[**29.3 Statistiques et export établissement**](#statistiques-et-export-établissement)

[**30. Backoffice Global Service Groupe**](#backoffice-global-service-groupe)

[**30.1 Validation des demandes**](#validation-des-demandes)

[**30.2 Validation des demandes vendeur**](#validation-des-demandes-vendeur)

[**30.3 Vue d\'ensemble des réseaux**](#vue-densemble-des-réseaux)

[**30.4 Paramètres globaux**](#paramètres-globaux)

[**30.5 CMS pédagogique et Administrateur de contenu pédagogique**](#cms-pédagogique-et-administrateur-de-contenu-pédagogique)

[**30.6 Révocation de session à distance**](#révocation-de-session-à-distance)

[**31. Module --- Paramétrage et personnalisation**](#module-paramétrage-et-personnalisation)

[**32. Relations entre les gestions**](#relations-entre-les-gestions)

[**33. Règles de gestion transversales**](#règles-de-gestion-transversales)

[**34. Exigences non fonctionnelles et règles de conception complémentaires**](#exigences-non-fonctionnelles-et-règles-de-conception-complémentaires)

[**34.1 Sécurité applicative**](#sécurité-applicative)

[**34.2 Protection des données personnelles et des mineurs**](#protection-des-données-personnelles-et-des-mineurs)

[**34.3 Journalisation et audit**](#journalisation-et-audit)

[**34.4 Résilience et mode hors ligne**](#résilience-et-mode-hors-ligne)

[**34.5 Performance et scalabilité**](#performance-et-scalabilité)

[**34.6 Tests et qualité**](#tests-et-qualité)

[**34.7 Conventions techniques**](#conventions-techniques)

[**34.8 Sauvegarde et plan de reprise**](#sauvegarde-et-plan-de-reprise)

[**34.9 Accessibilité et internationalisation**](#accessibilité-et-internationalisation)

[**34.10 Mentions légales et consentement**](#mentions-légales-et-consentement)

[**35. Architecture technique et estimation des écrans**](#architecture-technique-et-estimation-des-écrans)

[**35.1 Choix technologique**](#choix-technologique)

[**35.2 Mode hors ligne**](#mode-hors-ligne)

[**35.3 Stockage local et synchronisation**](#stockage-local-et-synchronisation)

[**35.4 Architecture du système d\'intelligence artificielle**](#architecture-du-système-dintelligence-artificielle)

[**35.5 Estimation du nombre d\'écrans par module**](#estimation-du-nombre-décrans-par-module)

[**36. Modèle économique global**](#modèle-économique-global)

[**36.1 Neuf flux de revenus indépendants**](#neuf-flux-de-revenus-indépendants)

[**36.2 Grille de l\'abonnement Premium élève**](#grille-de-labonnement-premium-élève)

[**36.3 Réconciliation : abonnement établissement et accès Premium élève**](#réconciliation-abonnement-établissement-et-accès-premium-élève)

[**36.4 Publicité limitée et protection des mineurs**](#publicité-limitée-et-protection-des-mineurs)

[**36.5 Sources de revenus par module --- vue de synthèse**](#sources-de-revenus-par-module-vue-de-synthèse)

[**37. Indicateurs de succès**](#indicateurs-de-succès)

[**37.1 Engagement**](#engagement)

[**37.2 Pédagogie**](#pédagogie)

[**37.3 Business**](#business)

[**37.4 Établissement et marketplace**](#établissement-et-marketplace)

[**38. Feuille de route produit**](#feuille-de-route-produit)

[**38.1 Phase 0 --- Socle déjà en production**](#phase-0-socle-déjà-en-production)

[**38.2 Phase 1 --- Socle du moteur de révision (collège et lycée)**](#phase-1-socle-du-moteur-de-révision-collège-et-lycée)

[**38.3 Phase 2 --- Préparation aux examens, engagement, ouverture du primaire**](#phase-2-préparation-aux-examens-engagement-ouverture-du-primaire)

[**38.4 Phase 3 --- Monétisation du moteur de révision et Maternelle**](#phase-3-monétisation-du-moteur-de-révision-et-maternelle)

[**38.5 Phase 4 --- Intelligence artificielle avancée du moteur de révision**](#phase-4-intelligence-artificielle-avancée-du-moteur-de-révision)

[**38.6 Phase 5 --- Extension géographique**](#phase-5-extension-géographique)

[**38.7 Ordre de priorité technique recommandé pour le volet révision**](#ordre-de-priorité-technique-recommandé-pour-le-volet-révision)

[**39. Conclusion**](#conclusion)

# **1. Introduction**

## **1.1 Contexte et positionnement**

EcoShop est une application développée par le Global Service Groupe (GSG) destinée à la gestion globale des établissements scolaires privés, en Guinée (GNF) et, à terme, dans la zone UEMOA puis CEDEAO (XOF). Elle couvre l\'ensemble de la chaîne de gestion scolaire --- de l\'administration de l\'établissement au suivi individuel de chaque élève --- une marketplace scolaire intégrée, et, depuis la présente révision, un moteur complet de révision, d\'entraînement et de réussite scolaire.

Ce cahier de conception, version 3.0, est le produit de la fusion de trois sources : le cahier de conception EcoShop v1.2 (intention fonctionnelle et règles de gestion détaillées), l\'état réel du code EcoShop au 20/08/2026 (déjà consolidés en version 2.0 de ce cahier), et le cahier de conception EduRéussite v1 --- une plateforme sœur, jusqu\'ici développée séparément, dont l\'objet est de transformer une simple banque de questions en système personnel de réussite scolaire (boucle Apprendre → S\'entraîner → S\'évaluer → Progresser).

> ***Règle de gestion ---** EcoShop et EduRéussite poursuivaient des objectifs largement parallèles --- toucher les mêmes familles, les mêmes établissements, les mêmes enseignants guinéens, avec deux comptes, deux applications et deux bases de données distinctes. Maintenir deux plateformes aurait dispersé l\'effort commercial et technique de GSG sans bénéfice pour l\'utilisateur final, qui aurait dû gérer deux inscriptions pour un seul enfant dans un seul établissement. La présente révision absorbe donc EduRéussite entièrement dans EcoShop : il n\'existe plus, à l\'issue de ce cahier, qu\'une seule plateforme, un seul compte par utilisateur, un seul moteur de rôles, et un seul modèle économique consolidé.*

## **1.2 Méthode de fusion : juger en faveur du plus pertinent**

Sur chaque fonctionnalité où les deux cahiers se recoupaient, ce document tranche explicitement en faveur de la conception la plus pertinente plutôt que de juxtaposer les deux --- un même besoin ne doit jamais être couvert par deux mécanismes concurrents dans l\'application finale. Quatre cas de figure se sont présentés :

-   **Le mécanisme EcoShop l\'emporte** lorsqu\'il est déjà production-réel et plus rigoureux : c\'est le cas de l\'authentification (moteur OTP multicanal, chapitre 5), du modèle de rôles (racine + poste déclaré, chapitre 4), du paiement (CinetPay, chapitre 17) et de la gouvernance des flux de revenus indépendants et paramétrables (chapitre 36).

-   **Le mécanisme EduRéussite l\'emporte** lorsqu\'il est structurellement supérieur : c\'est le cas du référentiel pédagogique multi-pays (chapitre 6), qui remplace la simple liste déclarative de cycles d\'EcoShop v2.0, et du moteur de contenu pédagogique et de questions (chapitres 9-10), bien plus riche que l\'Espace Exercices sommaire de la v2.0.

-   **Les deux fusionnent en un mécanisme enrichi** lorsqu\'ils sont complémentaires et non concurrents : c\'est le cas de l\'IA élève (chapitre 21, où le Tuteur IA d\'EduRéussite devient la spécification concrète de l\'abonnement IA élève d\'EcoShop), du mode hors ligne (chapitre 34) et de la protection des mineurs (chapitre 34).

-   **Le contenu est purement additif** lorsqu\'aucun équivalent n\'existait dans EcoShop v2.0 : gamification (22), compétitions (23), bibliothèque numérique et flashcards (26), analyse des compétences et recommandation (14), répétition espacée et planificateur (15), scan et résolution d\'exercice (21.5), espace Maternelle éveil préscolaire (intégré au chapitre 7 et 9), indicateurs de succès (37) et feuille de route produit (38).

Un principe explicite d\'anti-duplication a par ailleurs été appliqué à la structure elle-même : EduRéussite organisait son contenu à la fois par module fonctionnel (M04 à M16) et par espace acteur (M17 Espace Enseignant, M18 Espace Parent, M19 Espace Établissement), ce qui aurait dupliqué dans ce cahier des fonctionnalités déjà décrites ailleurs. EcoShop v2.0 n\'a jamais eu besoin de cette redondance : chaque fonctionnalité vit dans un seul module fonctionnel, et le chapitre Rôles (4) indique qui y accède. La présente révision conserve ce principe et absorbe le contenu réellement nouveau des espaces M17-M19 (devoirs numériques, analyse de classe, notifications de synthèse parent, statistiques consolidées établissement) directement dans les modules fonctionnels concernés, sans créer de chapitres « Espace Enseignant / Parent / Établissement » séparés.

## **1.3 Deux composantes historiques, un même écosystème**

EcoShop repose désormais sur trois composantes qui partagent la même base d\'utilisateurs, le même moteur d\'authentification et le même établissement comme point de convergence :

-   le **Système de gestion scolaire** (ERP scolaire) : administration, personnel, académique, notes officielles, finances, vie scolaire, communication, transport, bibliothèque physique, sécurité, paramétrage ;

-   le **Moteur de révision et de réussite scolaire** (ex-EduRéussite) : référentiel pédagogique multi-pays, contenu de cours, banque de questions, quiz, mode examen, préparation aux examens nationaux, analyse de compétences, recommandation, répétition espacée, planificateur, tuteur IA, gamification, compétitions, bibliothèque numérique ;

-   la **Marketplace scolaire contrôlée** (EcoShop Market) : un espace de vente encadré par le Global Service Groupe, où des vendeurs validés proposent aux élèves, parents, enseignants et personnels d\'encadrement des produits scolaires livrés directement à l\'établissement.

Ces trois composantes s\'appuient sur les mêmes comptes (élève, parent, enseignant), sur la même notion d\'établissement de rattachement, et sur des flux financiers et logistiques qui convergent au même point --- l\'école pour la marketplace et le transport, l\'établissement ou l\'élève lui-même pour les frais pédagogiques. Le chapitre 32 détaille précisément ces relations.

## **1.4 Objectifs du document**

-   Servir de référentiel fonctionnel unique et sans ambiguïté pour les équipes de conception et de développement, sur l\'ensemble du périmètre EcoShop désormais fusionné.

-   Définir précisément les rôles, permissions et parcours utilisateurs, y compris le parcours d\'authentification technique et les modes supervisés pour les publics jeunes (primaire, maternelle).

-   Documenter dans le détail l\'architecture du moteur OTP multicanal sur Supabase, du référentiel pédagogique multi-pays et du moteur de contenu/questions/recommandation.

-   Expliciter, pour chaque recoupement identifié entre EcoShop et EduRéussite, la décision de conception retenue et sa justification.

-   Établir les relations entre les différentes gestions afin de garantir la cohérence de l\'architecture de données unifiée.

-   Formuler les exigences non fonctionnelles nécessaires à un cahier de conception exhaustif, étendues à la protection des publics mineurs de la Maternelle au lycée.

-   Fournir une estimation actualisée du nombre d\'écrans à développer, un modèle économique consolidé, des indicateurs de succès et une feuille de route produit unifiée.

# **2. Présentation générale de EcoShop**

## **2.1 Vision produit**

EcoShop vise à digitaliser de bout en bout la gestion d\'un établissement scolaire privé --- et, au-delà, d\'un réseau d\'établissements --- tout en ouvrant des canaux de revenus complémentaires et des services à valeur ajoutée pour les familles : une marketplace scolaire encadrée, une offre d\'intelligence artificielle pédagogique et administrative, et, depuis la présente révision, un moteur complet de révision et de réussite scolaire (référentiel pédagogique multi-pays, banque de questions, quiz, examens blancs, tuteur IA, gamification). L\'application est pensée pour le contexte guinéen (paiement mobile, connectivité irrégulière, diversité des cycles scolaires --- crèche, maternelle, primaire, collège, lycée --- et des rythmes de composition) tout en restant configurable, dès sa conception, pour l\'ensemble des 16 pays de la CEDEAO puis pour l\'Afrique francophone au sens large (voir chapitre 6).

## **2.2 Public cible**

  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Segment**                                                                                                     **Usage principal**
  --------------------------------------------------------------------------------------------------------------- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Administrateur Global Service Groupe                                                                            Supervision multi-établissements, validation des établissements et des vendeurs, paramétrage de la plateforme, tarification

  Administrateur de contenu pédagogique                                                                           Création et validation du contenu de révision (cours, questions, activités Maternelle) via le CMS pédagogique, indépendamment de tout établissement (voir 30.5)

  Fondateur de réseau / Direction Générale (Siège)                                                                Création et pilotage d\'un réseau d\'établissements, vue consolidée sur les écoles membres

  Direction d\'établissement (Directeur, Proviseur, Censeur, Directeur des études, Chargé à l\'orientation\...)   Pilotage académique, administratif et financier de l\'établissement, gestion des services et des responsables, statistiques consolidées et concours internes

  Personnel administratif (secrétaire, comptable, surveillant, économe)                                           Opérations quotidiennes : inscriptions, caisse, réception de colis, discipline

  Enseignants, matrones et monitrices                                                                             Notes, cahier de texte, devoirs numériques, analyse de classe par compétence, présence, communication, congés, achats marketplace

  Parents                                                                                                         Suivi de la scolarité et de la progression de révision, paiement, achats marketplace, communication, suivi transport, autolimitation numérique de l\'enfant, console dédiée pour la Maternelle

  Élèves (de la Maternelle au lycée)                                                                              Révision, entraînement, examens blancs, notes officielles, emploi du temps, ressources pédagogiques, achats marketplace (selon âge/autorisation)

  Vendeurs / commerçants                                                                                          Vente de produits scolaires via la marketplace

  Chauffeurs (personnel de transport)                                                                             Démarrage de trajet et partage de position en temps réel
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Le chapitre 3 détaille les axes de différenciation retenus pour le volet révision et réussite scolaire, issus d\'une étude du marché des applications concurrentes actives en Afrique francophone.

## **2.3 Modèle de déploiement**

EcoShop est développée sous Flutter, avec deux cibles de déploiement :

-   **Application mobile (Android / iOS)**, destinée en priorité aux parents, élèves, enseignants, personnels d\'encadrement, chauffeurs et vendeurs --- usage nomade, mode hors ligne indispensable, y compris pour l\'intégralité du parcours de révision (voir chapitre 34).

-   **Application Windows**, destinée en priorité à l\'administration de l\'établissement, à la comptabilité et au back-office Global Service Groupe --- usage poste fixe, impression des reçus et documents, saisies volumineuses, CMS pédagogique.

Le choix Flutter permet de mutualiser une part significative de la base de code entre les deux cibles, tout en adaptant les parcours et la densité d\'information à chaque contexte d\'usage (voir chapitre 35).

L\'interface utilisateur (mobile et Web) constitue la couche de présentation du moteur d\'authentification décrit au chapitre 5 ; les deux cibles s\'appuient sur le même backend Supabase (Edge Functions et base de données Postgres) et sur le même mécanisme de session.

## **2.4 Principe de gratuité progressive**

L\'application reste gratuite pour un établissement jusqu\'à un effectif seuil d\'élèves inscrits ; au-delà, elle devient payante selon un barème indexé par tranche d\'effectif (abonnement Pro établissement, voir 17.7 et 36). Ce principe s\'applique indépendamment du modèle économique de la marketplace, qui repose sur des commissions et abonnements vendeurs, et indépendamment des abonnements de révision (Premium élève, IA admin, IA professeur, packs d\'examens), qui suivent chacun leur propre logique de facturation (voir chapitre 36).

> ***Règle de gestion ---** le seuil d\'effectif gratuit et le barème au-delà sont paramétrables côté back-office Global Service Groupe (chapitre 30) et ne sont jamais codés en dur dans l\'application cliente.*

## **2.5 Restrictions du mode gratuit**

En deçà du seuil d\'effectif, l\'établissement accède à EcoShop sans frais, mais certaines fonctionnalités premium restent verrouillées : personnalisation des thèmes graphiques (chapitre 31), personnalisation des templates de documents officiels (chapitre 18), paiement en ligne CinetPay des frais de scolarité (chapitre 17), et plus largement toute fonctionnalité identifiée comme génératrice de valeur ajoutée pour l\'établissement. Le passage en mode payant lève ces restrictions sans modification de l\'architecture ni des données déjà saisies.

> ***Règle de gestion ---** à l\'inverse, l\'accès aux fonctionnalités IA administratives (chat IA Directeur-Adviser, analyses groundées) suit un frais IA admin annuel indépendant du palier Pro : un établissement peut être en mode gratuit pour la licence de base et néanmoins souscrire au frais IA admin pour débloquer l\'IA (voir 17.7 et 36). Le volet révision (banque de questions, quiz, mode examen) reste, lui, accessible en offre FREE à tout élève quel que soit le statut de son établissement --- seule une partie de son contenu et de ses fonctionnalités avancées est réservée à l\'abonnement Premium élève (voir 21.4 et 36).*

# **3. Étude de marché et positionnement --- moteur de révision et de réussite**

Cette étude, héritée du cahier de conception EduRéussite, justifie les choix de conception du moteur de révision et de réussite scolaire intégré à EcoShop (chapitres 6 à 15 et 21 à 23). Elle porte spécifiquement sur le segment « application de révision scolaire », distinct du segment ERP scolaire sur lequel EcoShop n\'avait pas de concurrent frontal direct.

## **3.1 Panorama concurrentiel condensé**

  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Acteur**                                                             **Positionnement**                                                    **Limite identifiée pour le marché guinéen**
  ---------------------------------------------------------------------- --------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------
  Nomad Education (France)                                               Généraliste CP à Bac+5, contenu enseignants, mode hors ligne          Programme français adapté a posteriori, offre gratuite restreinte, paiement carte peu adapté au marché local

  Kalanso (Mali)                                                         Révision Bac, séries maliennes                                        Un seul pays et un seul examen terminal, pas de continuité collège→lycée, pas de brique enseignant/établissement

  Revizly (panafricain)                                                  Génération de fiches et QCM par IA à partir de photos                 Fonctionne en ligne uniquement, exclu des zones à connectivité faible

  Studirex (multi-pays)                                                  Bibliothèque de sujets d\'examens téléchargeables                     Aucun moteur adaptatif, aucun suivi de progression structuré

  Magoé Education (Guinée)                                               E-learning et gestion scolaire, plus de 100 établissements guinéens   Centré sur la gestion scolaire et la mise en relation des acteurs, pas sur un moteur de révision adaptatif par compétence

  Applications préscolaires généralistes (Binky Academy et similaires)   Jeux éducatifs 2-7 ans, suivi parental                                Références culturelles importées, achats intégrés peu compatibles mobile money, aucune conception pour la faible connectivité

  Africatik (RDC, programme opérateur)                                   Suite d\'applications certifiées maternelle à secondaire              Suite institutionnelle adossée à un opérateur unique plutôt qu\'éveil individualisé piloté par la famille
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## **3.2 Axes de différenciation retenus**

Douze axes structurants, directement traduits en règles de gestion dans les chapitres concernés :

-   Fidélité aux programmes nationaux réels, sur un référentiel pays réellement relationnel (chapitre 6).

-   Hors connexion réellement fonctionnel pour l\'apprentissage, l\'entraînement et l\'évaluation, pas seulement pour la consultation (chapitre 34).

-   Paiement adapté au marché : mobile money via CinetPay avant toute carte bancaire internationale (chapitre 17).

-   Continuité complète collège → lycée → concours sur un seul compte, historique de maîtrise par compétence jamais perdu (chapitre 14).

-   Écosystème à quatre acteurs interconnecté (élève, enseignant, parent, établissement) partageant la même base de compétences et de résultats, avec des droits différenciés --- déjà la logique du modèle de rôles EcoShop (chapitre 4).

-   Moteur de recommandation et répétition espacée natifs, dès le socle fonctionnel (chapitres 14 et 15).

-   IA pédagogique encadrée et validée par des enseignants : « IA génère → enseignant ou administrateur de contenu valide → publication » (chapitres 21 et 30).

-   Optimisation pour la faible connectivité et les terminaux d\'entrée de gamme : interface légère, téléchargement par paquets, aucune vidéo obligatoire (chapitre 34).

-   Alignement avec la dynamique de digitalisation institutionnelle guinéenne, ouvrant une voie de partenariat B2G à moyen terme (chapitres 28-30).

-   Compétitions et reconnaissance ancrées dans le contexte local : classements par établissement, ville, région, concours inter-écoles (chapitre 23).

-   Primaire traité comme un public à conception dédiée --- audio-first, formats simplifiés, gamification non comparative, compte rattaché à un parent par défaut --- non comme une déclinaison graphique du secondaire (chapitres 7, 9, 22).

-   Préscolaire pensé comme éveil localisé, hors connexion, entièrement piloté par le parent, sans aucune notion de score visible à l\'enfant (chapitres 7 et 9).

# **4. Gestion des rôles et des profils**

La gestion des rôles est le socle transversal de EcoShop : chaque module de gestion scolaire, chaque étape de la marketplace et chaque écran du moteur de révision s\'appuie sur la même matrice de permissions. Le relevé du code EcoShop distingue six rôles racines portés par le compte d\'authentification ; le cahier v1.2 décrivait une quinzaine de fonctions métier très fines ; EduRéussite, de son côté, distinguait cinq profils plus grossiers (Élève, Enseignant, Parent, Établissement, Administrateur) mais introduisait deux notions absentes d\'EcoShop v2.0 --- le compte élève supervisé pour les jeunes publics, et l\'administrateur de contenu pédagogique. Ce chapitre unifie les trois sources.

## **4.1 Modèle à deux niveaux : rôle racine et poste déclaré**

EcoShop distingue :

-   le **rôle racine**, porté par le compte Supabase Auth (attribut de la table \`profiles\`, recopié dans le jeton via le Custom Access Token Hook --- voir 5.6) et fixé à l\'authentification : Élève, Parent, Enseignant, Direction, Vendeur, Fondateur de réseau --- six valeurs, jamais davantage, car ce sont elles qui déterminent le canal d\'attribution du compte (auto-inscription ou invitation/demande, voir chapitre 5) ;

-   le **poste fonctionnel**, déclaré dynamiquement par l\'établissement au sein d\'un rôle racine, avec ses propres permissions fines : c\'est ainsi que Directeur, Proviseur, Censeur, Directeur des études, Chargé à l\'orientation, Secrétaire, Comptable, Surveillant général, Économe, Matrone et Monitrice existent tous **sous** le rôle racine « Direction », sans que le système n\'impose une liste figée.

> ***Règle de gestion ---** cette approche déclarative reprend et généralise le principe posé par la v1.2 (déclaration dynamique des niveaux et création dynamique des services, voir 4.5) : le modèle de rôles racine reste volontairement restreint à six valeurs pour ne pas complexifier le moteur d\'authentification, tandis que la richesse métier réelle d\'un établissement vit entièrement dans la couche « poste fonctionnel ». C\'est également ce modèle, plus rigoureux, qui prévaut sur la liste plate de profils d\'EduRéussite (Élève, Enseignant, Parent, Établissement, Administrateur) : chacun de ces cinq profils se retrouve dans le tableau des rôles racines ci-dessous, à l\'exception de l\'Administrateur de contenu pédagogique, absent du modèle EcoShop v2.0 et introduit en 4.4.*

## **4.2 Rôles racines**

  ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Rôle racine**       **Attribution**                                                                                           **Périmètre**
  --------------------- --------------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Élève                 Auto-inscription par code (voir 5.2), ou compte créé par un parent pour un élève du primaire (voir 4.3)   Consultation de ses notes, emploi du temps, révision et entraînement, ressources ; achats marketplace selon autorisation ; règlement de ses propres frais selon l\'âge

  Parent                Auto-inscription par code (voir 5.2)                                                                      Suivi de la scolarité et de la révision d\'un ou plusieurs enfants, paiement, achats marketplace, communication, suivi transport, Parent IA, console Maternelle

  Enseignant            Invitation par un établissement                                                                           Notes, cahier de texte, devoirs numériques, analyse de classe, emploi du temps, congés en auto-service, communication avec les classes suivies ; peut intervenir dans plusieurs établissements

  Direction             Invitation (rejoindre un établissement) ou demande de création d\'établissement                           Englobe tous les postes administratifs et d\'encadrement déclarés par l\'établissement (voir 4.1 et 4.5) : direction, secrétariat, comptabilité, surveillance, matrones, monitrices

  Vendeur               Demande de compte vendeur marketplace, indépendante de tout établissement                                 Gestion du catalogue et des commandes marketplace, indépendant de tout établissement scolaire

  Fondateur de réseau   Auto-déclaration lors de la création d\'un réseau                                                         Pilotage d\'un réseau scolaire, totalement indépendant de tout établissement au moment de la création ; devient opérationnellement la « Direction Générale / Siège » une fois le réseau constitué (voir chapitre 28)
  ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

L\'administrateur Global Service Groupe et l\'administrateur de contenu pédagogique ne sont pas des rôles racines du même ordre : ce sont des comptes de plateforme, distincts du modèle établissement, rattachés au Backoffice GSG (chapitre 30, voir 4.4).

## **4.3 Élève supervisé (primaire et Maternelle)**

En dessous d\'un seuil d\'âge paramétrable par pays (indicativement la fin du primaire), un compte Élève ne peut exister sans compte Parent associé actif : c\'est le mode **supervisé**.

-   Pour le primaire (CP1-CM2), le parent peut créer directement le compte de son enfant via un parcours dédié, avec création simultanée du compte parent superviseur si celui-ci n\'existe pas encore (voir 5.2).

-   Pour la Maternelle (Petite à Grande Section), il n\'existe pas de compte élève au sens propre : l\'enfant agit exclusivement à travers la console parent, sans identifiant ni accès autonome (voir 7.7 et 9.7).

> ***Règle de gestion ---** un compte élève en mode supervisé ne peut modifier ni son identité, ni son niveau, ni la supervision parentale elle-même ; seul le compte parent associé dispose de ces droits. Les fonctionnalités de communication et de classement public lui sont désactivées par défaut (voir 20.1 et 22.3). Cette règle, reprise du cahier EduRéussite (RG-002-03 et RG-025-04), s\'ajoute au mécanisme de liaison compte↔fiche déjà défini pour l\'ensemble des élèves (voir 5.6).*

## **4.4 Rôles de plateforme : Administrateur GSG et Administrateur de contenu pédagogique**

Deux comptes opèrent au niveau de la plateforme, sans rattachement à un établissement :

-   l\'**Administrateur Global Service Groupe**, déjà défini en v2.0 : validation des établissements, réseaux et vendeurs, paramètres globaux (chapitre 30) ;

-   l\'**Administrateur de contenu pédagogique**, rôle introduit par la fusion avec EduRéussite : responsable de la création et de la validation du contenu de révision (cours, questions, activités Maternelle) via le CMS pédagogique, sans droit de regard sur la gestion administrative, financière ou RH des établissements (voir 30.5).

> ***Règle de gestion ---** l\'Administrateur de contenu pédagogique dispose d\'un périmètre strictement borné au contenu : il ne peut ni consulter les données nominatives d\'un élève, ni intervenir sur la validation des établissements ou des vendeurs. Cette séparation des pouvoirs évite qu\'un rôle orienté production de contenu n\'hérite, par accumulation de privilèges, d\'un accès aux données personnelles qu\'il n\'a pas besoin de consulter --- principe de moindre privilège déjà posé en 34.1.*

## **4.5 Postes déclarés sous le rôle « Direction »**

  ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Poste**                                                **Périmètre d\'action principal**
  -------------------------------------------------------- ------------------------------------------------------------------------------------------------------------------------------------------------------------
  Directeur / administrateur d\'établissement              Paramétrage de l\'école, validation des inscriptions, création des services et attribution des responsables, accès à tous les modules de son établissement

  Directeur (primaire) / Proviseur (collège-lycée)         Pilotage pédagogique et administratif du ou des niveaux dont il a la charge

  Directeur des études, Censeur, Chargé à l\'orientation   Appui au proviseur pour le suivi pédagogique, la discipline et l\'orientation des élèves du secondaire

  Secrétaire                                               Inscriptions, dossiers élèves, édition de documents

  Comptable / caissier                                     Encaissements, reçus, cahier journal, budget, rapports financiers

  Surveillant général / économe                            Vie scolaire, discipline, réception des colis marketplace, cantine, internat

  Matrone                                                  Hygiène et vie quotidienne des tout-petits (crèche / maternelle), entretien des salles de classe

  Monitrice                                                Encadrement pédagogique des enfants de maternelle en salle de classe
  ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

> ***Règle de gestion ---** matrones et monitrices sont des postes distincts et ne doivent jamais être fusionnés sous une appellation générique unique (« encadreurs ») dans les listes de personnel : la matrone relève de l\'hygiène et du soin aux jeunes enfants, la monitrice de l\'encadrement pédagogique en classe de maternelle (voir 8.2).*

## **4.6 Déclaration des niveaux et création dynamique des postes**

Pour les établissements qui comptent plusieurs niveaux (crèche, maternelle, primaire, collège, lycée), les postes ne sont pas figés par le système mais déclarés au paramétrage : c\'est l\'administrateur de l\'établissement qui décide de l\'organisation réelle de son école.

-   Chaque niveau présent dans l\'établissement est déclaré dans les paramètres (chapitre 31), avec le ou les responsables qui lui sont attribués, en cohérence avec le référentiel pédagogique multi-pays (chapitre 6).

-   Lorsque l\'administrateur constate un besoin de service (par exemple un poste de comptable), il crée ce service et lui attribue un poste avec les droits correspondants --- cette création peut être assistée par l\'IA (suggestion de poste et de permissions) ou effectuée manuellement. Ce même patron « IA suggère → un humain valide » gouverne, à l\'échelle de la plateforme, la publication de contenu pédagogique (voir 30.5).

## **4.7 Principes transversaux de permission**

-   Un même établissement peut compter plusieurs comptes « Direction », mais un seul niveau « Administrateur Global Service Groupe » supra-établissement.

-   Un enseignant peut être rattaché à plusieurs établissements de la plateforme simultanément, avec un tableau de bord listant tous les établissements où il dispense des cours (voir 8.1).

-   Un champ ou une entité peut être ajouté par l\'administrateur d\'un établissement pour ses besoins propres, sans impacter les autres établissements de la plateforme.

-   Les droits de modification des notes officielles suivent un cycle de verrouillage progressif : saisie par l\'enseignant, remontée au responsable de service, verrouillage pour l\'enseignant, modification encore possible par le responsable, verrouillage définitif après proclamation des résultats de fin d\'année (voir 12.3) --- ce cycle ne s\'applique pas aux résultats d\'entraînement du moteur de révision, formatifs par nature (voir 12.6).

-   Toute action dans tout module est conditionnée par le rôle racine et, le cas échéant, le poste déclaré ; le module Authentification et sécurité (chapitre 5) est la source unique de vérité de ces permissions (table \`profiles\` et politiques Row Level Security, recopiées dans le jeton pour un contrôle rapide côté client), et ce contrôle est vérifié à chaque requête, jamais uniquement à l\'affichage de l\'écran (voir 34.1).

# **5. Authentification, identité fédérée et sécurité des comptes**

Ce chapitre remplace intégralement l\'architecture d\'authentification des versions précédentes de ce cahier --- un moteur OTP multicanal bâti sur des Edge Functions custom (génération et vérification du code côté serveur, puis échange d\'un lien magique via l\'API Admin Supabase). Cette révision 4.0 aligne EcoShop sur le modèle d\'authentification **natif** Supabase Auth désormais retenu comme référence unique pour l\'ensemble du portefeuille Global Service Groupe, et introduit l\'identité fédérée **GSG ID** portée par le **GSG Platform Kernel**. Le présent chapitre est autosuffisant : sa mise en œuvre ne requiert la lecture d\'aucun autre cahier de conception --- la section 5.11 en résume formellement le rattachement au noyau GSG, selon le gabarit d\'intégration commun à tous les cahiers produits du portefeuille.

## **5.1 Vue d\'ensemble du parcours de compte**

-   **Inscription par code (auto-service)** --- Élève et Parent sont les deux seuls rôles racines auto-inscriptibles : ils créent eux-mêmes leur compte via l\'authentification native Supabase Auth (signInWithOtp / verifyOtp), sur le canal de leur choix --- SMS, WhatsApp ou E-mail (voir 5.4).

-   **Sélection de rôle** --- après le premier code confirmé, le compte choisit son rôle racine parmi Élève et Parent uniquement ; les rôles à privilège (Enseignant, Direction, Vendeur, Fondateur de réseau) ne sont **jamais** auto-attribuables et renvoient systématiquement vers un parcours d\'invitation ou de demande (voir 5.3).

-   **Garde de session globale** --- toute route de l\'application est protégée par une vérification d\'authentification centrale ; la session est restaurée automatiquement au démarrage, sans nouvelle saisie de code tant que le jeton reste valide.

-   **Sélecteur d\'établissement actif** --- pour un compte rattaché à plusieurs établissements (Enseignant, Direction), un sélecteur permet de choisir l\'établissement sur lequel agir ; toutes les écritures et lectures sont ensuite scopées à cet établissement.

-   **Sélecteur d\'enfant** --- un Parent avec plusieurs enfants liés choisit l\'enfant actif pour consulter bulletins, absences, emploi du temps, révision, suivi transport, etc.

-   **Liaison compte élève ↔ fiche élève** --- un Parent (ou un Élève) relie son compte à la fiche administrative de l\'enfant via matricule + date de naissance (double facteur), avec protection anti-force-brute (voir 5.9).

> ***Règle de gestion ---** un même identifiant (numéro de téléphone ou adresse e-mail) ne peut être associé qu\'à un seul compte actif à la fois, tous rôles racines confondus. Avec l\'authentification native Supabase Auth, cette unicité n\'est plus garantie par une recherche de déduplication côté serveur applicatif : elle est assurée par construction, en réservant à chaque compte un seul identifiant canonique et en n\'ajoutant un second canal que par liaison explicite depuis une session déjà authentifiée (voir 5.4.4).*

## **5.2 Inscription auto-service (Élève, Parent)**

Le rôle Élève ou Parent est le seul point d\'entrée sans invitation préalable. L\'utilisateur saisit un identifiant (numéro de téléphone ou adresse e-mail), reçoit un code ou un lien via le canal choisi, le confirme, puis choisit son rôle. Une fois le compte créé :

-   s\'il a été inscrit au préalable par un tiers (établissement ou parent), il retrouve et rattache son compte à sa fiche existante via l\'identification décrite en 5.9 et 7.6 ;

-   sinon, il peut initier une demande d\'inscription à un établissement (voir 7.1) et, indépendamment, commencer à utiliser le moteur de révision en offre FREE sans établissement rattaché (voir 21.4).

Pour un élève du primaire, un parcours dédié « Créer le compte de mon enfant » permet au parent de créer directement le compte élève, avec création simultanée du compte parent superviseur si celui-ci n\'existe pas déjà. Ce parcours produit d\'emblée un compte en mode élève supervisé (voir 4.3) : l\'onboarding pédagogique (référentiel pays → niveau → classe → matières → objectif quotidien, voir chapitre 6) n\'est finalisé, pour un niveau primaire, qu\'une fois le compte parent associé et actif.

## **5.3 Onboarding des rôles à privilège**

Trois parcours distincts couvrent l\'ensemble des rôles non auto-inscriptibles :

  -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Parcours**                                       **Rôle concerné**                                            **Mécanique**
  -------------------------------------------------- ------------------------------------------------------------ ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Invitation à rejoindre un établissement existant   Enseignant, Direction (poste déclaré par l\'établissement)   L\'établissement invite un numéro/e-mail ; l\'invité confirme via l\'authentification native Supabase Auth, puis se voit attribuer le rôle et le poste prévus par l\'invitation

  Demande de création d\'un nouvel établissement     Direction (fondateur d\'établissement)                       Formulaire de création d\'école, validé par Global Service Groupe (voir 30.1) ; un courriel automatique confirme la soumission au demandeur

  Demande de compte Vendeur marketplace              Vendeur                                                      Indépendante de tout établissement, soumise à validation Global Service Groupe (identité, produits proposés, autorisation légale d\'exercer --- voir 30.1)
  -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Un quatrième cas, non redondant avec les trois parcours ci-dessus, existe pour le pilotage d\'un réseau, et un cinquième pour la production de contenu pédagogique :

-   **Réseau d\'établissements --- compte fondateur** : un utilisateur peut créer un compte « Fondateur de réseau » totalement indépendant de tout établissement, pour piloter un réseau scolaire (voir chapitre 28). Ce compte est également soumis à validation Global Service Groupe et n\'est jamais auto-attribué sans passer par le formulaire de création de réseau.

-   **Administrateur de contenu pédagogique** : compte de plateforme créé par invitation de Global Service Groupe, sans parcours d\'auto-inscription ni de demande, compte tenu du niveau de confiance requis pour publier du contenu pédagogique (voir 4.4 et 30.5).

## **5.4 Authentification native Supabase Auth --- architecture cible**

L\'ancienne architecture (Edge Functions sendOTP/verifyOTP, table Postgres dédiée aux codes, échange d\'un lien magique via l\'API Admin) réimplémentait, au niveau applicatif, des fonctions que Supabase Auth prend aujourd\'hui en charge nativement pour l\'ensemble des canaux utilisés par EcoShop. Cette révision retient donc le modèle de référence commun au portefeuille GSG (voir « GSG --- Modèle d\'authentification Supabase, migration Firebase → Supabase ») : deux points d\'entrée, quatre canaux, aucun stockage applicatif du code, aucune Edge Function intermédiaire pour l\'émission de la session.

### **5.4.1 Principe général : deux entrées, quatre canaux**

L\'utilisateur choisit d\'abord son identifiant --- **numéro de téléphone** ou **adresse e-mail** --- puis, pour le téléphone, le canal de réception du code. Les numéros de téléphone sont systématiquement saisis et validés au format international E.164 (indicatif + numéro, ex. +224XXXXXXXX), condition de fiabilité posée par le noyau GSG pour l\'ensemble des flux OTP de l\'écosystème (voir 5.5).

  ----------------------------------------------------------------------------------------------------------------------------------------------
  **Entrée**   **Canal**          **Appel Supabase**
  ------------ ------------------ --------------------------------------------------------------------------------------------------------------
  Téléphone    SMS (par défaut)   signInWithOtp({ phone }) puis verifyOtp({ phone, token, type: \'sms\' })

  Téléphone    WhatsApp           signInWithOtp({ phone, options: { channel: \'whatsapp\' } }) puis verifyOtp({ phone, token, type: \'sms\' })

  E-mail       Magic Link         signInWithOtp({ email, options: { emailRedirectTo } }) --- flux PKCE

  E-mail       Code OTP           signInWithOtp({ email }) puis verifyOtp({ email, token, type: \'email\' })
  ----------------------------------------------------------------------------------------------------------------------------------------------

Dans les quatre cas, l\'appel \`verifyOtp()\` renvoie directement une session Supabase Auth complète (jeton d\'accès + jeton de rafraîchissement) : il n\'existe plus d\'étape d\'échange intermédiaire ni de jeton propriétaire à faire transiter par une Edge Function. Le parcours rejoint ensuite le socle commun décrit en 5.1 : garde de session globale, sélection de rôle si premier accès, sélecteurs d\'établissement et d\'enfant.

### **5.4.2 Branche Téléphone --- SMS et WhatsApp**

-   **Choix A --- Réception par SMS** : Supabase Auth envoie un code à 6 chiffres via le provider SMS configuré (Twilio, recommandé pour sa couverture WhatsApp conjointe).

-   **Choix B --- Réception par WhatsApp** : même appel \`signInWithOtp()\`, avec \`options.channel = \'whatsapp\'\`. Nécessite un compte Twilio avec le canal WhatsApp activé (numéro WhatsApp Business approuvé par Meta).

> // Envoi du code (SMS ou WhatsApp)\
> const { error } = await supabase.auth.signInWithOtp({\
> phone: \'+224620000000\',\
> options: { channel: \'sms\' } // ou \'whatsapp\'\
> });\
> \
> // Vérification du code saisi par l\'utilisateur\
> const { data, error } = await supabase.auth.verifyOtp({\
> phone: \'+224620000000\',\
> token: \'123456\',\
> type: \'sms\'\
> });

**Option avancée, non retenue par défaut** --- pour un contrôle total du template WhatsApp ou une intégration directe avec l\'API Meta Cloud (hors Twilio), une Edge Function dédiée reste une voie de repli possible ; elle n\'est activée que si un besoin métier précis le justifie, jamais comme mécanisme par défaut.

> ***Règle de gestion ---** conformément à l\'addendum du 26/08/2026 du modèle d\'authentification commun au portefeuille GSG, le numéro transmis à signInWithOtp()/verifyOtp() doit être pré-normalisé au format E.164 côté client, avant l\'appel --- jamais par concaténation ad hoc de l\'indicatif et du numéro local au moment de l\'appel lui-même. EcoShop retient PharmaConnect comme référence portefeuille pour cette séparation : un sélecteur d\'indicatif pays dédié (PhoneInputField) alimente un point de normalisation unique (Validators.normalizeE164()) avant tout appel Supabase, sans modification du flux décrit ci-dessus --- uniquement une garantie de format en amont, déjà exigée par le profil utilisateur GSG ID (KER-ID-06, GSG Platform Kernel v3.0, section 3) et par le principe posé en 5.4.1.*

### **5.4.3 Branche E-mail --- Magic Link et code OTP**

Lorsque l\'utilisateur saisit son adresse e-mail, il reçoit son accès directement, sans passer par un réseau télécom ni par un coût d\'envoi SMS --- canal à privilégier chaque fois que le contexte le permet (voir 5.10).

-   **Mode Magic Link** : l\'utilisateur reçoit un lien cliquable qui le connecte directement (flux PKCE recommandé pour les apps mobiles/SPA).

-   **Mode Code OTP e-mail** : même mécanisme, mais le template d\'e-mail est personnalisé pour afficher un code à 6 chiffres ({{ .Token }}) que l\'utilisateur saisit manuellement --- mode à privilégier pour l\'expérience mobile.

> // Magic Link\
> await supabase.auth.signInWithOtp({\
> email: \'user@ecoshop.gsg\',\
> options: { emailRedirectTo: \'https://app.ecoshop.gsg/callback\' }\
> });\
> \
> // Code OTP e-mail (nécessite un template personnalisé avec {{ .Token }})\
> await supabase.auth.signInWithOtp({ email: \'user@ecoshop.gsg\' });\
> const { data, error } = await supabase.auth.verifyOtp({\
> email: \'user@ecoshop.gsg\',\
> token: \'123456\',\
> type: \'email\'\
> });

### **5.4.4 Unicité du compte et liaison multi-canal**

Contrairement à l\'ancien moteur, qui recherchait explicitement un utilisateur existant via l\'API Admin avant toute création, l\'authentification native Supabase Auth crée par défaut un nouvel utilisateur \`auth.users\` à la première vérification réussie d\'un identifiant qui n\'est associé à aucun compte --- y compris lorsque la même personne possède déjà un compte vérifié sur un autre canal. Cette différence de comportement appelle une règle de conception explicite.

> ***Règle de gestion ---** l\'identifiant utilisé lors de la toute première authentification d\'un utilisateur devient l\'identifiant canonique de son compte. L\'ajout d\'un second identifiant (par exemple un e-mail sur un compte créé par téléphone) ne passe jamais par un nouvel appel anonyme à signInWithOtp() sur ce second identifiant : il s\'effectue exclusivement depuis une session déjà authentifiée, via la mise à jour du profil Supabase Auth (liaison d\'identité), de sorte qu\'un seul et même utilisateur \`auth.users\` porte in fine les deux identifiants. L\'écran « Ajouter un e-mail / un numéro de secours » du profil utilisateur est le seul point d\'entrée de cette liaison.*

### **5.4.5 Configuration côté tableau de bord Supabase**

-   **Authentication \> Providers \> Phone** : activer, choisir le provider SMS (Twilio recommandé) et renseigner les identifiants API ; activer le canal WhatsApp dans les paramètres du provider Twilio.

-   **Authentication \> Providers \> Email** : activer, puis personnaliser les templates (Magic Link et Code OTP e-mail) dans Authentication \> Email Templates.

-   **Rate limiting et CAPTCHA** : limites de fréquence par identifiant et par IP, et intégration hCaptcha/Turnstile, configurées au niveau du projet Supabase (Authentication \> Rate Limits) --- voir 5.10.

-   **URL de redirection** : \`emailRedirectTo\` et URL autorisées déclarées dans Authentication \> URL Configuration, une entrée par environnement (mobile, Windows/Web, développement, production).

Ces réglages relèvent désormais de la configuration du projet Supabase, gérée par l\'équipe technique GSG, et non plus d\'une table applicative dédiée : ils remplacent l\'ancienne table \`otp_requests\` et la tâche de purge périodique qui lui était associée, retirées de cette révision.

## **5.5 Identité fédérée GSG ID (GSG Platform Kernel)**

L\'authentification propre à EcoShop, décrite en 5.4, reste seule responsable de la connexion des utilisateurs et fonctionne de façon totalement autonome : une indisponibilité de GSG ID ne bloque jamais la connexion à EcoShop (principe KER-ARC-03 et KER-VIS-04 du GSG Platform Kernel). L\'identité fédérée GSG ID décrite ici est une couche **additive**, jamais un remplacement du mécanisme de 5.4.

-   **Principe** --- une fois la session Supabase Auth d\'EcoShop établie, un traitement asynchrone présente le jeton signé (JWT) à GSG ID. GSG ID ne génère ni ne vérifie jamais lui-même un code OTP ; il vérifie la signature de ce jeton via le JWKS du projet Supabase d\'EcoShop, inscrit sur une liste blanche stricte de projets autorisés, puis résout ou crée le profil GSG ID correspondant.

-   **Déclenchement** --- un trigger Postgres sur \`auth.users\` (insertion ou mise à jour), ou une Edge Function programmée, appelle le point de fédération de GSG ID sans jamais bloquer ni ralentir le parcours de connexion décrit en 5.4.

-   **Stockage** --- une colonne nullable \`gsg_id\` (uuid) est ajoutée à la table \`profiles\` (voir 5.6) : ajout strictement additif, sans restructuration ni suppression d\'aucune donnée existante.

-   **Usage à ce stade** --- la fédération alimente la supervision transverse du portefeuille GSG (audit centralisé, chapitre 30) ; l\'authentification unique (SSO) vers d\'autres produits GSG reste une option future, proposée à côté du parcours existant, jamais imposée aux comptes déjà actifs (voir 5.11).

-   **Authentification multifacteur** --- les canaux OTP d\'EcoShop constituent déjà un facteur de possession ; aucune couche MFA supplémentaire du noyau n\'est requise à ce stade, une réévaluation restant possible pour les rôles Direction et Administrateur GSG.

> ***Règle de gestion ---** le référentiel géographique porté par le profil GSG ID (pays, devise, langue, fuseau horaire) et le référentiel pédagogique multi-pays d\'EcoShop (chapitre 6, domaine « education ») sont complémentaires et ne se recouvrent pas : le premier qualifie l\'utilisateur, le second qualifie le contenu scolaire consommé. Cette révision ne migre pas le chapitre 6 vers le moteur générique du GSG Platform Kernel (Referential Engine) ; cette question, distincte de l\'authentification, reste hors périmètre et ferait l\'objet d\'un document de migration dédié si elle était un jour engagée.*

## **5.6 Table profiles, rôle racine et Custom Access Token Hook**

Les attributs métier (rôle racine, poste déclaré, établissement rattaché, identité fédérée GSG ID) ne sont jamais stockés dans le jeton lui-même à l\'émission : ils vivent dans une table Postgres \`profiles\`, protégée par Row Level Security, qui reste la source de vérité. Un **Custom Access Token Hook** (fonction Postgres exécutée par Supabase Auth à chaque émission ou rafraîchissement de jeton) recopie ces attributs dans le jeton d\'accès pour un contrôle rapide côté client et côté politiques RLS ; ce recopiage n\'a lieu qu\'après attribution explicite du rôle (5.2/5.3), jamais par défaut --- un utilisateur nouvellement créé ne porte donc aucun privilège avant sélection de rôle. Cette table \`profiles\`, et non le contenu du jeton, fait foi à chaque vérification serveur (voir 4.7 et 34.1).

## **5.7 Session et multi-appareils**

-   La session est restaurée automatiquement au démarrage tant que le jeton de rafraîchissement Supabase reste valide ; son renouvellement est géré nativement par le SDK client Supabase (\`supabase_flutter\`).

-   Un compte peut être connecté simultanément sur plusieurs appareils (par exemple un parent sur mobile et sur Windows) ; il n\'existe pas de verrou de session unique.

-   La révocation d\'une session à distance (déconnexion forcée de tous les appareils, en cas de compte compromis) s\'appuie sur \`admin.signOut(userId, scope: \'global\')\`, disponible depuis le Backoffice GSG et depuis le profil du compte lui-même (voir 30.6).

## **5.8 Récupération de compte**

N\'existant sur EcoShop aucune notion de mot de passe (authentification exclusivement par code ou lien à usage unique), la récupération de compte se confond avec une nouvelle vérification : un utilisateur ayant perdu l\'accès à son appareil se réauthentifie simplement en redemandant un code sur son identifiant canonique (voir 5.4.4), qui rejoint automatiquement sa session Supabase existante. Ce choix évite par construction toute la surface de risque associée à la récupération de mot de passe (questions secrètes, liens de réinitialisation piratables).

## **5.9 Liaison compte ↔ fiche existante**

Un élève peut être inscrit dans une école de la plateforme par un tiers (établissement ou parent) sans s\'être lui-même authentifié au préalable. Lors de sa première connexion, l\'élève (ou le parent) doit pouvoir retrouver et rattacher son compte à son établissement.

-   Rattachement par **matricule + date de naissance** (double facteur), avec protection anti-force-brute (verrouillage temporaire après un nombre limité d\'essais infructueux).

-   Rattachement alternatif par le **numéro de téléphone du parent** déjà connu du dossier élève, ou par l\'**identifiant généré** décrit en 7.6.

> ***Règle de gestion ---** le rattachement compte↔fiche est un point de convergence critique entre le module Authentification et le module Administration/Scolarité (chapitre 7) : c\'est l\'identifiant généré ou le matricule qui permet à un compte créé après coup de retrouver une fiche préexistante, sans jamais dupliquer l\'élève dans le système.*

## **5.10 Sécurité, conformité et points de vigilance**

-   **Aucun code en clair** --- Supabase Auth génère, stocke et vérifie les codes OTP en interne ; EcoShop ne journalise, ne stocke ni ne manipule jamais le code lui-même, une amélioration de sécurité directe par rapport à l\'ancien moteur applicatif.

-   **Gestion des secrets** --- clés du provider SMS/WhatsApp (Twilio), clé du provider e-mail (Resend ou équivalent SMTP), clé CinetPay, clé service role Supabase, et secret client GSG ID, stockées dans le coffre-fort de secrets des Edge Functions et dans les paramètres du projet Supabase, jamais en dur dans le code client ni dans un dépôt de code ; rotation périodique documentée.

-   **Rate limiting et anti-force-brute** --- désormais assurés nativement au niveau du projet Supabase Auth (Authentication \> Rate Limits) et par CAPTCHA (hCaptcha/Turnstile) plutôt que par une table applicative dédiée ; les seuils sont ajustés par l\'équipe technique GSG selon les besoins UX de chaque application du portefeuille (voir 5.4.5).

-   **Coût** --- la branche téléphone (SMS et WhatsApp) est facturée par le provider (Twilio) ; la branche e-mail reste gratuite et instantanée --- à privilégier quand le contexte le permet (voir 5.4.3).

-   **Délai d\'expiration** --- par défaut 60 secondes entre deux demandes et 1 heure de validité du code ou du lien, ajustables côté tableau de bord Supabase selon les besoins UX d\'EcoShop.

-   **Réglementation locale** --- certains pays imposent des règles spécifiques sur l\'envoi de SMS/WhatsApp ; la conformité est vérifiée pays par pays au fil de la trajectoire d\'expansion du référentiel pédagogique (voir 6.5), en commençant par la Guinée.

-   **Cohérence multi-application** --- ce modèle (deux entrées, quatre canaux, aucune Edge Function intermédiaire) est la référence unique pour l\'ensemble des applications du portefeuille Global Service Groupe utilisant Supabase ; EcoShop en est le premier adoptant complet.

-   **Vérification serveur systématique** --- toute vérification de permission s\'exécute côté serveur à chaque requête, jamais uniquement à l\'affichage de l\'écran côté client, y compris pour la fédération GSG ID (voir 4.7 et 34.1).

## **5.11 Intégration au GSG Platform Kernel --- synthèse**

Conformément au gabarit d\'intégration Kernel commun à tous les cahiers de conception produits du portefeuille GSG (voir GSG Platform Kernel --- Cahier de conception v3.0, section 19), cette section synthétise le rattachement d\'EcoShop au noyau.

  -------------------------------------------------------------------------------------------------------------------------------------------------
  **Brique du noyau**                    **Statut pour EcoShop**
  -------------------------------------- ----------------------------------------------------------------------------------------------------------
  GSG ID (identité fédérée)              Oui --- fédération additive décrite en 5.5, sans remplacement de l\'authentification native (5.4)

  Org Registry (gsg_org_id)              Préparé, non activé --- colonne réservée sur établissement et réseau (chapitre 28), non encore peuplée

  GSG Referential (pays/devise/langue)   Non consommé à ce stade

  GSG Referential Engine                 Non consommé --- le référentiel pédagogique multi-pays d\'EcoShop (chapitre 6) conserve son schéma dédié

  Bus d\'événements inter-produits       Non consommé à ce stade --- événements candidats identifiés ci-dessous

  Audit centralisé                       Non consommé à ce stade

  Billing Core                           Non, par défaut (brique différée du noyau)

  Design System GSG                      Non, par défaut (brique non généralisée)
  -------------------------------------------------------------------------------------------------------------------------------------------------

**Cartographie des champs hérités du référentiel**

-   \`profiles.gsg_id\` (uuid, nullable) --- correspondance vers le profil GSG ID, alimentée par la fédération décrite en 5.5.

-   \`etablissement.gsg_org_id\` et \`reseau.gsg_org_id\` (uuid, nullable, chapitre 28) --- réservés pour un rattachement futur à l\'Org Registry, non encore peuplés.

**Événements candidats** (non branchés au lancement, publiables sur le bus le jour où l\'intégration est activée, sans jamais bloquer le fonctionnement autonome d\'EcoShop --- KER-EVT-02) : \`compte.cree\`, \`compte.role_attribue\`, \`etablissement.valide\`, \`abonnement.active\`.

**État au moment de la rédaction** --- EcoShop est, à ce jour, le seul produit du portefeuille GSG déjà en production. Pour le seul module Authentification/Identité, le présent chapitre constitue le document d\'intégration a posteriori prévu par la règle KER-INT-03 du noyau : cartographie des champs ci-dessus, bascule additive et non bloquante (KER-ID-03), sans fenêtre de service ni migration de données existantes --- les colonnes ajoutées sont nullables et inertes tant que la fédération n\'est pas explicitement activée. L\'intégration des autres briques du noyau (Referential Engine, bus d\'événements, audit) reste hors périmètre de cette révision et ferait l\'objet d\'une décision et d\'une documentation dédiées ultérieures, conformément aux règles KER-VIS-06 et KER-INT-03.

# **6. Référentiel pédagogique multi-pays**

Ce chapitre remplace, comme référentiel structurant, la simple liste déclarative de cycles (crèche, maternelle, primaire, collège, lycée) qui suffisait à EcoShop v2.0 tant que la plateforme ne visait que la Guinée. L\'ambition d\'extension à l\'ensemble de la zone UEMOA puis CEDEAO, déjà annoncée en v2.0 mais non outillée, était en revanche au cœur de la conception d\'EduRéussite : son schéma relationnel, structurellement supérieur à la simple liste déclarative, est ici adopté comme fondation commune à la fois du module Scolarité (chapitre 7) et du moteur de révision (chapitres 9 à 15).

> ***Règle de gestion ---** c\'est le référentiel EduRéussite qui l\'emporte sur ce point précis, non par ancienneté mais par supériorité structurelle : une hiérarchie unique mêlant l\'année scolaire aux cycles et aux classes, telle qu\'esquissée par la simple liste déclarative d\'EcoShop v2.0, obligerait à redéfinir l\'intégralité de la structure d\'un pays à chaque rentrée. Le référentiel adopté ici découple ce qui change rarement (structure d\'un système éducatif) de ce qui se renouvelle chaque année (contenu pédagogique).*

## **6.1 Principe de conception : découplage référentiel / contenu versionné**

Le référentiel pédagogique multi-pays repose sur un principe unique : séparer strictement ce qui décrit la structure d\'un système éducatif (cycles, classes, examens, filières --- données qui changent rarement) de ce qui décrit le contenu pédagogique d\'une année scolaire donnée (programme, matières, chapitres --- données qui se renouvellent chaque année).

Le référentiel structurel (pays, cycle, niveau, examen, filière) est donc modélisé indépendamment du temps, tandis que le contenu pédagogique s\'organise sous un programme officiel explicitement versionné par pays et par année scolaire, qui vient s\'y rattacher. Cette séparation permet d\'ajouter un nouveau pays --- y compris un pays de structure radicalement différente (système anglophone WAEC, lusophone, ou arabophone-francophone bilingue) --- sans modifier une seule ligne de code, en se limitant à l\'ajout de données dans les tables du référentiel structurel.

## **6.2 Schéma relationnel du référentiel structurel**

Sept entités constituent le référentiel structurel, stable et indépendant du temps. Le contenu pédagogique (programme, matières, chapitres, leçons, compétences, exercices --- voir chapitres 9 et 10) s\'y rattache sans jamais le modifier.

  ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Table**            **Rôle**                                                                                                                            **Champs clés**
  -------------------- ----------------------------------------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  pays                 Décrit un système éducatif national dans son ensemble                                                                               code_iso, nom, type_systeme (francophone_cfa / anglophone_waec / lusophone / arabophone_mixte), langue_enseignement_principale, organisme_examinateur, statut_deploiement

  pays_cycle           Décrit un cycle scolaire d\'un pays donné (préscolaire, primaire, secondaire 1er cycle, secondaire 2nd cycle)                       pays_id, code, nom_local, duree_annees, age_entree_theorique, grade_level_debut/fin

  pays_niveau          Unité atomique du référentiel : une classe, avec son appellation locale et sa normalisation inter-pays                              pays_cycle_id, appellation_locale, grade_level_normalise (entier continu et unique par pays), age_theorique_min/max, ordre, est_niveau_examinateur, filiere_id (nullable)

  pays_examen          Décrit un examen national ou régional reconnu, rattaché à une classe terminale précise                                              pays_niveau_id (où est_niveau_examinateur = vrai), nom/sigle, organisme_certificateur, obligatoire_pour_niveau_suivant

  pays_filiere         Filière du second cycle secondaire uniquement (séries francophones, ou électives anglophones WAEC)                                  pays_id, code/nom

  programme_officiel   Contenu pédagogique d\'un pays pour une année scolaire donnée --- c\'est ici, et ici seulement, que le temps entre dans le modèle   pays_id, annee_scolaire, version, statut (brouillon/publié/archivé), date_publication

  programme_matiere    Rattache une matière à un programme officiel, à une classe et, si applicable, à une filière                                         programme_officiel_id, pays_niveau_id, filiere_id (nullable), nom_matiere, coefficient, volume_horaire_hebdo
  ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## **6.3 Deux chaînes de hiérarchie distinctes**

Chaîne du référentiel structurel (stable) : **PAYS → CYCLE → NIVEAU (CLASSE) → EXAMEN / FILIÈRE**.

Chaîne du contenu pédagogique (versionnée par année scolaire) : **PROGRAMME OFFICIEL (PAYS + ANNÉE SCOLAIRE) → MATIÈRE → CHAPITRE → LEÇON → COMPÉTENCE → EXERCICE / QUESTION**.

## **6.4 Référentiel des 16 pays de la CEDEAO**

Le tableau ci-dessous applique le schéma relationnel aux 16 pays de la CEDEAO. La colonne « Confiance » indique le niveau de fiabilité de la donnée à la date de rédaction : les lignes « Moyenne » appellent une vérification sur source ministérielle avant intégration au référentiel de production.

  -------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Pays**         **Système**                       **Primaire / Examen**                              **Collège / Examen**                          **Confiance**
  ---------------- --------------------------------- -------------------------------------------------- --------------------------------------------- ---------------
  Guinée           Francophone CFA                   6 ans (CP1→CM2) --- CEPE                           4 ans (7e→10e) --- BEPC                       Élevée

  Sénégal          Francophone CFA                   6 ans (CI→CM2) --- CFEE                            4 ans (6e→3e) --- BFEM                        Élevée

  Côte d\'Ivoire   Francophone CFA                   6 ans (CP1→CM2) --- CEPE                           4 ans (6e→3e) --- BEPC                        Élevée

  Mali             Francophone CFA                   6 ans (1er cycle fondamental) --- CEP              3 ans (7e-9e) --- DEF                         Moyenne

  Burkina Faso     Francophone CFA                   6 ans (CP1→CM2) --- CEP                            4 ans (6e→3e) --- BEPC                        Moyenne

  Niger            Francophone CFA                   6 ans --- CFEPD / CEP                              4 ans (6e→3e) --- BEPC                        Moyenne

  Bénin            Francophone CFA                   6 ans (CI→CM2) --- CEP                             4 ans (6e→3e) --- BEPC                        Moyenne

  Togo             Francophone CFA                   6 ans --- CEPD                                     4 ans (6e→3e) --- BEPC                        Moyenne

  Ghana            Anglophone WAEC                   6 ans (P1-P6, « Basic Education »)                 3 ans (JHS1-3) --- BECE                       Élevée

  Nigeria          Anglophone WAEC                   6 ans (Primary 1-6)                                3 ans (JSS1-3) --- BECE/JSCE                  Élevée

  Sierra Leone     Anglophone WAEC                   6 ans --- NPSE                                     3 ans (JSS1-3) --- BECE                       Élevée

  Liberia          Anglophone WAEC                   6 ans (Grade 1-6) --- LPSCE                        3 ans (Grade 7-9) --- LJHSCE                  Élevée

  Gambie           Anglophone WAEC                   6 ans (Lower Basic)                                3 ans (Upper Basic, cumul 9 ans) --- GABECE   Élevée

  Guinée-Bissau    Lusophone                         Ensino Básico unifié 9 ans (3 ciclos)              voir colonne Primaire                         Moyenne

  Cap-Vert         Lusophone                         Ensino Básico 8 ans (2 ciclos, 1º-8º ano)          voir colonne Primaire                         Élevée

  Mauritanie       Arabophone-francophone bilingue   6 ans (fondamental) --- Concours d\'entrée en 7e   4 ans (7e→10e) --- BEPC                       Moyenne
  -------------------------------------------------------------------------------------------------------------------------------------------------------------------

Sauf mention contraire, le second cycle secondaire dure 3 ans et se conclut par un baccalauréat national (zone francophone/arabophone) ou le WASSCE (zone anglophone WAEC), à l\'exception du Cap-Vert (Ensino Secundário de 4 ans, 9º-12º ano).

> ***Règle de gestion ---** la Guinée-Bissau et le Cap-Vert regroupent le primaire et le collège en un seul bloc « Ensino Básico » (respectivement 9 et 8 ans) sans rupture d\'examen intermédiaire ; la répartition primaire/collège du tableau y est donc indicative plutôt que structurelle, et doit se traduire dans le référentiel par un seul pays_cycle « primaire » couvrant ces années plutôt que deux cycles distincts. Plus généralement, un pays_examen ne peut être créé que pour un pays_niveau dont l\'attribut est_niveau_examinateur est vrai, et une pays_filiere ne peut être associée qu\'à un pays_niveau du cycle secondaire_2 : aucun examen n\'est jamais rattaché à une classe intermédiaire, aucune filière n\'existe au primaire, au collège ou en Maternelle.*

## **6.5 Trajectoire d\'extension géographique**

  ------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Phase**                  **Pays**
  -------------------------- ---------------------------------------------------------------------------------------------------------------------------------
  Lancement                  Guinée

  Extension régionale        Côte d\'Ivoire, Sénégal, Mali

  Extension étendue          Burkina Faso, Niger, Bénin, Togo

  Extension CEDEAO élargie   Ghana, Nigeria, Sierra Leone, Liberia, Gambie, Guinée-Bissau, Cap-Vert, Mauritanie (systèmes anglophone, lusophone, arabophone)

  Extension continentale     Cameroun, RDC, autres pays francophones
  ------------------------------------------------------------------------------------------------------------------------------------------------------------

Les pays de systèmes anglophone, lusophone et arabophone impliquent une adaptation de conception distincte de celle déjà validée pour le socle francophone CFA (organisme certificateur régional WAEC, filières électives différentes, absence d\'examen isolé de fin de primaire dans certains pays) : ils sont regroupés dans une phase d\'extension dédiée plutôt que fondus dans la trajectoire francophone. Le programme guinéen 2026-2027 constitue le premier jeu de données réel, validé par des enseignants locaux, avant toute extension (voir 30.5).

## **6.6 Non-régression, isolation et gouvernance du référentiel**

-   **Non-régression des programmes** --- la publication d\'une nouvelle version d\'un programme officiel n\'affecte pas les résultats et statistiques déjà calculés sur une version antérieure.

-   **Isolation par pays** --- le contenu, les questions et les résultats d\'un pays ne sont jamais mélangés avec ceux d\'un autre pays dans les statistiques et classements nationaux (voir 20.1 et 23.1).

-   **Découplage référentiel / contenu** --- une nouvelle année scolaire ne peut jamais entraîner de modification des tables pays_cycle ou pays_niveau ; seule la création d\'un nouveau programme_officiel est requise.

-   **Unicité du grade_level normalisé** --- chaque pays_niveau dispose d\'un grade_level_normalise unique et continu au sein de son pays, condition des comparaisons et migrations inter-pays ; ce champ n\'est jamais affiché à l\'utilisateur, seule l\'appellation locale l\'est.

La gestion opérationnelle du référentiel (ajout d\'un pays, d\'un cycle, d\'un niveau, d\'un examen, d\'une filière, versionnage annuel d\'un programme officiel) est un back-office réservé à l\'Administrateur Global Service Groupe et à l\'Administrateur de contenu pédagogique (voir 4.4 et 30.5), jamais une opération accessible à un établissement individuel.

# **7. Module --- Gestion administrative et scolarité**

## **7.1 Inscription et réinscription**

-   Demande d\'inscription initiée par l\'élève ou le parent via un formulaire, adressée à un établissement choisi sur la plateforme.

-   Recherche et réinscription d\'un élève par le numéro de téléphone du parent, qui fait apparaître tous les élèves rattachés à ce numéro.

-   **Inscription d\'un nouvel élève** : création de la fiche élève avec génération automatique du matricule et de l\'identifiant (voir 7.6), gestion des dossiers (acte de naissance, photos, certificats), détection de double inscription, et blocage automatique au-delà du seuil d\'effectif gratuit (sauf établissement Pro, voir 2.4).

-   Inscriptions par masse (import Excel --- voir 7.5).

-   **Réinscription annuelle** : reconduction d\'un élève d\'une année sur l\'autre, avec vérification automatique des impayés de l\'année précédente, d\'une éventuelle sanction en cours et du statut boursier de l\'année à venir.

> ***Règle de gestion ---** un même élève ne peut pas appartenir à deux établissements différents au cours d\'une même année scolaire. Si l\'élève est déjà inscrit dans l\'établissement A et qu\'un agent tente de l\'inscrire dans l\'établissement B, le système avertit cet agent, avant validation, que l\'élève est déjà inscrit dans l\'établissement A pour cette même année. Si l\'agent confirme malgré tout l\'inscription, celle-ci est validée et une notification est envoyée à l\'établissement A, à condition que celui-ci n\'ait pas déjà annulé l\'inscription de son côté. Cette règle s\'applique à tous les établissements de la plateforme, qu\'ils soient indépendants ou membres d\'un réseau non harmonisé (voir chapitre 28).*

Un élève peut être inscrit par un tiers sans s\'être lui-même authentifié au préalable ; lors de sa première connexion, il retrouve et rattache son compte à son établissement via le parcours décrit en 5.7. Pour un élève du primaire, le parcours « Créer le compte de mon enfant » (voir 5.2) permet également au parent d\'inscrire directement son enfant en mode supervisé (voir 4.3).

## **7.2 Échéances de paiement et statut boursier**

-   **Échéances de paiement configurables** : l\'établissement définit des paliers de paiement (mensuel, trimestriel, etc.) par modalité, avec dates et pourcentages --- pré-remplis à chaque inscription mais ajustables au cas par cas.

-   **Statut boursier** : un élève peut être déclaré boursier pour une année scolaire précise (et non de façon permanente), avec traçabilité de qui a fait le changement et quand.

> ***Règle de gestion ---** les échéances de paiement configurables sont un repère indicatif, non une barrière : le paiement effectif reste libre et progressif (voir 17.1), sans jamais bloquer ou pénaliser un retard sur une échéance. Ce point corrige une ambiguïté de la version précédente du cahier, qui laissait entendre que les tranches conditionnaient l\'accès aux services.*

## **7.3 Classes, cycles, filières et années académiques**

La déclaration des cycles, classes, examens et filières d\'un établissement s\'appuie désormais sur le référentiel pédagogique multi-pays (chapitre 6) plutôt que sur une simple liste plate : chaque établissement sélectionne, parmi les pays_niveau du pays où il opère, les classes qu\'il propose réellement.

-   Paramétrage des cycles présents dans l\'établissement (préscolaire, primaire, secondaire 1er cycle, secondaire 2nd cycle, selon la nomenclature du pays_cycle du pays concerné) --- avec ou sans cantine, ce paramétrage conditionnant l\'activation des modules correspondants (voir chapitre 19).

-   Gestion des classes, cycles, filières, affectation des élèves dans les classes ; chaque classe est rattachée à un pays_niveau donné, dont l\'appellation locale (ex. « CM2 ») est celle affichée à l\'utilisateur.

-   Une classe peut être répartie sur une ou plusieurs salles physiques (gestion des groupes pédagogiques au sein d\'une même classe).

-   Gestion des années académiques, avec verrouillage des données d\'une année après la proclamation des résultats de fin d\'année.

-   Chaque classe hérite de l\'attribut **est_niveau_examinateur** de son pays_niveau (classe d\'examen ou classe intermédiaire), afin que le système sache où exiger la mention finale avant la proclamation (voir 12.3 et 12.4) et où proposer les espaces de préparation aux examens nationaux (voir chapitre 13).

## **7.4 Historique scolaire**

-   Transferts, redoublements, exclusions.

-   À la réinscription, vérification automatique : élève redevable de l\'année écoulée, admission ou non en classe supérieure, élève soumis à une sanction disciplinaire, statut boursier.

-   Passage automatique à la crèche et à la maternelle : un élève inscrit en moyenne section passe automatiquement en grande section l\'année suivante, puis de grande section en 1ère année, sans condition d\'évaluation.

-   Pour les classes d\'examen, chaque élève doit porter la mention « admis(e) » ou « recalé » dans le système avant la réinscription suivante ; la proclamation des résultats de fin d\'année n\'est acceptée par le système que si toutes les classes d\'examen concernées sont renseignées.

> ***Règle de gestion ---** le passage de la Grande Section de Maternelle vers le CP1 relève d\'une décision du parent ou de l\'enseignant sur la base des activités d\'éveil réalisées (voir 9.7), jamais d\'un score ou d\'un seuil calculé automatiquement par le système : la Maternelle ne produit aucune évaluation chiffrée exploitable à cette fin.*

## **7.5 Gestion des tuteurs, import/export et assistance à la saisie**

-   Chaque dossier élève prévoit les informations complètes des parents (prénom du père, fonction, téléphone, statut vivant/décédé ; nom et prénom de la mère, fonction, téléphone, statut vivant/décédée) ainsi que celles des tuteurs, distincts le cas échéant des parents.

-   Deux élèves, y compris de fratries différentes, peuvent partager le même compte parent ou le même compte tuteur : le modèle de données autorise un rattachement plusieurs-à-un entre élèves et parents/tuteurs.

-   Export et import de fichiers Excel pour les listes d\'élèves (inscriptions) et la saisie des notes : un modèle est téléchargé, complété hors ligne, puis réimporté.

-   Si un enseignant ne maîtrise pas les outils informatiques, le responsable du service concerné peut effectuer la saisie à sa place, l\'action restant tracée.

## **7.6 Identification des élèves**

Chaque élève est retrouvé sur la plateforme via deux identifiants complémentaires, dont l\'usage varie selon le niveau :

-   Un **matricule unique**, inscrit au dossier de l\'enfant lors de son inscription officielle.

-   Un **identifiant généré automatiquement** par le système, construit à partir du numéro de téléphone du parent, concaténé aux premières lettres des prénoms et à la première lettre du nom de l\'élève, suivi de son rang d\'inscription sous ce numéro. Exemple : pour un numéro « xxx » et l\'élève Mamadou Alpha Diallo, l\'identifiant est xxxMAD1 s\'il est le premier élève inscrit sous ce numéro, xxxMAD2 pour le second, et ainsi de suite.

> ***Règle de gestion ---** les élèves de la crèche et de la maternelle ne disposent que du second identifiant (généré automatiquement) ; le numéro de téléphone propre à l\'élève n\'est demandé qu\'à partir des classes supérieures à la 5ème année. C\'est ce même identifiant qui alimente la déduplication et le rattachement de compte décrits au chapitre 5.*

## **7.7 Spécificités par tranche d\'âge : renvoi au module académique**

Les adaptations de conception propres au primaire (formats audio-first, séances courtes, gamification non comparative) et à la Maternelle (espace d\'éveil sans lecture, sans score, entièrement piloté par le parent) relèvent du contenu pédagogique et de son moteur ; elles sont détaillées au chapitre 9 (9.6 et 9.7) plutôt que dans le présent module, qui reste centré sur la gestion administrative de l\'inscription et du dossier.

# **8. Module --- Gestion du personnel (RH)**

## **8.1 Enseignants**

-   À la maternelle et au primaire, un enseignant est rattaché à une seule classe pour toute l\'année scolaire ; il n\'y a pas de circulation entre classes.

-   Au secondaire (collège / lycée), les enseignants circulent entre les classes selon un emploi du temps défini par la direction des études ; ce sont eux qui peuvent dispenser une ou plusieurs disciplines dans un ou plusieurs établissements de la plateforme au cours d\'une même année scolaire.

-   Le profil et le tableau de bord d\'un enseignant du secondaire affichent la liste de tous les établissements où il intervient, avec les matières, horaires et classes associés à chacun.

## **8.2 Personnel administratif et d\'encadrement**

-   Direction, surveillants, secrétaires, comptables (voir 4.5 pour la liste complète des postes déclarés sous le rôle racine Direction).

-   **Matrones** : en charge de l\'hygiène et de la vie quotidienne des tout-petits (crèche / maternelle) ainsi que de l\'entretien des salles de classe.

-   **Monitrices** : en charge de l\'encadrement pédagogique des enfants de maternelle en salle de classe.

-   Recrutement et dossiers RH, présences et absences, évaluation des performances.

## **8.3 Dossier personnel et liaison de compte**

-   **Dossier personnel** : fiche complète pour tout type de personnel (enseignant, chauffeur, agent, etc.), avec documents et qualifications.

-   **Liaison de compte personnel** : un membre du personnel relie son compte applicatif à son dossier RH via matricule + date de naissance, sur le même principe de double facteur que la liaison élève (voir 5.7 et 7.6).

## **8.4 Contrats**

Gestion des contrats (CDI, CDD, vacataire) avec validation automatique de la rémunération selon le type de contrat : le système vérifie la cohérence entre le type de contrat déclaré et les règles de rémunération applicables (par exemple un vacataire rémunéré à l\'heure ou à la vacation plutôt qu\'au salaire mensuel fixe).

## **8.5 Congés**

Demande, approbation, refus, annulation et révocation de congé, en **auto-service strict** : le personnel demande pour lui-même, sans qu\'un tiers puisse initier une demande à sa place (contrairement à la saisie de notes, où une substitution tracée est possible --- voir 7.5).

> ***Règle de gestion ---** un congé d\'enseignant annule automatiquement les cours concernés sur l\'emploi du temps (voir 16.3) et déclenche la notification d\'annulation prévue en 16.6, sans double saisie : la déclaration d\'un congé est la seule action nécessaire, l\'impact sur le planning des classes concernées en découle.*

## **8.6 Salaires, primes et avances**

-   Gestion des salaires et primes de l\'ensemble du personnel (enseignants, matrones, monitrices, chauffeurs et autres agents).

-   **Primes et avances sur salaire** : gestion des primes ponctuelles et des avances, avec suivi du remboursement.

-   **Bulletin de paie** : calcul et génération d\'un bulletin de salaire (montant brut, hors charges sociales/fiscales), avec cycle **brouillon → validé → annulé**.

-   Paiement des salaires possible via mobile money, dans les mêmes conditions que les autres flux financiers de l\'établissement.

> ***Règle de gestion ---** les flux de paiement des salaires (sorties) alimentent le même cahier journal simplifié que les encaissements de scolarité (entrées) --- voir module financier, chapitre 17.4.*

# **9. Module --- Gestion académique et pédagogique**

Ce chapitre absorbe le moteur de contenu pédagogique d\'EduRéussite (module M04), structurellement plus riche que l\'« Espace Exercices » et les « Ressources pédagogiques » sommairement décrits dans EcoShop v2.0. La bibliothèque de contenu, le moteur de questions et le moteur de quiz/examen, trop volumineux pour tenir dans ce seul chapitre, sont détaillés aux chapitres 10 et 11.

## **9.1 Programmes et organisation**

-   Création des programmes scolaires, gestion des matières et de leurs coefficients --- désormais portée par les entités programme_officiel et programme_matiere du référentiel pédagogique multi-pays (voir 6.2).

-   Organisation des emplois du temps par classe et par enseignant (voir chapitre 16 pour le détail du moteur de planning).

## **9.2 Suivi pédagogique**

-   Cahier de texte numérique, suivi de la progression des cours.

-   Gestion des devoirs et des examens, y compris les **devoirs numériques** créés par l\'enseignant à partir de la banque de questions (paramétrés par classe, matière, chapitre, nombre de questions, durée, date limite --- voir 10.1), notifiés automatiquement à l\'ensemble de la classe concernée.

## **9.3 Moteur de contenu pédagogique (cours et leçons)**

Chaque leçon est structurée en séquence pédagogique complète plutôt qu\'en simple texte informatif : titre, introduction, objectifs, cours, définitions, exemples, illustrations, points à retenir, erreurs fréquentes, exercices et quiz associés.

-   **Bouton « Je n\'ai pas compris »** ouvrant une explication simplifiée alternative, dont le déclenchement est journalisé et alimente le système d\'analyse des lacunes (voir chapitre 14).

-   Bibliothèque de matières couvrant mathématiques, français, sciences, humanités et langues, déclinée selon le niveau (éveil et fondamentaux au primaire, matières disciplinaires au collège et au lycée), rattachée au référentiel pédagogique (chapitre 6).

-   Format audio-first et illustré pour les leçons destinées aux classes CP1 à CE2, en complément du texte plutôt qu\'en simple lecture à voix haute de celui-ci (voir 9.6).

> ***Règle de gestion ---** une leçon ne peut être publiée sans au moins un cours, un exemple et un exercice associé. Pour les classes CP1 à CE2, une leçon ne peut être publiée sans une version audio-illustrée validée en complément de sa version texte --- condition non négociable, distincte de la simple recommandation d\'usage. La publication elle-même suit le workflow Brouillon → Révision pédagogique → Validation → Publication piloté par l\'Administrateur de contenu pédagogique (voir 30.5).*

## **9.4 Ressources pédagogiques et pédagogie avancée (e-learning)**

-   Cours en ligne, vidéos et supports numériques, devoirs en ligne, forums de discussion.

-   **Ressources pédagogiques** : documents et supports de cours ajoutés par les enseignants de l\'établissement, en complément du contenu édité par Global Service Groupe, consultables aussi sous forme de fiches et flashcards (voir chapitre 26 --- Bibliothèque numérique).

> ***Règle de gestion ---** le module e-learning est un prolongement du cahier de texte numérique et de la gestion des devoirs : un devoir peut être publié indifféremment en présentiel (via le cahier de texte) ou en ligne, avec un même point d\'entrée de suivi pour l\'enseignant. L\'ancien « Espace Exercices » d\'EcoShop v2.0, réservé à l\'élève abonné à l\'IA, est désormais la banque de questions et le moteur de quiz décrits aux chapitres 10 et 11 : leur contenu de base reste accessible en offre FREE (voir 21.4 et 36), l\'abonnement Premium élève n\'en déverrouillant que les fonctionnalités avancées (statistiques détaillées, plan intelligent, répétition espacée, quota IA élevé).*

## **9.5 Assistant IA d\'apprentissage**

L\'assistant IA pédagogique individuel (Tuteur IA) fait l\'objet d\'une spécification dédiée au chapitre 21 (21.4), en tant que composante de l\'abonnement IA élève. Sa pertinence dépend directement des contenus versés par l\'enseignant au système (programme, supports de cours, documents) : plus l\'enseignant alimente le système, meilleure est la performance de l\'IA pour ses élèves --- cette dépendance doit rester visible pour l\'établissement, sous la forme d\'un indicateur de couverture de contenu par matière dans le tableau de bord Direction (chapitre 29).

## **9.6 Spécificités de conception pour le primaire (CP1 à CE2)**

Les classes CP1 à CE2 forment un public de 6 à 10-11 ans dont l\'autonomie de lecture, la capacité d\'attention et le rapport à l\'évaluation diffèrent nettement de ceux d\'un collégien ou d\'un lycéen. EcoShop ne décline pas pour ce public une simple version graphique du contenu secondaire ; cinq principes s\'appliquent transversalement aux modules concernés (9.3, chapitre 10, chapitre 22).

-   **Priorité à l\'audio et au visuel sur le texte long** : les consignes et les contenus s\'appuient en priorité sur la voix, les pictogrammes et l\'image plutôt que sur un texte dense, afin de ne pas présupposer une lecture autonome fluide.

-   **Formats de question simplifiés** : association image-son, Vrai/Faux illustré, QCM à deux ou trois choix, classement simple. Les formats à saisie libre ou à forte charge rédactionnelle sont réservés au CM1-CM2 et introduits progressivement (voir 10.2).

-   **Gamification non comparative** : les classements publics inter-élèves sont désactivés par défaut pour les classes CP1 à CE2 ; la progression y est valorisée par rapport à l\'élève lui-même (paliers personnels, badges de constance) plutôt que par comparaison à ses pairs (voir 22.3).

-   **Compte rattaché à un parent par défaut** : la création autonome d\'un compte élève sans compte parent associé est désactivée en dessous d\'un seuil d\'âge paramétrable (voir 4.3 et 5.2).

-   **Séances courtes et objectif quotidien réduit** : l\'objectif quotidien par défaut est significativement plus court qu\'au collège ou au lycée, afin de rester adapté à la capacité d\'attention d\'un enfant de 6 à 10 ans.

## **9.7 Espace Maternelle --- Éveil préscolaire**

La Maternelle (Petite, Moyenne et Grande Section, 3 à 5 ans) n\'est pas une extension du primaire mais un espace fonctionnellement à part : les enfants de cet âge ne lisent pas, n\'ont pas l\'autonomie de navigation d\'un élève du primaire, et ne doivent jamais être exposés à une notion d\'échec ou de comparaison.

### **9.7.1 Fonctionnalités clés**

-   Univers d\'activités organisés par **domaine de développement** plutôt que par matière scolaire : langage oral et pré-lecture, découverte des nombres et des formes, motricité fine, éveil sensoriel et couleurs, autonomie et vie pratique, éveil musical et rythme.

-   Formats d\'activité adaptés à l\'âge : association image-son, jeu de mémoire imagé, tracé guidé au doigt, écoute et répétition, coloriage guidé, histoire interactive à narration audio.

-   **Mascotte-guide vocale** accompagnant l\'enfant à chaque étape, se substituant à toute navigation textuelle ou par menu.

-   **Console parent dédiée** : lancement de session, choix du domaine du jour, réglage de la durée, consultation des activités réalisées et des domaines travaillés dans la semaine.

-   Fonctionnement hors connexion intégral après téléchargement du pack d\'activités, dans la continuité du principe offline-first appliqué au reste de la plateforme (voir chapitre 34).

### **9.7.2 Règles de gestion**

> ***Règle de gestion ---** aucune session d\'activité en Maternelle ne peut démarrer sans être initiée depuis la console parent ; l\'enfant ne dispose d\'aucun accès autonome à un menu, à un réglage ou à un choix d\'activité en dehors de la session lancée. Chaque session est plafonnée par défaut à une durée courte, réglable par le parent dans une limite recommandée, et se termine par une animation de fin invitant à une activité hors écran. Aucun prénom saisi par l\'enfant, aucune photo et aucun enregistrement vocal n\'est transmis à un serveur externe sans consentement parental explicite, révocable à tout moment depuis la console parent (voir 34.2). Aucune note, aucun classement ni aucune indication d\'échec n\'est jamais affiché à l\'enfant ; seul un renforcement positif (étoiles, animation, encouragement vocal) est utilisé, quel que soit le résultat de l\'activité.*

L\'inventaire des écrans dédiés (console parent, sélection de l\'univers du jour, session guidée par la mascotte, écran de fin d\'activité, tableau de bord parent, paramètres de temps d\'écran) est repris au chapitre 35.

# **10. Module --- Moteur de questions**

La banque de questions constitue l\'actif central du volet révision de la plateforme : une base richement structurée par métadonnées pédagogiques, condition de tout le reste du système (quiz, examens, recommandation, statistiques --- chapitres 11, 13, 14).

## **10.1 Métadonnées et structuration**

Chaque question porte des métadonnées obligatoires : pays, programme officiel, classe (pays_niveau), matière, chapitre, leçon, compétence, difficulté, type, temps recommandé, énoncé, réponses, bonne réponse, explication, source pédagogique, tags. C\'est ce même socle de métadonnées qui alimente les devoirs numériques créés par l\'enseignant (voir 9.2).

## **10.2 Types de questions et niveaux de difficulté**

-   Types supportés : QCM simple, QCM multiple, Vrai/Faux, réponse courte, texte à trous, association, classement, calcul, question avec image, question audio, question basée sur un document, problème.

-   Niveaux de difficulté : Facile, Moyen, Difficile, Expert --- ajustables automatiquement selon les performances de l\'élève, sans modifier la donnée source (voir 14.2).

-   Pour les classes CP1 à CE2, seuls les types association image-son, Vrai/Faux illustré, QCM à choix réduit et classement simple sont éligibles ; les formats à saisie libre sont réservés au CM1-CM2 et introduits progressivement (voir 9.6).

## **10.3 Signalement et qualité**

> ***Règle de gestion ---** une question ne peut être enregistrée sans compétence, difficulté et explication associées. Le niveau de difficulté affiché à l\'élève peut différer du niveau de base de la question si le moteur de recommandation l\'ajuste dynamiquement (voir 14.2), sans jamais modifier la donnée source. Une question signalée par au moins trois élèves distincts est automatiquement retirée temporairement de la diffusion, en attente de vérification par l\'Administrateur de contenu pédagogique (voir 30.5).*

# **11. Module --- Quiz, entraînement et mode examen**

## **11.1 Quiz et entraînement**

-   Modes : Quiz rapide (5 questions), Quiz standard (10 questions), Quiz intensif (20 à 50 questions), Quiz par chapitre, Quiz par matière, Quiz personnalisé (matière, chapitre, difficulté, nombre de questions, temps).

-   Correction immédiate avec explication à chaque question.

> ***Règle de gestion ---** chaque quiz terminé génère un enregistrement de tentative alimentant le profil de maîtrise (voir chapitre 14), y compris en mode hors connexion. Un quiz abandonné avant la dernière question n\'est pas comptabilisé dans les statistiques de réussite mais reste comptabilisé dans le temps d\'étude. Pour les classes CP1 à CE2, le quiz rapide est plafonné à 5 questions maximum, avec un nombre de choix par question réduit et un renforcement positif systématique en cas d\'erreur plutôt qu\'une simple indication d\'échec.*

## **11.2 Mode Examen**

Le mode Examen reproduit fidèlement les conditions d\'un examen réel (chronométrage, navigation contrainte, correction différée) afin d\'entraîner l\'élève à la gestion du temps et du stress.

-   Chronomètre, nombre de questions fixé, navigation entre questions, possibilité de revenir en arrière, verrouillage optionnel en fin de temps.

-   Remise automatique à expiration du temps imparti ; correction affichée après clôture de l\'examen, jamais pendant, y compris en cas de retour en arrière.

-   Restitution : note sur 20, temps total, nombre de bonnes/mauvaises réponses, points forts, points à renforcer.

> ***Règle de gestion ---** à expiration du chronomètre, l\'examen est automatiquement soumis avec les réponses saisies à cet instant. Cette note d\'examen blanc reste, comme l\'ensemble des résultats du présent chapitre, un résultat d\'entraînement formatif : elle n\'entre jamais dans le calcul de la moyenne officielle d\'un élève ni dans son bulletin (voir 12.6), même lorsque son barème (note sur 20) reprend celui des évaluations officielles.*

# **12. Module --- Notes, évaluations officielles et bulletins**

## **12.1 Saisie des notes**

-   Un enseignant saisit les notes par matière et par classe ; un élève peut avoir plusieurs notes dans une même matière (notes orales, évaluations écrites, participation, etc.).

-   Le système propose au professeur le maximum et la moyenne des notes disponibles ; celui-ci choisit la note retenue, avec calcul automatique de la moyenne et du classement de la classe.

-   Les élèves sont notifiés à chaque nouvelle note saisie (voir chapitre 20).

## **12.2 Rythme des compositions : un modèle déclaratif**

Plutôt que de préconfigurer un nombre fixe de compositions dans le système, EcoShop laisse le Directeur ou le Proviseur de l\'établissement déclarer lui-même chaque composition ou évaluation au fil de l\'année (par exemple : « deux évaluations ce mois-ci »). Le système ne fixe pas de nombre standard ; il fournit la structure permettant à chaque établissement d\'organiser son propre calendrier.

-   Dans la pratique observée en Guinée, le primaire retient souvent trois compositions trimestrielles et le secondaire deux compositions semestrielles ; ce sont des usages courants, non des règles imposées par le système.

-   L\'établissement peut en complément déclarer des tests de niveau et des évaluations mensuelles selon les mêmes modalités déclaratives.

> ***Règle de gestion ---** ce choix déclaratif remplace toute logique de paramétrage figé : la responsabilité de fixer le calendrier des évaluations revient entièrement à la direction pédagogique de l\'établissement.*

## **12.3 Cycle de verrouillage des notes**

-   L\'enseignant saisit les notes ; une fois remontées au responsable de service, elles ne peuvent plus être modifiées par l\'enseignant.

-   Le responsable du service concerné conserve la possibilité de les modifier.

-   Après la proclamation des résultats de fin d\'année, les données de l\'année deviennent définitivement inchangeables, pour tous les rôles.

## **12.4 Génération des bulletins et export PDF**

-   Composition des bulletins d\'une classe pour une période donnée, à partir des notes déjà saisies ; calcul automatique des moyennes, classement des élèves.

-   Conseils de classe, gestion du repêchage jusqu\'à une moyenne seuil paramétrable.

-   Export PDF : impression individuelle (élève/parent) ou groupée par classe (admin) au format A4, via le même moteur de templates que les reçus (voir 17.3 et 18).

> ***Règle de gestion ---** pour les classes déclarées comme classes d\'examen (voir 7.3), chaque élève doit porter la mention finale « admis(e) » ou « recalé » avant que le système n\'accepte la proclamation des résultats de fin d\'année ; sans cette mention, le verrouillage de fin d\'année décrit en 12.3 ne peut pas s\'exécuter pour ces classes.*

## **12.5 Absences et sanctions**

-   **Absences** : enregistrement des absences par élève, justifiées ou non.

-   **Sanctions** : déclaration et suivi d\'un dossier disciplinaire, avec levée de sanction tracée ; consultées automatiquement lors de la réinscription (voir 7.4).

## **12.6 Notes officielles et résultats d\'entraînement : une distinction stricte**

La fusion avec le moteur de révision (chapitres 10-11) introduit une masse de résultats formatifs (quiz, examens blancs) sans commune mesure avec le volume de notes officielles saisies par un enseignant.

> ***Règle de gestion ---** les résultats produits par le moteur de quiz et le mode Examen (chapitres 10 et 11) sont des résultats d\'entraînement : ils alimentent le profil de maîtrise par compétence (chapitre 14) et les statistiques personnelles de l\'élève, mais n\'entrent jamais dans le calcul de la moyenne officielle ni dans le bulletin décrit au présent chapitre. Seule une note saisie par un enseignant selon le cycle de verrouillage de 12.3 constitue une note officielle. Cette séparation, absente du cahier EduRéussite qui ne traitait pas de bulletins officiels, est nécessaire dès lors que les deux moteurs cohabitent dans une même application : elle évite qu\'un résultat de quiz auto-administré, non supervisé, ne vienne artificiellement gonfler ou pénaliser une moyenne engageant la scolarité réelle de l\'élève.*

## **12.7 Risque d\'échec et statistiques**

Score calculé automatiquement pour chaque élève, pondéré à 70 % sur les notes officielles et 30 % sur le taux de présence, avec un indicateur de fiabilité selon que le compte élève est réellement lié ou non (un score calculé sur un élève dont le compte n\'a jamais été rattaché, ou dont l\'assiduité n\'est que partiellement saisie, est signalé comme moins fiable).

-   Taux de réussite, classement global, performance des enseignants, tableaux de bord dynamiques (voir également chapitre 29 --- Reporting).

-   Ce score alimente directement l\'un des deux rapports groundés du Chat IA Directeur-Adviser (voir 21.1) et peut être recoupé, à titre indicatif seulement, avec le niveau de maîtrise par compétence issu du moteur de révision (voir 14.1) --- sans jamais s\'y substituer, puisque ce dernier repose sur des résultats d\'entraînement et non sur les notes officielles.

# **13. Module --- Préparation aux examens nationaux et concours**

Ce chapitre absorbe le module M08 d\'EduRéussite (« Préparation aux examens nationaux & concours »), le seul des modules M04-M16 dont le contenu n\'a pas été purement et simplement fondu dans un chapitre existant : la préparation aux examens nationaux justifie un espace dédié, distinct de l\'entraînement courant du chapitre 11, précisément parce qu\'elle s\'adresse à un sous-ensemble précis de classes --- les classes d\'examen définies en 7.3 --- et qu\'elle s\'appuie directement sur les entités pays_examen du référentiel pédagogique (chapitre 6).

## **13.1 Principe : un espace par examen, rattaché au référentiel**

Contrairement à la version EduRéussite d\'origine, qui déclinait un « Espace CEPE », un « Espace BEPC » et un « Espace BAC » comme trois espaces codés en dur, EcoShop v3.0 généralise le principe : un espace de préparation est généré automatiquement pour tout pays_examen déclaré au référentiel (voir 6.2), quel que soit le pays. Un élève voit apparaître l\'espace correspondant à l\'examen terminal de sa classe dès lors que celle-ci hérite de l\'attribut est_niveau_examinateur (voir 7.3).

> ***Règle de gestion ---** un espace de préparation aux examens n\'est visible pour un élève que si sa classe courante est rattachée à un pays_niveau pour lequel un pays_examen est déclaré et publié au référentiel. Un élève de classe intermédiaire (non examinatrice) n\'a accès à aucun espace de préparation aux examens nationaux, seulement à l\'entraînement courant du chapitre 11 ; c\'est la donnée du référentiel, et non une liste de noms d\'examens codée dans l\'application, qui pilote cet affichage --- condition nécessaire à l\'extension multi-pays décrite au chapitre 6.*

## **13.2 Contenu d\'un espace de préparation**

-   Entraînement ciblé sur les compétences de fin de cycle attendues à l\'examen, à partir de la banque de questions filtrée sur le pays_examen concerné (voir chapitre 10).

-   Examens blancs en conditions réelles, s\'appuyant sur le mode Examen du chapitre 11, avec un jeu de questions et une durée calibrés sur le format réel de l\'examen visé.

-   Annales d\'examens antérieurs, lorsque les droits de diffusion le permettent (voir 13.4).

-   Statistiques de préparation dédiées à l\'examen visé, distinctes des statistiques générales de révision (voir 13.4), restituées à l\'élève et, pour les classes de fin de primaire, au parent superviseur (voir 4.3).

-   Pour les examens du second cycle secondaire présentant plusieurs séries (filières), le contenu proposé est filtré selon la pays_filiere de l\'élève, sur le même principe que le programme_matiere (voir 6.2 et 9.1).

Au-delà des examens nationaux terminaux, le même mécanisme d\'espace dédié s\'étend, sans distinction technique particulière, aux concours d\'entrée, concours scolaires internes à un établissement (voir 32 et 30) et olympiades : ces événements ne correspondent pas nécessairement à un pays_examen du référentiel mais à un concours_evenement déclaré par un établissement ou par Global Service Groupe (voir chapitre 23, qui détaille l\'organisation et le classement des compétitions inter-établissements).

## **13.3 Cas particulier de l\'examen de fin de primaire**

L\'élève de fin de primaire (CEPE ou équivalent selon le pays, voir 6.4) constitue un profil de préparation distinct : plus jeune, moins autonome dans l\'organisation de sa révision, et pour lequel l\'enjeu du chronométrage strict est pédagogiquement contre-productif en dehors des toutes dernières semaines avant l\'examen.

> ***Règle de gestion ---** contrairement aux examens blancs de fin de collège et de fin de lycée, l\'examen blanc de fin de primaire ne chronomètre pas strictement les élèves par défaut : un chronomètre indicatif est affiché sans forcer la remise automatique de la copie. Ce comportement reste un paramètre activable par l\'enseignant ou par le parent superviseur, typiquement à l\'approche de la date réelle de l\'examen, afin d\'habituer progressivement l\'élève à la contrainte de temps sans l\'y exposer prématurément.*

## **13.4 Règles de gestion**

  --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Code**    **Règle**                                                   **Description**
  ----------- ----------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  RG-013-01   Droits de diffusion des annales                             Une annale d\'examen n\'est publiée dans un espace de préparation que si son statut de droit (source ministérielle officielle, licence explicite, ou domaine public administratif) a été validé par l\'Administrateur de contenu pédagogique selon le workflow de publication décrit en 9.3 et 30.5. À défaut de validation, l\'annale reste à l\'état brouillon et n\'est jamais visible d\'un élève.

  RG-013-02   Statistiques dédiées par examen                             Les statistiques de préparation à un examen national ou à un concours sont calculées et restituées séparément des statistiques générales de révision de l\'élève (chapitre 14) : un élève doit pouvoir situer précisément son niveau de préparation à l\'examen visé sans que celui-ci soit dilué dans une moyenne globale de toutes ses activités de révision.

  RG-013-03   Simulation de fin de primaire non chronométrée par défaut   Voir 13.3 : règle spécifique à l\'examen de fin de primaire, par contraste avec le chronométrage strict imposé par défaut aux examens blancs de fin de collège et de fin de lycée (voir chapitre 11).
  --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## **13.5 Articulation avec les autres modules**

-   Le référentiel pédagogique (chapitre 6) fournit la donnée pays_examen et pays_filiere qui pilote l\'affichage des espaces (13.1).

-   Le moteur de questions et le mode Examen (chapitres 10 et 11) fournissent respectivement la banque filtrable et le mécanisme de simulation chronométrée réutilisés ici sans duplication de code ni de règle.

-   Le profil de maîtrise par compétence (chapitre 14) reste alimenté par les tentatives réalisées dans un espace de préparation aux examens, au même titre que tout autre quiz ; les statistiques dédiées de 13.4 s\'y ajoutent sans le remplacer.

-   Comme l\'ensemble des résultats issus du moteur de révision, les scores obtenus dans un espace de préparation aux examens nationaux restent des résultats d\'entraînement au sens de 12.6 : ils n\'entrent jamais dans le calcul de la moyenne officielle ni dans le bulletin, y compris lorsqu\'ils portent sur l\'examen terminal réel de l\'élève.

-   Les packs de contenu commercialisés au titre du modèle économique (packs BEPC, BAC, concours --- voir chapitre 36) correspondent, côté conception fonctionnelle, aux mêmes espaces de préparation décrits ici : le pack est une modalité d\'accès commerciale, non une fonctionnalité distincte.

# **14. Module --- Analyse des compétences et moteur de recommandation**

Ce chapitre absorbe les modules M09 (Analyse des lacunes par compétence) et M10 (Moteur de recommandation) d\'EduRéussite, entièrement nouveaux pour EcoShop v2.0 : le « risque d\'échec » décrit en 12.7 reste un score administratif global, pondéré sur les notes officielles et la présence, tandis que le présent chapitre construit un diagnostic fin, par compétence, à l\'usage direct de l\'élève et de son enseignant.

> ***Règle de gestion ---** le profil de maîtrise par compétence décrit ici et le score de risque d\'échec de 12.7 sont deux indicateurs de nature différente, qui ne doivent jamais être fusionnés en un seul chiffre : le premier repose sur des résultats d\'entraînement (chapitres 10-11 et 13), mis à jour en continu et piloté par l\'élève ; le second repose sur des notes officielles et l\'assiduité, mis à jour au rythme des compositions et destiné en premier lieu à la direction. Un recoupement indicatif entre les deux reste possible (voir 12.7) mais aucun des deux ne remplace l\'autre.*

## **14.1 Profil de maîtrise par compétence**

Plutôt qu\'un score global par matière, le système calcule un pourcentage de maîtrise pour chaque compétence rattachée au référentiel de contenu (voir 6.3 et chapitre 10), mis à jour après chaque tentative de quiz, d\'examen ou d\'espace de préparation aux examens (chapitres 11 et 13).

-   Visualisation par barres de progression, par matière puis par compétence, avec recommandations textuelles générées automatiquement (par exemple : « À renforcer : la géométrie »).

-   Vue enseignant agrégée par classe, faisant apparaître les compétences les plus fréquemment sous le seuil d\'alerte au sein d\'un même groupe d\'élèves --- utile pour orienter une reprise de cours ciblée (voir 9.2).

-   Pour les classes CP1 à CE2, cette vue reste accessible à l\'enseignant et au parent superviseur mais n\'est jamais présentée à l\'élève lui-même sous forme de pourcentage ou de barre chiffrée, conformément au principe de gamification non comparative de 9.6.

> ***Règle de gestion ---** le niveau de maîtrise d\'une compétence pondère davantage les tentatives récentes que les tentatives anciennes, afin de refléter l\'état actuel des connaissances plutôt qu\'une moyenne indifférente au temps. Une compétence dont la maîtrise descend sous 50 % est automatiquement signalée comme point faible dans le tableau de bord de l\'élève et dans la vue agrégée de l\'enseignant.*

## **14.2 Moteur de recommandation**

À partir du profil de maîtrise (14.1) et de l\'historique complet de l\'élève, le système détermine automatiquement la prochaine activité de révision la plus pertinente, affichée comme recommandation du jour.

-   Analyse combinée des réponses, erreurs, temps de réponse, fréquence de pratique, difficulté effective et historique de progression.

-   Règles de transition : une erreur oriente vers un exercice similaire ; une réussite oriente vers une difficulté supérieure ; un échec répété oriente vers un retour au cours (voir 9.3) ; un oubli détecté déclenche une répétition espacée (voir chapitre 15) ; une bonne maîtrise oriente vers une nouvelle compétence.

-   C\'est ce même mécanisme d\'ajustement dynamique qui explique qu\'un élève puisse se voir proposer, pour une même question, un niveau de difficulté affiché différent de la difficulté de base enregistrée en 10.3, sans jamais modifier la donnée source.

> ***Règle de gestion ---** le moteur de recommandation privilégie les compétences sous le seuil de maîtrise tout en conservant une part d\'exercices de consolidation sur les compétences déjà acquises, afin d\'éviter qu\'un élève ne travaille exclusivement ses points faibles au détriment de la rétention de ses acquis. Une même question n\'est jamais proposée deux fois consécutivement à un même élève, sauf en mode correction explicite où l\'élève revoit délibérément une question déjà traitée.*

## **14.3 Articulation avec les autres modules**

-   Le profil de maîtrise (14.1) consomme les tentatives produites par les chapitres 10, 11 et 13 ; il alimente à son tour le planificateur intelligent et la répétition espacée du chapitre 15.

-   Le déclenchement du bouton « Je n\'ai pas compris » (voir 9.3) est journalisé et vient nourrir le diagnostic de lacune au même titre qu\'une erreur de quiz.

-   Le Tuteur IA (voir 21.4) s\'appuie sur le profil de maîtrise pour orienter ses explications, sans jamais avoir seul autorité pour le modifier : seules les règles de 14.1 et 14.2 mettent à jour la donnée.

# **15. Module --- Répétition espacée et planificateur intelligent**

Ce chapitre absorbe les modules M11 (Répétition espacée) et M12 (Planificateur intelligent) d\'EduRéussite, tous deux entièrement nouveaux pour EcoShop v2.0. Les deux fonctionnalités partagent une même logique --- organiser dans le temps l\'effort de révision de l\'élève --- mais à deux échelles différentes : la notion isolée pour la répétition espacée, le programme complet pour le planificateur.

## **15.1 Répétition espacée**

Chaque notion apprise entre dans un calendrier de répétition fondé sur les paliers classiques de la mémorisation espacée : J1 (apprentissage), puis rappels à J2, J4, J7, J14 et J30.

-   Le calendrier s\'adapte à la réussite ou à l\'échec de l\'élève à chaque étape de révision plutôt que de suivre un rythme fixe pour tous.

-   La file de révision du jour agrège l\'ensemble des notions arrivées à échéance, indépendamment de la matière, sous forme de cartes de révision individuelles.

> ***Règle de gestion ---** un échec à une étape de répétition espacée réinitialise l\'intervalle au palier précédent plutôt que de poursuivre la progression du calendrier. Le nombre de notions proposées en répétition espacée un même jour est plafonné, afin de ne pas saturer l\'objectif quotidien de l\'élève (voir 15.3) ; pour les classes CP1 à CE2, ce plafond est resserré conformément à l\'objectif quotidien réduit prévu en 9.6.*

## **15.2 Planificateur intelligent**

À partir d\'une échéance déclarée par l\'élève lui-même (par exemple : « mon examen est dans 60 jours »), le système construit automatiquement un programme de révision complet réparti sur la période disponible.

-   Saisie de l\'échéance et des matières concernées ; pour une échéance correspondant à un examen national ou à un concours du référentiel (voir chapitre 13), les matières et leur pondération peuvent être pré-remplies à partir du programme_matiere concerné (voir 6.2).

-   Génération d\'un plan quotidien tenant compte du poids relatif de chaque matière et des compétences faibles déjà identifiées par le profil de maîtrise (voir 14.1).

-   Vue calendrier du plan, mission du jour, possibilité d\'ajustement manuel par l\'élève.

> ***Règle de gestion ---** le plan est recalculé automatiquement si l\'élève prend du retard sur plusieurs jours consécutifs, sans jamais supprimer les notions déjà planifiées : elles sont redistribuées sur les jours restants. Lorsque la donnée de coefficient de matière est disponible pour le programme_matiere concerné (voir 6.2), le planificateur alloue davantage de temps aux matières à fort coefficient.*

## **15.3 Articulation avec les autres modules**

-   La répétition espacée (15.1) est l\'une des cinq règles de transition du moteur de recommandation (voir 14.2 : « oubli détecté → répétition espacée ») ; les deux mécanismes s\'exécutent en continu et non l\'un après l\'autre.

-   Le planificateur (15.2) peut mobiliser indifféremment le mode Quiz, le mode Examen ou un espace de préparation aux examens nationaux (chapitres 11 et 13) selon la nature de la mission du jour qu\'il génère.

-   L\'objectif quotidien mentionné en 9.6 pour le primaire est le même compteur que celui régulé par le plafond de répétition espacée de 15.1 : les deux ne s\'additionnent pas en deux limites indépendantes.

# **16. Module --- Emploi du temps**

## **16.1 Grille horaire**

Grille par défaut de l\'établissement, personnalisable par classe.

## **16.2 Calendrier scolaire et activités**

-   Calendrier scolaire, examens.

-   Activités culturelles et sportives, événements scolaires.

## **16.3 Séances récurrentes**

Cours répétés chaque semaine (matière, enseignant, salle, créneau) : c\'est la structure de base de l\'emploi du temps d\'une classe.

## **16.4 Séances ponctuelles et annulations**

Modification ou annulation d\'un cours pour un seul jour, sans toucher à la récurrence de la séance. Une annulation peut être déclenchée manuellement par l\'administration ou automatiquement par un congé enseignant (voir 8.5).

## **16.5 Détection de conflit**

Vérification automatique qu\'un enseignant ou une salle n\'est pas déjà occupé sur le même créneau, à la création d\'une séance récurrente comme d\'une séance ponctuelle.

## **16.6 Consultation par rôle et notifications**

-   Vue « Mon emploi du temps » pour élève, parent et enseignant ; vue de construction et de répartition pour l\'administration.

-   **Notification d\'annulation** : l\'élève, le parent et l\'enseignant concernés sont notifiés automatiquement en cas d\'annulation d\'un cours, qu\'elle soit manuelle ou déclenchée par un congé (voir 8.5 et chapitre 20).

# **17. Module --- Gestion financière et comptable**

Ce module concentre l\'essentiel des flux de trésorerie de l\'établissement et constitue le point de convergence entre la scolarité, le personnel, la marketplace et, depuis la fusion avec EduRéussite, les abonnements individuels de révision (Premium élève, IA professeur --- voir chapitre 21 et chapitre 36). Il reste également celui où les deux sources d\'origine --- cahier EcoShop v1.2 et état réel du code --- divergent le plus, notamment sur la logique de paiement (voir 17.1).

## **17.1 Paiement libre et progressif**

Aucune tranche n\'est imposée au parent : celui-ci paie selon ses moyens, le solde de l\'élève se met à jour au fil des versements, sans jamais bloquer ou pénaliser un retard.

> ***Règle de gestion ---** cette règle prime sur la description de la v1.2, qui présentait un système de paiement par tranches (2, 3, 4 tranches, mensuel, trimestriel) comme un mode de fonctionnement à part entière. Dans l\'état réel du produit, les échéances configurables décrites en 7.2 ne sont qu\'un **repère indicatif** affiché à l\'établissement et au parent ; elles ne conditionnent aucun blocage de service, aucune pénalité de retard, ni aucune restriction d\'accès.*

Selon son âge, un élève peut se voir accorder le droit de régler lui-même ses frais de scolarité, pour les cas où il ne bénéficie pas du soutien financier direct d\'un tuteur (voir 4.2).

## **17.2 Modes d\'encaissement**

-   **Encaissement espèces / banque** : enregistrement d\'un paiement de scolarité, cantine, transport, internat, etc. en espèces ou virement, avec écriture simultanée dans le solde de l\'élève et le cahier journal.

-   **Paiement en ligne (CinetPay)** : paiement de la scolarité par le parent via Orange Money, MTN, carte bancaire --- activable par établissement, au libre choix de l\'école, et verrouillé en mode gratuit (voir 2.5).

> ***Règle de gestion ---** l\'état réel du code fait converger l\'intégralité du paiement mobile scolaire vers l\'agrégateur CinetPay (Orange Money, MTN Mobile Money, carte bancaire derrière une même passerelle), là où la v1.2 décrivait une intégration directe aux opérateurs mobile money. C\'est ce même agrégateur, et non une intégration directe aux opérateurs comme l\'envisageait EduRéussite, qui traite également les abonnements individuels de révision (Premium élève, IA professeur --- voir 17.7) : la centralisation sur un seul prestataire simplifie la conformité et la réconciliation comptable pour l\'ensemble des flux de la plateforme, scolaires comme individuels.*

## **17.3 Reçus et impression**

-   **Reçu de paiement (PDF)** : génération d\'un reçu imprimable A4 pour chaque paiement, et un reçu récapitulatif annuel regroupant tous les paiements de l\'année scolaire.

-   Ce reçu récapitulatif est mis à jour à chaque nouveau paiement effectué à la caisse ; il est imprimé en deux exemplaires (un remis au parent ou à l\'élève, l\'autre conservé par la gestion comptable).

-   Impression prise en charge sur imprimante de bureau Xprinter 58 mm et sur imprimante portable GOOJPRT PT-210, avec un reçu au petit format délivré à chaque paiement à la caisse --- utile notamment en cas de coupure de courant limitant l\'accès aux moyens d\'impression habituels.

-   L\'apparence de ces reçus (logo, couleurs, mentions) est personnalisable par chaque établissement depuis l\'espace dédié du chapitre 18.

## **17.4 Cahier journal et solde élève**

-   **Cahier journal** : registre comptable de tous les encaissements de l\'établissement, classé par chapitre (scolarité, cantine, transport...), incluant les sorties liées aux salaires (voir 8.6).

-   **Solde élève** : suivi, par année scolaire, du montant dû et du montant payé pour chaque élève --- jamais mélangé d\'une année sur l\'autre.

## **17.5 Comptabilité de l\'établissement**

-   Cahier journal simplifié : date, chapitre, article, libellé, entrées, sorties --- et rapport journalier associé.

-   Budget structuré selon la hiérarchie : chapitre → article → libellé → unité → quantité → prix unitaire → prix total.

-   Le modèle de budget est exportable au format Excel, modifiable hors ligne, puis réimportable dans le système ; des modèles prédéfinis sont également disponibles et téléchargeables depuis l\'espace École.

-   Comptabilité analytique de gestion, couvrant l\'ensemble des niveaux de la vie de l\'école et le suivi de la réalisation budgétaire.

-   Suivi des impayés, facturation automatique, gestion des dépenses (salaires, matériel), rapports financiers consolidés (voir également chapitre 29 --- Reporting).

> ***Règle de gestion ---** les revenus générés par la marketplace (commissions, mise en avant de produits) et les frais de livraison interne alimentent également les rapports financiers de l\'établissement lorsque celui-ci perçoit une quote-part --- voir 27.8 et chapitre 32. Le règlement différé dû aux vendeurs affiliés (comptes auxiliaires, acomptes --- voir 27.12--27.13) constitue à l\'inverse un passif de l\'établissement envers ses vendeurs, distinct de ses recettes propres, et n\'est jamais confondu avec elles dans le cahier journal.*

## **17.6 Portefeuille établissement et distribution de fin d\'année**

-   **Portefeuille établissement** : argent collecté pour l\'école (net des frais du prestataire de paiement CinetPay), totalement indépendant de son statut Pro.

-   **Distribution de fin d\'année** : à la clôture de l\'année scolaire, Global Service Groupe détecte les soldes disponibles par établissement et notifie les administrateurs concernés (et l\'équipe GSG en récapitulatif) pour organiser le reversement.

## **17.7 Abonnements et frais plateforme**

  --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Flux**                                     **Nature**                                                                                                                                                                         **Périodicité**
  -------------------------------------------- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ------------------------------------
  Abonnement Pro établissement                 Facturé par palier selon le nombre d\'élèves (voir 2.4)                                                                                                                            Renouvelable chaque année scolaire

  Frais IA admin annuel                        Frais fixe, indépendant du palier Pro, débloque l\'accès IA pour tous les comptes administratifs de l\'établissement                                                               Annuel

  Abonnement Premium élève (révision)          Payé directement par l\'élève ou son parent, indépendant du statut Pro de l\'école ; débloque le contenu et les fonctionnalités avancées du moteur de révision (voir 21.4 et 36)   Mensuel ou annuel

  Abonnement IA professeur                     Payé directement par l\'enseignant, débloque uniquement l\'IA (pas l\'accès administrateur du moteur de révision --- voir 21.5)                                                    Mensuel

  Frais de création de réseau                  Payé une seule fois dans la vie d\'un réseau d\'établissements, lors de sa création (voir 28.3)                                                                                    Unique

  Packs de préparation (BEPC, BAC, concours)   Achat ponctuel donnant accès à un espace de préparation aux examens nationaux enrichi (annales, examens blancs supplémentaires --- voir chapitre 13)                               Ponctuel
  --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

**Alerte de bascule d\'année scolaire** : avertissement préventif (avant la fin de l\'année) puis réactif (si le renouvellement n\'a pas eu lieu) sur la perte à venir du palier Pro ou de l\'accès IA admin.

Le détail consolidé de ces flux et leur articulation avec le modèle économique global de la plateforme sont repris au chapitre 36.

## **17.8 Traçabilité des transactions et activation des abonnements**

EduRéussite consacrait un module entier (M23) à l\'architecture de paiement des abonnements individuels : Utilisateur → Abonnement → Passerelle de paiement → Confirmation → Activation Premium. Cette architecture ne diffère pas, dans son principe, du circuit de paiement scolaire déjà en place dans EcoShop (17.2) : les deux convergent vers le même prestataire CinetPay. Deux règles de gestion propres au caractère individuel et récurrent des abonnements de révision méritaient toutefois d\'être reprises explicitement, absentes du cahier EcoShop v1.2 qui ne traitait que du paiement scolaire encaissé par l\'établissement.

> ***Règle de gestion ---** en cas de confirmation de paiement retardée par la passerelle CinetPay, l\'activation de l\'abonnement Premium (élève) ou IA (professeur, admin) intervient automatiquement dès réception de la confirmation, sans action manuelle de l\'utilisateur ni nouvelle saisie. Chaque transaction de paiement --- scolaire ou individuelle --- est journalisée avec son statut complet (initiée, confirmée, échouée, remboursée) à des fins de support et d\'audit, consultable par l\'utilisateur dans son historique de transactions et par l\'Administrateur Global Service Groupe en cas de litige (voir chapitre 30).*

# **18. Documents officiels et espace de personnalisation des templates**

Ce chapitre dépasse la simple liste de documents générés par la plateforme (v2.0) pour établir un véritable **espace dédié**, propre à chaque établissement, où la direction personnalise elle-même l\'apparence de ses documents officiels sans jamais toucher au contenu ni à la logique métier qui les alimente.

## **18.1 Principe : un espace de personnalisation dédié par établissement**

Accessible depuis l\'application Windows, au sein du Backoffice établissement (voir chapitre 31), l\'espace de personnalisation des templates donne à chaque établissement un jeu de modèles qui lui est propre.

> ***Règle de gestion ---** les templates d\'un établissement ne sont jamais partagés avec un autre établissement de la plateforme, y compris au sein d\'un réseau : l\'étanchéité déjà posée pour les données de gestion (voir 28.1) s\'applique identiquement à l\'identité visuelle des documents. Seule la Direction Générale d\'un réseau peut, si elle le souhaite, proposer un template harmonisé à ses établissements membres, sur le même principe déclaratif que l\'harmonisation de gestion évoquée en 28.2 : chaque établissement membre reste libre de l\'adopter ou de conserver son propre template.*

## **18.2 Documents concernés**

  ---------------------------------------------------------------------------------------------------------------------------------
  **Document**                                       **Chapitre source du contenu**           **Format**
  -------------------------------------------------- ---------------------------------------- -------------------------------------
  Reçu de paiement (petit format)                    Financière --- encaissement (17.2)       Ticket imprimante portable / bureau

  Reçu récapitulatif annuel                          Financière --- reçus (17.3)              A4, 2 exemplaires

  Bulletin scolaire                                  Notes et bulletins (12.4)                A4, individuel ou groupé par classe

  Certificat de scolarité                            Documents officiels (présent chapitre)   A4

  Attestation (réussite, fréquentation, radiation)   Documents officiels (présent chapitre)   A4

  Carte scolaire                                     Documents officiels (présent chapitre)   Format carte, recto-verso

  Lettre de recommandation                           Documents officiels (présent chapitre)   A4

  Bulletin de paie                                   Personnel --- salaires (8.6)             A4
  ---------------------------------------------------------------------------------------------------------------------------------

Le certificat de maîtrise du moteur de révision (voir 23.3) et les documents produits par le Backoffice Global Service Groupe (rapports consolidés, factures GSG) sont volontairement exclus de cet espace : le premier porte l\'identité de Global Service Groupe plutôt que celle de l\'établissement, par cohérence avec son usage inter-établissements (concours, olympiades) ; les seconds relèvent du Backoffice GSG (chapitre 30), non du paramétrage d\'un établissement.

## **18.3 Éléments personnalisables**

-   **Identité visuelle** : logo de l\'établissement, couleur principale et couleur secondaire, police de titre --- cohérente avec la personnalisation des thèmes graphiques de l\'application décrite en 31.

-   **En-tête et pied de page** : nom complet et sigle de l\'établissement, adresse, coordonnées de contact, slogan facultatif, numéro d\'autorisation d\'ouverture lorsque la réglementation locale l\'exige.

-   **Signature et cachet** : image scannée de la signature du directeur ou du responsable habilité, et du cachet de l\'établissement, insérées automatiquement à l\'emplacement prévu par le modèle plutôt qu\'apposées manuellement après impression.

-   **Mentions et texte libre** : mentions légales spécifiques à l\'établissement, formule de politesse d\'une attestation, texte d\'accompagnement d\'un bulletin (par exemple une appréciation générale de fin de trimestre), dans les zones de texte libre prévues par chaque modèle.

-   **Langue du document** : lorsque plusieurs langues sont activées pour l\'établissement (voir 34.9), un même document peut disposer d\'un template par langue.

> ***Règle de gestion ---** la personnalisation porte exclusivement sur la présentation : aucun champ de personnalisation n\'autorise la modification de la donnée elle-même (un montant, une note, une date de naissance) ni de la logique de calcul qui la produit. Un établissement ne peut par exemple pas modifier, depuis cet espace, la formule de calcul d\'une moyenne (chapitre 12) ou le contenu d\'un reçu au-delà de sa mise en forme.*

## **18.4 Champs de fusion dynamiques**

Chaque zone de texte d\'un template peut insérer des **champs de fusion** --- des variables résolues au moment de la génération du document à partir des données réelles de l\'élève, du personnel ou de l\'établissement concerné (nom et prénom, matricule, classe, montant, date, moyenne, mention, etc.), organisés par type de document dans un panneau d\'insertion, sans nécessiter la moindre compétence technique de la personne qui compose le template.

> ***Règle de gestion ---** un champ de fusion inséré dans un template mais absent de la donnée réelle au moment de la génération (par exemple un numéro d\'autorisation non renseigné) est rendu par une chaîne vide plutôt que par une erreur bloquante ou par le nom technique du champ, afin qu\'un document imparfaitement paramétré reste malgré tout imprimable en situation réelle.*

## **18.5 Cycle de vie d\'un template : brouillon, aperçu, publication**

-   **Brouillon** : toute modification d\'un template est d\'abord enregistrée en brouillon, sans effet sur les documents déjà générés ni sur les nouvelles générations en cours.

-   **Aperçu** : un aperçu instantané, construit soit sur des données fictives, soit sur un élève ou un membre du personnel réel choisi comme échantillon, permet de vérifier le rendu avant publication, y compris la résolution effective des champs de fusion (18.4).

-   **Publication** : la validation du brouillon le fait remplacer le template actif pour l\'établissement ; c\'est ce template publié qui est utilisé par toute nouvelle génération de document, sur mobile comme sur Windows.

> ***Règle de gestion ---** la publication d\'un nouveau template n\'altère jamais rétroactivement un document déjà généré et archivé : chaque document conserve la version du template en vigueur au moment de sa génération, afin qu\'un bulletin ou un reçu déjà remis à une famille ne diverge jamais de sa copie archivée. Un historique des versions publiées est conservé pour audit, sur le même principe de traçabilité que les autres actions sensibles listées en 34.3.*

## **18.6 Accès et permissions**

Par défaut, seule la Direction (voir 4.5) peut éditer et publier un template. La Direction peut déléguer ce droit à un poste déclaré de son choix --- typiquement le Secrétaire, déjà en charge de l\'édition de documents au quotidien (voir 4.5) --- selon le même mécanisme de déclaration dynamique des postes et des permissions décrit en 4.6.

## **18.7 Accès réservé au mode payant**

La personnalisation des templates rejoint la personnalisation des thèmes graphiques parmi les fonctionnalités verrouillées en mode gratuit (voir 2.5).

> ***Règle de gestion ---** un établissement en mode gratuit continue de générer l\'ensemble des documents du présent chapitre, sans aucune restriction fonctionnelle : seule la personnalisation de leur apparence est verrouillée. Ces établissements utilisent un jeu de templates par défaut fourni par Global Service Groupe, sobre et neutre, portant uniquement le nom de l\'établissement inséré par champ de fusion (voir 18.4) et la mention « généré via EcoShop ». Le passage en mode payant débloque l\'espace de personnalisation sans perte des documents déjà générés.*

## **18.8 Moteur de génération unique**

> ***Règle de gestion ---** le moteur de génération de documents est unique et partagé : reçus (chapitre 17), bulletins (chapitre 12), certificats et attestations (présent chapitre) passent tous par le même pipeline de composition PDF et par le même espace de personnalisation de templates décrit ci-dessus, ce qui garantit une identité visuelle cohérente par établissement et évite toute duplication de logique de mise en page entre modules.*

# **19. Module --- Vie scolaire et services complémentaires**

## **19.1 Discipline et sanctions**

-   Suivi des sanctions disciplinaires par élève, consultées automatiquement lors de la réinscription (voir 7.4) et lors du calcul du risque d\'échec (voir 12.7).

-   Alertes liées à l\'absence, au retard ou à l\'impayé, transmises via le module de communication (chapitre 20).

## **19.2 Infrastructures et matériel**

Gestion des salles de classe et de leur affectation, du matériel (tables, ordinateurs\...) et de sa maintenance.

## **19.3 Services complémentaires paramétrables**

-   Suivi médical des élèves.

-   Cantine (repas, paiements) --- activable selon le paramétrage initial de l\'établissement.

-   Internat, si applicable.

-   Le transport scolaire et la bibliothèque physique, bien que rattachés à la vie de l\'élève, disposent chacun de leur propre chapitre (24 et 25) compte tenu de leur richesse fonctionnelle propre (suivi GPS, statuts d\'emprunt automatiques).

> ***Règle de gestion ---** la présence ou non de la cantine, de la maternelle, du primaire, du collège et du lycée est définie au paramétrage de l\'établissement (voir 2.4 et chapitre 31) et conditionne l\'affichage des modules correspondants pour l\'ensemble des rôles.*

## **19.4 Logistique et discipline au retrait marketplace**

La sécurité des transactions et la discipline des élèves lors du retrait des colis marketplace relèvent conjointement de la logistique marketplace (chapitre 27) et du présent module : un manquement constaté au moment du retrait (comportement, falsification de justificatif) peut être consigné comme incident disciplinaire au dossier de l\'élève.

# **20. Module --- Communication**

## **20.1 Communication interne**

-   SMS, e-mail, notifications push --- les mêmes canaux techniques que ceux mobilisés par le moteur OTP multicanal (chapitre 5) pour la vérification de compte, réutilisés ici pour la communication applicative.

-   Annonces générales publiées par l\'administration de l\'établissement, visibles par les rôles concernés.

## **20.2 Centre de notifications**

Chaque compte dispose d\'un centre de notifications personnel, alimenté par tous les modules producteurs d\'événements : nouvelle note (chapitre 12), annulation de cours (chapitre 16), paiement (chapitre 17), colis prêt à être récupéré (chapitre 27), distribution de fin d\'année (chapitre 17), congé approuvé/refusé (chapitre 8), etc. Le détail des relations entre modules producteurs et le centre de notifications est repris au chapitre 32.

## **20.3 Groupes de discussion**

Groupes de classe ou de matière créés par un enseignant ou l\'administration, avec au moins un adulte présent en permanence.

> ***Règle de gestion ---** trois garde-fous structurent ce module, non négociables du point de vue de la protection des mineurs : jamais de messagerie privée élève-élève, jamais d\'accès parent à ces groupes (ils restent un espace pédagogique enseignant-élèves, distinct de l\'espace parent décrit en 4.2), et contenu strictement textuel --- aucun partage de média (image, audio, vidéo, fichier) n\'est autorisé dans ces groupes. Un groupe qui perdrait son dernier adulte présent (par exemple à la suite d\'un départ d\'enseignant) doit être automatiquement suspendu jusqu\'à réaffectation d\'un adulte responsable.*

Ce principe d\'absence de messagerie privée élève-élève, déjà retenu par EcoShop v2.0, converge exactement avec la règle RG-021-01 du cahier EduRéussite (« pas de messagerie privée élève-élève en V1, tant qu\'un dispositif de modération dédié n\'est pas spécifié et validé ») : la fusion ne crée ici aucune tension à arbitrer, les deux cahiers ayant indépendamment posé la même limite de prudence vis-à-vis des jeunes publics.

## **20.4 Signalement et modération**

-   Un message peut être signalé par tout membre du groupe (élève ou adulte).

-   L\'administration de l\'établissement peut, sur un message signalé : exclure un membre du groupe, suspendre le groupe, ou escalader le signalement en incident disciplinaire (voir 19.1).

> ***Règle de gestion ---** tout signalement doit rester consultable par l\'administration même après suppression ou modification du message signalé (conservation d\'une copie horodatée au moment du signalement), afin qu\'une modération a posteriori reste possible ; cette exigence rejoint le principe de journalisation systématique posé au chapitre 34.*

# **21. Module --- Intelligence artificielle**

Ce module regroupe désormais sept briques distinctes, chacune avec son propre public et son propre modèle de facturation. La fusion avec EduRéussite en enrichit substantiellement deux : l\'abonnement IA élève (21.4), jusqu\'ici décrit de façon sommaire dans EcoShop v2.0, reçoit ici la spécification concrète et détaillée du Tuteur IA (module M13 d\'EduRéussite) ; et une brique entièrement nouvelle, le Scan et résolution d\'exercice (21.5, module M14), rejoint le module. Deux d\'entre elles --- Parent IA et Scan et résolution d\'exercice --- portent des exigences de confidentialité renforcées du fait qu\'elles touchent directement des données de mineurs.

## **21.1 Chat IA --- Directeur-Adviser**

Assistant conversationnel destiné à l\'administration de l\'établissement, doté de deux rapports « groundés » sur les données réelles de l\'établissement :

-   analyse du risque d\'échec par classe, à partir du score décrit en 12.7 ;

-   analyse des échéances de paiement en retard, à partir du suivi des impayés décrit en 17.5.

> ***Règle de gestion ---** les données réelles utilisées par ces deux rapports sont **pseudonymisées avant tout envoi au modèle** : aucune donnée nominative (nom, prénom, identifiants directs) n\'est transmise au fournisseur d\'intelligence artificielle. Ce principe de minimisation prime sur toute autre considération d\'ergonomie et s\'applique à toute évolution future du Chat IA Directeur-Adviser.*

L\'accès à cette fonctionnalité est conditionné au frais IA admin annuel décrit en 17.7, indépendant du palier Pro de l\'établissement.

## **21.2 Parent IA**

Suivi de l\'usage du smartphone de l\'enfant par le parent, dans une logique d\'autolimitation numérique (temps d\'écran, plages d\'usage), avec **consentement explicite**.

> ***Règle de gestion ---** le consentement requis pour Parent IA est double : celui du parent, qui active la fonctionnalité, et une information adaptée à l\'âge de l\'enfant sur le fait que son usage est suivi --- EcoShop ne doit jamais présenter ce suivi comme une surveillance dissimulée. La fonctionnalité est un outil d\'accompagnement parental, pas un outil de contrôle intrusif : elle ne donne accès qu\'à des métriques d\'usage agrégées (durée, plages horaires), jamais au contenu des échanges de l\'enfant sur les applications tierces suivies. Cette fonctionnalité touchant directement des données d\'enfants, elle relève des principes de protection des mineurs détaillés au chapitre 34.*

## **21.3 Analyse des performances et prédiction du risque d\'échec**

Analyse des performances et prédiction des risques d\'échec par intelligence artificielle, restituée dans les tableaux de bord (chapitre 29) et dans le score de risque d\'échec par élève (voir 12.7). Cette brique reste distincte du profil de maîtrise par compétence décrit au chapitre 14, lui-même alimenté par une mécanique déterministe (pondération temporelle, seuil d\'alerte) plutôt que par un modèle prédictif : les deux peuvent se recouper à titre indicatif (voir 12.7 et 14.1) sans jamais être confondus.

## **21.4 Abonnement IA élève --- Tuteur IA**

Le Tuteur IA est l\'assistant pédagogique conversationnel individuel de l\'élève. Il fait l\'objet, dans EduRéussite (module M13), d\'une spécification bien plus concrète que ce que décrivait sommairement EcoShop v2.0 (« assistant IA pédagogique individuel ») : cette spécification est ici adoptée intégralement comme contenu de l\'abonnement IA élève.

-   Explication d\'une notion, reformulation, exemple, génération d\'exercice, correction, détection de difficulté, proposition de méthode de travail.

-   **Mode pédagogique par questionnement guidé** (« Quelle formule pourrais-tu utiliser ? ») plutôt que réponse directe immédiate : le tuteur IA guide le raisonnement de l\'élève, il ne se substitue pas à lui.

-   Chaque sollicitation transmet au modèle le pays, le programme officiel, la classe, la matière, le chapitre et le niveau de l\'élève (voir référentiel, chapitre 6), afin de contraindre systématiquement la réponse au périmètre du programme officiel plutôt qu\'à une connaissance générale non contextualisée.

> ***Règle de gestion ---** sur la question du modèle d\'accès, EcoShop v2.0 et EduRéussite divergeaient : la première réservait tout usage du Tuteur IA à un abonnement payant mensuel indépendant du statut Pro de l\'établissement ; la seconde prévoyait un usage illimité en version pédagogique de base, avec un quota resserré au-delà d\'un certain volume pour les comptes non-Premium. C\'est le modèle EduRéussite qui est retenu ici, par cohérence avec le principe déjà posé pour le reste du moteur de révision (voir 9.4 et 36) : un socle de conversations avec le Tuteur IA reste accessible à tout élève sans abonnement, dans la limite d\'un quota mensuel resserré ; l\'abonnement Premium élève lève ce quota et donne un accès étendu, sans jamais requérir de frais additionnel distinct pour la seule activation du Tuteur IA. Ce choix maximise la valeur pédagogique perçue dès la première utilisation, condition de conversion sur un marché sensible au prix (voir chapitre 3).*
>
> ***Règle de gestion ---** la pertinence du Tuteur IA dépend directement des contenus que l\'enseignant verse au système (programme, supports de cours, documents) et de la richesse de la banque de questions du référentiel (chapitre 10) : plus l\'enseignant et l\'Administrateur de contenu pédagogique alimentent le système, meilleure est la performance de l\'IA pour les élèves concernés. Ce lien de dépendance doit rester visible pour l\'établissement, sous la forme d\'un indicateur de couverture de contenu par matière dans le tableau de bord Direction (chapitre 29).*

## **21.5 Scan et résolution d\'exercice**

Fonctionnalité entièrement nouvelle, absorbée du module M14 d\'EduRéussite, absente d\'EcoShop v2.0 : elle permet à l\'élève de photographier un exercice papier et d\'obtenir un accompagnement structuré vers la résolution, sans jamais se substituer à son raisonnement.

-   Reconnaissance de texte à partir de la photo, identification automatique de la matière et du chapitre concernés (rattachement au référentiel de contenu, chapitre 6 et chapitre 10).

-   Analyse du problème, proposition de méthode, guidage progressif, puis correction détaillée finale.

> ***Règle de gestion ---** le système ne peut afficher directement la solution finale d\'un exercice scanné sans être passé par les étapes de méthode et de guidage progressif, sauf demande explicite et répétée de l\'élève --- ce garde-fou reprend, pour l\'exercice photographié, le même principe de questionnement guidé que le Tuteur IA conversationnel (21.4). La reconnaissance de texte basique peut fonctionner hors connexion pour les formats simples ; l\'analyse approfondie par IA nécessite une connexion et est mise en file d\'attente dans le cas contraire, sur le même mécanisme de synchronisation différée que le reste de la plateforme (voir chapitre 34).*

## **21.6 Abonnement IA professeur**

Assistant IA pour l\'enseignant, mensuel, indépendant du statut Pro de l\'établissement et de l\'abonnement IA élève. Ce forfait débloque uniquement l\'assistant conversationnel de l\'enseignant ; il ne donne pas accès à la banque de questions ni au moteur de quiz administrateur, réservés à l\'abonnement Premium élève (voir 21.4 et chapitres 10-11).

## **21.7 Autres usages de l\'IA**

-   **QR code pour la prise de présence** : scan rapide en début de cours pour l\'enregistrement des présences.

-   **Reconnaissance faciale**, en option, comme méthode alternative de prise de présence.

-   **Assistance à la déclaration de service** : suggestion de poste et de permissions lors de la création dynamique d\'un service par l\'établissement (voir 4.6), et suggestion assistée lors de la publication de contenu pédagogique par l\'Administrateur de contenu pédagogique (voir 30.5).

> ***Règle de gestion ---** l\'usage de la reconnaissance faciale, portant sur des données biométriques de mineurs, est soumis à un consentement parental explicite distinct de celui requis pour Parent IA, et doit rester une option désactivée par défaut, jamais un mode de prise de présence imposé (voir chapitre 34).*

# **22. Module --- Gamification et engagement**

Ce chapitre absorbe le module M16 d\'EduRéussite, entièrement nouveau pour EcoShop v2.0 : soutenir la motivation et la régularité de l\'élève par un système de récompense structuré et progressif, distinct des compétitions inter-établissements et des certificats décrits au chapitre 23.

## **22.1 Points d\'expérience (XP)**

  ----------------------------------------------------------------------------
  **Action**                                 **XP attribués**
  ------------------------------------------ ---------------------------------
  Bonne réponse                              +10

  Quiz terminé                               +50

  Examen (mode Examen) terminé               +100

  Série de 7 jours consécutifs d\'activité   +200

  Objectif quotidien atteint                 +30
  ----------------------------------------------------------------------------

> ***Règle de gestion ---** une modification ultérieure d\'une réponse déjà corrigée ne génère pas de nouveaux points d\'expérience. Une série de jours consécutifs est réinitialisée à zéro si l\'élève ne réalise aucune activité de révision pendant une journée calendaire complète, fuseau horaire du profil faisant foi.*

## **22.2 Niveaux progressifs et badges**

-   Sept niveaux progressifs, fondés sur le cumul d\'XP : Débutant, Apprenti, Élève motivé, Bon élève, Excellent, Expert, Champion.

-   Badges de réussite (constance, progression, maîtrise d\'une compétence) et défi quotidien personnalisable par matière.

## **22.3 Classements et gamification non comparative**

Les classements publics inter-élèves valorisent la performance relative et s\'articulent avec les classements par établissement, ville et région décrits au chapitre 23.

> ***Règle de gestion ---** pour les classes CP1 à CE2, les classements publics inter-élèves sont désactivés par défaut ; seule une progression personnelle (paliers, badges de constance) est affichée à l\'élève et à son parent, conformément au principe de gamification non comparative déjà posé en 9.6. Pour la Maternelle, aucun système de points, de niveau ou de classement n\'est jamais affiché à l\'enfant, conformément à la règle de 9.7.2 : la gamification décrite au présent chapitre ne s\'applique qu\'à partir du CP1.*

## **22.4 Articulation avec les autres modules**

-   L\'XP est généré par les activités des chapitres 10, 11, 13 et 15 (quiz, examens, préparation aux examens, missions du planificateur), jamais par la saisie de notes officielles (chapitre 12), qui reste hors du périmètre de la gamification.

-   Les niveaux et badges alimentent le profil public de l\'élève mobilisé par les compétitions et classements du chapitre 23.

# **23. Module --- Compétitions, classements et certificats**

Ce chapitre absorbe le module M26 d\'EduRéussite, entièrement nouveau pour EcoShop v2.0 : ancrer la reconnaissance de la réussite dans des formats de compétition familiers du contexte scolaire local (concours interne, tournoi inter-écoles) et offrir une valorisation formelle des parcours de maîtrise, au-delà de la seule gamification individuelle du chapitre 22.

## **23.1 Classements multi-échelles**

Le classement d\'un élève peut être consulté à plusieurs échelles : personnelle (progression propre), classe, établissement, ville, région, pays, et compétition internationale lorsqu\'un événement de ce type est organisé.

> ***Règle de gestion ---** un classement national ou régional ne mélange jamais les résultats de deux pays différents, conformément au principe d\'isolation par pays posé au référentiel pédagogique (voir 6.6) ; de même, un classement établissement ne fait apparaître que les élèves réellement rattachés à cet établissement pour l\'année scolaire en cours (voir 7.1).*

## **23.2 Concours privés et événements de compétition**

-   **Concours privés** : créés par un établissement pour ses propres élèves (voir 2.2 et 30), sur le même principe déclaratif que le rythme des compositions (voir 12.2) --- nombre de manches, matières, récompenses librement définis par la direction.

-   **Événements de compétition** organisés au niveau de la plateforme (tournoi, championnat, concours inter-écoles, olympiade), avec règles et récompenses paramétrables par Global Service Groupe.

-   Un événement de compétition peut, sans distinction technique particulière, être adossé à un espace de préparation aux examens nationaux du chapitre 13 (par exemple une olympiade de mathématiques organisée en amont du BEPC) ou rester totalement indépendant du référentiel d\'examens.

## **23.3 Certificat de maîtrise**

En fin de parcours de préparation ou de compétition, un certificat de maîtrise peut être délivré à l\'élève, distinct du bulletin officiel du chapitre 12 : il valorise un parcours de révision ou une performance de compétition, jamais une évaluation officielle de scolarité.

> ***Règle de gestion ---** chaque certificat délivré porte un identifiant unique vérifiable, permettant à un tiers (établissement, employeur, organisateur de concours) de confirmer son authenticité depuis un écran de vérification dédié, sans avoir à créer de compte sur la plateforme.*

## **23.4 Lutte contre la fraude au classement**

> ***Règle de gestion ---** un temps de réponse anormalement court associé à un taux de réussite anormalement élevé déclenche une exclusion temporaire du classement public concerné, en attente de vérification par l\'Administrateur de contenu pédagogique ou par l\'établissement organisateur d\'un concours privé. Cette exclusion ne retire jamais les points d\'expérience ou les résultats déjà enregistrés (voir chapitre 22) ; elle suspend uniquement leur visibilité dans un classement public le temps de la vérification.*

# **24. Module --- Transport scolaire**

Ce module n\'apparaissait dans la v1.2 que comme un service complémentaire générique (« transport scolaire »). L\'état réel du code en fait un module à part entière, avec suivi géolocalisé en direct.

## **24.1 Circuits et arrêts**

Définition des circuits de bus scolaire et de leurs arrêts par l\'établissement.

## **24.2 Affectation d\'élèves**

Attribution d\'un élève à un circuit de transport, visible depuis la fiche élève (chapitre 7) et depuis le sélecteur d\'enfant du compte parent (voir 5.1).

## **24.3 Suivi en direct**

Le chauffeur démarre un trajet et partage sa position ; le parent suit le trajet de son enfant en temps réel sur une carte.

> ***Règle de gestion ---** le chauffeur est un poste déclaré au sein du personnel de l\'établissement (rôle racine Direction, voir 4.1 et 4.6), avec un accès applicatif volontairement restreint au seul module Transport (démarrage/arrêt de trajet, partage de position) : il n\'a par défaut aucune visibilité sur les autres modules de l\'établissement. Le partage de position n\'est actif que pendant la durée du trajet déclaré, jamais en continu.*

## **24.4 Facturation transport**

Le transport est facturé via le même circuit de paiement que la scolarité (paiement libre et progressif, voir 17.1), sans système de facturation séparé.

# **25. Module --- Bibliothèque physique**

Module entièrement absent du cahier v1.2, présent dans l\'état réel du code. Il gère le fonds documentaire physique de l\'établissement --- livres et ouvrages empruntables sur place --- indépendamment des Ressources pédagogiques numériques décrites en 9.4 et de la bibliothèque numérique de flashcards et fiches détaillée au chapitre 26 : les trois ne doivent jamais être confondus, ni dans l\'interface ni dans le modèle de données, un livre physique n\'ayant ni statut d\'emprunt numérique ni équivalent flashcard.

## **25.1 Catalogue de livres**

Consultation du catalogue de livres disponibles à l\'établissement --- accès gratuit, sans abonnement, y compris pour un établissement en mode gratuit (voir 2.5) : la bibliothèque physique n\'est jamais une fonctionnalité premium.

## **25.2 Emprunt et retour**

Emprunt d\'un livre par un élève, retour enregistré par le personnel (poste bibliothécaire ou surveillant, selon l\'organisation déclarée par l\'établissement --- voir 4.6).

## **25.3 Statuts automatiques**

Un emprunt passe automatiquement « en retard » puis « perdu » selon un délai configurable, sans action manuelle.

> ***Règle de gestion ---** les seuils de délai (retard, perte) sont paramétrables par établissement (voir chapitre 31), sur le même principe de configuration non codée en dur que les autres seuils de la plateforme (rate limiting, seuil d\'effectif gratuit, score de fiabilité vendeur). Un emprunt marqué « perdu » de façon répétée pour un même élève peut être signalé à la vie scolaire (chapitre 19), sans automatisme disciplinaire imposé --- la décision reste à l\'appréciation de l\'établissement.*

## **25.4 Gestion d\'inventaire**

Ajout, modification et suivi des quantités disponibles par l\'administration.

# **26. Module --- Bibliothèque numérique et flashcards**

Ce chapitre absorbe le module M20 d\'EduRéussite, entièrement nouveau pour EcoShop v2.0. Il complète la révision structurée (chapitres 9 à 11) par des formats de mémorisation courts et des ressources téléchargeables, et reste strictement distinct de la bibliothèque physique du chapitre 25, comme rappelé en 25.1 : aucun statut d\'emprunt, aucune notion de retour ni de perte n\'existe pour le contenu de ce chapitre.

## **26.1 Contenu de la bibliothèque numérique**

-   Fiches, résumés, formules, cartes mémoire, documents pédagogiques, contenus audio, rattachés au référentiel de contenu (chapitre 6) au même titre que les leçons du chapitre 9.

-   Les **Ressources pédagogiques** ajoutées par les enseignants de l\'établissement (voir 9.4) sont également consultables sous forme de fiches et flashcards depuis ce même espace, en complément du contenu édité par Global Service Groupe.

## **26.2 Flashcards**

Cartes mémoire consultables en session dédiée, avec détermination automatique des cartes à revoir selon la performance de l\'élève.

> ***Règle de gestion ---** la file de cartes à revoir s\'appuie sur le même mécanisme de répétition espacée que celui décrit en 15.1 : une carte marquée comme non maîtrisée réintègre le calendrier de rappel (J1, J2, J4, J7, J14, J30) au même titre qu\'une notion apprise en quiz, sans logique de mémorisation distincte propre aux flashcards.*

## **26.3 Révision audio téléchargeable**

Définitions, cours courts, vocabulaire, résumés et rappels disponibles en version audio téléchargeable, pour un usage hors connexion intégral (voir chapitre 34). Ce format rejoint, pour les classes supérieures, le principe audio-first déjà retenu pour les classes CP1 à CE2 (voir 9.6), en lui donnant ici une vocation de révision autonome plutôt que d\'accompagnement de la lecture.

## **26.4 Règle de gestion**

> ***Règle de gestion ---** aucun contenu de la bibliothèque numérique n\'est publié sans licence claire ou production propre validée par l\'Administrateur de contenu pédagogique, selon le même workflow Brouillon → Révision pédagogique → Validation → Publication que celui appliqué aux leçons (voir 9.3 et 30.5).*

# **27. Module --- Marketplace (EcoShop Market)**

Cette révision intègre au présent module le cadre financier et contractuel détaillé transmis sous le nom d\'AssoShop (module École & Marketplace scolaire) : architecture de sous-comptes marchands par établissement, isolation financière des vendeurs tiers, compte auxiliaire et règlement différé, convention vendeur-établissement. Conformément à la méthode de fusion posée en 1.2, ce cadre, plus précis que la description initiale d\'EcoShop Market sur le seul volet paiement et livraison, est retenu et vient préciser --- parfois en le corrigeant explicitement, voir 27.4 --- le modèle déjà posé en 27.1 à 27.10 ; les apports propres au règlement différé et au cadre contractuel sont regroupés en 27.11 à 27.15.

## **27.1 Concept : marketplace scolaire contrôlée**

EcoShop Market repose sur trois principes structurants : seuls les vendeurs validés par l\'administrateur Global Service Groupe peuvent vendre ; seuls les membres d\'un établissement rattaché à la plateforme peuvent acheter --- élèves, parents, mais aussi enseignants et personnels d\'encadrement (matrones, monitrices) ; tous les produits sont livrés à un point unique, l\'établissement scolaire, et non au domicile de l\'acheteur.

## **27.2 Gestion des vendeurs**

-   **Inscription contrôlée** : demande de création de compte Vendeur, soumise à validation de l\'administration Global Service Groupe (vérification de l\'identité, du type de produits proposés et de l\'autorisation légale d\'exercer --- voir 5.3 et 30.2).

-   **Profil vendeur** : nom du commerce, produits proposés, évaluations et réputation, historique des ventes.

-   **Validation des demandes vendeur** : y compris le traitement des vendeurs suspendus pour non-respect du SLA (voir 27.5), qui doivent repasser par une validation explicite pour être réactivés (voir 30.2).

-   **Chaîne d\'agrément multi-établissements** : une fois son compte validé par Global Service Groupe, le vendeur peut solliciter un rattachement auprès d\'un ou plusieurs établissements de la plateforme pour y proposer ses produits. Chaque établissement instruit et valide --- ou refuse --- individuellement cette demande d\'affiliation depuis son tableau de bord : un vendeur agréé par Global Service Groupe ne peut vendre au sein d\'un établissement donné sans l\'accord explicite et distinct de celui-ci, formalisé par la convention décrite en 27.14.

## **27.3 Catalogue de produits**

Types de produits autorisés : fournitures scolaires, livres, uniformes, gadgets éducatifs, et nourriture si l\'établissement l\'autorise. Le catalogue applique une **priorité géographique** : les produits des vendeurs de la même ville que l\'établissement sont mis en avant en premier, avec repli sur les vendeurs du pays si l\'offre locale est insuffisante.

## **27.4 Expérience d\'achat**

-   Navigation : recherche de produits, catégories, produits recommandés (assistée par l\'IA de recommandation, voir 27.9).

-   **Panier mono-vendeur** : un panier de commande ne peut contenir simultanément que des articles issus d\'un seul et même vendeur ; l\'ajout d\'un produit d\'un autre vendeur impose soit la finalisation de la commande en cours, soit la vidange du panier existant. Un acheteur souhaitant commander auprès de plusieurs vendeurs procède donc par commandes successives et indépendantes, chacune avec son propre suivi (voir 27.5--27.6).

-   **Horaire limite de commande (cut-off time)** : pour les produits à péremption rapide ou la restauration scolaire (cantine), le vendeur définit une heure limite journalière de prise de commande (par exemple, commande au plus tard à 07h00 pour une livraison prévue à 13h00) ; passé cet horaire, le système verrouille automatiquement toute nouvelle commande ou modification pour la tranche horaire concernée.

-   **Paiement CinetPay obligatoire, crédité au sous-compte établissement** : jamais en espèces ; le règlement est directement crédité, via l\'agrégateur CinetPay, sur le sous-compte marchand ouvert par l\'établissement sélectionné comme point de retrait --- jamais sur un compte propre au vendeur (voir 27.11). La commission Global Service Groupe de 3 % est prélevée à la source par l\'agrégateur au moment de la transaction (split payment), sans reversement manuel ultérieur. Le paiement peut être effectué via le compte scolaire de l\'élève, ou directement par le parent, l\'enseignant ou l\'encadreur acheteur.

> ***Règle de gestion ---** cette révision remplace le panier multi-vendeur décrit jusqu\'ici (scission automatique en sous-commandes par vendeur au paiement) par la contrainte de panier mono-vendeur posée par le cadre AssoShop, retenue conformément à la méthode de fusion du chapitre 1.2 : elle simplifie la gestion de l\'horaire limite de commande propre à chaque vendeur (ci-dessus), évite qu\'une même transaction de paiement doive être scindée entre plusieurs sous-comptes établissement lors du split payment (27.11), et rattache la responsabilité de livraison à un seul vendeur par commande.*

## **27.5 Livraison et SLA**

-   **Point de livraison unique** : tous les produits commandés pour les élèves d\'un établissement arrivent à l\'école, sous la responsabilité d\'un responsable désigné (économe ou surveillant).

-   **SLA de livraison** : délai de livraison déclaré par le vendeur à la commande ; en cas de dépassement, remboursement automatique de l\'acheteur et réduction correspondante du solde théorique crédité au vendeur sur son compte auxiliaire (voir 27.12) --- le vendeur ne détenant aucun portefeuille propre auprès de l\'agrégateur (27.11), cet ajustement reste interne à la plateforme, jamais un débit réel sur un compte vendeur.

-   **Score de fiabilité vendeur** : calculé sur les 30 derniers jours glissants ; suspension automatique du vendeur au-delà d\'un seuil de retards (seuil paramétrable, voir 30.2).

## **27.6 Réception et remise des colis**

-   **Réception** : scan du colis par QR code, enregistrement automatique dans le système.

-   **Remise à l\'élève** : notification envoyée, signature ou validation requise, historique de retrait conservé.

Un manquement constaté au retrait (comportement, falsification de justificatif) peut être consigné comme incident disciplinaire (voir 19.4).

## **27.7 Gestion des stocks et commandes abandonnées**

-   **Gestion des stocks** : décrément atomique du stock à la confirmation du paiement, avec gestion propre d\'une rupture de stock (remboursement automatique de l\'acheteur, notification au vendeur).

-   **Purge des commandes abandonnées** : une commande jamais payée est automatiquement marquée expirée après un délai configurable, libérant le stock réservé.

## **27.8 Modèle économique de la marketplace**

-   Commission Global Service Groupe de 3 % prélevée à la source sur chaque vente lors du split payment (voir 27.11).

-   Abonnement vendeur.

-   Frais de livraison interne.

-   Mise en avant payante de produits.

Ces revenus, lorsque l\'établissement en perçoit une quote-part, alimentent ses rapports financiers (voir 17.5 et chapitre 32).

## **27.9 Sécurité, traçabilité, litiges et fonctionnalités avancées**

-   Règles strictes : produits validés, vendeurs certifiés, transactions traçables.

-   Gestion des litiges : produit non conforme, retard de livraison, remboursement, ainsi que les contestations de règlement différé entre établissement et vendeur (voir 27.13).

-   Livraison programmée à jours précis ; commandes groupées, permettant une réduction des coûts de livraison.

-   Intelligence artificielle de recommandation de produits utiles aux élèves.

## **27.10 Tableaux de bord**

-   Côté établissement : volume des ventes, revenus générés pour l\'école, activité des vendeurs.

-   Côté vendeur : commandes, revenus, produits les plus populaires, répartition prix / commission / net disponible.

## **27.11 Sous-comptes marchands établissement et isolation financière des vendeurs tiers**

Le modèle financier de la marketplace distingue strictement deux niveaux de compte auprès de l\'agrégateur de paiement CinetPay.

-   **Sous-compte marchand établissement** : chaque établissement partenaire de la marketplace dispose de son propre sous-compte marchand auprès de CinetPay. Tout paiement effectué sur la plateforme (Mobile Money, carte bancaire) pour une commande dont cet établissement est le point de retrait est directement crédité sur ce sous-compte.

-   **Absence de portefeuille vendeur** : le vendeur ne dispose d\'aucun compte, wallet ni enregistrement financier propre auprès de l\'agrégateur de paiement : aucun risque de dispersion des fonds de la plateforme entre de multiples comptes marchands tiers non supervisés.

-   **Règlement différé hors plateforme** : le règlement de la marchandise ou de la prestation au vendeur est réalisé par l\'établissement --- virement, chèque ou espèces --- après livraison effective et validation de réception (voir 27.6), selon les modalités fixées par la convention de partenariat (voir 27.14).

> ***Règle de gestion ---** cette architecture à deux niveaux (sous-compte établissement + absence de portefeuille vendeur) prévaut sur toute lecture antérieure qui laisserait entendre l\'existence d\'un compte ou d\'un solde directement détenu par le vendeur auprès de l\'agrégateur ; le seul solde attribué à un vendeur dans le système est le solde théorique du compte auxiliaire décrit en 27.12, purement déclaratif et sans existence bancaire propre. Conformément à KER-REF-05 (GSG Platform Kernel v3.0), tout montant manipulé par ce module --- solde théorique inclus --- est stocké en unité mineure entière (centime de franc guinéen ou de franc CFA, sans décimale --- voir KER-REF-02), jamais en nombre à virgule flottante.*

## **27.12 Compte auxiliaire marchand et registre de créance**

Pour chaque établissement, la plateforme tient à jour un compte auxiliaire --- registre virtuel --- par vendeur affilié.

-   **Crédit automatique** : dès que l\'établissement valide la réception effective d\'une livraison (voir 27.6), le montant net dû au vendeur (montant total de la commande, diminué de la commission établissement éventuelle prévue par la convention --- voir 27.14) est automatiquement crédité au solde théorique du vendeur, visible depuis le tableau de bord de l\'établissement et depuis celui du vendeur.

-   **Ajustements** : ce même solde théorique absorbe, en sens inverse, les réductions liées à une SLA de livraison non respectée (voir 27.5) ou à un litige tranché en défaveur du vendeur (voir 27.9).

> ***Règle de gestion ---** le compte auxiliaire est un registre de créance interne à la plateforme, jamais un compte bancaire ou un portefeuille électronique réglementé ; il ne déclenche aucun mouvement de fonds automatique vers le vendeur, le règlement effectif restant du ressort de l\'établissement (27.11 et 27.13).*

## **27.13 Règlement différé, acomptes et double validation**

Un vendeur peut recevoir un règlement partiel (acompte) lorsque l\'établissement fait face à une illiquidité temporaire, selon le cycle suivant : (1) déclaration établissement --- l\'établissement enregistre le versement effectué (montant, mode de paiement : espèces, chèque, virement, Mobile Money) et le marque « Versé » ; le montant correspondant passe au statut En attente de confirmation vendeur ; (2) confirmation vendeur --- le vendeur valide la bonne réception des fonds depuis son interface ; (3) mise à jour du solde --- le montant restant dû (solde théorique cumulé, diminué du total des versements confirmés) est recalculé et affiché en temps réel aux deux parties.

> ***Règle de gestion ---** en cas de contestation du vendeur sur un versement déclaré par l\'établissement, la transaction bascule au statut Litige et est soumise à l\'arbitrage de l\'administration Global Service Groupe (voir 30.2), selon le même principe de médiation que les litiges de livraison posés en 27.9.*

## **27.14 Cadre contractuel vendeur-établissement**

L\'affiliation d\'un vendeur à un établissement (voir 27.2) ne devient effective pour l\'affichage de ses produits qu\'après approbation, par les deux parties, d\'une convention de partenariat dématérialisée sur la plateforme.

-   **Clauses paramétrées** : délai maximal de règlement après livraison (par exemple règlement sous 7 jours, règlement hebdomadaire, règlement à la livraison), taux de commission éventuellement prélevé par l\'établissement, conditions de pénalité ou de suspension de la boutique en cas de retard de livraison ou de règlement répété.

-   **Traçabilité et immuabilité** : chaque convention validée conserve l\'horodatage, l\'identité des deux signataires et la version des termes acceptés ; vendeur et établissement disposent d\'un accès permanent en lecture seule à la convention en vigueur depuis leur tableau de bord respectif.

-   **Avenants** : toute modification des clauses (délais, tarifs, commissions) exige une réédition de l\'accord et une validation bilatérale explicite avant prise d\'effet ; l\'ancienne version reste consultable dans l\'historique.

> ***Règle de gestion ---** les seuils par défaut proposés à la création d\'une convention (délai de règlement, plafond de commission établissement) sont paramétrables depuis le Backoffice Global Service Groupe (voir 30.4), jamais codés en dur, conformément au principe transversal de configuration posé en 30.4.*

## **27.15 Statut Visiteur et continuité d\'accès marketplace**

Un élève quittant l\'établissement auquel son compte est rattaché, pour rejoindre un établissement non partenaire de la plateforme, bascule automatiquement --- ainsi que son compte parent associé --- sous un statut Visiteur.

> ***Règle de gestion ---** le statut Visiteur ne retire aucun accès à la marketplace : il retire uniquement le rattachement à un établissement pour les modules de gestion scolaire (chapitres 7 à 20), qui perdent leur pertinence hors de la plateforme. L\'accès aux achats marketplace reste possible, à condition que l\'acheteur sélectionne, à chaque commande, un établissement actif de la plateforme comme point de retrait (voir 27.1) --- qui n\'est alors pas nécessairement l\'établissement d\'origine de l\'élève. Ce statut, distinct des rôles racines du chapitre 4, est un état du compte plutôt qu\'un rôle à part entière ; il n\'affecte ni l\'authentification (chapitre 5) ni l\'historique déjà produit par le compte.*

# **28. Établissements indépendants et réseaux d\'établissements**

Ce chapitre distingue deux situations qui ne doivent jamais être confondues dans le modèle de données ni dans les permissions : l\'hébergement multi-établissements par défaut, et le réseau d\'établissements constitué volontairement.

## **28.1 Établissements indépendants (hébergement multi-établissements)**

La plateforme héberge, par défaut, une multitude d\'établissements sans aucun lien entre eux. Chaque établissement dispose d\'un espace complètement étanche : ses élèves, ses enseignants, sa comptabilité lui sont propres. L\'établissement A n\'a aucune visibilité sur l\'existence de l\'établissement B, même s\'ils sont hébergés sur la même plateforme.

> ***Règle de gestion ---** aucun rôle « Fondateur » ni « responsable multi-établissement » n\'existe à ce niveau : seul l\'administrateur Global Service Groupe supervise l\'ensemble de ces établissements indépendants, chacun restant une entité de gestion isolée.*

## **28.2 Réseaux d\'établissements**

Un réseau d\'établissements regroupe des écoles appartenant à une même organisation, avec une administration générale. Les écoles conservent une autonomie locale tout en partageant une structure ou une vision commune, sous un niveau « Siège » --- la Direction Générale --- qui dispose d\'une vue consolidée sur l\'ensemble des écoles du réseau. Le compte à l\'origine de cette Direction Générale est celui du rôle racine « Fondateur de réseau » décrit en 4.2 et 5.3.

-   La création d\'un réseau fait naître une Direction Générale, dont les paramètres restent modifiables après la création du réseau.

-   Comptabilité et rapports consolidés : la Direction Générale visualise en un coup d\'œil des indicateurs agrégés sur tout le réseau (taux de recouvrement des frais de scolarité, nombre total d\'élèves\...).

-   Tableau de bord du réseau : comparaison entre les différents établissements du réseau (statistiques, performance, effectifs).

-   L\'harmonisation de la gestion entre les écoles d\'un même réseau (transferts d\'élèves, frais de scolarité) n\'est pas automatique : elle dépend du paramétrage choisi par la Direction Générale.

## **28.3 Création, invitation et annuaire**

-   **Création de réseau** : un directeur d\'établissement ou un fondateur indépendant peut créer un réseau, initialement vide, via un formulaire dédié. Les informations requises incluent : nom du réseau, courriel, téléphone, adresse, premier responsable, dénomination, devise, entre autres champs obligatoires. La création est systématiquement soumise à la validation de Global Service Groupe (voir 30.2) ; un courriel automatique confirme la soumission au demandeur.

-   **Invitation d\'établissements** : recherche d\'un établissement par nom et envoi d\'une invitation à rejoindre le réseau.

-   **Annuaire de recherche** : recherche insensible à la casse et aux accents pour retrouver un établissement à inviter.

-   C\'est uniquement au niveau de la création d\'un réseau qu\'un frais de création est exigé (voir 17.7) --- la simple création d\'un établissement indépendant n\'y est pas soumise.

## **28.4 Retrait et dissolution**

-   Un établissement peut quitter un réseau (retrait) ; le réseau entier peut être dissous (dissolution).

-   Les deux opérations exigent une **double confirmation** dans l\'interface, distincte l\'une de l\'autre : un retrait d\'établissement ne dissout pas le réseau, et une dissolution de réseau doit être explicitement différenciée d\'un simple retrait dans le parcours de confirmation.

> ***Règle de gestion ---** un établissement admis dans un réseau ne peut plus en être retiré que sur permission explicite de Global Service Groupe : la double confirmation côté interface ne remplace pas cette validation de plateforme, elle s\'y ajoute --- le retrait n\'est finalisé qu\'une fois l\'autorisation GSG accordée.*

## **28.5 Tableau de bord réseau**

Vue consolidée des établissements membres pour le directeur du réseau, reprise dans le module Reporting (voir 29.1).

## **28.6 Règle d\'unicité d\'inscription, valable pour tous**

La règle d\'unicité d\'un élève sur la plateforme (voir 7.1) s\'applique indifféremment aux établissements indépendants et aux réseaux d\'établissements, y compris lorsque la gestion du réseau n\'est pas harmonisée (voir 28.2).

# **29. Module --- Reporting et tableaux de bord**

La v1.2 dispersait ces éléments entre plusieurs sections (rapports financiers, statistiques pédagogiques, tableau de bord réseau). L\'état réel du code en fait un module dédié, point de restitution commun à l\'ensemble des autres modules --- désormais enrichi, par la fusion avec EduRéussite, des statistiques du moteur de révision (chapitres 10 à 15) et des compétitions (chapitre 23), qui n\'avaient pas d\'équivalent dans EcoShop v2.0.

## **29.1 Tableau de bord Directeur**

Vue temps réel pour un établissement, agrégeant :

-   l\'effectif de l\'établissement ;

-   le taux de recouvrement des frais (voir 17.4) ;

-   le montant impayé (voir 17.5) ;

-   le taux d\'absentéisme (voir 12.5) ;

-   le nombre d\'élèves à risque d\'échec (voir 12.7) ;

-   l\'indicateur de couverture de contenu par matière, alimentant la pertinence du Tuteur IA (voir 21.4).

Pour un réseau d\'établissements, ce tableau de bord se prolonge par la vue consolidée de la Direction Générale (voir 28.2 et 28.5).

## **29.2 Alertes proactives**

-   Signalement automatique d\'un taux d\'impayés au-delà d\'un seuil paramétrable (voir chapitre 31).

-   Signalement automatique d\'un contrat RH arrivant à expiration (voir 8.4).

-   Ces deux alertes rejoignent l\'alerte de bascule d\'année scolaire décrite en 17.7 dans le centre de notifications (voir 20.2).

## **29.3 Statistiques et export établissement**

Au-delà du tableau de bord temps réel, la Direction dispose d\'un espace de statistiques consolidées et d\'export, distinct de l\'analyse de classe destinée à l\'enseignant (voir 9.2 et 14.1).

-   **Comparaison inter-classes** : moyennes officielles, taux de réussite et niveau de maîtrise moyen par compétence, comparés entre les classes d\'un même niveau (voir 14.1), à l\'usage de la direction pédagogique plutôt que d\'un enseignant isolé.

-   **Export** : les rapports financiers (voir chapitre 17), les bulletins groupés (voir 12.4) et les statistiques consolidées sont exportables aux formats Excel et PDF, sur le même moteur de templates que les autres documents de la plateforme (voir chapitre 18).

-   **Concours internes** : les résultats des concours privés organisés par l\'établissement (voir 23.2) sont restitués dans ce même espace de statistiques consolidées, distincts des statistiques de révision individuelle de chaque élève.

> ***Règle de gestion ---** les statistiques consolidées de ce chapitre s\'appuient exclusivement sur les notes officielles (chapitre 12) pour tout indicateur qualifié de « moyenne » ou de « taux de réussite » scolaire ; les résultats d\'entraînement du moteur de révision n\'y apparaissent que sous un libellé explicite (« maîtrise par compétence », « score de préparation ») afin de préserver, à l\'échelle du reporting établissement, la distinction posée en 12.6.*

# **30. Backoffice Global Service Groupe**

Ce chapitre consolide les mentions éparses de la v1.2 (validation des créations, barème paramétrable) en un module d\'administration de plateforme à part entière, distinct du modèle « établissement ». La fusion avec EduRéussite y ajoute un domaine entièrement nouveau, le CMS pédagogique (30.5), condition de la scalabilité du contenu de révision sans intervention d\'un développeur à chaque nouvelle question ou activité.

## **30.1 Validation des demandes**

-   **Validation des demandes d\'établissement** : traitement des demandes de création d\'établissement reçues (voir 5.3).

-   **Validation des demandes de réseau** : traitement des demandes de création de réseau (voir 28.3).

## **30.2 Validation des demandes vendeur**

Traitement des demandes de compte Vendeur marketplace (voir 5.3 et 27.2), y compris la réactivation des vendeurs suspendus pour non-respect du SLA de livraison (voir 27.5). Le Backoffice GSG est également l\'instance d\'arbitrage des litiges de règlement différé entre établissement et vendeur (voir 27.13) et des litiges de livraison (voir 27.9).

## **30.3 Vue d\'ensemble des réseaux**

Consultation en lecture seule des réseaux d\'établissements créés (voir chapitre 28), sans droit d\'intervention directe dans leur gestion courante --- celle-ci reste de la responsabilité de la Direction Générale du réseau.

## **30.4 Paramètres globaux**

Configuration du barème tarifaire et des seuils de la plateforme, jamais codés en dur :

-   tranches de l\'abonnement Pro établissement (voir 2.4 et 17.7) ;

-   frais IA admin annuel, tarifs des abonnements IA élève et professeur (voir 17.7 et chapitre 21) ;

-   commission marketplace et seuils du score de fiabilité vendeur (voir 27.5 et 27.8) ;

-   délai maximal de règlement par défaut et plafond de commission établissement pour les conventions vendeur-établissement (voir 27.14) ;

-   seuils d\'alerte (impayés, contrats RH expirant --- voir 29.2) ;

-   activation de la fédération d\'identité GSG ID pour l\'établissement ou le réseau concerné, lorsque cette option est ouverte (voir 5.5) ;

-   délais de retard/perte de la bibliothèque physique (voir 25.3) ;

-   seuil d\'âge de bascule vers le mode élève supervisé, paramétrable par pays (voir 4.3) ;

-   plafonds quotidiens de quiz et de répétition espacée pour les classes CP1 à CE2 (voir 9.6 et 15.1).

> ***Règle de gestion ---** cette exigence de configuration non codée en dur, déjà présente ponctuellement dans la v1.2, est élevée ici au rang de principe transversal : tout seuil, tarif ou barème mentionné dans ce cahier doit être modifiable depuis le Backoffice Global Service Groupe sans nouvelle publication de l\'application cliente (voir également chapitre 34).*

## **30.5 CMS pédagogique et Administrateur de contenu pédagogique**

Ce domaine, entièrement absent d\'EcoShop v2.0, absorbe le module M24 d\'EduRéussite : il permet la création et la publication de contenu pédagogique (programmes, matières, chapitres, leçons, questions, activités Maternelle) sans intervention d\'un développeur, sous la responsabilité de l\'Administrateur de contenu pédagogique (voir 4.4).

-   **Back-office du référentiel** : gestion des pays, cycles, niveaux, examens et filières (chapitre 6), des programmes officiels versionnés par année scolaire et de leurs matières.

-   **CMS de création de question** : formulaire structuré reprenant l\'intégralité des métadonnées obligatoires du chapitre 10 (pays, classe, matière, chapitre, leçon, compétence, type, difficulté, énoncé, choix, bonne réponse, explication, source pédagogique).

-   **Formulaire dédié à l\'activité ludo-éducative Maternelle** (domaine de développement, format d\'activité, ressources audio et illustrées, consigne vocale), distinct du formulaire de question standard et soumis à son propre circuit de validation, cohérent avec les exigences de 9.7.

-   **File de validation** : vue de travail listant tout contenu au statut Révision pédagogique, à l\'usage des profils habilités à faire progresser un contenu vers la Validation.

> ***Règle de gestion ---** aucune question, leçon ou activité Maternelle créée via le CMS --- y compris lorsqu\'elle est générée par IA --- ne peut atteindre le statut Publication sans être passée par le statut Validation, attribué par un profil habilité distinct de son auteur lorsque l\'auteur n\'est pas lui-même l\'Administrateur de contenu pédagogique. Ce workflow Brouillon → Révision pédagogique → Validation → Publication, déjà posé en 9.3, 13.4 et 26.4, est unique et partagé par tous les types de contenu pédagogique de la plateforme. Chaque contenu conserve son auteur, son validateur, sa date, sa version, son programme officiel rattaché, sa source et son statut, condition d\'une traçabilité qualité complète.*

## **30.6 Révocation de session à distance**

Outil de révocation de session d\'un compte compromis, en lien avec l\'authentification native Supabase Auth (voir 5.7).

# **31. Module --- Paramétrage et personnalisation**

-   Logo et identité visuelle de l\'établissement, gestion des thèmes graphiques --- personnalisation réservée aux établissements en mode payant (voir 2.5).

-   **Espace de personnalisation des templates de documents officiels** (reçus, bulletins, certificats, attestations, cartes scolaires) : décrit en détail au chapitre 18, également réservé au mode payant.

-   Système de notation (sur 20, sur 10, etc.).

-   Langues disponibles (français, anglais\...).

-   Déclaration des niveaux présents dans l\'établissement (crèche, maternelle, primaire, collège, lycée) et des postes attribués à chacun, avec création dynamique des services associés (voir 4.6).

-   Configuration des classes, cycles et des services annexes actifs (cantine, internat --- voir 19.3).

-   **Sélection des classes proposées par l\'établissement au sein du référentiel pédagogique multi-pays** : l\'établissement choisit, parmi les pays_niveau existants pour le pays où il opère (voir 6.2 et 7.3), les classes qu\'il propose réellement ; cet écran ne donne en revanche aucun droit de modification sur le référentiel lui-même (ajout d\'un pays, d\'un cycle, d\'un examen), qui reste un privilège de plateforme réservé au Backoffice GSG et à l\'Administrateur de contenu pédagogique (voir 30.5 et 6.6).

-   Configuration des échéances de paiement indicatives par modalité (voir 7.2), des délais de la bibliothèque physique (voir 25.3) et des circuits de transport (voir 24.1).

-   Animations d\'interface, intégrées aux paramètres globaux de l\'application.

> ***Règle de gestion ---** le paramétrage établissement (ce chapitre) et les paramètres globaux plateforme (chapitre 30) forment deux couches distinctes : le premier ajuste l\'expérience d\'un établissement donné dans les limites que le second autorise --- un établissement ne peut par exemple pas s\'auto-attribuer un seuil de gratuité supérieur à celui fixé par Global Service Groupe, ni ajouter de lui-même une classe ou un examen absent du référentiel pédagogique multi-pays.*

# **32. Relations entre les gestions**

EcoShop n\'est pas une juxtaposition de modules indépendants : chaque gestion s\'appuie sur des données ou des règles produites par une autre. Le tableau suivant explicite les principales relations structurantes, qui doivent guider la conception du modèle de données. Il reprend et complète le tableau de la v2.0 avec les modules issus de la fusion avec EduRéussite (repérés par ✦✦).

  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Gestion source**                                                **Gestion liée**                                                                           **Nature de la relation**
  ----------------------------------------------------------------- ------------------------------------------------------------------------------------------ ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Authentification (5)                                              Tous les modules                                                                           Le rôle racine et le poste déclaré, stockés dans la table \`profiles\` et recopiés dans le jeton par le Custom Access Token Hook de l\'authentification native Supabase Auth, conditionnent chaque action dans chaque module.

  Authentification (5)                                              Administration / Scolarité (7), RH (8)                                                     L\'identifiant généré ou le matricule permet à un compte créé après coup de retrouver et rattacher une fiche élève ou personnel préexistante.

  Administration (inscription, 7)                                   Établissements de la plateforme (28)                                                       Un élève ne peut être inscrit que dans un seul établissement de la plateforme par année, qu\'il s\'agisse d\'établissements indépendants ou de réseaux ; alerte à l\'agent et notification inter-établissements.

  Administration (réinscription, 7)                                 Financière (17) / Discipline (19) / Notes (12)                                             La réinscription vérifie automatiquement les impayés, le statut boursier, les sanctions et l\'admission en classe supérieure.

  Référentiel pédagogique (6) ✦✦                                    Scolarité (7) / Académique (9) / Moteur de questions (10)                                  Le référentiel structurel (pays, cycle, niveau, examen, filière) fournit les classes sur lesquelles s\'appuient la déclaration des classes d\'un établissement et l\'ensemble du contenu pédagogique versionné.

  Référentiel pédagogique (6) ✦✦                                    Préparation aux examens nationaux (13)                                                     Un pays_examen déclaré et publié au référentiel pilote automatiquement l\'affichage d\'un espace de préparation, sans liste d\'examens codée en dur.

  Personnel --- Enseignants (8)                                     Académique / Notes (9, 12)                                                                 Un enseignant multi-établissement dispense des cours et saisit des notes propres à chaque établissement où il est affecté.

  Personnel --- Congés (8)                                          Emploi du temps (16)                                                                       Un congé d\'enseignant annule automatiquement les séances concernées et déclenche la notification d\'annulation, sans double saisie.

  Académique (cahier de texte, 9)                                   Pédagogie avancée / e-learning (9.4), IA élève (21.4)                                      Un devoir ou un support de cours publié en présentiel peut être prolongé en ligne ; les contenus versés par l\'enseignant alimentent la pertinence du Tuteur IA.

  Moteur de questions (10) ✦✦                                       Académique --- devoirs numériques (9.2) / Quiz-Examen (11) / Recommandation (14)           La banque de questions, structurée par compétence et difficulté, alimente à la fois les devoirs numériques créés par l\'enseignant, les quiz et examens de l\'élève, et le moteur de recommandation.

  Quiz et mode Examen (11) ✦✦                                       Notes et bulletins --- 12.6                                                                Les résultats produits par le moteur de quiz et le mode Examen sont des résultats d\'entraînement formatifs : ils n\'entrent jamais dans le calcul de la moyenne officielle ni dans le bulletin.

  Notes et bulletins (12)                                           Financière (reçus, 17) / Documents (18)                                                    Les bulletins et reçus partagent le même moteur de génération PDF et le même espace de personnalisation de templates (chapitre 18).

  Espace de personnalisation des templates (18) ✦✦                  Paramétrage établissement (31) / Réseau (28.2) / Mode gratuit (2.5)                        L\'accès à l\'espace est réservé au mode payant et administré depuis le Backoffice établissement ; une Direction Générale de réseau peut proposer un template harmonisé, chaque établissement membre restant libre de l\'adopter.

  Notes --- Risque d\'échec (12.7)                                  Intelligence artificielle (21.1) / Analyse des compétences (14.1)                          Le score de risque d\'échec alimente le rapport groundé et pseudonymisé du Chat IA Directeur-Adviser, et peut être recoupé, à titre indicatif seulement, avec le niveau de maîtrise par compétence issu du moteur de révision.

  Préparation aux examens nationaux (13) ✦✦                         Scolarité --- classe d\'examen (7.3)                                                       Seules les classes héritant de l\'attribut est_niveau_examinateur de leur pays_niveau affichent un espace de préparation aux examens nationaux.

  Analyse des compétences (14) ✦✦                                   Moteur de recommandation / Répétition espacée (14.2, 15)                                   Les règles de transition du moteur de recommandation déclenchent notamment la répétition espacée d\'une notion oubliée et alimentent le planificateur intelligent.

  Répétition espacée (15) ✦✦                                        Bibliothèque numérique --- flashcards (26.2)                                               Une flashcard non maîtrisée réintègre le même calendrier de rappel (J1, J2, J4, J7, J14, J30) qu\'une notion apprise en quiz, sans logique de mémorisation distincte.

  Financière (caisse, 17)                                           Personnel (salaires, 8)                                                                    Encaissements de scolarité (entrées) et sorties liées aux salaires alimentent le même cahier journal simplifié.

  Financière (comptabilité analytique, 17)                          Tous les modules                                                                           Le suivi budgétaire par chapitre/article agrège les dépenses et recettes de l\'ensemble des services de l\'école, y compris les revenus marketplace, transport et abonnements individuels de révision.

  Financière --- traçabilité des transactions (17.8) ✦✦             Financière --- paiement scolaire (17.2) / IA (21.4, 21.6)                                  L\'activation automatique différée et la journalisation complète des transactions s\'appliquent indifféremment au paiement scolaire encaissé par l\'établissement et aux abonnements individuels (Premium élève, IA professeur).

  Vie scolaire (paramétrage cantine/internat, 19)                   Paramétrage établissement (31)                                                             L\'activation des cycles et services conditionne l\'affichage de ces modules pour tous les rôles.

  Communication --- Groupes de discussion (20)                      Discipline (19)                                                                            Un message signalé et modéré peut être escaladé en incident disciplinaire au dossier de l\'élève.

  Espace parent                                                     Financière / Marketplace / Communication / Transport                                       Le paiement en ligne, les achats marketplace, les notifications et le suivi GPS du transport convergent vers un même compte parent.

  Élève supervisé (4.3) ✦✦                                          Authentification --- parcours dédié (5.2) / Académique --- primaire (9.6)                  Le mode supervisé conditionne le parcours de création de compte par le parent et les restrictions fonctionnelles (communication, classement public) appliquées au contenu académique du primaire.

  Maternelle (9.7) ✦✦                                               Gamification (22.3)                                                                        Aucune gamification chiffrée (points, niveau, classement) n\'est jamais affichée à l\'enfant en Maternelle ; seule la vie scolaire administrative et la console parent s\'appliquent à ce public.

  Marketplace --- achat (27)                                        Espace élève / parent                                                                      L\'achat est initié depuis le compte élève ou parent, avec paiement CinetPay, via le compte scolaire ou paiement direct.

  Marketplace --- livraison (27)                                    Vie scolaire (infrastructures / discipline, 19)                                            La réception et la remise des colis s\'effectuent au sein de l\'établissement, sous la responsabilité de l\'économe ou du surveillant ; un incident au retrait peut générer une sanction.

  Marketplace --- revenus (27)                                      Financière (rapports, 17)                                                                  Les commissions et frais de livraison perçus par l\'établissement, le cas échéant, sont intégrés aux rapports financiers.

  Marketplace --- règlement différé (27.11--27.13)                  Financière (passif, 17.5)                                                                  Le compte auxiliaire par vendeur et le solde théorique qu\'il porte constituent un passif de l\'établissement envers ses vendeurs affiliés, suivi au même endroit que les recettes de l\'établissement (cahier journal, 17.4-17.5) mais jamais confondu avec elles ; un litige de règlement différé non résolu entre les deux parties est arbitré par le Backoffice GSG (30.2).

  Marketplace --- achat (27)                                        Personnel (enseignants, matrones, monitrices)                                              Au-delà des élèves et parents, les enseignants et personnels d\'encadrement de l\'établissement peuvent acheter sur la marketplace avec livraison à l\'école.

  Transport (24)                                                    Financière (17)                                                                            Le transport est facturé via le même circuit de paiement libre que la scolarité, sans système séparé.

  Bibliothèque physique (25)                                        Vie scolaire (discipline, 19)                                                              Un emprunt répété marqué « perdu » peut être signalé à la vie scolaire, sans automatisme disciplinaire imposé.

  Gamification (22) ✦✦                                              Quiz / Examen / Préparation examens / Planificateur (10-15) / Compétitions (23)            L\'XP est généré exclusivement par les activités du moteur de révision, jamais par la saisie de notes officielles ; les niveaux et badges alimentent le profil public mobilisé par les compétitions du chapitre 23.

  Compétitions et certificats (23) ✦✦                               Reporting --- concours internes (29.3) / Préparation aux examens (13)                      Les résultats des concours privés organisés par un établissement sont restitués dans les statistiques consolidées établissement ; un événement de compétition peut être adossé à un espace de préparation aux examens nationaux.

  CMS pédagogique (30.5) ✦✦                                         Académique --- leçons (9.3) / Moteur de questions (10.3) / Bibliothèque numérique (26.4)   Tout contenu pédagogique --- leçon, question, activité Maternelle, fiche ou flashcard --- passe par le même workflow Brouillon → Révision pédagogique → Validation → Publication avant d\'être visible d\'un élève.

  Réseau d\'établissements --- Direction Générale (28)              Financière / Administration / Reporting (29)                                               La Direction Générale consulte des indicateurs consolidés (recouvrement, effectifs) sur les établissements du réseau, sans rompre l\'autonomie locale ni l\'étanchéité des établissements indépendants.

  Création d\'établissement / réseau (5, 28)                        Backoffice GSG (30) / Modèle économique (36)                                               Toute création est soumise à validation Global Service Groupe ; seule la création d\'un réseau déclenche un frais de création.

  IA --- Tuteur IA, Scan d\'exercice (21.4, 21.5) ✦✦                Financière / Modèle économique (17.7, 36)                                                  L\'abonnement Premium élève et l\'abonnement IA professeur sont des services payants distincts de la licence applicative et des revenus marketplace, suivant chacun sa propre logique de facturation.

  IA --- Parent IA, reconnaissance faciale, Scan d\'exercice (21)   Exigences non fonctionnelles --- protection des mineurs (34)                               Ces fonctionnalités touchant des données d\'enfants sont soumises à un consentement explicite et à des restrictions d\'usage détaillées au chapitre 34.

  Mode gratuit (2.5)                                                Financière / Paramétrage / Documents (17, 31, 18)                                          Le paiement en ligne CinetPay, la personnalisation des thèmes et la personnalisation des templates de documents restent verrouillés tant que l\'établissement n\'est pas passé en mode payant ; le contenu de base du moteur de révision, lui, reste accessible en offre FREE quel que soit le statut de l\'établissement.

  Reporting (29)                                                    Personnel --- Contrats (8) / Financière (17) / Notes (12)                                  Les alertes proactives du tableau de bord Directeur agrègent l\'expiration des contrats RH, le taux d\'impayés et le taux d\'élèves à risque d\'échec.

  Sécurité et rôles (5)                                             Tous les modules                                                                           Chaque action dans chaque module est conditionnée par le rôle racine et le poste déclaré définis au chapitre 4 et portés par le jeton d\'authentification.

  Communication                                                     Tous les modules                                                                           Chaque événement significatif (note, absence, impayé, colis prêt, sanction, congé traité) déclenche une notification centralisée.
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# **33. Règles de gestion transversales**

Les règles suivantes, énoncées de façon éparse dans les sources initiales, s\'appliquent transversalement à plusieurs modules et doivent être traitées comme des invariants du système. Les règles issues de la fusion avec EduRéussite, entièrement nouvelles pour EcoShop v2.0, sont repérées par ✦✦.

-   Unicité d\'inscription d\'un élève sur la plateforme au cours d\'une même année scolaire, avec notification croisée entre établissements (7.1).

-   Aucun rôle racine à privilège (Enseignant, Direction, Vendeur, Fondateur de réseau) n\'est auto-attribuable ; seuls Élève et Parent le sont, via l\'authentification native Supabase Auth (5.2, 5.3, 5.4).

-   Le rôle racine du jeton d\'authentification ne porte jamais de privilège avant l\'attribution explicite d\'un rôle ou d\'un poste ; aucun attribut métier n\'est posé dans la table \`profiles\` ni recopié dans le jeton par le seul fait de vérifier un code (5.6).

-   Verrouillage progressif des notes : enseignant → responsable de service → verrouillage définitif après proclamation des résultats (12.3).

-   Paramétrage des cycles et services par établissement (crèche, cantine, maternelle, primaire, collège, lycée), qui conditionne l\'affichage des modules correspondants (19.3, 31).

-   Gratuité de l\'application jusqu\'à un seuil d\'effectif, puis facturation par palier (2.4) ; le frais IA admin annuel et les abonnements Premium élève/IA professeur suivent chacun leur propre logique, indépendante du palier Pro (17.7).

-   Le paiement de la scolarité est libre et progressif : aucune tranche n\'est bloquante, les échéances configurées ne sont qu\'un repère (7.2, 17.1).

-   Vérifications automatiques à la réinscription : impayés, admission, sanction, statut boursier (7.4).

-   Substitution de saisie possible par un responsable de service pour un enseignant peu à l\'aise avec les outils informatiques, avec traçabilité de l\'action (7.5) --- à l\'inverse, une demande de congé reste en auto-service strict, sans substitution possible (8.5).

-   Import / export Excel encadré par un modèle téléchargeable, pour les inscriptions comme pour les notes (7.5).

-   Personnalisation des templates de documents (reçus, bulletins, attestations, recommandations) par établissement, dans un espace dédié réservé au mode payant, via un moteur de génération unique (chapitre 18) ; un document publié conserve la version du template en vigueur à sa génération, sans altération rétroactive (18.5).

-   Ajout de champs personnalisés par établissement pour les entités dont les informations varient d\'un établissement à l\'autre.

-   Point de livraison unique de la marketplace : l\'établissement, jamais le domicile de l\'acheteur (27.5).

-   Traçabilité systématique des paiements effectués par un tiers pour le compte d\'un autre (ex. salaire, frais de scolarité réglés par un tuteur).

-   Rattachement d\'un élève inscrit par un tiers à son établissement dès sa première connexion, via son matricule, l\'identifiant généré ou le numéro de téléphone du parent (5.7).

-   Déclaration dynamique des compositions et évaluations par la direction pédagogique, sans nombre imposé par le système (12.2).

-   Passage automatique des élèves de crèche et de maternelle à la section ou classe suivante, sans condition d\'évaluation (7.4).

-   Mention obligatoire « admis(e) » ou « recalé » pour les classes d\'examen, condition préalable à la proclamation des résultats de fin d\'année (12.4).

-   Double identification des élèves (matricule officiel + identifiant généré), avec des règles différenciées pour la crèche/maternelle et pour le numéro de téléphone propre à l\'élève, demandé seulement au-delà de la 5ème année (7.6).

-   Rattachement fixe d\'un enseignant à sa classe en maternelle/primaire, contre une circulation par emploi du temps au secondaire, où s\'applique la règle des établissements multiples (8.1).

-   Étanchéité totale des établissements indépendants (aucune visibilité mutuelle, seul Global Service Groupe les supervise), à ne pas confondre avec un réseau d\'établissements doté d\'une Direction Générale (28).

-   Validation Global Service Groupe obligatoire à la création de tout établissement, réseau ou compte Vendeur ; un établissement admis dans un réseau ne peut plus en être retiré sauf permission de Global Service Groupe, malgré la double confirmation applicative (28.3, 28.4).

-   Aucune donnée nominative n\'est transmise à un modèle d\'intelligence artificielle tiers : pseudonymisation systématique avant tout envoi (21.1, 34).

-   Aucun seuil, tarif ou barème mentionné dans ce cahier n\'est codé en dur : tous sont paramétrables depuis le Backoffice Global Service Groupe (30.4, 34).

-   ✦✦ Séparation stricte entre notes officielles et résultats d\'entraînement du moteur de révision : quiz, examens blancs et préparation aux examens nationaux n\'entrent jamais dans le calcul de la moyenne officielle ni dans le bulletin (12.6).

-   ✦✦ Mode élève supervisé en dessous d\'un seuil d\'âge paramétrable par pays : pas de compte élève sans compte parent actif, fonctionnalités de communication et de classement public désactivées par défaut (4.3).

-   ✦✦ Découplage strict entre le référentiel structurel et le contenu pédagogique versionné : une nouvelle année scolaire ne modifie jamais les tables pays_cycle ou pays_niveau, seule la création d\'un nouveau programme_officiel est requise (6.6).

-   ✦✦ Isolation stricte des contenus, questions, résultats et classements par pays dans le référentiel pédagogique multi-pays, jamais mélangés dans les statistiques ou classements nationaux (6.6, 23.1).

-   ✦✦ Aucun contenu pédagogique (leçon, question, activité Maternelle, fiche, flashcard) n\'est publié sans être passé par le statut Validation, attribué par un profil habilité distinct de son auteur (30.5).

-   ✦✦ Gamification non comparative pour les classes CP1 à CE2 (classements publics désactivés par défaut) et absence totale de score, classement ou notion d\'échec visible à l\'enfant en Maternelle (9.6, 9.7.2, 22.3).

-   ✦✦ Aucune session d\'activité Maternelle ne peut démarrer sans être initiée depuis la console parent ; l\'enfant ne dispose d\'aucun accès autonome à un menu ou à un réglage (9.7.2).

-   ✦✦ Priorité aux compétences sous le seuil de maîtrise dans le moteur de recommandation, tout en conservant une part de consolidation ; une même question n\'est jamais proposée deux fois consécutivement à un élève, sauf en mode correction explicite (14.2).

-   ✦✦ Activation automatique d\'un abonnement (Premium élève, IA professeur) dès réception de la confirmation de paiement, même différée par la passerelle, avec journalisation complète du statut de chaque transaction, scolaire comme individuelle (17.8).

-   ✦✦ Absence de messagerie privée élève-élève : une convergence indépendante des deux cahiers sources sur cette même limite de prudence vis-à-vis des jeunes publics, non un arbitrage de fusion (20.3).

# **34. Exigences non fonctionnelles et règles de conception complémentaires**

Ni le cahier EcoShop v1.2, ni le relevé des fonctionnalités du code, ni le cahier EduRéussite ne formulaient d\'exigences non fonctionnelles regroupées en un chapitre unique. Un cahier de conception exhaustif ne peut pas s\'arrêter à la liste des fonctionnalités visibles : ce chapitre rassemble les règles de conception complémentaires qu\'une application manipulant des données financières et des données de mineurs, à l\'échelle d\'un pays puis d\'une zone régionale, doit respecter dès la conception --- enrichi, sur la résilience hors ligne (34.4), par les règles plus concrètes qu\'EduRéussite avait développées pour son propre moteur de révision.

## **34.1 Sécurité applicative**

-   Chiffrement des données sensibles au repos (base de données Postgres, sauvegardes) et en transit (TLS de bout en bout sur tous les appels Edge Functions et API tierces).

-   Gestion des secrets (clés Twilio SMS/WhatsApp, Resend e-mail, CinetPay, clé service role Supabase, secret client GSG ID) via le coffre-fort de secrets des Edge Functions et les paramètres du projet Supabase, jamais en dur dans le code client ni dans un dépôt de code source ; rotation périodique documentée.

-   Application stricte du principe de moindre privilège dans les politiques Row Level Security (RLS) de la base Postgres et dans les politiques de Supabase Storage : un compte ne peut lire ou écrire que les données couvertes par son rôle racine, son poste et son établissement actif (voir chapitre 4 et 5).

-   Protection anti-force-brute homogène sur tous les points d\'entrée sensibles : vérification de code (5.10), rattachement compte↔fiche (5.9), et plus généralement tout mécanisme à double facteur du système.

-   Vérification stricte de la signature de tout jeton présenté à un service tiers du portefeuille GSG (liste blanche de projets Supabase autorisés, JWKS) avant toute fédération d\'identité (voir 5.5).

-   Toute vérification de permission s\'exécute côté serveur à chaque requête, jamais uniquement à l\'affichage de l\'écran côté client --- principe déjà posé en 4.7, élevé ici au rang d\'exigence non fonctionnelle transversale, y compris pour les endpoints du moteur de révision issus de la fusion (banque de questions, quiz, Tuteur IA, Scan d\'exercice).

## **34.2 Protection des données personnelles et des mineurs**

-   Minimisation des données transmises à tout modèle d\'intelligence artificielle tiers : pseudonymisation systématique, déjà posée comme règle transversale (chapitre 33), étendue par principe à toute future fonctionnalité IA du même type, y compris le Tuteur IA et le Scan d\'exercice (21.4, 21.5).

-   Consentement explicite et distinct pour chaque fonctionnalité portant sur des données d\'enfant : Parent IA (21.2) et reconnaissance faciale (21.7) ne partagent pas le même consentement, et chacun doit pouvoir être retiré indépendamment de l\'autre à tout moment, sans désactiver le compte. La console parent de la Maternelle (9.7.2) suit le même principe pour tout enregistrement vocal ou visuel de l\'enfant.

-   **Seuil d\'âge de bascule vers le mode élève supervisé** (voir 4.3), paramétrable par pays depuis le Backoffice GSG (30.4), jamais codé en dur : ce seuil constitue à lui seul une donnée sensible, puisqu\'il détermine directement l\'application ou non des restrictions de communication et de classement public à un compte donné.

-   Durée de rétention définie et documentée pour chaque catégorie de donnée : codes de vérification (TTL 3--5 minutes, 5.4.7), journaux d\'audit (34.3), historiques de position GPS du transport (24.3, purge au-delà de la durée du trajet sauf besoin probatoire explicite), messages de groupes de discussion signalés (20.4, conservés au-delà de la suppression pour modération a posteriori).

-   Droit d\'accès et de rectification : un parent ou un élève majeur peut consulter les données détenues sur lui via son espace ; une procédure d\'export et de suppression de compte doit être prévue dans le Backoffice GSG (chapitre 30), avec purge en cascade des données associées sous réserve des obligations légales de conservation comptable.

## **34.3 Journalisation et audit**

Toute action sensible doit être tracée avec auteur, date, ancienne valeur et nouvelle valeur, au minimum pour :

-   changement de statut boursier (7.2) ;

-   levée de sanction disciplinaire (19.1) ;

-   modification de notes après remontée au responsable de service (12.3) ;

-   saisie de notes par substitution (7.5) ;

-   validation ou refus d\'une demande de congé (8.5) ;

-   chaque transaction de paiement, scolaire ou individuelle, avec son statut complet --- initiée, confirmée, échouée, remboursée (17.8) ;

-   validation ou refus d\'un contenu pédagogique par l\'Administrateur de contenu pédagogique (30.5) ;

-   suppression ou anonymisation d\'un compte utilisateur ;

-   modification des paramètres globaux du Backoffice GSG (30.4) ;

-   révocation d\'une session à distance (5.5, 30.6).

## **34.4 Résilience et mode hors ligne**

Le mode hors ligne, déjà identifié comme une exigence forte pour la saisie des présences et des notes en classe ainsi que pour la consultation par les familles en zones à connectivité limitée (voir chapitre 35), s\'étend désormais à l\'intégralité du parcours de révision (quiz, examens, flashcards, activités Maternelle) : c\'est l\'un des piliers différenciants hérités d\'EduRéussite (voir chapitre 3), dont les règles de résilience, plus concrètes que la simple mention générique d\'EcoShop v2.0, sont ici adoptées intégralement.

-   les écritures réalisées hors ligne sont mises en file locale et synchronisées dès rétablissement de la connexion, sans jamais perdre une tentative de quiz ou d\'examen déjà réalisée hors ligne, y compris en cas d\'interruption réseau pendant le transfert lui-même ;

-   en cas de conflit sur une entité partagée (note, paiement), la règle de résolution par défaut est la conservation des deux écritures avec alerte à un responsable habilité, plutôt qu\'une résolution automatique silencieuse qui risquerait d\'effacer une saisie légitime --- en particulier pour les paiements, où toute perte silencieuse est inacceptable ; pour les données de progression du moteur de révision (XP, historique de tentatives, calendrier de répétition espacée), la donnée la plus récente selon l\'horodatage fait foi, sauf lorsqu\'elle est cumulative par nature, auquel cas elle s\'additionne plutôt que de s\'écraser ;

-   **téléchargement par paquets** : tout contenu volumineux (examens blancs, packs audio de révision, activités ludo-éducatives de Maternelle) est systématiquement segmenté en paquets téléchargeables indépendamment, afin de tolérer les coupures réseau fréquentes sans devoir reprendre un téléchargement depuis son origine ;

-   un échec d\'envoi de code de vérification (SMS, WhatsApp ou e-mail) doit proposer un renvoi immédiat ou un canal de secours, plutôt qu\'un blocage sec de l\'inscription (voir 5.4.3).

## **34.5 Performance et scalabilité**

-   Index dédiés pour les requêtes fréquentes à fort volume : déduplication des demandes de code par identifiant (5.4.7), recherche d\'établissement insensible à la casse et aux accents (28.3), recherche d\'élève par numéro de téléphone parent (7.1), filtrage de la banque de questions par pays / programme / compétence / difficulté (chapitre 10).

-   Les Edge Functions du moteur OTP multicanal sont dimensionnées pour absorber les pics d\'inscription en début d\'année scolaire, avec une stratégie de limitation de la latence de démarrage à froid (fonctions maintenues « chaudes » pendant les périodes de forte affluence) ; le même soin de dimensionnement s\'applique aux périodes de forte affluence du moteur de révision, notamment à l\'approche des examens nationaux (chapitre 13).

## **34.6 Tests et qualité**

-   Tests unitaires systématiques sur les Edge Functions sensibles, en priorité sendOTP et verifyOTP (5.4.3, 5.4.4).

-   Tests d\'intégration bout en bout sur le parcours d\'authentification complet, pour chacun des trois canaux (SMS, WhatsApp, e-mail).

-   Tests de charge sur le rate limiting du moteur OTP multicanal, pour valider les seuils par défaut avant chaque changement de barème.

-   Tests de non-régression sur les règles de gestion critiques listées au chapitre 33, notamment le cycle de verrouillage des notes, la règle d\'unicité d\'inscription et la séparation entre notes officielles et résultats d\'entraînement (12.6).

-   Tests de synchronisation hors ligne dédiés au moteur de révision : perte de connexion en cours de quiz, en cours de téléchargement d\'un paquet de contenu, et en cours de synchronisation d\'XP (voir 34.4).

## **34.7 Conventions techniques**

-   Convention de nommage homogène pour les tables Postgres, les rôles racines, les postes déclarés et les attributs recopiés dans le jeton, documentée dans le dictionnaire de données du projet.

-   Versionnage explicite des Edge Functions exposées (sendOTP, verifyOTP et toute API future), avec dépréciation progressive plutôt que rupture immédiate lorsqu\'une évolution de contrat est nécessaire.

## **34.8 Sauvegarde et plan de reprise**

Sauvegarde régulière des données et protection des informations sensibles, avec fréquence, durée de rétention et test périodique de restauration documentés --- au-delà de la simple mention de la v1.2 (« sauvegarde des données »), ce chapitre en fait une exigence vérifiable, incluant un objectif de point de reprise (RPO) et un objectif de délai de reprise (RTO) formalisés par Global Service Groupe.

## **34.9 Accessibilité et internationalisation**

-   Contraste et taille de police ajustables, en complément de la personnalisation des thèmes graphiques (chapitre 31).

-   Structure multilingue déjà prévue (français, anglais --- chapitre 31) conçue pour accueillir les langues d\'enseignement des systèmes anglophone, lusophone et arabophone du référentiel pédagogique (voir 6.5), sans refonte de l\'architecture de contenu.

## **34.10 Mentions légales et consentement**

Acceptation de conditions générales d\'utilisation à l\'inscription, adaptées au rôle (un parcours simplifié et lisible par un enfant pour le rôle Élève, un parcours complet pour les rôles Parent, Direction, Vendeur et Fondateur de réseau), et accessibles à tout moment depuis le profil du compte.

# **35. Architecture technique et estimation des écrans**

## **35.1 Choix technologique**

EcoShop est développée sous Flutter pour ses deux cibles : application mobile (Android / iOS) à destination des familles, enseignants, personnels d\'encadrement, chauffeurs et vendeurs, et application Windows à destination de l\'administration, de la comptabilité et du back-office Global Service Groupe. Le socle applicatif (gestion d\'état, appels API, modèles de données) est mutualisé ; les interfaces sont adaptées à chaque contexte d\'usage : densité d\'information plus élevée et flux de saisie plus longs côté Windows, parcours simplifiés et mode hors ligne renforcé côté mobile.

Le backend s\'appuie sur **Supabase** (Auth, base de données Postgres, Storage, Realtime) et sur des Edge Functions pour la logique serveur sensible qui ne relève pas nativement de Supabase Auth --- au premier rang desquelles la fédération d\'identité GSG ID décrite au chapitre 5, les webhooks de paiement CinetPay et le backend IA. Ce choix, acté avec la présente révision, remplace Firebase envisagé jusqu\'alors : il conserve la même répartition des responsabilités (Authentication / base de données documentaire ou relationnelle / stockage de fichiers / fonctions serverless) tout en apportant une base de données relationnelle Postgres unique --- plus adaptée à la richesse du référentiel pédagogique multi-pays (chapitre 6) et à ses jointures entre pays, cycles, niveaux, programmes et compétences qu\'un modèle documentaire --- et un contrôle d\'accès par Row Level Security (RLS), exprimé en SQL directement sur les tables plutôt que dans un langage de règles séparé. L\'organisation en couches Presentation → Application / State Management → Domain → Data → Local Database / API, retenue par EduRéussite pour son propre moteur de révision, est adoptée comme architecture cible pour l\'ensemble de l\'application mobile plutôt que pour le seul volet révision : elle n\'entre en contradiction avec aucun choix déjà posé par EcoShop v2.0 et clarifie la séparation entre logique métier et présentation sur les deux plateformes.

## **35.2 Mode hors ligne**

Le mode hors ligne est identifié comme une exigence forte, en particulier pour la saisie des présences, des notes en salle de classe et pour la consultation par les familles en zones à connectivité limitée --- et, depuis la fusion avec EduRéussite, pour l\'intégralité du parcours de révision (quiz, examens, flashcards, activités Maternelle), l\'un des piliers différenciants du produit (voir chapitre 3). Les écritures réalisées hors ligne sont synchronisées dès rétablissement de la connexion, avec gestion des conflits sur les entités partagées (notes, paiements, progression) selon les principes de résilience posés en 34.4.

## **35.3 Stockage local et synchronisation**

EcoShop v2.0 ne précisait pas de moteur de stockage local ; EduRéussite en faisait un choix structurant de son architecture mobile, retenu ici pour l\'ensemble de l\'application : **SQLite / Drift** comme moteur de base de données locale sur mobile.

-   Données conservées localement : contenu pédagogique téléchargé (questions, cours, fiches, packs audio --- voir 34.4), progression de l\'élève, réponses et tentatives, sessions, paramètres utilisateur, ainsi que les données de scolarité nécessaires à un usage hors ligne complet (présences, notes en cours de saisie).

-   Séquence de synchronisation : (1) l\'utilisateur agit hors connexion --- répond à une question, saisit une présence ; (2) l\'action est enregistrée localement dans SQLite/Drift ; (3) la connexion est détectée par l\'application ; (4) l\'action est placée dans une file de synchronisation ; (5) la file est transmise au serveur dès qu\'un réseau stable est disponible ; (6) le serveur confirme la réception et résout les conflits éventuels selon les règles de priorité posées en 34.4 (horodatage, sauf données cumulatives).

## **35.4 Architecture du système d\'intelligence artificielle**

Ce schéma, absent d\'EcoShop v2.0, formalise le circuit commun à toutes les briques IA du chapitre 21 (Chat IA Directeur-Adviser, Tuteur IA, Scan d\'exercice, Parent IA) : **Utilisateur → Application → Backend IA → Contexte pédagogique (pays, programme, classe, matière, chapitre, niveau, historique) → Modèle IA → Réponse contrôlée**.

-   Le contexte pédagogique complet --- rattaché au référentiel multi-pays (chapitre 6) et à l\'historique de l\'élève (chapitre 14) --- est systématiquement injecté dans chaque appel au modèle, afin de réduire au minimum le risque de réponse hors programme ou inadaptée au niveau de l\'élève (voir 21.4).

-   Pour le Chat IA Directeur-Adviser, ce même circuit s\'applique après l\'étape de pseudonymisation décrite en 21.1 et 34.2 : aucune donnée nominative n\'entre dans le Backend IA.

-   Le Backend IA orchestre également la file d\'attente du Scan d\'exercice en cas d\'absence de connexion (voir 21.5 et 34.4).

## **35.5 Estimation du nombre d\'écrans par module**

Le tableau ci-dessous actualise l\'estimation d\'EcoShop v2.0 pour tenir compte des modules issus de la fusion avec EduRéussite (référentiel pédagogique, moteur de questions et CMS, quiz et mode Examen, préparation aux examens nationaux, analyse des compétences, répétition espacée et planificateur, Maternelle, gamification, compétitions et certificats, bibliothèque numérique), ainsi que du nouvel espace de personnalisation des templates de documents officiels. Il raisonne en écrans fonctionnels (liste, détail, formulaire de création/édition regroupés lorsque pertinent) et doit être affiné lors du découpage détaillé des maquettes.

  ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Module**                                                                                                                                           **Écrans mobile**   **Écrans Windows**
  ---------------------------------------------------------------------------------------------------------------------------------------------------- ------------------- --------------------
  Socle transversal (authentification / moteur OTP multicanal, élève supervisé, choix du rôle, notifications, aide/FAQ, mode hors ligne, paramètres)   14                  7

  Administration et scolarité (inscriptions, dossiers, classes, historique)                                                                            8                   14

  Identification élève et première connexion (recherche d\'école, rattachement de compte, création du compte de mon enfant)                            5                   2

  Personnel et RH (profils, présence, contrats, congés, salaires, avances, bulletin de paie)                                                           6                   14

  Déclaration des niveaux, postes et services (paramétrage dynamique des rôles)                                                                        0                   6

  Référentiel pédagogique multi-pays (pays, cycles, niveaux, examens, filières, programmes officiels) ✦✦                                               0                   8

  Académique et pédagogique (programmes, cahier de texte, e-learning, ressources, leçons structurées)                                                  10                  8

  Maternelle --- Éveil préscolaire (console parent, univers d\'activités, session guidée par la mascotte) ✦✦                                           6                   0

  Moteur de questions et CMS pédagogique (création de question, activités Maternelle, file de validation) ✦✦                                           0                   10

  Quiz, entraînement et mode Examen ✦✦                                                                                                                 9                   0

  Préparation aux examens nationaux et concours (espaces CEPE, BEPC, BAC, concours) ✦✦                                                                 6                   0

  Analyse des compétences et moteur de recommandation ✦✦                                                                                               4                   2

  Répétition espacée et planificateur intelligent ✦✦                                                                                                   5                   0

  Emploi du temps (grille, séances récurrentes/ponctuelles, conflits)                                                                                  6                   8

  Notes et bulletins (saisie, consultation, classement, conseils de classe)                                                                            6                   10

  Financière et comptable (paiement, reçus, caisse, portefeuille, budget, comptabilité analytique)                                                     8                   16

  Documents officiels (certificats, attestations, cartes, bulletins de paie)                                                                           2                   8

  Espace de personnalisation des templates (éditeur de template, champs de fusion, aperçu, publication, historique des versions) ✦✦                    0                   6

  Vie scolaire (infrastructures, activités, discipline, santé, cantine, internat)                                                                      6                   12

  Communication (messagerie, groupes de discussion, notifications, annonces, modération)                                                               8                   5

  Intelligence artificielle (Chat Directeur-Adviser, Parent IA, Tuteur IA, Scan d\'exercice, IA professeur, QR/reconnaissance faciale)                 10                  6

  Gamification et engagement (XP, niveaux, badges) ✦✦                                                                                                  4                   0

  Compétitions, classements et certificats ✦✦                                                                                                          6                   2

  Transport scolaire (circuits, affectation, suivi GPS, facturation)                                                                                   5                   3

  Bibliothèque physique (catalogue, emprunt/retour, inventaire)                                                                                        3                   3

  Bibliothèque numérique et flashcards ✦✦                                                                                                              5                   0

  Sécurité, rôles et sauvegarde                                                                                                                        2                   6

  Établissements indépendants et réseaux (invitation, annuaire, retrait/dissolution, tableau de bord réseau)                                           0                   9

  Création d\'établissement / réseau (formulaire, validation GSG)                                                                                      3                   3

  Reporting (tableau de bord Directeur, alertes proactives, comparaison inter-classes, export, concours internes)                                      4                   6

  Paramétrage et personnalisation                                                                                                                      2                   6

  Marketplace --- espace vendeur (inscription, catalogue, commandes, tableau de bord)                                                                  10                  0

  Marketplace --- achat élève / parent (navigation, panier multi-vendeur, paiement, suivi)                                                             9                   0

  Marketplace --- réception et remise à l\'établissement (scan, historique)                                                                            5                   3

  Marketplace --- back-office Global Service Groupe (validation, litiges, commissions)                                                                 0                   8

  Backoffice GSG (validation établissements/réseaux/vendeurs, CMS pédagogique, paramètres globaux, révocation de session)                              0                   9
  ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

**Total estimé : environ 177 écrans côté mobile, 200 écrans côté Windows, soit environ 377 écrans fonctionnels pour l\'ensemble de l\'application** (contre 283 dans l\'estimation EcoShop v2.0 --- l\'écart de +94 s\'explique presque intégralement par les modules issus de la fusion avec EduRéussite et par l\'espace de personnalisation des templates, repérés ci-dessus par ✦✦, ainsi que par le détail supplémentaire porté au socle transversal d\'authentification pour le parcours de l\'élève supervisé).

> ***Règle de gestion ---** cette estimation est une base de travail. Le périmètre effectif du développement peut être phasé (lancement d\'un MVP sur un sous-ensemble d\'écrans prioritaires --- socle transversal avec authentification OTP multicanal, administration, notes, gestion financière, puis moteur de révision de base), sans remettre en cause l\'architecture de données et de rôles définie dans ce cahier. Le phasage recommandé est détaillé à la feuille de route produit (chapitre 38).*

# **36. Modèle économique global**

EcoShop v2.0 décrivait six flux de revenus indépendants, chacun avec sa propre logique de facturation, sa propre périodicité et son propre déclencheur. EduRéussite, de son côté, organisait son modèle autour d\'une grille freemium à trois offres (FREE, PREMIUM, ÉTABLISSEMENT) et de plusieurs sources de revenus complémentaires propres à la préparation aux examens. Ce chapitre restructure entièrement le modèle économique pour faire coexister les deux logiques sans contradiction silencieuse : le principe d\'indépendance des flux, plus rigoureux et déjà éprouvé par EcoShop v2.0, reste la règle par défaut ; la grille freemium d\'EduRéussite, plus fine pour piloter la conversion d\'un élève individuel, est adoptée comme habillage commercial du flux « Abonnement Premium élève » sans remettre en cause cette indépendance.

## **36.1 Neuf flux de revenus indépendants**

  -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Flux**                                                    **Déclencheur**                                                                                                                                                **Indépendance**
  ----------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------
  Licence applicative (abonnement Pro établissement)          Franchissement du seuil d\'effectif gratuit (2.4, 17.7)                                                                                                        Indépendant des autres flux

  Frais IA admin annuel                                       Souscription de l\'établissement pour débloquer le Chat IA Directeur-Adviser (17.7, 21.1)                                                                      Indépendant du palier Pro

  Abonnement Premium élève (moteur de révision)               Souscription individuelle, mensuelle ou annuelle, de l\'élève ou de son parent (17.7, 21.4)                                                                    Indépendant du statut Pro et du frais IA admin --- sous réserve du mécanisme de bascule optionnelle décrit en 36.3

  Abonnement IA professeur                                    Souscription individuelle mensuelle de l\'enseignant (17.7, 21.6)                                                                                              Indépendant des flux précédents ; ne débloque pas l\'accès administrateur du moteur de révision

  Frais de création de réseau                                 Création d\'un réseau d\'établissements par un Fondateur de réseau (28.3)                                                                                      Frais unique, exigé une seule fois dans la vie du réseau

  Commission marketplace                                      3 % prélevés sur chaque vente EcoShop Market, plus abonnements vendeurs, frais de livraison interne et mise en avant payante (27.8)                            Ouvert aux élèves, parents, enseignants et personnels d\'encadrement

  Packs de préparation aux examens (BEPC, BAC, concours) ✦✦   Achat ponctuel donnant accès à un espace de préparation enrichi (annales, examens blancs supplémentaires --- voir 13.2 et 17.7)                                Indépendant de l\'abonnement Premium élève ; peut être acheté par un élève en offre FREE

  Concours sponsorisés et partenariats ✦✦                     Un partenaire (entreprise, institution) finance un événement de compétition (chapitre 23) ou une opération de contenu, en échange d\'une visibilité encadrée   Ponctuel, contractualisé au cas par cas par Global Service Groupe

  Publicité limitée dans l\'offre FREE ✦✦                     Espaces publicitaires strictement encadrés, visibles uniquement dans l\'offre gratuite du moteur de révision                                                   Soumis aux restrictions de protection des mineurs posées en 36.4
  -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Ces neuf flux sont indépendants dans leur facturation mais convergent dans les rapports financiers consolidés du back-office Global Service Groupe (chapitre 30), qui offre une vision globale de la performance du réseau d\'établissements, de la marketplace et du moteur de révision.

> ***Règle de gestion ---** cette indépendance de facturation ne doit pas se traduire par une indépendance de gouvernance : les neuf flux partagent le même principe de configuration non codée en dur posé en 30.4 --- aucun tarif, aucun taux de commission, aucun seuil n\'est figé dans l\'application cliente.*

## **36.2 Grille de l\'abonnement Premium élève**

La grille FREE / PREMIUM d\'EduRéussite, plus concrète que la description sommaire d\'EcoShop v2.0, est adoptée pour structurer le contenu de l\'abonnement Premium élève défini en 36.1 et 21.4.

  --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  **Offre**                                      **Cible**                                  **Contenu principal**
  ---------------------------------------------- ------------------------------------------ --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  FREE                                           Tout élève, sans condition d\'abonnement   Contenu de base (chapitres 9-11), quiz en nombre limité, statistiques de base, Tuteur IA avec quota resserré (voir 21.4), quelques examens blancs

  PREMIUM (Abonnement Premium élève)             Élève ou parent souscripteur               Toutes les matières, contenus premium, examens blancs illimités, statistiques avancées (chapitre 14), plan de révision intelligent et répétition espacée (chapitre 15), quota IA élevé (chapitre 21), téléchargements hors ligne avancés (chapitre 34)

  ÉTABLISSEMENT (abonnement Pro établissement)   Établissement scolaire                     Comptes élèves et enseignants, administration complète (chapitres 7-8, 12), devoirs numériques (9.2), statistiques et rapports (chapitre 29) --- distinct par nature de l\'offre PREMIUM individuelle, voir 36.3
  --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

> ***Règle de gestion ---** à l\'expiration d\'un abonnement Premium élève, l\'élève conserve l\'accès en lecture à son historique de progression (chapitre 14) mais repasse aux limites de l\'offre FREE pour toute nouvelle activité, sans jamais perdre les données déjà produites.*

## **36.3 Réconciliation : abonnement établissement et accès Premium élève**

EduRéussite prévoyait, par sa règle RG-022-02, qu\'un élève rattaché à un établissement disposant d\'un abonnement Établissement actif bénéficie automatiquement des droits Premium sans abonnement individuel distinct. Cette cascade entre en tension directe avec le principe d\'indépendance des flux posé par EcoShop v2.0 (36.1), où l\'abonnement Pro établissement ne débloque explicitement ni le frais IA admin, ni l\'abonnement IA élève, ni l\'abonnement IA professeur --- chacun de ces flux ayant volontairement sa propre logique de facturation pour éviter qu\'un établissement non abonné à l\'IA ne prive ses élèves d\'un accès individuel qu\'ils auraient pu financer eux-mêmes, et inversement.

> ***Règle de gestion ---** c\'est le principe d\'indépendance des flux d\'EcoShop qui prévaut par défaut, pour rester cohérent avec l\'ensemble du modèle économique de la plateforme plutôt que d\'introduire une exception isolée pour le seul moteur de révision : l\'abonnement Pro établissement ne confère aucun droit Premium élève automatique. La cascade proposée par EduRéussite n\'est cependant pas écartée mais transformée en **option de regroupement commercial (bundling)**, activable établissement par établissement depuis le Backoffice GSG (30.4) : un établissement peut choisir de souscrire un forfait Pro incluant l\'accès Premium pour l\'ensemble de ses élèves, facturé comme un flux additionnel clairement identifié et non comme une extension implicite et gratuite de la licence Pro existante. Ce choix reste réversible et n\'affecte jamais un élève dont l\'établissement n\'a pas activé l\'option --- celui-ci conserve la possibilité de souscrire individuellement, comme le prévoit 36.1.*

## **36.4 Publicité limitée et protection des mineurs**

La publicité dans l\'offre FREE, absente d\'EcoShop v2.0, introduite comme source de revenus par EduRéussite (9.1), est retenue mais strictement encadrée compte tenu du public très majoritairement mineur de la plateforme.

> ***Règle de gestion ---** aucun espace publicitaire n\'est jamais affiché à un élève en mode supervisé (voir 4.3) ni en Maternelle (voir 9.7.2). Pour les autres élèves en offre FREE, la publicité reste soumise à une validation de contenu par Global Service Groupe (aucune publicité pour des produits ou services inadaptés à un public scolaire), n\'interrompt jamais une session de quiz, d\'examen ou d\'activité en cours, et ne collecte aucune donnée de navigation croisée avec un tiers publicitaire hors du strict nécessaire à l\'affichage --- ce garde-fou rejoint le principe de minimisation des données de mineurs posé en 34.2.*

## **36.5 Sources de revenus par module --- vue de synthèse**

Cette synthèse relie chaque flux du présent chapitre au module fonctionnel qui le produit, afin d\'éviter toute ambiguïté d\'attribution lors du chiffrage projet.

-   Licence applicative et Frais IA admin → Backoffice GSG et paramétrage établissement (chapitres 30-31).

-   Abonnement Premium élève et Abonnement IA professeur → moteur de révision et Intelligence artificielle (chapitres 9-15 et 21).

-   Frais de création de réseau → Établissements et réseaux (chapitre 28).

-   Commission marketplace → Marketplace (chapitre 27).

-   Packs de préparation aux examens → Préparation aux examens nationaux et concours (chapitre 13).

-   Concours sponsorisés et partenariats → Compétitions, classements et certificats (chapitre 23).

-   Publicité limitée → offre FREE du moteur de révision, gouvernée par 36.4.

# **37. Indicateurs de succès**

Ce chapitre est entièrement nouveau pour EcoShop : ni la v1.2 ni l\'état réel du code ne formalisaient d\'indicateurs de succès dédiés, alors qu\'EduRéussite en avait fait un chapitre à part entière, structuré en trois familles. Cette structure est reprise et complétée par les indicateurs propres au volet gestion scolaire et marketplace d\'EcoShop, absents du cahier EduRéussite qui ne couvrait que la révision.

## **37.1 Engagement**

-   Utilisateurs actifs quotidiens et hebdomadaires, par rôle (élève, parent, enseignant, direction).

-   Sessions quotidiennes et temps d\'étude cumulé sur le moteur de révision (chapitres 9-15).

-   Nombre de questions répondues, de flashcards révisées (chapitre 26) et de missions de planificateur complétées (chapitre 15).

-   Taux d\'adoption du mode hors ligne (chapitre 34), révélateur de l\'usage réel en zone à connectivité limitée.

## **37.2 Pédagogie**

-   Progression moyenne de maîtrise par compétence (chapitre 14), suivie dans le temps par pays, par cycle et par établissement.

-   Taux de réussite aux examens blancs et diminution du taux d\'erreur dans le temps, par matière et par espace de préparation aux examens nationaux (chapitre 13).

-   Taux de compétences maîtrisées (seuil de 50 % ou plus, voir 14.1) par classe, restitué à l\'enseignant et à la direction (chapitre 29).

-   Corrélation, suivie à titre d\'étude et non de règle de gestion automatisée, entre l\'usage du moteur de révision et l\'évolution des notes officielles d\'un élève --- sans jamais faire de cette corrélation un substitut au score de risque d\'échec (voir 12.7 et 12.6).

## **37.3 Business**

-   Répartition des utilisateurs entre offre FREE et offre Premium élève, et taux de conversion FREE → Premium (voir 36.2).

-   Revenu moyen par utilisateur (ARPU), décomposé par flux de revenus (voir 36.1 et 36.5) plutôt qu\'en un seul chiffre agrégé, condition d\'un pilotage fin d\'un modèle à neuf flux indépendants.

-   Nombre d\'abonnements Pro établissement actifs et taux de renouvellement, en particulier à la bascule d\'année scolaire (voir 17.7).

-   Taux d\'établissements ayant activé l\'option de regroupement commercial Pro + Premium élève (voir 36.3), révélateur de l\'appétence du marché pour le bundling par rapport à la vente individuelle.

## **37.4 Établissement et marketplace**

Ces indicateurs, absents du cahier EduRéussite qui ne couvrait pas la gestion scolaire ni la marketplace, complètent les trois familles précédentes pour donner une vue équilibrée des deux composantes ERP et marketplace de la plateforme.

-   Taux de recouvrement des frais de scolarité et volume du portefeuille établissement (chapitre 17).

-   Nombre d\'établissements et de réseaux actifs, taux de croissance par pays du référentiel pédagogique (chapitre 6).

-   Volume de ventes marketplace, commission perçue, score de fiabilité moyen des vendeurs (chapitre 27).

-   Taux de contenu pédagogique validé par rapport au contenu en attente de révision, par pays et par matière (voir 30.5), indicateur direct de la capacité de la plateforme à alimenter le Tuteur IA (voir 21.4).

# **38. Feuille de route produit**

Ce chapitre est entièrement nouveau pour EcoShop : le cahier v1.2 et l\'état réel du code ne comportaient pas de feuille de route formalisée, le socle de gestion scolaire, financier et marketplace étant déjà largement en production. EduRéussite, à l\'inverse, présentait une feuille de route en cinq phases pensée pour un développement entièrement nouveau. Ce chapitre ne reprend donc pas telle quelle la feuille de route d\'EduRéussite : il la restructure en tenant compte du fait que le socle ERP d\'EcoShop existe déjà, ce qui change fondamentalement l\'ordre de priorité et le point de départ du projet fusionné.

## **38.1 Phase 0 --- Socle déjà en production**

Contrairement au cas d\'EduRéussite, cette phase n\'est pas à construire mais à consolider : administration et scolarité, RH, notes et bulletins, emploi du temps, financière, documents, vie scolaire, communication, transport, bibliothèque physique, marketplace, établissements et réseaux, backoffice GSG (chapitres 4-5, 7-8, 12, 16-20, 24-25, 27-31 et 33-35). L\'authentification native Supabase Auth, désormais fédérée par GSG ID (chapitre 5), fait partie de cette base et sert de point d\'ancrage à l\'intégration du moteur de révision : aucune nouvelle brique d\'authentification n\'est nécessaire pour accueillir les fonctionnalités issues d\'EduRéussite.

## **38.2 Phase 1 --- Socle du moteur de révision (collège et lycée)**

Objectif : obtenir rapidement un moteur de révision utilisable, greffé sur les comptes Élève existants, priorisé sur le collège et le lycée avant le primaire et la Maternelle.

-   Référentiel pédagogique multi-pays, limité au premier pays de lancement (chapitre 6).

-   Moteur de questions et CMS pédagogique de base (chapitres 10 et 30.5).

-   Quiz et corrections immédiates (chapitre 11.1).

-   Résultats et profil de maîtrise de premier niveau (chapitre 14.1).

-   Mode hors ligne et synchronisation du moteur de révision, sur le socle SQLite/Drift (chapitres 34-35).

## **38.3 Phase 2 --- Préparation aux examens, engagement, ouverture du primaire**

-   Mode Examen et espaces de préparation aux examens nationaux, à commencer par l\'examen de fin de collège et de fin de lycée (chapitres 11.2 et 13).

-   Planificateur intelligent et répétition espacée (chapitre 15).

-   Gamification et premiers classements (chapitre 22).

-   Vue enseignant du moteur de révision : devoirs numériques, analyse de classe par compétence (voir 9.2 et 14.1).

-   Ouverture du niveau primaire (CP1-CM2) : formats audio-illustrés, questions simplifiées, mode élève supervisé, gamification non comparative, espace de préparation à l\'examen de fin de primaire (voir 9.6, 13.3 et 22.3).

## **38.4 Phase 3 --- Monétisation du moteur de révision et Maternelle**

Les paiements, l\'espace parent et l\'espace établissement existent déjà côté EcoShop (Phase 0) ; cette phase se concentre donc, pour le volet révision, sur ce qui manque réellement.

-   Abonnement Premium élève et sa grille FREE/PREMIUM (chapitre 36.2), branchés sur le circuit de paiement CinetPay déjà en production.

-   Option de regroupement commercial Pro établissement + Premium élève (chapitre 36.3).

-   Compétitions, classements élargis et certificats (chapitre 23).

-   Ouverture de l\'espace Maternelle (PS-GS) : pipeline de contenu ludo-éducatif audio-animé, console parent dédiée, absence totale de score visible à l\'enfant (chapitre 9.7).

-   Bibliothèque numérique et flashcards (chapitre 26).

## **38.5 Phase 4 --- Intelligence artificielle avancée du moteur de révision**

Le Chat IA Directeur-Adviser et Parent IA existent déjà côté EcoShop (Phase 0, chapitres 21.1-21.2) ; cette phase complète le volet IA avec les briques issues d\'EduRéussite.

-   Tuteur IA conversationnel (chapitre 21.4).

-   Scan et résolution d\'exercice (chapitre 21.5).

-   Génération assistée de questions pour le CMS pédagogique, sous supervision de l\'Administrateur de contenu pédagogique (chapitre 30.5).

-   Recommandations avancées et analyse prédictive du profil de maîtrise (chapitre 14.2 et 21.3).

## **38.6 Phase 5 --- Extension géographique**

Guinée → extension régionale (Côte d\'Ivoire, Sénégal, Mali) → extension étendue (Burkina Faso, Niger, Bénin, Togo) → extension CEDEAO élargie (systèmes anglophone, lusophone, arabophone) → extension continentale, selon la trajectoire déjà détaillée au référentiel pédagogique (voir 6.5). Chaque nouveau pays s\'ajoute par la seule création de données de référentiel, sans modification du code applicatif (voir 6.1).

## **38.7 Ordre de priorité technique recommandé pour le volet révision**

En repartant du socle technique déjà en production côté EcoShop plutôt que de l\'architecture générique proposée par EduRéussite : référentiel pédagogique (6) → moteur de questions (10) → quiz (11.1) → mode Examen et correction (11.2) → profil de maîtrise (14.1) → mode hors ligne du moteur de révision (34-35) → synchronisation → CMS pédagogique et back-office (30.5) → vue enseignant (9.2) → préparation aux examens nationaux (13) → gamification (22) → paiements et abonnement Premium élève (36) → Maternelle (9.7) → intelligence artificielle avancée (21.4-21.5) → expansion internationale (6.5).

# **39. Conclusion**

EcoShop se positionne désormais comme une plateforme unique couvrant trois ambitions qui, séparément, ciblaient un public scolaire ouest-africain aux besoins pourtant largement communs : la gestion intégrale d\'un établissement scolaire --- de l\'inscription à la proclamation des résultats ---, une marketplace scolaire contrôlée et une offre d\'intelligence artificielle administrative, et, depuis la présente révision, un moteur complet de révision et de réussite scolaire, du CP1 à la Terminale et jusqu\'aux concours.

Cette révision a rapproché trois sources qui, prises isolément, donnaient chacune une image incomplète du besoin réel des familles et des établissements : le cahier de conception v1.2 exprimait une ambition fonctionnelle riche mais partiellement déconnectée de l\'état réel du code ; le relevé des fonctionnalités du 20/08/2026 décrivait fidèlement ce qui existe, sans toujours porter la profondeur des règles de gestion qui en justifient l\'existence ; le cahier EduRéussite, enfin, décrivait un moteur de révision structurellement riche mais pensé comme un produit autonome, dupliquant sous forme d\'« espaces acteurs » une partie de ce qu\'EcoShop organisait déjà par modules fonctionnels. Plutôt que de juxtaposer ces trois visions, ce cahier de conception v3.0 les a systématiquement confrontées point par point, en tranchant chaque fois en faveur de la conception la plus pertinente (voir la méthodologie posée au chapitre 1) :

-   le référentiel pédagogique multi-pays d\'EduRéussite, structurellement supérieur à la simple liste déclarative de cycles d\'EcoShop v2.0, devient le socle commun de la scolarité et du moteur de révision (chapitre 6) ;

-   l\'organisation par modules fonctionnels d\'EcoShop, plus rigoureuse que le doublon « module + espace acteur » d\'EduRéussite, structure l\'ensemble du cahier, le contenu propre à chaque acteur étant absorbé dans le module concerné plutôt que dupliqué (voir chapitre 1) ;

-   une frontière stricte, absente des deux cahiers sources pris isolément, sépare désormais les notes officielles des résultats d\'entraînement produits par le moteur de révision, condition indispensable dès lors que les deux moteurs cohabitent dans une même application (voir 12.6) ;

-   le modèle de rôles à deux niveaux d\'EcoShop (rôle racine et poste déclaré) absorbe les apports d\'EduRéussite --- élève supervisé, Administrateur de contenu pédagogique --- sans perdre sa rigueur (chapitre 4) ;

-   un même socle d\'authentification --- natif Supabase Auth et désormais fédéré par GSG ID au niveau du portefeuille Global Service Groupe --- gouverne l\'ensemble des rôles, des postes et des parcours dédiés au jeune public, y compris la création de compte par un parent pour son enfant (chapitre 5) ;

-   un même compte parent centralise scolarité, révision, marketplace, transport et communication ;

-   un même établissement demeure le point de livraison et de responsabilité, aussi bien pour la marketplace que pour la bibliothèque physique, le transport scolaire ou le CMS pédagogique ;

-   des flux financiers désormais mieux détaillés (neuf flux indépendants plutôt que six) intègrent les abonnements individuels de révision sans rompre le principe d\'indépendance de facturation, la cascade établissement→élève proposée par EduRéussite étant conservée comme option plutôt qu\'imposée par défaut (chapitre 36) ;

-   des exigences non fonctionnelles explicites --- sécurité, protection des mineurs, journalisation, résilience hors ligne --- encadrent désormais des fonctionnalités qui, par nature, manipulent à grande échelle des données sensibles d\'un public très majoritairement mineur (chapitre 34) ;

-   un espace de personnalisation dédié permet à chaque établissement d\'imprimer sa propre identité visuelle sur ses documents officiels (reçus, bulletins, certificats, attestations, cartes scolaires) sans jamais toucher à la donnée ni à la logique métier qui les produit (chapitre 18).

La feuille de route de développement (chapitre 38) peut s\'appuyer sur l\'estimation d\'écrans du chapitre 35 pour phaser un lancement progressif --- en s\'appuyant sur le socle EcoShop déjà en production (administration, notes, financière, marketplace) pour greffer, module par module, le moteur de révision : référentiel et banque de questions d\'abord, préparation aux examens et engagement ensuite, monétisation et Maternelle en troisième lieu, intelligence artificielle avancée enfin, avant l\'extension progressive aux quinze autres pays de la CEDEAO.

Le résultat n\'est pas la somme de deux cahiers de conception mais un seul produit repensé : une plateforme où un même élève, un même parent et un même établissement retrouvent, sous un seul compte et une seule application, la gestion administrative de la scolarité et le chemin quotidien vers la réussite aux examens.
