# Rapport de contrôle qualité — EPC BETHEL

**Version contrôlée :** 1.9.4 — étapes 1 à 9 consolidées  
**Date :** 16 octobre 2026  
**Statut :** candidat de préproduction ; non certifié pour la production.

## État global

| Contrôle | Résultat | Détail |
|---|---|---|
| Intégrité de l’archive source de l’étape 5 | Réussi | ZIP ouvert sans erreur. L’intégrité de l’archive finale de l’étape 6 est vérifiée après empaquetage. |
| Syntaxe TypeScript/TSX | Réussi | 25 fichiers parcourus ; aucune erreur de syntaxe détectée par le parseur TypeScript. |
| Imports internes | Réussi | Aucun import local manquant détecté par le contrôle statique. |
| Tables/RPC | Réussi en statique | Les 23 tables consultées et 31 RPC utilisées par le code sont déclarées dans les migrations. |
| Migrations | Réussi en statique | Les migrations 001 à 014 sont présentes sans trou de numérotation ; les délimiteurs dollar sont appariés. |
| `SECURITY DEFINER` | Réussi en statique | Les blocs analysés définissent un `search_path` vide. Les tests RLS restent requis. |
| Secrets et `.gitignore` | Réussi en statique | Aucun accès client détecté à `process.env.SUPABASE_SERVICE_ROLE_KEY` ; `.env.example` reste sans secrets renseignés et `.env*` est ignoré sauf le modèle. |
| `npm run preflight` | Réussi avec avertissement | 11 contrôles réussis, 1 avertissement (absence de `package-lock.json`), 0 échec. |
| Installation npm | Bloquée | `npm install` a échoué sur `EAI_AGAIN registry.npmjs.org`, problème d’accès au registre dans l’environnement. |
| Typecheck complet | Non validé | Les dépendances Next.js, React, Supabase et Node ne sont pas installées ; le `tsc` global ne peut pas confirmer les types du projet. |
| Build Next.js | Non validé | Aucun `npm run build` exécuté avec succès. |
| Migrations Supabase | Non exécutées | Aucun projet Supabase de test connecté. |
| Tests RLS, parcours fonctionnels et end-to-end | À faire | Ils requièrent des comptes de test et une base Supabase configurée. |
| Déploiement Vercel | Non effectué | Aucun projet réel n’est connecté ; aucun déploiement n’a été fait. |

## Corrections repérées lors de l’étape 6

L’analyse directe de `tsc` sans les dépendances installées a permis d’isoler deux défauts applicatifs parmi les diagnostics produits par l’absence de types : un nom d’état `loading` inexistant dans le module Patrimoine, remplacé par l’état réel `busy`, et un motif de refus potentiellement nul, désormais normalisé en chaîne avant validation. Le typecheck complet reste non confirmé tant que les dépendances ne sont pas installées.

## Outil ajouté à l’étape 6

Le script `scripts/preflight-check.mjs`, invoqué par `npm run preflight`, réalise des contrôles de structure, de migration, de tables/RPC référencées et de protection des secrets sans dépendre des paquets applicatifs. Il est reproductible en local, mais ne remplace pas le build, le typecheck ou les tests réels.

## Blocage npm et dépendances

Le registre npm n’a pas été résolu (`EAI_AGAIN registry.npmjs.org`). Cet échec n’est pas une preuve que le code compile ou ne compile pas. `package-lock.json` est absent : générer ce fichier sur une machine disposant d’un accès au registre npm et le versionner pour figer les dépendances.

## Contrôles à mener avant production

1. Sur une machine connectée, exécuter `npm install`, puis `npm run preflight`, `npm run typecheck` et `npm run build` ; corriger toutes les erreurs.
2. Sur un projet Supabase de développement sauvegardé, exécuter les migrations 001 à 014 une par une et traiter le premier échec avant de continuer.
3. Vérifier les OTP et invitations e-mail, les URL autorisées, et les rôles `admin`, `modification` et `observateur` via l’interface, les routes serveur, les RPC et les politiques RLS.
4. Tester les modules élèves, inscriptions/transferts, frais, concessions, paiements/annulations, trésorerie, dépenses/transferts, achats/réceptions, patrimoine/maintenance et rapports avec des données de test connues.
5. Comparer les résultats financiers avec des requêtes SQL indépendantes, puis valider responsive, impression et export Excel.
6. Déployer d’abord en préproduction sur Vercel avec les variables secrètes configurées côté serveur. Passer en production uniquement après validation et sauvegarde.

Pour le compte administrateur, les variables d’environnement, l’installation et l’ordre des migrations, consulter `README.md`, `INSTALLATION_RAPIDE.txt` et `RAPPORT_ETAPE_6_PREDEPLOIEMENT.md`.

**Limite explicite :** ce rapport n’est ni une certification de compilation, ni une certification de sécurité ou de conformité comptable. Le projet reste candidat de préproduction tant que les tests réels ne sont pas réussis.

## Addendum — Étape 7 / version 1.9.2 (16 octobre 2026)

Une suite de 12 tests structurels hors ligne a été ajoutée dans `tests/release-readiness.test.mjs`, accessible via `npm run test:release`. Résultat obtenu dans l’environnement de préparation : 12 tests réussis, 0 échec. `npm run preflight` retourne 11 contrôles réussis, 1 avertissement relatif au `package-lock.json` absent, 0 échec. L’analyse syntaxique réalisée avec le compilateur TypeScript global porte sur 23 fichiers TS/TSX et ne relève aucune erreur de syntaxe.

Limites inchangées : la connexion au registre npm échoue avec `EAI_AGAIN registry.npmjs.org`, par conséquent les dépendances ne sont pas installées et `npm run typecheck`/`npm run build` ne sont pas validés. Les migrations n’ont pas été exécutées sur Supabase ; les tests RLS, les parcours fonctionnels et le déploiement Vercel restent à réaliser. La procédure complète se trouve dans `CHECKLIST_MISE_EN_SERVICE.md` et `RAPPORT_ETAPE_7_VALIDATION_FINALE.md`.


## Addendum — Étape 8 / version 1.9.3 (16 octobre 2026)

- Suppression des lignes fictives d'élèves, de coordonnées, d'achats, de dépenses, de paiements et de patrimoine dans le catalogue des modules.
- Tableaux scolaires vides en mode déconnecté ; créations désactivées en aperçu.
- Permissions en fermeture par défaut lorsqu'aucun rôle n'est connu ; navigation protégée masquée tant que le rôle n'a pas été vérifié.
- Ajout de quatre tests structurels pour prévenir la réintroduction des exemples fictifs et vérifier la lecture seule par défaut.
- Les tests hors ligne et le précontrôle ont été exécutés sur cette version. Le build, le typecheck complet, les migrations réelles et les tests de préproduction restent non validés, faute d'accès au registre npm et au projet Supabase.


## Addendum — Étape 9 / version 1.9.4 (16 octobre 2026)

- Barre supérieure rendue interactive : recherche rapide des modules accessibles, fermeture par clic extérieur et Échap, menu de compte tenant compte du rôle, déconnexion, et popover notifications avec état vide explicite.
- Nettoyage des artefacts générés : `tsconfig.tsbuildinfo` supprimé du paquet source.
- Documentation centrale réécrite pour aligner version, nombre de migrations, commandes de test et limites du build.
- Suite hors ligne portée à **19 tests réussis, 0 échec** ; `npm run preflight` exécuté avec 11 réussites, 1 avertissement relatif au lockfile, 0 échec. 24 fichiers TS/TSX ont passé l’analyse syntaxique, sans erreur.
- La compilation complète, les migrations sur Supabase, les tests RLS en environnement connecté et le déploiement Vercel restent non validés.
