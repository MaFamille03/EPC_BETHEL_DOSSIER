# EPC BETHEL — Gestion des élèves (V1.12.0)

## Modifications

- Ajout de filtres visibles pour le statut du dossier (Actif, Transféré, Sorti, Archivé) et la classe actuelle.
- Ajout d'une pagination de la liste des élèves, avec choix de 10, 25 ou 50 dossiers par page.
- La recherche, le changement de filtre et le changement de taille de page ramènent la liste à la première page.
- Affichage du nombre de résultats correspondant à la recherche et aux filtres, et de la plage actuellement affichée.
- Ajustements responsive des filtres pour les écrans étroits.
- Conservation des RPC et du schéma Supabase existants : aucun changement SQL ni suppression de données.

## Contrôles effectués

- Archive source ouverte et intégrité ZIP contrôlée.
- Analyse syntaxique isolée de `components/module-page.tsx` via TypeScript : 0 diagnostic de syntaxe.
- Build Next.js, typecheck complet et tests sur Supabase non exécutés dans cet environnement.

## Limite connue

La liste utilise toujours les chargements existants de l'application (jusqu'à 1 000 dossiers élèves). La pagination ajoutée organise les résultats chargés côté interface ; elle ne remplace pas encore une pagination/recherche côté serveur pour les établissements dépassant ce volume.
