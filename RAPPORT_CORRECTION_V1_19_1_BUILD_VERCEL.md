# Rapport de correction — EPC BETHEL V1.19.1

## Erreur signalée

Le build Vercel échouait dans `components/class-fee-tariffs-manager.tsx` à la ligne de sauvegarde des catégories de frais. Le même objet `payload` était inféré comme une union entre le corps d’une mise à jour (nom, statut actif) et celui d’une création (code, nom, type et statut actif). TypeScript refusait de passer cette union à `insert()` à cause des propriétés supplémentaires incompatibles.

## Correction appliquée

Le traitement est maintenant séparé selon le cas :

- Mise à jour : envoie uniquement `name` et `is_active`.
- Création : envoie `code`, `name`, `kind` et `is_active`.

La correction est localisée et ne change pas les règles métier, les tables SQL, ni les fonctionnalités des catégories de frais. La version du projet passe à `1.19.1`.

## Vérifications disponibles

- `node scripts/preflight-check.mjs` : 11 contrôles réussis, 0 échec, 1 avertissement lié à l’absence de `package-lock.json`.
- `node --test tests/release-readiness.test.mjs` : 41 tests réussis sur 41, dont un test ciblé qui vérifie que les corps de création et de mise à jour restent séparés.
- L’installation des dépendances avec `npm install --ignore-scripts --no-audit --no-fund` a expiré dans l’environnement. Le `typecheck` et le build complet Next.js n’ont donc pas pu être relancés ici.

## Étape après récupération du ZIP

Décompresser le projet corrigé, remplacer le contenu de la branche `main` par cette version puis relancer le déploiement Vercel. Ce ZIP contient le correctif ; il ne modifie pas automatiquement le dépôt GitHub existant.
