# EPC BETHEL — Étape 3 : gestion scolaire

## Fonctionnalités ajoutées

- Modification des dossiers élèves dans la page Élèves, y compris matricule, identité, sexe, naissance, notes et responsable légal principal. Les champs du responsable incluent le lien avec l’élève, le téléphone, l’e-mail, la profession et l’adresse. Un matricule peut être généré automatiquement lors de la création si le champ reste vide.
- Création d’inscriptions et de réinscriptions via la fonction SQL `create_school_enrollment`. Le parcours de création ne propose plus « Transfert » comme type d’inscription ; le transfert possède ses propres actions afin d’éviter de créer une deuxième inscription pour la même année scolaire.
- Changement de classe pour une inscription active de l’année courante : l’inscription existante est mise à jour, le motif est ajouté aux notes et l’opération est journalisée.
- Sortie définitive ou transfert hors établissement : la fonction clôture l’inscription courante, note la date et le motif, et met à jour le statut de l’élève si aucune autre inscription active dans l’année scolaire courante ne subsiste.
- Paramètres de l’établissement : ajout d’une liste des années scolaires historiques, création d’une nouvelle année, modification des dates et choix de l’année active.
- Paramètres de l’établissement : gestion des classes et niveaux. Les classes existantes ne sont pas supprimées ; elles peuvent être désactivées pour interdire de nouvelles affectations tout en conservant l’historique.
- Fonctions SQL à accès contrôlé et opérations journalisées dans `audit_logs`. Les droits restent soumis aux rôles et politiques déjà installés par les migrations 010 et 011.

## Nouvelle migration

`supabase/migrations/012_school_management_completion.sql`

Cette migration remplace la signature de la fonction de création des élèves pour enregistrer les coordonnées étendues du responsable légal, ajoute une fonction de mise à jour du dossier, une fonction d’inscription/réinscription, les fonctions de transfert/sortie et une fonction de gestion des classes.

Appliquer cette migration **après 001 à 011**, sur une base de développement ou après une sauvegarde de la base réelle. La migration doit être appliquée une seule fois dans l’ordre des migrations du projet.

## Vérifications effectuées

- Analyse syntaxique TypeScript/TSX au moyen du transpileur TypeScript : 23 fichiers analysés, aucune erreur de syntaxe détectée.
- Imports internes : les nouveaux composants utilisent des chemins déjà présents dans le projet (`lib/supabase`, `components/access-context`).
- Vérification visuelle du code des parcours et des noms de fonctions RPC par rapprochement du front-end et de la migration 012.
- Les 15 classes initiales de la migration 001 sont conservées.
- La version du paquet est alignée sur la livraison `1.7.0`.

## Limites restantes

- Les dépendances npm n’ont pas pu être installées dans cet environnement ; le `typecheck` complet et `next build` n’ont donc pas pu être validés. Les messages actuels de `tsc` sont dominés par les modules `react`, `next` et `lucide-react` manquants.
- La migration 012 n’a pas été exécutée sur une instance PostgreSQL/Supabase réelle. Les fonctions SQL doivent être testées sur une base de développement avec les rôles `admin`, `modification` et `observateur`.
- Les e-mails/OTP de l’étape 2 exigent toujours les réglages décrits dans `ETAPE_2_SECURITE.md`.
- La fonctionnalité Excel existante a été conservée. Son import repose encore sur l’upsert direct de dossiers et n’écrit pas chaque import dans un journal métier détaillé ; ce point pourra être renforcé lors d’un contrôle de l’import.

## Scénarios de test à exécuter après application de la migration

1. Créer un élève en laissant le matricule vide, puis confirmer qu’un matricule unique est généré.
2. Modifier un dossier et son responsable ; vérifier que les données et le journal d’audit sont mis à jour.
3. Inscrire un élève actif dans une année ouverte, puis confirmer que la tentative d’inscription en double est refusée.
4. Changer sa classe ; vérifier que l’inscription existante est modifiée sans créer de doublon et que l’audit conserve l’origine et la destination.
5. Clôturer l’inscription par sortie ou transfert externe ; vérifier la mise à jour des statuts.
6. Créer/modifier une classe et préparer une année scolaire ; activer l’année voulue et vérifier la navigation et les nouvelles inscriptions.
7. Répéter les opérations avec un compte Observateur et confirmer le refus d’écriture côté Supabase.
