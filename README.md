# EPC BETHEL — Application de gestion scolaire

**Établissement :** EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY  
**Version courante :** 1.9.4  
**Stack :** Next.js 15, React 19, TypeScript, Supabase/PostgreSQL

## État de livraison

EPC BETHEL est une base applicative avancée, mais elle **n’est pas certifiée prête pour la production**. Les dépendances n’ont pas pu être installées dans l’environnement de préparation, car le registre npm a renvoyé `EAI_AGAIN`. Le `typecheck`, la compilation Next.js, les migrations sur une base Supabase réelle et les tests de bout en bout restent donc à valider dans un environnement configuré.

Les contrôles hors ligne actuels comprennent `npm run preflight` et **19 tests hors ligne** via `npm run test:release`. Ils contrôlent la structure et certains invariants du code, sans remplacer la compilation ou les tests réels.

## Fonctionnalités incluses

- Tableau de bord, navigation et recherche rapide des modules.
- Authentification par code OTP temporaire envoyé par e-mail et création de compte protégée par un code d’accès.
- Gestion des élèves, responsables légaux, inscriptions, classes et années scolaires.
- Frais scolaires, six échéances, concessions, encaissements, reçus, dépenses et trésorerie.
- Achats, fournisseurs, réceptions, inventaire et maintenance du patrimoine.
- Rapports de gestion, filtres, exports et impressions selon les modules.
- Administration des accès : administrateur principal, observateur et modification.
- Quatorze migrations SQL de référence, `001` à `014`.

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
4. Configurez Supabase Auth : OTP par e-mail, modèle d’invitation, URL du site, redirections autorisées et service e-mail.
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

- `npm run test:release` : **19 tests** de cohérence et de pré-livraison, sans accès réseau ou Supabase.
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
