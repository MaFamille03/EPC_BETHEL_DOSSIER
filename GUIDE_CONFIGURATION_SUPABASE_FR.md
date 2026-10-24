# Guide Supabase — EPC BETHEL

## Variables utilisées par l’application

- `NEXT_PUBLIC_SUPABASE_URL` : URL du projet.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` ou `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` : clé publique.
- `NEXT_PUBLIC_SITE_URL` : URL du site à utiliser pour les invitations et les redirections.
- `SUPABASE_SERVICE_ROLE_KEY` ou `SUPABASE_SECRET_KEY` : clé privée réservée aux opérations serveur.

Le code autorisant les nouvelles inscriptions est administré dans **Paramètres → Utilisateurs et autorisations**. Il est stocké sous forme de hash salé dans `public.admin_access_settings`. Il ne doit pas être renseigné dans une variable d’environnement dédiée.

## Migration de transfert administrateur

Sur une base existante à la migration 025, sauvegardez la base puis appliquez `supabase/migrations/026_transferable_admin_profile.sql` après validation en préproduction. La fonction `public.transfer_epc_admin(uuid)` permet à l’administrateur courant de transférer son rôle à un utilisateur déjà créé, actif et confirmé par e-mail. L’opération est transactionnelle ; l’ancien administrateur devient Modification.

Ne modifiez pas les migrations déjà appliquées. `supabase/setup/INSTALLATION_COMPLETE.sql` est réservé à l’initialisation d’un nouveau projet Supabase vide.

## Rappels de sécurité

- Ne mettez jamais les clés service dans un composant client ou une variable préfixée `NEXT_PUBLIC_`.
- Ne commitez jamais `.env.local` ou une vraie configuration de production.
- Conservez les règles RLS et les fonctions `SECURITY DEFINER` avec un `search_path` vide.
- Sauvegardez avant les migrations, puis testez les accès et les données métier sur une base de préproduction.
