# Rapport de modification — Trésorerie EPC BETHEL V1.16.0

## Modifications

- Spécialisation des rubriques `caisse-mobile-money`, `banque`, `transferts-internes` et `journal-tresorerie`.
- Filtrage par type de compte dans les vues caisse/Mobile Money et banque.
- Transferts groupés visuellement par identifiant, avec un seul enregistrement par transfert dans son historique.
- Vue Journal consolidée sur tous les comptes, avec indicateurs et export filtré.
- Ajout de `mobile_money` au type PostgreSQL `account_kind`, champ `provider_name` et RPC `create_cash_account` dans la migration 021.
- Création du compte contrôlée côté serveur par un rôle administrateur et journalisée dans `audit_logs`.
- Formulaire de création avec code unique, nom, type, solde initial et date d’ouverture, et champs Banque/opérateur selon le type.
- Règles de transfert existantes conservées : l’opération reste transactionnelle et produit une sortie et une entrée liées.

## Limites de vérification

La migration SQL n’a pas été exécutée sur un projet Supabase connecté. Le build Next.js et les tests de bout en bout ne peuvent donc pas être revendiqués. Avant production, sauvegarder la base, appliquer la migration 021 après 020 en préproduction, puis tester la création de comptes en admin, la lecture seule, les encaissements, dépenses, transferts et le rapprochement bancaire.
