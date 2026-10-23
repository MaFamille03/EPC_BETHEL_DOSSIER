# EPC BETHEL — Étape 10 : Notes et bulletins du primaire

## Fonctionnalités développées

La suite de pré-livraison comporte 23 tests structurels hors ligne. Ces tests ne remplacent pas la compilation complète ni les essais sur Supabase.

- Vue d'ensemble par année scolaire, trimestre et classe.
- Création d'évaluations par classe, matière, période, type, date, barème et coefficient.
- Saisie collective des notes pour tous les élèves inscrits dans la classe de l'évaluation.
- Statuts distincts : note saisie, absence justifiée, absence non justifiée, dispensé et note manquante.
- Vérification du barème avant enregistrement.
- Résultats individuels par matière, moyenne simple, pondérée par coefficient ou par catégorie.
- Paramétrage des règles par année scolaire et classe.
- Préparation des bulletins en brouillon, publication autorisée à l'administration et conservation des versions remplacées.
- Aperçu du bulletin publié et impression du navigateur vers PDF.
- Export CSV du relevé individuel.
- Journalisation des créations et corrections de notes par un déclencheur de base de données.
- RLS Supabase pour protéger évaluations, règles, notes et bulletins.

## Migration à appliquer

Appliquer `supabase/migrations/018_notes_bulletins_workflows.sql` après les migrations 001 à 017, sur le projet Supabase de destination. Faire d'abord une sauvegarde et tester dans un environnement de préproduction.

La migration crée les tables `school_assessments`, `school_grade_rules` et `school_bulletins`, puis complète `student_grades`. Elle ne supprime pas les anciennes notes. Les notes historiques restent présentes et continuent à alimenter les moyennes individuelles, mais elles ne sont pas associées automatiquement à une nouvelle évaluation.

## Calcul des moyennes

- `simple` : moyenne arithmétique des notes normalisées sur l'échelle du bulletin.
- `coefficients` : moyenne pondérée des notes normalisées avec le coefficient de chaque évaluation.
- `categories` : moyennes pondérées des compositions et des examens selon les pourcentages configurés. Si une catégorie n'a aucune note, les poids disponibles sont renormalisés. Les autres évaluations disposent de leur propre pondération configurable.
- La moyenne générale du bulletin est la moyenne des moyennes des matières disposant d'au moins une note exploitable. Aucun coefficient de matière n'est inventé.
- Les notes manquantes et les absences ne sont pas automatiquement converties en zéro.

## Déploiement manuel

1. Sauvegarder la base Supabase.
2. Appliquer les migrations existantes dans l'ordre, puis la migration 018.
3. Installer les dépendances avec `npm install` sur une machine disposant d'un accès au registre npm.
4. Renseigner les variables Supabase dans `.env.local` à partir de `.env.example`.
5. Lancer `npm run typecheck`, `npm run test:release` et `npm run build`.
6. Dans l'application, créer les matières nécessaires dans Configuration, vérifier les classes et inscriptions, puis définir les règles de calcul avec l'administration.
7. Tester avec des élèves fictifs : création d'évaluation, notes, absences, barèmes différents, calcul des moyennes, brouillon, publication, remplacement et impression PDF.
8. Ne publier qu'après validation des résultats par la direction.

## Limites à connaître

- Les enseignants ne disposent pas encore d'un système d'affectation enseignant-classe/matière dans cet écran ; les autorisations sont celles des rôles existants de l'application et de Supabase.
- Le modèle de bulletin proposé est imprimable depuis le navigateur, mais il doit être approuvé par l'établissement avant de devenir le modèle officiel.
- La publication et l'archivage sont exécutés par plusieurs requêtes client ; pour une garantie transactionnelle renforcée, prévoir une fonction RPC PostgreSQL dédiée avant une utilisation à grande échelle.
- Aucun test n'a été exécuté sur la base Supabase réelle de l'établissement dans cet environnement.


## Validation réalisée pendant la préparation du ZIP

- `node --test tests/release-readiness.test.mjs` : 23 réussis, 0 échec.
- `node scripts/preflight-check.mjs` : 11 réussis, 0 échec, 1 avertissement (absence de `package-lock.json`).
- Analyse syntaxique TypeScript/TSX : 31 fichiers, 0 erreur de syntaxe.
- `npm install` a expiré dans l'environnement de préparation ; les dépendances ne sont pas installées. Par conséquent, le typecheck complet et le build Next.js ne sont pas certifiés ici.
- La migration 018 n'a pas été exécutée sur une base Supabase réelle ; son application et les tests fonctionnels restent à faire sur une base de préproduction avant production.
