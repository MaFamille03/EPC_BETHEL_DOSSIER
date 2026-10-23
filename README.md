# EPC BETHEL — Application de gestion scolaire

**Établissement :** EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY  
**Version courante :** 1.13.2  
**Stack :** Next.js 15, React 19, TypeScript, Supabase/PostgreSQL

## État de livraison

EPC BETHEL est une base applicative avancée, mais elle **n’est pas certifiée prête pour la production**. Les dépendances n’ont pas pu être installées dans l’environnement de préparation, car le registre npm a renvoyé `EAI_AGAIN`. Le `typecheck`, la compilation Next.js, les migrations sur une base Supabase réelle et les tests de bout en bout restent donc à valider dans un environnement configuré.

Les contrôles hors ligne actuels comprennent `npm run preflight` et **24 tests hors ligne** via `npm run test:release`. La livraison comprend le module Notes et bulletins (migrations 016 et 018), le rapprochement bancaire transactionnel (migration 017) et les améliorations de Gestion des élèves en V1.13.0 et la fenêtre de formulaire élève élargie en V1.13.1 et les raccourcis directs vers Finance scolaire et Notes et bulletins depuis le dossier individuel en V1.13.2. Elle inclut le modèle Excel téléchargeable. Ces contrôles structurels ne remplacent pas la compilation ou les tests réels sur Supabase.

## Fonctionnalités incluses

- Tableau de bord, navigation et recherche rapide des modules.
- Authentification par adresse e-mail et mot de passe ; création de compte avec confirmation du mot de passe et code d’accès. Réinitialisation du mot de passe par e-mail.
- Gestion des élèves, responsables légaux, inscriptions, classes et années scolaires ; import Excel avec aperçu et modèle vierge téléchargeable.
- Frais scolaires, six échéances, concessions, encaissements, reçus, dépenses et trésorerie.
- Achats, fournisseurs, réceptions, inventaire et maintenance du patrimoine.
- Rapports de gestion, filtres, exports et impressions selon les modules.
- Administration des accès : administrateur principal, observateur et modification.
- Dix-huit migrations SQL de référence, `001` à `018`.

## Prérequis et installation locale

- Node.js 20.9 ou supérieur.
- Un projet Supabase de **développement**.
- Un accès au registre npm pour installer les dépendances.

Depuis la racine du projet :

```bash
npm install
cp .env.example .env.local
```

Sous Windows PowerShell, la seconde commande devient `Copy-Item .env.example .env.local`.

Complétez `.env.local` avec les paramètres de votre projet :

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://VOTRE_PROJET.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=VOTRE_CLE_PUBLIQUE
NEXT_PUBLIC_SITE_URL=http://localhost:3000
EPC_BETHEL_REGISTRATION_CODE=
SUPABASE_SERVICE_ROLE_KEY=
```

Renseignez `EPC_BETHEL_REGISTRATION_CODE` avec au moins 24 caractères aléatoires pour autoriser les inscriptions. `SUPABASE_SERVICE_ROLE_KEY` est strictement réservée aux routes serveur. Ne jamais la préfixer par `NEXT_PUBLIC_`, l’insérer dans un composant client ou la committer dans Git.

Après avoir renseigné les variables, lancez :

```bash
npm run test:release
npm run preflight
npm run typecheck
npm run build
npm run dev
```

Le typecheck et le build doivent réussir avant tout déploiement.

## Migrations Supabase

1. Créez un projet Supabase de développement et sauvegardez la base avant toute modification du schéma.
2. Exécutez une migration à la fois, dans cet ordre : `001` à `009`, puis `010_add_observateur_role.sql`, `011_auth_admin_and_observer_access.sql`, `012_school_management_completion.sql`, `013_financial_integrity_reporting.sql` et `014_management_reports_asset_integration.sql`.
3. Vérifiez le résultat après chaque fichier. Au premier échec, arrêtez-vous et examinez l’état du schéma ; ne relancez pas aveuglément une migration partiellement exécutée.
4. Configurez Supabase Auth pour la connexion par mot de passe et les URL autorisées. La création initiale de compte passe par une route serveur protégée par EPC_BETHEL_REGISTRATION_CODE et SUPABASE_SERVICE_ROLE_KEY.
5. Vérifiez l’identité et la confirmation de `minnhindje@gmail.com`. Cette adresse est conçue comme administrateur principal. Ne permettez jamais à un utilisateur public de s’attribuer le rôle administrateur à partir d’un champ de formulaire.
6. Testez les politiques RLS, les fonctions SQL et les parcours avec les trois rôles avant d’ajouter les données réelles de l’école.

Les migrations sont des scripts de référence : leur présence dans le ZIP ne signifie pas qu’elles ont été exécutées sur le projet Supabase réel.

## Rôles et autorisations

- **Administrateur principal (`admin`)** : `minnhindje@gmail.com`, seul habilité à gérer les comptes et leurs niveaux d’accès.
- **Observateur (`observateur`)** : consultation en lecture seule, attribuée par défaut aux nouveaux comptes.
- **Modification (`modification`)** : gestion des données métier, sans administration des utilisateurs ni accès au journal de sécurité.

Les restrictions visuelles de navigation ne suffisent pas : les permissions doivent être appliquées aussi par les routes serveur, PostgreSQL et les politiques RLS.

## Classes prévues

MS, GSA, GSB, CP1 A/B, CP2 A/B, CE1 A/B, CE2 A/B, CM1 A/B et CM2 A/B.

## Contrôles hors ligne et limites

- `npm run test:release` : **23 tests** de cohérence et de pré-livraison, sans accès réseau ou Supabase.
- Appliquer `supabase/migrations/016_notes_bulletins.sql` pour activer la saisie des notes.
- Appliquer `supabase/migrations/017_bank_reconciliation_workflow.sql` pour activer le rapprochement bancaire sécurisé.
- Appliquer `supabase/migrations/018_notes_bulletins_workflows.sql` pour activer les évaluations, les règles de calcul et les bulletins trimestriels, après sauvegarde et validation en préproduction.
- `npm run preflight` : contrôle de la structure, des imports locaux, des migrations, des tables/RPC référencées et de certains points de protection des secrets.
- Les tests de barre supérieure vérifient la recherche rapide, les menus, la fermeture par clic extérieur et Échap ; la zone de notifications indique explicitement lorsqu’aucune source de notifications n’est connectée.
- Le fichier `tsconfig.tsbuildinfo` est un artefact généré et n’est pas livré dans l’archive source.
- `package-lock.json` n’est pas inclus, car la création du lockfile a échoué lorsque le registre npm était inaccessible. Générez-le sur une machine connectée et versionnez-le avant le déploiement.

Le précontrôle local ne remplace pas `npm run typecheck`, `npm run build`, les tests d’intégration SQL/RLS, les tests dans le navigateur ou un déploiement de préproduction Vercel.

## Mise en service

Consultez `CHECKLIST_MISE_EN_SERVICE.md`, `RAPPORT_CONTROLE_QUALITE.md` et `RAPPORT_ETAPE_9_COHERENCE.md`. Avant la production, vérifiez au minimum : authentification OTP et invitations, matrice des trois rôles, dossiers élèves, inscriptions et transferts, échéances/concessions, paiements/annulations, dépenses/transferts, commandes/réceptions, inventaire/maintenance, rapports et exports, affichage responsive et sauvegarde/restauration.

**Cette livraison reste un candidat de préproduction.** Aucun déploiement Vercel ni aucune validation des migrations sur le projet Supabase réel n’a été réalisé dans cette étape.

## Archive consolidée pour GitHub/Vercel

Cette livraison réunit les changements des étapes 1 à 9 et place `package.json` à la racine du projet. Avant l’import, lire `DEPLOIEMENT_VERCEL.md` et `LIVRAISON_FINALE_EPC_BETHEL.md`. La compilation et la validation Supabase restent à réaliser sur un environnement connecté ; ne pas considérer l’archive comme déjà déployée ou certifiée en production.


### Code d’accès aux inscriptions
Le compte administrateur principal définit ou remplace le code dans **Paramètres → Utilisateurs et autorisations**. Appliquer la migration `015_admin_registration_code_settings.sql` avant d’utiliser cette fonction. Le code est stocké sous forme de hash scrypt salé et n’est jamais renvoyé à l’interface.
