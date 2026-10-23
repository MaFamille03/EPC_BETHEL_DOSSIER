import {
  LayoutDashboard,
  Users,
  GraduationCap,
  Wallet,
  ArrowLeftRight,
  ReceiptText,
  ShoppingCart,
  Package,
  BarChart3,
  Settings,
  ShieldCheck,
  type LucideIcon,
} from 'lucide-react';

export type Module = {
  key: string;
  title: string;
  description: string;
  icon: LucideIcon;
  table?: string;
  columns: string[];
};

export const navigation = [
  {
    label: 'Vue générale',
    items: [
      { key: 'dashboard', title: 'Tableau de bord', icon: LayoutDashboard },
      { key: 'rapports', title: 'Rapports', icon: BarChart3 },
    ],
  },
  {
    label: 'Gestion scolaire',
    items: [
      { key: 'eleves', title: 'Gestion des élèves', icon: Users },
      { key: 'scolarite', title: 'Finance scolaire', icon: ReceiptText },
      { key: 'notes-bulletins', title: 'Notes et bulletins', icon: GraduationCap },
    ],
  },
  {
    label: 'Finances',
    items: [
      { key: 'caisse-mobile-money', title: 'Caisse et comptes Mobile Money', icon: Wallet },
      { key: 'banque', title: 'Banque', icon: Wallet },
      { key: 'transferts-internes', title: 'Transferts internes', icon: ArrowLeftRight },
      { key: 'journal-tresorerie', title: 'Journal de trésorerie (historique)', icon: ReceiptText },
    ],
  },
  {
    label: 'Établissement',
    items: [
      { key: 'patrimoine', title: 'Patrimoine', icon: Package },
    ],
  },
  {
    label: 'Administration',
    items: [
      { key: 'utilisateurs', title: 'Utilisateurs et rôles', icon: ShieldCheck },
      { key: 'parametres', title: 'Paramètres', icon: Settings },
    ],
  },
];

// Ce fichier ne contient volontairement aucun faux dossier d'élève ni mouvement financier.
// Les tableaux affichent uniquement les données chargées depuis le système.
export const modules: Record<string, Module> = {
  'notes-bulletins': {
    key: 'notes-bulletins',
    title: 'Notes et bulletins',
    description: 'Configurez les évaluations, saisissez les notes par classe, consultez les résultats individuels et préparez les bulletins trimestriels.',
    icon: GraduationCap,
    columns: ['Élève', 'Classe', 'Matière', 'Évaluation', 'Note', 'Période'],
  },
  eleves: {
    key: 'eleves',
    title: 'Gestion des élèves',
    description: 'Consultez et gérez les dossiers des élèves de l’établissement.',
    icon: Users,
    table: 'students',
    columns: ['Matricule', 'Nom & prénoms', 'Classe', 'Responsable', 'Téléphone', 'Statut'],
  },
  inscriptions: {
    key: 'inscriptions',
    title: 'Inscriptions',
    description: 'Suivez les inscriptions, réinscriptions et affectations en classe.',
    icon: GraduationCap,
    table: 'enrollments',
    columns: ['Élève', 'Année scolaire', 'Classe', 'Date', 'Type', 'Statut'],
  },
  scolarite: {
    key: 'scolarite',
    title: 'Finance scolaire',
    description: 'Scolarité en six versements, frais d’inscription, frais annexes et concessions.',
    icon: ReceiptText,
    table: 'student_charges',
    columns: ['Élève', 'Nature des frais', 'Montant dû', 'Déjà payé', 'Reste à payer', 'Situation'],
  },
  paiements: {
    key: 'paiements',
    title: 'Encaissements & reçus',
    description: 'Enregistrez les paiements, générez les reçus et suivez les affectations aux frais scolaires.',
    icon: ReceiptText,
    table: 'payments',
    columns: ['Reçu', 'Date', 'Élève', 'Montant', 'Mode', 'Statut'],
  },
  tresorerie: {
    key: 'tresorerie',
    title: 'Trésorerie',
    description: 'Suivez les entrées, sorties, soldes de caisse et mouvements bancaires.',
    icon: Wallet,
    table: 'cash_transactions',
    columns: ['Date', 'Libellé', 'Compte', 'Entrée', 'Sortie', 'Référence'],
  },
  depenses: {
    key: 'depenses',
    title: 'Dépenses',
    description: 'Enregistrez les charges, justificatifs et validations de paiement.',
    icon: ReceiptText,
    table: 'expenses',
    columns: ['Date', 'Désignation', 'Catégorie', 'Bénéficiaire', 'Montant', 'Statut'],
  },
  achats: {
    key: 'achats',
    title: 'Achats & fournisseurs',
    description: 'Centralisez les demandes d’achat, les fournisseurs et les réceptions.',
    icon: ShoppingCart,
    table: 'purchase_requests',
    columns: ['Référence', 'Demande', 'Fournisseur', 'Date', 'Montant estimé', 'Statut'],
  },
  patrimoine: {
    key: 'patrimoine',
    title: 'Patrimoine',
    description: 'Inventaire des biens, équipements, affectations et maintenance.',
    icon: Package,
    table: 'assets',
    columns: ['Code inventaire', 'Désignation', 'Catégorie', 'Localisation', 'Valeur d’achat', 'État'],
  },
  rapports: {
    key: 'rapports',
    title: 'Rapports & exports',
    description: 'Préparez les états de recettes, dépenses, impayés et inventaire.',
    icon: BarChart3,
    columns: ['Rapport', 'Période', 'Dernière mise à jour', 'Format'],
  },
  utilisateurs: {
    key: 'utilisateurs',
    title: 'Utilisateurs & rôles',
    description: 'Gérez les comptes du logiciel et les autorisations par fonction.',
    icon: ShieldCheck,
    table: 'profiles',
    columns: ['Nom complet', 'Adresse e-mail', 'Rôle', 'Accès', 'Statut'],
  },
  parametres: {
    key: 'parametres',
    title: 'Paramètres',
    description: 'Configurez l’année scolaire, les tarifs, les versements et les comptes financiers.',
    icon: Settings,
    columns: ['Paramètre', 'Valeur actuelle', 'Action'],
  },
};

// Les quatre entrées financières partagent le moteur de trésorerie existant.
modules['caisse-mobile-money'] = { ...modules.tresorerie, key: 'caisse-mobile-money', title: 'Caisse et comptes Mobile Money' };
modules.banque = { ...modules.tresorerie, key: 'banque', title: 'Banque' };
modules['transferts-internes'] = { ...modules.tresorerie, key: 'transferts-internes', title: 'Transferts internes' };
modules['journal-tresorerie'] = { ...modules.tresorerie, key: 'journal-tresorerie', title: 'Journal de trésorerie (historique)' };
