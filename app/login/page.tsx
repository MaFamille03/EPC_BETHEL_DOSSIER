'use client';
import Link from 'next/link';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Leaf, LockKeyhole, Mail, ArrowRight, ShieldCheck, CheckCircle2, AlertCircle, RefreshCw } from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [adminCode, setAdminCode] = useState('');
  const [requiresAdminCode, setRequiresAdminCode] = useState(false);
  const [step, setStep] = useState<'email' | 'code'>('email');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  async function sendCode() {
    setError('');
    setNotice('');
    if (!isSupabaseConfigured()) {
      setError('Configurez Supabase pour activer la connexion sécurisée.');
      return;
    }
    const normalized = email.trim().toLowerCase();
    if (!normalized) {
      setError('Saisissez votre adresse e-mail.');
      return;
    }
    const client = supabase();
    if (!client) return;
    setLoading(true);
    const accessResponse = await fetch(`/api/admin/admin-access-code?email=${encodeURIComponent(normalized)}`, { cache: 'no-store' });
    const accessInfo = await accessResponse.json().catch(() => ({}));
    if (!accessResponse.ok) { setLoading(false); setError(accessInfo.error || 'Impossible de vérifier les règles d’accès.'); return; }
    const needsAdminCode = !!accessInfo.requiresCode;
    setRequiresAdminCode(needsAdminCode);
    if (needsAdminCode) {
      if (adminCode.length < 12) { setLoading(false); setError('Cette adresse est autorisée à devenir administrateur : saisissez le code administrateur configuré dans les paramètres.'); return; }
      const check = await fetch('/api/admin/admin-access-code', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'verify', email: normalized, code: adminCode }) });
      if (!check.ok) { const result = await check.json().catch(() => ({})); setLoading(false); setError(result.error || 'Code administrateur incorrect.'); return; }
    }
    const { error: otpError } = await client.auth.signInWithOtp({
      email: normalized,
      options: { shouldCreateUser: false },
    });
    setLoading(false);
    if (otpError) {
      setError('Impossible d’envoyer le code. Vérifiez l’adresse, la configuration e-mail et les réglages Supabase.');
      return;
    }
    setEmail(normalized);
    setStep('code');
    setNotice('Si un compte existe pour cette adresse, un code temporaire a été envoyé. Vérifiez également les courriers indésirables.');
  }

  async function verifyCode(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError('');
    setNotice('');
    if (!/^\d{6,8}$/.test(code.trim())) {
      setError('Saisissez le code numérique reçu par e-mail.');
      return;
    }
    const client = supabase();
    if (!client) {
      setError('Configurez Supabase pour activer la connexion sécurisée.');
      return;
    }
    setLoading(true);
    const { data, error: verifyError } = await client.auth.verifyOtp({
      email: email.trim().toLowerCase(),
      token: code.trim(),
      type: 'email',
    });
    if (verifyError || !data.user) {
      setLoading(false);
      setError('Code invalide ou expiré. Demandez un nouveau code puis réessayez.');
      return;
    }

    const { data: profile, error: profileError } = await client
      .from('profiles')
      .select('role,is_active')
      .eq('id', data.user.id)
      .maybeSingle();

    if (profileError || !profile || !profile.is_active) {
      await client.auth.signOut();
      setLoading(false);
      setError('Ce compte est inactif ou son profil n’existe pas. Contactez l’administrateur.');
      return;
    }
    if (requiresAdminCode && data.user.email?.toLowerCase() !== 'minnhindje@gmail.com') {
      const promotion = await fetch('/api/admin/admin-access-code', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${data.session?.access_token || ''}` }, body: JSON.stringify({ action: 'promote', code: adminCode }) });
      if (!promotion.ok) { await client.auth.signOut(); setLoading(false); setError('La connexion a réussi, mais le rôle administrateur n’a pas pu être attribué. Vérifiez le code dans les paramètres.'); return; }
    }
    if (data.user.email?.toLowerCase() === 'minnhindje@gmail.com' && profile.role !== 'admin') {
      await client.auth.signOut();
      setLoading(false);
      setError('Le profil administrateur principal n’est pas initialisé. Appliquez les migrations de sécurité EPC BETHEL.');
      return;
    }
    setLoading(false);
    router.replace('/');
    router.refresh();
  }

  async function resetEmail() {
    setCode('');
    setAdminCode('');
    setRequiresAdminCode(false);
    setError('');
    setNotice('');
    setStep('email');
  }

  return <main className="login-page">
    <div className="login-visual">
      <div className="login-brand"><div className="brand-mark"><Leaf size={24}/></div><div><strong>EPC BETHEL</strong><span>GESTION SCOLAIRE</span></div></div>
      <div className="login-visual-content"><span className="login-overline"><i/> ESPACE DE GESTION</span><h1>Une école bien gérée,<br/><em>un avenir mieux préparé.</em></h1><p>Une plateforme claire et fiable pour piloter la vie scolaire, les finances et le patrimoine de votre établissement.</p><div className="login-illustration"><div className="illustration-ring ring-one"/><div className="illustration-ring ring-two"/><div className="illustration-card card-back"><div/><div/><div/></div><div className="illustration-card card-front"><div className="illus-logo"><Leaf size={22}/></div><span>ANNÉE SCOLAIRE</span><strong>2026 — 2027</strong><div className="illus-lines"><i/><i/><i/></div><div className="illus-bottom"><span>BETHEL</span><ShieldCheck size={19}/></div></div><div className="floating-badge"><ShieldCheck size={16}/><span>Connexion par code e-mail</span></div></div></div>
      <div className="login-visual-footer"><span>EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY</span><span>Abidjan · Côte d’Ivoire</span></div>
    </div>
    <div className="login-form-side"><div className="login-form-wrap">
      <div className="mobile-login-brand"><div className="brand-mark"><Leaf size={22}/></div><strong>EPC BETHEL</strong></div>
      <div className="login-welcome"><div className="login-icon"><LockKeyhole size={21}/></div><span className="eyebrow">ACCÈS SÉCURISÉ</span><h2>{step === 'email' ? 'Connectez-vous' : 'Vérifiez votre e-mail'}</h2><p>{step === 'email' ? 'Recevez un code temporaire pour accéder à votre espace.' : `Saisissez le code reçu à ${email}.`}</p></div>
      {step === 'email' ? <form onSubmit={e => { e.preventDefault(); void sendCode(); }} className="login-form">
        <label className="form-field"><span>Adresse e-mail</span><div className="input-with-icon"><Mail size={17}/><input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="votre@adresse.com" autoComplete="email" maxLength={254} required/></div></label>
        {email.trim().toLowerCase() !== 'minnhindje@gmail.com' && <label className="form-field"><span>Code administrateur (si cette adresse a été autorisée)</span><div className="input-with-icon"><ShieldCheck size={17}/><input type="password" autoComplete="off" value={adminCode} onChange={e=>setAdminCode(e.target.value)} placeholder="Code administrateur" maxLength={128}/></div></label>}
        {error&&<div className="login-error"><AlertCircle size={16}/>{error}</div>}
        <button className="button button-primary login-submit" disabled={loading}>{loading?'Envoi du code…':'Recevoir mon code'} <ArrowRight size={17}/></button>
      </form> : <form onSubmit={verifyCode} className="login-form">
        {notice&&<div className="login-notice"><CheckCircle2 size={16}/>{notice}</div>}
        {requiresAdminCode && <label className="form-field"><span>Code administrateur</span><div className="input-with-icon"><ShieldCheck size={17}/><input type="password" value={adminCode} onChange={e=>setAdminCode(e.target.value)} autoComplete="off" required minLength={12} maxLength={128} /></div></label>}
        <label className="form-field"><span>Code de sécurité (e-mail)</span><div className="input-with-icon"><ShieldCheck size={17}/><input type="text" inputMode="numeric" autoComplete="one-time-code" value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,'').slice(0,8))} placeholder="Saisir le code reçu" minLength={6} maxLength={8} required/></div></label>
        {error&&<div className="login-error"><AlertCircle size={16}/>{error}</div>}
        <button className="button button-primary login-submit" disabled={loading}>{loading?'Vérification…':'Vérifier et se connecter'} <ArrowRight size={17}/></button>
        <div className="otp-actions"><button type="button" className="forgot-link" onClick={() => void sendCode()} disabled={loading}><RefreshCw size={14}/> Renvoyer le code</button><button type="button" className="forgot-link" onClick={() => void resetEmail()} disabled={loading}>Changer d’adresse</button></div>
      </form>}
      <div className="login-security"><ShieldCheck size={16}/><span>Code temporaire personnel. Ne le partagez avec personne.</span></div>
      <div className="login-help">Pas encore de compte ? <Link href="/register">Créer un compte avec un code d’accès</Link></div>
    </div><div className="login-copyright">© 2026 EPC BETHEL · Tous droits réservés</div></div>
  </main>;
}
