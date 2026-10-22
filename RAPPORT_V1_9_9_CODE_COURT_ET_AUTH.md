# EPC BETHEL — Version 1.9.9

## Modifications
- Le code d’accès administrateur demandé lors de la création d’un compte est maintenant numérique, de 6 à 8 chiffres.
- Ce code est utilisé uniquement pour autoriser une nouvelle inscription. La connexion reste basée sur l’adresse e-mail et le mot de passe du compte.
- Le formulaire des paramètres et le formulaire d’inscription valident le format numérique court.
- Correction d’un défaut d’import dans la route d’inscription : `scryptSync` était utilisé sans être importé.

## Déploiement
- Aucun changement de schéma SQL requis par cette modification.
- Après remplacement du dépôt, lancer `npm install`, `npm run test:release`, `npm run preflight`, `npm run typecheck` et `npm run build`.
- Le nouveau code d’accès doit être enregistré dans Paramètres → Utilisateurs et autorisations. Les codes longs déjà enregistrés devront être remplacés par un code de 6 à 8 chiffres.

## Limites
Les contrôles de compilation complète et les tests contre la base Supabase réelle doivent être exécutés dans l’environnement du projet. Le code court doit être communiqué uniquement aux personnes autorisées ; prévoir une limitation des tentatives si l’application est exposée publiquement.
