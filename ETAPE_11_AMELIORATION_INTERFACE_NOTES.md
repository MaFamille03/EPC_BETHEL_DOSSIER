# EPC BETHEL — Étape 11 : organisation de l'interface Notes et bulletins

## Modifications

- Les filtres Année scolaire, Trimestre et Classe sont affichés sur une même ligne sur les écrans larges.
- Le titre et l'action Actualiser sont regroupés dans un en-tête plus compact.
- Les cinq onglets du module sont alignés dans une barre horizontale dédiée.
- Le titre, les filtres et la navigation restent visibles pendant le défilement vertical, sous la barre supérieure de l'application.
- Sur les écrans étroits, les filtres se réorganisent et la barre des onglets défile horizontalement pour éviter les chevauchements.
- Les modifications sont limitées au composant Notes et bulletins et à ses styles ; les règles métier et les migrations ne sont pas modifiées.

## Contrôles effectués

- `node --test tests/release-readiness.test.mjs` : 23 tests réussis, 0 échec.
- `node scripts/preflight-check.mjs` : 11 contrôles réussis, 0 échec, 1 avertissement (package-lock.json absent).
- Le build Next.js et le typecheck complet n'ont pas été exécutés dans cet environnement car les dépendances ne sont pas installées.

## Déploiement

Aucune migration SQL supplémentaire n'est nécessaire pour cette modification de présentation. Après extraction, installer les dépendances sur une machine connectée puis exécuter `npm run typecheck` et `npm run build` avant le déploiement.
