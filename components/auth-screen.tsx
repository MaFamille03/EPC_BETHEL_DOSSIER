'use client';
import Image from 'next/image';
import { usePathname, useRouter } from 'next/navigation';
import { useState } from 'react';
import { LockKeyhole, Mail, ArrowRight, ShieldCheck, AlertCircle, Eye, EyeOff, KeyRound, UserRound, CheckCircle2 } from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';

export default function AuthScreen() {
  const router = useRouter();
  const pathname = usePathname();
  const isRegister = pathname === '/register';
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [adminCode, setAdminCode] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  function switchMode(register: boolean) {
    setError(''); setNotice('');
    router.push(register ? '/register' : '/login');
  }

  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(''); setNotice('');
    if (!isSupabaseConfigured()) { setError('Configuration Supabase absente côté navigateur. Dans Vercel, vérifiez NEXT_PUBLIC_SUPABASE_URL et NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY (ou NEXT_PUBLIC_SUPABASE_ANON_KEY), puis redéployez.'); return; }
    const client = supabase();
    if (!client) { setError('Configuration Supabase incomplète. Vérifiez les variables publiques puis redéployez.'); return; }
    setLoading(true);
    const normalized = email.trim().toLowerCase();
    const { data, error: authError } = await client.auth.signInWithPassword({ email: normalized, password });
    if (authError || !data.user) {
      setLoading(false);
      setError('Connexion impossible. Vérifiez votre e-mail et votre mot de passe. Si votre compte vient d’être créé, vérifiez aussi la configuration de Supabase Auth.'); return;
    }
    const { data: profile, error: profileError } = await client.from('profiles').select('role,is_active').eq('id', data.user.id).maybeSingle();
    if (profileError || !profile || !profile.is_active) {
      await client.auth.signOut(); setLoading(false);
      setError('Votre authentification fonctionne, mais votre profil EPC BETHEL est absent ou inactif. Exécutez la migration d’initialisation de l’administrateur puis réessayez.'); return;
    }
    if (normalized === 'minnhindje@gmail.com' && profile.role !== 'admin') {
      await client.auth.signOut(); setLoading(false);
      setError('Votre profil existe, mais le rôle administrateur principal n’est pas activé. Vérifiez le profil dans Supabase.'); return;
    }
    setLoading(false); router.replace('/'); router.refresh();
  }

  async function register(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(''); setNotice('');
    if (password.length < 10) { setError('Choisissez un mot de passe d’au moins 10 caractères.'); return; }
    if (password !== confirmPassword) { setError('Les deux mots de passe ne correspondent pas.'); return; }
    if (!isSupabaseConfigured()) { setError('Configuration Supabase absente côté navigateur. Vérifiez NEXT_PUBLIC_SUPABASE_URL et NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY (ou NEXT_PUBLIC_SUPABASE_ANON_KEY) dans Vercel, puis redéployez.'); return; }
    setLoading(true);
    try {
      const response = await fetch('/api/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ fullName, email, password, code: adminCode }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'La création du compte a échoué.');
      setNotice('Compte créé. Vous pouvez maintenant vous connecter avec votre adresse e-mail et votre mot de passe.');
      setPassword(''); setConfirmPassword(''); setAdminCode('');
    } catch (e) { setError(e instanceof Error ? e.message : 'Une erreur est survenue.'); }
    finally { setLoading(false); }
  }

  async function resetPassword() {
    setError(''); setNotice(''); const normalized = email.trim().toLowerCase();
    if (!normalized) { setError('Saisissez votre adresse e-mail avant de demander la réinitialisation.'); return; }
    const client = supabase();
    if (!client) { setError('Configuration Supabase absente. Vérifiez les variables publiques dans Vercel puis redéployez.'); return; }
    setLoading(true);
    const { error: resetError } = await client.auth.resetPasswordForEmail(normalized, { redirectTo: `${window.location.origin}/reset-password` });
    setLoading(false);
    if (resetError) { setError('Le lien ne peut pas être envoyé. Vérifiez les paramètres e-mail et les URL autorisées dans Supabase.'); return; }
    setNotice('Si cette adresse correspond à un compte, un lien de réinitialisation a été envoyé. Vérifiez aussi les courriers indésirables.');
  }

  return <main className="login-page auth-page">
    <section className="login-visual" aria-label="Présentation de l’établissement">
      <div className="login-brand"><Image src="/epc-bethel-logo.webp" alt="Logo officiel EPC BETHEL Assemblées de Dieu Jean Folly" width={88} height={88} priority className="login-school-logo"/><div><strong>EPC BETHEL</strong><span>GESTION SCOLAIRE</span></div></div>
      <div className="login-visual-content"><span className="login-overline"><i/> ESPACE DE GESTION</span><h1>Une école bien gérée,<br/><em>un avenir mieux préparé.</em></h1><p>Une plateforme claire et fiable pour piloter la vie scolaire, les finances et le patrimoine de votre établissement.</p><div className="login-illustration"><div className="illustration-ring ring-one"/><div className="illustration-ring ring-two"/><div className="illustration-card card-back"><div/><div/><div/></div><div className="illustration-card card-front"><div className="illus-logo"><ShieldCheck size={23}/></div><span>ANNÉE SCOLAIRE</span><strong>2026 — 2027</strong><div className="illus-lines"><i/><i/><i/></div><div className="illus-bottom"><span>BETHEL</span><ShieldCheck size={19}/></div></div><div className="floating-badge"><ShieldCheck size={16}/><span>Connexion sécurisée</span></div></div></div>
      <div className="login-visual-footer"><span>EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY</span><span>Abidjan · Côte d’Ivoire</span></div>
    </section>
    <section className="login-form-side auth-form-side"><div className="login-form-wrap auth-form-wrap">
      <div className="mobile-login-brand"><Image src="/epc-bethel-logo.webp" alt="Logo officiel EPC BETHEL" width={54} height={54} priority className="mobile-school-logo"/><strong>EPC BETHEL</strong></div>
      <div className="login-welcome auth-welcome"><div className="login-icon">{isRegister ? <ShieldCheck size={21}/> : <LockKeyhole size={21}/>}</div><span className="eyebrow">{isRegister ? 'ACCÈS SUR AUTORISATION' : 'ACCÈS SÉCURISÉ'}</span><h2>{isRegister ? 'Créer un compte' : 'Connectez-vous'}</h2><p>{isRegister ? 'Créez votre mot de passe et confirmez-le. Le code d’accès est demandé uniquement lors de l’inscription.' : 'Utilisez votre adresse e-mail et votre mot de passe personnel.'}</p></div>
      {isRegister ? <form onSubmit={register} className="login-form auth-register-form">
        <label className="form-field"><span>Nom complet</span><div className="input-with-icon"><UserRound size={17}/><input value={fullName} onChange={e=>setFullName(e.target.value)} autoComplete="name" maxLength={120} placeholder="Nom et prénoms" required/></div></label>
        <label className="form-field"><span>Adresse e-mail</span><div className="input-with-icon"><Mail size={17}/><input type="email" value={email} onChange={e=>setEmail(e.target.value)} autoComplete="email" maxLength={254} placeholder="vous@exemple.com" required/></div></label>
        <label className="form-field"><span>Mot de passe (10 caractères minimum)</span><div className="input-with-icon"><KeyRound size={17}/><input type={showPassword?'text':'password'} value={password} onChange={e=>setPassword(e.target.value)} autoComplete="new-password" minLength={10} maxLength={128} placeholder="Créer un mot de passe" required/><button type="button" className="password-toggle" onClick={()=>setShowPassword(!showPassword)} aria-label={showPassword?'Masquer le mot de passe':'Afficher le mot de passe'}>{showPassword?<EyeOff size={16}/>:<Eye size={16}/>}</button></div></label>
        <label className="form-field"><span>Confirmer le mot de passe</span><div className="input-with-icon"><KeyRound size={17}/><input type={showPassword?'text':'password'} value={confirmPassword} onChange={e=>setConfirmPassword(e.target.value)} autoComplete="new-password" minLength={10} maxLength={128} placeholder="Saisir à nouveau le mot de passe" required/></div></label>
        <label className="form-field"><span>Code d’accès (6 à 8 chiffres, inscription uniquement)</span><div className="input-with-icon"><ShieldCheck size={17}/><input type="password" value={adminCode} onChange={e=>setAdminCode(e.target.value.replace(/\D/g, '').slice(0, 8))} inputMode="numeric" pattern="[0-9]{6,8}" minLength={6} maxLength={8} autoComplete="off" placeholder="Code fourni par l’administrateur" required/></div></label>
        {error&&<div className="login-error"><AlertCircle size={15}/>{error}</div>}{notice&&<div className="login-notice"><CheckCircle2 size={15}/>{notice}</div>}
        <button className="button button-primary login-submit" disabled={loading}>{loading?'Création du compte…':'Créer mon compte'} <ArrowRight size={17}/></button>
      </form> : <form onSubmit={signIn} className="login-form">
        <label className="form-field"><span>Adresse e-mail</span><div className="input-with-icon"><Mail size={17}/><input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="votre@adresse.com" autoComplete="email" maxLength={254} required/></div></label>
        <label className="form-field"><span>Mot de passe</span><div className="input-with-icon"><KeyRound size={17}/><input type={showPassword?'text':'password'} value={password} onChange={e=>setPassword(e.target.value)} placeholder="Votre mot de passe" autoComplete="current-password" required/><button type="button" className="password-toggle" onClick={()=>setShowPassword(!showPassword)} aria-label={showPassword?'Masquer le mot de passe':'Afficher le mot de passe'}>{showPassword?<EyeOff size={16}/>:<Eye size={16}/>}</button></div></label>
        {error&&<div className="login-error"><AlertCircle size={15}/>{error}</div>}{notice&&<div className="login-notice"><ShieldCheck size={15}/>{notice}</div>}
        <button className="button button-primary login-submit" disabled={loading}>{loading?'Connexion…':'Se connecter'} <ArrowRight size={17}/></button>
        <button type="button" className="forgot-link" onClick={()=>void resetPassword()} disabled={loading}>Mot de passe oublié ? Recevoir un lien de réinitialisation</button>
      </form>}
      <div className="login-security"><ShieldCheck size={16}/><span>Ne partagez jamais votre mot de passe.</span></div>
      <div className="login-help">{isRegister ? 'Vous avez déjà un compte ? ' : 'Pas encore de compte ? '}{isRegister ? <button type="button" onClick={()=>switchMode(false)}>Retour à la connexion</button> : <button type="button" onClick={()=>switchMode(true)}>Créer un compte avec un code d’accès</button>}</div>
    </div><div className="login-copyright">© 2026 EPC BETHEL · Tous droits réservés</div></section>
  </main>;
}
