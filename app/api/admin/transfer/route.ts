import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { getSupabaseServerConfig } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  const authorization = request.headers.get('authorization') || '';
  const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  if (!token) return NextResponse.json({ error: 'Authentification requise.' }, { status: 401 });

  let body: { newAdminUserId?: unknown; confirmation?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Les informations envoyées sont invalides.' }, { status: 400 });
  }

  const newAdminUserId = typeof body.newAdminUserId === 'string' ? body.newAdminUserId.trim() : '';
  const confirmation = typeof body.confirmation === 'string' ? body.confirmation.trim() : '';
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(newAdminUserId)) {
    return NextResponse.json({ error: 'Sélectionnez un compte utilisateur valide.' }, { status: 400 });
  }
  if (confirmation !== 'TRANSFERER') {
    return NextResponse.json({ error: 'Saisissez TRANSFERER pour confirmer le changement d’administrateur.' }, { status: 400 });
  }

  const { url, publicKey } = getSupabaseServerConfig();
  if (!url || !publicKey) {
    return NextResponse.json({ error: 'La configuration Supabase serveur est incomplète.' }, { status: 503 });
  }

  const supabase = createClient(url, publicKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  if (authError || !authData.user) {
    return NextResponse.json({ error: 'Session invalide. Reconnectez-vous.' }, { status: 401 });
  }

  const { error } = await supabase.rpc('transfer_epc_admin', {
    p_new_admin_user_id: newAdminUserId,
  });
  if (error) {
    const message = error.message || 'Le transfert n’a pas pu être effectué.';
    const status = /42501|permission|administrateur actif|accès réservé/i.test(message) ? 403
      : /22023|introuvable|actif|sélectionnez/i.test(message) ? 400 : 500;
    return NextResponse.json({ error: status === 500 ? 'Le transfert n’a pas pu être effectué. Vérifiez que la migration 026 a été appliquée, puis réessayez.' : message }, { status });
  }

  return NextResponse.json({ ok: true, message: 'Le rôle administrateur a été transféré. Votre compte conserve le niveau Modification.' }, { headers: { 'Cache-Control': 'no-store' } });
}
