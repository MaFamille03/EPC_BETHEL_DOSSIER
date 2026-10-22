#!/usr/bin/env node
/**
 * Vérifications locales sans accès Supabase ni installation de dépendances.
 * Ne remplace ni `npm run typecheck`, ni `npm run build`, ni les tests RLS.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const failures = [];
const warnings = [];
const passes = [];
const pass = (message) => passes.push(message);
const fail = (message) => failures.push(message);
const warn = (message) => warnings.push(message);
const exists = (p) => fs.existsSync(path.join(root, p));
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

function walk(dir) {
  const result = [];
  for (const entry of fs.readdirSync(path.join(root, dir), { withFileTypes: true })) {
    if (['node_modules', '.next', '.git'].includes(entry.name)) continue;
    const relative = path.posix.join(dir.replaceAll(path.sep, '/'), entry.name);
    if (entry.isDirectory()) result.push(...walk(relative));
    else result.push(relative);
  }
  return result;
}

for (const p of [
  'package.json', 'README.md', '.env.example', '.gitignore', 'next.config.ts', 'tsconfig.json',
  'app/page.tsx', 'app/login/page.tsx', 'app/register/page.tsx', 'app/utilisateurs/page.tsx',
  'app/api/auth/register/route.ts', 'app/api/admin/users/route.ts', 'components/app-shell.tsx',
  'lib/supabase.ts', 'supabase/migrations',
]) {
  if (!exists(p)) fail(`Fichier ou dossier requis absent : ${p}`);
}
if (failures.length === 0) pass('Structure minimale du projet présente.');

let pkg;
try {
  pkg = JSON.parse(read('package.json'));
  if (!pkg.scripts?.build || !pkg.scripts?.typecheck) fail('Les scripts build et typecheck doivent être définis.');
  else pass('Scripts de build et de vérification TypeScript déclarés.');
  if (!pkg.dependencies?.next || !pkg.dependencies?.react || !pkg.dependencies?.['@supabase/supabase-js']) {
    fail('Une dépendance principale Next.js, React ou Supabase est absente du package.json.');
  } else pass('Dépendances principales déclarées.');
} catch (error) {
  fail(`package.json illisible : ${error instanceof Error ? error.message : String(error)}`);
}

const envExample = read('.env.example');
for (const key of ['NEXT_PUBLIC_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'EPC_BETHEL_REGISTRATION_CODE']) {
  if (!new RegExp(`^${key}=`, 'm').test(envExample)) fail(`Variable ${key} absente de .env.example.`);
}
if (envExample.includes('YOUR_PROJECT.supabase.co') && !envExample.match(/^SUPABASE_SERVICE_ROLE_KEY=.+$/m) && !envExample.match(/^EPC_BETHEL_REGISTRATION_CODE=.+$/m)) {
  pass('Le fichier d’exemple ne contient pas de clé de service ou de code d’inscription renseigné.');
} else {
  warn('Contrôler manuellement .env.example : il doit contenir uniquement des exemples, jamais de secret réel.');
}
const gitignore = read('.gitignore');
if (/^\.env\*$/m.test(gitignore) && /^!\.env\.example$/m.test(gitignore)) pass('Les fichiers .env sont ignorés, sauf le modèle .env.example.');
else fail('Les règles .gitignore ne protègent pas correctement les fichiers .env.');

const codeFiles = walk('app').concat(walk('components'), walk('lib')).filter((f) => /\.(ts|tsx|js|jsx)$/.test(f));
const missingImports = [];
const rpcCalls = new Set();
const clientServerSecretLeaks = [];
for (const relative of codeFiles) {
  const source = read(relative);
  const importPattern = /(?:from\s*|import\s*)["']([^"']+)["']/g;
  for (const match of source.matchAll(importPattern)) {
    const specifier = match[1];
    if (!specifier.startsWith('.') && !specifier.startsWith('@/')) continue;
    const base = specifier.startsWith('@/') ? path.join(root, specifier.slice(2)) : path.resolve(root, path.dirname(relative), specifier);
    const candidates = [base, ...['.ts', '.tsx', '.js', '.jsx', '.json', '.css'].map((ext) => `${base}${ext}`), path.join(base, 'index.ts'), path.join(base, 'index.tsx')];
    if (!candidates.some((candidate) => fs.existsSync(candidate))) missingImports.push(`${relative}: ${specifier}`);
  }
  for (const match of source.matchAll(/\.rpc\(\s*["']([a-zA-Z0-9_]+)["']/g)) rpcCalls.add(match[1]);
  const clientDirective = /^\s*["']use client["'];/.test(source);
  if (clientDirective && /process\.env\.SUPABASE_SERVICE_ROLE_KEY|import[^\n]*SUPABASE_SERVICE_ROLE_KEY/.test(source)) clientServerSecretLeaks.push(relative);
}
if (missingImports.length) missingImports.forEach((entry) => fail(`Import interne introuvable : ${entry}`));
else pass(`Imports internes présents (${codeFiles.length} fichiers TS/JS parcourus).`);
if (clientServerSecretLeaks.length) clientServerSecretLeaks.forEach((entry) => fail(`Clé de service référencée côté client : ${entry}`));
else pass('Aucune référence à SUPABASE_SERVICE_ROLE_KEY dans un module client.');

const migrationDir = path.join(root, 'supabase/migrations');
let migrations = [];
if (fs.existsSync(migrationDir)) {
  migrations = fs.readdirSync(migrationDir).filter((name) => /^\d{3}_.+\.sql$/.test(name)).sort();
  const sequence = migrations.map((name) => Number(name.slice(0, 3)));
  const expected = Array.from({ length: sequence.length }, (_, index) => index + 1);
  if (JSON.stringify(sequence) === JSON.stringify(expected)) pass(`Migrations numérotées sans trou : ${migrations[0]} à ${migrations.at(-1)} (${migrations.length} fichiers).`);
  else fail(`Séquence des migrations non continue : ${sequence.join(', ')}.`);
  const sqlContents = migrations.map((name) => ({ name, source: fs.readFileSync(path.join(migrationDir, name), 'utf8') }));
  for (const { name, source } of sqlContents) {
    const tags = source.match(/\$[a-zA-Z_0-9]*\$/g) || [];
    const counts = new Map();
    for (const tag of tags) counts.set(tag, (counts.get(tag) || 0) + 1);
    for (const [tag, count] of counts) if (count % 2 !== 0) fail(`${name}: délimiteur ${tag} non apparié.`);
    if (/\bdrop\s+table\b/i.test(source)) warn(`${name}: contient DROP TABLE ; revoir l’impact avant application en production.`);
  }
  const sql = sqlContents.map((item) => item.source).join('\n');
  const createdFunctions = new Set([...sql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-zA-Z0-9_]+)/ig)].map((match) => match[1].toLowerCase()));
  const missingRpcs = [...rpcCalls].filter((name) => !createdFunctions.has(name.toLowerCase()));
  if (missingRpcs.length) missingRpcs.forEach((name) => fail(`RPC appelée par le code mais absente des migrations : ${name}`));
  else pass(`Les ${rpcCalls.size} RPC référencées par l’application sont présentes dans les migrations.`);
  const createdTables = new Set([...sql.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-zA-Z0-9_]+)/ig)].map((match) => match[1].toLowerCase()));
  const tableRefs = new Set(codeFiles.flatMap((relative) => [...read(relative).matchAll(/\.from\(\s*["']([a-zA-Z0-9_]+)["']/g)].map((match) => match[1].toLowerCase())));
  const missingTables = [...tableRefs].filter((name) => !createdTables.has(name));
  if (missingTables.length) missingTables.forEach((name) => fail(`Table référencée par l’application mais absente des migrations : ${name}`));
  else pass(`Les ${tableRefs.size} tables interrogées depuis le code sont présentes dans les migrations.`);
  const securityDefinerBlocks = [...sql.matchAll(/security\s+definer([\s\S]{0,100}?)(?=as\s+\$)/ig)];
  const unsafe = securityDefinerBlocks.filter((match) => !/set\s+search_path\s*=\s*''/i.test(match[1]));
  if (unsafe.length) warn(`${unsafe.length} fonction(s) SECURITY DEFINER méritent une vérification manuelle du search_path.`);
  else pass('Les blocs SECURITY DEFINER analysés définissent un search_path vide.');
} else {
  fail('Dossier de migrations Supabase absent.');
}

const requiredReports = ['RAPPORT_CONTROLE_QUALITE.md', 'ETAPE_6_NOTES.txt'];
for (const p of requiredReports) if (!exists(p)) fail(`Rapport requis absent : ${p}`);
if (exists('package-lock.json')) pass('package-lock.json présent.');
else warn('package-lock.json absent : prévoir npm install sur une machine connectée pour figer les versions avant production.');

console.log('\nEPC BETHEL — CONTRÔLE LOCAL PRÉ-DÉPLOIEMENT');
for (const item of passes) console.log(`PASS  ${item}`);
for (const item of warnings) console.log(`WARN  ${item}`);
for (const item of failures) console.log(`FAIL  ${item}`);
console.log(`\nRésultat : ${passes.length} réussis, ${warnings.length} avertissements, ${failures.length} échecs.`);
console.log('Ce contrôle structurel ne remplace pas le typecheck, le build, l’exécution PostgreSQL/Supabase ou les tests fonctionnels.');
process.exitCode = failures.length ? 1 : 0;
