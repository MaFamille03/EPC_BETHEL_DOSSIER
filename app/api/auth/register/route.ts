import { NextRequest, NextResponse } from 'next/server';
import { scryptSync, timingSafeEqual } from 'node:crypto';
import { createSupabaseServiceClient } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';
const PRIMARY_ADMIN_EMAIL = 'minnhindje@gmail.com';
function verifyRegistrationCode(received: string, stored: string) {
  const [salt, expected] = stored.split(':');
  if (!salt || !expected) return false;
  const actual = scryptSync(received, salt, 64);
  const expectedBuffer = Buffer.from(expected, 'hex');
  return actual.length === expectedBuffer.length && timingSafeEqual(actual, expectedBuffer);
}

export async function POST(request: NextRequest) {
  let body: { code?: unknown };
  try { body = await request.json(); }
  catch { return NextResponse.json({ error: 'Les informations envoyées sont invalides.' }, { status: 400 }); }

  const code = typeof body.code === 'string' ? body.code.trim() : '';
  if (!/^\d{6,8}$/.test(code)) return NextResponse.json({ error: 'Saisissez le code d’accès numérique de 6 à 8 chiffres fourni par l’administrateur.' }, { status: 403 });
  const admin = createSupabaseServiceClient();
  if (!admin) return NextResponse.json({ error: 'Le service est momentanément indisponible. Contactez l’administrateur de l’application.' }, { status: 503 });
  const { data: accessSettings, error: settingsError } = await admin.from('admin_access_settings').select('registration_code_hash').eq('id', true).maybeSingle();
  if (settingsError) return NextResponse.json({ error: 'Impossible de vérifier le code d’accès. Contactez l’administrateur puis réessayez.' }, { status: 503 });
  if (!accessSettings?.registration_code_hash) return NextResponse.json({ error: 'Le code d’accès initial n’est pas encore défini. Connectez-vous avec le compte administrateur principal et définissez-le dans Paramètres → Utilisateurs et autorisations.' }, { status: 503 });
  if (!verifyRegistrationCode(code, accessSettings.registration_code_hash)) return NextResponse.json({ error: 'Code administrateur incorrect. Demandez le code d’accès à l’administrateur.' }, { status: 403 });

  // Ce point de terminaison valide uniquement le code d'inscription.
  // La création du compte est effectuée par supabase.auth.signUp côté client,
  // afin que Supabase envoie son e-mail de confirmation à l'adresse saisie.
  return NextResponse.json({ ok: true, message: 'Code d’accès valide. Vous pouvez créer votre compte ; un e-mail de confirmation sera envoyé.' }, { status: 200 });
}
