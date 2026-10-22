import { createClient, type SupabaseClient } from '@supabase/supabase-js';
let client: SupabaseClient | null = null;
function publicSupabaseKey() {
  // Accepte les clés publiques historiques (anon) et les nouvelles publishable keys.
  return process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';
}
export function isSupabaseConfigured() {
  return Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() && publicSupabaseKey().trim());
}
export function supabase() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = publicSupabaseKey().trim();
  if (!url || !key) return null;
  if (!client) client = createClient(url, key);
  return client;
}
