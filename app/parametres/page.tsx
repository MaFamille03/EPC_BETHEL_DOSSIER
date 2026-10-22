'use client';

import { useCallback, useEffect, useState } from 'react';
import { AppShell } from '@/components/app-shell';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';
import { useEPCAccess } from '@/components/access-context';
import { ClassesManager } from '@/components/classes-manager';
import { SchoolYearsManager } from '@/components/school-years-manager';
import { Building2, Save, RefreshCw, CheckCircle2, AlertCircle, ShieldCheck } from 'lucide-react';

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

  useEffect(() => { void load(); }, [load]);

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

    <SchoolYearsManager />
    <ClassesManager />
  </>;
}

export default function SettingsPage() {
  return <AppShell><SettingsContent /></AppShell>;
}
