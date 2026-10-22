import { NextRequest, NextResponse } from 'next/server';
import { createHash, randomBytes } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

export const dynamic = 'force-dynamic';
const PRIMARY = 'minnhindje@gmail.com';
function serverClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error('Configuration serveur Supabase incomplète.');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
async function requirePrimary(req: NextRequest) {
  const token = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) throw new Error('Authentification requise.');
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) throw new Error('Configuration Supabase incomplète.');
  const auth = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: { user }, error } = await auth.auth.getUser(token);
  if (error || !user) throw new Error('Session invalide.');
  if (user.email?.toLowerCase() !== PRIMARY) throw new Error('Accès réservé à l’administrateur principal.');
  const db = serverClient();
  const { data: profile } = await db.from('profiles').select('role,is_active').eq('id', user.id).maybeSingle();
  if (!profile || profile.role !== 'admin' || !profile.is_active) throw new Error('Profil administrateur principal inactif.');
  return { user, db };
}
function errorResponse(error: unknown) {
  const message = error instanceof Error ? error.message : 'Erreur serveur.';
  const status = message.includes('réservé') ? 403 : message.includes('Authentification') || message.includes('Session') ? 401 : 500;
  return NextResponse.json({ error: message }, { status, headers: { 'Cache-Control': 'no-store' } });
}
export async function GET(req: NextRequest) {
  try {
    const email = (req.nextUrl.searchParams.get('email') || '').trim().toLowerCase();
    const db = serverClient();
    const { data, error } = await db.from('admin_access_code').select('target_email,code_hash').eq('singleton', true).maybeSingle();
    if (error) throw new Error('Lecture de la configuration du code impossible. Appliquez la migration 015.');
    if (email) return NextResponse.json({ requiresCode: !!data && data.target_email === email }, { headers: { 'Cache-Control': 'no-store' } });
    const { user } = await requirePrimary(req);
    return NextResponse.json({ configured: !!data, targetEmail: data?.target_email || '', updatedAt: null, administrator: user.email }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (e) { return errorResponse(e); }
}
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const action = String(body.action || '');
    const db = serverClient();
    if (action === 'configure') {
      const { user } = await requirePrimary(req);
      const targetEmail = String(body.targetEmail || '').trim().toLowerCase();
      const code = String(body.code || '');
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(targetEmail) || targetEmail.length > 254) return NextResponse.json({ error: 'Adresse e-mail cible invalide.' }, { status: 400 });
      if (targetEmail === PRIMARY) return NextResponse.json({ error: 'L’administrateur principal est déjà protégé par son compte.' }, { status: 400 });
      if (code.length < 12 || code.length > 128) return NextResponse.json({ error: 'Choisissez un code administrateur d’au moins 12 caractères.' }, { status: 400 });
      const salt = randomBytes(24).toString('hex');
      const hash = createHash('sha256').update(`${salt}:${code}`).digest('hex');
      const { error } = await db.from('admin_access_code').upsert({ singleton: true, target_email: targetEmail, code_salt: salt, code_hash: hash, updated_by: user.id, updated_at: new Date().toISOString() }, { onConflict: 'singleton' });
      if (error) throw new Error(`Enregistrement impossible : ${error.message}`);
      return NextResponse.json({ ok: true, targetEmail });
    }
    if (action === 'verify') {
      const email = String(body.email || '').trim().toLowerCase();
      const code = String(body.code || '');
      const { data, error } = await db.from('admin_access_code').select('target_email,code_salt,code_hash').eq('singleton', true).maybeSingle();
      if (error) throw new Error('Vérification du code impossible.');
      const received = createHash('sha256').update(`${data?.code_salt || 'missing'}:${code}`).digest('hex');
      const valid = !!data && email === data.target_email && code.length >= 12 && received === data.code_hash;
      if (!valid) return NextResponse.json({ error: 'Code administrateur incorrect pour cette adresse.' }, { status: 403 });
      return NextResponse.json({ ok: true });
    }
    if (action === 'promote') {
      const token = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
      if (!token) return NextResponse.json({ error: 'Authentification requise.' }, { status: 401 });
      const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
      const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
      const auth = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } });
      const { data: { user }, error: authError } = await auth.auth.getUser(token);
      if (authError || !user?.email) return NextResponse.json({ error: 'Session invalide.' }, { status: 401 });
      const email = user.email.toLowerCase();
      if (email === PRIMARY) return NextResponse.json({ ok: true });
      const code = String(body.code || '');
      const { data, error } = await db.from('admin_access_code').select('target_email,code_salt,code_hash').eq('singleton', true).maybeSingle();
      const received = createHash('sha256').update(`${data?.code_salt || 'missing'}:${code}`).digest('hex');
      if (error || !data || email !== data.target_email || code.length < 12 || received !== data.code_hash) return NextResponse.json({ error: 'Autorisation administrateur invalide.' }, { status: 403 });
      const { error: profileError } = await db.from('profiles').update({ role: 'admin', is_active: true }).eq('id', user.id);
      if (profileError) throw new Error(`Promotion administrateur impossible : ${profileError.message}`);
      return NextResponse.json({ ok: true });
    }
    return NextResponse.json({ error: 'Action inconnue.' }, { status: 400 });
  } catch (e) { return errorResponse(e); }
}
