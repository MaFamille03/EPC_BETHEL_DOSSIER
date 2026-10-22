import { NextRequest, NextResponse } from 'next/server';
import { timingSafeEqual } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

export const dynamic = 'force-dynamic';

const PRIMARY_ADMIN_EMAIL = 'minnhindje@gmail.com';

function sameSecret(received: string, expected: string) {
  const receivedBuffer = Buffer.from(received, 'utf8');
  const expectedBuffer = Buffer.from(expected, 'utf8');
  return receivedBuffer.length === expectedBuffer.length && timingSafeEqual(receivedBuffer, expectedBuffer);
}

export async function POST(request: NextRequest) {
  let body: { code?: unknown; email?: unknown; fullName?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Les informations envoyées sont invalides.' }, { status: 400 });
  }

  const expectedCode = process.env.EPC_BETHEL_REGISTRATION_CODE?.trim() || '';
  if (!expectedCode || expectedCode.length < 24) {
    return NextResponse.json(
      { error: 'La création de compte est désactivée : configurez EPC_BETHEL_REGISTRATION_CODE côté serveur avec au moins 24 caractères aléatoires.' },
      { status: 503 },
    );
  }

  const code = typeof body.code === 'string' ? body.code.trim() : '';
  if (!code || !sameSecret(code, expectedCode)) {
    return NextResponse.json({ error: 'Code de sécurité incorrect. Demandez le code à l’administrateur.' }, { status: 403 });
  }

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const fullName = typeof body.fullName === 'string' ? body.fullName.trim() : '';
  if (!email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return NextResponse.json({ error: 'Adresse e-mail invalide.' }, { status: 400 });
  }
  if (!fullName || fullName.length > 120) {
    return NextResponse.json({ error: 'Le nom complet est obligatoire (120 caractères maximum).' }, { status: 400 });
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || (process.env.NODE_ENV !== 'production' ? request.nextUrl.origin : '');
  if (!url || !serviceKey || !siteUrl) {
    return NextResponse.json({ error: 'Configuration serveur incomplète : vérifiez Supabase, la clé de service et NEXT_PUBLIC_SITE_URL.' }, { status: 503 });
  }

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Une invitation confirme la propriété de la boîte e-mail. Ne jamais marquer une
  // adresse comme vérifiée sans que son propriétaire ait suivi le lien reçu par e-mail.
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { full_name: fullName },
    redirectTo: new URL('/login', siteUrl).toString(),
  });

  if (error || !data.user) {
    const msg = error?.message.toLowerCase() || '';
    if (msg.includes('already') || msg.includes('registered') || msg.includes('exists')) {
      return NextResponse.json({ error: 'Cette adresse e-mail possède déjà un compte. Connectez-vous avec un code e-mail.' }, { status: 409 });
    }
    return NextResponse.json({ error: 'L’invitation n’a pas pu être envoyée. Vérifiez la configuration e-mail de Supabase.' }, { status: 400 });
  }

  // Le trigger de la migration 011 crée le profil. Tous les comptes non principaux
  // commencent en lecture seule ; les permissions se changent ensuite dans Utilisateurs.
  const role = email === PRIMARY_ADMIN_EMAIL ? 'admin' : 'observateur';
  const { error: profileError } = await admin.from('profiles').upsert(
    { id: data.user.id, full_name: fullName, role, is_active: true },
    { onConflict: 'id' },
  );
  if (profileError) {
    // Le profil de l’administrateur principal est volontairement non supprimable ;
    // pour les autres rôles, retire le profil créé par le trigger avant le compte Auth.
    if (role !== 'admin') {
      await admin.from('profiles').delete().eq('id', data.user.id);
      await admin.auth.admin.deleteUser(data.user.id);
    }
    return NextResponse.json({ error: 'Le profil n’a pas pu être initialisé. Appliquez les migrations de sécurité puis réessayez.' }, { status: 500 });
  }

  return NextResponse.json({
    ok: true,
    email,
    role,
    message: 'Un e-mail de confirmation a été envoyé. Ouvrez le lien reçu avant de vous connecter avec votre code temporaire.',
  }, { status: 201 });
}
