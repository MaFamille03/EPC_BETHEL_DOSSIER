import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');
const exists = (relative) => fs.existsSync(path.join(root, relative));
const primaryAdmin = 'minnhindje@gmail.com';

function allSourceFiles(relativeDirectories) {
  const files = [];
  for (const relativeDirectory of relativeDirectories) {
    const start = path.join(root, relativeDirectory);
    if (!fs.existsSync(start)) continue;
    const visit = (current) => {
      for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
        const absolute = path.join(current, entry.name);
        if (entry.isDirectory()) visit(absolute);
        else if (/\.(?:ts|tsx|js|jsx)$/.test(entry.name)) files.push(absolute);
      }
    };
    visit(start);
  }
  return files;
}

test('la configuration de paquet expose les commandes requises', () => {
  const pkg = JSON.parse(read('package.json'));
  assert.equal(pkg.private, true);
  assert.ok(pkg.scripts?.build);
  assert.ok(pkg.scripts?.typecheck);
  assert.ok(pkg.scripts?.preflight);
  assert.ok(pkg.scripts?.['test:release']);
  assert.ok(pkg.engines?.node, 'la version minimale de Node.js doit être déclarée');
});

test('les migrations SQL sont présentes et numérotées sans trou', () => {
  const directory = path.join(root, 'supabase/migrations');
  const files = fs.readdirSync(directory).filter((name) => /^\d{3}_.+\.sql$/.test(name)).sort();
  assert.equal(files.length, 24);
  assert.deepEqual(files.map((name) => Number(name.slice(0, 3))), Array.from({ length: 24 }, (_, i) => i + 1));
});

test('les routes serveur nécessaires au parcours des comptes existent', () => {
  assert.ok(exists('app/api/auth/register/route.ts'));
  assert.ok(exists('app/api/admin/users/route.ts'));
  assert.ok(exists('app/api/admin/registration-code/route.ts'));
  assert.ok(exists('supabase/migrations/015_admin_registration_code_settings.sql'));
  const register = read('app/api/auth/register/route.ts');
  const users = read('app/api/admin/users/route.ts');
  assert.match(register, /export\s+async\s+function\s+POST/);
  assert.match(users, /export\s+async\s+function\s+GET/);
  assert.match(users, /export\s+async\s+function\s+POST/);
  assert.match(users, /export\s+async\s+function\s+PATCH/);
});

test('le code d’inscription se configure dans les paramètres et reste haché côté serveur', () => {
  const source = read('app/api/auth/register/route.ts');
  const settingsRoute = read('app/api/admin/registration-code/route.ts');
  const migration = read('supabase/migrations/015_admin_registration_code_settings.sql');
  assert.match(source, /timingSafeEqual/);
  assert.match(source, /registration_code_hash/);
  assert.match(source, /Ce point de terminaison valide uniquement le code d'inscription/);
  assert.match(read('components/auth-screen.tsx'), /signUp/);
  assert.match(settingsRoute, /export\s+async\s+function\s+PUT/);
  assert.match(settingsRoute, /scryptSync/);
  assert.match(settingsRoute, /minnhindje@gmail\.com/);
  assert.match(migration, /enable row level security/i);
});

test('l’adresse principale est cohérente dans les contrôles de sécurité', () => {
  const files = [
    'components/auth-screen.tsx',
    'app/api/admin/users/route.ts',
    'app/utilisateurs/page.tsx',
    'supabase/migrations/011_auth_admin_and_observer_access.sql',
  ];
  for (const file of files) assert.ok(read(file).toLowerCase().includes(primaryAdmin), `${file} doit protéger l’administrateur principal`);
});

test('la connexion par mot de passe vérifie le profil actif et offre la réinitialisation', () => {
  const source = read('components/auth-screen.tsx');
  assert.match(source, /signInWithPassword/);
  assert.match(source, /resetPasswordForEmail/);
  assert.match(source, /profile\.is_active/);
  assert.match(source, /router\.replace\('\/'\)/);
});

test('le profil de sécurité interdit la promotion publique au rôle administrateur', () => {
  const sql = read('supabase/migrations/011_auth_admin_and_observer_access.sql');
  assert.match(sql, /create or replace function public\.update_profile_access/i);
  assert.match(sql, /p_role not in \('observateur'::public\.app_role,'modification'::public\.app_role\)/i);
  assert.match(sql, /guard_epc_profile_insert/);
  assert.match(sql, /guard_epc_profile_delete/);
  assert.match(sql, /set search_path = ''/i);
});

test('les profils observateur et modification sont séparés de l’administration', () => {
  const access = read('components/access-context.tsx');
  const shell = read('components/app-shell.tsx');
  const users = read('app/utilisateurs/page.tsx');
  assert.match(access, /'admin'\s*\|\s*'observateur'\s*\|\s*'modification'/);
  assert.match(access, /role\s*!==\s*'admin'\s*&&\s*role\s*!==\s*'modification'/);
  assert.match(shell, /observateur:\s*\[/);
  assert.match(users, /Lecture seule/);
  assert.match(users, /Modification/);
});

test('aucune clé de service Supabase n’est référencée dans un composant client', () => {
  const files = allSourceFiles(['app', 'components', 'lib']);
  const offenders = [];
  for (const absolute of files) {
    const source = fs.readFileSync(absolute, 'utf8');
    if (/^\s*['"]use client['"];?/m.test(source) && /process\.env\.SUPABASE_SERVICE_ROLE_KEY|import[^\n]*SUPABASE_SERVICE_ROLE_KEY/.test(source)) {
      offenders.push(path.relative(root, absolute));
    }
  }
  assert.deepEqual(offenders, []);
});

test('les exemples de configuration ne contiennent pas de secret réel', () => {
  const env = read('.env.example');
  assert.match(env, /^NEXT_PUBLIC_SUPABASE_URL=https:\/\/YOUR_PROJECT\.supabase\.co$/m);
  assert.match(env, /^SUPABASE_SERVICE_ROLE_KEY=$/m);
  assert.match(env, /^SUPABASE_SERVICE_ROLE_KEY=$/m);
  assert.doesNotMatch(env, /^SUPABASE_SECRET_KEY=.+$/m);
  assert.match(env, /^EPC_BETHEL_REGISTRATION_CODE=$/m);
  assert.ok(!exists('.env.local'));
  assert.ok(!exists('.env.production'));
});

test('les garde-fous financiers et les rapports disposent de leurs migrations', () => {
  const finances = read('supabase/migrations/013_financial_integrity_reporting.sql');
  const reports = read('supabase/migrations/014_management_reports_asset_integration.sql');
  assert.match(finances, /get_financial_overview/i);
  assert.match(finances, /get_school_fee_ledger/i);
  assert.match(reports, /get_management_report_rows/i);
  assert.match(reports, /receive_purchase_order/i);
  assert.match(reports, /create_order_from_request/i);
});

test('la documentation prévient que les tests de préproduction restent obligatoires', () => {
  const readme = read('README.md');
  assert.match(readme, /npm run typecheck/);
  assert.match(readme, /npm run build/);
  assert.match(readme, /de \*\*développement\*\*/i);
  assert.match(readme, /n’est pas certifiée prête pour la production/i);
});


test('le catalogue des modules ne contient pas de dossiers ou mouvements fictifs', () => {
  const modules = read('lib/modules.ts');
  assert.doesNotMatch(modules, /\bdemo\s*:/i);
  assert.doesNotMatch(modules, /Kouassi Grâce Marie|Yao Nathaniel|N’Guessan David/);
  assert.doesNotMatch(modules, /07 08 12 34 56|REC-2026-0182|PAT-0001/);
});

test('les tableaux scolaires démarrent vides et restent vides hors connexion', () => {
  const source = read('components/module-page.tsx');
  assert.match(source, /useState<Row\[]>\(\[\]\)/);
  assert.match(source, /if\(!connected\)\{setRows\(\[\]\);setFeeTotalCount\(0\);setSchoolYear\(null\);return;\}/);
  assert.doesNotMatch(source, /module\?\.demo/);
  assert.ok(exists('components/notes-bulletins-page.tsx'));
  assert.ok(exists('supabase/migrations/016_notes_bulletins.sql'));
  assert.ok(exists('components/bank-reconciliation-page.tsx'));
  assert.ok(exists('supabase/migrations/017_bank_reconciliation_workflow.sql'));
  assert.match(source, /useState\(50\)/);
  assert.match(source, /student-list-pagination/);
  assert.match(source, /section!=='eleves'&&section!=='scolarite'&&<div className=['\"]metric-strip['\"]/);
  const studentImport = read('components/student-import.tsx');
  assert.match(studentImport, /student-template-download/);
  assert.match(studentImport, /Télécharger les erreurs CSV/);
  assert.match(studentImport, /Matricule déjà présent dans la base/);
  assert.match(studentImport, /select\('student_number'\)\.in\('student_number',batch\)/);
  assert.match(source, /async function viewStudentHistory/);
  assert.match(source, /Identité de l’élève/);
  assert.ok(exists('public/modele-importation-eleves-epc-bethel.xlsx'));
});

test('l’absence de profil authentifié est en lecture seule par défaut', () => {
  const access = read('components/access-context.tsx');
  const shell = read('components/app-shell.tsx');
  assert.match(access, /role:\s*null,\s*isReadOnly:\s*true,\s*isAdmin:\s*false/);
  assert.match(access, /role\s*!==\s*'admin'\s*&&\s*role\s*!==\s*'modification'/);
  assert.match(shell, /Boolean\(role\s*&&\s*allowed\[role\]\?\.includes\(i\.key\)\)/);
  assert.match(shell, /router\.replace\('\/login'\)/);
});

test('le mode aperçu explique qu’aucune donnée réelle n’est chargée et bloque les créations scolaires', () => {
  const shell = read('components/app-shell.tsx');
  const modulePage = read('components/module-page.tsx');
  assert.match(shell, /Aucune donnée réelle n’est chargée et les modifications sont désactivées/);
  assert.match(modulePage, /showForm&&!isReadOnly/);
  assert.match(modulePage, /connected&&!isReadOnly&&!concessionView/);
  assert.match(modulePage, /La scolarité et l’inscription\/réinscription peuvent être payées en 1 à 6 versements/);
});


test('Finance scolaire présente les réductions et les échéanciers variables', () => {
  const source = read('components/module-page.tsx');
  const migration = read('supabase/migrations/019_finance_scolaire_reductions_echeanciers.sql');
  const shell = read('components/app-shell.tsx');
  const modules = read('lib/modules.ts');
  assert.match(source, /Gérer les réductions/);
  assert.match(source, /Nombre de versements/);
  assert.match(source, /create_installment_student_charge/);
  assert.match(source, /Finance scolaire.*Enregistrer un paiement/s);
  assert.match(source, /finance-action-layout/);
  assert.match(migration, /cardinality\(p_due_dates\) > 6/);
  assert.match(migration, /p_fee_code not in \('SCOLARITE','INSCRIPTION'\)/);
  assert.match(migration, /get_school_fee_summary/);
  assert.match(migration, /get_school_fee_ledger_filtered/);
  assert.doesNotMatch(shell, /nav-count\">6/);
  assert.match(modules, /versements de 1 à 6 échéances.*réductions accordées/);
  assert.match(source, /Demander une réduction/);
  assert.match(source, /Inscription \/ réinscription/);
  assert.match(source, /Scolarité annuelle/);
  assert.match(read('app/globals.css'), /finance-action-layout \.button\{width:100%;height:44px;min-height:44px/);
  assert.doesNotMatch(read('app/page.tsx'), /échéances et concessions/i);
});

test('le formulaire de création de compte de trésorerie est bancaire et sans branche de caisse impossible', () => {
  const source = read('components/treasury-page.tsx');
  assert.match(source, /showAccountForm && isAdmin && !isReadOnly && mode === 'bank'/);
  assert.match(source, /kindAllowed = mode === 'bank' && accountForm\.kind === 'bank'/);
  assert.doesNotMatch(source, /mode === 'cash-mobile-money' && <label className="form-field"><span>Type de compte \*<\/span>/);
  assert.match(source, /<h2>Nouveau compte bancaire<\/h2>/);
});

test('la version courante et les guides d’installation sont cohérents', () => {
  const pkg = JSON.parse(read('package.json'));
  assert.equal(pkg.version, '1.19.0');
  assert.match(read('README.md'), /\*\*Version courante :\*\*\s*1\.19\.0/);
  assert.match(read('INSTALLATION_RAPIDE.txt'), /VERSION 1\.19\.0/);
  assert.match(read('CHANGELOG.md'), /^## 1\.19\.0/m);
  assert.match(read('RAPPORT_ETAPE_9_COHERENCE.md'), /\*\*Version contrôlée :\*\*\s*1\.9\.4/);
});




test('Finance scolaire regroupe les actions et explique clairement les réductions', () => {
  const source = read('components/module-page.tsx');
  const css = read('app/globals.css');
  assert.match(source, /finance-action-group finance-action-main/);
  assert.match(source, /finance-action-group finance-action-tools/);
  assert.match(source, /Demander une réduction/);
  assert.match(source, /Demande de réduction transmise/);
  assert.match(source, /Total des réductions appliquées/);
  assert.match(css, /finance-action-layout/);
  assert.match(css, /height:42px;min-height:42px/);
});

test('le dossier élève expose les raccourcis Finance scolaire et Notes et bulletins avec présélection', () => {
  const modulePage = read('components/module-page.tsx');
  const notesPage = read('components/notes-bulletins-page.tsx');
  assert.match(modulePage, /className="student-name-link"[\s\S]*viewStudentHistory\(row\)/);
  assert.match(modulePage, /router\.push\(`\/scolarite\?studentQuery=\$\{encodeURIComponent\(studentQuery\)\}`\)/);
  assert.match(modulePage, /router\.push\(`\/notes-bulletins\?studentId=\$\{encodeURIComponent\(student\._id\)\}`\)/);
  assert.match(notesPage, /get\('studentId'\)/);
  assert.match(notesPage, /setSelectedEnrollmentId\(target\.id\)/);
});

test('le module Notes et bulletins expose les parcours primaire et trimestriel', () => {
  const component = read('components/notes-bulletins-page.tsx');
  const migration = read('supabase/migrations/018_notes_bulletins_workflows.sql');
  assert.match(component, /Saisie collective/);
  assert.match(component, /Résultats individuels/);
  assert.match(component, /Bulletins trimestriels/);
  assert.match(component, /Pondération par catégorie/);
  assert.match(component, /window\.print\(\)/);
  assert.match(migration, /create table if not exists public\.school_assessments/);
  assert.match(migration, /create table if not exists public\.school_grade_rules/);
  assert.match(migration, /create table if not exists public\.school_bulletins/);
});

test('les notes distinguent les absences des notes manquantes et gardent un audit', () => {
  const component = read('components/notes-bulletins-page.tsx');
  const migration = read('supabase/migrations/018_notes_bulletins_workflows.sql');
  assert.match(component, /absent_excused/);
  assert.match(component, /absent_unexcused/);
  assert.match(component, /status !== 'missing'/);
  assert.match(migration, /school_grade_audit_write/);
  assert.match(migration, /grade\.updated/);
  assert.match(migration, /student_grades_score_range_check/);
});

test('la migration Notes applique les contrôles RLS et ne crée pas de politique de suppression', () => {
  const migration = read('supabase/migrations/018_notes_bulletins_workflows.sql');
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /school_bulletins_update/);
  assert.match(migration, /school_assessments_update/);
  assert.doesNotMatch(migration, /for delete to authenticated/i);
});


test('Import Excel s’ouvre dans une fenêtre superposée sans déplacer la page', () => {
  const source = read('components/student-import.tsx');
  const css = read('app/globals.css');
  assert.match(source, /onClick=\{\(\) => \{ setError\(''\); setIsImportPanelOpen\(true\); \}\}/);
  assert.match(source, /<ModalPortal>/);
  assert.match(source, /className=\"modal student-import-modal\" role=\"dialog\" aria-modal=\"true\"/);
  assert.match(source, /student-import-toggle-label/);
  assert.match(css, /\.student-import-modal/);
  assert.match(source, /Télécharger le modèle Excel/);
});

test('le guide de déploiement Notes exige une migration 018 et des essais en préproduction', () => {
  const guide = read('ETAPE_10_NOTES_BULLETINS.md');
  assert.match(guide, /018_notes_bulletins_workflows\.sql/);
  assert.match(guide, /préproduction/);
  assert.match(guide, /Les notes manquantes et les absences ne sont pas automatiquement converties en zéro/);
});

test('Finance scolaire explique les versements et garde des boutons uniformes', () => {
  const source = read('components/module-page.tsx');
  const css = read('app/globals.css');
  const migration = read('supabase/migrations/019_finance_scolaire_reductions_echeanciers.sql');
  const packageInfo = JSON.parse(read('package.json'));
  assert.equal(packageInfo.version, '1.19.0');
  assert.match(source, /Demandes de réduction/);
  assert.match(source, /Gérer les réductions/);
  assert.match(source, /Échéancier de \{installmentCount\} versement/);
  assert.match(source, /Nombre de versements/);
  assert.match(source, /create_installment_student_charge/);
  assert.match(migration, /p_fee_code not in \('SCOLARITE','INSCRIPTION'\)/);
  assert.match(migration, /cardinality\(p_due_dates\) > 6/);
  const fixMigration = read('supabase/migrations/020_fix_school_fee_ledger_ambiguity.sql');
  assert.match(fixMigration, /charge_rows\.gross_amount>0 and charge_rows\.amount_due=0/);
  assert.match(fixMigration, /classified\.payment_status=p_payment_status/);
  assert.match(css, /finance-summary-grid\{display:grid;grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/);
  assert.match(css, /finance-action-layout \.button\{width:100%;height:44px;min-height:44px/);
  assert.match(css, /finance-action-layout \.button\{width:100%;height:42px;min-height:42px/);
  assert.match(css, /installment-help/);
  assert.doesNotMatch(source, />\s*Concession(s)?\s*</i);
});

test('les formulaires des trois modules s’ouvrent en fenêtres superposées', () => {
  const modulePage = read('components/module-page.tsx');
  const paymentsPage = read('components/payments-page.tsx');
  const notesPage = read('components/notes-bulletins-page.tsx');
  const settingsPage = read('app/parametres/page.tsx');
  const css = read('app/globals.css');
  assert.match(modulePage, /showForm&&!isReadOnly&&typeof document!=='undefined'&&createPortal/);
  assert.match(modulePage, /showStudentDetail&&studentDetail&&typeof document!=='undefined'&&createPortal/);
  assert.match(modulePage, /showChargeDetail&&selectedCharge&&typeof document!=='undefined'&&createPortal/);
  assert.match(paymentsPage, /showForm&&!isReadOnly&&typeof document!=='undefined'&&createPortal/);
  assert.match(notesPage, /showAssessmentForm && createPortal/);
  assert.match(notesPage, /showGradeEntryForm && selectedAssessment && createPortal/);
  assert.match(notesPage, /showRuleForm && createPortal/);
  assert.match(notesPage, /showSubjectForm && createPortal/);
  assert.match(settingsPage, /showSchoolForm && !isReadOnly && <ModalPortal>/);
  assert.match(settingsPage, /showAdminCodeForm && isAdmin && <ModalPortal>/);
  assert.match(css, /\.modal-backdrop\{position:fixed;inset:0/);
  assert.match(css, /\.notes-form-backdrop\{z-index:140/);
});

test('le nombre de tests documenté correspond à la suite de pré-livraison', () => {
  const testSource = read('tests/release-readiness.test.mjs');
  const count = (testSource.match(/^test\(/gm) || []).length;
  assert.equal(count, 40, 'la suite de contrôle doit contenir exactement 40 tests');
  assert.match(read('README.md'), /40 tests hors ligne/);
  assert.match(read('CHANGELOG.md'), /40 tests hors ligne/);
  assert.match(read('CHANGELOG.md'), /Tests de pré-livraison : 36 réussis sur 36/);
  assert.match(read('ETAPE_10_NOTES_BULLETINS.md'), /23 tests structurels hors ligne/);
  assert.doesNotMatch(read('README.md'), /12 contrôles structurels hors ligne/);
});

test('les commandes de barre supérieure proposent recherche, fermeture et menus du compte', () => {
  const topbar = read('components/topbar-menus.tsx');
  assert.match(topbar, /aria-label="Rechercher un module"/);
  assert.match(topbar, /router\.push/);
  assert.match(topbar, /document\.addEventListener\('pointerdown'/);
  assert.match(topbar, /event\.key === 'Escape'/);
  assert.match(topbar, /Aucune notification disponible/);
  assert.match(topbar, /Gestion des utilisateurs/);
  assert.match(topbar, /void onLogout\(\)/);
});


test('Finance scolaire affiche compteur et pagination près de la recherche, pas sous le tableau', () => {
  const source = read('components/module-page.tsx');
  const css = read('app/globals.css');
  const searchAt = source.indexOf('<div className="table-search">');
  const paginationAt = source.indexOf('className="finance-list-pagination"');
  const tableAt = source.indexOf('<div className="table-scroll"><table>');
  assert.ok(searchAt >= 0 && paginationAt > searchAt && tableAt > paginationAt);
  assert.match(source, /section!=='eleves'&&!\(section==='scolarite'&&!concessionView\)&&<div className="table-footer"/);
  assert.match(css, /\.finance-list-pagination\{display:flex/);
  assert.match(source, /Les soldes sont calculés automatiquement à partir de tous les paiements validés\./);
});


test('les quatre rubriques de trésorerie ont des vues distinctes', () => {
  const treasury = read('components/treasury-page.tsx');
  const route = read('app/[section]/page.tsx');
  const modules = read('lib/modules.ts');
  assert.match(route, /section==='caisse-mobile-money'\?'cash-mobile-money':section==='banque'\?'bank':section==='transferts-internes'\?'transfers':'journal'/);
  assert.match(treasury, /account.kind === 'cash' \|\| account.kind === 'mobile_money'/);
  assert.match(treasury, /transaction.transaction_type === 'transfer'/);
  assert.match(treasury, /Chaque transfert est présenté une seule fois/);
  assert.match(treasury, /if \(mode === 'journal'\) return txs/);
  assert.match(modules, /registre unique de caisse pour les espèces, Orange Money, Wave et Moov Money/);
});

test('le type Mobile Money est migré et la création de comptes est auditée côté SQL', () => {
  const migration = read('supabase/migrations/021_treasury_account_types_and_creation.sql');
  const treasury = read('components/treasury-page.tsx');
  assert.match(migration, /add value if not exists 'mobile_money'/i);
  assert.match(migration, /add column if not exists provider_name/i);
  assert.match(migration, /create or replace function public\.create_cash_account/i);
  assert.match(migration, /has_any_role\(array\['admin'\]::public\.app_role\[\]\)/i);
  assert.match(migration, /insert into public\.audit_logs/i);
  assert.match(migration, /revoke all on function public\.create_cash_account/i);
  assert.match(migration, /grant execute on function public\.create_cash_account/i);
  assert.match(treasury, /client\.rpc\('create_cash_account'/);
  assert.match(treasury, /provider_name/);
});


test('les paiements et dépenses proposent un compte cohérent avec le mode de règlement', () => {
  const payments = read('components/payments-page.tsx');
  const expenses = read('components/expenses-page.tsx');
  const migration = read('supabase/migrations/021_treasury_account_types_and_creation.sql');
  assert.match(payments, /accountsForPaymentMethod/);
  assert.match(payments, /account\.kind==='cash'/);
  assert.match(payments, /register_student_payment_for_fee_with_provider/);
  assert.match(payments, /mobile_money_provider/);
  assert.match(expenses, /accountsForExpenseMethod/);
  assert.match(expenses, /account\.kind==='cash'/);
  assert.match(expenses, /create_expense_with_provider/);
  assert.match(expenses, /mobile_money_provider/);
  assert.match(migration, /payments_account_method_match/);
  assert.match(migration, /expenses_account_method_match/);
  assert.match(migration, /mobile_money/);
});


test('caisse unique utilise les opérateurs Mobile Money comme canaux de paiement', () => {
  const payments = read('components/payments-page.tsx');
  const expenses = read('components/expenses-page.tsx');
  const migration = read('supabase/migrations/022_cash_register_single_ledger_and_controls.sql');
  const treasury = read('components/treasury-page.tsx');
  assert.match(payments, /accountsForPaymentMethod=\(accounts:Option\[\],method:string\)=>\{if\(method==='especes'\|\|method==='mobile_money'\)/);
  assert.match(expenses, /accountsForExpenseMethod=\(accounts:Option\[\],method:string\)=>\{if\(method==='especes'\|\|method==='mobile_money'\)/);
  assert.match(payments, /Orange Money/);
  assert.match(payments, /Wave/);
  assert.match(payments, /Moov Money/);
  assert.match(migration, /L’opérateur est un moyen de paiement, pas un compte séparé/);
  assert.match(migration, /cash_method_balance\(v_channel,v_when,null\)/);
  assert.match(migration, /create or replace function public\.validate_expense/);
  assert.match(treasury, /Caisse théorique en espèces/);
  assert.match(treasury, /Caisse physique réelle/);
});

test('les lignes manuelles de caisse sont ajoutées, modifiables ou supprimables avec trace d’audit', () => {
  const treasury = read('components/treasury-page.tsx');
  const migration = read('supabase/migrations/022_cash_register_single_ledger_and_controls.sql');
  assert.match(treasury, /Ajouter une ligne de caisse/);
  assert.match(treasury, /update_manual_cash_movement/);
  assert.match(treasury, /delete_manual_cash_movement/);
  assert.match(migration, /create or replace function public\.create_manual_cash_movement/);
  assert.match(migration, /create or replace function public\.update_manual_cash_movement/);
  assert.match(migration, /create or replace function public\.delete_manual_cash_movement/);
  assert.match(migration, /motif de modification/);
  assert.match(migration, /motif de suppression est obligatoire/);
  assert.match(migration, /deleted_transaction',to_jsonb\(v_tx\)/);
});


test('la caisse utilise un seul registre avec comptage physique et actions manuelles protégées', () => {
  const treasury = read('components/treasury-page.tsx');
  const migration = read('supabase/migrations/023_cash_register_edit_delete_guardrails.sql');
  const modules = read('lib/modules.ts');
  assert.match(modules, /title: 'Caisse et Mobile Money'/);
  assert.match(treasury, /Caisse théorique en espèces/);
  assert.match(treasury, /Caisse physique réelle/);
  assert.match(treasury, /cash-register-panel-actions/);
  assert.match(treasury, /Ajouter une ligne de caisse/);
  assert.match(treasury, /<th>Référence<\/th><th>Date<\/th><th>Libellé<\/th><th>Moyen de paiement<\/th><th>Entrée<\/th><th>Sortie<\/th><th>Solde<\/th><th>Statut<\/th><th>Actions<\/th>/);
  assert.match(migration, /registre unique de caisse principal/);
  assert.match(migration, /moyen de paiement d’origine/);
  assert.match(migration, /update_manual_cash_movement/);
  assert.match(migration, /delete_manual_cash_movement/);
});


test('la configuration des tarifs respecte la classe, l’année et les échéances', () => {
  const migration = read('supabase/migrations/024_student_fees_tariffs_and_status.sql');
  const manager = read('components/class-fee-tariffs-manager.tsx');
  assert.match(migration, /create table if not exists public\.class_fee_tariffs/i);
  assert.match(migration, /unique \(school_year_id,class_id,fee_category_id\)/i);
  assert.match(migration, /check \(installment_count between 1 and 6\)/i);
  assert.match(migration, /perform public\.apply_class_fee_tariffs\(v_enrollment\)/i);
  assert.match(migration, /if exists\(select 1 from public\.student_charges c/i);
  assert.match(manager, /Échéance \{index \+ 1\}/);
  assert.match(manager, /apply_class_fee_tariffs/);
});

test('les réductions sont ciblées et l’abandon préserve les dettes historiques', () => {
  const migration = read('supabase/migrations/024_student_fees_tariffs_and_status.sql');
  const studentModule = read('components/module-page.tsx');
  assert.match(migration, /request_enrollment_concession_scoped/i);
  assert.match(migration, /fee_category_id uuid references public\.fee_categories/i);
  assert.match(migration, /financial_charges_preserved',true/i);
  assert.match(migration, /create or replace function public\.abandon_school_enrollment/i);
  assert.match(migration, /set status='abandon'/i);
  assert.match(migration, /student\.abandoned/i);
  assert.match(studentModule, /enfant_pasteur/);
  assert.match(studentModule, /reduction_particuliere/);
  assert.match(studentModule, /abandon_school_enrollment/);
});

test('la fiche individuelle des notes permet les trois trimestres et protège les années clôturées', () => {
  const notes = read('components/notes-bulletins-page.tsx');
  const migration = read('supabase/migrations/024_student_fees_tariffs_and_status.sql');
  assert.match(notes, /showStudentDetailNotes/);
  assert.match(notes, /1er trimestre/);
  assert.match(notes, /2e trimestre/);
  assert.match(notes, /3e trimestre/);
  assert.match(notes, /deleteIndividualGrade/);
  assert.match(notes, /saveIndividualGrade/);
  assert.match(migration, /guard_student_grade_mutation/);
  assert.match(migration, /Les notes d’une année scolaire clôturée ne peuvent plus être modifiées/);
  assert.match(migration, /grade\.deleted/);
});
