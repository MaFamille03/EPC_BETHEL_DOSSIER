'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertCircle, BookOpen, Check, ChevronRight, ClipboardList, Download,
  FileCheck2, FileText, GraduationCap, Plus, RefreshCw, Save, Settings2,
  Users, XCircle,
} from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';
import { useEPCAccess } from '@/components/access-context';

type Term = 'T1' | 'T2' | 'T3';
type Tab = 'overview' | 'entry' | 'results' | 'bulletins' | 'settings';
type SchoolYear = { id: string; label: string; is_current: boolean; is_closed: boolean };
type SchoolClass = { id: string; name: string; code: string; is_active: boolean };
type Subject = { id: string; code: string; name: string; is_active: boolean };
type Enrollment = {
  id: string; student_id: string; school_year_id: string; class_id: string; status: string;
  student?: { student_number: string; last_name: string; first_names: string };
  school_year?: SchoolYear; school_class?: SchoolClass;
};
type Assessment = {
  id: string; school_year_id: string; class_id: string; subject_id: string; term: Term;
  title: string; assessment_type: string; assessment_date: string; score_max: number;
  coefficient: number; status: string; subject?: Subject; school_class?: SchoolClass;
};
type Grade = {
  id: string; enrollment_id: string; subject_id: string; term: Term; assessment_id: string | null;
  assessment_label: string; assessment_date: string; score: number; score_max: number;
  coefficient: number; status: string; remarks: string | null;
};
type GradeRule = {
  id?: string; school_year_id: string; class_id: string | null; calculation_method: 'simple' | 'coefficients' | 'categories';
  composition_weight: number; exam_weight: number; other_weight: number; report_scale: number; is_approved: boolean;
};
type Bulletin = { id: string; enrollment_id: string; term: Term; status: string; payload: any; average: number | null; report_scale: number; generated_at: string; published_at: string | null };

const TERMS: { value: Term; label: string }[] = [
  { value: 'T1', label: '1er trimestre' }, { value: 'T2', label: '2e trimestre' }, { value: 'T3', label: '3e trimestre' },
];
const ASSESSMENT_TYPES = [
  { value: 'devoir', label: 'Devoir' }, { value: 'composition', label: 'Composition' },
  { value: 'examen', label: 'Examen trimestriel' }, { value: 'oral', label: 'Évaluation orale' }, { value: 'autre', label: 'Autre' },
];
const STATUS_LABEL: Record<string, string> = {
  entered: 'Note saisie', absent_excused: 'Absence justifiée', absent_unexcused: 'Absence non justifiée', exempt: 'Dispensé', missing: 'Non renseignée',
};
const round = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
const normRelation = <T,>(value: T | T[] | null | undefined): T | undefined => Array.isArray(value) ? value[0] : value || undefined;
const frenchDate = (value?: string | null) => value ? new Date(`${value.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR') : '—';
const safeName = (e?: Enrollment) => `${e?.student?.last_name || ''} ${e?.student?.first_names || ''}`.trim() || 'Élève sans nom';

export function NotesBulletinsPage() {
  const { isReadOnly, role } = useEPCAccess();
  const connected = isSupabaseConfigured();
    const [tab, setTab] = useState<Tab>('overview');
  const [years, setYears] = useState<SchoolYear[]>([]);
  const [classes, setClasses] = useState<SchoolClass[]>([]);
  const [enrollments, setEnrollments] = useState<Enrollment[]>([]);
  const [subjects, setSubjects] = useState<Subject[]>([]);
  const [assessments, setAssessments] = useState<Assessment[]>([]);
  const [grades, setGrades] = useState<Grade[]>([]);
  const [rules, setRules] = useState<GradeRule[]>([]);
  const [bulletins, setBulletins] = useState<Bulletin[]>([]);
  const [yearId, setYearId] = useState('');
  const [term, setTerm] = useState<Term>('T1');
  const [classId, setClassId] = useState('');
  const [subjectId, setSubjectId] = useState('');
  const [assessmentId, setAssessmentId] = useState('');
  const [selectedEnrollmentId, setSelectedEnrollmentId] = useState('');
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState('');
  const [errorNotice, setErrorNotice] = useState(false);
  const [gradeInputs, setGradeInputs] = useState<Record<string, string>>({});
  const [gradeStatuses, setGradeStatuses] = useState<Record<string, string>>({});
  const [assessmentTitle, setAssessmentTitle] = useState('Composition n° 1');
  const [assessmentType, setAssessmentType] = useState('composition');
  const [assessmentDate, setAssessmentDate] = useState(new Date().toISOString().slice(0, 10));
  const [scoreMax, setScoreMax] = useState('20');
  const [assessmentCoefficient, setAssessmentCoefficient] = useState('1');
  const [ruleMethod, setRuleMethod] = useState<GradeRule['calculation_method']>('coefficients');
  const [compositionWeight, setCompositionWeight] = useState('40');
  const [examWeight, setExamWeight] = useState('60');
  const [otherWeight, setOtherWeight] = useState('0');
  const [reportScale, setReportScale] = useState('20');
  const [subjectCode, setSubjectCode] = useState('');
  const [subjectName, setSubjectName] = useState('');
  const [selectedBulletinId, setSelectedBulletinId] = useState('');

  const announce = (message: string, isError = false) => { setNotice(message); setErrorNotice(isError); };

  const refresh = useCallback(async () => {
    const client = supabase();
    if (!client) { setYears([]); setClasses([]); setEnrollments([]); setSubjects([]); setAssessments([]); setGrades([]); setRules([]); setBulletins([]); return; }
    setLoading(true);
    try {
      const [yr, cl, en, su, as, gr, ru, bu] = await Promise.all([
        client.from('school_years').select('id,label,is_current,is_closed').order('starts_on', { ascending: false }),
        client.from('classes').select('id,name,code,is_active').eq('is_active', true).order('level_order').order('name'),
        client.from('enrollments').select('id,student_id,school_year_id,class_id,status,students(student_number,last_name,first_names),school_years(id,label,is_current,is_closed),classes(id,name,code,is_active)').in('status', ['inscrit', 'reinscrit']).order('enrolled_on', { ascending: false }),
        client.from('school_subjects').select('id,code,name,is_active').eq('is_active', true).order('name'),
        client.from('school_assessments').select('id,school_year_id,class_id,subject_id,term,title,assessment_type,assessment_date,score_max,coefficient,status,classes(id,name,code,is_active),school_subjects(id,code,name,is_active)').order('assessment_date', { ascending: false }),
        client.from('student_grades').select('id,enrollment_id,subject_id,term,assessment_id,assessment_label,assessment_date,score,score_max,coefficient,status,remarks'),
        client.from('school_grade_rules').select('id,school_year_id,class_id,calculation_method,composition_weight,exam_weight,other_weight,report_scale,is_approved'),
        client.from('school_bulletins').select('id,enrollment_id,term,status,payload,average,report_scale,generated_at,published_at').order('generated_at', { ascending: false }),
      ]);
      const failed = [yr, cl, en, su, as, gr, ru, bu].find((r) => r.error);
      if (failed?.error) throw failed.error;
      const normalizedEnrollments = (en.data || []).map((raw: any) => ({
        ...raw, student: normRelation(raw.students), school_year: normRelation(raw.school_years), school_class: normRelation(raw.classes),
      })) as Enrollment[];
      const normalizedAssessments = (as.data || []).map((raw: any) => ({
        ...raw, subject: normRelation(raw.school_subjects), school_class: normRelation(raw.classes),
      })) as Assessment[];
      setYears((yr.data || []) as SchoolYear[]);
      setClasses((cl.data || []) as SchoolClass[]);
      setEnrollments(normalizedEnrollments);
      setSubjects((su.data || []) as Subject[]);
      setAssessments(normalizedAssessments);
      setGrades((gr.data || []) as Grade[]);
      setRules((ru.data || []) as GradeRule[]);
      setBulletins((bu.data || []) as Bulletin[]);
      setYearId((old) => old && (yr.data || []).some((y: any) => y.id === old) ? old : ((yr.data || []).find((y: any) => y.is_current)?.id || (yr.data || [])[0]?.id || ''));
      setClassId((old) => old && (cl.data || []).some((c: any) => c.id === old) ? old : (cl.data || [])[0]?.id || '');
      setSubjectId((old) => old && (su.data || []).some((s: any) => s.id === old) ? old : (su.data || [])[0]?.id || '');
    } catch (e) {
      announce('Impossible de charger le module Notes et bulletins. Vérifiez la connexion et appliquez les migrations scolaires.', true);
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const yearEnrollments = useMemo(() => enrollments.filter((e) => e.school_year_id === yearId), [enrollments, yearId]);
  const classEnrollments = useMemo(() => yearEnrollments.filter((e) => !classId || e.class_id === classId).sort((a, b) => safeName(a).localeCompare(safeName(b), 'fr')), [yearEnrollments, classId]);
  const termAssessments = useMemo(() => assessments.filter((a) => a.school_year_id === yearId && a.term === term && (!classId || a.class_id === classId)), [assessments, yearId, term, classId]);
  const selectedAssessment = assessments.find((a) => a.id === assessmentId);
  const currentGrades = useMemo(() => grades.filter((g) => g.term === term && yearEnrollments.some((e) => e.id === g.enrollment_id) && (!classId || yearEnrollments.find((e) => e.id === g.enrollment_id)?.class_id === classId)), [grades, term, yearEnrollments, classId]);
  const selectedRule = rules.find((r) => r.school_year_id === yearId && r.class_id === (classId || null)) || rules.find((r) => r.school_year_id === yearId && !r.class_id);
  const scale = Number(selectedRule?.report_scale || 20);

  useEffect(() => {
    if (!yearId) return;
    const applicable = rules.find((r) => r.school_year_id === yearId && r.class_id === (classId || null)) || rules.find((r) => r.school_year_id === yearId && !r.class_id);
    if (!applicable) return;
    setRuleMethod(applicable.calculation_method);
    setCompositionWeight(String(applicable.composition_weight));
    setExamWeight(String(applicable.exam_weight));
    setOtherWeight(String(applicable.other_weight ?? 0));
    setReportScale(String(applicable.report_scale));
  }, [yearId, classId, rules]);

  useEffect(() => {
    if (!assessmentId || !selectedAssessment) { setGradeInputs({}); setGradeStatuses({}); return; }
    const nextValues: Record<string, string> = {};
    const nextStatuses: Record<string, string> = {};
    for (const e of enrollments.filter((item) => item.school_year_id === selectedAssessment.school_year_id && item.class_id === selectedAssessment.class_id)) {
      const g = grades.find((item) => item.assessment_id === assessmentId && item.enrollment_id === e.id);
      nextValues[e.id] = g && g.status === 'entered' ? String(g.score) : '';
      nextStatuses[e.id] = g?.status || 'missing';
    }
    setGradeInputs(nextValues); setGradeStatuses(nextStatuses);
  }, [assessmentId, selectedAssessment, enrollments, grades]);

  const getSubjectAverage = useCallback((enrollmentId: string, subject: Subject, targetTerm: Term, rule?: GradeRule) => {
    const studentGrades = grades.filter((g) => g.enrollment_id === enrollmentId && g.subject_id === subject.id && g.term === targetTerm && g.status === 'entered');
    if (!studentGrades.length) return null;
    const normalized = studentGrades.map((g) => ({
      value: (Number(g.score) / Number(g.score_max || 20)) * Number(rule?.report_scale || 20),
      coefficient: Number(g.coefficient || 1),
      type: assessments.find((a) => a.id === g.assessment_id)?.assessment_type || 'autre',
    }));
    const method = rule?.calculation_method || 'coefficients';
    if (method === 'simple') return round(normalized.reduce((s, g) => s + g.value, 0) / normalized.length);
    if (method === 'categories') {
      const compositions = normalized.filter((g) => g.type === 'composition');
      const exams = normalized.filter((g) => g.type === 'examen');
      const others = normalized.filter((g) => g.type !== 'composition' && g.type !== 'examen');
      const weightedAvg = (list: typeof normalized) => list.length ? list.reduce((s, g) => s + g.value * g.coefficient, 0) / list.reduce((s, g) => s + g.coefficient, 0) : null;
      const ca = weightedAvg(compositions); const ea = weightedAvg(exams); const oa = weightedAvg(others);
      let weighted = 0; let weights = 0;
      if (ca !== null) { weighted += ca * Number(rule?.composition_weight ?? 40); weights += Number(rule?.composition_weight ?? 40); }
      if (ea !== null) { weighted += ea * Number(rule?.exam_weight ?? 60); weights += Number(rule?.exam_weight ?? 60); }
      if (oa !== null) { weighted += oa * Number(rule?.other_weight ?? 0); weights += Number(rule?.other_weight ?? 0); }
      return weights ? round(weighted / weights) : null;
    }
    return round(normalized.reduce((s, g) => s + g.value * g.coefficient, 0) / normalized.reduce((s, g) => s + g.coefficient, 0));
  }, [grades, assessments]);

  const studentResults = useMemo(() => {
    const enrollment = classEnrollments.find((e) => e.id === selectedEnrollmentId) || classEnrollments[0];
    if (!enrollment) return null;
    const rule = rules.find((r) => r.school_year_id === yearId && r.class_id === enrollment.class_id) || rules.find((r) => r.school_year_id === yearId && !r.class_id);
    const subjectsWithGrades = subjects.map((subject) => ({ subject, average: getSubjectAverage(enrollment.id, subject, term, rule) })).filter((x) => x.average !== null);
    const average = subjectsWithGrades.length ? round(subjectsWithGrades.reduce((s, item) => s + Number(item.average), 0) / subjectsWithGrades.length) : null;
    return { enrollment, subjectsWithGrades, average, rule };
  }, [yearEnrollments, classEnrollments, selectedEnrollmentId, subjects, term, rules, yearId, getSubjectAverage]);

  async function createAssessment() {
    const client = supabase();
    if (!client || isReadOnly || !yearId || !classId || !subjectId || !assessmentTitle.trim()) { announce('Choisissez une année, une classe, une matière et un intitulé.', true); return; }
    const max = Number(scoreMax); const coef = Number(assessmentCoefficient);
    if (!Number.isFinite(max) || max <= 0 || max > 1000 || !Number.isFinite(coef) || coef <= 0 || coef > 100) { announce('Le barème et le coefficient doivent être des nombres positifs valides.', true); return; }
    if (new Date(`${assessmentDate}T00:00:00`).getTime() > new Date(`${new Date().toISOString().slice(0, 10)}T23:59:59`).getTime()) { announce('La date de l’évaluation ne peut pas être dans le futur.', true); return; }
    setSaving(true);
    const actor = (await client.auth.getUser()).data.user;
    const { data, error } = await client.from('school_assessments').insert({ school_year_id: yearId, class_id: classId, subject_id: subjectId, term, title: assessmentTitle.trim(), assessment_type: assessmentType, assessment_date: assessmentDate, score_max: max, coefficient: coef, status: 'open', created_by: actor?.id || null }).select('id').single();
    setSaving(false);
    if (error || !data) { announce('Création impossible. Vérifiez les autorisations et les paramètres de cette évaluation.', true); return; }
    setAssessmentId(data.id); announce('Évaluation créée. Vous pouvez maintenant saisir les notes.'); setTab('entry'); await refresh();
  }

  async function lockAssessment(assessment: Assessment) {
    const client = supabase();
    if (!client || role !== 'admin' || isReadOnly) { announce('Seul l’administrateur peut verrouiller une évaluation.', true); return; }
    if (assessment.status === 'locked' || assessment.status === 'cancelled') return;
    const { error } = await client.from('school_assessments').update({ status: 'locked' }).eq('id', assessment.id);
    if (error) { announce('Impossible de verrouiller cette évaluation.', true); return; }
    announce('Évaluation verrouillée. Les notes ne peuvent plus être modifiées depuis cet écran.'); await refresh();
  }

  async function saveClassGrades() {
    const client = supabase();
    if (!client || !selectedAssessment || isReadOnly) return;
    const roster = enrollments.filter((e) => e.school_year_id === selectedAssessment.school_year_id && e.class_id === selectedAssessment.class_id);
    if (!roster.length) { announce('Aucun élève inscrit dans cette classe pour cette année scolaire.', true); return; }
    const rows: any[] = [];
    for (const enrollment of roster) {
      const status = gradeStatuses[enrollment.id] || 'missing';
      const rawScore = (gradeInputs[enrollment.id] || '').trim();
      if (status === 'entered' && rawScore === '') { announce(`Saisissez une note ou choisissez un statut pour ${safeName(enrollment)}.`, true); return; }
      const numericScore = rawScore === '' ? 0 : Number(rawScore);
      if (!Number.isFinite(numericScore) || numericScore < 0 || numericScore > Number(selectedAssessment.score_max)) { announce(`La note de ${safeName(enrollment)} doit être comprise entre 0 et ${selectedAssessment.score_max}.`, true); return; }
      if (status !== 'entered' && status !== 'missing' && rawScore !== '') { announce(`Effacez la note de ${safeName(enrollment)} avant de choisir un statut d’absence ou de dispense.`, true); return; }
      rows.push({ enrollment_id: enrollment.id, subject_id: selectedAssessment.subject_id, term: selectedAssessment.term, assessment_id: selectedAssessment.id, assessment_label: selectedAssessment.title, assessment_date: selectedAssessment.assessment_date, score: numericScore, score_max: selectedAssessment.score_max, coefficient: selectedAssessment.coefficient, status, remarks: null });
    }
    setSaving(true);
    const { error } = await client.from('student_grades').upsert(rows, { onConflict: 'enrollment_id,subject_id,term,assessment_label' });
    setSaving(false);
    if (error) { announce('Les notes n’ont pas pu être enregistrées. Vérifiez la migration 018 et les autorisations.', true); return; }
    announce('Les résultats de la classe ont été enregistrés. Les statuts non notés ne sont pas inclus dans les moyennes.'); await refresh();
  }

  async function saveRule() {
    const client = supabase();
    if (!client || role !== 'admin' || !yearId) { announce('Seul un administrateur peut modifier les règles de calcul.', true); return; }
    const comp = Number(compositionWeight); const exam = Number(examWeight); const other = Number(otherWeight); const scaleValue = Number(reportScale);
    if (ruleMethod === 'categories' && comp + exam + other !== 100) { announce('Les poids des compositions, examens et autres évaluations doivent totaliser 100 %.', true); return; }
    if (![comp, exam, other, scaleValue].every(Number.isFinite) || comp < 0 || exam < 0 || other < 0 || scaleValue <= 0) { announce('Vérifiez les paramètres de calcul.', true); return; }
    const existing = rules.find((r) => r.school_year_id === yearId && r.class_id === (classId || null));
    const values = { school_year_id: yearId, class_id: classId || null, calculation_method: ruleMethod, composition_weight: comp, exam_weight: exam, other_weight: other, report_scale: scaleValue, is_approved: true };
    setSaving(true);
    const result = existing?.id ? await client.from('school_grade_rules').update({ ...values, approved_at: new Date().toISOString(), approved_by: (await client.auth.getUser()).data.user?.id || null, updated_by: (await client.auth.getUser()).data.user?.id || null }).eq('id', existing.id) : await client.from('school_grade_rules').insert({ ...values, approved_at: new Date().toISOString(), approved_by: (await client.auth.getUser()).data.user?.id || null, updated_by: (await client.auth.getUser()).data.user?.id || null });
    setSaving(false);
    if (result.error) { announce('Impossible d’enregistrer les règles. Seule la direction ou l’administration peut les configurer.', true); return; }
    announce('Règles de calcul enregistrées. Les bulletins déjà publiés ne sont pas recalculés automatiquement.'); await refresh();
  }

  async function addSubject() {
    const client = supabase();
    if (!client || role !== 'admin' || !subjectCode.trim() || !subjectName.trim()) { announce('Un code et un nom de matière sont requis. Action réservée à l’administrateur.', true); return; }
    const { error } = await client.from('school_subjects').insert({ code: subjectCode.trim().toUpperCase(), name: subjectName.trim(), is_active: true });
    if (error) { announce('Matière non créée. Vérifiez que le code n’est pas déjà utilisé.', true); return; }
    setSubjectCode(''); setSubjectName(''); announce('Matière ajoutée au référentiel.'); await refresh();
  }

  function buildBulletin(enrollment: Enrollment) {
    const rule = rules.find((r) => r.school_year_id === yearId && r.class_id === enrollment.class_id) || rules.find((r) => r.school_year_id === yearId && !r.class_id);
    const reportScaleValue = Number(rule?.report_scale || 20);
    const subjectRows = subjects.map((subject) => ({ subject_id: subject.id, subject: subject.name, average: getSubjectAverage(enrollment.id, subject, term, rule) })).filter((item) => item.average !== null);
    const average = subjectRows.length ? round(subjectRows.reduce((sum, item) => sum + Number(item.average), 0) / subjectRows.length) : null;
    const relevantAssessments = assessments.filter((a) => a.school_year_id === yearId && a.class_id === enrollment.class_id && a.term === term && a.status !== 'cancelled' && a.status !== 'draft');
    const expectedCount = relevantAssessments.length;
    const relevantIds = new Set(relevantAssessments.map((a) => a.id));
    const gradeCount = grades.filter((g) => g.enrollment_id === enrollment.id && g.term === term && g.assessment_id && relevantIds.has(g.assessment_id) && g.status !== 'missing').length;
    return { enrollment_id: enrollment.id, term, status: 'draft', average, report_scale: reportScaleValue, payload: { student_name: safeName(enrollment), student_number: enrollment.student?.student_number || '', class_name: enrollment.school_class?.name || '', school_year: years.find((y) => y.id === yearId)?.label || '', term_label: TERMS.find((t) => t.value === term)?.label || term, subjects: subjectRows, grade_count: gradeCount, assessment_count: expectedCount, calculation_method: rule?.calculation_method || 'coefficients', incomplete: expectedCount > 0 && gradeCount < expectedCount }, created_by: null };
  }

  async function generateBulletins() {
    const client = supabase();
    if (!client || isReadOnly || role !== 'admin') { announce('La préparation des bulletins est réservée à l’administration dans cette version.', true); return; }
    const roster = classEnrollments;
    if (!roster.length) { announce('Aucun élève inscrit dans la classe sélectionnée.', true); return; }
    const drafts = roster.map(buildBulletin);
    if (drafts.some((b) => !b.payload.subjects.length)) { announce('Certains élèves n’ont aucune note saisie. Complétez les notes avant de préparer les bulletins.', true); return; }
    const user = (await client.auth.getUser()).data.user;
    setSaving(true);
    let failed = false;
    for (const draft of drafts) {
      const existing = bulletins.find((b) => b.enrollment_id === draft.enrollment_id && b.term === term && b.status === 'draft');
      const data = { ...draft, created_by: user?.id || null, generated_at: new Date().toISOString() };
      const result = existing ? await client.from('school_bulletins').update(data).eq('id', existing.id) : await client.from('school_bulletins').insert(data);
      if (result.error) { failed = true; break; }
    }
    setSaving(false);
    if (failed) { announce('La préparation des bulletins a été interrompue. Actualisez la page et vérifiez les bulletins en brouillon.', true); return; }
    announce(`${drafts.length} bulletin(s) préparé(s) en brouillon. Vérifiez les résultats avant publication.`); setTab('bulletins'); await refresh();
  }

  async function publishBulletin(bulletin: Bulletin) {
    const client = supabase();
    if (!client || role !== 'admin' || isReadOnly) { announce('Seul l’administrateur peut publier un bulletin dans cette version.', true); return; }
    const payload = bulletin.payload || {};
    if (!Array.isArray(payload.subjects) || !payload.subjects.length || bulletin.average === null || payload.incomplete) { announce('Ce bulletin ne contient pas assez de résultats pour être publié.', true); return; }
    const existingPublished = bulletins.find((b) => b.enrollment_id === bulletin.enrollment_id && b.term === bulletin.term && b.status === 'published');
    setSaving(true);
    if (existingPublished) {
      const { error: supersedeError } = await client.from('school_bulletins').update({ status: 'superseded' }).eq('id', existingPublished.id);
      if (supersedeError) { setSaving(false); announce('Impossible d’archiver la version publiée précédente.', true); return; }
    }
    const user = (await client.auth.getUser()).data.user;
    const { error } = await client.from('school_bulletins').update({ status: 'published', published_at: new Date().toISOString(), published_by: user?.id || null, supersedes_id: existingPublished?.id || null }).eq('id', bulletin.id);
    setSaving(false);
    if (error) { announce('Publication impossible. L’ancienne version, si présente, a pu être archivée ; actualisez la page avant de réessayer.', true); return; }
    announce('Bulletin publié. Une nouvelle version remplacera l’ancienne sans effacer son historique.'); await refresh();
  }

  function exportStudentReport(enrollment: Enrollment) {
    const rule = rules.find((r) => r.school_year_id === yearId && r.class_id === enrollment.class_id) || rules.find((r) => r.school_year_id === yearId && !r.class_id);
    const subjectRows = subjects.map((subject) => ({ subject: subject.name, average: getSubjectAverage(enrollment.id, subject, term, rule) })).filter((item) => item.average !== null);
    const average = subjectRows.length ? round(subjectRows.reduce((sum, item) => sum + Number(item.average), 0) / subjectRows.length) : null;
    const rows = [['EPC BETHEL — RELEVÉ DE NOTES', ''], ['Élève', safeName(enrollment)], ['Matricule', enrollment.student?.student_number || ''], ['Classe', enrollment.school_class?.name || ''], ['Année scolaire', years.find((y) => y.id === yearId)?.label || ''], ['Période', TERMS.find((t) => t.value === term)?.label || term], [], ['Matière', `Moyenne /${rule?.report_scale || 20}`], ...subjectRows.map((x) => [x.subject, String(x.average)]), [], ['Moyenne générale', average === null ? 'Non calculable' : String(average)]];
    const csv = rows.map((r) => r.map((v) => `"${String(v ?? '').replaceAll('"', '""')}"`).join(';')).join('\r\n');
    const url = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' }));
    const a = document.createElement('a'); a.href = url; a.download = `epc-bethel-releve-${(enrollment.student?.student_number || 'eleve').replace(/[^a-zA-Z0-9-_]/g, '-')}-${term}.csv`; a.click(); URL.revokeObjectURL(url);
  }

  const publishedBulletins = bulletins.filter((b) => b.status === 'published' && yearEnrollments.some((e) => e.id === b.enrollment_id) && b.term === term);
  const selectedBulletin = publishedBulletins.find((b) => b.id === selectedBulletinId);
  const drafts = bulletins.filter((b) => b.status === 'draft' && yearEnrollments.some((e) => e.id === b.enrollment_id) && b.term === term);
  const currentYear = years.find((y) => y.id === yearId);
  const currentRule = rules.find((r) => r.school_year_id === yearId && r.class_id === (classId || null)) || rules.find((r) => r.school_year_id === yearId && !r.class_id);
  const rosterForAssessment = selectedAssessment ? enrollments.filter((e) => e.school_year_id === selectedAssessment.school_year_id && e.class_id === selectedAssessment.class_id) : [];

  const tabs: { id: Tab; label: string; icon: typeof GraduationCap }[] = [
    { id: 'overview', label: 'Vue d’ensemble', icon: GraduationCap }, { id: 'entry', label: 'Saisie des notes', icon: ClipboardList },
    { id: 'results', label: 'Résultats des élèves', icon: Users }, { id: 'bulletins', label: 'Bulletins trimestriels', icon: FileText },
    { id: 'settings', label: 'Configuration', icon: Settings2 },
  ];

  return <>
    <div className="notes-bulletins-sticky">
    <div className="page-heading notes-bulletins-heading">
      <div><div className="eyebrow">SUIVI PÉDAGOGIQUE · PRIMAIRE</div><h1>Notes et bulletins</h1><p>Préparez les évaluations, suivez les résultats et publiez les bulletins trimestriels.</p></div>
      <div className="heading-actions"><button className="button button-secondary" onClick={() => void refresh()} disabled={loading}><RefreshCw size={16}/> Actualiser</button></div>
    </div>
    {!connected && <div className="inline-notice"><AlertCircle size={16}/> Mode aperçu : aucune note réelle n’est chargée. Configurez Supabase et appliquez les migrations scolaires.</div>}
    {notice && <div className="inline-notice" role="status" style={errorNotice ? { borderColor: 'var(--danger, #b91c1c)' } : undefined}>{errorNotice ? <AlertCircle size={16}/> : <Check size={16}/>} {notice}</div>}
    <section className="panel notes-bulletins-filter-panel">
      <div className="form-grid notes-bulletins-filters">
        <label className="form-field"><span>Année scolaire</span><select value={yearId} onChange={(e) => setYearId(e.target.value)}><option value="">Choisir une année</option>{years.map((y) => <option key={y.id} value={y.id}>{y.label}{y.is_current ? ' · En cours' : ''}{y.is_closed ? ' · Clôturée' : ''}</option>)}</select></label>
        <label className="form-field"><span>Trimestre</span><select value={term} onChange={(e) => setTerm(e.target.value as Term)}>{TERMS.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}</select></label>
        <label className="form-field"><span>Classe</span><select value={classId} onChange={(e) => { setClassId(e.target.value); setAssessmentId(''); }}><option value="">Toutes les classes</option>{classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
      </div>
      {currentYear?.is_closed && <div className="inline-notice"><AlertCircle size={16}/> Cette année scolaire est clôturée. La consultation reste disponible, mais les nouvelles saisies doivent être bloquées.</div>}
      <div className="table-actions notes-bulletins-tabs">{tabs.map((item) => { const Icon = item.icon; return <button key={item.id} className={`button ${tab === item.id ? 'button-primary' : 'button-secondary'}`} onClick={() => setTab(item.id)}><Icon size={15}/>{item.label}</button>; })}</div>
    </section>
    </div>

    {tab === 'overview' && <>
      <div className="metric-strip">
        <div className="metric-mini"><span>Élèves inscrits</span><strong>{yearEnrollments.length}</strong></div>
        <div className="metric-mini"><span>Évaluations du trimestre</span><strong>{termAssessments.length}</strong></div>
        <div className="metric-mini"><span>Notes renseignées</span><strong>{currentGrades.filter((g) => g.status === 'entered').length}</strong></div>
        <div className="metric-mini"><span>Bulletins publiés</span><strong>{publishedBulletins.length}</strong></div>
      </div>
      <section className="panel table-panel"><div className="panel-toolbar"><div><h2><BookOpen size={19}/> Avancement par classe</h2><p>Les indicateurs reflètent les données enregistrées pour le trimestre sélectionné.</p></div></div><div className="table-scroll"><table><thead><tr><th>Classe</th><th>Élèves</th><th>Évaluations</th><th>Notes saisies</th><th>Bulletins publiés</th><th>Action</th></tr></thead><tbody>{classes.filter((c) => !classId || c.id === classId).map((c) => { const roster = yearEnrollments.filter((e) => e.class_id === c.id); const assessmentCount = assessments.filter((a) => a.school_year_id === yearId && a.class_id === c.id && a.term === term && a.status !== 'cancelled').length; const gradeCount = grades.filter((g) => g.term === term && roster.some((e) => e.id === g.enrollment_id) && g.status === 'entered').length; const bulletinCount = publishedBulletins.filter((b) => roster.some((e) => e.id === b.enrollment_id)).length; return <tr key={c.id}><td><strong>{c.name}</strong></td><td>{roster.length}</td><td>{assessmentCount}</td><td>{gradeCount}</td><td>{bulletinCount}/{roster.length}</td><td><button className="button button-secondary" onClick={() => { setClassId(c.id); setTab('entry'); }}><ChevronRight size={15}/> Ouvrir</button></td></tr>; })}{!classes.length && <tr><td colSpan={6} className="empty-cell">Aucune classe active n’est configurée.</td></tr>}</tbody></table></div></section>
    </>}

    {tab === 'entry' && <>
      <section className="panel"><div className="panel-toolbar"><div><h2><Plus size={19}/> Créer une évaluation</h2><p>Une évaluation est définie une seule fois pour une classe, une matière et un trimestre.</p></div></div>
        <div className="form-grid">
          <label className="form-field"><span>Matière *</span><select value={subjectId} onChange={(e) => setSubjectId(e.target.value)}><option value="">Choisir une matière</option>{subjects.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
          <label className="form-field"><span>Intitulé *</span><input value={assessmentTitle} onChange={(e) => setAssessmentTitle(e.target.value)} maxLength={120} placeholder="Ex. Composition n° 1"/></label>
          <label className="form-field"><span>Type</span><select value={assessmentType} onChange={(e) => setAssessmentType(e.target.value)}>{ASSESSMENT_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}</select></label>
          <label className="form-field"><span>Date</span><input type="date" value={assessmentDate} onChange={(e) => setAssessmentDate(e.target.value)} max={new Date().toISOString().slice(0, 10)}/></label>
          <label className="form-field"><span>Barème maximal</span><input type="number" min="0.25" max="1000" step="0.25" value={scoreMax} onChange={(e) => setScoreMax(e.target.value)}/></label>
          <label className="form-field"><span>Coefficient</span><input type="number" min="0.1" max="100" step="0.1" value={assessmentCoefficient} onChange={(e) => setAssessmentCoefficient(e.target.value)}/></label>
        </div><div className="modal-footer"><button className="button button-primary" onClick={() => void createAssessment()} disabled={!connected || isReadOnly || saving || !yearId || !classId || currentYear?.is_closed}><Plus size={16}/> Créer l’évaluation</button></div>
      </section>
      <section className="panel"><div className="panel-toolbar"><div><h2><ClipboardList size={19}/> Saisie collective</h2><p>Choisissez une évaluation, puis saisissez les résultats de tous les élèves de sa classe.</p></div></div>
        <label className="form-field"><span>Évaluation à saisir</span><select value={assessmentId} onChange={(e) => setAssessmentId(e.target.value)}><option value="">Choisir une évaluation</option>{termAssessments.filter((a) => a.status !== 'cancelled').map((a) => <option key={a.id} value={a.id}>{a.school_class?.name || classes.find((c) => c.id === a.class_id)?.name} · {a.subject?.name || subjects.find((s) => s.id === a.subject_id)?.name} · {a.title} (/{a.score_max})</option>)}</select></label>
        {selectedAssessment && <><div className="table-scroll" style={{ marginTop: 16 }}><table><thead><tr><th>Élève</th><th>Note /{selectedAssessment.score_max}</th><th>Statut</th></tr></thead><tbody>{rosterForAssessment.map((e) => <tr key={e.id}><td><strong>{safeName(e)}</strong><small style={{ display: 'block', opacity: .7 }}>{e.student?.student_number || 'Sans matricule'}</small></td><td><input aria-label={`Note de ${safeName(e)}`} type="number" min="0" max={selectedAssessment.score_max} step="0.25" value={gradeInputs[e.id] || ''} disabled={isReadOnly || selectedAssessment.status === 'locked' || currentYear?.is_closed} placeholder="—" onChange={(ev) => { const value = ev.target.value; setGradeInputs((old) => ({ ...old, [e.id]: value })); setGradeStatuses((old) => ({ ...old, [e.id]: value === '' ? 'missing' : 'entered' })); }} style={{ maxWidth: 130 }}/></td><td><select aria-label={`Statut de ${safeName(e)}`} value={gradeStatuses[e.id] || 'missing'} disabled={isReadOnly || selectedAssessment.status === 'locked' || currentYear?.is_closed} onChange={(ev) => { setGradeStatuses((old) => ({ ...old, [e.id]: ev.target.value })); if (ev.target.value !== 'entered') setGradeInputs((old) => ({ ...old, [e.id]: '' })); }}>{Object.entries(STATUS_LABEL).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></td></tr>)}{!rosterForAssessment.length && <tr><td colSpan={3} className="empty-cell">Aucun élève inscrit dans cette classe pour l’année choisie.</td></tr>}</tbody></table></div><div className="modal-footer"><span className="table-footer">Les absences et les notes manquantes sont distinctes d’une note égale à zéro.</span><button className="button button-primary" onClick={() => void saveClassGrades()} disabled={!connected || isReadOnly || saving || selectedAssessment.status === 'locked' || currentYear?.is_closed}><Save size={16}/>{saving ? 'Enregistrement…' : 'Enregistrer les notes de la classe'}</button></div></>}
      </section>
      <section className="panel table-panel"><div className="panel-toolbar"><div><h2>Évaluations existantes</h2><p>{termAssessments.length} évaluation(s) dans le trimestre sélectionné.</p></div></div><div className="table-scroll"><table><thead><tr><th>Date</th><th>Classe</th><th>Matière</th><th>Évaluation</th><th>Barème</th><th>Coef.</th><th>État</th></tr></thead><tbody>{termAssessments.map((a) => <tr key={a.id}><td>{frenchDate(a.assessment_date)}</td><td>{a.school_class?.name || classes.find((c) => c.id === a.class_id)?.name || '—'}</td><td>{a.subject?.name || subjects.find((s) => s.id === a.subject_id)?.name || '—'}</td><td>{a.title}</td><td>{a.score_max}</td><td>{a.coefficient}</td><td><div className="table-actions"><span>{a.status === 'locked' ? 'Verrouillée' : a.status === 'cancelled' ? 'Annulée' : 'Ouverte'}</span>{a.status === 'open' && role === 'admin' && <button className="button button-secondary" onClick={() => void lockAssessment(a)} disabled={saving || isReadOnly}><Check size={14}/> Verrouiller</button>}</div></td></tr>)}{!termAssessments.length && <tr><td colSpan={7} className="empty-cell">Aucune évaluation créée pour ces critères.</td></tr>}</tbody></table></div></section>
    </>}

    {tab === 'results' && <section className="panel table-panel"><div className="panel-toolbar"><div><h2><Users size={19}/> Résultats individuels</h2><p>Consultez les moyennes calculées à partir des notes enregistrées.</p></div><div className="table-actions"><select aria-label="Choisir un élève" value={selectedEnrollmentId} onChange={(e) => setSelectedEnrollmentId(e.target.value)}><option value="">Choisir un élève</option>{classEnrollments.map((e) => <option key={e.id} value={e.id}>{safeName(e)} · {e.student?.student_number}</option>)}</select></div></div>
      {studentResults ? <><div className="metric-strip"><div className="metric-mini"><span>Élève</span><strong>{safeName(studentResults.enrollment)}</strong></div><div className="metric-mini"><span>Moyenne générale provisoire</span><strong>{studentResults.average === null ? '—' : `${studentResults.average.toLocaleString('fr-FR', { maximumFractionDigits: 2 })}/${scale}`}</strong></div><div className="metric-mini"><span>Matières avec note</span><strong>{studentResults.subjectsWithGrades.length}</strong></div></div><div className="table-scroll"><table><thead><tr><th>Matière</th><th>Moyenne /{scale}</th><th>Évaluations enregistrées</th><th>Détail</th></tr></thead><tbody>{studentResults.subjectsWithGrades.map(({ subject, average }) => { const sg = grades.filter((g) => g.enrollment_id === studentResults.enrollment.id && g.subject_id === subject.id && g.term === term); return <tr key={subject.id}><td><strong>{subject.name}</strong></td><td>{average}</td><td>{sg.filter((g) => g.status === 'entered').length}</td><td>{sg.map((g) => `${g.assessment_label}: ${g.status === 'entered' ? `${g.score}/${g.score_max}` : STATUS_LABEL[g.status] || g.status}`).join(' · ') || '—'}</td></tr>; })}{!studentResults.subjectsWithGrades.length && <tr><td colSpan={4} className="empty-cell">Aucune note exploitable pour cet élève et cette période.</td></tr>}</tbody></table></div><div className="modal-footer"><button className="button button-secondary" onClick={() => exportStudentReport(studentResults.enrollment)} disabled={!studentResults.subjectsWithGrades.length}><Download size={16}/> Exporter le relevé CSV</button></div></> : <div className="empty-cell">Sélectionnez un élève pour afficher ses résultats.</div>}
      <div className="table-footer">Les résultats affichés sont provisoires. Les règles de calcul et les notes disponibles déterminent la moyenne.</div>
    </section>}

    {tab === 'bulletins' && <>
      <section className="panel"><div className="panel-toolbar"><div><h2><FileCheck2 size={19}/> Préparer les bulletins</h2><p>Générez des brouillons à partir des notes saisies, puis vérifiez-les avant publication.</p></div></div><div className="inline-notice"><AlertCircle size={16}/> La publication est réservée à l’administrateur dans cette première version. Les bulletins sont des instantanés : les changements ultérieurs de notes ne les réécrivent pas.</div><div className="modal-footer"><button className="button button-primary" onClick={() => void generateBulletins()} disabled={!connected || role !== 'admin' || isReadOnly || saving || !classEnrollments.length || currentYear?.is_closed}><FileText size={16}/> Préparer les bulletins de la classe</button></div></section>
      <section className="panel table-panel"><div className="panel-toolbar"><div><h2>Brouillons à vérifier</h2><p>{drafts.length} bulletin(s) en brouillon pour la période.</p></div></div><div className="table-scroll"><table><thead><tr><th>Élève</th><th>Moyenne</th><th>État</th><th>Généré le</th><th>Action</th></tr></thead><tbody>{drafts.map((b) => { const e = yearEnrollments.find((item) => item.id === b.enrollment_id); const incomplete = Boolean(b.payload?.incomplete); return <tr key={b.id}><td>{safeName(e)}</td><td>{b.average === null ? '—' : `${Number(b.average).toLocaleString('fr-FR', { maximumFractionDigits: 2 })}/${b.report_scale}`}</td><td>{incomplete ? 'À vérifier : notes manquantes possibles' : 'À vérifier avant publication'}</td><td>{frenchDate(b.generated_at)}</td><td><button className="button button-primary" disabled={saving || role !== 'admin' || isReadOnly || b.average === null} onClick={() => void publishBulletin(b)}><Check size={15}/> Publier</button></td></tr>; })}{!drafts.length && <tr><td colSpan={5} className="empty-cell">Aucun brouillon pour ces critères. Préparez les bulletins après la saisie des notes.</td></tr>}</tbody></table></div></section>
      <section className="panel table-panel"><div className="panel-toolbar"><div><h2>Bulletins publiés</h2><p>{publishedBulletins.length} bulletin(s) publiés pour la période.</p></div></div><div className="table-scroll"><table><thead><tr><th>Élève</th><th>Classe</th><th>Moyenne</th><th>Publication</th><th>État</th></tr></thead><tbody>{publishedBulletins.map((b) => { const e = yearEnrollments.find((item) => item.id === b.enrollment_id); return <tr key={b.id}><td>{b.payload?.student_name || safeName(e)}</td><td>{b.payload?.class_name || e?.school_class?.name || '—'}</td><td>{b.average === null ? '—' : `${Number(b.average).toLocaleString('fr-FR', { maximumFractionDigits: 2 })}/${b.report_scale}`}</td><td>{frenchDate(b.published_at)}</td><td><div className="table-actions"><span className="status-pill status-success">Publié</span><button className="button button-secondary" onClick={() => setSelectedBulletinId(b.id)}><FileText size={15}/> Voir / imprimer</button></div></td></tr>; })}{!publishedBulletins.length && <tr><td colSpan={5} className="empty-cell">Aucun bulletin publié pour ces critères.</td></tr>}</tbody></table></div><div className="table-footer">Pour obtenir un PDF, ouvrez un bulletin ci-dessous et utilisez l’impression du navigateur avec la destination « Enregistrer au format PDF ».</div></section>
      {selectedBulletin && <section className="panel print-bulletin"><div className="panel-toolbar"><div><h2>Aperçu du bulletin publié</h2><p>Version figée au moment de la publication.</p></div><div className="table-actions"><button className="button button-secondary" onClick={() => setSelectedBulletinId('')}><XCircle size={15}/> Fermer</button><button className="button button-primary" onClick={() => window.print()}><Download size={15}/> Imprimer / PDF</button></div></div><div className="bulletin-document"><div className="bulletin-document-header"><h1>EPC BETHEL</h1><p>ASSEMBLÉES DE DIEU JEAN FOLLY</p><h2>BULLETIN SCOLAIRE</h2><p>{selectedBulletin.payload?.school_year || currentYear?.label || ''} · {selectedBulletin.payload?.term_label || term}</p></div><div className="bulletin-student-info"><p><strong>Élève :</strong> {selectedBulletin.payload?.student_name || '—'}</p><p><strong>Matricule :</strong> {selectedBulletin.payload?.student_number || '—'}</p><p><strong>Classe :</strong> {selectedBulletin.payload?.class_name || '—'}</p></div><table><thead><tr><th>Matière</th><th>Moyenne /{selectedBulletin.report_scale}</th></tr></thead><tbody>{(selectedBulletin.payload?.subjects || []).map((subject: any) => <tr key={subject.subject_id}><td>{subject.subject}</td><td>{Number(subject.average).toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td></tr>)}</tbody></table><div className="bulletin-average"><strong>Moyenne générale</strong><strong>{selectedBulletin.average === null ? '—' : `${Number(selectedBulletin.average).toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}/${selectedBulletin.report_scale}`}</strong></div><p className="bulletin-appreciation"><strong>Appréciation générale :</strong> ...................................................................................................</p><div className="bulletin-signatures"><span>Signature de l’enseignant</span><span>Direction</span></div><p className="bulletin-footnote">Bulletin publié le {frenchDate(selectedBulletin.published_at)}. Toute correction doit suivre la procédure de rectification de l’établissement.</p></div></section>}
    </>}

    {tab === 'settings' && <>
      <section className="panel"><div className="panel-toolbar"><div><h2><Settings2 size={19}/> Règles de calcul</h2><p>Les paramètres s’appliquent à l’année et à la classe sélectionnées. La configuration doit être validée par l’administration.</p></div></div>
        <div className="form-grid"><label className="form-field"><span>Méthode de calcul</span><select value={ruleMethod} onChange={(e) => setRuleMethod(e.target.value as GradeRule['calculation_method'])}><option value="simple">Moyenne simple</option><option value="coefficients">Moyenne pondérée par coefficient</option><option value="categories">Pondération par catégorie</option></select></label><label className="form-field"><span>Échelle du bulletin</span><input type="number" min="1" max="1000" step="1" value={reportScale} onChange={(e) => setReportScale(e.target.value)}/></label>{ruleMethod === 'categories' && <><label className="form-field"><span>Poids des compositions (%)</span><input type="number" min="0" max="100" value={compositionWeight} onChange={(e) => setCompositionWeight(e.target.value)}/></label><label className="form-field"><span>Poids des examens (%)</span><input type="number" min="0" max="100" value={examWeight} onChange={(e) => setExamWeight(e.target.value)}/></label><label className="form-field"><span>Poids des autres évaluations (%)</span><input type="number" min="0" max="100" value={otherWeight} onChange={(e) => setOtherWeight(e.target.value)}/></label></>}</div>
        {ruleMethod === 'categories' && Number(compositionWeight) + Number(examWeight) + Number(otherWeight) !== 100 && <div className="inline-notice"><AlertCircle size={16}/> Les poids des compositions, examens et autres évaluations doivent totaliser 100 %.</div>}
        <div className="modal-footer"><button className="button button-primary" onClick={() => void saveRule()} disabled={!connected || role !== 'admin' || saving || !yearId || (ruleMethod === 'categories' && Number(compositionWeight) + Number(examWeight) + Number(otherWeight) !== 100)}><Save size={16}/> Enregistrer la règle</button>{role !== 'admin' && <span>Configuration réservée à l’administrateur.</span>}</div>
        <div className="table-footer">Règle actuelle : {currentRule ? `${currentRule.calculation_method}, échelle ${currentRule.report_scale}, ${currentRule.class_id ? 'spécifique à la classe' : 'règle générale de l’année'}.` : 'Aucune règle explicite ; la moyenne pondérée par coefficient sur 20 est utilisée par défaut.'}</div>
      </section>
      <section className="panel"><div className="panel-toolbar"><div><h2><BookOpen size={19}/> Matières</h2><p>Le référentiel des matières utilisées dans les évaluations.</p></div></div><div className="table-scroll"><table><thead><tr><th>Code</th><th>Matière</th><th>État</th></tr></thead><tbody>{subjects.map((s) => <tr key={s.id}><td>{s.code}</td><td>{s.name}</td><td>Active</td></tr>)}{!subjects.length && <tr><td colSpan={3} className="empty-cell">Aucune matière n’est configurée. Ajoutez-en une ci-dessous.</td></tr>}</tbody></table></div>
        {role === 'admin' && <><div className="form-grid" style={{ marginTop: 16 }}><label className="form-field"><span>Code de la matière</span><input value={subjectCode} onChange={(e) => setSubjectCode(e.target.value)} maxLength={20} placeholder="Ex. MATH"/></label><label className="form-field"><span>Nom de la matière</span><input value={subjectName} onChange={(e) => setSubjectName(e.target.value)} maxLength={100} placeholder="Ex. Mathématiques"/></label></div><div className="modal-footer"><button className="button button-secondary" onClick={() => void addSubject()} disabled={!connected || isReadOnly || !subjectCode.trim() || !subjectName.trim()}><Plus size={16}/> Ajouter une matière</button></div></>}
      </section>
      <section className="panel"><div className="panel-toolbar"><div><h2><AlertCircle size={19}/> Principes de publication</h2><p>Les notes et les bulletins sont des données scolaires sensibles.</p></div></div><ul><li>Les notes manquantes et les absences ne sont pas assimilées automatiquement à zéro.</li><li>Les bulletins publiés sont conservés comme instantanés et ne sont pas recalculés silencieusement.</li><li>Les corrections après publication doivent être autorisées et traçables.</li><li>Les permissions de la base de données restent la protection principale ; masquer un bouton ne remplace pas une règle d’accès.</li></ul></section>
    </>}
    {loading && <div className="table-footer">Chargement des données…</div>}
  </>;
}
