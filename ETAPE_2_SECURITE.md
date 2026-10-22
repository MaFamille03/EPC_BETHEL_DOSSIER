# EPC BETHEL — Étape 2 : comptes, authentification et autorisations

## Fonctionnement livré dans le code

- L’adresse `minnhindje@gmail.com` est prévue comme administrateur principal.
- Les autres profils sont créés avec le rôle `observateur` par défaut.
- La connexion utilise un code temporaire envoyé à l’adresse e-mail par Supabase Auth.
- La création d’un compte se fait sur `/register` et exige le code serveur `EPC_BETHEL_REGISTRATION_CODE`. Après acceptation du code, Supabase envoie une invitation de confirmation : la boîte e-mail doit être confirmée avant la première connexion OTP. Cela évite de marquer arbitrairement l’adresse d’un tiers comme vérifiée.
- La page Administration > Utilisateurs permet à l’administrateur principal d’inviter des personnes (toujours Observateur au départ), puis de choisir pour chaque compte entre deux niveaux opérationnels comme dans GMP : **Observateur (lecture seule)** ou **Modification (gestion des données métier)**. L’administration des comptes et des journaux reste réservée au compte principal. L’activation/désactivation est également contrôlée depuis cette page.
- Le rôle Administrateur ne peut pas être affecté à un autre compte par l’interface, l’API ou une écriture directe de profil ; l’identifiant et le profil de l’administrateur sont protégés.
- Le rôle Observateur dispose de politiques SQL de lecture seule. Le rôle Modification peut écrire dans les modules métier à travers les politiques RLS existantes, mais ne peut pas administrer les comptes ni consulter les journaux internes de sécurité. Les politiques d’écriture restent appliquées côté base.
- Les changements de rôle et d’état de compte sont inscrits dans `audit_logs`.

## Migrations à appliquer

Dans Supabase SQL Editor, appliquer les migrations dans l’ordre du projet :

1. `010_add_observateur_role.sql`
2. `011_auth_admin_and_observer_access.sql`

Les migrations 001 à 009 doivent déjà avoir été appliquées. Faire une sauvegarde avant d’appliquer les migrations à une base contenant des données. La migration 011 normalise les profils existants : l’adresse administrateur devient `admin`, les autres deviennent `observateur`. L’administrateur peut ensuite passer les utilisateurs concernés au niveau `modification` depuis la page Utilisateurs.

## Variables d’environnement

Ajouter ces valeurs dans `.env.local` en développement et dans Vercel > Settings > Environment Variables en production :

```dotenv
NEXT_PUBLIC_SITE_URL=https://votre-application.vercel.app
NEXT_PUBLIC_SUPABASE_URL=https://VOTRE-PROJET.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=VOTRE_CLE_PUBLIQUE_SUPABASE
SUPABASE_SERVICE_ROLE_KEY=VOTRE_CLE_SERVICE_ROLE_CONFIDENTIELLE
EPC_BETHEL_REGISTRATION_CODE=VOTRE_CODE_LONG_ET_IMPREVISIBLE
```

`NEXT_PUBLIC_SITE_URL` doit être l’URL canonique de l’application en production (et doit aussi être ajoutée aux URL de redirection autorisées de Supabase Auth). `SUPABASE_SERVICE_ROLE_KEY` et `EPC_BETHEL_REGISTRATION_CODE` sont exclusivement côté serveur. Ne pas les préfixer par `NEXT_PUBLIC_`, ni les committer dans Git. Utiliser un code aléatoire d’au moins 24 caractères, différent de tout mot de passe. L’API refuse les codes plus courts. Le code n’est pas inscrit en clair dans le code source.

## Réglages obligatoires dans Supabase Auth

1. Dans Authentication > Sign In / Providers (le nom du menu peut varier), désactiver les inscriptions publiques directes (« Allow new users to sign up »). La création passe par `/register`, qui vérifie le code côté serveur et utilise l’API d’administration. Ce réglage est indispensable : sinon une personne pourrait contourner le code en appelant directement l’API publique Supabase Auth.
2. Dans Authentication > Email Templates, garder un modèle d’invitation qui contient `{{ .ConfirmationURL }}` afin que chaque nouvel utilisateur confirme l’accès à sa boîte e-mail. Configurer aussi le modèle « Magic Link / OTP » afin qu’il affiche `{{ .Token }}` pour la connexion par code. Exemple de contenu OTP :

```html
<h2>Votre code de connexion EPC BETHEL</h2>
<p>Utilisez ce code temporaire pour vous connecter :</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:6px">{{ .Token }}</p>
<p>Ne partagez pas ce code. Si vous n’avez pas demandé de connexion, ignorez cet e-mail.</p>
```

3. Configurer le Site URL et autoriser les URL de redirection de l’application (notamment `/login`) dans Supabase Auth.
4. Vérifier les limites d’envoi d’e-mails et la configuration SMTP. L’invitation/confirmation et les codes OTP exigent un service e-mail correctement configuré.
5. Vérifier que `minnhindje@gmail.com` existe dans Auth ou créer le compte via `/register` avec le code d’inscription, puis confirmer le lien reçu. Le profil doit être `admin` après application des migrations. Si l’adresse existe déjà dans Supabase Auth, confirmez qu’elle est vérifiée et appliquez les migrations avant de tester la connexion.

## Tests avant mise en production

- Connexion OTP pour le compte administrateur principal.
- Refus d’accès à la page Utilisateurs pour tout autre compte.
- Inscription refusée avec un code erroné ou si le code n’est pas configuré.
- Un compte inscrit reçoit une invitation à confirmer et ne peut pas se connecter par OTP avant que l’adresse e-mail soit confirmée.
- Après confirmation, le profil commence avec `observateur` et peut seulement consulter les données autorisées.
- Les commandes d’écriture sont masquées pour le rôle Observateur dans les modules scolaires et financiers ; même en contournant l’interface, les politiques RLS et fonctions SQL refusent les écritures non autorisées.
- Le compte principal ne peut pas être désactivé ni rétrogradé ; aucun autre utilisateur ne peut recevoir le rôle `admin`.
- Les changements de rôle et désactivations créent une ligne d’audit.
- Les invitations administratives restent possibles ; tous les comptes commencent en Observateur, puis l’administrateur peut changer leur rôle depuis le tableau des utilisateurs.

L’application a été modifiée localement, mais les migrations n’ont pas été exécutées sur un projet Supabase réel. Les tests e-mail/OTP et les contrôles RLS de bout en bout exigent la configuration du projet. Ne pas considérer le déploiement comme validé avant ces tests.
