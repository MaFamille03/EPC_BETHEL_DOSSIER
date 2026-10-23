# EPC BETHEL V1.19.0 — Formulaires en fenêtres superposées

## Objectif
Uniformiser la saisie dans Gestion des élèves, Finance scolaire et Notes et bulletins : la page de travail reste visible en arrière-plan ; le formulaire s’ouvre au-dessus, comme un UserForm Excel.

## Modifications
- Gestion des élèves : la création et la modification des dossiers utilisent la fenêtre large existante, avec en-tête et pied d’action persistants.
- Finance scolaire : le formulaire de création des frais et de leur échéancier utilise une fenêtre large avec grille responsive et zone des champs défilante.
- Notes et bulletins : création d’évaluation, saisie collective des notes, modification des règles de calcul et ajout de matière ouvrent désormais des fenêtres superposées.
- Les boutons Annuler/Fermer ou le clic sur l’arrière-plan ferment la fenêtre ; Échap ferme les fenêtres du module Notes et bulletins. Les opérations réussies ferment la fenêtre après enregistrement, tandis qu’une erreur laisse le formulaire ouvert pour correction.
- Les tables restent dans la page, à l’exception du tableau de saisie collective des notes qui est inclus dans sa fenêtre. La liste des évaluations, le résumé des règles et le référentiel des matières restent visibles derrière les fenêtres.
- Les règles de sécurité, validations, opérations Supabase et données ne changent pas. Aucune migration SQL n’est ajoutée.

## Vérifications hors ligne
- `npm run test:release` : 38 tests réussis sur 38.
- `npm run preflight` : 11 réussis, 1 avertissement (absence de `package-lock.json`), 0 échec.
- Analyse syntaxique TypeScript/TSX isolée : 29 fichiers, 0 erreur de syntaxe.

## Limites
Le typecheck complet et le build Next.js n’ont pas été validés dans cet environnement car les dépendances du projet ne sont pas installées. Les parcours doivent être testés dans le navigateur et avec une base Supabase de préproduction avant mise en production.
