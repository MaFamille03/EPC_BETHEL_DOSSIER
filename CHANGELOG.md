## 1.19.2 — Correction du chargement des soldes de frais dans le formulaire d’encaissement

- Remplace l’appel à `.finally()` sur le résultat PromiseLike de Supabase par deux branches `.then()` (succès et erreur), compatibles avec son type de retour.
- Réinitialise l’état de chargement lorsque le formulaire est fermé ou qu’aucune inscription n’est sélectionnée.
- En cas d’échec réseau, vide la liste des soldes, affiche un message utile et désactive l’indicateur de chargement.
- La suite de cette livraison comprend désormais 42 tests hors ligne, dont un test de régression vérifiant l’absence de `.finally()` sur ce résultat Supabase.

## 1.19.1 — Correction du build Vercel lors de l’enregistrement des catégories de frais

- Correction de l’erreur TypeScript dans `components/class-fee-tariffs-manager.tsx` : les données envoyées lors de la modification d’une catégorie sont maintenant définies séparément de celles envoyées lors de sa création. Cela évite de transmettre à Supabase une union de types contenant les champs `code` et `kind` dans le chemin de mise à jour.
- Aucun changement aux règles métier, à la structure Supabase ou au comportement des catégories de frais.
- Les 41 tests de pré-livraison (dont un test ciblé sur cette régression) et le précontrôle structurel passent localement. Le build Next.js complet reste à confirmer : l’installation npm a expiré dans l’environnement de correction.

## 1.19.0 — Dossier élève, tarifs annuels, concessions et notes individuelles

- Enrichissement du dossier élève avec adresse et coordonnées, affichage du statut d’inscription, saisie structurée des informations du responsable et inscription de l’élève avec l’année/la classe choisies.
- Ajout d’un statut administratif d’abandon distinct des réductions : l’inscription est clôturée avec trace d’audit, tandis que les frais et le solde historiques sont conservés.
- Ajout d’une configuration des catégories de frais et des tarifs par classe et année scolaire, avec montant et jusqu’à six échéances ; les tarifs sont copiés dans les charges au moment de l’attribution et ne changent pas rétroactivement.
- Ajout des réductions ciblées par catégorie, avec motif, valeur fixe ou pourcentage, période de validité et historique. À l’approbation, les frais impayés admissibles sont recalculés ; les frais ayant reçu un paiement confirmé sont préservés.
- Synthèse de Finance scolaire en grille fixe de trois colonnes : net attendu, paiements confirmés, reste à recevoir, totaux nets par catégorie et réductions réellement appliquées.
- Formulaire d’encaissement lié à une catégorie de frais, avec solde avant versement, paiements partiels/successifs, clé d’idempotence, validation transactionnelle et reçu. Seuls les paiements validés réduisent le solde.
- Dans Notes et bulletins, ajout d’une fiche individuelle modale avec onglets Premier, Deuxième et Troisième trimestre ; affichage des notes existantes, coefficients/moyennes, ajout/modification/suppression avec journal d’audit et impression du relevé trimestriel.
- Nouvelle migration Supabase `024_student_fees_tariffs_and_status.sql`. Elle doit être appliquée en environnement de préproduction après sauvegarde avant d’activer les nouveaux parcours.
- La suite locale comprend désormais 40 tests hors ligne, ciblant aussi les tarifs par classe/année, le traitement distinct des abandons, les réductions ciblées et les garde-fous sur les notes.
- Vérifications hors ligne et syntaxiques relancées ; le typecheck/build Next.js complet reste à valider avec les dépendances npm installées et les fonctions SQL testées sur un projet Supabase de développement.

## 1.18.3 — Fenêtres superposées harmonisées dans toute l’application

- Ajout d’un composant commun `ModalPortal` qui rend les fenêtres de saisie au niveau de `document.body`, évite qu’un parent à défilement les coupe et bloque le défilement de la page en arrière-plan.
- Harmonisation des fenêtres de classes, années scolaires, dépenses, achats, patrimoine, mouvements de caisse, comptage physique, transferts internes et création de compte bancaire.
- Le formulaire d’import Excel des élèves et le formulaire d’invitation d’un utilisateur s’ouvrent désormais dans une fenêtre superposée.
- Les formulaires des paramètres de l’établissement (coordonnées officielles et code d’accès aux inscriptions) s’ouvrent eux aussi en fenêtre superposée ; la page Paramètres affiche un aperçu des coordonnées.
- Le rapprochement bancaire place l’import CSV, la sélection de la ligne et la validation du rapprochement dans une fenêtre modale ; la liste des relevés reste sur la page d’origine.
- Les formulaires déjà superposés de Gestion des élèves, Finance scolaire, Encaissements et Notes et bulletins conservent leur fonctionnement.
- Aucun changement au schéma Supabase ni aux règles métier de la comptabilité scolaire.
- Vérifications hors ligne : 37/37 tests réussis ; précontrôle structurel : 11 contrôles réussis, 1 avertissement concernant l’absence de `package-lock.json`. Le typecheck complet et le build Next.js restent à valider avec les dépendances installées.

## 1.18.2 — Formulaires superposés façon UserForm

- Les formulaires de création/modification des élèves, de création des frais scolaires, de détail des échéanciers et d’encaissement sont rendus directement sous `document.body` au moyen de portails React. La page source reste visible en arrière-plan et n’est pas déplacée vers le formulaire.
- Dans Notes et bulletins, la création d’une évaluation, la saisie collective des notes, la configuration des règles de calcul et l’ajout d’une matière s’ouvrent maintenant dans des fenêtres modales superposées.
- Ajout de boutons explicites pour ouvrir chaque formulaire ; fermeture par le bouton de fermeture, Annuler/Fermer ou clic sur le fond de la fenêtre. Les filtres et la page de départ restent conservés.
- Mise en page adaptée aux écrans mobiles et au contenu long : en-tête/pied de fenêtre stables et zone de formulaire défilante.
- Aucun changement au schéma Supabase ni aux règles de calcul des frais, des notes ou des bulletins.
- La suite de régression compte désormais 37 tests hors ligne, dont un contrôle dédié aux fenêtres superposées des trois modules.
- Contrôle syntaxique TypeScript/JSX effectué localement. Installation npm et build complet non exécutés : le registre de dépendances n’a pas répondu dans l’environnement de préparation. Les tests hors ligne doivent être lancés avec `npm run test:release` et la compilation validée avant le déploiement.

## 1.18.1 — Correction du build Vercel

- Correction d’une comparaison TypeScript impossible dans le formulaire bancaire : le formulaire ne s’affiche que dans la rubrique Banque, il ne doit donc pas tester le mode Caisse/Mobile Money.
- Le formulaire de création est désormais explicitement bancaire ; le choix d’un compte caisse ou d’un portefeuille Mobile Money a été retiré de ce formulaire.
- La caisse reste un registre unique : espèces, Orange Money, Wave et Moov Money sont des moyens/canaux de paiement, tandis que la création de comptes bancaires reste séparée.
- Tests de livraison mis à jour et vérification dédiée du formulaire bancaire. **Tests de pré-livraison : 36 réussis sur 36.** Le build Next.js complet doit être relancé sur Vercel pour confirmer la correction dans l’environnement de production.

## 1.18.0 — Caisse unique et contrôle des mouvements

- Libellé du menu simplifié en « Caisse et Mobile Money » pour éviter de laisser croire qu’il faut ouvrir plusieurs comptes. Le compte bancaire reste dans sa propre rubrique.
- Dans le panneau de caisse, les actions « Compter la caisse » et « Ajouter une ligne de caisse » sont désormais placées à côté de la synthèse de caisse théorique, de la caisse physique et des soldes par moyen de paiement.
- Le tableau de caisse conserve l’ordre demandé : Référence, Date, Libellé, Moyen de paiement, Entrée, Sortie, Solde, Statut, Actions.
- La modification/suppression des lignes saisies manuellement est renforcée côté SQL : seules les lignes de la caisse principale peuvent être modifiées ou supprimées, le motif reste obligatoire et les changements susceptibles de rendre un canal négatif sont refusés. Les encaissements, dépenses et transferts liés se corrigent dans leurs modules d’origine afin de préserver la traçabilité.
- Migration `023_cash_register_edit_delete_guardrails.sql` : garde-fous de mise à jour/suppression des lignes manuelles de caisse.
- Tests locaux : 35 réussis sur 35. Le build complet et les migrations doivent être validés sur une base de préproduction avant la production.

## 1.17.0 — Caisse unique et moyens Mobile Money

- La rubrique Caisse utilise un seul compte de trésorerie principal : les espèces et Orange Money, Wave ou Moov Money sont des moyens/canaux, pas des comptes de caisse distincts. La rubrique Banque reste séparée.
- Les formulaires d’encaissement et de dépense associent les opérations en espèces et Mobile Money à la caisse principale. Le formulaire propose le fournisseur Orange Money, Wave ou Moov Money et l’affiche dans le journal, les exports et les reçus.
- La migration `022_cash_register_single_ledger_and_controls.sql` ajoute la catégorisation des mouvements, un comptage physique horodaté, le calcul de caisse théorique, ainsi que des RPC contrôlées et auditées pour saisir, modifier ou supprimer les lignes manuelles de caisse. Les paiements, dépenses et transferts issus de leurs modules restent protégés contre l’édition/suppression directe dans le journal.
- Le contrôle des dépenses utilise le solde du moyen de paiement sélectionné lorsqu’il s’agit de la caisse commune, au lieu de mélanger espèces et Mobile Money.
- Affichage compact en grille 2 colonnes pour les indicateurs de caisse, soldes Orange/Wave/Moov, tableau ordonné Référence, Date, Libellé, Moyen de paiement, Entrée, Sortie, Solde, Statut et Actions.
- L’écran n’offre plus la création de plusieurs comptes de caisse ou de portefeuilles Mobile Money ; la création de comptes demeure dans la rubrique Banque.
- Tests locaux : 34 réussis sur 34. La migration SQL, les permissions RLS, le typecheck complet et le build doivent être vérifiés sur une base de préproduction avant la production.

## 1.16.1 — Import Excel avec commande visible

- Dans Gestion des élèves, le panneau « Importer les élèves depuis Excel » affiche désormais un libellé visible « Déplier » lorsqu’il est fermé et « Réplier » lorsqu’il est ouvert, à la place des symboles plus/moins.
- Le libellé est présenté comme une commande clairement identifiable, avec un style cohérent, un état ouvert/fermé et un comportement adapté aux petits écrans.
- L’import Excel, le téléchargement du modèle, l’aperçu, les contrôles des doublons et le rapport CSV restent inchangés.
- Aucune migration SQL n’est nécessaire.

## 1.16.0 — Rubriques de trésorerie spécialisées

- Séparation des vues Caisse et comptes Mobile Money, Banque, Transferts internes et Journal de trésorerie : chaque page n’affiche plus le même tableau général.
- Caisse/Mobile Money affiche uniquement les comptes physiques et les portefeuilles Mobile Money, avec leurs soldes, entrées, sorties et mouvements associés.
- Banque affiche uniquement les comptes bancaires et conserve le rapprochement des relevés dans cette rubrique.
- Transferts internes présente chaque transfert une seule fois avec source, destination, montant, référence et libellé ; les fonctions SQL continuent à créer les deux mouvements liés sans recette/dépense artificielle.
- Journal de trésorerie conserve la vue consolidée sur tous les comptes, avec filtres et export CSV.
- Nouvelle migration `021_treasury_account_types_and_creation.sql` : type de compte `mobile_money`, champ opérateur et RPC transactionnelle de création de compte avec contrôle administrateur et journal d’audit.
- Création de comptes intégrée aux pages Caisse/Mobile Money et Banque ; solde initial daté, code unique et champs spécifiques au compte.
- Les marges, cartes et filtres sont plus compacts, les commandes alignées et les messages sans résultat plus explicites.
- Contrôles hors ligne et analyse syntaxique réalisés. Le build complet, les tests RLS et les tests sur Supabase réel restent requis en préproduction.

## 1.15.3 — Pagination Finance scolaire en haut

- Déplacement du compteur « Affichage de … sur … frais » et des commandes précédent/suivant dans la barre supérieure, à proximité de la recherche.
- Maintien de l’aide sur le calcul des soldes dans le bloc du compteur.
- Suppression du pied de tableau en doublon pour la liste des frais scolaires.
- Mise en page responsive pour les écrans étroits ; aucune migration SQL ni modification des règles de calcul.

# Journal des versions — EPC BETHEL

## 1.15.2 — Correction du chargement des frais et synthèse 2 × 2

- Correction de l'ambiguïté PostgreSQL `gross_amount` dans `get_school_fee_ledger_filtered` en qualifiant explicitement les colonnes du CTE. La nouvelle migration `020_fix_school_fee_ledger_ambiguity.sql` remplace la fonction sans changer son contrat RPC ni les règles de calcul.
- Les quatre indicateurs « Total net facturé », « Réductions appliquées », « Paiements validés » et « Reste à recouvrer » sont affichés en grille de deux colonnes et deux lignes, y compris sur petit écran, avec des cartes plus compactes.
- Contrôles statiques, tests hors ligne, intégrité de l'archive et présence de la migration corrective vérifiés. La migration et les calculs doivent encore être exécutés et testés en préproduction Supabase.

## 1.15.1 — Finance scolaire plus lisible

- Les libellés visibles utilisent « réduction » et « demandes de réduction » plutôt que « concession », sans renommer les objets SQL afin de préserver la compatibilité avec Supabase.
- La barre d’action Finance scolaire utilise une grille responsive : boutons alignés et de même hauteur (44 px sur grand écran, 42 px sur mobile), avec des libellés plus courts et une répartition plus claire entre actions principales et outils.
- L’écran de création explique que les frais de scolarité et d’inscription/réinscription peuvent être répartis de 1 à 6 versements et que les dates d’échéance doivent être chronologiques.
- Une aide visuelle dans le formulaire clarifie la ventilation des montants et le traitement d’une réduction approuvée ; les calculs et l’écriture des frais restent effectués par la base de données.
- Ajout d’un test de pré-livraison dédié à la compréhension des libellés, au nombre de versements et à l’uniformité des boutons. Build complet et essais Supabase réels restent à effectuer en préproduction.

## 1.15.0 — Clarification de Finance scolaire

- Le vocabulaire visible de l’application privilégie « réduction » et « réductions et aides » plutôt que « concession » ; les noms techniques des tables et RPC restent inchangés pour préserver la compatibilité Supabase.
- Réorganisation des actions Finance scolaire en deux groupes (actions principales et outils), avec une hauteur homogène de 44 px sur ordinateur et 42 px sur mobile. Ajout d’un accès « Demander une réduction » dans l’écran de suivi des réductions.
- Réduction du terme ambigu dans les raccourcis du tableau de bord.
- La création des frais de scolarité et d’inscription/réinscription conserve un échéancier variable de 1 à 6 versements, avec une date par versement et contrôle de l’ordre chronologique. Les frais annexes et autres restent à paiement unique.
- Les quatre indicateurs de synthèse s’appuient sur les agrégats SQL complets, et les filtres permettent de cibler l’année, la classe, la nature des frais et la situation de paiement.
- Tests hors ligne mis à jour pour vérifier les actions réorganisées, le vocabulaire visible, le badge supprimé et les versements variables. L’installation des dépendances, le build complet et les essais sur Supabase de préproduction restent requis avant production.

## 1.14.0 — Finance scolaire clarifiée et échéanciers flexibles

- Remplacement du libellé « concession » dans les textes visibles par « réduction » ou « réduction et aide », plus compréhensible pour l’équipe de gestion. Le nom technique des tables et RPC reste inchangé pour préserver la base existante.
- Suppression du badge statique « 6 » à côté de Finance scolaire : il ne représentait aucune donnée réelle.
- Harmonisation des boutons de la barre d’action Finance scolaire (hauteur commune, retours à la ligne maîtrisés et disposition adaptée aux petits écrans).
- Clarification de la synthèse financière : montant net dû, réductions appliquées, paiements validés et reste à recouvrer dont les retards.
- Frais de scolarité et frais d’inscription/réinscription peuvent être planifiés de 1 à 6 versements avec dates d’échéance contrôlées. Les frais annexes et autres frais restent en paiement unique.
- Ajout de fonctions RPC pour les filtres financiers, la synthèse et le détail des versements ; l’export de Finance scolaire récupère toutes les lignes correspondant aux filtres, au-delà des 100 lignes visibles par page.
- La migration 019 doit être appliquée et testée sur Supabase de préproduction avant déploiement. Compilation complète, typecheck et essais sur Supabase réel non validés dans cet environnement.

## 1.13.2 — Raccourcis depuis le dossier élève

- Le nom et les prénoms de chaque élève sont désormais cliquables dans la liste et ouvrent le dossier individuel avec les coordonnées et l’historique scolaire.
- Ajout dans le dossier de deux raccourcis : « Finance scolaire » et « Notes et bulletins ».
- Le raccourci Finance scolaire ouvre la rubrique avec une recherche préremplie sur le matricule de l’élève (ou son nom en solution de repli).
- Le raccourci Notes et bulletins ouvre les résultats individuels avec l’inscription actuelle de l’élève présélectionnée ; si aucune inscription active exploitable n’est trouvée, la page affiche un message explicite.
- Aucun changement SQL ni de règles de droits n’est introduit. Les raccourcis ouvrent les modules existants et conservent les autorisations habituelles.
- Contrôles hors ligne : 24 tests réussis, contrôle structurel 11 réussites et 1 avertissement lié à l’absence de `package-lock.json` ; analyse syntaxique des deux composants modifiés réussie. Build complet et essais Supabase réels restent requis avant production.

## 1.13.1 — Fenêtre de formulaire du dossier élève

- Le formulaire « Créer un dossier élève » et son équivalent de modification s’ouvrent dans une fenêtre superposée plus large, au-dessus de la page courante.
- Les champs d’identité, de responsable légal et les autres informations sont répartis sur trois colonnes sur grand écran, deux colonnes sur écran intermédiaire et une colonne sur mobile.
- La zone de formulaire conserve son propre défilement si nécessaire ; l’en-tête et les boutons Annuler/Enregistrer restent visibles.
- Les champs et procédures d’enregistrement existants sont conservés. Aucun changement SQL n’est ajouté.
- Contrôles hors ligne : 23 tests réussis, 0 échec ; précontrôle structurel 11 réussites, 0 échec et 1 avertissement lié à l’absence de `package-lock.json`. Analyse syntaxique du composant modifié réussie. Build complet et tests Supabase réels restent à effectuer en préproduction.


## 1.13.0 — Amélioration de la gestion des élèves

- Suppression des trois cartes de métriques dans la page élèves, sans toucher aux autres rubriques ; le bouton Actualiser reste disponible dans l’en-tête.
- Déplacement de la pagination et du compteur au-dessus du tableau, à côté du titre « Liste des élèves ».
- Passage à 50 élèves par page par défaut (choix 10 et 25 conservés) et affichage des noms/prénoms longs sur plusieurs lignes.
- Import Excel préservé dans un panneau repliable ; le modèle vierge est téléchargeable depuis la page, y compris en lecture seule ou hors connexion. Les erreurs/doublons ont un rapport CSV téléchargeable et la liste s’actualise après l’import.
- Vérification préalable des matricules existants, rapport d’import plus explicite et actualisation de la liste après import réussi.
- Ajout d’une fiche de consultation avec l’identité, le responsable légal, les notes administratives et l’historique des inscriptions, ainsi que de sections distinctes dans le formulaire de modification.
- Aucun changement du schéma de base ni des RPC scolaires. La recherche reste limitée aux dossiers chargés (maximum actuel 1 000) ; pagination serveur, responsables légaux et affectation en classe dans l’import Excel restent des évolutions distinctes.
- L’analyse syntaxique et l’intégrité de l’archive sont contrôlées ; build complet et tests réels Supabase non validés dans cet environnement.

## 1.11.3 — Finition du module Notes et bulletins

- Suppression du message ambigu laissant entendre que l’accès à la préparation des bulletins est réservé à l’administrateur ; les permissions effectives restent contrôlées par les rôles et les règles d’accès existantes.
- Remplacement du sélecteur « Choisir un élève » par un champ mieux structuré, libellé « Élève à consulter », avec focus clavier visible et identifiant élève facultatif.
- Réduction des espaces verticaux inutiles dans les panneaux, indicateurs et en-têtes de Notes et bulletins.
- Tests de pré-livraison : 23 réussis. Contrôle structurel : 11 réussis, 1 avertissement lié à l’absence de package-lock.json, 0 échec. Le build et le typecheck restent à exécuter après installation des dépendances.


## 1.11.2 — Module Notes et bulletins du primaire

- Ajout des évaluations par classe, matière, trimestre, barème et coefficient.
- Saisie collective des notes avec statuts distincts pour absences, dispenses et notes manquantes.
- Moyennes configurables et préparation/publication des bulletins trimestriels.
- Aperçu imprimable du bulletin publié et export CSV des relevés individuels.
- Migration Supabase 018, contrôles RLS et journalisation des modifications de notes.
- Contrôle hors ligne : 23 tests hors ligne réussis. Le typecheck/build complet et les essais Supabase doivent être réalisés sur une machine connectée et en préproduction.

## 1.10.5 — Organisation du menu et consolidation de trésorerie
- Organisation de la navigation en cinq rubriques principales conformément au cahier des charges.
- Raccordement des entrées financières au module de trésorerie existant.
- Module Notes et bulletins : saisie des notes, calcul de moyennes pondérées et export CSV après migration 016.
- Module Banque : import CSV de relevé, propositions de rapprochement et validation transactionnelle après migration 017.
- Contrôles de rapprochement empêchant les doublons et vérifiant compte, montant, sens et validation du mouvement.

## 1.9.7 — Harmonisation de la charte graphique officielle

- Palette centrale alignée sur le logo de l’établissement : vert `#0C6900`, orange `#FF6600`, violet `#802872` et blanc.
- Contrastes renforcés sur les boutons principaux, les éléments de navigation et les panneaux de connexion.
- Accent orange/violet discret dans la navigation et les bandeaux, sans surcharger les pages.
- Ajout d’un indicateur de focus clavier plus visible et respect de la préférence de réduction des animations.
- Contrôle de pré-livraison relancé ; build Next.js complet et validation réelle Supabase restent à effectuer dans un environnement connecté.

## 1.9.6 — Authentification unifiée et correction de configuration Supabase

- Connexion et inscription partagent désormais la même page et conservent le panneau visuel fixe.
- Réduction des logos répétés et formulaire plus haut, avec mise en page compacte.
- Client Supabase compatible avec les variables de clé publique `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` et `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- Route d’inscription compatible avec `SUPABASE_SECRET_KEY` et l’ancien nom `SUPABASE_SERVICE_ROLE_KEY`.
- Les secrets restent réservés au serveur ; aucune clé secrète n’est ajoutée au dépôt.

## 1.9.5 — Connexion par mot de passe et lisibilité

- Connexion avec adresse e-mail et mot de passe, sans code administrateur lors des connexions ordinaires.
- Réinitialisation du mot de passe par e-mail depuis la page de connexion.
- Inscription avec mot de passe, confirmation du mot de passe et code d’accès.
- Augmentation modérée de la taille des textes de l’interface.
- Le rôle applicatif continue d’être déterminé côté base de données, jamais depuis le formulaire.


## 1.9.4 — Étape 9 : cohérence d’interface et hygiène de livraison

- La recherche rapide de la barre supérieure permet de filtrer les modules accessibles et d’y naviguer ; le raccourci `Ctrl/Cmd + K` ouvre la recherche.
- Le menu de compte est interactif, affiche le niveau d’accès, propose les liens permis au rôle et permet la déconnexion ; il se ferme par clic extérieur ou Échap.
- La cloche ouvre un état vide explicite : aucune source de notifications n’est déclarée connectée à ce stade, aucune alerte fictive n’est affichée.
- Documentation racine et guide d’installation alignés sur la version 1.9.4 ; ajout de tests de cohérence documentaire et des commandes de barre supérieure.
- Suppression de `tsconfig.tsbuildinfo`, artefact de compilation généré, de l’archive livrée.
- La suite de cette version comprenait **19 tests hors ligne** ; le précontrôle conservait son avertissement relatif à l’absence de `package-lock.json`. Compilation complète, exécution Supabase et déploiement Vercel restaient non validés.

## 1.9.3 — Étape 8 : mode aperçu sûr et absence de données fictives

- Suppression des exemples fictifs d'élèves, coordonnées, paiements, dépenses, achats et patrimoine des métadonnées de modules.
- Les listes scolaires démarrent vides et demeurent vides sans connexion Supabase ; aucun exemple n'est présenté comme un enregistrement de l'établissement.
- Les actions de création des rubriques scolaires sont indisponibles en mode aperçu.
- Le contexte d'accès applique la lecture seule par défaut si aucun rôle utilisateur n'est établi.
- En environnement connecté, les menus protégés ne sont visibles que lorsqu'un rôle valide a été vérifié ; une erreur de vérification renvoie vers la connexion.
- Ajout de quatre tests structurels pour détecter le retour des données fictives et préserver le principe « fail closed ».
- La validation par build, par TypeScript complet et sur Supabase reste à effectuer : le registre npm renvoie toujours `EAI_AGAIN` et le fichier `package-lock.json` ne peut pas être généré ici.


## 1.9.2 — Étape 7 : revue finale de livraison

- Ajout d’une suite de 12 tests de pré-livraison hors ligne avec `node:test`, lançable par `npm run test:release` sans dépendances applicatives installées.
- Les tests couvrent la présence des routes d’authentification, le rôle de l’administrateur principal, l’inscription par code, l’OTP, la séparation des rôles, l’absence de références de clé service dans les composants clients, les migrations et les garde-fous financiers.
- Ajout de `CHECKLIST_MISE_EN_SERVICE.md` couvrant installation, Supabase de développement, matrice RLS, parcours métier, préproduction Vercel et critères de mise en production.
- Mise à jour de la documentation vers la version 1.9.2 et ajout du rapport final de contrôle.
- Résultats locaux : 12 tests hors ligne réussis ; précontrôle 11 réussites, 1 avertissement et 0 échec ; 23 fichiers TypeScript/TSX sans erreur syntaxique.
- Le build complet et le typecheck ne sont pas validés : le registre npm est inaccessible (`EAI_AGAIN registry.npmjs.org`) et les dépendances ne sont pas installées. La migration SQL et les tests end-to-end doivent encore être exécutés sur un projet Supabase de développement. `package-lock.json` reste à générer dans un environnement connecté.

## 1.9.1 — Étape 6 : contrôles finaux et préparation au déploiement

- Ajout du script autonome `scripts/preflight-check.mjs` et de la commande `npm run preflight`.
- Contrôles statiques des fichiers essentiels, imports locaux, références tables/RPC, ordre des migrations, délimiteurs SQL, règles `.env` et absence d’utilisation client de la clé service.
- Mise à jour du rapport qualité avec les résultats mesurés de l’étape 6 et les limites explicites de la validation.
- 25 fichiers TypeScript/TSX passent l’analyse syntaxique ; aucune erreur syntaxique détectée.
- L’analyse statique a corrigé deux défauts dans le module Patrimoine (état `loading` inexistant et motif de refus potentiellement nul).
- Les dépendances n’ont pas pu être installées : le registre npm a renvoyé `EAI_AGAIN registry.npmjs.org`. Le typecheck et le build complet ne sont donc pas validés.
- La base Supabase n’étant pas connectée, les migrations et les tests fonctionnels/RLS restent à exécuter sur un projet de développement.
- `package-lock.json` absent : à générer et conserver depuis un environnement connecté avant le déploiement.


## 1.9.0 — Étape 5 : achats, patrimoine et rapports

- Rapport de gestion connecté aux fonctions PostgreSQL : synthèse financière, impayés, encaissements, dépenses, journal de caisse/banque, bons de commande, réceptions, inventaire et maintenance.
- Filtres de période, année scolaire lorsque pertinent, recherche, pagination serveur, export Excel des résultats filtrés (maximum 50 000 lignes) et impression navigateur.
- Historique réel des réceptions affiché dans Achats, avec recherche ; activation/désactivation des fournisseurs sans supprimer l’historique.
- À la réception d’articles de nature « immobilisation », création automatique d’une fiche d’inventaire par unité entière, liée à la ligne de commande ; aucune dépense ou sortie de trésorerie n’est créée par la réception.
- Catégorie patrimoniale propagée de la demande à la ligne de commande ; la catégorie est résolue à partir du code ou du nom ; une valeur non reconnue est refusée, tandis qu’une catégorie non renseignée utilise « Autres biens » si cette catégorie est active.
- Modification des fiches d’inventaire et enregistrement transactionnel des maintenances avec synchronisation du statut du bien.
- Nouvelle migration `014_management_reports_asset_integration.sql`.
- Contrôles statiques et intégrité de l’archive réalisés. Compilation Next.js et exécution des migrations sur Supabase restent à valider dans un environnement configuré.


## 1.8.0 — Étape 4 : fiabilité financière et trésorerie

- Ajout d’agrégats PostgreSQL pour les recettes, dépenses, frais, paiements affectés, soldes dus et trésorerie afin d’éviter des totaux limités au nombre de lignes chargées dans le navigateur.
- Ajout d’une liste de frais paginée côté serveur et de listes d’inscriptions avec solde positif pour l’encaissement.
- Refonte du tableau de bord pour obtenir les indicateurs et recettes mensuelles depuis les fonctions SQL.
- Refus côté base des dates de paiement, de validation de dépense et de transfert situées dans le futur ; contrôles de date cohérents dans l’interface.
- Conservation de l’historique des opérations et des mécanismes de contrepassation existants.
- Migration ajoutée : `013_financial_integrity_reporting.sql`. Tests de compilation et d’intégration Supabase encore requis avant production.

## Version 1.6.1 — Stabilisation technique (16 octobre 2026)
- Alignement de la version du paquet sur la livraison V1.6.
- Déclaration du prérequis Node.js 20.9 ou supérieur dans `package.json`.
- Renforcement de `.gitignore` pour exclure les fichiers d’environnement contenant des secrets, en conservant `.env.example`.
- Sécurisation du `search_path` des cinq fonctions `SECURITY DEFINER` de la migration 008 (`search_path = ''` ; références de schéma qualifiées).
- Contrôles statiques effectués ; compilation complète et exécution des migrations restent à valider dans un environnement disposant des dépendances et d’un projet Supabase de test.

## Version 1.5.0 — Étape 4 : achats et patrimoine
- Page Achats & fournisseurs : gestion des fournisseurs, demandes avec lignes, soumission et décision, commandes créées depuis les demandes approuvées, réceptions partielles/complètes.
- Page Patrimoine & inventaire : registre des biens, catégories initiales, maintenance et mouvements d’emplacement.
- Migration `008_achats_patrimoine_workflows.sql` : fonctions transactionnelles de workflow et contrôle des quantités réceptionnées.
- Les commandes et réceptions n’émettent pas de mouvement de trésorerie. Le paiement doit passer par Dépenses pour éviter les doubles sorties.
- Les tests de compilation et de connexion Supabase restent à effectuer avant la production.


## Version 1.4.0 — Étape 3 : trésorerie et comptabilité
- Nouvelle page Trésorerie reliée à Supabase : comptes actifs, soldes calculés à partir du solde initial et des mouvements validés, journal filtrable et export CSV.
- Transferts internes par fonction SQL transactionnelle : deux mouvements liés (sortie/entrée), contrôle du compte source, vérification du solde et journal d’audit.
- Nouvelle page Dépenses : création en brouillon, catégories, compte à débiter, validation avec contrôle du solde, annulation par contrepassation et export CSV.
- Numérotation annuelle des dépenses et journal d’audit.
- Migration `007_tresorerie_comptabilite.sql`.
- L’étape n’est pas certifiée en production avant application et tests des migrations sur Supabase de développement, tests sous chaque rôle et compilation complète.

## Version 1.3.0 — Étape 2
- Encaissements, affectations, reçus et annulations.

## Version 1.2.0 — Étape 1
- Éléments de gestion scolaire et concessions.

## Version 1.6.0 — Étape 5
- Renforcement du contrôle d’authentification dans l’espace applicatif et filtrage de navigation selon les rôles.
- Administration des utilisateurs : invitations par e-mail côté serveur, attribution de rôle et activation/désactivation des profils. La clé service n’est jamais exposée au navigateur.
- Paramètres réels de l’établissement et gestion transactionnelle de l’année scolaire active via la migration 009.
- Réinitialisation du mot de passe par e-mail avec écran de définition du nouveau mot de passe.
- Import des élèves depuis Excel (.xlsx/.xls) ou CSV avec aperçu, contrôle des champs obligatoires, détection des matricules en double et import par lots sans écraser les dossiers existants.
- Exports CSV existants conservés; impression navigateur utilisable pour l’enregistrement PDF.


## Version 1.7.0 — Étape 3 : gestion scolaire
- Dossiers élèves : modification des données principales et des coordonnées du responsable légal principal (téléphone, e-mail, profession, adresse et lien avec l’élève).
- Matricule proposé automatiquement si celui-ci est laissé vide à la création ; le matricule reste obligatoire pour la modification d’un dossier existant.
- Inscriptions et réinscriptions enregistrées via une fonction SQL contrôlée, avec vérification de l’élève actif, de l’année ouverte, de la classe active et journal d’audit.
- Changement de classe sur une inscription active, avec date, motif et journal d’audit.
- Sortie définitive ou transfert vers un autre établissement, avec clôture de l’inscription active et mise à jour du statut du dossier si aucune autre inscription active ne subsiste.
- Paramètres : gestion des classes (création, modification, ordre, activation/désactivation) et liste historique des années scolaires (création, modification, choix de l’année active).
- Nouvelle migration `012_school_management_completion.sql`.
- Les validations de syntaxe TypeScript passent, mais la compilation complète et l’exécution PostgreSQL/Supabase restent à effectuer dans un environnement connecté aux dépendances et au projet réel.



## 1.9.8 — Code d’accès administrateur configurable
- Ajout du paramètre « Utilisateurs et autorisations » pour définir/remplacer le code d’inscription depuis l’application.
- Le code n’est jamais renvoyé au navigateur ; seul son condensat salé est stocké dans une table inaccessible aux rôles anon/authenticated.
- Ajout de la migration `015_admin_registration_code_settings.sql`.
- Les API d’administration acceptent les clés Supabase publishable/anon et secret/service_role actuelles.
- La création de compte vérifie le code stocké côté serveur ; plus besoin de la variable `EPC_BETHEL_REGISTRATION_CODE`.

## 1.11.2 — Harmonisation des cinq vues Notes et bulletins
- Mise en page cohérente des vues Vue d’ensemble, Saisie des notes, Résultats des élèves, Bulletins trimestriels et Configuration.
- Filtres alignés sur une ligne sur écran large et navigation horizontale persistante.
- Espacements, formulaires, tableaux et métriques adaptés aux écrans étroits pour éviter les chevauchements.
