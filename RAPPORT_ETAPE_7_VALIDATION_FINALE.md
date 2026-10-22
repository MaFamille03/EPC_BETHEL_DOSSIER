# EPC BETHEL — Étape 7 : revue finale de livraison

**Version :** 1.9.2  
**Statut :** candidat de préproduction. L’application n’est pas certifiée pour la production.

## Résumé

La revue finale ajoute une suite de tests structurels reproductibles sans dépendances applicatives ni connexion Internet, actualise la documentation et regroupe les conditions de mise en service. Aucun accès au compte Supabase ou Vercel de l’établissement n’était disponible ; aucun déploiement ni test sur données réelles n’a été effectué.

## Contrôles exécutés

| Contrôle | Résultat | Interprétation |
|---|---|---|
| `node --test tests/release-readiness.test.mjs` | 12 réussis, 0 échec | Cohérence statique des fichiers et invariants de sécurité testés. |
| `npm run preflight` | 11 réussis, 1 avertissement, 0 échec | Arborescence, références internes, tables/RPC, migrations, secrets. |
| Analyse syntaxique TypeScript/TSX | 23 fichiers, 0 erreur syntaxique | Contrôle de syntaxe uniquement. |
| Archive ZIP | À vérifier après création du ZIP final | L’intégrité ZIP sera contrôlée avant livraison. |
| `npm run typecheck` | Non validé | Dépendances absentes ; l’appel global a signalé notamment des modules/t types introuvables. |
| `npm run build` | Non validé | Next.js et les dépendances ne sont pas installés. |
| Migrations Supabase | Non exécutées | Un projet de développement et une sauvegarde sont nécessaires. |
| Tests end-to-end / Vercel | Non exécutés | Connexion projet et secrets de déploiement indisponibles. |

## Suite de tests hors ligne ajoutée

Le fichier `tests/release-readiness.test.mjs` contient 12 vérifications : scripts du paquet, présence et continuité des 14 migrations, routes API, contrôle du code d'inscription, cohérence de l'adresse de l'administrateur, OTP, restrictions du rôle admin, distinction observateur/modification, absence de référence à la clé service dans les composants clients, absence de secrets réels dans les exemples, fonctions financières/rapports et avertissements de sécurité dans la documentation.

Commande :

```bash
npm run test:release
```

Ces tests sont volontairement structurels : ils ne lancent ni Next.js ni PostgreSQL. Un test réussi ne prouve pas que le code SQL compile ou que les politiques RLS sont correctement actives sur la base réelle.

## Blocage d’installation

La commande d’accès au registre npm a échoué avec `EAI_AGAIN registry.npmjs.org`. Aucun `package-lock.json` n’a été généré, et aucun verrouillage manuel des dépendances n’a été simulé. Cette limite doit être résolue dans un environnement connecté avant le contrôle complet `npm install`, `npm run typecheck` et `npm run build`.

## Actions obligatoires avant production

1. Générer et conserver `package-lock.json` avec le registre npm accessible.
2. Installer les dépendances et faire passer `npm run test:release`, `npm run preflight`, `npm run typecheck` et `npm run build`.
3. Sauvegarder le projet de données, puis exécuter les migrations 001–014 une à une sur Supabase de développement.
4. Tester connexion OTP, confirmation invitation, inscription par code, rôle admin, observateur et modification, ainsi que les politiques RLS directement.
5. Tester les parcours élèves, frais, échéances, concessions, encaissements, annulations/contrepassations, transferts, dépenses, achats, réception, inventaire, maintenance et rapports.
6. Déployer sur un environnement Preview Vercel, vérifier logs et usages mobiles, puis seulement décider de la production.
7. Conserver les résultats des tests et un plan de retour arrière avant de migrer la base de production.

La liste complète et les cases à cocher sont dans `CHECKLIST_MISE_EN_SERVICE.md`.
