# EPC BETHEL — Gestion scolaire et financière

**Version courante :** 1.21.0
**Stack :** Next.js 15, React 19, TypeScript, Supabase/PostgreSQL.
**Déploiement :** GitHub + Vercel.

## Objectif

Application interne de gestion scolaire pour EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY. Elle regroupe les dossiers des élèves, les inscriptions, les frais et échéances, la trésorerie, les notes et bulletins, les achats, le patrimoine, les rapports et l’administration des accès.

## Principales rubriques

- **Vue générale :** indicateurs scolaires et financiers.
- **Gestion scolaire :** dossiers des élèves, import Excel, frais de scolarité, notes et bulletins.
- **Finances :** caisse/Mobile Money, banque, transferts internes, journal, dépenses et rapprochement bancaire.
- **Établissement :** achats, inventaire et patrimoine.
- **Administration :** utilisateurs et autorisations, paramètres, années scolaires, classes, tarifs et échéances annuelles.

## Architecture

- `app/` : pages et API serveur.
- `components/` : modules d’interface et composants métier.
- `lib/` : clients Supabase et logique partagée.
- `supabase/migrations/` : historique SQL versionné de 001 à 026.
- `supabase/setup/INSTALLATION_COMPLETE.sql` : script consolidé réservé à une **nouvelle base vide**. `supabase/setup/README.md` explique l’initialisation du premier administrateur.
- `tests/` et `scripts/` : contrôles structurels hors ligne.
- `public/` : logo, icônes, filigrane et modèle Excel d’import des élèves.
- `documentation/` : spécifications techniques et documentation métier.

## Variables d’environnement

Dans Vercel, conserver les variables déjà configurées. Le projet utilise :

| Variable | Usage |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | URL du projet Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` ou `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Clé publique de navigateur |
| `NEXT_PUBLIC_SITE_URL` | URL canonique du site, utilisée pour les liens d’invitation |
| `SUPABASE_SERVICE_ROLE_KEY` ou `SUPABASE_SECRET_KEY` | Clé serveur privée, uniquement pour les routes serveur |

Le code d’accès aux nouvelles inscriptions est stocké sous forme de hash dans `admin_access_settings` et se gère dans **Paramètres → Utilisateurs et autorisations**. Il ne nécessite pas de variable d’environnement dédiée. Ne jamais exposer la clé service dans un composant client, une variable `NEXT_PUBLIC_` ou Git.

Le fichier `.env.example` fournit uniquement des exemples ; il ne contient aucun secret réel.

## Migrations Supabase : lire avant d’exécuter

### Projet existant

Ne remplacez pas l’historique et ne réexécutez pas toutes les migrations sur une base déjà utilisée. Vérifiez la dernière migration réellement appliquée dans Supabase, faites une sauvegarde, puis appliquez **uniquement les migrations manquantes et dans l’ordre numérique**.

Pour une base déjà à la migration 025, la modification de cette version est :

`supabase/migrations/026_transferable_admin_profile.sql`

Cette migration active le transfert contrôlé du rôle Administrateur dans Paramètres. Vercel ne déploie pas automatiquement les changements PostgreSQL : la migration doit être exécutée séparément dans Supabase après sauvegarde et validation en préproduction.

### Nouvelle base vide uniquement

Pour initialiser un nouveau projet Supabase vide, vous pouvez exécuter une seule fois :

`supabase/setup/INSTALLATION_COMPLETE.sql`

Ce script consolide le schéma et les évolutions de 001 à 026 pour une installation neuve ; le bootstrap historique par adresse e-mail fixe y est retiré. **Ne l’exécutez jamais sur votre base existante**, car il contient le schéma initial complet et les évolutions historiques. Suivez `supabase/setup/README.md` pour attribuer explicitement le premier rôle administrateur via une fonction SQL réservée à l’initialisation.

Les migrations numérotées sont conservées comme historique de mise à niveau pour ne pas désynchroniser l’état d’une base déjà déployée.

## Rôles et changement d’administrateur

- **Administrateur :** gère les utilisateurs, les paramètres de sécurité et les autorisations.
- **Modification :** gère les données métier autorisées, sans administrer les comptes.
- **Observateur :** consulte les informations en lecture seule.

Pour changer d’administrateur, ouvrez **Paramètres → Profil administrateur**. Sélectionnez un utilisateur déjà créé, actif et confirmé par e-mail, puis saisissez `TRANSFERER`. Le transfert s’effectue dans une transaction SQL : le compte choisi devient Administrateur et l’ancien compte conserve le niveau Modification. L’application déconnecte l’ancien administrateur à la fin de l’opération. Ne supprimez pas le profil administrateur avant d’avoir transféré le rôle.

L’attribution du rôle Administrateur est bloquée dans les formulaires ordinaires ; seule la fonction SQL contrôlée autorise le transfert. Les nouveaux utilisateurs commencent avec le niveau Observateur.

## Développement et contrôles

Prérequis : Node.js 20.9 ou supérieur et npm.

```bash
npm install
npm run test:release
npm run preflight
npm run typecheck
npm run build
npm run dev
```

Conservez `package-lock.json` après l’installation sur une machine connectée au registre npm. Les tests hors ligne et le précontrôle vérifient la cohérence structurelle ; ils ne remplacent pas la compilation, les tests PostgreSQL/RLS ni les essais métier en préproduction.

Avant l’utilisation réelle, validez au minimum les rôles, la connexion, les invitations, les transferts de paiement, les encaissements, les annulations, les réductions, les échéances scolaires, les notes et bulletins, les rapports et le transfert d’administrateur sur une base de préproduction.
