'use client';
import Link from 'next/link';
import Image from 'next/image';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { LockKeyhole, Mail, ArrowRight, ShieldCheck, AlertCircle, Eye, EyeOff, KeyRound } from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(''); setNotice('');
    if (!isSupabaseConfigured()) { setError('Configurez Supabase pour activer la connexion.'); return; }
    const client = supabase();
    if (!client) { setError('Configuration Supabase manquante.'); return; }
    setLoading(true);
    const normalized = email.trim().toLowerCase();
    const { data, error: authError } = await client.auth.signInWithPassword({ email: normalized, password });
    if (authError || !data.user) {
      setLoading(false);
      setError('Adresse e-mail ou mot de passe incorrect. Si vous venez de créer votre compte, confirmez votre adresse e-mail ou utilisez « Mot de passe oublié ».');
      return;
    }
    const { data: profile, error: profileError } = await client.from('profiles').select('role,is_active').eq('id', data.user.id).maybeSingle();
    if (profileError || !profile || !profile.is_active) {
      await client.auth.signOut(); setLoading(false);
      setError('Ce compte est inactif ou son profil n’existe pas. Contactez l’administrateur.'); return;
    }
    if (normalized === 'minnhindje@gmail.com' && profile.role !== 'admin') {
      await client.auth.signOut(); setLoading(false);
      setError('Le compte principal existe, mais son rôle administrateur n’est pas initialisé. Vérifiez la migration 011 dans Supabase.'); return;
    }
    setLoading(false); router.replace('/'); router.refresh();
  }

  async function resetPassword() {
    setError(''); setNotice('');
    const normalized = email.trim().toLowerCase();
    if (!normalized) { setError('Saisissez votre adresse e-mail avant de demander la réinitialisation.'); return; }
    const client = supabase();
    if (!client) { setError('Configuration Supabase manquante.'); return; }
    setLoading(true);
    const { error: resetError } = await client.auth.resetPasswordForEmail(normalized, { redirectTo: `${window.location.origin}/reset-password` });
    setLoading(false);
    if (resetError) { setError('Impossible d’envoyer le lien de réinitialisation. Vérifiez les réglages e-mail et les URL autorisées dans Supabase.'); return; }
    setNotice('Si cette adresse correspond à un compte, un lien de réinitialisation lui sera envoyé. Vérifiez votre boîte e-mail et les courriers indésirables.');
  }

  return <main className="login-page">
    <div className="login-visual">
      <div className="login-brand"><Image src="/epc-bethel-logo.webp" alt="Logo officiel EPC BETHEL Assemblées de Dieu Jean Folly" width={104} height={104} priority className="login-school-logo"/><div><strong>EPC BETHEL</strong><span>GESTION SCOLAIRE</span></div></div>
      <div className="login-visual-content"><span className="login-overline"><i/> ESPACE DE GESTION</span><h1>Une école bien gérée,<br/><em>un avenir mieux préparé.</em></h1><p>Une plateforme claire et fiable pour piloter la vie scolaire, les finances et le patrimoine de votre établissement.</p><div className="login-illustration"><div className="illustration-ring ring-one"/><div className="illustration-ring ring-two"/><div className="illustration-card card-back"><div/><div/><div/></div><div className="illustration-card card-front"><div className="illus-logo"><Image src="/epc-bethel-logo.webp" alt="Logo EPC BETHEL" width={68} height={68} className="illus-school-logo"/></div><span>ANNÉE SCOLAIRE</span><strong>2026 — 2027</strong><div className="illus-lines"><i/><i/><i/></div><div className="illus-bottom"><span>BETHEL</span><ShieldCheck size={19}/></div></div><div className="floating-badge"><ShieldCheck size={16}/><span>Connexion sécurisée</span></div></div></div>
      <div className="login-visual-footer"><span>EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY</span><span>Abidjan · Côte d’Ivoire</span></div>
    </div>
    <div className="login-form-side"><div className="login-form-wrap">
      <div className="mobile-login-brand"><Image src="/epc-bethel-logo.webp" alt="Logo officiel EPC BETHEL" width={76} height={76} priority className="mobile-school-logo"/><strong>EPC BETHEL</strong></div>
      <div className="login-welcome"><div className="login-icon"><LockKeyhole size={21}/></div><span className="eyebrow">ACCÈS SÉCURISÉ</span><h2>Connectez-vous</h2><p>Utilisez votre adresse e-mail et votre mot de passe personnel.</p></div>
      <form onSubmit={signIn} className="login-form">
        <label className="form-field"><span>Adresse e-mail</span><div className="input-with-icon"><Mail size={17}/><input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="votre@adresse.com" autoComplete="email" maxLength={254} required/></div></label>
        <label className="form-field"><span>Mot de passe</span><div className="input-with-icon"><KeyRound size={17}/><input type={showPassword?'text':'password'} value={password} onChange={e=>setPassword(e.target.value)} placeholder="Votre mot de passe" autoComplete="current-password" required/><button type="button" className="password-toggle" onClick={()=>setShowPassword(!showPassword)} aria-label={showPassword?'Masquer le mot de passe':'Afficher le mot de passe'}>{showPassword?<EyeOff size={16}/>:<Eye size={16}/>}</button></div></label>
        {error&&<div className="login-error"><AlertCircle size={16}/>{error}</div>}
        {notice&&<div className="login-notice"><ShieldCheck size={16}/>{notice}</div>}
        <button className="button button-primary login-submit" disabled={loading}>{loading?'Veuillez patienter…':'Se connecter'} <ArrowRight size={17}/></button>
        <button type="button" className="forgot-link" onClick={()=>void resetPassword()} disabled={loading}>Mot de passe oublié ? Recevoir un lien de réinitialisation</button>
      </form>
      <div className="login-security"><ShieldCheck size={16}/><span>Ne partagez jamais votre mot de passe.</span></div>
      <div className="login-help">Pas encore de compte ? <Link href="/register">Créer un compte avec un code d’accès</Link></div>
    </div><div className="login-copyright">© 2026 EPC BETHEL · Tous droits réservés</div></div>
  </main>;
}
