# EPC BETHEL — livrables de spécification

Fichiers :
- `Specification_technique_EPC_BETHEL.docx` : cahier technique et modèle de données.
- `001_initial_schema_epc_bethel.sql` : migration PostgreSQL/Supabase initiale.

## Attention avant production
La migration SQL est une base de référence à auditer et tester dans un projet Supabase de développement. Elle crée le schéma, les contraintes, quelques vues, les rôles et les politiques RLS de départ. Elle ne constitue pas seule une application prête à encaisser des paiements : les fonctions transactionnelles de validation/annulation de paiement, de validation de dépense, de transfert, et de numérotation doivent être implémentées et testées avant toute mise en production.

Ne pas utiliser des données réelles avant validation des droits RLS, des workflows financiers, des sauvegardes et de la restauration.
