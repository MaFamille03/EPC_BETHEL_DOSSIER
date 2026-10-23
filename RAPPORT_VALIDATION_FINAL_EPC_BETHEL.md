# Rapport de validation — EPC BETHEL 1.10.5

## Modifications de cette livraison

- Corrigé les tests de pré-livraison qui contrôlaient des attentes obsolètes (création d’utilisateur dans la route de validation, variable d’environnement historique et version documentaire).
- Harmonisé la version documentaire sur 1.10.5.
- Ajouté `016_notes_bulletins.sql` : matières, notes par inscription/période/évaluation, contraintes de note et coefficient, politiques RLS.
- Ajouté `components/notes-bulletins-page.tsx` : saisie des notes, calcul de moyennes pondérées et export CSV de relevé.
- Ajouté `017_bank_reconciliation_workflow.sql` : fonction transactionnelle de rapprochement qui vérifie rôle, compte, statut validé, sens et montant, empêche le double rapprochement et écrit une trace d’audit.
- Ajouté `components/bank-reconciliation-page.tsx` : import de relevé CSV, suivi des imports et rapprochement avec des mouvements existants sans créer de mouvements de trésorerie.
- Mis à jour les guides d’installation.

## Résultats exécutés dans cet environnement

| Contrôle | Résultat |
|---|---|
| `node --test tests/release-readiness.test.mjs` | **19 réussis, 0 échec** |
| `npm run preflight` | **11 réussis, 0 échec, 1 avertissement** |
| Séquence de migrations | **001 à 017 sans trou** |
| Vérification des RPC référencées | **32 RPC présentes dans les migrations** |
| Vérification des tables référencées | **28 tables présentes dans les migrations** |
| TypeScript | **Non validé** : dépendances npm non installées |
| Build Next.js | **Non exécuté** : commande `next` indisponible sans dépendances |
| Tests PostgreSQL/Supabase | **Non exécutés** : aucune base de préproduction connectée |

## Limites et étapes obligatoires avant production

L’installation des dépendances (`npm install`) a expiré dans l’environnement faute de disponibilité du registre npm. Les commandes `tsc --noEmit` et `next build` ont donc échoué à résoudre les modules manquants ; cela ne permet pas de conclure à une erreur de code, mais la compilation reste à effectuer sur une machine connectée.

Les migrations 016 et 017 sont livrées mais ne sont pas appliquées à une base. Avant production :

1. Sauvegarder la base puis appliquer les migrations 016 et 017 sur une base de préproduction.
2. Installer les dépendances et lancer `npm run typecheck`, `npm run build`, `npm run test:release` et `npm run preflight`.
3. Créer les matières scolaires dans `school_subjects`, puis tester la saisie et les moyennes avec des inscriptions fictives de test.
4. Importer un relevé bancaire de test et vérifier rapprochement exact, mauvais montant, mauvais sens, compte différent, ligne déjà rapprochée et mouvement déjà rapproché.
5. Tester le paiement scolaire et le transfert interne avec des comptes de test, puis confirmer qu’aucun doublon n’est créé et que le transfert ne modifie pas la trésorerie globale.
6. Vérifier les permissions de chaque rôle et la conservation de l’audit.

Aucune donnée réelle n’a été créée ni modifiée par cette livraison. Le projet n’est pas certifié prêt pour la production tant que ces vérifications d’intégration ne sont pas passées.
