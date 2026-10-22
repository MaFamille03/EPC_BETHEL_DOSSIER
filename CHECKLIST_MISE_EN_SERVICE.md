# EPC BETHEL — checklist de mise en service

**Statut actuel : candidat de préproduction, non certifié pour la production.** Cette checklist doit être remplie par étapes. Ne pas importer les données réelles avant validation de la base et des permissions.

## A. Poste de développement

- [ ] Utiliser Node.js 20.9 ou supérieur.
- [ ] Accéder au registre npm et exécuter `npm install` à la racine du projet.
- [ ] Conserver le `package-lock.json` généré dans le dépôt.
- [ ] Exécuter `npm run test:release`.
- [ ] Exécuter `npm run preflight`.
- [ ] Exécuter `npm run typecheck` sans erreur.
- [ ] Exécuter `npm run build` sans erreur.
- [ ] Lancer `npm run dev` et tester la navigation, l'authentification et les modules.

## B. Supabase — environnement de développement uniquement

- [ ] Créer un projet Supabase de développement et une sauvegarde avant tout changement.
- [ ] Définir les URL autorisées, l'URL du site et les redirections Auth.
- [ ] Configurer l'envoi d'invitations et de codes OTP par e-mail.
- [ ] Définir `NEXT_PUBLIC_SUPABASE_URL` et `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- [ ] Définir `NEXT_PUBLIC_SITE_URL` sur l'URL de l'environnement testé.
- [ ] Définir `EPC_BETHEL_REGISTRATION_CODE` avec au moins 24 caractères aléatoires ; ne jamais utiliser une valeur d'exemple.
- [ ] Définir `SUPABASE_SERVICE_ROLE_KEY` uniquement côté serveur, dans un gestionnaire de secrets, jamais dans le navigateur ou Git.
- [ ] Examiner puis exécuter les migrations `001` à `014`, une par une et dans l'ordre.
- [ ] Arrêter au premier échec SQL ; diagnostiquer avant de poursuivre.
- [ ] Confirmer que `minnhindje@gmail.com` est la véritable adresse contrôlée par l'administrateur et vérifier son profil `admin` dans Supabase.
- [ ] Tester inscription par code, confirmation e-mail, connexion OTP, déconnexion et compte désactivé.
- [ ] Vérifier que le compte `observateur` ne peut ni écrire via l'interface ni contourner les protections RLS/RPC.
- [ ] Vérifier que le compte `modification` peut modifier les données métier autorisées, mais ne peut pas gérer les utilisateurs ni devenir administrateur.
- [ ] Vérifier le compte administrateur : gestion des comptes, modification des autorisations et protection contre la rétrogradation.
- [ ] Tester frais, six échéances, concessions, paiements partiels, reçus, dépenses, contrepassations et transferts de caisse/banque.
- [ ] Tester achats, réceptions partielles et complètes, création de biens, maintenance, rapports et exports.
- [ ] Comparer les totaux de l'interface aux requêtes de contrôle PostgreSQL ; noter les résultats.
- [ ] Vérifier les politiques RLS et les droits `EXECUTE` des fonctions SQL avec chaque rôle.

## C. Préproduction Vercel

- [ ] Importer le dépôt dans Vercel et utiliser le bon dossier racine (`EPC_BETHEL_APP`).
- [ ] Configurer les variables publiques et secrètes selon leur portée ; ne jamais exposer la clé de service.
- [ ] Créer un déploiement Preview, pas Production.
- [ ] Confirmer la compilation et la disponibilité des routes `/login`, `/register` et `/api/...`.
- [ ] Tester sur ordinateur, tablette et téléphone.
- [ ] Examiner les journaux Vercel et Supabase après chaque parcours important.
- [ ] Conserver les captures/résultats des tests, la version déployée et le plan de retour arrière.

## D. Autorisation de mise en production

- [ ] Tous les tests des sections A, B et C sont réussis et documentés.
- [ ] Sauvegarde de la base réalisée et procédure de restauration vérifiée.
- [ ] Aucun secret n'est committé ou exposé.
- [ ] Les migrations et politiques ont été revues avant application sur la base de production.
- [ ] L'administrateur a vérifié ses accès et dispose d'un moyen de récupération de compte.
- [ ] La direction valide l'utilisation de vraies données scolaires et financières.
- [ ] Le déploiement production est effectué uniquement après ces validations.

**Aucune case ne doit être considérée comme validée sur la base du seul contrôle statique du code.**
