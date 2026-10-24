import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

export const dynamic = 'force-dynamic';

type Role = 'admin' | 'observateur' | 'modification';
const editableRoles: Exclude<Role, 'admin'>[] = ['observateur', 'modification'];

function clients(token?: string) {
  const url = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;
  const service = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !anon || !service) {
    throw new Error('Le service est momentanément indisponible. Contactez l’administrateur de l’application.');
  }
  const auth = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: token ? { headers: { Authorization: `Bearer ${token}` } } : undefined,
  });
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  return { auth, admin };
}

async function requireAdmin(req: NextRequest) {
  const header = req.headers.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) throw new Error('Authentification requise.');
  const { auth, admin } = clients(token);
  const { data: { user }, error } = await auth.auth.getUser(token);
  if (error || !user) throw new Error('Session invalide.');
  const { data: profile, error: profileError } = await admin
    .from('profiles').select('id,role,is_active').eq('id', user.id).maybeSingle();
  if (profileError || !profile || profile.role !== 'admin' || !profile.is_active) {
    throw new Error('Accès réservé à un profil Administrateur actif.');
  }
  return { user, admin };
}

function statusFor(message: string) {
  if (message.includes('Accès réservé')) return 403;
  if (message.includes('Authentification') || message.includes('Session invalide')) return 401;
  if (message.includes('n’est pas initialisé')) return 503;
  return 500;
}

export async function GET(req: NextRequest) {
  try {
    const { admin } = await requireAdmin(req);
    const [{ data: profiles, error: profileError }, { data: userList, error: userError }] = await Promise.all([
      admin.from('profiles').select('id,full_name,role,is_active,created_at').order('created_at', { ascending: false }).limit(1000),
      admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
    ]);
    if (profileError || userError) throw new Error(profileError?.message || userError?.message || 'Lecture des comptes impossible.');
    const authById = new Map(userList.users.map(user => [user.id, user]));
    const users = (profiles || []).map(profile => {
      const authUser = authById.get(profile.id);
      return { ...profile, email: authUser?.email || '', email_confirmed: Boolean(authUser?.email_confirmed_at) };
    });
    return NextResponse.json({ users }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Erreur serveur';
    return NextResponse.json({ error: msg }, { status: statusFor(msg), headers: { 'Cache-Control': 'no-store' } });
  }
}

export async function POST(req: NextRequest) {
  try {
    const { admin } = await requireAdmin(req);
    const body = await req.json();
    const email = String(body.email || '').trim().toLowerCase();
    const full_name = String(body.full_name || '').trim();
    // Chaque invitation commence en lecture seule. Le rôle se change ensuite depuis l’administration.
    const role: Role = 'observateur';

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
      return NextResponse.json({ error: 'Adresse e-mail invalide.' }, { status: 400 });
    }
    if (!full_name || full_name.length > 120) {
      return NextResponse.json({ error: 'Le nom complet est obligatoire (120 caractères maximum).' }, { status: 400 });
    }
    const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || (process.env.NODE_ENV !== 'production' ? req.nextUrl.origin : '');
    if (!siteUrl) return NextResponse.json({ error: 'Le service d’invitation n’est pas configuré. Contactez l’administrateur.' }, { status: 503 });
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { full_name },
      redirectTo: new URL('/login', siteUrl).toString(),
    });
    if (error) throw new Error(error.message);
    if (!data.user) throw new Error('Le compte invité n’a pas pu être créé.');

    const { error: profileError } = await admin.from('profiles').upsert(
      { id: data.user.id, full_name, role: 'observateur', is_active: true },
      { onConflict: 'id' },
    );
    if (profileError) throw new Error(`Invitation créée mais profil non enregistré : ${profileError.message}. Contactez l’administrateur de l’établissement.`);
    return NextResponse.json({ ok: true, userId: data.user.id, role: 'observateur' }, { status: 201 });
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Erreur serveur';
    return NextResponse.json({ error: msg }, { status: statusFor(msg) });
  }
}

export async function PATCH(req: NextRequest) {
  try {
    const { user, admin } = await requireAdmin(req);
    const body = await req.json();
    const userId = String(body.userId || '');
    if (!userId) return NextResponse.json({ error: 'Identifiant utilisateur manquant.' }, { status: 400 });
    if (userId === user.id) return NextResponse.json({ error: 'Le compte administrateur ne peut pas être modifié depuis cette interface.' }, { status: 400 });

    const [{ data: targetProfile, error: targetProfileError }, { data: targetAuth, error: targetAuthError }] = await Promise.all([
      admin.from('profiles').select('id,role,is_active').eq('id', userId).maybeSingle(),
      admin.auth.admin.getUserById(userId),
    ]);
    if (targetProfileError || targetAuthError || !targetProfile || !targetAuth.user) {
      return NextResponse.json({ error: 'Utilisateur introuvable.' }, { status: 404 });
    }
    if (targetProfile.role === 'admin') {
      return NextResponse.json({ error: 'Le profil administrateur se gère depuis Paramètres → Profil administrateur.' }, { status: 400 });
    }

    const nextRole = body.role === undefined ? targetProfile.role : body.role;
    const nextActive = body.is_active === undefined ? targetProfile.is_active : body.is_active;
    if (!editableRoles.includes(nextRole as Exclude<Role, 'admin'>)) {
      return NextResponse.json({ error: 'Le niveau d’accès doit être Observateur ou Modification. Le rôle administrateur se gère depuis Paramètres.' }, { status: 400 });
    }
    if (typeof nextActive !== 'boolean') return NextResponse.json({ error: 'État du compte invalide.' }, { status: 400 });

    const { auth } = clients((req.headers.get('authorization') || '').replace(/^Bearer\s+/i, ''));
    const { error: updateError } = await auth.rpc('update_profile_access', {
      p_user_id: userId,
      p_role: nextRole,
      p_is_active: nextActive,
    });
    if (updateError) throw new Error(updateError.message);
    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Erreur serveur';
    return NextResponse.json({ error: msg }, { status: statusFor(msg) });
  }
}
