'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { ArrowLeft, ArrowRight, CheckCircle2, Eye, EyeOff, KeyRound, Leaf, LoaderCircle, Mail, ShieldCheck, UserRound } from 'lucide-react';

export default function RegisterPage() {
  const router = useRouter();
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [showCode, setShowCode] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const response = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fullName, email, code }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Création du compte impossible.');
      setNotice('Un e-mail de confirmation a été envoyé à cette adresse. Ouvrez le lien reçu pour confirmer que la boîte vous appartient, puis revenez à la connexion pour recevoir votre code temporaire.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Une erreur est survenue.');
    } finally {
      setBusy(false);
    }
  }

  return <main className="reset-page"><section className="reset-card register-card">
    <div className="reset-brand"><span className="brand-mark"><Leaf size={23}/></span><span><strong>EPC BETHEL</strong><small>GESTION SCOLAIRE</small></span></div>
    <div className="login-icon"><ShieldCheck size={22}/></div>
    <span className="eyebrow">ACCÈS SUR AUTORISATION</span>
    <h1>Créer un compte</h1>
    <p>Un code d’accès fourni par l’administrateur est nécessaire. Tous les nouveaux comptes reçoivent le rôle Observateur par défaut.</p>
    <form className="settings-form" onSubmit={submit}>
      <label className="form-field"><span>Nom complet</span><div className="input-with-icon"><UserRound size={16}/><input value={fullName} onChange={e=>setFullName(e.target.value)} autoComplete="name" maxLength={120} placeholder="Nom et prénoms" required/></div></label>
      <label className="form-field"><span>Adresse e-mail</span><div className="input-with-icon"><Mail size={16}/><input type="email" value={email} onChange={e=>setEmail(e.target.value)} autoComplete="email" maxLength={254} placeholder="vous@exemple.com" required/></div></label>
      <label className="form-field"><span>Code de sécurité pour créer un compte</span><div className="input-with-icon"><KeyRound size={16}/><input type={showCode?'text':'password'} value={code} onChange={e=>setCode(e.target.value)} autoComplete="off" maxLength={200} placeholder="Code fourni par l’administrateur" required/><button type="button" className="password-toggle" onClick={()=>setShowCode(!showCode)} aria-label={showCode?'Masquer le code':'Afficher le code'}>{showCode?<EyeOff size={16}/>:<Eye size={16}/>}</button></div></label>
      {error&&<div className="login-error">{error}</div>}
      {notice&&<div className="login-notice"><CheckCircle2 size={16}/>{notice}</div>}
      <button className="button button-primary login-submit" disabled={busy}>{busy?<><LoaderCircle size={17} className="spin"/> Création…</>:'Créer mon compte'} <ArrowRight size={17}/></button>
    </form>
    <button type="button" className="text-link reset-back" onClick={()=>router.push('/login')}><ArrowLeft size={15}/> Retour à la connexion</button>
    <p className="register-footnote">Le code d’accès est vérifié côté serveur et n’est jamais envoyé au navigateur depuis la configuration.</p>
  </section></main>;
}
