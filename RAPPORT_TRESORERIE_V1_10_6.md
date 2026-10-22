# EPC BETHEL — Rapport de finalisation du module Trésorerie (V1.10.6)

## Travaux intégrés depuis la V1.10.5

- Conservation des cinq rubriques principales : A. Situation globale ; B. Caisse et Mobile Money ; C. Banque ; D. Transferts internes ; E. Journal de trésorerie.
- Ajout du parcours de clôture journalière pour caisse et Mobile Money : calcul du solde théorique à partir des mouvements validés, saisie du montant compté, calcul de l'écart, justification obligatoire en cas d'écart et historique des clôtures.
- Ajout d'une table `cash_daily_closures` append-only : une clôture ne peut pas être modifiée ou supprimée par les utilisateurs authentifiés. Une seconde clôture pour le même compte et la même date est refusée.
- Ajout de l'import CSV de relevés bancaires, sur un compte bancaire choisi. Colonnes acceptées : Date au format AAAA-MM-JJ, Libellé, Débit, Crédit ; Référence facultative. Les lignes importées ne créent pas de mouvements de trésorerie.
- Ajout du rapprochement manuel d'une ligne de relevé avec un mouvement validé, avec contrôle du compte, du sens et du montant avant création du lien de rapprochement.
- Le rapprochement bancaire ne modifie ni les mouvements ni les soldes. Les lignes non rapprochées restent visibles.
- Version du paquet mise à jour en 1.10.6 ; contrôle de pré-livraison actualisé pour 17 migrations.

## Migration Supabase requise

Appliquer `supabase/migrations/017_treasury_closures.sql` après les migrations 001 à 016. Cette migration ajoute la table de clôture et ses politiques RLS sans supprimer ni réinitialiser de données existantes. La migration 016 reste nécessaire pour le type de compte `mobile_money`.

## Contrôles effectués

- `node scripts/preflight-check.mjs` : contrôle structurel attendu à 11 réussis, 1 avertissement et 0 échec.
- `node --test tests/release-readiness.test.mjs` : 19 tests réussis, 0 échec.
- `npm install --ignore-scripts --no-audit --no-fund` : non terminé dans le délai disponible ; typecheck et build restent donc non confirmés.
- Aucun accès au projet Supabase réel n'a été effectué. Les imports de relevés, règles RLS, écritures SQL et rapprochements doivent être testés dans un environnement Supabase de préproduction.
- Le build Next.js et le typecheck TypeScript ne sont pas déclarés réussis ici, car les dépendances du projet n'ont pas été installées dans cet environnement.

## Limites à connaître avant production

- L'import CSV attend une date `AAAA-MM-JJ` et des montants entiers en FCFA ; il ne traite pas les formats propriétaires de banque, les PDF, les fichiers Excel ou les dates locales `JJ/MM/AAAA`.
- Le rapprochement proposé est manuel et exact sur le compte, le sens et le montant. Il ne réalise pas d'appariement automatique ni de gestion avancée des frais bancaires ou des correspondances partielles.
- La clôture utilise les mouvements disponibles chargés dans l'interface (jusqu'à 1 000 mouvements). Pour un historique supérieur, il faut un calcul SQL dédié côté serveur avant la mise en production.
- La création et la désactivation des comptes de trésorerie restent à gérer par le parcours d'administration existant. Les politiques Supabase demeurent l'autorité finale pour les droits.
- Ne pas déployer en production avant d'avoir exécuté la migration 017, confirmé le build et le typecheck, puis testé les workflows avec les rôles réels sur une base de préproduction.
