# Initialisation d’une nouvelle base EPC BETHEL

`INSTALLATION_COMPLETE.sql` regroupe le schéma et les évolutions des migrations 001 à 026, dans l’ordre, pour un projet Supabase **neuf et vide**. Le bootstrap historique qui attribuait automatiquement l’administration à une adresse e-mail fixe a été retiré de ce script : aucun compte n’est promu administrateur implicitement.

## Initialiser le premier administrateur

1. Exécutez `INSTALLATION_COMPLETE.sql` dans le SQL Editor d’un projet Supabase neuf et vide.
2. Dans Supabase Auth, créez le compte destiné à administrer l’établissement et confirmez son adresse e-mail. Si le compte existait déjà avant l’installation, conservez-le ; son profil est créé avec le rôle Observateur.
3. Vérifiez que le compte est actif et qu’un profil correspondant existe dans `public.profiles`.
4. Relevez l’UUID du compte puis exécutez depuis le SQL Editor :

   ```sql
   select public.bootstrap_epc_admin('UUID-DU-COMPTE-À-ADMINISTRER');
   ```

La fonction refuse d’agir si un profil administrateur existe déjà, si le compte n’est pas actif ou si son adresse e-mail n’est pas confirmée. Elle n’est pas exécutable par les rôles `anon` ou `authenticated` de l’application ; l’appel initial est réservé à l’administration technique de Supabase.

Pour une base existante, n’utilisez pas ce script complet : faites une sauvegarde, vérifiez l’état des migrations, puis appliquez uniquement les migrations manquantes dans l’ordre.
