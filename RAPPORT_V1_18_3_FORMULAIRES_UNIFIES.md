# EPC BETHEL — Rapport V1.18.3

## Objectif
Harmoniser le comportement des formulaires ouverts depuis les commandes de l’application pour qu’ils se présentent au-dessus de la page active, comme le formulaire « Nouvel élève », sans déplacer ni remplacer cette page.

## Modifications
- Création du composant réutilisable `components/modal-portal.tsx`. Les fenêtres concernées sont rendues directement sous `document.body`, et le défilement de la page d’arrière-plan est neutralisé pendant l’ouverture.
- Mise en portail des fenêtres de création/modification des classes et années scolaires, des dépenses, des achats, du patrimoine, des mouvements de caisse, du comptage physique, des transferts internes et des comptes bancaires.
- Conversion de l’import Excel des élèves en fenêtre superposée avec aperçu, erreurs et commandes d’import conservées.
- Conversion du formulaire d’invitation d’un utilisateur en fenêtre superposée.
- Conversion des formulaires de coordonnées de l’établissement et de code d’accès administrateur en fenêtres superposées ; la page Paramètres conserve un aperçu des coordonnées et le statut du code.
- Conversion du parcours d’importation et de rapprochement bancaire en fenêtre superposée ; le tableau des relevés demeure dans la page d’origine.
- Conservation des fenêtres déjà superposées de Gestion des élèves, Finance scolaire, Encaissements et Notes et bulletins.
- Ajout d’une mise en page adaptée aux écrans mobiles et aux formulaires longs.

## Vérifications effectuées
- `node --test tests/release-readiness.test.mjs` : 37 tests réussis sur 37.
- `node scripts/preflight-check.mjs` : 11 contrôles réussis, aucun échec et un avertissement parce que `package-lock.json` est absent.
- Le dossier livré ne contient pas de dépendances npm installées ; le typecheck complet et le build Next.js n’ont donc pas encore été exécutés dans cet environnement. Il faudra installer les dépendances puis lancer `npm run typecheck` et `npm run build` avant le déploiement.

## Compatibilité
Aucune migration Supabase n’est ajoutée. Les actions métier et les règles d’accès existantes sont conservées.
