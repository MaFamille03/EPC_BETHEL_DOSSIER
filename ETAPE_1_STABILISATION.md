# EPC BETHEL — Étape 1 : stabilisation technique

**Date des contrôles :** 16 octobre 2026  
**Version déclarée après corrections :** 1.6.1  
**Portée :** contrôles statiques et corrections sûres du socle ; aucune connexion à un projet Supabase réel.

## Corrections appliquées

1. Alignement de `package.json` sur la livraison V1.6 et incrément de version en `1.6.1`.
2. Ajout du prérequis Node.js `>=20.9.0` dans `package.json`.
3. Renforcement de `.gitignore` : les fichiers `.env*` sont ignorés, à l’exception de `.env.example`, afin de réduire le risque d’ajouter des secrets à Git.
4. Dans la migration `008_achats_patrimoine_workflows.sql`, remplacement du `search_path = public` par `search_path = ''` pour les cinq fonctions `SECURITY DEFINER`. Les objets applicatifs et fonctions liés sont référencés explicitement par schéma dans les corps de ces fonctions.
5. Ajout du présent compte rendu et mise à jour du journal des versions.

## Résultats des vérifications

| Contrôle | Résultat | Détail |
|---|---|---|
| Intégrité ZIP de la livraison de départ | Réussi | Archive ouverte et entrée ZIP corrompue non détectée. |
| Structure du projet | Réussi | Routes App Router, composants, bibliothèque, configuration et neuf migrations présentes. |
| Analyse syntaxique TS/TSX | Réussi | 18 fichiers source analysés par le parseur TypeScript fourni dans l’environnement ; aucune erreur de parsing. |
| Compilation/typecheck complet | Non validé | Les dépendances Next.js, React, Supabase et types Node ne sont pas installées. `tsc --noEmit` retourne donc des erreurs de modules/types introuvables, qui ne permettent pas de juger le résultat du code dans un environnement installé. |
| Installation npm | Bloquée dans cet environnement | `npm install --no-audit --no-fund` a expiré. Aucun `package-lock.json` n’a été fabriqué artificiellement. |
| Ordre des migrations | Réussi en statique | Les migrations `001` à `009` sont présentes et numérotées dans l’ordre. |
| Délimiteurs dollar SQL | Réussi en statique | Chaque fichier SQL a un nombre pair de délimiteurs `$$`. Ce contrôle ne prouve pas que les scripts sont exécutables. |
| Validation PostgreSQL/Supabase | Non effectuée | Aucun serveur PostgreSQL, CLI Supabase ou projet de test connecté dans cet environnement. |
| Build Next.js / tests navigateur | Non effectués | Dépendent de l’installation des dépendances et de la configuration Supabase. |

## À faire avant déploiement

- Installer les dépendances dans un environnement avec accès à npm, puis générer et versionner le fichier de verrouillage (`package-lock.json`).
- Exécuter `npm run typecheck` et `npm run build` et corriger tout diagnostic réel.
- Appliquer les neuf migrations dans l’ordre sur une base Supabase de développement vierge, en arrêtant au premier échec.
- Tester RLS, rôles, fonctions `SECURITY DEFINER`, encaissements, annulations, transferts, dépenses et achats à l’aide de comptes et données fictifs.
- Continuer l’étape 2 séparément pour le compte administrateur principal, l’inscription sécurisée et la gestion des permissions demandées.

## Conclusion

La livraison a reçu des corrections ciblées de configuration et de durcissement SQL. Elle n’est **pas certifiée compilable ni prête pour la production** tant que l’installation, le build, les migrations et les tests sur Supabase n’ont pas été exécutés avec succès.
