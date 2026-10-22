# EPC BETHEL — Étape 8 : mode aperçu sans données fictives et fermeture par défaut

**Version :** 1.9.3  
**Statut :** correction locale contrôlée ; compilation complète et validation de production toujours requises.

## Constat traité

Lorsqu'aucune connexion Supabase n'était configurée, le catalogue des modules et la page scolaire pouvaient afficher des exemples fictifs (noms d'élèves, coordonnées, paiements et biens). Une bannière annonçait le mode aperçu, mais ces lignes restaient visuellement semblables à de vraies données.

## Modifications

- Suppression des exemples de dossiers et de mouvements de `lib/modules.ts` ; le catalogue ne contient plus de jeux de données de démonstration.
- Les tableaux génériques et le registre de frais commencent avec un tableau vide ; en mode déconnecté, les listes et compteurs restent vides.
- Les boutons de création des rubriques scolaires sont masqués tant que Supabase n'est pas configuré.
- Le mode aperçu indique désormais qu'aucune donnée réelle n'est chargée et que les modifications sont désactivées.
- Le contexte d'autorisations échoue par défaut en lecture seule quand aucun rôle n'est établi.
- En environnement Supabase configuré, l'absence de rôle n'affiche plus les menus protégés ; une erreur de vérification renvoie vers la connexion.
- Le contrôle de version passe à `1.9.3`.
- Quatre tests hors ligne ont été ajoutés pour prévenir le retour des données fictives et vérifier la fermeture par défaut.

## Contrôles

- `npm run test:release` : 16 tests structurels hors ligne réussis, 0 échec.
- `npm run preflight` : vérification statique de la structure, des imports, migrations et références SQL.
- Analyse de syntaxe TypeScript/TSX par le compilateur TypeScript global, sans installation des dépendances applicatives.
- Intégrité de l'archive finale confirmée par `unzip -t` après création du paquet.

## Limites

Le registre npm renvoie `EAI_AGAIN registry.npmjs.org` depuis l'environnement de préparation. Aucun `package-lock.json` n'a donc été simulé. `npm run typecheck`, `npm run build`, l'exécution des migrations sur une base PostgreSQL/Supabase et les essais end-to-end demeurent à exécuter depuis un environnement connecté au projet de développement. Cette étape n'est pas une mise en production.
