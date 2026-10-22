# EPC BETHEL — Correction de navigation Trésorerie V1.10.7

## Problème constaté
La version 1.10.6 présentait les cinq rubriques comme des onglets internes à la page Trésorerie, mais le menu latéral conservait l'ancienne entrée unique « Trésorerie ». Le changement demandé n'était donc pas visible dans la navigation de gauche.

## Correction apportée
- Le menu latéral affiche désormais, sous « Trésorerie », les cinq accès :
  A. Situation globale ;
  B. Caisse et Mobile Money ;
  C. Banque ;
  D. Transferts internes ;
  E. Journal de trésorerie.
- Chaque accès ouvre directement la rubrique correspondante au moyen d'un fragment d'URL.
- Les cinq onglets internes restent synchronisés avec les liens latéraux.
- Les autres modules de l'application et les droits de rôle existants sont conservés.
- Aucune migration Supabase supplémentaire n'est nécessaire pour cette correction d'interface.

## Contrôles exécutés
- `node --test tests/release-readiness.test.mjs` : 19 tests réussis, 0 échec.
- `node scripts/preflight-check.mjs` : 11 contrôles réussis, 0 échec, 1 avertissement (absence de `package-lock.json`).
- Le build Next.js et le contrôle TypeScript complet ne sont pas déclarés réussis : ils n'ont pas été exécutés dans cet environnement.

## Déploiement
Importer cette version dans le dépôt GitHub relié à Vercel, puis lancer un nouveau déploiement. Après déploiement, ouvrir « Trésorerie » dans le menu de gauche ; les cinq sous-rubriques doivent apparaître. Si l'ancien écran reste affiché, effectuer un rechargement forcé du navigateur.
