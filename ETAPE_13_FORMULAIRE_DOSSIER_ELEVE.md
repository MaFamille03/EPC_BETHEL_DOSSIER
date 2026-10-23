# EPC BETHEL — V1.13.1 : fenêtre du formulaire élève

## Modification

Le formulaire de création et de modification d’un élève conserve le mode fenêtre superposée et occupe désormais plus de largeur. Sur grand écran, les champs sont organisés en trois colonnes pour favoriser la saisie de gauche à droite et limiter le défilement vertical. Sur écran intermédiaire, deux colonnes sont utilisées ; sur mobile, le formulaire revient à une seule colonne.

L’en-tête et les boutons d’action restent fixes dans la fenêtre. Seule la zone des champs défile si nécessaire. Le champ des notes administratives dispose de toute la largeur. Les sections Identité, Responsable légal et Informations administratives sont conservées.

## Périmètre et validation

Aucun changement des champs métier, RPC, politiques RLS ou migrations SQL n’a été effectué. L’analyse syntaxique du composant modifié ne signale aucune erreur. Les 23 tests hors ligne et les 11 contrôles structurels passent (un avertissement signale l’absence de package-lock.json). La compilation complète, le typecheck complet et les tests sur un projet Supabase de préproduction doivent encore être réalisés.
