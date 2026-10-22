# EPC BETHEL — Étape 8 : sécurisation du mode aperçu et contrôles de livraison

**Version du paquet :** 1.9.3  
**Statut :** contrôles hors ligne réussis ; installation complète et validation de production non confirmées.

## 1. Corrections livrées

- Suppression des exemples fictifs de noms d'élèves, coordonnées, inscriptions, paiements, achats, dépenses et biens du catalogue des modules.
- Les listes de la gestion scolaire commencent vides et restent vides lorsque Supabase n'est pas configuré. Le registre de frais ne réintroduit plus ses lignes de démonstration hors connexion.
- Les boutons de création des modules scolaires ne sont pas disponibles en mode aperçu.
- La bannière indique explicitement qu'aucune donnée réelle n'est chargée et que les modifications sont désactivées.
- Le contexte d'accès traite toute absence de rôle vérifié comme une situation en lecture seule. En environnement connecté, les menus protégés ne sont affichés que si le rôle est connu ; une erreur de vérification renvoie vers la connexion.
- Le tableau HTML `data-readonly` est cohérent avec ce principe.

## 2. Résultats effectivement exécutés

| Contrôle | Résultat | Portée |
|---|---:|---|
| `npm run test:release` | **16 réussis, 0 échec** | Tests structurels hors ligne, sans Supabase |
| `npm run preflight` | **11 réussis, 0 échec, 1 avertissement** | Structure, imports, secrets, migrations, RPC et tables |
| Analyse syntaxique TypeScript/TSX | **23 fichiers, 0 erreur de syntaxe** | Analyse syntaxique uniquement, pas de vérification des types |
| Recherche des anciennes lignes fictives dans le code d'exécution | Aucune correspondance détectée | `app`, `components`, `lib` |
| Intégrité de l'archive finale | Confirmée | Test ZIP `unzip -t` effectué après création |

L'avertissement de précontrôle concerne l'absence de `package-lock.json`.

## 3. Pourquoi le build n'est pas validé

Une nouvelle tentative de création du lockfile avec `npm install --package-lock-only --ignore-scripts` a échoué avec `EAI_AGAIN registry.npmjs.org`. Les dépendances ne sont donc toujours pas installées dans cet environnement.

Les commandes complètes ont été tentées :

- `npm run typecheck` s'arrête sur des modules et types absents (`next`, `react`, `@supabase/supabase-js`, `@types/node`, etc.). Le résultat ne constitue pas un typecheck réussi et doit être refait après installation correcte.
- `npm run build` échoue avec `next: not found`, car Next.js n'est pas installé.

Je n'ai pas fabriqué manuellement un `package-lock.json` ni marqué ces validations comme réussies.

## 4. Ce qui reste indispensable

1. Sur un poste connecté au registre npm, exécuter `npm install`, conserver le `package-lock.json`, puis passer `npm run test:release`, `npm run preflight`, `npm run typecheck` et `npm run build`.
2. Sur un projet Supabase de développement avec sauvegarde, appliquer les migrations `001` à `014` une par une et arrêter au premier échec SQL.
3. Tester connexion OTP, invitations, compte administrateur `minnhindje@gmail.com`, profils observateur et modification, politiques RLS et appels RPC.
4. Tester les opérations réelles avec données fictives de test : élève, inscription, six échéances, concession, paiement partiel, dépense, transfert de trésorerie, réception d'achat, inventaire, maintenance et rapports.
5. Déployer un Preview Vercel, vérifier les journaux, effectuer les essais sur ordinateur/mobile et documenter le retour arrière avant de décider d'une mise en production.

Cette livraison renforce le mode aperçu et les contrôles statiques. Elle ne constitue pas un déploiement sur le projet Supabase/Vercel réel.
