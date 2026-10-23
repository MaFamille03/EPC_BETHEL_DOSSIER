# Rapport de livraison — EPC BETHEL V1.18.0

## Changements inclus

- Interface de caisse nommée « Caisse et Mobile Money » pour rappeler que l’établissement conserve un registre de caisse unique et que Banque est une rubrique distincte.
- Moyens de règlement de caisse : espèces, Orange Money, Wave et Moov Money. Les opérateurs sont des canaux de paiement et non des comptes à ouvrir. Les soldes des opérateurs restent visibles séparément pour le contrôle.
- Les indicateurs de caisse présentent le solde théorique en espèces, le dernier comptage physique réel, l’écart constaté et les soldes Mobile Money.
- Les actions « Compter la caisse » et « Ajouter une ligne de caisse » sont regroupées dans le panneau de synthèse.
- Le tableau des mouvements respecte l’ordre : Référence, Date, Libellé, Moyen de paiement, Entrée, Sortie, Solde, Statut, Actions.
- Les lignes manuelles de type ajustement peuvent être modifiées/supprimées avec un motif. Les opérations liées à un reçu, une dépense, un transfert, une contrepassation ou un rapprochement restent protégées et doivent être corrigées dans leur module d’origine.
- Migration 023 : sécurise les modifications/suppressions de mouvements manuels et vérifie que l’opération porte sur la caisse principale.

## Contrôles réalisés

- `npm run test:release` : 35 tests réussis, aucun échec.
- `npm run preflight` : 11 contrôles réussis, aucun échec, 1 avertissement (absence de `package-lock.json`).
- Analyse syntaxique isolée TypeScript/TSX : 29 fichiers analysés, aucune erreur de syntaxe.
- Cohérence des 23 migrations : numérotation sans trou et délimiteurs dollar vérifiés en statique.
- Archive ZIP vérifiée après empaquetage.

## Contrôles encore requis avant production

La compilation complète Next.js, le typecheck avec les dépendances installées, l’exécution des migrations et les parcours fonctionnels sur une base Supabase de préproduction n’ont pas été réalisés ici. Sauvegarder la base, confirmer l’application des migrations 001 à 022, puis exécuter la migration 023 une seule fois en préproduction avant la production. Tester les entrées/sorties par canal, le comptage physique, les soldes, les modifications et suppressions autorisées/refusées.
