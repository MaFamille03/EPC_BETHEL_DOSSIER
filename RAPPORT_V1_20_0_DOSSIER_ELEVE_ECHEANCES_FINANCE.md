# EPC BETHEL V1.20.0 — Dossier élève, échéances annuelles et synthèse financière

## Portée

Cette version applique les demandes portant sur le formulaire de création d'un élève, le paramétrage des tarifs et des échéances annuelles, et la synthèse de Finance scolaire. Le module **Notes et bulletins n'a pas été modifié** dans cette livraison, conformément à la demande de poursuivre ce point plus tard.

## 1. Dossier complet du nouvel élève

Le formulaire place désormais la classe/niveau, l'année scolaire et le statut d'inscription immédiatement après les champs d'identité. La classe et l'année scolaire sont obligatoires lors de la création; l'année proposée est l'année en cours et non clôturée. Le responsable légal et son téléphone sont obligatoires. La validation est contrôlée côté interface et côté base via la migration 025.

Le changement de classe d'un dossier déjà créé se fait par le parcours Inscriptions afin de conserver l'historique des affectations scolaires annuelles. La fiche en modification ne présente plus l'avis réservé à la création.

## 2. Paramètres : tarifs et échéances annuelles fixes

Un calendrier de six dates distinctes, classées strictement par ordre chronologique, est configuré pour chaque année scolaire dans Paramètres. Les dates s'appliquent aux catégories de frais et aux classes pour cette année; un retard de paiement ne les décale pas. Les dates d'un calendrier configuré sont affichées en lecture seule. Une correction exceptionnelle est réservée aux rôles autorisés, exige une confirmation explicite et s'applique seulement aux nouvelles attributions : elle ne réécrit pas les frais, échéanciers ou paiements déjà enregistrés.

Les tarifs restent configurés par classe, année et catégorie de frais. Le parcours de création manuelle d'un frais dans Finance scolaire ne demande plus à l'utilisateur de choisir lui-même le nombre ou les dates des échéances; il utilise le calendrier annuel des Paramètres. Les migrations conservent les frais historiques.

## 3. Synthèse compacte de Finance scolaire

La zone de synthèse fixe comprend maintenant exactement six indicateurs, dans une grille de trois colonnes sur deux lignes :

- Ligne 1 : Total net attendu, Total reçu à ce jour, Reste à recevoir.
- Ligne 2 : Total de la scolarité, Total des frais annexes et droits d'inscription, Total des réductions appliquées.

Le total net attendu est affiché séparément du total brut (indiqué à titre de détail). Les totaux des catégories sont affichés nets des réductions, et le montant des réductions est indiqué séparément. Le style réduit les espacements et la hauteur des cartes pour libérer davantage de place au contenu sous la synthèse.

## 4. Migration et mise en service

La nouvelle migration est : `supabase/migrations/025_annual_payment_schedule_and_required_student_class.sql`.

Avant le déploiement, sauvegarder la base puis appliquer cette migration à l'environnement Supabase concerné. Configurer ensuite les six dates pour l'année scolaire avant de créer/modifier les tarifs et avant toute nouvelle inscription qui doit recevoir automatiquement les frais paramétrés. Les écritures doivent d'abord être testées en préproduction, en particulier les RPC d'inscription et d'attribution des frais.

Cette archive ne modifie pas automatiquement la base Supabase distante. L'inclusion du fichier SQL dans le ZIP ne signifie pas que la migration a été exécutée.

## 5. Contrôles exécutés

- `node --test tests/release-readiness.test.mjs` : **45 tests réussis, 0 échec**.
- `npm run preflight` : **11 contrôles réussis, 0 échec, 1 avertissement** (absence de `package-lock.json`).
- Le précontrôle détecte 25 migrations numérotées sans trou, 41 RPC référencées et 34 tables référencées.

## Limites connues

Le répertoire `node_modules` n'est pas présent dans l'environnement de préparation et l'installation des dépendances en ligne n'a pas abouti. Par conséquent, le build Next.js complet (`npm run build`) et le contrôle TypeScript (`npm run typecheck`) n'ont pas pu être exécutés; aucune réussite de build complet n'est revendiquée. La migration 025 n'a pas été exécutée sur la base Supabase réelle et les parcours n'ont pas pu être validés dans un navigateur connecté à cette base.

Il faut donc traiter cette archive comme une livraison de code à vérifier en préproduction, pas comme une validation du déploiement final.
