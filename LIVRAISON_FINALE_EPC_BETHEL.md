# Livraison consolidée EPC BETHEL — étapes 1 à 9

**Version du projet :** 1.9.4  
**Date de préparation :** 16 octobre 2026  
**Base :** code cumulé dans `EPC_BETHEL_ETAPE_9_COHERENCE.zip`

Cette archive réunit le code de l’application, les évolutions des étapes 1 à 9, les migrations SQL 001 à 014, les tests hors ligne et les rapports/documentations des étapes.

## Contrôles répétés sur cette copie consolidée

- `node --test tests/release-readiness.test.mjs` : 19 tests réussis, 0 échec.
- `node scripts/preflight-check.mjs` : 11 réussites, 0 échec, 1 avertissement (`package-lock.json` absent).
- 14 migrations SQL présentes, dans une séquence continue.
- L’archive de livraison met `package.json` et le code directement à la racine, pour simplifier l’import du dépôt dans GitHub/Vercel.

## Limites

Le registre npm a renvoyé `EAI_AGAIN registry.npmjs.org` lors de la tentative de création du lockfile. Le `package-lock.json`, le typecheck complet, la compilation Next.js, l’exécution des migrations sur un projet Supabase et le déploiement Vercel n’ont donc pas été validés depuis cet environnement. Aucun secret de production n’est inclus dans le paquet.

Voir `DEPLOIEMENT_VERCEL.md` et `CHECKLIST_MISE_EN_SERVICE.md` avant toute mise en service réelle.
