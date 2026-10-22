## 1.9.7 — Harmonisation de la charte graphique officielle

- Palette centrale alignée sur le logo de l’établissement : vert `#0C6900`, orange `#FF6600`, violet `#802872` et blanc.
- Contrastes renforcés sur les boutons principaux, les éléments de navigation et les panneaux de connexion.
- Accent orange/violet discret dans la navigation et les bandeaux, sans surcharger les pages.
- Ajout d’un indicateur de focus clavier plus visible et respect de la préférence de réduction des animations.
- Contrôle de pré-livraison relancé ; build Next.js complet et validation réelle Supabase restent à effectuer dans un environnement connecté.

## 1.9.6 — Authentification unifiée et correction de configuration Supabase

- Connexion et inscription partagent désormais la même page et conservent le panneau visuel fixe.
- Réduction des logos répétés et formulaire plus haut, avec mise en page compacte.
- Client Supabase compatible avec les variables de clé publique `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` et `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- Route d’inscription compatible avec `SUPABASE_SECRET_KEY` et l’ancien nom `SUPABASE_SERVICE_ROLE_KEY`.
- Les secrets restent réservés au serveur ; aucune clé secrète n’est ajoutée au dépôt.

## 1.9.5 — Connexion par mot de passe et lisibilité

- Connexion avec adresse e-mail et mot de passe, sans code administrateur lors des connexions ordinaires.
- Réinitialisation du mot de passe par e-mail depuis la page de connexion.
- Inscription avec mot de passe, confirmation du mot de passe et code d’accès.
- Augmentation modérée de la taille des textes de l’interface.
- Le rôle applicatif continue d’être déterminé côté base de données, jamais depuis le formulaire.

# Journal des versions — EPC BETHEL

## 1.9.4 — Étape 9 : cohérence d’interface et hygiène de livraison

- La recherche rapide de la barre supérieure permet de filtrer les modules accessibles et d’y naviguer ; le raccourci `Ctrl/Cmd + K` ouvre la recherche.
- Le menu de compte est interactif, affiche le niveau d’accès, propose les liens permis au rôle et permet la déconnexion ; il se ferme par clic extérieur ou Échap.
- La cloche ouvre un état vide explicite : aucune source de notifications n’est déclarée connectée à ce stade, aucune alerte fictive n’est affichée.
- Documentation racine et guide d’installation alignés sur la version 1.9.4 ; ajout de tests de cohérence documentaire et des commandes de barre supérieure.
- Suppression de `tsconfig.tsbuildinfo`, artefact de compilation généré, de l’archive livrée.
- La suite actuelle comprend **19 tests hors ligne** ; le précontrôle conserve son avertissement relatif à l’absence de `package-lock.json`. Compilation complète, exécution Supabase et déploiement Vercel toujours non validés.

## 1.9.3 — Étape 8 : mode aperçu sûr et absence de données fictives

- Suppression des exemples fictifs d'élèves, coordonnées, paiements, dépenses, achats et patrimoine des métadonnées de modules.
- Les listes scolaires démarrent vides et demeurent vides sans connexion Supabase ; aucun exemple n'est présenté comme un enregistrement de l'établissement.
- Les actions de création des rubriques scolaires sont indisponibles en mode aperçu.
- Le contexte d'accès applique la lecture seule par défaut si aucun rôle utilisateur n'est établi.
- En environnement connecté, les menus protégés ne sont visibles que lorsqu'un rôle valide a été vérifié ; une erreur de vérification renvoie vers la connexion.
- Ajout de quatre tests structurels pour détecter le retour des données fictives et préserver le principe « fail closed ».
- La validation par build, par TypeScript complet et sur Supabase reste à effectuer : le registre npm renvoie toujours `EAI_AGAIN` et le fichier `package-lock.json` ne peut pas être généré ici.


## 1.9.2 — Étape 7 : revue finale de livraison

- Ajout d’une suite de 12 tests de pré-livraison hors ligne avec `node:test`, lançable par `npm run test:release` sans dépendances applicatives installées.
- Les tests couvrent la présence des routes d’authentification, le rôle de l’administrateur principal, l’inscription par code, l’OTP, la séparation des rôles, l’absence de références de clé service dans les composants clients, les migrations et les garde-fous financiers.
- Ajout de `CHECKLIST_MISE_EN_SERVICE.md` couvrant installation, Supabase de développement, matrice RLS, parcours métier, préproduction Vercel et critères de mise en production.
- Mise à jour de la documentation vers la version 1.9.2 et ajout du rapport final de contrôle.
- Résultats locaux : 12 tests hors ligne réussis ; précontrôle 11 réussites, 1 avertissement et 0 échec ; 23 fichiers TypeScript/TSX sans erreur syntaxique.
- Le build complet et le typecheck ne sont pas validés : le registre npm est inaccessible (`EAI_AGAIN registry.npmjs.org`) et les dépendances ne sont pas installées. La migration SQL et les tests end-to-end doivent encore être exécutés sur un projet Supabase de développement. `package-lock.json` reste à générer dans un environnement connecté.

## 1.9.1 — Étape 6 : contrôles finaux et préparation au déploiement

- Ajout du script autonome `scripts/preflight-check.mjs` et de la commande `npm run preflight`.
- Contrôles statiques des fichiers essentiels, imports locaux, références tables/RPC, ordre des migrations, délimiteurs SQL, règles `.env` et absence d’utilisation client de la clé service.
- Mise à jour du rapport qualité avec les résultats mesurés de l’étape 6 et les limites explicites de la validation.
- 25 fichiers TypeScript/TSX passent l’analyse syntaxique ; aucune erreur syntaxique détectée.
- L’analyse statique a corrigé deux défauts dans le module Patrimoine (état `loading` inexistant et motif de refus potentiellement nul).
- Les dépendances n’ont pas pu être installées : le registre npm a renvoyé `EAI_AGAIN registry.npmjs.org`. Le typecheck et le build complet ne sont donc pas validés.
- La base Supabase n’étant pas connectée, les migrations et les tests fonctionnels/RLS restent à exécuter sur un projet de développement.
- `package-lock.json` absent : à générer et conserver depuis un environnement connecté avant le déploiement.


## 1.9.0 — Étape 5 : achats, patrimoine et rapports

- Rapport de gestion connecté aux fonctions PostgreSQL : synthèse financière, impayés, encaissements, dépenses, journal de caisse/banque, bons de commande, réceptions, inventaire et maintenance.
- Filtres de période, année scolaire lorsque pertinent, recherche, pagination serveur, export Excel des résultats filtrés (maximum 50 000 lignes) et impression navigateur.
- Historique réel des réceptions affiché dans Achats, avec recherche ; activation/désactivation des fournisseurs sans supprimer l’historique.
- À la réception d’articles de nature « immobilisation », création automatique d’une fiche d’inventaire par unité entière, liée à la ligne de commande ; aucune dépense ou sortie de trésorerie n’est créée par la réception.
- Catégorie patrimoniale propagée de la demande à la ligne de commande ; la catégorie est résolue à partir du code ou du nom ; une valeur non reconnue est refusée, tandis qu’une catégorie non renseignée utilise « Autres biens » si cette catégorie est active.
- Modification des fiches d’inventaire et enregistrement transactionnel des maintenances avec synchronisation du statut du bien.
- Nouvelle migration `014_management_reports_asset_integration.sql`.
- Contrôles statiques et intégrité de l’archive réalisés. Compilation Next.js et exécution des migrations sur Supabase restent à valider dans un environnement configuré.


## 1.8.0 — Étape 4 : fiabilité financière et trésorerie

- Ajout d’agrégats PostgreSQL pour les recettes, dépenses, frais, paiements affectés, soldes dus et trésorerie afin d’éviter des totaux limités au nombre de lignes chargées dans le navigateur.
- Ajout d’une liste de frais paginée côté serveur et de listes d’inscriptions avec solde positif pour l’encaissement.
- Refonte du tableau de bord pour obtenir les indicateurs et recettes mensuelles depuis les fonctions SQL.
- Refus côté base des dates de paiement, de validation de dépense et de transfert situées dans le futur ; contrôles de date cohérents dans l’interface.
- Conservation de l’historique des opérations et des mécanismes de contrepassation existants.
- Migration ajoutée : `013_financial_integrity_reporting.sql`. Tests de compilation et d’intégration Supabase encore requis avant production.

## Version 1.6.1 — Stabilisation technique (16 octobre 2026)
- Alignement de la version du paquet sur la livraison V1.6.
- Déclaration du prérequis Node.js 20.9 ou supérieur dans `package.json`.
- Renforcement de `.gitignore` pour exclure les fichiers d’environnement contenant des secrets, en conservant `.env.example`.
- Sécurisation du `search_path` des cinq fonctions `SECURITY DEFINER` de la migration 008 (`search_path = ''` ; références de schéma qualifiées).
- Contrôles statiques effectués ; compilation complète et exécution des migrations restent à valider dans un environnement disposant des dépendances et d’un projet Supabase de test.

## Version 1.5.0 — Étape 4 : achats et patrimoine
- Page Achats & fournisseurs : gestion des fournisseurs, demandes avec lignes, soumission et décision, commandes créées depuis les demandes approuvées, réceptions partielles/complètes.
- Page Patrimoine & inventaire : registre des biens, catégories initiales, maintenance et mouvements d’emplacement.
- Migration `008_achats_patrimoine_workflows.sql` : fonctions transactionnelles de workflow et contrôle des quantités réceptionnées.
- Les commandes et réceptions n’émettent pas de mouvement de trésorerie. Le paiement doit passer par Dépenses pour éviter les doubles sorties.
- Les tests de compilation et de connexion Supabase restent à effectuer avant la production.


## Version 1.4.0 — Étape 3 : trésorerie et comptabilité
- Nouvelle page Trésorerie reliée à Supabase : comptes actifs, soldes calculés à partir du solde initial et des mouvements validés, journal filtrable et export CSV.
- Transferts internes par fonction SQL transactionnelle : deux mouvements liés (sortie/entrée), contrôle du compte source, vérification du solde et journal d’audit.
- Nouvelle page Dépenses : création en brouillon, catégories, compte à débiter, validation avec contrôle du solde, annulation par contrepassation et export CSV.
- Numérotation annuelle des dépenses et journal d’audit.
- Migration `007_tresorerie_comptabilite.sql`.
- L’étape n’est pas certifiée en production avant application et tests des migrations sur Supabase de développement, tests sous chaque rôle et compilation complète.

## Version 1.3.0 — Étape 2
- Encaissements, affectations, reçus et annulations.

## Version 1.2.0 — Étape 1
- Éléments de gestion scolaire et concessions.

## Version 1.6.0 — Étape 5
- Renforcement du contrôle d’authentification dans l’espace applicatif et filtrage de navigation selon les rôles.
- Administration des utilisateurs : invitations par e-mail côté serveur, attribution de rôle et activation/désactivation des profils. La clé service n’est jamais exposée au navigateur.
- Paramètres réels de l’établissement et gestion transactionnelle de l’année scolaire active via la migration 009.
- Réinitialisation du mot de passe par e-mail avec écran de définition du nouveau mot de passe.
- Import des élèves depuis Excel (.xlsx/.xls) ou CSV avec aperçu, contrôle des champs obligatoires, détection des matricules en double et import par lots sans écraser les dossiers existants.
- Exports CSV existants conservés; impression navigateur utilisable pour l’enregistrement PDF.


## Version 1.7.0 — Étape 3 : gestion scolaire
- Dossiers élèves : modification des données principales et des coordonnées du responsable légal principal (téléphone, e-mail, profession, adresse et lien avec l’élève).
- Matricule proposé automatiquement si celui-ci est laissé vide à la création ; le matricule reste obligatoire pour la modification d’un dossier existant.
- Inscriptions et réinscriptions enregistrées via une fonction SQL contrôlée, avec vérification de l’élève actif, de l’année ouverte, de la classe active et journal d’audit.
- Changement de classe sur une inscription active, avec date, motif et journal d’audit.
- Sortie définitive ou transfert vers un autre établissement, avec clôture de l’inscription active et mise à jour du statut du dossier si aucune autre inscription active ne subsiste.
- Paramètres : gestion des classes (création, modification, ordre, activation/désactivation) et liste historique des années scolaires (création, modification, choix de l’année active).
- Nouvelle migration `012_school_management_completion.sql`.
- Les validations de syntaxe TypeScript passent, mais la compilation complète et l’exécution PostgreSQL/Supabase restent à effectuer dans un environnement connecté aux dépendances et au projet réel.



## 1.9.8 — Code d’accès administrateur configurable
- Ajout du paramètre « Utilisateurs et autorisations » pour définir/remplacer le code d’inscription depuis l’application.
- Le code n’est jamais renvoyé au navigateur ; seul son condensat salé est stocké dans une table inaccessible aux rôles anon/authenticated.
- Ajout de la migration `015_admin_registration_code_settings.sql`.
- Les API d’administration acceptent les clés Supabase publishable/anon et secret/service_role actuelles.
- La création de compte vérifie le code stocké côté serveur ; plus besoin de la variable `EPC_BETHEL_REGISTRATION_CODE`.

## 1.10.5 — Trésorerie organisée en cinq rubriques
- Navigation de trésorerie structurée autour des cinq rubriques demandées, filtres par période/compte/nature/statut et export CSV des résultats.
- Transferts confirmés avant enregistrement et messages de trésorerie simplifiés.
- Ajout du type de compte Mobile Money via migration additive 016.
- Rapport de livraison et limites de préproduction : `RAPPORT_TRESORERIE_V1_10_5.md`.

## V1.10.6 — Finalisation Trésorerie
- Clôtures journalières de caisse et Mobile Money avec écart justifié et historique non modifiable.
- Import CSV des relevés bancaires et rapprochement manuel sans création ni altération de mouvements financiers.
- Migration additive 017 et rapport `RAPPORT_TRESORERIE_V1_10_6.md`.
