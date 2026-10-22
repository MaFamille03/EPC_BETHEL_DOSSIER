# Déploiement d’EPC BETHEL sur Vercel

Cette archive consolide les modifications des étapes 1 à 9. Le dossier courant est la racine du projet : `package.json`, `app/`, `components/`, `lib/` et `supabase/` doivent se trouver au même niveau dans le dépôt GitHub.

> **État important :** les contrôles hors ligne réussissent, mais le build Next.js et les migrations sur une vraie base Supabase n’ont pas encore été validés dans l’environnement de préparation. Traiter cette version comme une candidate de préproduction, pas comme une production déjà vérifiée.

## Méthode recommandée : GitHub puis Vercel

1. Téléchargez et décompressez l’archive. Ne poussez pas l’archive ZIP elle-même : poussez son contenu, avec `package.json` à la racine du dépôt.
2. Créez un dépôt GitHub privé et chargez tous les fichiers du dossier. Ne chargez jamais un fichier `.env.local` contenant des secrets.
3. Avant la production, depuis un ordinateur où le registre npm est accessible, ouvrez un terminal à la racine du projet et exécutez :

   ```bash
   npm install
   npm run test:release
   npm run preflight
   npm run typecheck
   npm run build
   ```

   Gardez `package-lock.json` dans le dépôt après la réussite de `npm install`. Le fichier n’est pas inclus ici car sa génération a échoué dans l’environnement de préparation (`EAI_AGAIN registry.npmjs.org`).
4. Dans Vercel, utilisez **Add New → Project**, importez le dépôt GitHub, vérifiez que le répertoire racine est `./` et que le framework est détecté comme **Next.js**. La commande de build est `npm run build`.
5. Configurez les variables d’environnement ci-dessous pour les environnements nécessaires. N’ajoutez aucune valeur secrète au code ni au dépôt GitHub.
6. Déployez d’abord un aperçu (Preview), vérifiez les journaux de build et testez le site. Ne basculez pas en production avant la validation des migrations et des permissions.

## Variables d’environnement Vercel

Récupérez les valeurs Supabase depuis **Project Settings → API** de votre projet Supabase. Les noms des variables doivent être écrits exactement ainsi :

| Variable | Valeur |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | URL de votre projet Supabase, du type `https://xxxx.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Clé publique/anon de ce projet Supabase |
| `NEXT_PUBLIC_SITE_URL` | URL canonique de l’application déployée, par exemple `https://votre-projet.vercel.app` |
| `SUPABASE_SERVICE_ROLE_KEY` | Clé service Supabase, réservée au serveur ; **ne jamais** lui ajouter `NEXT_PUBLIC_` |
| `EPC_BETHEL_REGISTRATION_CODE` | Secret aléatoire d’au moins 24 caractères, utilisé pour autoriser les inscriptions ; ce n’est pas le code OTP de connexion |

Si le domaine Vercel n’existe pas encore, vous pouvez effectuer un premier déploiement Preview, puis renseigner `NEXT_PUBLIC_SITE_URL` avec l’URL canonique et redéployer. Configurez aussi dans Supabase Auth l’URL du site, les redirections autorisées, les e-mails/OTP et le modèle d’invitation.

## Migrations Supabase — à faire avant les tests métier

1. Utilisez un projet Supabase de développement et faites une sauvegarde avant tout changement de schéma.
2. Exécutez les 14 fichiers de `supabase/migrations/` dans l’ordre numérique, de `001_initial_schema.sql` à `014_management_reports_asset_integration.sql`.
3. Contrôlez chaque migration au fur et à mesure. Arrêtez-vous au premier échec et examinez l’état de la base ; ne relancez pas aveuglément une migration partiellement exécutée.
4. Vérifiez les politiques RLS, les droits d’exécution des fonctions SQL et les trois profils : administrateur principal, observateur et modification.
5. Vérifiez que l’adresse `minnhindje@gmail.com` est bien confirmée et reconnue comme administrateur principal. Ne donnez jamais le rôle admin depuis un champ public de formulaire.
6. Testez les inscriptions, dossiers élèves, frais/échéances, concessions, encaissements, annulations, dépenses, transferts, achats, réceptions, inventaire, maintenance et rapports avant toute donnée réelle.

## Déploiement par le terminal (alternative)

Sur un poste où Node.js 20.9 ou plus récent, npm, un accès réseau et la CLI Vercel sont disponibles :

```bash
npm install
npm run test:release
npm run preflight
npm run typecheck
npm run build
npx vercel
```

Vérifiez la préproduction avant d’utiliser `npx vercel --prod`. N’exécutez pas le déploiement de production tant que `typecheck`, `build`, les migrations et les tests fonctionnels ne sont pas concluants.

## Contrôles locaux déjà disponibles

```bash
npm run test:release
npm run preflight
```

Ces commandes ne nécessitent pas de connexion Supabase mais ne remplacent pas le build Next.js, les tests d’intégration SQL/RLS ou les tests du navigateur.
