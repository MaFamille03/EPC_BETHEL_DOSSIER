# Checklist de mise en service EPC BETHEL

## Configuration
- [ ] Vérifier que les variables Supabase et `NEXT_PUBLIC_SITE_URL` sont déjà définies dans Vercel pour les bons environnements.
- [ ] Confirmer que les clés privées Supabase restent côté serveur et ne figurent pas dans Git.
- [ ] Vérifier les URL de redirection et la confirmation des e-mails dans Supabase Auth.
- [ ] Vérifier le profil Administrateur actif après connexion.

## Base de données
- [ ] Effectuer une sauvegarde Supabase avant toute migration.
- [ ] Vérifier le statut réel des migrations déjà appliquées.
- [ ] Appliquer uniquement les migrations manquantes dans l’ordre. Pour une base déjà à 025, appliquer la migration 026 après validation en préproduction.
- [ ] Ne pas exécuter `supabase/setup/INSTALLATION_COMPLETE.sql` sur une base existante : ce script est réservé à une base vide.

## Sécurité et rôles
- [ ] Tester Observateur (lecture seule) et Modification (gestion des données autorisées).
- [ ] Tester les invitations et la confirmation de l’adresse e-mail.
- [ ] Tester le transfert administrateur vers un compte actif et confirmé.
- [ ] Vérifier que l’ancien administrateur devient Modification et est déconnecté après le transfert.
- [ ] Vérifier qu’un utilisateur ordinaire ne peut pas s’attribuer le rôle Administrateur.

## Fonctionnel et livraison
- [ ] Tester les dossiers élèves, inscriptions, frais, échéances, paiements et reçus.
- [ ] Tester les annulations et corrections de mouvements de trésorerie.
- [ ] Tester les notes, bulletins, achats, patrimoine et rapports.
- [ ] Lancer `npm run test:release`, `npm run preflight`, `npm run typecheck` et `npm run build`.
- [ ] Réaliser les tests complets sur un environnement de préproduction avant les données réelles.
