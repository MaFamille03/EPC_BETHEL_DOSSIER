'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { BadgePercent, CalendarClock, CheckCircle2, CircleAlert, Edit3, Plus, RefreshCw, Save, X } from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';
import { useEPCAccess } from '@/components/access-context';

type YearOption = { id: string; label: string; is_current: boolean; is_closed: boolean };
type ClassOption = { id: string; name: string };
type FeeCategory = { id: string; code: string; name: string; kind: 'scolarite' | 'inscription' | 'annexe' | 'autre'; is_active: boolean };
type Tariff = { id: string; school_year_id: string; class_id: string; fee_category_id: string; gross_amount: number; installment_count: number; due_dates: string[]; is_active: boolean; school_years?: { label: string } | { label: string }[]; classes?: { name: string } | { name: string }[]; fee_categories?: { name: string; code: string; kind: string; is_active: boolean } | { name: string; code: string; kind: string; is_active: boolean }[] };
type TariffForm = { id?: string; school_year_id: string; class_id: string; fee_category_id: string; gross_amount: string; is_active: boolean };
type SchoolYearSchedule = { id: string; school_year_id: string; due_dates: string[]; is_locked: boolean; updated_at: string };
type CategoryForm = { id?: string; code: string; name: string; kind: FeeCategory['kind']; is_active: boolean };
const blankDueDates = () => Array.from({ length: 6 }, () => '');
const emptyTariff = (): TariffForm => ({ school_year_id: '', class_id: '', fee_category_id: '', gross_amount: '', is_active: true });
const emptyCategory = (): CategoryForm => ({ code: '', name: '', kind: 'annexe', is_active: true });
const normalize = <T,>(value: T | T[] | null | undefined): T | undefined => Array.isArray(value) ? value[0] : value || undefined;
const money = (value: number) => `${new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(value)} FCFA`;
const kindLabel: Record<FeeCategory['kind'], string> = { scolarite: 'Scolarité', inscription: 'Inscription', annexe: 'Frais annexes', autre: 'Autres frais' };
const dateLabel = (value: string) => value ? new Date(`${value}T00:00:00`).toLocaleDateString('fr-FR') : '—';

export function ClassFeeTariffsManager() {
  const { isReadOnly, role } = useEPCAccess();
  const connected = isSupabaseConfigured();
  const canManage = !isReadOnly && ['admin', 'direction'].includes(role || '');
  const [years, setYears] = useState<YearOption[]>([]);
  const [classes, setClasses] = useState<ClassOption[]>([]);
  const [categories, setCategories] = useState<FeeCategory[]>([]);
  const [tariffs, setTariffs] = useState<Tariff[]>([]);
  const [schedules, setSchedules] = useState<SchoolYearSchedule[]>([]);
  const [scheduleYearId, setScheduleYearId] = useState('');
  const [scheduleDates, setScheduleDates] = useState<string[]>(blankDueDates());
  const [showScheduleForm, setShowScheduleForm] = useState(false);
  const [scheduleCorrection, setScheduleCorrection] = useState(false);
  const [scheduleSaving, setScheduleSaving] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [applying, setApplying] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [showTariffForm, setShowTariffForm] = useState(false);
  const [showCategoryForm, setShowCategoryForm] = useState(false);
  const [tariffForm, setTariffForm] = useState<TariffForm>(emptyTariff());
  const [categoryForm, setCategoryForm] = useState<CategoryForm>(emptyCategory());
  const [classFilter, setClassFilter] = useState('all');
  const [yearFilter, setYearFilter] = useState('all');

  const refresh = useCallback(async () => {
    const client = supabase();
    if (!client) { setYears([]); setClasses([]); setCategories([]); setTariffs([]); return; }
    setLoading(true); setError('');
    try {
      const [yearResult, classResult, categoryResult, tariffResult, scheduleResult] = await Promise.all([
        client.from('school_years').select('id,label,is_current,is_closed').order('starts_on', { ascending: false }),
        client.from('classes').select('id,name').eq('is_active', true).order('level_order').order('name'),
        client.from('fee_categories').select('id,code,name,kind,is_active').order('kind').order('name'),
        client.from('class_fee_tariffs').select('id,school_year_id,class_id,fee_category_id,gross_amount,installment_count,due_dates,is_active,school_years(label),classes(name),fee_categories(name,code,kind,is_active)').order('created_at', { ascending: false }),
        client.from('school_year_payment_schedules').select('id,school_year_id,due_dates,is_locked,updated_at').order('updated_at', { ascending: false }),
      ]);
      const failed = [yearResult, classResult, categoryResult, tariffResult, scheduleResult].find((result) => result.error);
      if (failed?.error) throw failed.error;
      setYears((yearResult.data || []) as YearOption[]);
      setClasses((classResult.data || []) as ClassOption[]);
      setCategories((categoryResult.data || []) as FeeCategory[]);
      setTariffs((tariffResult.data || []) as unknown as Tariff[]);
      setSchedules((scheduleResult.data || []) as unknown as SchoolYearSchedule[]);
    } catch (e) {
      setError('Impossible de charger les tarifs et le calendrier annuel. Vérifiez que les migrations 024 et 025 sont appliquées et que votre compte est autorisé.');
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);
  const activeYears = useMemo(() => years.filter((year) => !year.is_closed), [years]);
  const visibleTariffs = useMemo(() => tariffs.filter((tariff) => (yearFilter === 'all' || tariff.school_year_id === yearFilter) && (classFilter === 'all' || tariff.class_id === classFilter)), [tariffs, yearFilter, classFilter]);

  function openScheduleForm(yearId?: string, correction = false) {
    const defaultYear = activeYears.find((year) => year.is_current) || activeYears[0];
    const targetId = yearId || scheduleYearId || defaultYear?.id || '';
    const year = years.find((item) => item.id === targetId);
    if (!targetId || !year) { setError('Créez d’abord une année scolaire dans les paramètres.'); return; }
    if (year.is_closed) { setError('Une année scolaire clôturée ne peut pas recevoir de modification des échéances.'); return; }
    const currentSchedule = schedules.find((item) => item.school_year_id === targetId);
    if (currentSchedule && correction && !window.confirm('Les échéances sont fixées pour cette année. Une correction exceptionnelle changera le calendrier appliqué aux futures attributions, mais ne modifiera aucun frais déjà attribué ni paiement enregistré. Continuer ?')) return;
    setScheduleYearId(targetId);
    setScheduleDates(currentSchedule ? [...currentSchedule.due_dates] : blankDueDates());
    setScheduleCorrection(!!currentSchedule && correction);
    setError(''); setShowScheduleForm(true);
  }

  async function saveSchedule(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const client = supabase();
    if (!client) { setError('Connexion à Supabase indisponible.'); return; }
    if (scheduleDates.length !== 6 || scheduleDates.some((date) => !date) || scheduleDates.some((date, index) => index > 0 && date <= scheduleDates[index - 1])) { setError('Renseignez six dates distinctes, dans l’ordre chronologique.'); return; }
    const existing = schedules.find((item) => item.school_year_id === scheduleYearId);
    if (existing && !scheduleCorrection && JSON.stringify(existing.due_dates) !== JSON.stringify(scheduleDates)) { setError('Les échéances sont déjà fixées. Utilisez la correction exceptionnelle si une vraie correction administrative est nécessaire.'); return; }
    setScheduleSaving(true); setError(''); setNotice('');
    const { error: saveError } = await client.rpc('save_school_year_payment_schedule', { p_school_year_id: scheduleYearId, p_due_dates: scheduleDates, p_confirm_change: scheduleCorrection });
    setScheduleSaving(false);
    if (saveError) { setError(saveError.message || 'Enregistrement des échéances impossible.'); return; }
    setShowScheduleForm(false); setScheduleCorrection(false);
    setNotice(existing ? 'Calendrier annuel enregistré. Les frais déjà attribués conservent leurs dates.' : 'Les six échéances annuelles sont maintenant fixées. Elles s’appliquent à toutes les catégories de frais et ne se décalent pas lorsqu’un élève paie en retard.');
    await refresh();
  }

  function openNewTariff() {
    const currentYear = activeYears.find((year) => year.is_current) || activeYears[0];
    const firstClass = classes[0];
    const firstCategory = categories.find((item) => item.is_active);
    if (currentYear && !schedules.some((item) => item.school_year_id === currentYear.id && item.is_locked)) {
      setNotice('Configurez d’abord les six échéances annuelles dans Paramètres.');
      openScheduleForm(currentYear.id); return;
    }
    setTariffForm({ ...emptyTariff(), school_year_id: currentYear?.id || '', class_id: firstClass?.id || '', fee_category_id: firstCategory?.id || '' });
    setError(''); setShowTariffForm(true);
  }

  function openEditTariff(tariff: Tariff) {
    if (!schedules.some((item) => item.school_year_id === tariff.school_year_id && item.is_locked)) { openScheduleForm(tariff.school_year_id); return; }
    setTariffForm({ id: tariff.id, school_year_id: tariff.school_year_id, class_id: tariff.class_id, fee_category_id: tariff.fee_category_id, gross_amount: String(tariff.gross_amount), is_active: tariff.is_active });
    setError(''); setShowTariffForm(true);
  }

  async function saveTariff(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); const client = supabase(); if (!client) { setError('Connexion à Supabase indisponible.'); return; }
    const amount = Number(tariffForm.gross_amount);
    if (!tariffForm.school_year_id || !tariffForm.class_id || !tariffForm.fee_category_id || !Number.isSafeInteger(amount) || amount < 0) { setError('Choisissez l’année, la classe et la catégorie, puis saisissez un montant entier positif.'); return; }
    const year = years.find((item) => item.id === tariffForm.school_year_id);
    const schedule = schedules.find((item) => item.school_year_id === tariffForm.school_year_id && item.is_locked);
    if (year?.is_closed) { setError('Une année clôturée ne peut pas recevoir de modification de tarif.'); return; }
    if (!schedule) { setError('Configurez les six échéances annuelles dans Paramètres avant d’enregistrer le tarif.'); return; }
    setSaving(true); setError(''); setNotice('');
    const payload = { school_year_id: tariffForm.school_year_id, class_id: tariffForm.class_id, fee_category_id: tariffForm.fee_category_id, gross_amount: amount, installment_count: 6, due_dates: schedule.due_dates, is_active: tariffForm.is_active, updated_at: new Date().toISOString() };
    const request = tariffForm.id
      ? client.from('class_fee_tariffs').update(payload).eq('id', tariffForm.id)
      : client.from('class_fee_tariffs').upsert(payload, { onConflict: 'school_year_id,class_id,fee_category_id' });
    const { error: saveError } = await request;
    setSaving(false);
    if (saveError) { setError(saveError.message.includes('duplicate') ? 'Un tarif existe déjà pour cette classe, cette année et cette catégorie.' : 'Enregistrement du tarif impossible. Vérifiez les autorisations et les données.'); return; }
    setShowTariffForm(false); setNotice('Tarif enregistré avec le calendrier fixe de l’année scolaire. Les frais déjà attribués ne sont pas modifiés rétroactivement.'); await refresh();
  }

  async function saveCategory(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); const client = supabase(); if (!client) { setError('Connexion à Supabase indisponible.'); return; }
    if (!categoryForm.name.trim() || !categoryForm.code.trim()) { setError('Le code et le nom de la catégorie sont obligatoires.'); return; }
    setSaving(true); setError('');
    // Keep update and insert payloads separate: Supabase types the allowed fields
    // differently for an update of an existing category versus a new category.
    const result = categoryForm.id
      ? await client.from('fee_categories').update({
          name: categoryForm.name.trim(),
          is_active: categoryForm.is_active,
        }).eq('id', categoryForm.id)
      : await client.from('fee_categories').insert({
          code: categoryForm.code.trim().toUpperCase().replace(/[^A-Z0-9_-]/g, '_'),
          name: categoryForm.name.trim(),
          kind: categoryForm.kind,
          is_active: categoryForm.is_active,
        });
    setSaving(false);
    if (result.error) { setError(result.error.code === '23505' ? 'Ce code de catégorie existe déjà.' : 'Enregistrement de la catégorie impossible.'); return; }
    setShowCategoryForm(false); setNotice('Catégorie enregistrée. La désactivation conserve les frais et les reçus historiques.'); await refresh();
  }

  async function toggleTariff(tariff: Tariff) {
    const client = supabase(); if (!client || !canManage) return;
    const { error: updateError } = await client.from('class_fee_tariffs').update({ is_active: !tariff.is_active, updated_at: new Date().toISOString() }).eq('id', tariff.id);
    if (updateError) { setError('Modification du statut du tarif impossible.'); return; }
    setNotice(tariff.is_active ? 'Tarif désactivé. Les frais déjà attribués restent inchangés.' : 'Tarif réactivé pour les prochaines attributions.'); await refresh();
  }

  async function applyToExisting() {
    const client = supabase(); if (!client || !canManage) return;
    const yearId = yearFilter !== 'all' ? yearFilter : activeYears.find((year) => year.is_current)?.id;
    if (!yearId) { setError('Choisissez une année scolaire non clôturée.'); return; }
    const targetYear = years.find((year) => year.id === yearId);
    if (targetYear?.is_closed) { setError('L’année scolaire sélectionnée est clôturée.'); return; }
    const classIds = classFilter !== 'all' ? [classFilter] : classes.map((item) => item.id);
    const { data: enrollmentRows, error: enrollmentError } = await client.from('enrollments').select('id,school_year_id,class_id,status').eq('school_year_id', yearId).in('class_id', classIds).in('status', ['inscrit', 'reinscrit']);
    if (enrollmentError) { setError('Chargement des inscriptions à actualiser impossible.'); return; }
    if (!enrollmentRows?.length) { setNotice('Aucune inscription active pour cette sélection.'); return; }
    if (!window.confirm(`Appliquer les tarifs actifs aux ${enrollmentRows.length} inscription(s) sélectionnée(s) qui n’ont pas encore de frais correspondants ? Les frais existants ne seront pas remplacés.`)) return;
    setApplying(true); setError(''); let applied = 0; let failed = 0;
    for (const enrollment of enrollmentRows) {
      const { data, error: applyError } = await client.rpc('apply_class_fee_tariffs', { p_enrollment_id: enrollment.id });
      if (applyError) failed++; else applied += Number(data || 0);
    }
    setApplying(false); setNotice(`Tarifs appliqués : ${applied} catégorie(s) de frais créée(s), ${failed} inscription(s) en erreur. Les frais préexistants ont été conservés.`); await refresh();
  }

  return <section className="panel settings-panel class-fee-tariffs-panel">
    <div className="panel-heading"><div><h2><CalendarClock size={19}/> Tarifs des frais scolaires</h2><p>Configurez les montants par classe et par année. Chaque tarif utilise six échéances. Les six échéances sont fixées une fois par année scolaire dans Paramètres, puis appliquées à tous les frais. Un retard de paiement ne décale jamais les dates.</p></div><div className="heading-actions"><button type="button" className="button button-secondary" onClick={() => void refresh()} disabled={loading}><RefreshCw size={15}/> Actualiser</button>{canManage && <button type="button" className="button button-primary" onClick={openNewTariff}><Plus size={16}/> Nouveau tarif</button>}</div></div>
    {!connected && <div className="inline-notice"><CircleAlert size={16}/>Connectez Supabase pour configurer les tarifs persistants.</div>}
    {notice && <div className="inline-notice"><CheckCircle2 size={16}/><span>{notice}</span><button className="icon-button" onClick={() => setNotice('')} aria-label="Fermer"><X size={14}/></button></div>}
    {error && !showTariffForm && !showCategoryForm && <div className="inline-notice" role="alert"><CircleAlert size={16}/><span>{error}</span><button className="icon-button" onClick={() => setError('')} aria-label="Fermer"><X size={14}/></button></div>}
    <section className="annual-payment-schedule-panel" aria-label="Échéances annuelles de paiement">
      <div className="annual-payment-schedule-heading"><div><h3><CalendarClock size={17}/> Calendrier annuel des six échéances</h3><p>Définissez les dates au début de l’année scolaire. Elles s’appliquent à toutes les classes et catégories de frais ; les retards individuels ne les déplacent pas.</p></div><label className="form-field"><span>Année scolaire</span><select value={scheduleYearId || (activeYears.find((year) => year.is_current)?.id || activeYears[0]?.id || '')} onChange={(e) => setScheduleYearId(e.target.value)}><option value="">Sélectionner une année</option>{years.map((year) => <option key={year.id} value={year.id}>{year.label}{year.is_closed ? ' · Clôturée' : year.is_current ? ' · En cours' : ''}</option>)}</select></label></div>
      {(() => { const activeScheduleYearId = scheduleYearId || (activeYears.find((year) => year.is_current)?.id || activeYears[0]?.id || ''); const year = years.find((item) => item.id === activeScheduleYearId); const schedule = schedules.find((item) => item.school_year_id === activeScheduleYearId); return <><div className={`annual-schedule-status ${schedule ? 'is-configured' : 'is-missing'}`}>{schedule ? <><strong>Échéances fixées · {year?.label || 'Année sélectionnée'}</strong><span>Dernier enregistrement : {schedule.updated_at ? new Date(schedule.updated_at).toLocaleDateString('fr-FR') : '—'}</span></> : <><strong>Calendrier non configuré</strong><span>Les tarifs et frais de cette année ne pourront pas utiliser un calendrier fixe avant son enregistrement.</span></>}</div>{schedule && <div className="annual-schedule-dates">{schedule.due_dates.map((date, index) => <div key={`${schedule.school_year_id}-${index}`}><span>Échéance {index + 1}</span><strong>{dateLabel(date)}</strong></div>)}</div>}<div className="annual-schedule-actions">{canManage && !year?.is_closed && <button type="button" className="button button-primary" onClick={() => openScheduleForm(activeScheduleYearId, !!schedule)}><CalendarClock size={15}/>{schedule ? 'Corriger exceptionnellement les dates' : 'Configurer les six dates'}</button>}{year?.is_closed && <span className="form-footnote">Année clôturée : calendrier consultable, mais non modifiable.</span>}</div></>; })()}
    </section>
    <div className="class-fee-tariffs-toolbar"><label className="form-field"><span>Année scolaire</span><select value={yearFilter} onChange={(e) => setYearFilter(e.target.value)}><option value="all">Toutes les années</option>{years.map((year) => <option key={year.id} value={year.id}>{year.label}{year.is_closed ? ' · Clôturée' : year.is_current ? ' · En cours' : ''}</option>)}</select></label><label className="form-field"><span>Classe</span><select value={classFilter} onChange={(e) => setClassFilter(e.target.value)}><option value="all">Toutes les classes</option>{classes.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>{canManage && <button type="button" className="button button-secondary" onClick={() => void applyToExisting()} disabled={applying || loading}><BadgePercent size={15}/>{applying ? 'Application…' : 'Appliquer aux inscriptions sans frais'}</button>}</div>
    <div className="table-scroll"><table><thead><tr><th>Année</th><th>Classe</th><th>Catégorie</th><th>Montant brut</th><th>Échéances</th><th>Statut</th><th>Actions</th></tr></thead><tbody>{visibleTariffs.map((tariff) => { const year = normalize(tariff.school_years); const klass = normalize(tariff.classes); const category = normalize(tariff.fee_categories); return <tr key={tariff.id}><td>{year?.label || '—'}</td><td>{klass?.name || '—'}</td><td><strong>{category?.name || 'Catégorie indisponible'}</strong><small className="payment-subline">{category?.code || ''} · {kindLabel[(category?.kind as FeeCategory['kind']) || 'autre']}</small></td><td>{money(Number(tariff.gross_amount || 0))}</td><td>6 dates · {tariff.due_dates?.[0] || '—'} → {tariff.due_dates?.[5] || '—'}</td><td><span className={`status-pill ${tariff.is_active ? 'status-good' : 'status-warn'}`}><i/>{tariff.is_active ? 'Actif' : 'Désactivé'}</span></td><td><div className="row-actions">{canManage && <><button className="button button-secondary" onClick={() => openEditTariff(tariff)}><Edit3 size={14}/> Modifier</button><button className="button button-secondary" onClick={() => void toggleTariff(tariff)}>{tariff.is_active ? 'Désactiver' : 'Activer'}</button></>}</div></td></tr>; })}{visibleTariffs.length === 0 && <tr><td colSpan={7} className="empty-cell">{loading ? 'Chargement des tarifs…' : 'Aucun tarif pour ces filtres. Ajoutez un tarif pour qu’il soit attribué lors de l’inscription.'}</td></tr>}</tbody></table></div>
    <div className="class-fee-category-section"><div><h3>Catégories de frais</h3><p>Les catégories désactivées restent consultables dans l’historique et ne sont pas attribuées automatiquement.</p></div>{canManage && <button type="button" className="button button-secondary" onClick={() => { setCategoryForm(emptyCategory()); setError(''); setShowCategoryForm(true); }}><Plus size={15}/> Ajouter une catégorie</button>}</div>
    <div className="class-fee-category-list">{categories.map((category) => <div key={category.id} className="class-fee-category-item"><div><strong>{category.name}</strong><span>{category.code} · {kindLabel[category.kind]}</span></div><span className={`status-pill ${category.is_active ? 'status-good' : 'status-warn'}`}><i/>{category.is_active ? 'Active' : 'Désactivée'}</span>{canManage && <div className="row-actions"><button className="button button-secondary" onClick={() => { setCategoryForm({ id: category.id, code: category.code, name: category.name, kind: category.kind, is_active: category.is_active }); setError(''); setShowCategoryForm(true); }}>Modifier</button><button className="button button-secondary" onClick={async () => { const client = supabase(); if (!client) return; const { error: updateError } = await client.from('fee_categories').update({ is_active: !category.is_active }).eq('id', category.id); if (updateError) setError('Modification de la catégorie impossible.'); else { setNotice(category.is_active ? 'Catégorie désactivée, sans suppression de son historique.' : 'Catégorie réactivée.'); await refresh(); } }}>{category.is_active ? 'Désactiver' : 'Réactiver'}</button></div>}</div>)}</div>

    {showScheduleForm && typeof document !== 'undefined' && createPortal(<div className="modal-backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget && !scheduleSaving) setShowScheduleForm(false); }}><section className="modal annual-schedule-modal" role="dialog" aria-modal="true" aria-label="Calendrier annuel des échéances"><div className="modal-header"><div><span className="eyebrow">PARAMÈTRES FINANCIERS · CALENDRIER ANNUEL</span><h2>{scheduleCorrection ? 'Correction exceptionnelle des échéances' : schedules.some((item) => item.school_year_id === scheduleYearId) ? 'Échéances annuelles fixées' : 'Configurer les six échéances'}</h2><p>Les dates s’appliquent à tous les frais de l’année scolaire. Un paiement tardif ne les décale pas.</p></div><button className="icon-button" onClick={() => setShowScheduleForm(false)} disabled={scheduleSaving} aria-label="Fermer"><X size={18}/></button></div><form onSubmit={saveSchedule}><div className="modal-body annual-schedule-modal-body">{error && <div className="inline-notice" role="alert"><CircleAlert size={15}/>{error}</div>}<label className="form-field"><span>Année scolaire *</span><select required value={scheduleYearId} disabled={scheduleCorrection || schedules.some((item) => item.school_year_id === scheduleYearId)} onChange={(e) => { setScheduleYearId(e.target.value); const existing = schedules.find((item) => item.school_year_id === e.target.value); setScheduleDates(existing ? [...existing.due_dates] : blankDueDates()); }}><option value="">Sélectionner</option>{activeYears.map((year) => <option key={year.id} value={year.id}>{year.label}{year.is_current ? ' · En cours' : ''}</option>)}</select></label><div className="annual-schedule-date-fields">{scheduleDates.map((date, index) => <label className="form-field" key={index}><span>Échéance {index + 1} *</span><input type="date" required value={date} readOnly={schedules.some((item) => item.school_year_id === scheduleYearId) && !scheduleCorrection} onChange={(e) => setScheduleDates((old) => old.map((value, i) => i === index ? e.target.value : value))}/></label>)}</div>{scheduleCorrection && <div className="inline-notice"><CircleAlert size={16}/><span>Une correction s’appliquera seulement aux futures attributions. Les frais, échéanciers et paiements déjà enregistrés restent inchangés.</span></div>}{schedules.some((item) => item.school_year_id === scheduleYearId) && !scheduleCorrection && canManage && !years.find((year) => year.id === scheduleYearId)?.is_closed && <button type="button" className="button button-secondary" onClick={() => openScheduleForm(scheduleYearId, true)}>Corriger exceptionnellement les dates</button>}<p className="form-footnote">Les six dates doivent être renseignées, distinctes et strictement classées par ordre chronologique. Une fois enregistrées, elles sont verrouillées pour l’année scolaire ; toute correction nécessite une confirmation explicite.</p></div><div className="modal-footer"><button type="button" className="button button-secondary" onClick={() => setShowScheduleForm(false)} disabled={scheduleSaving}>Fermer</button>{(!schedules.some((item) => item.school_year_id === scheduleYearId) || scheduleCorrection) && canManage && <button type="submit" className="button button-primary" disabled={scheduleSaving}>{scheduleSaving ? 'Enregistrement…' : <><Save size={15}/> {scheduleCorrection ? 'Confirmer la correction' : 'Fixer les échéances annuelles'}</>}</button>}</div></form></section></div>, document.body)}

    {showTariffForm && typeof document !== 'undefined' && createPortal(<div className="modal-backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget && !saving) setShowTariffForm(false); }}><section className="modal class-fee-tariff-modal" role="dialog" aria-modal="true" aria-label="Tarif des frais scolaires"><div className="modal-header"><div><span className="eyebrow">PARAMÈTRES FINANCIERS</span><h2>{tariffForm.id ? 'Modifier un tarif' : 'Configurer un tarif'}</h2><p>Le montant sera copié dans les frais de chaque nouvelle attribution ; une modification ultérieure ne réécrit pas les charges historiques.</p></div><button className="icon-button" onClick={() => setShowTariffForm(false)} aria-label="Fermer"><X size={18}/></button></div><form onSubmit={saveTariff}><div className="modal-body class-fee-tariff-form-body">{error && <div className="inline-notice" role="alert"><CircleAlert size={15}/>{error}</div>}<div className="form-grid"><label className="form-field"><span>Année scolaire *</span><select required value={tariffForm.school_year_id} onChange={(e) => setTariffForm({ ...tariffForm, school_year_id: e.target.value })}><option value="">Sélectionner</option>{activeYears.map((year) => <option key={year.id} value={year.id}>{year.label}</option>)}</select></label><label className="form-field"><span>Classe *</span><select required value={tariffForm.class_id} onChange={(e) => setTariffForm({ ...tariffForm, class_id: e.target.value })}><option value="">Sélectionner</option>{classes.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label className="form-field"><span>Catégorie de frais *</span><select required value={tariffForm.fee_category_id} onChange={(e) => setTariffForm({ ...tariffForm, fee_category_id: e.target.value })}><option value="">Sélectionner</option>{categories.filter((item) => item.is_active).map((item) => <option key={item.id} value={item.id}>{item.name} · {kindLabel[item.kind]}</option>)}</select></label><label className="form-field"><span>Montant total brut (FCFA) *</span><input required type="number" min="0" step="1" value={tariffForm.gross_amount} onChange={(e) => setTariffForm({ ...tariffForm, gross_amount: e.target.value })} placeholder="Ex. 150000"/></label></div><div className="tariff-annual-schedule-readonly">{(() => { const schedule = schedules.find((item) => item.school_year_id === tariffForm.school_year_id && item.is_locked); return schedule ? <><strong><CalendarClock size={15}/> Échéances annuelles fixes</strong><div>{schedule.due_dates.map((date, index) => <span key={index}>Échéance {index + 1} · {dateLabel(date)}</span>)}</div><small>Les dates se configurent une seule fois dans Paramètres. Toute correction exceptionnelle se fait dans le calendrier annuel et ne modifie pas les charges déjà attribuées.</small></> : <><strong>Calendrier annuel manquant</strong><small>Configurez d’abord les six échéances dans la section « Calendrier annuel » de Paramètres.</small><button type="button" className="button button-secondary" onClick={() => { setShowTariffForm(false); openScheduleForm(tariffForm.school_year_id); }}>Configurer les échéances annuelles</button></>; })()}</div><label className="settings-checkbox"><input type="checkbox" checked={tariffForm.is_active} onChange={(e) => setTariffForm({ ...tariffForm, is_active: e.target.checked })}/><span><strong>Tarif actif</strong><small>Utilisable pour les prochaines attributions de frais.</small></span></label></div><div className="modal-footer"><button type="button" className="button button-secondary" onClick={() => setShowTariffForm(false)}>Annuler</button><button type="submit" className="button button-primary" disabled={saving || !schedules.some((item) => item.school_year_id === tariffForm.school_year_id && item.is_locked)}>{saving ? 'Enregistrement…' : <><Save size={15}/> Enregistrer le tarif</>}</button></div></form></section></div>, document.body)}

    {showCategoryForm && typeof document !== 'undefined' && createPortal(<div className="modal-backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget && !saving) setShowCategoryForm(false); }}><section className="modal" role="dialog" aria-modal="true" aria-label="Catégorie de frais"><div className="modal-header"><div><span className="eyebrow">PARAMÈTRES FINANCIERS</span><h2>{categoryForm.id ? 'Modifier une catégorie' : 'Nouvelle catégorie de frais'}</h2></div><button className="icon-button" onClick={() => setShowCategoryForm(false)} aria-label="Fermer"><X size={18}/></button></div><form onSubmit={saveCategory}><div className="modal-body">{error && <div className="inline-notice" role="alert"><CircleAlert size={15}/>{error}</div>}<label className="form-field"><span>Nom de la catégorie *</span><input required maxLength={120} value={categoryForm.name} onChange={(e) => setCategoryForm({ ...categoryForm, name: e.target.value })}/></label>{!categoryForm.id && <><label className="form-field"><span>Code unique *</span><input required maxLength={40} value={categoryForm.code} onChange={(e) => setCategoryForm({ ...categoryForm, code: e.target.value.toUpperCase().replace(/[^A-Z0-9_-]/g, '_') })} placeholder="EXAMEN, CANTINE…"/></label><label className="form-field"><span>Type de frais *</span><select value={categoryForm.kind} onChange={(e) => setCategoryForm({ ...categoryForm, kind: e.target.value as FeeCategory['kind'] })}><option value="scolarite">Scolarité</option><option value="inscription">Inscription</option><option value="annexe">Frais annexes</option><option value="autre">Autres frais</option></select></label><p className="form-footnote">Le type est fixé à la création pour préserver la cohérence de l’historique financier.</p></>}<label className="settings-checkbox"><input type="checkbox" checked={categoryForm.is_active} onChange={(e) => setCategoryForm({ ...categoryForm, is_active: e.target.checked })}/><span><strong>Catégorie active</strong><small>La désactivation n’efface aucun frais, paiement ou reçu existant.</small></span></label></div><div className="modal-footer"><button type="button" className="button button-secondary" onClick={() => setShowCategoryForm(false)}>Annuler</button><button type="submit" className="button button-primary" disabled={saving}>{saving ? 'Enregistrement…' : 'Enregistrer la catégorie'}</button></div></form></section></div>, document.body)}
  </section>;
}
