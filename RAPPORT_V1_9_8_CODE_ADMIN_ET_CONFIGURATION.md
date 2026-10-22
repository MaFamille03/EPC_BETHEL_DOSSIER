# EPC BETHEL — Version 1.9.8
## Code administrateur dans les paramètres et correction de configuration Supabase

### Modifications
- Ajout de **Paramètres → Utilisateurs et autorisations** pour que l’administrateur principal `minnhindje@gmail.com` définisse ou remplace le code d’accès aux inscriptions.
- Le code en clair n’est jamais enregistré en base ni renvoyé au navigateur. Il est dérivé avec `scrypt` et un sel aléatoire, puis vérifié côté serveur.
- La création de compte lit le condensat depuis `public.admin_access_settings`.
- L’API d’administration accepte les noms de clés publics actuels et historiques (`NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_ANON_KEY`) ainsi que les clés serveur (`SUPABASE_SECRET_KEY`, `SUPABASE_SERVICE_ROLE_KEY`).
- La table de configuration est protégée par RLS et aucune permission directe n’est accordée aux rôles `anon` et `authenticated` ; l’accès passe par les routes serveur qui vérifient la session, l’adresse principale et le rôle actif.

### Installation obligatoire
1. Dans Supabase Dashboard → SQL Editor, exécuter **une seule fois** `supabase/migrations/015_admin_registration_code_settings.sql`.
2. Dans Vercel → Settings → Environment Variables, vérifier pour l’environnement Production :
   - `NEXT_PUBLIC_SUPABASE_URL` = URL du projet Supabase ;
   - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` ou `NEXT_PUBLIC_SUPABASE_ANON_KEY` = clé publique correspondante ;
   - `SUPABASE_SECRET_KEY` ou `SUPABASE_SERVICE_ROLE_KEY` = clé privée du même projet, uniquement côté serveur et jamais préfixée par `NEXT_PUBLIC_`.
3. Redéployer Vercel après toute modification des variables.
4. Se connecter comme `minnhindje@gmail.com`, ouvrir Paramètres → Utilisateurs et autorisations, puis définir un code d’au moins 16 caractères. Le code n’est plus défini dans une variable d’environnement.
5. Tester une inscription avec un compte de test et confirmer qu’une connexion ultérieure utilise uniquement l’e-mail et le mot de passe.

### Contrôles effectués localement
- Suite de pré-livraison : 19 tests réussis, 0 échec.
- Préflight : 11 contrôles réussis, 0 échec, 1 avertissement (absence de `package-lock.json`).
- Les imports internes, la numérotation des 15 migrations, les tables et RPC référencées ont été contrôlés.

### Limites
La compilation complète Next.js/TypeScript, l’exécution de la migration sur la vraie base Supabase et le test en production n’ont pas été exécutés depuis cet environnement. Le dossier doit donc être déployé et testé dans Vercel/Supabase avant de déclarer la version validée en production.
