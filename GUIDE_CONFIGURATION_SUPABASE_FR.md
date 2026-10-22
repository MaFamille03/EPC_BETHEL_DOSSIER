# Configuration Supabase — EPC BETHEL (version 1.10.1)

## À quoi servent ces deux variables ?

- `SUPABASE_SERVICE_ROLE_KEY` : clé privée très puissante utilisée uniquement par le serveur pour les opérations administratives. Elle ne doit jamais commencer par `NEXT_PUBLIC_`, être placée dans un composant navigateur, ni être publiée sur GitHub.
- `EPC_BETHEL_REGISTRATION_CODE` : code court saisi par les personnes autorisées au moment de créer un compte. Il ne remplace ni le mot de passe ni la confirmation par e-mail.

## Où les configurer ?

Dans Vercel : projet EPC BETHEL → Settings → Environment Variables. Contrôler les variables suivantes :

- `SUPABASE_SERVICE_ROLE_KEY` (ou `SUPABASE_SECRET_KEY`) = clé privée du projet Supabase, côté serveur uniquement.
- `NEXT_PUBLIC_SUPABASE_URL` = URL du projet Supabase.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` (ou `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`) = clé publique du projet Supabase.

Sélectionner les environnements utilisés (Production, Preview et/ou Development), enregistrer puis redéployer l’application. Ne jamais envoyer les clés secrètes dans une capture d’écran ou une conversation.

**Le code `EPC_BETHEL_REGISTRATION_CODE` n’est pas nécessaire si tu utilises la gestion du code depuis Paramètres → Utilisateurs et autorisations.** Dans ce cas, crée ou remplace le code directement dans l’application. Il sert uniquement à autoriser les nouvelles inscriptions ; il ne sert jamais à se connecter.

## Confirmation de l’adresse e-mail

Dans Supabase → Authentication → Email Templates → Confirm signup, coller le contenu de `MODELE_EMAIL_CONFIRMATION_FRANCAIS.html`. Garder impérativement `{{ .ConfirmationURL }}` dans le modèle. Vérifier aussi Authentication → URL Configuration : l’URL du site et l’URL de redirection vers `/login?confirmed=1` doivent être autorisées. La confirmation par e-mail doit être activée.

## À propos du filigrane

Le logo transparent est appliqué comme filigrane grand format sur les pages de l’application, la connexion et la réinitialisation du mot de passe. Son opacité est volontairement faible pour préserver la lisibilité. L’impression masque ce filigrane.

## Vérification

Après configuration, tester en préproduction : inscription avec une adresse à laquelle vous avez accès, réception de l’e-mail, clic de confirmation, puis connexion avec e-mail et mot de passe. Le code ne permet pas de se connecter ; il sert seulement à autoriser une inscription.
