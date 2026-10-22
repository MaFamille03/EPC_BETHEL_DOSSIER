'use client';

import { useCallback, useEffect, useState } from 'react';
import { AppShell } from '@/components/app-shell';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';
import { useEPCAccess } from '@/components/access-context';
import { ClassesManager } from '@/components/classes-manager';
import { SchoolYearsManager } from '@/components/school-years-manager';
import { Building2, Save, RefreshCw, CheckCircle2, AlertCircle, ShieldCheck, KeyRound } from 'lucide-react';

type SchoolSettings = { school_name: string; phone: string; email: string; address: string };
const initialSchool: SchoolSettings = {
  school_name: 'EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY',
  phone: '', email: '', address: '',
};

function SettingsContent() {
  const { isReadOnly } = useEPCAccess();
  const [school, setSchool] = useState<SchoolSettings>(initialSchool);
  const [loading, setLoading] = useState(false);
  const [savingSchool, setSavingSchool] = useState(false);
  const [adminTargetEmail, setAdminTargetEmail] = useState('');
  const [adminAccessCode, setAdminAccessCode] = useState('');
  const [adminCodeConfigured, setAdminCodeConfigured] = useState(false);
  const [isPrimaryAdmin, setIsPrimaryAdmin] = useState(false);
  const [savingAdminCode, setSavingAdminCode] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const connected = isSupabaseConfigured();

  const load = useCallback(async () => {
    const client = supabase();
    if (!client) { setError('Configurez Supabase pour enregistrer les paramètres réels.'); return; }
    setLoading(true); setError('');
    const { data, error: queryError } = await client.from('school_settings')
      .select('school_name,phone,email,address').order('created_at').limit(1).maybeSingle();
    if (queryError) setError(`Chargement impossible : ${queryError.message}`);
    else if (data) setSchool({
      school_name: data.school_name || '', phone: data.phone || '',
      email: data.email || '', address: data.address || '',
    });
    setLoading(false);
  }, []);

  useEffect(() => {
    void load();
    const client = supabase();
    if (client) void (async () => {
      const { data: { session } } = await client.auth.getSession();
      if (!session) return;
      setIsPrimaryAdmin(session.user.email?.toLowerCase() === 'minnhindje@gmail.com');
      const response = await fetch('/api/admin/admin-access-code', { headers: { Authorization: `Bearer ${session.access_token}` }, cache: 'no-store' });
      if (response.ok) { const data = await response.json(); setAdminCodeConfigured(!!data.configured); setAdminTargetEmail(data.targetEmail || ''); }
    })();
  }, [load]);

  async function saveAdminAccessCode(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(''); setNotice('');
    const client = supabase(); if (!client) { setError('Supabase n’est pas configuré.'); return; }
    const { data: { session } } = await client.auth.getSession();
    if (!session) { setError('Reconnectez-vous avec le compte administrateur principal.'); return; }
    setSavingAdminCode(true);
    const response = await fetch('/api/admin/admin-access-code', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}` }, body: JSON.stringify({ action: 'configure', targetEmail: adminTargetEmail, code: adminAccessCode }) });
    const result = await response.json().catch(() => ({})); setSavingAdminCode(false);
    if (!response.ok) { setError(result.error || 'Impossible d’enregistrer le code administrateur.'); return; }
    setAdminCodeConfigured(true); setAdminAccessCode(''); setNotice(`Code administrateur configuré pour ${result.targetEmail}.`);
  }

  async function saveSchool(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const client = supabase();
    if (!client) { setError('Supabase n’est pas configuré.'); return; }
    setSavingSchool(true); setNotice(''); setError('');
    const { error: saveError } = await client.rpc('save_school_settings', {
      p_school_name: school.school_name,
      p_phone: school.phone || null,
      p_email: school.email || null,
      p_address: school.address || null,
    });
    setSavingSchool(false);
    if (saveError) { setError(`Enregistrement impossible : ${saveError.message}`); return; }
    setNotice('Coordonnées de l’établissement enregistrées.');
  }

  return <>
    <div className="page-heading">
      <div><div className="eyebrow">ADMINISTRATION</div><h1>Paramètres de l’établissement</h1><p>Gérez les coordonnées officielles, les années scolaires et les classes.</p></div>
      <button type="button" className="button button-secondary" onClick={() => void load()} disabled={loading}><RefreshCw size={16}/> Actualiser</button>
    </div>
    {!connected && <div className="inline-notice"><ShieldCheck size={16}/> Mode aperçu : les modifications ne seront pas conservées sans Supabase.</div>}
    {notice && <div className="inline-notice"><CheckCircle2 size={16}/>{notice}</div>}
    {error && <div className="inline-notice"><AlertCircle size={16}/>{error}</div>}

    <section className="panel settings-panel">
      <div className="panel-heading"><div><h2><Building2 size={19}/> Identité de l’établissement</h2><p>Ces informations peuvent apparaître sur les reçus et les rapports.</p></div></div>
      <form className="settings-form" onSubmit={saveSchool}>
        <label className="form-field"><span>Nom officiel *</span><input required maxLength={180} disabled={isReadOnly} value={school.school_name} onChange={e => setSchool({ ...school, school_name: e.target.value })}/></label>
        <div className="settings-fields-grid">
          <label className="form-field"><span>Téléphone</span><input disabled={isReadOnly} value={school.phone} onChange={e => setSchool({ ...school, phone: e.target.value })} placeholder="+225…"/></label>
          <label className="form-field"><span>Adresse e-mail</span><input type="email" disabled={isReadOnly} value={school.email} onChange={e => setSchool({ ...school, email: e.target.value })} placeholder="contact@epcbethel.ci"/></label>
        </div>
        <label className="form-field"><span>Adresse physique</span><textarea rows={2} disabled={isReadOnly} value={school.address} onChange={e => setSchool({ ...school, address: e.target.value })} placeholder="Adresse de l’établissement"/></label>
        {!isReadOnly && <button type="submit" className="button button-primary" disabled={savingSchool || !connected}><Save size={16}/>{savingSchool ? 'Enregistrement…' : 'Enregistrer les coordonnées'}</button>}
        {isReadOnly && <p className="form-footnote">Votre niveau d’accès permet de consulter les paramètres, mais pas de les modifier.</p>}
      </form>
    </section>

    {isPrimaryAdmin && !isReadOnly && <section className="panel settings-panel admin-code-panel">
      <div className="panel-heading"><div><h2><KeyRound size={19}/> Accès d’un administrateur supplémentaire</h2><p>Réservé au compte principal minnhindje@gmail.com. Le code est stocké sous forme de hachage et ne peut pas être relu après enregistrement.</p></div></div>
      <form className="settings-form" onSubmit={saveAdminAccessCode}>
        <label className="form-field"><span>Adresse e-mail autorisée à devenir administrateur *</span><input type="email" required maxLength={254} value={adminTargetEmail} onChange={e => setAdminTargetEmail(e.target.value)} placeholder="autre.administrateur@exemple.com" /></label>
        <label className="form-field"><span>{adminCodeConfigured ? 'Nouveau code administrateur (remplacement)' : 'Créer le code administrateur'} *</span><input type="password" required minLength={12} maxLength={128} autoComplete="new-password" value={adminAccessCode} onChange={e => setAdminAccessCode(e.target.value)} placeholder="Au moins 12 caractères" /></label>
        <p className="form-footnote">L’adresse indiquée devra confirmer sa boîte e-mail avec le code temporaire habituel et saisir ce code administrateur pour obtenir le rôle administrateur. Toute modification remplace le code et l’adresse précédents.</p>
        <button type="submit" className="button button-primary" disabled={savingAdminCode || !connected}><ShieldCheck size={16}/>{savingAdminCode ? 'Enregistrement…' : 'Enregistrer le code administrateur'}</button>
      </form>
    </section>}

    <SchoolYearsManager />
    <ClassesManager />
  </>;
}

export default function SettingsPage() {
  return <AppShell><SettingsContent /></AppShell>;
}
