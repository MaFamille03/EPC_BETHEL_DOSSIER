# EPC BETHEL — Rapport d’étape 2 : comptes et sécurité

## Changements intégrés dans le code

- Administrateur principal prévu : `minnhindje@gmail.com`. Le schéma associe le rôle `admin` à cette adresse et empêche, dans les protections de profil, de promouvoir un autre compte ou de désactiver/rétrograder le compte principal.
- Création de compte via `/register`, protégée par `EPC_BETHEL_REGISTRATION_CODE`, vérifiée côté serveur. L’API exige un code d’au moins 24 caractères.
- L’inscription crée une invitation e-mail. L’utilisateur doit confirmer la propriété de sa boîte avant de se connecter ; l’API ne marque pas arbitrairement l’adresse comme vérifiée.
- Connexion sans mot de passe : code OTP temporaire envoyé par e-mail par Supabase Auth.
- Deux niveaux opérationnels comme dans GMP : `observateur` (lecture seule) et `modification` (édition des données métier). Tous les nouveaux comptes commencent observateurs. Seul le compte administrateur peut modifier ces niveaux ou activer/désactiver un autre compte.
- Les droits sont appliqués côté PostgreSQL/RLS et les commandes d’écriture sont masquées pour les observateurs dans l’interface. Le niveau Modification n’autorise pas à administrer les utilisateurs, ni à consulter les journaux de sécurité.
- Les changements de rôle et d’état sont consignés dans `audit_logs`.
- Variables et consignes Supabase documentées dans `ETAPE_2_SECURITE.md`.

## Fichiers principaux concernés

- `app/login/page.tsx` — connexion OTP par e-mail.
- `app/register/page.tsx` et `app/api/auth/register/route.ts` — création de compte sécurisée et invitation e-mail.
- `app/utilisateurs/page.tsx` et `app/api/admin/users/route.ts` — invitation, niveau d’accès, activation/désactivation.
- `components/access-context.tsx`, `components/app-shell.tsx` et composants métier — application de l’accès lecture seule dans l’interface.
- `supabase/migrations/010_add_observateur_role.sql` — nouveaux niveaux d’accès dans l’énumération PostgreSQL.
- `supabase/migrations/011_auth_admin_and_observer_access.sql` — administrateur principal, rôles par défaut, contrôles, RLS et audit.

## Contrôles exécutés localement

- Analyse syntaxique TypeScript/TSX : **21 fichiers analysés, aucune erreur syntaxique détectée**.
- Vérification des imports locaux : **aucun import interne manquant détecté**.
- Configuration `package.json` lisible et valide.
- Migrations SQL présentes dans l’ordre `001` à `011`.
- Archive ZIP testée après création.

## Limites : ne pas considérer le déploiement comme validé

- L’installation complète des dépendances npm a expiré dans l’environnement de préparation ; `npm run typecheck` et `npm run build` ne sont donc pas déclarés réussis.
- Les migrations 010 et 011 n’ont pas été exécutées sur un projet Supabase réel.
- L’envoi des invitations/OTP, les modèles d’e-mail, la confirmation de la boîte, les RLS et les transactions doivent être testés dans un projet Supabase de développement.
- Il faut configurer `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` et un `EPC_BETHEL_REGISTRATION_CODE` aléatoire d’au moins 24 caractères. La clé `SUPABASE_SERVICE_ROLE_KEY` et le code d’inscription restent exclusivement côté serveur.
- Dans Supabase Auth, configurer les modèles d’invitation avec `{{ .ConfirmationURL }}` et d’OTP avec `{{ .Token }}`, ajouter `/login` aux URL de redirection autorisées, vérifier l’envoi e-mail et désactiver les inscriptions publiques directes afin de ne pas contourner le code d’accès.
- **Avant d’appliquer la migration 011 sur une base déjà utilisée, effectuer une sauvegarde.** Cette migration passe les profils existants non-administrateurs au niveau `observateur`; l’administrateur devra réattribuer `modification` aux personnes qui en ont besoin.

## Ordre de déploiement

1. Sauvegarder la base et vérifier que les migrations 001 à 009 sont appliquées.
2. Appliquer `010_add_observateur_role.sql`, puis `011_auth_admin_and_observer_access.sql`, dans cet ordre, sur une base de développement.
3. Confirmer l’adresse administrateur et vérifier son profil `admin`.
4. Tester les scénarios administrateur, observateur, modification et compte désactivé, y compris par requêtes directes à Supabase.
5. Exécuter `npm install`, `npm run typecheck` et `npm run build` dans l’environnement de déploiement avant de publier.
