# EPC BETHEL — Étape 4 : scolarité, encaissements et trésorerie

**Version du projet :** 1.8.0  
**Migration ajoutée :** `supabase/migrations/013_financial_integrity_reporting.sql`

## Modifications incluses

- Calcul côté PostgreSQL des totaux financiers consommés par le tableau de bord, la page des encaissements et la page des dépenses. Les indicateurs ne dépendent plus des seules lignes récentes chargées dans le navigateur.
- Ajout d'un registre des frais scolaires paginé côté serveur, avec montant brut, réduction, montant net dû, sommes payées affectées, reste dû, matricule, classe et année scolaire.
- Ajout d'une liste d'inscriptions dont le solde dû est positif pour la création des encaissements. Le libellé comprend le matricule pour différencier les homonymes.
- Renforcement des fonctions d'encaissement, de validation de dépense et de transfert afin de refuser les opérations datées dans le futur.
- Calcul des soldes qui tient compte de la date d'effet du solde d'ouverture du compte.
- Nouvelles limites explicites sur les fonctions SQL (retraits des permissions `public`/`anon`, exécution réservée à `authenticated`) et `search_path` fixé.
- Amélioration des libellés français des mois sur le graphique du tableau de bord et des champs date dans l'interface.

## Règles financières à préserver

- Les paiements sont affectés dans une transaction SQL aux échéances les plus anciennes, puis aux frais ponctuels impayés.
- Le montant d'un paiement ne peut pas dépasser le reste dû sur les frais validés de l'inscription.
- Les frais de scolarité annuels gardent les montants brut, réduction appliquée et montant net. Une concession n'est appliquée que si elle est approuvée et encore valide au moment de la création des échéances.
- Une dépense est créée en brouillon ; elle affecte la trésorerie seulement à la validation, avec contrôle du solde disponible.
- L'annulation d'une opération financière conserve l'historique et s'appuie sur une contrepassation selon les fonctions déjà présentes.
- Un transfert entre comptes crée un mouvement sortant et un mouvement entrant liés et ne compte pas comme recette ni dépense.
- Les soldes et agrégats excluent les dates postérieures à la date courante. Le solde d'ouverture n'est pas disponible avant sa date d'effet.

## Limites connues

- Le tableau de frais est paginé par 100 lignes côté serveur.
- Les listes de reçus, dépenses et mouvements de trésorerie affichent encore les 500 ou 1 000 opérations les plus récentes selon le module. Les totaux et soldes montrés sur ces pages sont, eux, agrégés côté PostgreSQL sur l'ensemble des opérations applicables. La pagination/recherche complète de ces journaux reste à finaliser.
- Le module des rapports détaillés n'est pas couvert par cette étape.
- Les tests de migration réelle, de transactions concurrentes et de contrôle RLS exigent un projet Supabase de développement et des comptes de test.

## Contrôles de livraison

- 23 fichiers TypeScript/TSX analysés avec le compilateur TypeScript en mode transpilation isolée : aucune erreur syntaxique détectée.
- Migration SQL 013 : 10 déclarations de fonctions, 10 couples de révocation/attribution d'exécution, 20 délimiteurs dollar-quote appariés, un `BEGIN` et un `COMMIT` transactionnels.
- Archive ZIP à vérifier après empaquetage.
- La compilation complète Next.js (`npm run build`), le contrôle de types global (`npm run typecheck`) et l'exécution des migrations n'ont pas pu être confirmés dans l'environnement de préparation, car l'installation des dépendances npm a expiré et aucune base Supabase réelle n'était connectée.

## Installation prudente

1. Sauvegarder la base et le dépôt actuel.
2. Appliquer la migration `013_financial_integrity_reporting.sql` uniquement après `001` à `012`, d'abord dans un projet de développement.
3. Tester les reçus partiels, paiements complets, dépassements de solde, concessions de 0/50/100 %, dépenses sans solde suffisant, annulations, transferts, dates futures et comptes avec date d'ouverture future.
4. Comparer les soldes affichés aux mouvements de trésorerie dans PostgreSQL, puis exécuter `npm run typecheck` et `npm run build` dans un environnement où `npm install` est achevé.

Ne pas appliquer à la production avant réussite des scénarios de test et contrôle des sauvegardes.
