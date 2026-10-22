'use client';

import { useCallback, useEffect, useState } from 'react';
import { AppShell } from '@/components/app-shell';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';
import { useEPCAccess } from '@/components/access-context';
import { ClassesManager } from '@/components/classes-manager';
import { SchoolYearsManager } from '@/components/school-years-manager';
import { Building2, Save, RefreshCw, CheckCircle2, AlertCircle, ShieldCheck, KeyRound, Eye, EyeOff } from 'lucide-react';

type SchoolSettings = { school_name: string; phone: string; email: string; address: string };
const initialSchool: SchoolSettings = {
  school_name: 'EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY',
  phone: '', email: '', address: '',
};

function SettingsContent() {
  const { isReadOnly, isAdmin } = useEPCAccess();
  const [school, setSchool] = useState<SchoolSettings>(initialSchool);
  const [loading, setLoading] = useState(false);
  const [savingSchool, setSavingSchool] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [adminCode, setAdminCode] = useState('');
  const [showAdminCode, setShowAdminCode] = useState(false);
  const [codeConfigured, setCodeConfigured] = useState<boolean | null>(null);
  const [savingCode, setSavingCode] = useState(false);
  const [codeNotice, setCodeNotice] = useState('');
  const [codeError, setCodeError] = useState('');
  const connected = isSupabaseConfigured();

  const load = useCallback(async () => {
    const client = supabase();
    if (!client) { setError('La connexion aux données doit être activée pour enregistrer les paramètres.'); return; }
    setLoading(true); setError('');
    const { data, error: queryError } = await client.from('school_settings')
      .select('school_name,phone,email,address').order('created_at').limit(1).maybeSingle();
    if (queryError) setError(`Chargement impossible : un problème est survenu. Contactez l’administrateur.`);
    else if (data) setSchool({
      school_name: data.school_name || '', phone: data.phone || '',
      email: data.email || '', address: data.address || '',
    });
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const loadAdminCodeStatus = useCallback(async () => {
    const client = supabase();
    if (!client) return;
    const { data: sessionData } = await client.auth.getSession();
    const token = sessionData.session?.access_token;
    if (!token) return;
    const response = await fetch('/api/admin/registration-code', { headers: { Authorization: `Bearer ${token}` }, cache: 'no-store' });
    const result = await response.json().catch(() => ({}));
    if (response.ok) setCodeConfigured(Boolean(result.configured));
    else setCodeError(result.error || 'Impossible de vérifier le code administrateur.');
  }, []);

  useEffect(() => { if (isAdmin) void loadAdminCodeStatus(); }, [isAdmin, loadAdminCodeStatus]);

  async function saveAdminCode(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalizedCode = adminCode.trim();
    if (!/^\d{6,8}$/.test(normalizedCode)) { setCodeError('Choisissez un code numérique de 6 à 8 chiffres.'); return; }
    const client = supabase();
    if (!client) { setCodeError('La connexion aux données est indisponible.'); return; }
    const { data: sessionData } = await client.auth.getSession();
    const token = sessionData.session?.access_token;
    if (!token) { setCodeError('Votre session a expiré. Reconnectez-vous.'); return; }
    setSavingCode(true); setCodeError(''); setCodeNotice('');
    try {
      const response = await fetch('/api/admin/registration-code', { method: 'PUT', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: JSON.stringify({ code: normalizedCode }) });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error || 'Enregistrement du code impossible.');
      setCodeConfigured(true); setAdminCode(''); setCodeNotice('Code enregistré. Pour votre sécurité, il ne sera plus affiché.');
    } catch (e) { setCodeError(e instanceof Error ? e.message : 'Erreur lors de l’enregistrement.'); }
    finally { setSavingCode(false); }
  }

  async function saveSchool(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const client = supabase();
    if (!client) { setError('La connexion aux données n’est pas activée.'); return; }
    setSavingSchool(true); setNotice(''); setError('');
    const { error: saveError } = await client.rpc('save_school_settings', {
      p_school_name: school.school_name,
      p_phone: school.phone || null,
      p_email: school.email || null,
      p_address: school.address || null,
    });
    setSavingSchool(false);
    if (saveError) { setError(`Enregistrement impossible : un problème est survenu. Contactez l’administrateur.`); return; }
    setNotice('Coordonnées de l’établissement enregistrées.');
  }

  return <>
    <div className="page-heading">
      <div><div className="eyebrow">ADMINISTRATION</div><h1>Paramètres de l’établissement</h1><p>Gérez les coordonnées officielles, les années scolaires et les classes.</p></div>
      <button type="button" className="button button-secondary" onClick={() => void load()} disabled={loading}><RefreshCw size={16}/> Actualiser</button>
    </div>
    {!connected && <div className="inline-notice"><ShieldCheck size={16}/> Mode aperçu : les modifications ne seront pas conservées tant que la connexion aux données n’est pas activée.</div>}
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

    {isAdmin && <section className="panel settings-panel">
      <div className="panel-heading"><div><h2><KeyRound size={19}/> Utilisateurs et autorisations</h2><p>Définissez ici le code utilisé pour autoriser les nouvelles inscriptions. Ce code n’est pas votre mot de passe de connexion.</p></div></div>
      <div className="settings-form">
        <div className="inline-notice"><ShieldCheck size={16}/><span>{codeConfigured === null ? 'Vérification du code d’accès…' : codeConfigured ? 'Un code d’accès est actuellement configuré.' : 'Aucun code d’accès n’a encore été défini. Les nouvelles inscriptions restent bloquées jusqu’à sa création.'}</span></div>
        {codeNotice && <div className="inline-notice"><CheckCircle2 size={16}/>{codeNotice}</div>}
        {codeError && <div className="inline-notice" role="alert"><AlertCircle size={16}/>{codeError}</div>}
        <form className="settings-form" onSubmit={saveAdminCode}>
          <label className="form-field"><span>{codeConfigured ? 'Nouveau code d’accès (6 à 8 chiffres)' : 'Code d’accès initial (6 à 8 chiffres)'}</span><div className="input-with-icon"><KeyRound size={17}/><input type={showAdminCode ? 'text' : 'password'} autoComplete="new-password" minLength={6} maxLength={8} inputMode="numeric" pattern="[0-9]{6,8}" value={adminCode} onChange={e => setAdminCode(e.target.value.replace(/\D/g, '').slice(0, 8))} placeholder="Ex. : 48271635" required/><button type="button" className="password-toggle" onClick={() => setShowAdminCode(v => !v)} aria-label={showAdminCode ? 'Masquer le code' : 'Afficher le code'}>{showAdminCode ? <EyeOff size={16}/> : <Eye size={16}/>}</button></div></label>
          <p className="form-footnote">Choisissez un code numérique de 6 à 8 chiffres. Il sert uniquement à autoriser les nouvelles inscriptions, pas à vous connecter. Il est stocké sous forme de condensat salé et ne peut pas être relu depuis l’application. Communiquez-le uniquement aux personnes autorisées.</p>
          <button type="submit" className="button button-primary" disabled={savingCode || !connected}><Save size={16}/>{savingCode ? 'Enregistrement…' : codeConfigured ? 'Remplacer le code d’accès' : 'Définir le code initial'}</button>
        </form>
      </div>
    </section>}
    <SchoolYearsManager />
    <ClassesManager />
  </>;
}

export default function SettingsPage() {
  return <AppShell><SettingsContent /></AppShell>;
}
