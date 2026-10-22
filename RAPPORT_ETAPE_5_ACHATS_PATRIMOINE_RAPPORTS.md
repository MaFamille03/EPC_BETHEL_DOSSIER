# EPC BETHEL — Rapport de l’étape 5 : achats, patrimoine et rapports

**Version :** 1.9.0  
**Migration ajoutée :** `014_management_reports_asset_integration.sql`

## 1. Achats et fournisseurs

- L’onglet Réceptions présente l’historique des réceptions enregistrées, avec numéro, date, commande, fournisseur, référence de livraison et statut.
- Recherche intégrée sur l’historique des réceptions.
- Un fournisseur peut être désactivé ou réactivé sans effacer ses anciennes commandes. Les nouvelles commandes sont liées à des fournisseurs actifs.
- La catégorie saisie sur la demande est copiée sur la ligne de commande. Pour une immobilisation, le code ou le nom exact d’une catégorie active est résolu à la réception. Si la catégorie saisie est inconnue ou inactive, la réception est refusée avec un message explicite. Si aucune catégorie n’est saisie, la catégorie « Autres biens » est utilisée comme valeur par défaut, à condition qu’elle soit active.

## 2. Intégration du patrimoine

- La réception d’une ligne de commande de nature « immobilisation » crée automatiquement une fiche dans `assets` pour chaque unité entière reçue.
- Chaque bien garde le lien vers la ligne du bon de commande, le fournisseur, le coût unitaire et sa catégorie. Des codes d’inventaire uniques sont générés.
- Les quantités fractionnaires sont refusées pour les immobilisations ; les quantités reçues ne peuvent pas dépasser les quantités commandées.
- La fiche d’inventaire existante peut être modifiée depuis l’interface.
- La maintenance est enregistrée via `register_asset_maintenance`, qui contrôle les données, le prestataire actif et l’état du bien, puis synchronise le statut quand une maintenance commence ou se termine.
- La réception physique ne crée pas de sortie de trésorerie ; le règlement doit rester enregistré via le workflow Dépenses pour éviter les doubles mouvements.

## 3. Rapports de gestion

La page Rapports ne redirige plus vers la page générique. Elle se connecte à Supabase et fournit :

- Synthèse financière : recettes validées et dépenses validées de la période, frais nets, remises, paiements affectés, impayés et trésorerie.
- Impayés de scolarité : matricule, élève, classe, année, montants bruts et nets, montants payés, solde et date d’échéance.
- Journal des encaissements.
- Journal des dépenses.
- Journal de caisse et de banque.
- Bons de commande et réceptions.
- Inventaire du patrimoine et suivi des maintenances.

Les rapports détaillés sont calculés et paginés dans PostgreSQL, filtrables par date et recherche, avec filtre par année scolaire pour les impayés et paiements. L’export Excel parcourt les pages filtrées jusqu’à 50 000 lignes et l’impression navigateur est disponible. Aucun chiffre de démonstration n’est utilisé en cas de connexion absente.

## 4. Fichiers touchés

- `components/reports-page.tsx` — nouveau module de rapports réels.
- `components/purchases-assets-page.tsx` — historique des réceptions, gestion fournisseur, modification des biens et maintenance contrôlée.
- `app/[section]/page.tsx` — branchement de la page Rapports sur son nouveau composant.
- `app/globals.css` — dispositions adaptées aux filtres et aux écrans étroits.
- `supabase/migrations/014_management_reports_asset_integration.sql` — RPC de rapports, propagation de catégorie, réception intégrée aux actifs et RPC maintenance.
- `README.md`, `INSTALLATION_RAPIDE.txt`, `ETAPE_5_NOTES.txt`, `CHANGELOG.md`, `RAPPORT_CONTROLE_QUALITE.md` — documentation mise à jour.

## 5. Contrôles et limites

- 24 fichiers TS/TSX passés dans une transpilation syntaxique isolée sans erreur de syntaxe.
- Aucun import interne manquant détecté par le contrôle statique.
- Les 14 migrations sont présentes dans l’ordre ; les fonctions clés et les délimiteurs SQL de la migration 014 ont passé les contrôles statiques simples.
- `npm install` a expiré malgré une tentative avec cache préférentiel. En conséquence, `npm run typecheck` et `npm run build` ne sont pas certifiés.
- La migration 014 n’a pas été exécutée sur une base Supabase réelle ; les parcours de l’étape 5 doivent être testés dans un environnement de développement avant l’usage de données réelles.

## 6. Procédure conseillée

1. Sauvegarder le projet et la base.
2. Appliquer les migrations 001 à 014 une par une sur un projet Supabase de développement.
3. Exécuter `npm install`, `npm run typecheck` et `npm run build` dans un environnement disposant de l’accès aux dépendances.
4. Tester les rapports en les comparant à des requêtes de référence, puis les réceptions partielles/complètes, la génération du patrimoine, les catégories et les maintenances.
5. Vérifier avec les profils administrateur, modification et observateur, puis seulement préparer un déploiement de préproduction.
