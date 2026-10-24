'use client';

import { useCallback, useEffect, useState } from 'react';
import { CheckCircle2, Edit3, Plus, RefreshCw, Save, X, BookOpen, AlertCircle } from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';
import { useEPCAccess } from '@/components/access-context';
import { ModalPortal } from '@/components/modal-portal';

type SchoolClass = { id: string; code: string; name: string; level_order: number; is_active: boolean };
type ClassForm = { code: string; name: string; level_order: string; is_active: boolean };
const emptyForm: ClassForm = { code: '', name: '', level_order: '1', is_active: true };

export function ClassesManager() {
  const { isReadOnly } = useEPCAccess();
  const [classes, setClasses] = useState<SchoolClass[]>([]);
  const [form, setForm] = useState<ClassForm>(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const connected = isSupabaseConfigured();

  const load = useCallback(async () => {
    const client = supabase();
    if (!client) { setError('La connexion aux données doit être activée pour gérer les classes.'); return; }
    setLoading(true); setError('');
    const { data, error: queryError } = await client.from('classes').select('id,code,name,level_order,is_active').order('level_order').order('name');
    if (queryError) setError(`Chargement impossible : un problème est survenu. Contactez l’administrateur.`);
    else setClasses((data || []) as SchoolClass[]);
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  function startCreate() {
    setEditingId(null); setForm(emptyForm); setShowForm(true); setNotice(''); setError('');
  }
  function startEdit(item: SchoolClass) {
    setEditingId(item.id);
    setForm({ code: item.code, name: item.name, level_order: String(item.level_order), is_active: item.is_active });
    setShowForm(true); setNotice(''); setError('');
  }
  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const client = supabase();
    if (!client) { setError('La connexion aux données n’est pas activée.'); return; }
    const level = Number(form.level_order);
    if (!Number.isInteger(level) || level < 1 || level > 99) { setError('L’ordre du niveau doit être un entier entre 1 et 99.'); return; }
    setSaving(true); setError(''); setNotice('');
    const { error: saveError } = await client.rpc('save_class', {
      p_id: editingId,
      p_code: form.code.trim().toUpperCase(),
      p_name: form.name.trim(),
      p_level_order: level,
      p_is_active: form.is_active,
    });
    setSaving(false);
    if (saveError) { setError(`Enregistrement impossible : un problème est survenu. Contactez l’administrateur.`); return; }
    setShowForm(false); setNotice(editingId ? 'Classe mise à jour.' : 'Classe créée.');
    await load();
  }

  return <section className="panel settings-panel">
    <div className="panel-heading">
      <div><h2><BookOpen size={19}/> Classes et niveaux</h2><p>Gérez les classes scolaires, leur code, l’ordre du niveau et leur disponibilité pour les inscriptions.</p></div>
      <div className="heading-actions">
        <button type="button" className="button button-secondary" onClick={() => void load()} disabled={loading}><RefreshCw size={16}/> Actualiser</button>
        {!isReadOnly && <button type="button" className="button button-primary" onClick={startCreate}><Plus size={16}/> Nouvelle classe</button>}
      </div>
    </div>

    {notice && <div className="inline-notice"><CheckCircle2 size={16}/>{notice}</div>}
    {error && <div className="inline-notice"><AlertCircle size={16}/>{error}</div>}
    <div className="table-scroll">
      <table>
        <thead><tr><th>Code</th><th>Classe</th><th>Ordre du niveau</th><th>État</th><th className="action-col">Action</th></tr></thead>
        <tbody>
          {classes.map(item => <tr key={item.id}>
            <td><span className="record-id">{item.code}</span></td>
            <td><span className="cell-strong">{item.name}</span></td>
            <td>{item.level_order}</td>
            <td><span className={`status-pill ${item.is_active ? 'status-good' : 'status-warn'}`}><i/>{item.is_active ? 'Active' : 'Inactive'}</span></td>
            <td>{!isReadOnly ? <button type="button" className="button button-secondary" onClick={() => startEdit(item)}><Edit3 size={15}/> Modifier</button> : <span>—</span>}</td>
          </tr>)}
          {classes.length === 0 && <tr><td colSpan={5} className="empty-cell">{loading ? 'Chargement des classes…' : 'Aucune classe disponible. Actualisez la page ou contactez l’administrateur.'}</td></tr>}
        </tbody>
      </table>
    </div>
    {showForm && !isReadOnly && <ModalPortal><div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setShowForm(false); }}>
      <section className="modal" role="dialog" aria-modal="true" aria-labelledby="class-modal-title">
        <div className="modal-header"><div><span className="eyebrow">RÉFÉRENTIEL SCOLAIRE</span><h2 id="class-modal-title">{editingId ? 'Modifier la classe' : 'Créer une classe'}</h2></div><button type="button" className="icon-button" onClick={() => setShowForm(false)} aria-label="Fermer"><X size={18}/></button></div>
        <form onSubmit={save}>
          <div className="modal-body">
            <div className="settings-fields-grid">
              <label className="form-field"><span>Code *</span><input required maxLength={20} value={form.code} onChange={e => setForm({ ...form, code: e.target.value.toUpperCase() })} placeholder="Ex. CP1A"/></label>
              <label className="form-field"><span>Ordre du niveau *</span><input required type="number" min={1} max={99} step={1} value={form.level_order} onChange={e => setForm({ ...form, level_order: e.target.value })}/></label>
            </div>
            <label className="form-field"><span>Nom de la classe *</span><input required maxLength={100} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Ex. CP1 A"/></label>
            <label className="form-field checkbox-field"><input type="checkbox" checked={form.is_active} onChange={e => setForm({ ...form, is_active: e.target.checked })}/><span>Classe disponible pour les nouvelles inscriptions</span></label>
            <p className="form-footnote">La désactivation conserve l’historique et n’efface aucune inscription passée.</p>
          </div>
          <div className="modal-footer"><button type="button" className="button button-secondary" onClick={() => setShowForm(false)}>Annuler</button><button type="submit" className="button button-primary" disabled={saving}><Save size={16}/>{saving ? 'Enregistrement…' : 'Enregistrer'}</button></div>
        </form>
      </section>
    </div></ModalPortal>}
  </section>;
}
