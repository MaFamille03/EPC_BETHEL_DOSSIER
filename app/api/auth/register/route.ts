import { NextRequest, NextResponse } from 'next/server';
import { timingSafeEqual } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

export const dynamic = 'force-dynamic';
const PRIMARY_ADMIN_EMAIL = 'minnhindje@gmail.com';
function sameSecret(received: string, expected: string) {
  const a = Buffer.from(received, 'utf8'); const b = Buffer.from(expected, 'utf8');
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function POST(request: NextRequest) {
  let body: { code?: unknown; email?: unknown; fullName?: unknown; password?: unknown };
  try { body = await request.json(); }
  catch { return NextResponse.json({ error: 'Les informations envoyées sont invalides.' }, { status: 400 }); }

  const expectedCode = process.env.EPC_BETHEL_REGISTRATION_CODE?.trim() || '';
  if (expectedCode.length < 24) return NextResponse.json({ error: 'La création de compte est désactivée : configurez EPC_BETHEL_REGISTRATION_CODE côté serveur avec au moins 24 caractères aléatoires.' }, { status: 503 });
  const code = typeof body.code === 'string' ? body.code.trim() : '';
  if (!code || !sameSecret(code, expectedCode)) return NextResponse.json({ error: 'Code administrateur incorrect. Demandez le code d’accès à l’administrateur.' }, { status: 403 });

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const fullName = typeof body.fullName === 'string' ? body.fullName.trim() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  if (!email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return NextResponse.json({ error: 'Adresse e-mail invalide.' }, { status: 400 });
  if (!fullName || fullName.length > 120) return NextResponse.json({ error: 'Le nom complet est obligatoire (120 caractères maximum).' }, { status: 400 });
  if (password.length < 10 || password.length > 128) return NextResponse.json({ error: 'Le mot de passe doit contenir entre 10 et 128 caractères.' }, { status: 400 });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) return NextResponse.json({ error: 'Configuration serveur incomplète : vérifiez Supabase et SUPABASE_SERVICE_ROLE_KEY dans Vercel.' }, { status: 503 });

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data, error } = await admin.auth.admin.createUser({
    email, password, email_confirm: true, user_metadata: { full_name: fullName },
  });
  if (error || !data.user) {
    const msg = error?.message.toLowerCase() || '';
    if (msg.includes('already') || msg.includes('registered') || msg.includes('exists')) return NextResponse.json({ error: 'Cette adresse possède déjà un compte. Utilisez la connexion ou « Mot de passe oublié ». ' }, { status: 409 });
    return NextResponse.json({ error: 'La création du compte a échoué. Vérifiez les journaux Supabase Auth.' }, { status: 400 });
  }

  const role = email === PRIMARY_ADMIN_EMAIL ? 'admin' : 'observateur';
  const { error: profileError } = await admin.from('profiles').upsert({
    id: data.user.id, full_name: fullName, role, is_active: true,
  }, { onConflict: 'id' });
  if (profileError) {
    // Supprime le compte fraîchement créé pour éviter un utilisateur sans profil utilisable.
    await admin.auth.admin.deleteUser(data.user.id);
    return NextResponse.json({ error: 'Le profil applicatif n’a pas pu être initialisé. Vérifiez les migrations de sécurité.' }, { status: 500 });
  }
  return NextResponse.json({ ok: true, email, role, message: 'Compte créé. Connectez-vous avec votre adresse e-mail et votre mot de passe.' }, { status: 201 });
}
