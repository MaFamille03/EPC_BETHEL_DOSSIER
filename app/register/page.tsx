'use client';
import { useState } from 'react';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import { ArrowLeft, ArrowRight, CheckCircle2, Eye, EyeOff, KeyRound, LoaderCircle, Mail, ShieldCheck, UserRound } from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';

export default function RegisterPage() {
  const router = useRouter();
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [adminCode, setAdminCode] = useState('');
  const [showPasswords, setShowPasswords] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(''); setNotice('');
    if (password.length < 10) { setError('Choisissez un mot de passe d’au moins 10 caractères.'); return; }
    if (password !== confirmPassword) { setError('Les deux saisies du mot de passe ne correspondent pas.'); return; }
    if (!isSupabaseConfigured()) { setError('Configurez Supabase avant de créer un compte.'); return; }
    const client = supabase();
    if (!client) { setError('Configuration Supabase manquante.'); return; }
    setBusy(true);
    try {
      const response = await fetch('/api/auth/register', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fullName, email, password, code: adminCode }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Code administrateur invalide ou création de compte impossible.');
      setNotice('Compte créé avec succès. Vous pouvez maintenant vous connecter avec votre adresse e-mail et votre mot de passe.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Une erreur est survenue.');
    } finally { setBusy(false); }
  }

  return <main className="reset-page"><section className="reset-card register-card">
    <div className="reset-brand"><Image src="/epc-bethel-logo.webp" alt="Logo officiel EPC BETHEL Assemblées de Dieu Jean Folly" width={88} height={88} priority className="register-school-logo"/><span><strong>EPC BETHEL</strong><small>GESTION SCOLAIRE</small></span></div>
    <div className="login-icon"><ShieldCheck size={22}/></div><span className="eyebrow">ACCÈS SUR AUTORISATION</span>
    <h1>Créer un compte</h1>
    <p>Créez votre mot de passe et confirmez-le. Le code administrateur est demandé uniquement lors de l’inscription ; les connexions suivantes utilisent l’e-mail et le mot de passe.</p>
    <form className="settings-form" onSubmit={submit}>
      <label className="form-field"><span>Nom complet</span><div className="input-with-icon"><UserRound size={16}/><input value={fullName} onChange={e=>setFullName(e.target.value)} autoComplete="name" maxLength={120} placeholder="Nom et prénoms" required/></div></label>
      <label className="form-field"><span>Adresse e-mail</span><div className="input-with-icon"><Mail size={16}/><input type="email" value={email} onChange={e=>setEmail(e.target.value)} autoComplete="email" maxLength={254} placeholder="vous@exemple.com" required/></div></label>
      <label className="form-field"><span>Mot de passe (10 caractères minimum)</span><div className="input-with-icon"><KeyRound size={16}/><input type={showPasswords?'text':'password'} value={password} onChange={e=>setPassword(e.target.value)} autoComplete="new-password" minLength={10} maxLength={128} placeholder="Créer un mot de passe" required/><button type="button" className="password-toggle" onClick={()=>setShowPasswords(!showPasswords)} aria-label={showPasswords?'Masquer les mots de passe':'Afficher les mots de passe'}>{showPasswords?<EyeOff size={16}/>:<Eye size={16}/>}</button></div></label>
      <label className="form-field"><span>Confirmer le mot de passe</span><div className="input-with-icon"><KeyRound size={16}/><input type={showPasswords?'text':'password'} value={confirmPassword} onChange={e=>setConfirmPassword(e.target.value)} autoComplete="new-password" minLength={10} maxLength={128} placeholder="Saisir à nouveau le mot de passe" required/></div></label>
      <label className="form-field"><span>Code administrateur / code d’accès</span><div className="input-with-icon"><ShieldCheck size={16}/><input type="password" value={adminCode} onChange={e=>setAdminCode(e.target.value)} autoComplete="off" maxLength={200} placeholder="Code fourni par l’administrateur" required/></div></label>
      {error&&<div className="login-error">{error}</div>}{notice&&<div className="login-notice"><CheckCircle2 size={16}/>{notice}</div>}
      <button className="button button-primary login-submit" disabled={busy}>{busy?<><LoaderCircle size={17} className="spin"/> Création…</>:'Créer mon compte'} <ArrowRight size={17}/></button>
    </form>
    <button type="button" className="text-link reset-back" onClick={()=>router.push('/login')}><ArrowLeft size={15}/> Retour à la connexion</button>
    <p className="register-footnote">Le code sert à autoriser l’inscription. Il ne remplace pas votre mot de passe et ne sera pas demandé à chaque connexion.</p>
  </section></main>;
}
