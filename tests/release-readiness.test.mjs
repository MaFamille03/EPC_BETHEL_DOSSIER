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
  assert.equal(files.length, 18);
  assert.deepEqual(files.map((name) => Number(name.slice(0, 3))), Array.from({ length: 18 }, (_, i) => i + 1));
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
  assert.match(source, /section!==['\"]eleves['\"]&&<div className=['\"]metric-strip['\"]/);
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
  assert.match(modulePage, /!isReadOnly&&connected&&!\(section==='scolarite'&&concessionView\)/);
  assert.match(modulePage, /Aucune donnée réelle chargée/);
});


test('la version courante et les guides d’installation sont cohérents', () => {
  const pkg = JSON.parse(read('package.json'));
  assert.equal(pkg.version, '1.13.0');
  assert.match(read('README.md'), /\*\*Version courante :\*\*\s*1\.13\.0/);
  assert.match(read('INSTALLATION_RAPIDE.txt'), /VERSION 1\.13\.0/);
  assert.match(read('CHANGELOG.md'), /^## 1\.13\.0/m);
  assert.match(read('RAPPORT_ETAPE_9_COHERENCE.md'), /\*\*Version contrôlée :\*\*\s*1\.9\.4/);
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

test('le guide de déploiement Notes exige une migration 018 et des essais en préproduction', () => {
  const guide = read('ETAPE_10_NOTES_BULLETINS.md');
  assert.match(guide, /018_notes_bulletins_workflows\.sql/);
  assert.match(guide, /préproduction/);
  assert.match(guide, /Les notes manquantes et les absences ne sont pas automatiquement converties en zéro/);
});

test('le nombre de tests documenté correspond à la suite de pré-livraison', () => {
  const testSource = read('tests/release-readiness.test.mjs');
  const count = (testSource.match(/^test\(/gm) || []).length;
  assert.equal(count, 23, 'la suite de contrôle doit contenir exactement 23 tests');
  assert.match(read('README.md'), /23 tests hors ligne/);
  assert.match(read('CHANGELOG.md'), /23 tests hors ligne/);
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
