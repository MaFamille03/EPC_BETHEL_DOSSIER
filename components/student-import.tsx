'use client';
import { useRef, useState } from 'react';
import { FileSpreadsheet, Upload, CheckCircle2, AlertCircle, X, Download } from 'lucide-react';
import { supabase, isSupabaseConfigured } from '@/lib/supabase';

type ImportRow={student_number:string;last_name:string;first_names:string;sex:'F'|'M'|'X'|null;birth_date:string|null;birth_place:string|null;rowNo:number;error?:string;isExisting?:boolean};
const norm=(v:unknown)=>String(v??'').trim();
const key=(v:unknown)=>norm(v).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
const find=(row:Record<string,unknown>,aliases:string[])=>{const keys=Object.keys(row);const actual=keys.find(k=>aliases.includes(key(k)));return actual?row[actual]:'';};
function dateValue(value:unknown):string|null{if(value===null||value===undefined||value==='')return null;if(typeof value==='number'&&value>20000){const d=new Date(Date.UTC(1899,11,30)+value*86400000);return d.toISOString().slice(0,10);}const s=norm(value);if(/^\d{4}-\d{2}-\d{2}$/.test(s))return s;const m=s.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/);if(m)return `${m[3]}-${m[2].padStart(2,'0')}-${m[1].padStart(2,'0')}`;return null;}

export function StudentImport({onImported}:{onImported?:()=>void|Promise<void>}){
 const fileRef=useRef<HTMLInputElement>(null);const [rows,setRows]=useState<ImportRow[]>([]);const [fileName,setFileName]=useState('');const [busy,setBusy]=useState(false);const [notice,setNotice]=useState('');const [error,setError]=useState('');
 async function choose(file?:File){
  if(!file)return;setFileName(file.name);setRows([]);setError('');setNotice('');
  try{
   const XLSX=await import('xlsx');const buffer=await file.arrayBuffer();const workbook=XLSX.read(buffer,{type:'array',cellDates:false});const sheet=workbook.Sheets[workbook.SheetNames[0]];if(!sheet)throw new Error('Le fichier ne contient aucune feuille.');
   const raw=XLSX.utils.sheet_to_json<Record<string,unknown>>(sheet,{defval:'',raw:true});
   const parsed:ImportRow[]=raw.map((r,i)=>{const student_number=norm(find(r,['matricule','studentnumber','numeroeleve','numereleve']));const last_name=norm(find(r,['nom','lastname','nomdefamille']));const first_names=norm(find(r,['prenoms','firstname','firstnames','prenom']));const sx=key(find(r,['sexe','sex']));const sex:ImportRow['sex']=sx==='f'||sx==='feminin'?'F':sx==='m'||sx==='masculin'?'M':sx?'X':null;const birthRaw=find(r,['datedenaissance','naissance','birthdate']);const birth_date=dateValue(birthRaw);const errors:string[]=[];if(!student_number)errors.push('Matricule manquant');if(!last_name)errors.push('Nom manquant');if(!first_names)errors.push('Prénoms manquants');if(birthRaw&&!birth_date)errors.push('Date de naissance invalide');return{student_number,last_name,first_names,sex,birth_date,birth_place:norm(find(r,['lieudenaissance','birthplace']))||null,rowNo:i+2,error:errors.join(' · ')||undefined};}).filter(r=>r.student_number||r.last_name||r.first_names);
   const seen=new Set<string>();for(const r of parsed){const n=r.student_number.toLocaleLowerCase();if(n&&seen.has(n))r.error=[r.error,'Matricule en double dans le fichier'].filter(Boolean).join(' · ');if(n)seen.add(n);}
   if(!parsed.length)throw new Error('Aucune ligne exploitable. Vérifiez les en-têtes du fichier.');
   const client=supabase();const existing=new Set<string>();
   if(client){const numbers=Array.from(new Set(parsed.map(r=>r.student_number).filter(Boolean)));for(let i=0;i<numbers.length;i+=500){const {data,error}=await client.from('students').select('student_number').in('student_number',numbers.slice(i,i+500));if(error)throw error;(data||[]).forEach((r:any)=>existing.add(String(r.student_number||'').toLocaleLowerCase()));}}
   for(const r of parsed){if(r.student_number&&existing.has(r.student_number.toLocaleLowerCase())){r.isExisting=true;r.error=[r.error,'Matricule déjà présent dans la base'].filter(Boolean).join(' · ');}}
   setRows(parsed);setNotice(`${parsed.length} ligne(s) analysée(s), ${parsed.filter(r=>r.isExisting).length} matricule(s) déjà présent(s). Vérifiez l’aperçu avant import.`);
  }catch(e){setError(e instanceof Error?e.message:'Lecture du fichier impossible.');}
 }
 async function importRows(){
  const client=supabase();if(!client)return;const valid=rows.filter(r=>!r.error);if(!valid.length){setError('Aucune ligne valide à importer.');return;}
  setBusy(true);setError('');setNotice('');
  try{
   const {data:{user}}=await client.auth.getUser();if(!user)throw new Error('Session expirée. Reconnectez-vous.');
   // Check existing matricules first so the final report can distinguish duplicates from inserted records.
   const existing=new Set<string>();
   for(let i=0;i<valid.length;i+=500){const batch=valid.slice(i,i+500).map(r=>r.student_number);const {data,error}=await client.from('students').select('student_number').in('student_number',batch);if(error)throw error;(data||[]).forEach((r:any)=>existing.add(String(r.student_number||'').toLocaleLowerCase()));}
   const candidates=valid.filter(r=>!existing.has(r.student_number.toLocaleLowerCase()));
   let inserted=0;
   for(let i=0;i<candidates.length;i+=100){const batch=candidates.slice(i,i+100).map(({student_number,last_name,first_names,sex,birth_date,birth_place})=>({student_number,last_name,first_names,sex,birth_date,birth_place,created_by:user.id}));const {data,error}=await client.from('students').upsert(batch,{onConflict:'student_number',ignoreDuplicates:true}).select('id');if(error)throw error;inserted+=(data||[]).length;}
   const skippedExisting=rows.filter(r=>r.isExisting).length;const skippedConcurrent=valid.length-inserted;const invalid=rows.filter(r=>r.error&&!r.isExisting).length;
   setNotice(`Import terminé : ${inserted} élève(s) ajouté(s), ${skippedExisting+skippedConcurrent} matricule(s) déjà présent(s) ou ajouté(s) entre-temps ignoré(s)${invalid?`, ${invalid} ligne(s) à corriger non importée(s)`:''}.`);
   setRows([]);if(fileRef.current)fileRef.current.value='';setFileName('');await onImported?.();
  }catch(e){setError(e instanceof Error?e.message:'Import impossible.');}
  finally{setBusy(false);}
 }
 const validCount=rows.filter(r=>!r.error).length;const existingCount=rows.filter(r=>r.isExisting).length;const correctionCount=rows.filter(r=>r.error&&!r.isExisting).length;
 function exportErrorReport(){const failed=rows.filter(r=>r.error);if(!failed.length)return;const quote=(v:unknown)=>`"${String(v??'').replaceAll('"','""')}"`;const csv=[['Ligne','Matricule','Nom','Prénoms','Motif'].map(quote).join(';'),...failed.map(r=>[r.rowNo,r.student_number,r.last_name,r.first_names,r.error].map(quote).join(';'))].join('\r\n');const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8;'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='epc-bethel-erreurs-import-eleves.csv';a.click();URL.revokeObjectURL(url);}
 return <section className="panel import-panel student-import-panel">
  <div className="student-import-heading">
   <details className="student-import-details">
    <summary><span className="student-import-summary-title"><FileSpreadsheet size={19}/> Importer les élèves depuis Excel</span><span className="student-import-summary-note">Importer plusieurs dossiers en une fois · .xlsx, .xls ou .csv</span></summary>
    <div className="student-import-content">
     <div className="import-instructions"><strong>Colonnes attendues</strong><span>Matricule · Nom · Prénoms · Sexe (facultatif) · Date de naissance (facultative) · Lieu de naissance (facultatif)</span><small>Les en-têtes peuvent être écrits avec ou sans accents. La première ligne doit contenir les titres des colonnes. Les matricules existants ne sont pas écrasés.</small></div>
     <div className="import-controls"><input ref={fileRef} type="file" accept=".xlsx,.xls,.csv" onChange={e=>void choose(e.target.files?.[0])} aria-label="Choisir un fichier Excel"/><button className="button button-secondary" onClick={()=>fileRef.current?.click()} disabled={busy}><Upload size={16}/> Choisir un fichier</button>{fileName&&<span className="import-filename">{fileName}</span>}</div>
     {notice&&<div className="inline-notice"><CheckCircle2 size={16}/>{notice}</div>}{error&&<div className="inline-notice"><AlertCircle size={16}/>{error}<button className="icon-button" onClick={()=>setError('')} aria-label="Fermer"><X size={14}/></button></div>}
     {rows.length>0&&<><div className="import-preview-head"><strong>Aperçu de l’import</strong><span>{validCount} prêt(s) · {existingCount} déjà présent(s) · {correctionCount} à corriger</span>{rows.some(r=>r.error)&&<button className="button button-secondary" onClick={exportErrorReport}><Download size={14}/> Télécharger les erreurs CSV</button>}</div><div className="table-scroll import-preview"><table><thead><tr><th>Ligne</th><th>Matricule</th><th>Nom</th><th>Prénoms</th><th>Sexe</th><th>Date de naissance</th><th>Contrôle</th></tr></thead><tbody>{rows.slice(0,30).map(r=><tr key={`${r.rowNo}-${r.student_number}`}><td>{r.rowNo}</td><td>{r.student_number||'—'}</td><td>{r.last_name||'—'}</td><td>{r.first_names||'—'}</td><td>{r.sex||'—'}</td><td>{r.birth_date||'—'}</td><td>{r.error?<span className="status-pill status-warn">{r.error}</span>:<span className="status-pill status-good">Valide</span>}</td></tr>)}</tbody></table>{rows.length>30&&<p className="form-footnote">Les 30 premières lignes sont affichées ; les {rows.length} lignes seront contrôlées avant import.</p>}</div><div className="import-actions"><button className="button button-secondary" onClick={()=>{setRows([]);setFileName('');setNotice('');if(fileRef.current)fileRef.current.value='';}}>Annuler l’aperçu</button><button className="button button-primary" onClick={()=>void importRows()} disabled={busy||!isSupabaseConfigured()||validCount===0}>{busy?'Import en cours…':`Importer ${validCount} élève(s)`}</button></div></>}
     {!isSupabaseConfigured()&&<p className="form-footnote">La connexion aux données doit être activée pour enregistrer les élèves.</p>}
    </div>
   </details>
   <a className="button button-secondary student-template-download" href="/modele-importation-eleves-epc-bethel.xlsx" download="Modele_importation_eleves_EPC_BETHEL.xlsx"><Download size={16}/> Télécharger le modèle Excel</a>
  </div>
 </section>;
}
