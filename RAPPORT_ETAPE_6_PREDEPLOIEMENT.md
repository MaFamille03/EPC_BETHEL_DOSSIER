# Étape 6 — Contrôles finaux et préparation au déploiement

**Projet :** EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY  
**Version de contrôle :** 1.9.1  
**Date :** 16 octobre 2026  
**Périmètre :** contrôle statique consolidé des étapes 1 à 5, outillage de précontrôle et préparation des consignes de déploiement.

## 1. Résultat synthétique

**Statut : candidat de préproduction — déploiement de production non autorisé à ce stade.** Le code est structuré et passe les contrôles statiques exécutables dans cet environnement. La compilation, l’exécution de PostgreSQL/Supabase et les tests de bout en bout ne sont pas confirmés.

## 2. Vérifications exécutées

| Contrôle | Résultat | Détail |
|---|---|---|
| Intégrité de l’archive d’entrée | Réussi | Archive ZIP ouverte sans erreur, 79 entrées dans la version reçue. |
| Syntaxe TypeScript/TSX | Réussi | 25 fichiers analysés avec le parseur TypeScript installé globalement ; 0 erreur de syntaxe détectée. |
| Imports internes | Réussi | Aucun import relatif ou `@/…` manquant détecté dans les fichiers applicatifs. |
| Références aux fonctions SQL | Réussi | Les 31 appels RPC repérés dans le code correspondent à des fonctions déclarées dans les migrations. |
| Références aux tables | Réussi | Les 23 tables interrogées depuis l’application sont présentes dans les migrations. |
| Migrations | Réussi en contrôle statique | Les 14 migrations numérotées de `001` à `014` sont présentes, sans trou ; délimiteurs dollar appariés. |
| Fonctions `SECURITY DEFINER` | Réussi en contrôle statique | Les blocs repérés définissent un `search_path` vide. Cela ne remplace pas une revue SQL ni des tests RLS. |
| Fichiers d’environnement | Réussi | `.env.example` ne contient pas de clé de service renseignée ; `.gitignore` exclut `.env*` sauf `.env.example`. |
| Référence à la clé service côté client | Réussi | Aucun accès à `process.env.SUPABASE_SERVICE_ROLE_KEY` dans les modules client. |
| Contrôle `npm run preflight` | Réussi avec avertissement | 11 contrôles réussis, 1 avertissement, 0 échec. L’avertissement concerne l’absence de `package-lock.json`. |

## 3. Tests bloqués par l’environnement

L’installation des dépendances a été tentée avec `npm install`, mais a échoué car le registre npm n’était pas résolu : `EAI_AGAIN registry.npmjs.org`. Ce résultat est une indisponibilité réseau dans l’environnement de préparation, pas une preuve d’erreur ou de réussite de la compilation.

En conséquence :

- `npm run typecheck` **n’est pas validé**. L’exécution directe de `tsc` sans les dépendances installées rapporte notamment l’absence des types Next.js, React, Supabase et Node ; cela ne permet pas d’isoler toutes les erreurs TypeScript propres au projet.
- `npm run build` **n’a pas été exécuté avec succès**.
- Les migrations SQL n’ont pas été exécutées sur PostgreSQL/Supabase.
- Les tests de connexion OTP, inscription, permissions par rôle, RLS, workflows financiers, rapports, export Excel, responsivité et tests end-to-end n’ont pas été réalisés contre une instance fonctionnelle.
- Aucun projet Vercel/Supabase réel n’était connecté, donc aucun déploiement n’a été fait.

## 4. Corrections de code issues de l’analyse statique

L’analyse `tsc` sans dépendances a révélé deux défauts applicatifs indépendants des modules manquants dans `components/purchases-assets-page.tsx` : une référence à un état `loading` non défini (remplacée par `busy`) et un motif de refus dont la valeur pouvait être `null` (normalisée et vérifiée avant l’appel RPC). Les diagnostics restants de type TS2307/TS2580/TS7026 et ceux liés à l’inférence Supabase/React sont affectés par l’absence des paquets et de leurs déclarations ; ils ne permettent pas de certifier un typecheck propre.

## 5. Outil de contrôle local ajouté

Un script autonome `scripts/preflight-check.mjs` et la commande `npm run preflight` ont été ajoutés. Le script utilise Node.js et contrôle la structure, les variables d’exemple, la protection de `.env`, la présence des migrations, les tables/RPC référencées et certaines mesures statiques de sécurité. Il peut être exécuté sans installer les dépendances applicatives.

Il **ne remplace pas** `npm run typecheck`, `npm run build`, l’exécution des migrations SQL ou les tests réels. L’absence de `package-lock.json` reste un avertissement ; il faut générer et conserver ce fichier depuis un environnement disposant d’un accès au registre npm afin de figer les dépendances résolues.

## 6. Procédure requise avant le déploiement

1. Sur une machine connectée, utiliser Node.js `20.9` ou supérieur et exécuter `npm install` à la racine du projet ; vérifier que `package-lock.json` est généré, puis le conserver dans le dépôt.
2. Exécuter, dans cet ordre, `npm run preflight`, `npm run typecheck` et `npm run build`. Résoudre toute erreur avant de poursuivre.
3. Créer ou utiliser une base Supabase de **développement**, effectuer une sauvegarde, puis appliquer les migrations `001` à `014` une à une. Arrêter au premier échec ; ne pas relancer aveuglément une migration partiellement exécutée.
4. Configurer et tester l’e-mail Supabase (invitation et OTP), les URL autorisées et les redirections. Configurer les secrets dans l’environnement serveur/Vercel sans exposer `SUPABASE_SERVICE_ROLE_KEY` côté navigateur.
5. Tester les profils `admin`, `modification` et `observateur`, en vérifiant non seulement les menus mais aussi les accès directs, RLS et chaque RPC sensible.
6. Exécuter les scénarios scolaires et financiers documentés dans `README.md` : inscriptions/transferts, frais et concessions, paiements partiels et annulations, dépenses, transferts de caisse, achats/réceptions, inventaire, maintenance et rapports. Comparer les montants affichés à des requêtes SQL de contrôle.
7. Tester l’affichage sur ordinateur, tablette et téléphone, les impressions et les exports. Effectuer d’abord un déploiement Vercel de préproduction ; sauvegarder et valider les données avant toute mise en production.

## 7. Conclusion

L’étape 6 fournit un contrôle statique reproductible et un parcours de validation. Elle n’établit pas que l’application compile, que les migrations s’exécutent sans erreur ou que les rôles sont correctement imposés dans un projet réel. EPC BETHEL doit rester en préproduction jusqu’à réussite des tests listés ci-dessus.
