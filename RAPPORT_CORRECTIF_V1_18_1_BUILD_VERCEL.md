# Correctif V1.18.1 — build Vercel

## Erreur résolue

Le build Next.js échouait dans `components/treasury-page.tsx` sur une comparaison TypeScript impossible entre `mode === 'bank'` (condition extérieure du formulaire) et `mode === 'cash-mobile-money'` (condition imbriquée dans ce formulaire).

## Correction

- Le formulaire de création de compte est explicitement réservé à la rubrique Banque.
- Le choix « Caisse physique / Portefeuille Mobile Money » et le champ fournisseur Mobile Money ont été retirés de ce formulaire : la caisse utilise un registre unique, avec les espèces, Orange Money, Wave et Moov Money comme moyens de paiement.
- Le validateur refuse toute création de compte hors du mode Banque et le RPC reçoit explicitement `p_kind: 'bank'`.
- Aucune migration SQL n’est nécessaire pour ce correctif.

## Contrôles

- `npm run test:release` : 36 réussis sur 36.
- `npm run preflight` : 11 contrôles réussis, 0 échec, 1 avertissement (`package-lock.json` absent).
- Syntaxe TSX : vérifiée par transpilation isolée.
- Build Next.js complet : non validé ici faute de dépendances installées ; relancer `npm run build` sur Vercel.
