# Rapport de modification — EPC BETHEL V1.16.1

## Modification livrée

Dans Gestion des élèves, le contrôle de l’élément natif `<details>` affichait auparavant un symbole plus/moins généré par CSS. Il affiche maintenant un libellé explicite : **Déplier** lorsque le panneau est fermé et **Réplier** lorsque le panneau est ouvert. Le libellé suit l’état réel du panneau et reste accessible au clavier via le résumé natif.

Le téléchargement du modèle Excel, l’analyse du fichier, l’aperçu, la validation des matricules, l’importation et le rapport CSV sont conservés.

## Compatibilité

Aucune migration SQL n’est nécessaire. Les modules de trésorerie V1.16.0 sont conservés. Le numéro de version de l’application est incrémenté à 1.16.1.

## Contrôles

Les contrôles exécutés sont listés dans le compte rendu de livraison et dans la sortie des tests `npm run test:release` et `npm run preflight`. Le build Next.js complet peut nécessiter l’installation des dépendances si l’environnement de vérification ne les possède pas.
