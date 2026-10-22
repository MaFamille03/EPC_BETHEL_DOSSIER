'use client';
import { useEffect, useMemo, useState } from 'react';
import { Download, Plus, Search, SlidersHorizontal, MoreHorizontal, Printer, X, CheckCircle2, ChevronLeft, ChevronRight, RefreshCw, Edit3, ArrowRightLeft, LogOut } from 'lucide-react';
import { modules } from '@/lib/modules';
import { PaymentsPage } from '@/components/payments-page';
import { supabase, isSupabaseConfigured } from '@/lib/supabase';
import { StudentImport } from '@/components/student-import';
import { useEPCAccess } from '@/components/access-context';

type Row = Record<string,string>;
type Option = {id:string; label:string};

export function ModulePage({section}:{section:string}) {
 const { isReadOnly } = useEPCAccess();
 const module=modules[section];
 const [query,setQuery]=useState(''); const [feePage,setFeePage]=useState(0); const [feeTotalCount,setFeeTotalCount]=useState(0); const [showForm,setShowForm]=useState(false); const [notice,setNotice]=useState(''); const [formMode,setFormMode]=useState<'record'|'concession'|'class-transfer'|'exit'>('record'); const [concessionView,setConcessionView]=useState(false); const [editingStudentId,setEditingStudentId]=useState<string|null>(null); const [workflowEnrollmentId,setWorkflowEnrollmentId]=useState<string|null>(null);
 const [rows,setRows]=useState<Row[]>([]); const [saving,setSaving]=useState(false); const [loadingRows,setLoadingRows]=useState(false);
 const [form,setForm]=useState<Record<string,string>>({});
 const [students,setStudents]=useState<Option[]>([]); const [classes,setClasses]=useState<Option[]>([]); const [enrollmentOptions,setEnrollmentOptions]=useState<Option[]>([]); const [schoolYear,setSchoolYear]=useState<Option|null>(null);
 const connected=isSupabaseConfigured();

 async function loadStudents(client:NonNullable<ReturnType<typeof supabase>>) {
   const [{data,error},{data:enrollmentData,error:enrollmentError},{data:guardianData,error:guardianError}] = await Promise.all([
     client.from('students').select('id,student_number,last_name,first_names,sex,birth_date,birth_place,status,notes').order('last_name').order('first_names').limit(1000),
     client.from('enrollments').select('student_id,classes(name),school_years(is_current)').in('status',['inscrit','reinscrit']).limit(2000),
     client.from('student_guardians').select('student_id,is_primary,relationship,guardians(full_name,phone,email,address,occupation)').eq('is_primary',true).limit(2000)
   ]);
   if(error) throw error; if(enrollmentError) throw enrollmentError; if(guardianError) throw guardianError;
   const classByStudent=new Map<string,string>(); (enrollmentData||[]).forEach((e:any)=>{if(e.school_years?.is_current)classByStudent.set(e.student_id,e.classes?.name||'À affecter')});
   const guardianByStudent=new Map<string,{name:string;phone:string;email:string;address:string;occupation:string;relationship:string}>();
   (guardianData||[]).forEach((g:any)=>{const x=Array.isArray(g.guardians)?g.guardians[0]:g.guardians;if(x)guardianByStudent.set(g.student_id,{name:x.full_name||'',phone:x.phone||'',email:x.email||'',address:x.address||'',occupation:x.occupation||'',relationship:g.relationship||'Responsable légal'})});
   setRows((data||[]).map((r:any)=>{const guardian=guardianByStudent.get(r.id);return {_id:r.id,_studentNumber:r.student_number,_lastName:r.last_name,_firstNames:r.first_names,_sex:r.sex||'',_birthDate:r.birth_date||'',_birthPlace:r.birth_place||'',_notes:r.notes||'',_guardianName:guardian?.name||'',_guardianPhone:guardian?.phone||'',_guardianEmail:guardian?.email||'',_guardianAddress:guardian?.address||'',_guardianOccupation:guardian?.occupation||'',_guardianRelationship:guardian?.relationship||'Responsable légal','Matricule':r.student_number,'Nom & prénoms':`${r.last_name} ${r.first_names}`,'Classe':classByStudent.get(r.id)||'À affecter','Responsable':guardian?.name||'—','Téléphone':guardian?.phone||'—','Statut':r.status==='actif'?'Actif':r.status==='transfere'?'Transféré':r.status==='sorti'?'Sorti':r.status==='archive'?'Archivé':r.status||'—'};}));
   setStudents((data||[]).filter((r:any)=>r.status==='actif').map((r:any)=>({id:r.id,label:`${r.last_name} ${r.first_names} · ${r.student_number}`})));
 }
 async function loadEnrollments(client:NonNullable<ReturnType<typeof supabase>>) {
   const [{data,error},{data:studentData,error:studentError},{data:classData,error:classError},{data:yearData,error:yearError}]=await Promise.all([
     client.from('enrollments').select('id,student_id,school_year_id,class_id,enrolled_on,status,notes,students(last_name,first_names,student_number),classes(name),school_years(label,is_current,is_closed)').order('enrolled_on',{ascending:false}).limit(1000),
     client.from('students').select('id,student_number,last_name,first_names').eq('status','actif').order('last_name').limit(1000),
     client.from('classes').select('id,name,code').eq('is_active',true).order('level_order').limit(100),
     client.from('school_years').select('id,label').eq('is_current',true).maybeSingle()
   ]);
   if(error) throw error; if(studentError) throw studentError; if(classError) throw classError; if(yearError) throw yearError;
   const currentEnrolled=new Set<string>((data||[]).filter((r:any)=>r.school_years?.is_current && ['inscrit','reinscrit'].includes(r.status)).map((r:any)=>r.student_id));
   setRows((data||[]).map((r:any)=>({_id:r.id,_studentId:r.student_id,_classId:r.class_id,_schoolYearId:r.school_year_id,_status:r.status,_yearCurrent:String(!!r.school_years?.is_current),_yearClosed:String(!!r.school_years?.is_closed),_notes:r.notes||'','Élève':r.students?`${r.students.last_name} ${r.students.first_names}`:'Élève inconnu','Année scolaire':r.school_years?.label||'—','Classe':r.classes?.name||'—','Date':r.enrolled_on||'—','Type':r.status==='reinscrit'?'Réinscription':r.status==='transfere'?'Transfert hors établissement':r.status==='sorti'?'Sortie':r.status==='annule'?'Annulation':'Inscription','Statut':r.status==='annule'?'Annulée':r.status==='sorti'?'Sorti':r.status==='transfere'?'Transféré hors établissement':r.status==='reinscrit'?'Réinscription active':r.status==='inscrit'?'Inscription active':r.status||'—'})));
   setStudents((studentData||[]).filter((r:any)=>!currentEnrolled.has(r.id)).map((r:any)=>({id:r.id,label:`${r.last_name} ${r.first_names} · ${r.student_number}`})));
   setClasses((classData||[]).map((r:any)=>({id:r.id,label:r.name})));
   setSchoolYear(yearData?{id:yearData.id,label:yearData.label}:null);
 }
 async function loadSchoolFees(client:NonNullable<ReturnType<typeof supabase>>, page=0, search=query) {
   const [{data:chargeData,error:chargeError},{data:enrollmentData,error:enrollmentError},{data:yearData,error:yearError}]=await Promise.all([
     client.rpc('get_school_fee_ledger',{p_school_year_id:null,p_limit:100,p_offset:page*100,p_query:search.trim()||null}),
     client.from('enrollments').select('id,students(last_name,first_names,student_number),classes(name),school_years(label)').in('status',['inscrit','reinscrit']).order('created_at',{ascending:false}).limit(1000),
     client.from('school_years').select('id,label').eq('is_current',true).maybeSingle()
   ]);
   if(chargeError)throw chargeError;if(enrollmentError)throw enrollmentError;if(yearError)throw yearError;
   setSchoolYear(yearData?{id:yearData.id,label:yearData.label}:null);
   const ledger=(chargeData||[]) as any[];
   setFeeTotalCount(ledger.length?Number(ledger[0].total_count||0):0);
   setFeePage(page);
   setRows(ledger.map((r:any)=>{
     const gross=Number(r.gross_amount||0);const discount=Number(r.discount_amount||0);const due=Number(r.amount_due||0);const paid=Number(r.amount_paid||0);const balance=Number(r.balance_due||0);
     return {_id:r.charge_id,'Élève':r.student_name||'—','Matricule':r.student_number||'—','Classe':r.class_name||'—','Année scolaire':r.school_year||'—','Nature des frais':`${r.category_name||'Frais'} · ${r.description||''}`,'Montant brut':`${new Intl.NumberFormat('fr-FR').format(gross)} FCFA`,'Réduction':`${new Intl.NumberFormat('fr-FR').format(discount)} FCFA`,'Montant dû':`${new Intl.NumberFormat('fr-FR').format(due)} FCFA`,'Déjà payé':`${new Intl.NumberFormat('fr-FR').format(paid)} FCFA`,'Reste à payer':`${new Intl.NumberFormat('fr-FR').format(balance)} FCFA`,'Situation':due===0&&gross>0?'Exonéré':balance<=0?'Soldé':paid<=0?'Impayé':'Partiel'};
   }));
   setEnrollmentOptions((enrollmentData||[]).map((r:any)=>({id:r.id,label:`${r.students?.last_name||''} ${r.students?.first_names||''} · ${r.classes?.name||'Classe ?'} · ${r.school_years?.label||'Année ?'}`})));
 }
 async function loadConcessions(client:NonNullable<ReturnType<typeof supabase>>) {
   const [{data,error},{data:enrollmentData,error:enrollmentError}] = await Promise.all([
     client.from('enrollment_concessions').select('id,enrollment_id,kind,percentage,fixed_amount,reason_code,reason_detail,status,requested_at,approved_at,enrollments(students(last_name,first_names),classes(name),school_years(label))').order('requested_at',{ascending:false}).limit(1000),
     client.from('enrollments').select('id,students(last_name,first_names,student_number),classes(name),school_years(label)').in('status',['inscrit','reinscrit']).order('created_at',{ascending:false}).limit(1000)
   ]);
   if(error)throw error; if(enrollmentError)throw enrollmentError;
   setRows((data||[]).map((r:any)=>({
     _id:r.id,
     'Élève':r.enrollments?.students?`${r.enrollments.students.last_name} ${r.enrollments.students.first_names}`:'—',
     'Classe':r.enrollments?.classes?.name||'—',
     'Année scolaire':r.enrollments?.school_years?.label||'—',
     'Réduction':r.kind==='percentage'?`${Number(r.percentage||0)} %`:`${new Intl.NumberFormat('fr-FR').format(Number(r.fixed_amount||0))} FCFA`,
     'Motif':r.reason_detail||r.reason_code||'—',
     'Statut':r.status==='requested'?'En attente':r.status==='approved'?'Approuvée':r.status==='rejected'?'Refusée':'Révoquée',
     'Demandée le':r.requested_at?new Date(r.requested_at).toLocaleDateString('fr-FR'):'—'
   })));
   setEnrollmentOptions((enrollmentData||[]).map((r:any)=>({id:r.id,label:`${r.students?.last_name||''} ${r.students?.first_names||''} · ${r.classes?.name||'Classe ?'} · ${r.school_years?.label||'Année ?'}`})));
 }

 async function refresh() {
   if(!connected || !['eleves','inscriptions','scolarite'].includes(section)) return;
   const client=supabase(); if(!client)return;
   setLoadingRows(true);
   try { if(section==='eleves') await loadStudents(client); else if(section==='inscriptions') await loadEnrollments(client); else if(section==='scolarite'&&concessionView) await loadConcessions(client); else await loadSchoolFees(client,feePage,query); }
   catch(e:any){setNotice(`Chargement impossible : ${e?.message||'vérifiez les migrations et les droits Supabase.'}`);}
   finally {setLoadingRows(false);}
 }
 useEffect(()=>{if(section==='scolarite'&&!concessionView){if(!connected){setRows([]);setFeeTotalCount(0);setSchoolYear(null);return;}const client=supabase();if(!client)return;setLoadingRows(true);void loadSchoolFees(client,feePage,query).catch((e:any)=>setNotice(`Chargement des frais impossible : ${e?.message||'vérifiez la migration financière 013 et les droits Supabase.'}`)).finally(()=>setLoadingRows(false));}},[section,connected,concessionView,feePage,query]);
 useEffect(()=>{if(!(section==='scolarite'&&!concessionView))void refresh();},[section,connected,concessionView]);
 const filtered=useMemo(()=>rows.filter(r=>Object.entries(r).some(([k,v])=>k!=='_id'&&String(v).toLowerCase().includes(query.toLowerCase()))),[rows,query]);
 if(!module)return <div className="empty-state"><h2>Page introuvable</h2><p>Cette rubrique n’existe pas.</p></div>;
 if(section==='paiements') return <PaymentsPage/>;
 const titleKeys=section==='scolarite'&&concessionView?['Élève','Classe','Année scolaire','Réduction','Motif','Statut','Demandée le']:section==='scolarite'?['Élève','Matricule','Classe','Année scolaire','Nature des frais','Montant brut','Réduction','Montant dû','Déjà payé','Reste à payer','Situation']:module.columns;
 async function saveRecord(){
   if(section==='eleves'&&connected){
     const client=supabase(); if(!client)return;
     if((editingStudentId&&!form['Matricule']?.trim())||!form['Nom']?.trim()||!form['Prénoms']?.trim()){setNotice('Veuillez renseigner le nom et les prénoms' + (editingStudentId ? ', ainsi que le matricule.' : '.'));return;}
     setSaving(true);
     const args={p_student_number:form['Matricule']?.trim()||null,p_last_name:form['Nom'].trim(),p_first_names:form['Prénoms'].trim(),p_sex:form['Sexe']||null,p_birth_date:form['Date de naissance']||null,p_birth_place:form['Lieu de naissance']||null,p_guardian_name:form['Nom du responsable']||null,p_guardian_phone:form['Téléphone du responsable']||null,p_guardian_address:form['Adresse du responsable']||null,p_notes:form['Notes']||null,p_guardian_email:form['E-mail du responsable']||null,p_guardian_occupation:form['Profession du responsable']||null,p_guardian_relationship:form['Lien avec l’élève']||'Responsable légal'};
     const {error}=editingStudentId
       ? await client.rpc('update_student_with_guardian',{p_student_id:editingStudentId,...args})
       : await client.rpc('create_student_with_guardian',args);
     setSaving(false); if(error){setNotice(`Enregistrement impossible : ${error.message}`);return;}
     setShowForm(false);setForm({});setEditingStudentId(null);setNotice(editingStudentId?'Dossier élève mis à jour.':'Dossier élève enregistré dans Supabase.');await refresh();return;
   }
   if(section==='inscriptions'&&formMode==='class-transfer'&&connected){
     const client=supabase(); if(!client)return;
     if(!workflowEnrollmentId||!form['Nouvelle classe']){setNotice('Sélectionnez la nouvelle classe.');return;}
     setSaving(true);
     const {error}=await client.rpc('transfer_student_class',{p_enrollment_id:workflowEnrollmentId,p_target_class_id:form['Nouvelle classe'],p_transfer_date:form['Date du transfert']||new Date().toISOString().slice(0,10),p_reason:form['Motif']||null});
     setSaving(false);if(error){setNotice(`Changement de classe impossible : ${error.message}`);return;}
     setShowForm(false);setForm({});setWorkflowEnrollmentId(null);setFormMode('record');setNotice('Changement de classe enregistré avec historique.');await refresh();return;
   }
   if(section==='inscriptions'&&formMode==='exit'&&connected){
     const client=supabase(); if(!client)return;
     if(!workflowEnrollmentId||!form['Type de sortie']){setNotice('Sélectionnez le type de sortie.');return;}
     if(!window.confirm('Confirmer la sortie de cet élève ? Cette action clôture son inscription active.'))return;
     const exitStatus=form['Type de sortie']==='Transfert vers un autre établissement'?'transfere':'sorti';
     setSaving(true);
     const {error}=await client.rpc('close_school_enrollment',{p_enrollment_id:workflowEnrollmentId,p_exit_status:exitStatus,p_exit_date:form['Date de sortie']||new Date().toISOString().slice(0,10),p_reason:form['Motif']||null});
     setSaving(false);if(error){setNotice(`Clôture impossible : ${error.message}`);return;}
     setShowForm(false);setForm({});setWorkflowEnrollmentId(null);setFormMode('record');setNotice(exitStatus==='transfere'?'Inscription clôturée : transfert hors établissement enregistré.':'Inscription clôturée : sortie définitive enregistrée.');await refresh();return;
   }
   if(section==='scolarite'&&formMode==='concession'&&connected){
     const client=supabase(); if(!client)return;
     if(!form['Inscription']||!form['Motif']){setNotice('Sélectionnez une inscription et renseignez le motif de la demande.');return;}
     const kind=form['Type de réduction']==='Montant fixe'?'fixed_amount':'percentage';
     const percentage=Number(form['Pourcentage']||0); const fixed=Number(String(form['Montant fixe']||'').replace(/\s/g,'').replace(/,/g,'.'));
     if(kind==='percentage'&&(!Number.isFinite(percentage)||percentage<0||percentage>100)){setNotice('Le pourcentage doit être compris entre 0 et 100.');return;}
     if(kind==='fixed_amount'&&(!Number.isSafeInteger(fixed)||fixed<0)){setNotice('Le montant fixe doit être un nombre entier positif en FCFA.');return;}
     setSaving(true);
     const {error}=await client.rpc('request_enrollment_concession',{p_enrollment_id:form['Inscription'],p_kind:kind,p_percentage:kind==='percentage'?percentage:null,p_fixed_amount:kind==='fixed_amount'?fixed:null,p_reason_code:form['Motif'],p_reason_detail:form['Précisions']||null,p_valid_from:form['Valable du']||null,p_valid_to:form['Valable jusqu’au']||null});
     setSaving(false);if(error){setNotice(`Demande de concession impossible : ${error.message}`);return;}
     setShowForm(false);setForm({});setFormMode('record');setConcessionView(true);setNotice('Demande de concession transmise. Elle doit être approuvée par la direction ou l’administration avant application.');await loadConcessions(client);return;
   }
   if(section==='scolarite'&&connected){
     const client=supabase(); if(!client)return;
     const amount=Number(String(form['Montant annuel']||'').replace(/\s/g,'').replace(/,/g,'.'));
     if(form['Nature des frais']&&form['Nature des frais']!=='Scolarité annuelle'){
       const code=form['Nature des frais']==='Inscription / réinscription'?'INSCRIPTION':form['Nature des frais']==='Frais annexes'?'ANNEXE':'AUTRE';
       if(!form['Inscription']||!Number.isSafeInteger(amount)||amount<=0||!form['Description']?.trim()){setNotice('Sélectionnez une inscription et renseignez la désignation et un montant entier en FCFA.');return;}
       setSaving(true);
       const {error}=await client.rpc('create_one_time_student_charge',{p_enrollment_id:form['Inscription'],p_fee_code:code,p_description:form['Description'],p_amount:amount,p_due_on:form['Date d’échéance']||null});
       setSaving(false);if(error){setNotice(`Création des frais impossible : ${error.message}`);return;}
       setShowForm(false);setForm({});setFeePage(0);setQuery('');setNotice('Frais ponctuels enregistrés. Ils sont intégrés au solde de l’élève.');await loadSchoolFees(client,0,'');return;
     }
     if(!form['Inscription']||!Number.isSafeInteger(amount)||amount<=0){setNotice('Sélectionnez une inscription et saisissez un montant annuel entier en FCFA.');return;}
     const dates=[1,2,3,4,5,6].map(i=>form[`Échéance ${i}`]||'');
     if(dates.some(d=>!d)||dates.some((d,i)=>i>0&&d<dates[i-1])){setNotice('Renseignez les six dates dans l’ordre chronologique.');return;}
     setSaving(true);
     const {error}=await client.rpc('create_six_installments',{p_enrollment_id:form['Inscription'],p_amount:amount,p_due_dates:dates,p_description:form['Description']||'Scolarité annuelle'});
     setSaving(false);if(error){setNotice(`Création des six échéances impossible : ${error.message}`);return;}
     setShowForm(false);setForm({});setFeePage(0);setQuery('');setNotice('Scolarité enregistrée. Le montant net et les six échéances tiennent compte d’une concession approuvée et encore valide, le cas échéant.');await loadSchoolFees(client,0,'');return;
   }
   if(section==='inscriptions'&&connected){
     const client=supabase(); if(!client)return;
     if(!schoolYear){setNotice('Aucune année scolaire active n’est configurée. Ouvrez Paramètres et définissez une année en cours.');return;}
     if(!form['Élève']||!form['Classe']){setNotice('Sélectionnez un élève et une classe.');return;}
     setSaving(true);
     const status=form['Type']==='Réinscription'?'reinscrit':'inscrit';
     const {error}=await client.rpc('create_school_enrollment',{p_student_id:form['Élève'],p_school_year_id:schoolYear.id,p_class_id:form['Classe'],p_enrolled_on:form['Date']||new Date().toISOString().slice(0,10),p_enrollment_type:status,p_notes:form['Notes']||null});
     setSaving(false);if(error){setNotice(error.code==='23505'?'Cet élève est déjà inscrit pour cette année scolaire.':`Inscription impossible : ${error.message}`);return;}
     setShowForm(false);setForm({});setNotice(`Inscription enregistrée pour l’année ${schoolYear.label}.`);await refresh();return;
   }
   const row:Row={}; titleKeys.forEach(k=>row[k]=form[k]||'—'); setRows(old=>[row,...old]);setShowForm(false);setForm({});setNotice(connected?'Cette rubrique n’est pas encore raccordée à la base de données : la ligne est uniquement temporaire.':'Ligne ajoutée à la liste de démonstration ; elle ne sera pas conservée après fermeture ou actualisation.');
 }
 function exportCsv(){const csv=[titleKeys.join(';'),...filtered.map(r=>titleKeys.map(k=>`"${String(r[k]||'').replaceAll('"','""')}"`).join(';'))].join('\n');const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8;'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=`epc-bethel-${section}.csv`;a.click();URL.revokeObjectURL(url);}
 function field(key:string){
   if(section==='scolarite'&&formMode==='concession'&&key==='Inscription')return <select required value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}><option value="">Sélectionner une inscription active</option>{enrollmentOptions.map(o=><option key={o.id} value={o.id}>{o.label}</option>)}</select>;
   if(section==='scolarite'&&formMode==='concession'&&key==='Type de réduction')return <select value={form[key]||'Pourcentage'} onChange={e=>setForm({...form,[key]:e.target.value})}><option>Pourcentage</option><option>Montant fixe</option></select>;
   if(section==='scolarite'&&formMode==='concession'&&key==='Motif')return <select required value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}><option value="">Sélectionner un motif</option><option value="enfant_pasteur">Enfant de pasteur</option><option value="social">Aide sociale</option><option value="bourse">Bourse</option><option value="personnel">Enfant du personnel</option><option value="fratrie">Réduction fratrie</option><option value="autre">Autre</option></select>;
   if(section==='scolarite'&&formMode==='concession'&&key==='Pourcentage')return <input required type="number" min="0" max="100" step="0.01" value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})} placeholder="Ex. 50 ou 100"/>;
   if(section==='scolarite'&&formMode==='concession'&&key==='Montant fixe')return <input required type="number" min="0" step="1" value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})} placeholder="Montant en FCFA"/>;
   if(section==='scolarite'&&formMode==='concession'&&['Valable du','Valable jusqu’au'].includes(key))return <input type="date" value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}/>;
   if(section==='scolarite'&&formMode==='concession'&&key==='Précisions')return <textarea value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})} placeholder="Justification complémentaire" rows={2}/>;
   if(section==='scolarite'&&key==='Inscription')return <select required value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}><option value="">Sélectionner une inscription active</option>{enrollmentOptions.map(o=><option key={o.id} value={o.id}>{o.label}</option>)}</select>;
   if(section==='scolarite'&&key==='Nature des frais')return <select value={form[key]||'Scolarité annuelle'} onChange={e=>setForm({...form,[key]:e.target.value})}><option>Scolarité annuelle</option><option>Inscription / réinscription</option><option>Frais annexes</option><option>Autres frais</option></select>;
   if(section==='scolarite'&&key==='Montant annuel')return <input required type="number" min="1" step="1" value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})} placeholder={form['Nature des frais']&&form['Nature des frais']!=='Scolarité annuelle'?'Montant en FCFA':'Montant annuel en FCFA'}/>;
   if(section==='scolarite'&&key==='Date d’échéance')return <input type="date" value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}/>;
   if(section==='scolarite'&&key.startsWith('Échéance '))return <input required type="date" value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}/>;
   if(section==='inscriptions'&&key==='Élève')return <select required value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}><option value="">Sélectionner un élève</option>{students.map(o=><option key={o.id} value={o.id}>{o.label}</option>)}</select>;
   if(section==='inscriptions'&&key==='Classe')return <select required value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}><option value="">Sélectionner une classe</option>{classes.map(o=><option key={o.id} value={o.id}>{o.label}</option>)}</select>;
   if(section==='inscriptions'&&key==='Type')return <select value={form[key]||'Inscription'} onChange={e=>setForm({...form,[key]:e.target.value})}><option>Inscription</option><option>Réinscription</option></select>;
   if(section==='inscriptions'&&key==='Nouvelle classe')return <select required value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}><option value="">Sélectionner la nouvelle classe</option>{classes.map(o=><option key={o.id} value={o.id}>{o.label}</option>)}</select>;
   if(section==='inscriptions'&&key==='Type de sortie')return <select required value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}><option value="">Sélectionner</option><option>Transfert vers un autre établissement</option><option>Sortie définitive</option></select>;
   if(key==='Notes'||key==='Motif'||key==='Désignation'||key==='Demande'||key==='Adresse du responsable')return <textarea value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})} placeholder={`Renseigner ${key.toLowerCase()}`} rows={2}/>;
   if(key==='Sexe')return <select value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}><option value="">Sélectionner</option><option value="F">Féminin</option><option value="M">Masculin</option><option value="X">Autre / non précisé</option></select>;
   return <input type={key.toLowerCase().includes('date')?'date':key.toLowerCase().includes('e-mail')?'email':'text'} value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})} placeholder={`Saisir ${key.toLowerCase()}`} />;
 }
 const formKeys=section==='eleves'?['Matricule','Nom','Prénoms','Sexe','Date de naissance','Lieu de naissance','Nom du responsable','Lien avec l’élève','Téléphone du responsable','E-mail du responsable','Profession du responsable','Adresse du responsable','Notes']:section==='inscriptions'&&formMode==='class-transfer'?['Nouvelle classe','Date du transfert','Motif']:section==='inscriptions'&&formMode==='exit'?['Type de sortie','Date de sortie','Motif']:section==='inscriptions'?['Élève','Classe','Type','Date','Notes']:section==='scolarite'&&formMode==='concession'?['Inscription','Type de réduction',...(form['Type de réduction']==='Montant fixe'?['Montant fixe']:['Pourcentage']),'Motif','Précisions','Valable du','Valable jusqu’au']:section==='scolarite'?['Nature des frais','Inscription','Description','Montant annuel',...(form['Nature des frais']&&form['Nature des frais']!=='Scolarité annuelle'?['Date d’échéance']:['Échéance 1','Échéance 2','Échéance 3','Échéance 4','Échéance 5','Échéance 6'])]:titleKeys;
 return <><div className="page-heading"><div><div className="eyebrow">ESPACE DE GESTION</div><h1>{concessionView?'Concessions scolaires':module.title}</h1><p>{concessionView?'Demandes de réduction soumises à validation de la direction.':module.description}</p></div><div className="heading-actions">{section==='scolarite'&&connected&&<button className="button button-secondary" onClick={()=>{setConcessionView(v=>!v);setQuery('')}}>{concessionView?'Voir les frais':'Voir les concessions'}</button>}{connected&&['eleves','inscriptions','scolarite'].includes(section)&&<button className="button button-secondary" onClick={()=>void refresh()} disabled={loadingRows}><RefreshCw size={16}/> Actualiser</button>}<button className="button button-secondary" onClick={exportCsv}><Download size={16}/> Exporter CSV</button>{section==='scolarite'&&connected&&!isReadOnly&&!concessionView&&<button className="button button-secondary" onClick={()=>{setForm({});setFormMode('concession');setShowForm(true)}}><Plus size={17}/> Demander une concession</button>}{!isReadOnly&&connected&&!(section==='scolarite'&&concessionView)&&<button className="button button-primary" onClick={()=>{setForm({});setEditingStudentId(null);setWorkflowEnrollmentId(null);setFormMode('record');setShowForm(true)}}><Plus size={17}/> {section==='eleves'?'Nouvel élève':section==='inscriptions'?'Nouvelle inscription':section==='achats'?'Nouvelle demande':section==='scolarite'?'Créer les frais':'Ajouter'}</button>}</div></div>
 {section==='eleves'&&connected&&!isReadOnly&&<StudentImport/>}
 {notice&&<div className="inline-notice"><CheckCircle2 size={16}/><span>{notice}</span><button onClick={()=>setNotice('')} aria-label="Fermer"><X size={15}/></button></div>}
 {section==='inscriptions'&&connected&&!schoolYear&&<div className="inline-notice"><CheckCircle2 size={16}/><span>Aucune année scolaire active trouvée. Configurez d’abord l’année scolaire dans les paramètres Supabase.</span></div>}
 <div className="metric-strip"><div className="metric-mini"><span>Total des éléments</span><strong>{(section==='scolarite'&&!concessionView?feeTotalCount:filtered.length).toString().padStart(2,'0')}</strong><small>{connected&&['eleves','inscriptions','scolarite'].includes(section)?'Données chargées depuis Supabase':'Aucune donnée réelle chargée'}</small></div><div className="metric-mini"><span>Année en cours</span><strong>{schoolYear?.label||'À configurer'}</strong><small>{schoolYear?'Année active dans Supabase':'Non disponible sans connexion'}</small></div><div className="metric-mini"><span>Actualisation</span><strong>{loadingRows?'En cours…':'Manuelle'}</strong><small>Utilisez Actualiser pour recharger</small></div></div>
 <section className="panel table-panel"><div className="panel-toolbar"><div><h2>Liste des {module.title.toLowerCase()}</h2><p>{filtered.length} résultat{filtered.length>1?'s':''} affiché{filtered.length>1?'s':''}</p></div><div className="table-actions"><div className="table-search"><Search size={16}/><input value={query} onChange={e=>{setQuery(e.target.value);if(section==='scolarite'&&!concessionView)setFeePage(0);}} placeholder={section==='scolarite'&&!concessionView?'Élève, matricule, classe ou frais…':'Rechercher dans la liste…'}/></div><button className="button button-icon-text" onClick={()=>setNotice('La recherche filtre les lignes chargées. Les filtres avancés seront ajoutés avec les modules financiers.')}><SlidersHorizontal size={16}/><span>Filtres</span></button><button className="icon-button bordered" onClick={()=>window.print()} aria-label="Imprimer"><Printer size={17}/></button></div></div>
 <div className="table-scroll"><table><thead><tr>{titleKeys.map(k=><th key={k}>{k}</th>)}<th className="action-col">Action</th></tr></thead><tbody>{filtered.map((row,i)=><tr key={i}>{titleKeys.map((k,j)=><td key={k}>{j===0&&section==='eleves'?<span className="record-id">{row[k]}</span>:k.toLowerCase().includes('statut')||k.toLowerCase().includes('situation')||k==='État'?<span className={`status-pill ${String(row[k]).toLowerCase().includes('attente')||String(row[k]).toLowerCase().includes('vérifier')||String(row[k]).toLowerCase().includes('maintenance')||String(row[k]).toLowerCase().includes('annul')?'status-warn':String(row[k]).toLowerCase().includes('partiel')?'status-info':'status-good'}`}><i/>{row[k]}</span>:<span className={j===1?'cell-strong':''}>{row[k]||'—'}</span>}</td>)}<td>{section==='scolarite'&&concessionView&&row._id&&row['Statut']==='En attente'&&!isReadOnly?<div className="row-actions"><button className="button button-secondary" onClick={async()=>{const client=supabase();if(!client)return;const {error}=await client.rpc('decide_enrollment_concession',{p_concession_id:row._id,p_approve:true,p_decision_note:null});if(error){setNotice(`Approbation impossible : ${error.message}`);return;}setNotice('Concession approuvée. Elle sera appliquée à la création des frais de scolarité si elle est encore valide.');await refresh();}}>Approuver</button><button className="button button-secondary" onClick={async()=>{const note=window.prompt('Motif du refus (facultatif)')||null;const client=supabase();if(!client)return;const {error}=await client.rpc('decide_enrollment_concession',{p_concession_id:row._id,p_approve:false,p_decision_note:note});if(error){setNotice(`Refus impossible : ${error.message}`);return;}setNotice('Demande refusée.');await refresh();}}>Refuser</button></div>:section==='eleves'&&row._id&&!isReadOnly?<button className="button button-secondary" title="Modifier le dossier" onClick={()=>{setEditingStudentId(row._id);setForm({'Matricule':row._studentNumber||row['Matricule']||'','Nom':row._lastName||'','Prénoms':row._firstNames||'','Sexe':row._sex||'','Date de naissance':row._birthDate||'','Lieu de naissance':row._birthPlace||'','Nom du responsable':row._guardianName||'','Téléphone du responsable':row._guardianPhone||'','E-mail du responsable':row._guardianEmail||'','Profession du responsable':row._guardianOccupation||'','Adresse du responsable':row._guardianAddress||'','Lien avec l’élève':row._guardianRelationship||'Responsable légal','Notes':row._notes||''});setFormMode('record');setWorkflowEnrollmentId(null);setShowForm(true);setNotice('')}}><Edit3 size={15}/> Modifier</button>:section==='inscriptions'&&row._id&&!isReadOnly&&['inscrit','reinscrit'].includes(row._status)&&row._yearCurrent==='true'&&row._yearClosed!=='true'?<div className="row-actions"><button className="button button-secondary" onClick={()=>{setWorkflowEnrollmentId(row._id);setFormMode('class-transfer');setForm({'Nouvelle classe':'','Date du transfert':new Date().toISOString().slice(0,10),'Motif':''});setShowForm(true);setNotice('')}}><ArrowRightLeft size={15}/> Changer de classe</button><button className="button button-secondary" onClick={()=>{setWorkflowEnrollmentId(row._id);setFormMode('exit');setForm({'Type de sortie':'','Date de sortie':new Date().toISOString().slice(0,10),'Motif':''});setShowForm(true);setNotice('')}}><LogOut size={15}/> Sortie</button></div>:<button className="icon-button row-more" title="Options" onClick={()=>setNotice(`Aucune action supplémentaire disponible pour cet enregistrement.`)}><MoreHorizontal size={18}/></button>}</td></tr>)}{filtered.length===0&&<tr><td colSpan={titleKeys.length+1} className="empty-cell">{loadingRows?'Chargement des données…':'Aucun résultat ne correspond à votre recherche.'}</td></tr>}</tbody></table></div><div className="table-footer">{section==='scolarite'&&!concessionView?<><span>Affichage de <strong>{feeTotalCount?feePage*100+1:0}–{Math.min((feePage+1)*100,feeTotalCount)}</strong> sur <strong>{feeTotalCount}</strong> frais. Les soldes sont calculés côté PostgreSQL à partir de tous les paiements validés.</span><div className="pagination"><button className="icon-button bordered" onClick={()=>setFeePage(p=>Math.max(0,p-1))} disabled={feePage===0||loadingRows} aria-label="Page précédente"><ChevronLeft size={16}/></button><span className="page-number active">{feePage+1} / {Math.max(1,Math.ceil(feeTotalCount/100))}</span><button className="icon-button bordered" onClick={()=>setFeePage(p=>p+1)} disabled={loadingRows||(feePage+1)*100>=feeTotalCount} aria-label="Page suivante"><ChevronRight size={16}/></button></div></>:<><span>Affichage de <strong>{filtered.length?1:0}–{filtered.length}</strong> sur <strong>{filtered.length}</strong> éléments</span><div className="pagination"><button className="icon-button bordered" disabled aria-label="Précédent"><ChevronLeft size={16}/></button><button className="page-number active">1</button><button className="icon-button bordered" disabled aria-label="Suivant"><ChevronRight size={16}/></button></div></>}</div></section>
 {showForm&&!isReadOnly&&<div className="modal-backdrop" onMouseDown={e=>{if(e.target===e.currentTarget)setShowForm(false)}}><section className="modal"><div className="modal-header"><div><span className="eyebrow">NOUVEL ENREGISTREMENT</span><h2>{section==='eleves'?(editingStudentId?'Modifier le dossier élève':'Créer un dossier élève'):section==='inscriptions'&&formMode==='class-transfer'?'Changer un élève de classe':section==='inscriptions'&&formMode==='exit'?'Enregistrer une sortie ou un transfert':section==='inscriptions'?'Créer une inscription':section==='scolarite'&&formMode==='concession'?'Demander une concession':section==='scolarite'?'Créer les six échéances':`Ajouter · ${module.title}`}</h2></div><button className="icon-button" onClick={()=>setShowForm(false)} aria-label="Fermer"><X size={18}/></button></div><div className="modal-body">{section==='inscriptions'&&formMode==='record'&&schoolYear&&<div className="inline-notice"><CheckCircle2 size={16}/><span>Année scolaire : <strong>{schoolYear.label}</strong></span></div>}{section==='inscriptions'&&formMode==='class-transfer'&&<div className="inline-notice"><CheckCircle2 size={16}/><span>Le changement met à jour l’affectation de l’inscription active et conserve le motif dans l’historique.</span></div>}{section==='inscriptions'&&formMode==='exit'&&<div className="inline-notice"><CheckCircle2 size={16}/><span>Cette action clôture l’inscription active et enregistre la raison de la sortie.</span></div>}{section==='scolarite'&&connected&&<div className="inline-notice"><CheckCircle2 size={16}/><span>{formMode==='concession'?'La demande restera en attente jusqu’à la décision de la direction ou de l’administration.':'Les six échéances sont créées dans une transaction SQL. Une concession approuvée et valide est appliquée automatiquement au montant net.'}</span></div>}{formKeys.map((key)=><label className="form-field" key={key}><span>{key==='Montant annuel'&&section==='scolarite'&&form['Nature des frais']&&form['Nature des frais']!=='Scolarité annuelle'?'Montant':key}{(section==='eleves'&&['Nom','Prénoms'].includes(key))||(section==='inscriptions'&&formMode==='record'&&['Élève','Classe'].includes(key))||(['Nouvelle classe','Type de sortie'].includes(key))?' *':''}</span>{field(key)}</label>)}<p className="form-footnote">{connected&&['eleves','inscriptions','scolarite'].includes(section)?'Cette opération sera enregistrée dans Supabase et soumise aux règles d’accès de votre compte.':'Connexion Supabase requise : aucune modification ne sera enregistrée en mode aperçu.'}</p></div><div className="modal-footer"><button className="button button-secondary" onClick={()=>{setShowForm(false);setFormMode('record');setEditingStudentId(null);setWorkflowEnrollmentId(null)}}>Annuler</button><button className="button button-primary" onClick={()=>void saveRecord()} disabled={saving}>{saving?'Enregistrement…':'Enregistrer'}</button></div></section></div>}
 </>;
}

