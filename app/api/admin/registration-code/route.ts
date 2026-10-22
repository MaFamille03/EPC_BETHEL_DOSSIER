import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { createSupabaseServiceClient, getSupabaseServerConfig } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';
const PRIMARY_ADMIN_EMAIL = 'minnhindje@gmail.com';
function digest(code: string, salt: string) {
  return scryptSync(code, salt, 64).toString('hex');
}
function verify(code: string, stored: string) {
  const [salt, expected] = stored.split(':');
  if (!salt || !expected) return false;
  const actualBuffer = Buffer.from(digest(code, salt), 'hex');
  const expectedBuffer = Buffer.from(expected, 'hex');
  return actualBuffer.length === expectedBuffer.length && timingSafeEqual(actualBuffer, expectedBuffer);
}
async function requirePrimaryAdmin(request: NextRequest) {
  const { url, publicKey } = getSupabaseServerConfig();
  const service = createSupabaseServiceClient();
  if (!url || !publicKey || !service) throw new Error('Configuration serveur manquante : renseignez l’URL Supabase, une clé publique et une clé de service dans Vercel.');
  const authorization = request.headers.get('authorization') || '';
  const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  if (!token) throw new Error('Authentification requise.');
  const auth = createClient(url, publicKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: { user }, error } = await auth.auth.getUser(token);
  if (error || !user) throw new Error('Session invalide. Reconnectez-vous.');
  if (user.email?.trim().toLowerCase() !== PRIMARY_ADMIN_EMAIL) throw new Error('Accès réservé à l’administrateur principal.');
  const { data: profile, error: profileError } = await service.from('profiles').select('role,is_active').eq('id', user.id).maybeSingle();
  if (profileError || profile?.role !== 'admin' || profile.is_active !== true) throw new Error('Le profil administrateur principal n’est pas actif. Vérifiez la migration 011.');
  return { service, user };
}
function errorResponse(error: unknown) {
  const message = error instanceof Error ? error.message : 'Erreur serveur.';
  const status = message.includes('réservé') ? 403 : message.includes('Authentification') || message.includes('Session invalide') ? 401 : message.includes('Configuration serveur') ? 503 : 500;
  return NextResponse.json({ error: message }, { status, headers: { 'Cache-Control': 'no-store' } });
}
export async function GET(request: NextRequest) {
  try {
    const { service } = await requirePrimaryAdmin(request);
    const { data, error } = await service.from('admin_access_settings').select('registration_code_hash,updated_at').eq('id', true).maybeSingle();
    if (error) throw new Error(`Lecture du paramètre impossible : ${error.message}. Vérifiez la migration 015.`);
    return NextResponse.json({ configured: Boolean(data?.registration_code_hash), updatedAt: data?.updated_at || null }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) { return errorResponse(error); }
}
export async function PUT(request: NextRequest) {
  try {
    const { service, user } = await requirePrimaryAdmin(request);
    const body = await request.json();
    const code = typeof body.code === 'string' ? body.code.trim() : '';
    if (!/^\d{6,8}$/.test(code)) return NextResponse.json({ error: 'Le code d’accès doit contenir entre 6 et 8 chiffres.' }, { status: 400 });
    const salt = randomBytes(16).toString('hex');
    const registration_code_hash = `${salt}:${digest(code, salt)}`;
    const { error } = await service.from('admin_access_settings').upsert({ id: true, registration_code_hash, updated_by: user.id, updated_at: new Date().toISOString() }, { onConflict: 'id' });
    if (error) throw new Error(`Enregistrement impossible : ${error.message}. Vérifiez la migration 015.`);
    return NextResponse.json({ ok: true, message: 'Le code d’accès a été enregistré. Il ne sera plus affiché dans les paramètres.' }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) { return errorResponse(error); }
}
