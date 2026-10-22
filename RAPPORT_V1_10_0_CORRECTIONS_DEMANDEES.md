# EPC BETHEL — Version 1.10.0

## Corrections intégrées au code source
- Les messages d’état dans Paramètres disposent désormais d’espacements et d’un alignement adaptés pour éviter les chevauchements.
- Le code d’accès 6–8 chiffres est vérifié côté serveur ; l’inscription utilise ensuite `supabase.auth.signUp` pour déclencher le processus natif de confirmation e-mail de Supabase.
- Après l’inscription, l’interface indique en français que l’utilisateur doit confirmer son adresse e-mail avant de se connecter.
- Le bandeau « Année scolaire » dans la barre latérale devient un raccourci vers les paramètres et la section des années scolaires. Le tableau explique comment créer puis activer une année si aucune n’existe.
- Ajout d’un modèle de courriel français `MODELE_EMAIL_CONFIRMATION_FRANCAIS.html`.

## Configuration Supabase indispensable
1. Dans Authentication → Email Templates → Confirm signup, coller le contenu du fichier HTML en conservant `{{ .ConfirmationURL }}`.
2. Vérifier que la confirmation d’adresse e-mail est activée dans les réglages Auth.
3. Ajouter l’URL de production et `https://VOTRE-DOMAINE/login?confirmed=1` aux URL de redirection autorisées.
4. La création du compte dépend de l’activation des inscriptions par e-mail dans Supabase. Le code d’accès de l’application reste contrôlé côté serveur avant l’inscription.
5. Pour l’année scolaire, appliquer les migrations déjà prévues dans l’ordre du projet ; `save_school_year` doit être disponible et le rôle doit être `admin` ou `direction` selon les règles SQL.

## Limites des vérifications
L’archive et les fichiers ont été préparés, mais cette session ne dispose pas d’un projet Supabase connecté pour tester réellement l’envoi d’e-mail, la confirmation, les autorisations RLS ni le déploiement de production. Ne pas considérer ces tests d’intégration comme réussis avant vérification sur le projet.
