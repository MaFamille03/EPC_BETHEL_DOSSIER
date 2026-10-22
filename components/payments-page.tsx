'use client';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { CheckCircle2, Download, Printer, Plus, RefreshCw, Search, X, ReceiptText, WalletCards, CircleAlert } from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';
import { useEPCAccess } from '@/components/access-context';

type Option = { id: string; label: string; balance?: number };
type PaymentRow = { id: string; receipt_number: string; paid_at: string; amount: number; method: string; status: string; payer_name: string | null; external_reference: string | null; notes: string | null; cancellation_reason?: string | null; enrollment_id: string; account_id: string; student: string; student_number: string; class_name: string; school_year: string; account_name: string };
type Receipt = PaymentRow & { allocations: { description: string; amount: number; installment_no: number | null }[] };
const money = (n: number) => new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(n) + ' FCFA';
const methods: Record<string,string> = { especes:'Espèces', virement:'Virement bancaire', mobile_money:'Mobile Money', cheque:'Chèque', autre:'Autre' };
const statusLabel: Record<string,string> = { validated:'Validé', cancelled:'Annulé', draft:'Brouillon' };

export function PaymentsPage() {
  const { isReadOnly } = useEPCAccess();
  const connected = isSupabaseConfigured();
  const [rows, setRows] = useState<PaymentRow[]>([]);
  const [totals, setTotals] = useState({ receipts_total: 0, receipts_today: 0, validated_receipt_count: 0 });
  const [enrollments, setEnrollments] = useState<Option[]>([]);
  const [accounts, setAccounts] = useState<Option[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [query, setQuery] = useState('');
  const [notice, setNotice] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [receipt, setReceipt] = useState<Receipt | null>(null);
  const [form, setForm] = useState({ enrollment_id:'', amount:'', method:'especes', account_id:'', paid_date:new Date().toISOString().slice(0,10), payer_name:'', external_reference:'', notes:'' });

  const refresh = useCallback(async () => {
    const client = supabase();
    if (!client) { setRows([]); return; }
    setLoading(true);
    try {
      const [{data: paymentData,error: paymentError},{data: enrollmentData,error: enrollmentError},{data: accountData,error: accountError},{data: summaryData,error: summaryError}] = await Promise.all([
        client.from('payments').select('id,receipt_number,paid_at,amount,method,status,payer_name,external_reference,notes,cancellation_reason,enrollment_id,account_id,enrollments(students(last_name,first_names,student_number),classes(name),school_years(label)),cash_accounts(name)').order('paid_at',{ascending:false}).limit(500),
        client.rpc('get_enrollment_payment_options'),
        client.from('cash_accounts').select('id,name').eq('is_active',true).order('name'),
        client.rpc('get_financial_summary',{p_from:null,p_to:null})
      ]);
      if (paymentError) throw paymentError; if (enrollmentError) throw enrollmentError; if (accountError) throw accountError; if (summaryError) throw summaryError;
      setTotals({receipts_total:Number((summaryData as any)?.receipts_total||0),receipts_today:Number((summaryData as any)?.receipts_today||0),validated_receipt_count:Number((summaryData as any)?.validated_receipt_count||0)});
      setRows((paymentData||[]).map((r:any) => {
        const e = Array.isArray(r.enrollments) ? r.enrollments[0] : r.enrollments;
        const student = Array.isArray(e?.students) ? e.students[0] : e?.students;
        const klass = Array.isArray(e?.classes) ? e.classes[0] : e?.classes;
        const year = Array.isArray(e?.school_years) ? e.school_years[0] : e?.school_years;
        const account = Array.isArray(r.cash_accounts) ? r.cash_accounts[0] : r.cash_accounts;
        return {...r, student:`${student?.last_name||''} ${student?.first_names||''}`.trim()||'Élève inconnu', student_number:student?.student_number||'—', class_name:klass?.name||'—', school_year:year?.label||'—', account_name:account?.name||'—'} as PaymentRow;
      }));
      setEnrollments((enrollmentData||[]).map((r:any) => ({id:r.enrollment_id,label:r.option_label,balance:Number(r.balance_due||0)})));
      setAccounts((accountData||[]).map((a:any)=>({id:a.id,label:a.name})));
      setForm(f=>({...f, account_id:f.account_id||(accountData||[])[0]?.id||'', enrollment_id:f.enrollment_id||(enrollmentData||[])[0]?.id||''}));
    } catch (e:any) { setNotice(`Chargement des encaissements impossible : un problème est survenu. Vérifiez votre connexion ou contactez l’administrateur.`); }
    finally { setLoading(false); }
  }, []);
  useEffect(()=>{ void refresh(); },[refresh]);

  const filtered = useMemo(()=>rows.filter(r=>[r.receipt_number,r.student,r.student_number,r.class_name,r.school_year,r.account_name,methods[r.method]||r.method,statusLabel[r.status]||r.status,r.external_reference||''].join(' ').toLowerCase().includes(query.toLowerCase())),[rows,query]);
  const totalToday = totals.receipts_today;
  const totalValidated = totals.receipts_total;

  async function savePayment() {
    const client=supabase(); if(!client)return;
    const amount=Number(form.amount);
    if(!form.enrollment_id||!form.account_id||!form.paid_date||!Number.isSafeInteger(amount)||amount<=0){setNotice('Sélectionnez l’inscription et le compte, puis saisissez une date et un montant entier positif en FCFA.');return;}
    setSaving(true);
    const paidAt=new Date(`${form.paid_date}T12:00:00.000Z`).toISOString();
    const {data,error}=await client.rpc('register_student_payment',{p_enrollment_id:form.enrollment_id,p_amount:amount,p_method:form.method,p_account_id:form.account_id,p_paid_at:paidAt,p_payer_name:form.payer_name||null,p_external_reference:form.external_reference||null,p_notes:form.notes||null});
    setSaving(false);
    if(error){setNotice(`Encaissement non enregistré : un problème est survenu. Contactez l’administrateur.`);return;}
    setShowForm(false);setForm(f=>({...f,amount:'',payer_name:'',external_reference:'',notes:''}));
    setNotice(`Paiement validé. Reçu ${data?.receipt_number||''} · ${money(amount)}. Le solde de l’élève et la trésorerie ont été mis à jour.`);
    await refresh();
    if(data?.id) await openReceipt(String(data.id));
  }

  async function openReceipt(paymentId:string) {
    const client=supabase(); if(!client)return;
    const {data,error}=await client.from('payments').select('id,receipt_number,paid_at,amount,method,status,payer_name,external_reference,notes,cancellation_reason,enrollment_id,account_id,enrollments(students(last_name,first_names,student_number),classes(name),school_years(label)),cash_accounts(name),payment_allocations(amount,installments(installment_no),student_charges(description,fee_categories(name)))').eq('id',paymentId).single();
    if(error){setNotice(`Impossible d’ouvrir le reçu : un problème est survenu. Contactez l’administrateur.`);return;}
    const e=Array.isArray(data.enrollments)?data.enrollments[0]:data.enrollments;const student=Array.isArray(e?.students)?e.students[0]:e?.students;const klass=Array.isArray(e?.classes)?e.classes[0]:e?.classes;const year=Array.isArray(e?.school_years)?e.school_years[0]:e?.school_years;const account=Array.isArray(data.cash_accounts)?data.cash_accounts[0]:data.cash_accounts;
    const allocations=(data.payment_allocations||[]).map((a:any)=>{const c=Array.isArray(a.student_charges)?a.student_charges[0]:a.student_charges;const cat=Array.isArray(c?.fee_categories)?c.fee_categories[0]:c?.fee_categories;const ins=Array.isArray(a.installments)?a.installments[0]:a.installments;return {description:`${cat?.name||'Frais'}${c?.description?` — ${c.description}`:''}`,amount:Number(a.amount),installment_no:ins?.installment_no??null};});
    setReceipt({...data,student:`${student?.last_name||''} ${student?.first_names||''}`.trim(),student_number:student?.student_number||'—',class_name:klass?.name||'—',school_year:year?.label||'—',account_name:account?.name||'—',allocations} as Receipt);
  }
  async function cancelPayment(row:PaymentRow) {
    const reason=window.prompt(`Motif obligatoire pour annuler le reçu ${row.receipt_number} :`); if(!reason?.trim())return;
    const client=supabase();if(!client)return;
    const {error}=await client.rpc('cancel_payment',{p_payment_id:row.id,p_reason:reason.trim()});
    if(error){setNotice(`Annulation refusée : un problème est survenu. Contactez l’administrateur.`);return;}
    setNotice(`Le reçu ${row.receipt_number} a été annulé avec une contrepassation en trésorerie. L’historique est conservé.`);setReceipt(null);await refresh();
  }
  function exportCsv(){const lines=[['Reçu','Date','Élève','Matricule','Classe','Année','Montant FCFA','Mode','Compte','Statut'],...filtered.map(r=>[r.receipt_number,new Date(r.paid_at).toLocaleString('fr-FR'),r.student,r.student_number,r.class_name,r.school_year,String(r.amount),methods[r.method]||r.method,r.account_name,statusLabel[r.status]||r.status])];const csv=lines.map(line=>line.map(v=>`"${String(v??'').replaceAll('"','""')}"`).join(';')).join('\n');const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8;'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='epc-bethel-encaissements.csv';a.click();URL.revokeObjectURL(url);}

  return <>
    <div className="page-heading"><div><div className="eyebrow">GESTION FINANCIÈRE</div><h1>Encaissements & reçus</h1><p>Enregistrez les paiements des familles, suivez les reçus et consultez les affectations aux frais scolaires.</p></div><div className="heading-actions"><button className="button button-secondary" onClick={()=>void refresh()} disabled={loading}><RefreshCw size={16}/> Actualiser</button><button className="button button-secondary" onClick={exportCsv}><Download size={16}/> Exporter CSV</button>{!isReadOnly&&<button className="button button-primary" onClick={()=>setShowForm(true)}><Plus size={17}/> Nouvel encaissement</button>}</div></div>
    {!connected&&<div className="inline-notice"><CircleAlert size={16}/><span>Mode aperçu : l’enregistrement des paiements n’est pas disponible pour le moment.</span></div>}
    {notice&&<div className="inline-notice"><CheckCircle2 size={16}/><span>{notice}</span><button onClick={()=>setNotice('')} aria-label="Fermer"><X size={15}/></button></div>}
    <div className="metric-strip"><div className="metric-mini"><span>Encaissements validés</span><strong>{totals.validated_receipt_count.toLocaleString('fr-FR')}</strong><small>Nombre total calculé automatiquement</small></div><div className="metric-mini"><span>Total encaissé validé</span><strong>{money(totalValidated)}</strong><small>Total depuis le début, tous reçus validés</small></div><div className="metric-mini"><span>Encaissé aujourd’hui</span><strong>{money(totalToday)}</strong><small>Total du jour calculé automatiquement</small></div></div>
    <section className="panel table-panel"><div className="panel-toolbar"><div><h2>Journal des encaissements</h2><p>{filtered.length} reçu{filtered.length>1?'s':''} affiché{filtered.length>1?'s':''} · liste des 500 reçus les plus récents, totaux globaux calculés automatiquement</p></div><div className="table-actions"><div className="table-search"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Rechercher un reçu, un élève…"/></div></div></div><div className="table-scroll"><table><thead><tr><th>Reçu</th><th>Date</th><th>Élève</th><th>Classe / année</th><th>Mode</th><th>Compte</th><th>Montant</th><th>Statut</th><th>Actions</th></tr></thead><tbody>{filtered.map(r=><tr key={r.id}><td><span className="record-id">{r.receipt_number}</span></td><td>{new Date(r.paid_at).toLocaleDateString('fr-FR')}</td><td><span className="cell-strong">{r.student}</span><small className="payment-subline">{r.student_number}</small></td><td>{r.class_name}<small className="payment-subline">{r.school_year}</small></td><td>{methods[r.method]||r.method}</td><td>{r.account_name}</td><td><strong>{money(Number(r.amount))}</strong></td><td><span className={`status-pill ${r.status==='cancelled'?'status-warn':r.status==='draft'?'status-info':'status-good'}`}><i/>{statusLabel[r.status]||r.status}</span></td><td><div className="row-actions"><button className="button button-secondary" onClick={()=>void openReceipt(r.id)}><ReceiptText size={14}/> Reçu</button>{!isReadOnly&&r.status==='validated'&&<button className="button button-secondary" onClick={()=>void cancelPayment(r)}>Annuler</button>}</div></td></tr>)}{filtered.length===0&&<tr><td colSpan={9} className="empty-cell">{loading?'Chargement des encaissements…':'Aucun encaissement trouvé.'}</td></tr>}</tbody></table></div><div className="table-footer"><span>Les reçus annulés restent visibles. La liste présente les 500 reçus les plus récents ; les indicateurs portent sur l’ensemble des reçus validés.</span><button className="button button-secondary" onClick={()=>void refresh()} disabled={loading}><RefreshCw size={14}/> {loading?'Chargement…':'Actualiser la liste'}</button></div></section>
    {showForm&&!isReadOnly&&<div className="modal-backdrop" onMouseDown={e=>{if(e.target===e.currentTarget)setShowForm(false)}}><section className="modal"><div className="modal-header"><div><span className="eyebrow">NOUVEL ENCAISSEMENT</span><h2>Enregistrer un paiement</h2></div><button className="icon-button" onClick={()=>setShowForm(false)} aria-label="Fermer"><X size={18}/></button></div><div className="modal-body"><div className="inline-notice payment-form-note"><WalletCards size={16}/><span>Le paiement sera affecté automatiquement aux échéances les plus anciennes puis aux frais ponctuels impayés. Un reçu sera numéroté et un seul mouvement d’entrée sera créé en trésorerie.</span></div><label className="form-field"><span>Inscription / élève *</span><select required value={form.enrollment_id} onChange={e=>setForm({...form,enrollment_id:e.target.value})}><option value="">Sélectionner l’élève</option>{enrollments.map(o=><option key={o.id} value={o.id}>{o.label}</option>)}</select></label><label className="form-field"><span>Montant reçu (FCFA) *</span><input type="number" min="1" step="1" required value={form.amount} onChange={e=>setForm({...form,amount:e.target.value})} placeholder="Ex. 50000"/></label><label className="form-field"><span>Date du paiement *</span><input type="date" required max={new Date().toISOString().slice(0,10)} value={form.paid_date} onChange={e=>setForm({...form,paid_date:e.target.value})}/></label><label className="form-field"><span>Mode de paiement *</span><select value={form.method} onChange={e=>setForm({...form,method:e.target.value})}><option value="especes">Espèces</option><option value="virement">Virement bancaire</option><option value="mobile_money">Mobile Money</option><option value="cheque">Chèque</option><option value="autre">Autre</option></select></label><label className="form-field"><span>Compte destinataire *</span><select required value={form.account_id} onChange={e=>setForm({...form,account_id:e.target.value})}><option value="">Sélectionner le compte</option>{accounts.map(o=><option key={o.id} value={o.id}>{o.label}</option>)}</select></label><label className="form-field"><span>Nom du payeur</span><input value={form.payer_name} onChange={e=>setForm({...form,payer_name:e.target.value})} placeholder="Parent ou représentant légal"/></label><label className="form-field"><span>Référence externe</span><input value={form.external_reference} onChange={e=>setForm({...form,external_reference:e.target.value})} placeholder="Référence de virement / transaction"/></label><label className="form-field"><span>Observations</span><textarea rows={2} value={form.notes} onChange={e=>setForm({...form,notes:e.target.value})} placeholder="Information complémentaire (facultatif)"/></label><p className="form-footnote">Le serveur contrôle les droits, le solde restant, le compte actif et l’absence de dépassement avant de valider le paiement.</p></div><div className="modal-footer"><button className="button button-secondary" onClick={()=>setShowForm(false)}>Annuler</button><button className="button button-primary" onClick={()=>void savePayment()} disabled={saving||!connected}>{saving?'Validation…':'Valider et générer le reçu'}</button></div></section></div>}
    {receipt&&<div className="modal-backdrop receipt-backdrop" onMouseDown={e=>{if(e.target===e.currentTarget)setReceipt(null)}}><section className="receipt-modal"><div className="receipt-actions"><span>APERÇU DU REÇU</span><div><button className="button button-secondary" onClick={()=>window.print()}><Printer size={15}/> Imprimer</button><button className="icon-button" onClick={()=>setReceipt(null)} aria-label="Fermer"><X size={18}/></button></div></div><article className="receipt-print-area"><header className="receipt-header"><div className="receipt-mark">EPC</div><div><h2>EPC BETHEL</h2><p>ASSEMBLÉES DE DIEU JEAN FOLLY</p><small>REÇU D’ENCAISSEMENT</small></div></header><div className="receipt-number"><span>Numéro du reçu</span><strong>{receipt.receipt_number}</strong></div><div className="receipt-grid"><div><span>Élève</span><strong>{receipt.student}</strong><small>Matricule : {receipt.student_number}</small></div><div><span>Classe</span><strong>{receipt.class_name}</strong><small>Année : {receipt.school_year}</small></div><div><span>Date de paiement</span><strong>{new Date(receipt.paid_at).toLocaleDateString('fr-FR')}</strong></div><div><span>Payeur</span><strong>{receipt.payer_name||'Parent / représentant'}</strong></div></div><table className="receipt-lines"><thead><tr><th>Désignation</th><th>Montant</th></tr></thead><tbody>{receipt.allocations.map((a,i)=><tr key={i}><td>{a.description}{a.installment_no?` · Échéance ${a.installment_no}/6`:''}</td><td>{money(a.amount)}</td></tr>)}</tbody><tfoot><tr><th>Total encaissé</th><th>{money(Number(receipt.amount))}</th></tr></tfoot></table><div className="receipt-payment-meta"><span>Mode : <strong>{methods[receipt.method]||receipt.method}</strong></span><span>Compte : <strong>{receipt.account_name}</strong></span></div>{receipt.external_reference&&<p className="receipt-ref">Référence : {receipt.external_reference}</p>}{receipt.status==='cancelled'&&<div className="receipt-cancelled">REÇU ANNULÉ — {receipt.cancellation_reason||'Motif enregistré dans le journal des opérations'}</div>}<div className="receipt-signatures"><div>Signature du caissier</div><div>Cachet de l’établissement</div></div><footer>Merci de conserver ce reçu comme justificatif de paiement.</footer></article></section></div>}
  </>;
}
