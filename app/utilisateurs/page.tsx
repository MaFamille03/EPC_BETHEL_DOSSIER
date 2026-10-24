'use client';
import { useCallback, useEffect, useState } from 'react';
import { AppShell } from '@/components/app-shell';
import { supabase, isSupabaseConfigured } from '@/lib/supabase';
import { ModalPortal } from '@/components/modal-portal';
import { UserPlus, RefreshCw, ShieldCheck, Mail, UserRound, CheckCircle2, AlertCircle, LockKeyhole, X } from 'lucide-react';

type Role = 'admin' | 'observateur' | 'modification';
type EditableRole = Exclude<Role, 'admin'>;
type UserRow = { id: string; email: string; full_name: string; role: Role; is_active: boolean; created_at: string };
const PRIMARY_ADMIN_EMAIL = 'minnhindje@gmail.com';

export default function UsersPage() {
  const [rows, setRows] = useState<UserRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [form, setForm] = useState({ email: '', full_name: '' });
  const [showInvite, setShowInvite] = useState(false);

  const load = useCallback(async () => {
    const client = supabase();
    if (!client) { setError('La connexion aux données doit être activée pour gérer les utilisateurs.'); return; }
    setLoading(true); setError('');
    try {
      const { data: { session } } = await client.auth.getSession();
      if (!session) throw new Error('Session expirée. Reconnectez-vous.');
      const response = await fetch('/api/admin/users', { headers: { Authorization: `Bearer ${session.access_token}` }, cache: 'no-store' });
      const json = await response.json();
      if (!response.ok) throw new Error(json.error || 'Chargement impossible');
      setRows(json.users || []);
    } catch (e) { setError(e instanceof Error ? e.message : 'Erreur de chargement'); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function invite(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const client = supabase();
    if (!client) return;
    setSaving(true); setError(''); setNotice('');
    try {
      const { data: { session } } = await client.auth.getSession();
      if (!session) throw new Error('Session expirée. Reconnectez-vous.');
      const response = await fetch('/api/admin/users', {
        method: 'POST', headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      });
      const json = await response.json();
      if (!response.ok) throw new Error(json.error || 'Invitation impossible');
      setNotice(`Invitation envoyée à ${form.email}. Le compte démarre en lecture seule ; tu pourras ajuster son rôle après son inscription.`);
      setForm({ email: '', full_name: '' });
      setShowInvite(false);
      await load();
    } catch (e) { setError(e instanceof Error ? e.message : 'Invitation impossible'); }
    finally { setSaving(false); }
  }

  async function update(row: UserRow, patch: Partial<Pick<UserRow, 'role' | 'is_active'>>) {
    const client = supabase();
    if (!client) return;
    if (row.email.toLowerCase() === PRIMARY_ADMIN_EMAIL || row.role === 'admin') {
      setError('Le compte administrateur principal est protégé.'); return;
    }
    setError(''); setNotice('');
    try {
      const { data: { session } } = await client.auth.getSession();
      if (!session) throw new Error('Session expirée.');
      const response = await fetch('/api/admin/users', {
        method: 'PATCH', headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ userId: row.id, ...patch }),
      });
      const json = await response.json();
      if (!response.ok) throw new Error(json.error || 'Modification impossible');
      setNotice('Les autorisations ont été enregistrées.');
      await load();
    } catch (e) { setError(e instanceof Error ? e.message : 'Modification impossible'); }
  }

  return <AppShell>
    <div className="page-heading"><div><div className="eyebrow">ADMINISTRATION</div><h1>Utilisateurs et autorisations</h1><p>Les nouveaux comptes sont en lecture seule par défaut. Attribue ensuite Lecture seule ou Modification à chaque compte ; l’administration reste réservée au compte principal.</p></div><button className="button button-secondary" onClick={() => void load()} disabled={loading}><RefreshCw size={16}/> Actualiser</button></div>
    {!isSupabaseConfigured() && <div className="inline-notice"><ShieldCheck size={16}/> Mode aperçu : la connexion aux données doit être activée pour gérer les comptes.</div>}
    {error && <div className="inline-notice"><AlertCircle size={16}/>{error}</div>}
    {notice && <div className="inline-notice"><CheckCircle2 size={16}/>{notice}</div>}
    <section className="panel form-panel"><div className="panel-heading"><div><h2>Inviter un utilisateur</h2><p>Invitez un membre de l’équipe par e-mail. Chaque nouveau compte commence en lecture seule et peut être ajusté ensuite.</p></div><button type="button" className="button button-primary" onClick={() => { setError(''); setShowInvite(true); }} disabled={!isSupabaseConfigured()}><UserPlus size={16}/> Inviter un utilisateur</button></div>
      <p className="form-footnote"><strong>Information pour l’administrateur</strong><span>Le code d’inscription est un réglage distinct du mot de passe utilisé pour se connecter.</span></p>
    </section>
    {showInvite && <ModalPortal><div className="modal-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget && !saving) setShowInvite(false); }}><section className="modal user-invite-modal" role="dialog" aria-modal="true" aria-labelledby="invite-user-title">
      <div className="modal-header"><div><span className="eyebrow">ADMINISTRATION</span><h2 id="invite-user-title">Inviter un utilisateur</h2><p>Le nouvel utilisateur recevra un e-mail d’invitation et commencera en lecture seule.</p></div><button type="button" className="icon-button" onClick={() => setShowInvite(false)} disabled={saving} aria-label="Fermer"><X size={18}/></button></div>
      <form onSubmit={invite}>
        <div className="modal-body"><label className="form-field"><span>Nom complet *</span><input required maxLength={120} value={form.full_name} onChange={e => setForm({ ...form, full_name: e.target.value })} placeholder="Nom et prénoms" autoFocus/></label>
        <label className="form-field"><span>Adresse e-mail *</span><input required type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value.trim() })} placeholder="prenom@exemple.com"/></label>
        {error && <div className="inline-notice"><AlertCircle size={16}/>{error}</div>}
        <p className="form-footnote">Après son inscription, vous pourrez lui attribuer le rôle Lecture seule ou Modification.</p></div>
        <div className="modal-footer"><button type="button" className="button button-secondary" onClick={() => setShowInvite(false)} disabled={saving}>Annuler</button><button type="submit" className="button button-primary" disabled={saving || !isSupabaseConfigured()}>{saving ? 'Envoi…' : <><Mail size={16}/> Envoyer l’invitation</>}</button></div>
      </form>
    </section></div></ModalPortal>}
    <section className="panel table-panel"><div className="panel-toolbar"><div><h2>Comptes enregistrés</h2><p>{rows.length} compte{rows.length > 1 ? 's' : ''} chargé{rows.length > 1 ? 's' : ''}</p></div></div>
      <div className="table-scroll"><table><thead><tr><th>Utilisateur</th><th>Autorisation</th><th>État du compte</th><th>Inscription</th><th>Actions</th></tr></thead><tbody>
        {rows.map(row => {
          const isPrimary = row.email.toLowerCase() === PRIMARY_ADMIN_EMAIL || row.role === 'admin';
          return <tr key={row.id}>
            <td><div className="admin-user-cell"><span className="person-avatar green">{isPrimary ? <ShieldCheck size={16}/> : <UserRound size={16}/>}</span><span><strong>{row.full_name || 'Nom non renseigné'}</strong><small>{row.email}</small>{isPrimary && <small className="field-help">Compte principal protégé</small>}</span></div></td>
            <td>{isPrimary ? <span className="role-pill role-pill-admin"><LockKeyhole size={13}/> Administrateur principal</span> : <select aria-label={`Autorisation de ${row.email}`} value={row.role} onChange={e => void update(row, { role: e.target.value as EditableRole })}><option value="observateur">Lecture seule — consulter les informations</option><option value="modification">Modification — gérer les données de l’école</option></select>}</td>
            <td><span className={`status-pill ${row.is_active ? 'status-good' : 'status-warn'}`}><i/>{row.is_active ? 'Actif' : 'Désactivé'}</span></td>
            <td>{row.created_at ? new Date(row.created_at).toLocaleDateString('fr-FR') : '—'}</td>
            <td>{isPrimary ? <span className="field-help">Protection active</span> : <button className="button button-secondary" onClick={() => void update(row, { is_active: !row.is_active })}>{row.is_active ? 'Désactiver' : 'Réactiver'}</button>}</td>
          </tr>;
        })}
        {!rows.length && <tr><td colSpan={5} className="empty-cell">{loading ? 'Chargement…' : 'Aucun utilisateur retourné. Vérifiez la configuration et les droits administrateur.'}</td></tr>}
      </tbody></table></div>
    </section>
    <div className="inline-notice"><ShieldCheck size={16}/><span>Les niveaux d’accès disponibles sont Lecture seule et Modification. L’administration est réservée au compte principal : {PRIMARY_ADMIN_EMAIL}.</span></div>
  </AppShell>;
}
