'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { CalendarDays, CheckCircle2, Edit3, Plus, RefreshCw, Save, X, AlertCircle } from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';
import { useEPCAccess } from '@/components/access-context';

type SchoolYear = { id: string; label: string; starts_on: string; ends_on: string; is_current: boolean; is_closed: boolean };
type YearForm = { label: string; starts_on: string; ends_on: string; is_current: boolean };

function dateForInput(date: string) { return date ? date.slice(0, 10) : ''; }

export function SchoolYearsManager() {
  const { isReadOnly } = useEPCAccess();
  const connected = isSupabaseConfigured();
  const [years, setYears] = useState<SchoolYear[]>([]);
  const [form, setForm] = useState<YearForm>({ label: '2026–2027', starts_on: '2026-09-01', ends_on: '2027-07-10', is_current: true });
  const [editingId, setEditingId] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    const client = supabase();
    if (!client) { setError('Activez la connexion aux données pour gérer les années scolaires réelles.'); return; }
    setLoading(true); setError('');
    const { data, error: queryError } = await client.from('school_years')
      .select('id,label,starts_on,ends_on,is_current,is_closed')
      .order('starts_on', { ascending: false }).limit(50);
    if (queryError) setError(`Chargement impossible : un problème est survenu. Contactez l’administrateur.`);
    else setYears((data || []) as SchoolYear[]);
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const currentYear = useMemo(() => years.find(year => year.is_current), [years]);

  function startCreate() {
    const latest = years.reduce<SchoolYear | null>((top, candidate) => !top || candidate.starts_on > top.starts_on ? candidate : top, null);
    const baseStartYear = latest ? Number(latest.starts_on.slice(0, 4)) + 1 : new Date().getFullYear();
    const nextLabel = `${baseStartYear}–${baseStartYear + 1}`;
    setEditingId(null);
    setForm({ label: nextLabel, starts_on: `${baseStartYear}-09-01`, ends_on: `${baseStartYear + 1}-07-10`, is_current: years.length === 0 });
    setShowForm(true); setNotice(''); setError('');
  }

  function startEdit(item: SchoolYear) {
    if (item.is_closed) return;
    setEditingId(item.id);
    setForm({ label: item.label, starts_on: dateForInput(item.starts_on), ends_on: dateForInput(item.ends_on), is_current: item.is_current });
    setShowForm(true); setNotice(''); setError('');
  }

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const client = supabase();
    if (!client) { setError('La connexion aux données n’est pas activée.'); return; }
    if (!form.label.trim() || form.ends_on <= form.starts_on) { setError('Le libellé est obligatoire et la date de fin doit suivre la date de début.'); return; }
    setSaving(true); setError(''); setNotice('');
    const { error: saveError } = await client.rpc('save_school_year', {
      p_id: editingId,
      p_label: form.label.trim(),
      p_starts_on: form.starts_on,
      p_ends_on: form.ends_on,
      p_is_current: form.is_current,
    });
    setSaving(false);
    if (saveError) { setError(`Enregistrement impossible : un problème est survenu. Contactez l’administrateur.`); return; }
    setShowForm(false); setNotice(editingId ? 'Année scolaire mise à jour.' : 'Année scolaire créée.');
    await load();
  }

  return <section id="annees-scolaires" className="panel settings-panel">
    <div className="panel-heading">
      <div><h2><CalendarDays size={19}/> Années scolaires</h2><p>Conservez l’historique, préparez l’année suivante et choisissez l’année utilisée par défaut pour les nouvelles inscriptions.</p></div>
      <div className="heading-actions">
        <button type="button" className="button button-secondary" onClick={() => void load()} disabled={loading}><RefreshCw size={16}/> Actualiser</button>
        {!isReadOnly && <button type="button" className="button button-primary" onClick={startCreate}><Plus size={16}/> Nouvelle année</button>}
      </div>
    </div>
    {currentYear && <div className="inline-notice"><CheckCircle2 size={16}/> Année actuellement active : <strong>{currentYear.label}</strong></div>}
    {!currentYear && years.length > 0 && <div className="inline-notice"><AlertCircle size={16}/> Aucune année n’est actuellement active. Activez une année pour permettre les nouvelles inscriptions.</div>}
    {!connected && <div className="inline-notice"><AlertCircle size={16}/> Mode aperçu : les modifications ne seront pas conservées tant que la connexion aux données n’est pas activée.</div>}
    {notice && <div className="inline-notice"><CheckCircle2 size={16}/>{notice}</div>}
    {error && <div className="inline-notice"><AlertCircle size={16}/>{error}</div>}
    <div className="table-scroll">
      <table>
        <thead><tr><th>Année</th><th>Du</th><th>Au</th><th>État</th><th className="action-col">Action</th></tr></thead>
        <tbody>
          {years.map(item => <tr key={item.id}>
            <td><span className="cell-strong">{item.label}</span></td><td>{dateForInput(item.starts_on)}</td><td>{dateForInput(item.ends_on)}</td>
            <td><span className={`status-pill ${item.is_closed ? 'status-warn' : item.is_current ? 'status-good' : 'status-info'}`}><i/>{item.is_closed ? 'Clôturée' : item.is_current ? 'Active' : 'Préparée'}</span></td>
            <td>{!isReadOnly && !item.is_closed ? <button type="button" className="button button-secondary" onClick={() => startEdit(item)}><Edit3 size={15}/>{item.is_current ? 'Modifier' : 'Modifier / activer'}</button> : <span>—</span>}</td>
          </tr>)}
          {years.length === 0 && <tr><td colSpan={5} className="empty-cell">{loading ? 'Chargement des années…' : 'Aucune année scolaire enregistrée. Cliquez sur « Nouvelle année » pour en créer une, puis cochez « Définir cette année comme année active ». '}</td></tr>}
        </tbody>
      </table>
    </div>
    {showForm && !isReadOnly && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setShowForm(false); }}>
      <section className="modal" role="dialog" aria-modal="true" aria-labelledby="year-modal-title">
        <div className="modal-header"><div><span className="eyebrow">CALENDRIER SCOLAIRE</span><h2 id="year-modal-title">{editingId ? 'Modifier une année scolaire' : 'Créer une année scolaire'}</h2></div><button type="button" className="icon-button" onClick={() => setShowForm(false)} aria-label="Fermer"><X size={18}/></button></div>
        <form onSubmit={save}>
          <div className="modal-body">
            <label className="form-field"><span>Libellé *</span><input required maxLength={30} value={form.label} onChange={e => setForm({ ...form, label: e.target.value })} placeholder="2027–2028"/></label>
            <div className="settings-fields-grid">
              <label className="form-field"><span>Date de début *</span><input required type="date" value={form.starts_on} onChange={e => setForm({ ...form, starts_on: e.target.value })}/></label>
              <label className="form-field"><span>Date de fin *</span><input required type="date" value={form.ends_on} onChange={e => setForm({ ...form, ends_on: e.target.value })}/></label>
            </div>
            <label className="checkbox-field"><input type="checkbox" checked={form.is_current} onChange={e => setForm({ ...form, is_current: e.target.checked })}/><span>Définir cette année comme année active</span></label>
            <p className="form-footnote">Une seule année peut être active à la fois. Une année clôturée reste dans l’historique et n’est pas modifiable depuis cet écran.</p>
          </div>
          <div className="modal-footer"><button type="button" className="button button-secondary" onClick={() => setShowForm(false)}>Annuler</button><button type="submit" className="button button-primary" disabled={saving}><Save size={16}/>{saving ? 'Enregistrement…' : 'Enregistrer'}</button></div>
        </form>
      </section>
    </div>}
  </section>;
}
