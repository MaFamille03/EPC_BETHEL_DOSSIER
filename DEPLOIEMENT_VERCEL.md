# Déploiement EPC BETHEL — Vercel et Supabase

Cette version corrige la gestion des droits administrateur et ajoute le transfert contrôlé du rôle depuis Paramètres. Les variables déjà présentes dans Vercel peuvent être conservées ; aucune variable dédiée au code d’inscription n’est requise.

## Variables d’environnement

Vérifiez dans Vercel que les variables existantes sont bien définies pour les environnements utilisés :

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` ou `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `NEXT_PUBLIC_SITE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` ou `SUPABASE_SECRET_KEY` côté serveur uniquement

Ne copiez jamais de valeur secrète dans ce dépôt. `NEXT_PUBLIC_SITE_URL` doit correspondre à l’URL canonique autorisée dans Supabase Auth.

## Mise à jour d’un projet déjà déployé

1. Sauvegardez la base Supabase et confirmez la dernière migration réellement appliquée.
2. Déployez le code via le flux GitHub/Vercel habituel.
3. Si la base est à la version de schéma 025, exécutez **uniquement** `supabase/migrations/026_transferable_admin_profile.sql` dans Supabase, après validation en préproduction.
4. Vérifiez que le profil Administrateur existant est actif et que l’accès fonctionne.
5. Dans l’application, testez l’invitation d’un utilisateur, la confirmation d’e-mail, les rôles Observateur/Modification et le transfert administrateur vers un compte confirmé.
6. Vérifiez qu’après le transfert, l’ancien compte devient Modification et que le nouveau compte a accès à l’administration.

Ne réécrivez pas les migrations 001–025 et ne réexécutez pas l’ensemble des migrations sur une base déjà utilisée. Vercel déploie le code de l’application, mais pas les migrations PostgreSQL à votre place.

## Initialisation d’un nouveau projet Supabase vide

Le script `supabase/setup/INSTALLATION_COMPLETE.sql` regroupe les migrations 001 à 026 dans leur ordre d’origine. Il est destiné exclusivement à une base vide : ne l’exécutez pas sur la base actuellement utilisée. Pour initialiser le premier administrateur sur une base neuve, suivez `supabase/setup/README.md`.

## Vérifications de livraison

Sur une machine de développement connectée au registre npm :

```bash
npm install
npm run test:release
npm run preflight
npm run typecheck
npm run build
```

Conservez `package-lock.json` généré dans le dépôt. Avant une mise en production, faites aussi des tests fonctionnels des paiements, annulations, échéances, dépenses, notes, permissions RLS et de la procédure de transfert administrateur dans un environnement de préproduction.
