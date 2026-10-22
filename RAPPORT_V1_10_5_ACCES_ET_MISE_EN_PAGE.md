# EPC BETHEL — Version 1.10.5

## Corrections
- Le message de connexion distingue désormais un profil absent, un compte désactivé par l’administration et une erreur de lecture du profil.
- Le formulaire « Inviter un utilisateur » utilise une grille responsive, des champs extensibles et un bouton qui passe sur sa propre ligne.
- Les titres, notices, champs et tableaux autorisent le retour à la ligne et limitent les débordements horizontaux.
- Le texte d’aide sur les secrets Supabase est clarifié et n’affiche plus les noms de variables comme une instruction à l’utilisateur final.

## Vérifications et limites
- Archive source V1.10.4 extraite puis modifiée.
- À effectuer avant production : `npm install`, `npm run typecheck`, `npm run build`, puis tests de connexion avec un compte actif, désactivé et sans profil, et contrôle responsive des pages.
- Les changements de CSS réduisent les risques de chevauchement, mais aucun audit visuel exhaustif automatisé de chaque page n’est déclaré réussi.
