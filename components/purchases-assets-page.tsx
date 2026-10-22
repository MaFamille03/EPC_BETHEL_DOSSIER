'use client';
import { useCallback, useEffect, useState } from 'react';
import { supabase, isSupabaseConfigured } from '@/lib/supabase';
import { useEPCAccess } from '@/components/access-context';
import { Plus, RefreshCw, Search, CheckCircle2, AlertCircle } from 'lucide-react';

type Item = Record<string, any>;
const money = (v: any) => `${new Intl.NumberFormat('fr-FR').format(Number(v || 0))} FCFA`;
const date = (v: any) => v ? new Date(`${String(v).slice(0,10)}T12:00:00`).toLocaleDateString('fr-FR') : '—';
const purchaseStatus: Record<string, string> = {
  draft: 'Brouillon', submitted: 'À approuver', approved: 'Approuvée', rejected: 'Refusée',
  ordered: 'Commandée', partially_received: 'Partiellement reçue', received: 'Reçue',
  closed: 'Clôturée', cancelled: 'Annulée', validated: 'Validée',
};

export function PurchasesPage() {
  const { isReadOnly } = useEPCAccess();
  const connected = isSupabaseConfigured();
  const [tab, setTab] = useState<'requests' | 'suppliers' | 'orders' | 'receipts'>('requests');
  const [rows, setRows] = useState<Item[]>([]);
  const [suppliers, setSuppliers] = useState<Item[]>([]);
  const [orders, setOrders] = useState<Item[]>([]);
  const [receiptRows, setReceiptRows] = useState<Item[]>([]);
  const [query, setQuery] = useState('');
  const [modal, setModal] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [receiptLines, setReceiptLines] = useState<Item[]>([]);
  const [form, setForm] = useState<Record<string, string>>({ kind: 'asset', quantity: '1', unitPrice: '0' });

  const load = useCallback(async () => {
    const db = supabase();
    if (!db) {
      setRows([]); setSuppliers([]); setOrders([]); setReceiptRows([]);
      return;
    }
    setBusy(true);
    try {
      const [requestsResult, suppliersResult, ordersResult, receiptsResult] = await Promise.all([
        db.from('purchase_requests').select('id,request_number,purpose,cost_center,status,estimated_total,requested_at,decision_note,requested_by').order('requested_at', { ascending: false }).limit(500),
        db.from('suppliers').select('id,name,phone,email,is_active').order('name').limit(500),
        db.from('purchase_orders').select('id,order_number,ordered_on,status,total_amount,expected_delivery_on,suppliers(name),purchase_requests(request_number)').order('ordered_on', { ascending: false }).limit(500),
        db.from('goods_receipts').select('id,receipt_number,received_at,delivery_reference,status,notes,purchase_orders(order_number,suppliers(name)),goods_receipt_lines(quantity_received)').order('received_at', { ascending: false }).limit(500),
      ]);
      if (requestsResult.error) throw requestsResult.error;
      if (suppliersResult.error) throw suppliersResult.error;
      if (ordersResult.error) throw ordersResult.error;
      if (receiptsResult.error) throw receiptsResult.error;
      setRows(requestsResult.data || []);
      setSuppliers(suppliersResult.data || []);
      setOrders(ordersResult.data || []);
      setReceiptRows((receiptsResult.data || []).map((receipt: Item) => {
        const order = Array.isArray(receipt.purchase_orders) ? receipt.purchase_orders[0] : receipt.purchase_orders;
        const supplier = Array.isArray(order?.suppliers) ? order.suppliers[0] : order?.suppliers;
        return {
          ...receipt,
          order_number: order?.order_number || '—',
          supplier_name: supplier?.name || '—',
          line_count: Array.isArray(receipt.goods_receipt_lines) ? receipt.goods_receipt_lines.length : 0,
        };
      }));
    } catch (error: any) {
      setNotice(`Chargement impossible : un problème est survenu. Vérifiez votre connexion ou contactez l’administrateur.`);
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const visible = tab === 'requests'
    ? rows.filter((row) => `${row.request_number} ${row.purpose} ${row.status}`.toLowerCase().includes(query.toLowerCase()))
    : tab === 'suppliers'
      ? suppliers.filter((row) => `${row.name} ${row.phone || ''} ${row.email || ''} ${row.is_active ? 'actif' : 'inactif'}`.toLowerCase().includes(query.toLowerCase()))
      : tab === 'orders'
        ? orders.filter((row) => `${row.order_number} ${row.suppliers?.name || ''} ${row.status}`.toLowerCase().includes(query.toLowerCase()))
        : receiptRows.filter((row) => `${row.receipt_number} ${row.order_number} ${row.supplier_name} ${row.delivery_reference || ''} ${row.status}`.toLowerCase().includes(query.toLowerCase()));

  async function submit() {
    const db = supabase();
    if (!db) return;
    setBusy(true);
    setNotice('');
    try {
      const { data: { user }, error: userError } = await db.auth.getUser();
      if (userError || !user) throw new Error('Connectez-vous avec un compte autorisé.');

      if (tab === 'suppliers') {
        if (!form.name?.trim()) throw new Error('Le nom du fournisseur est obligatoire.');
        const { error } = await db.from('suppliers').insert({
          name: form.name.trim(), phone: form.phone || null, email: form.email || null,
          address: form.address || null, registration_reference: form.registration_reference || null,
          payment_terms: form.payment_terms || null, notes: form.notes || null, created_by: user.id,
        });
        if (error) throw error;
        setNotice('Fournisseur enregistré.');
      } else if (tab === 'requests') {
        if (!form.purpose?.trim() || !form.description?.trim()) throw new Error('Indiquez le besoin et au moins un article.');
        const quantity = Number(form.quantity || 1);
        const unitPrice = Number(form.unitPrice || 0);
        if (!Number.isFinite(quantity) || quantity <= 0 || !Number.isSafeInteger(unitPrice) || unitPrice < 0) throw new Error('La quantité doit être positive et le prix unitaire un entier positif ou nul.');
        if (form.kind === 'asset' && !Number.isInteger(quantity)) throw new Error('La quantité d’une immobilisation doit être un nombre entier.');
        const requestNumber = `DA-${new Date().getFullYear()}-${Date.now().toString().slice(-6)}`;
        const { data: request, error } = await db.from('purchase_requests').insert({
          request_number: requestNumber, requested_by: user.id, purpose: form.purpose.trim(),
          cost_center: form.cost_center || null, estimated_total: Math.round(quantity * unitPrice), status: 'draft',
        }).select('id').single();
        if (error) throw error;
        const { error: lineError } = await db.from('purchase_request_lines').insert({
          request_id: request.id, description: form.description.trim(), item_kind: form.kind || 'other',
          quantity, estimated_unit_price: unitPrice, category: form.category || null, notes: form.notes || null,
        });
        if (lineError) {
          await db.from('purchase_requests').delete().eq('id', request.id);
          throw lineError;
        }
        setNotice(`Demande ${requestNumber} créée en brouillon.`);
      } else if (tab === 'orders') {
        if (!form.request_id || !form.supplier_id) throw new Error('Sélectionnez une demande approuvée et un fournisseur actif.');
        const orderNumber = `BC-${new Date().getFullYear()}-${Date.now().toString().slice(-6)}`;
        const { error } = await db.rpc('create_order_from_request', {
          p_request_id: form.request_id, p_supplier_id: form.supplier_id, p_order_number: orderNumber,
          p_ordered_on: form.ordered_on || new Date().toISOString().slice(0, 10),
          p_expected_delivery_on: form.expected_delivery_on || null, p_notes: form.notes || null,
        });
        if (error) throw error;
        setNotice(`Bon de commande ${orderNumber} créé. La commande ne débite pas la trésorerie : son règlement reste enregistré dans Dépenses.`);
      } else {
        if (!form.order_id || !form.line_id) throw new Error('Sélectionnez une commande et une ligne à réceptionner.');
        const quantity = Number(form.quantity_received);
        if (!Number.isFinite(quantity) || quantity <= 0) throw new Error('La quantité reçue doit être positive.');
        const line = receiptLines.find((item) => item.id === form.line_id);
        if (line?.item_kind === 'asset' && !Number.isInteger(quantity)) throw new Error('La quantité reçue d’une immobilisation doit être un nombre entier.');
        const receiptNumber = `BR-${new Date().getFullYear()}-${Date.now().toString().slice(-6)}`;
        const { error } = await db.rpc('receive_purchase_order', {
          p_order_id: form.order_id, p_receipt_number: receiptNumber,
          p_lines: [{ line_id: form.line_id, quantity_received: quantity, condition_note: form.condition_note || null }],
          p_delivery_reference: form.delivery_reference || null, p_notes: form.notes || null,
        });
        if (error) throw error;
        setNotice(`Réception ${receiptNumber} enregistrée. Les immobilisations reçues sont ajoutées automatiquement à l’inventaire.`);
      }
      setModal(false);
      setForm({ kind: 'asset', quantity: '1', unitPrice: '0' });
      await load();
    } catch (error: any) {
      setNotice(`Enregistrement impossible : un problème est survenu. Contactez l’administrateur.`);
    } finally {
      setBusy(false);
    }
  }

  async function toggleSupplier(supplier: Item) {
    const db = supabase();
    if (!db || isReadOnly) return;
    const action = supplier.is_active ? 'désactiver' : 'réactiver';
    if (!window.confirm(`Voulez-vous ${action} le fournisseur « ${supplier.name} » ? Les commandes historiques seront conservées.`)) return;
    setBusy(true);
    try {
      const { error } = await db.from('suppliers').update({ is_active: !supplier.is_active }).eq('id', supplier.id);
      if (error) throw error;
      setNotice(`Fournisseur ${supplier.is_active ? 'désactivé' : 'réactivé'}. L’historique des commandes est conservé.`);
      await load();
    } catch (error: any) {
      setNotice(`Modification impossible : un problème est survenu. Contactez l’administrateur.`);
    } finally {
      setBusy(false);
    }
  }

  async function decide(request: Item, approve: boolean) {
    const db = supabase();
    if (!db) return;
    const note = approve ? '' : (window.prompt('Motif obligatoire du refus') || '').trim();
    if (!approve && !note) return;
    setBusy(true);
    try {
      const { error } = await db.rpc('decide_purchase_request', { p_request_id: request.id, p_approve: approve, p_decision_note: note || null });
      if (error) throw error;
      setNotice(approve ? 'Demande approuvée. Créez ensuite le bon de commande dans l’onglet Commandes.' : 'Demande refusée.');
      await load();
    } catch (error: any) {
      setNotice(`Décision impossible : un problème est survenu. Contactez l’administrateur.`);
    } finally {
      setBusy(false);
    }
  }

  async function submitForApproval(request: Item) {
    const db = supabase();
    if (!db) return;
    setBusy(true);
    try {
      const { error } = await db.rpc('submit_purchase_request', { p_request_id: request.id });
      if (error) throw error;
      setNotice('Demande transmise pour approbation.');
      await load();
    } catch (error: any) {
      setNotice(`Envoi impossible : un problème est survenu. Contactez l’administrateur.`);
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    async function loadReceiptLines() {
      if (tab !== 'receipts' || !form.order_id) { setReceiptLines([]); return; }
      const db = supabase();
      if (!db) return;
      const { data, error } = await db.from('purchase_order_lines')
        .select('id,description,item_kind,quantity_ordered,quantity_received,unit_price')
        .eq('purchase_order_id', form.order_id).order('description');
      if (error) { setNotice(`Lignes indisponibles : un problème est survenu. Contactez l’administrateur.`); return; }
      setReceiptLines((data || []).filter((line: Item) => Number(line.quantity_ordered) > Number(line.quantity_received)));
      setForm((current) => ({ ...current, line_id: '', quantity_received: '' }));
    }
    void loadReceiptLines();
  }, [tab, form.order_id]);

  const tabs = [['requests', 'Demandes'], ['suppliers', 'Fournisseurs'], ['orders', 'Commandes'], ['receipts', 'Réceptions']] as const;
  const headers = tab === 'requests'
    ? ['Référence', 'Objet', 'Montant estimé', 'Date', 'Statut', 'Action']
    : tab === 'suppliers'
      ? ['Fournisseur', 'Téléphone', 'E-mail', 'Statut', 'Action']
      : tab === 'orders'
        ? ['Bon de commande', 'Fournisseur', 'Date', 'Livraison prévue', 'Montant', 'Statut']
        : ['N° réception', 'Date', 'Commande', 'Fournisseur', 'Référence livraison', 'Lignes', 'Statut'];

  return (
    <div className="module-workspace">
      <div className="page-heading">
        <div><div className="eyebrow">ACHATS & APPROVISIONNEMENT</div><h1>Achats & fournisseurs</h1><p>Suivez les demandes, les décisions, les commandes et les réceptions. Les commandes ne débitent pas la trésorerie avant leur règlement dans Dépenses.</p></div>
        <div className="heading-actions"><button className="button button-secondary" onClick={() => void load()} disabled={busy}><RefreshCw size={16}/> Actualiser</button>{!isReadOnly && <button className="button button-primary" onClick={() => { setForm(tab === 'receipts' ? {} : { kind: 'asset', quantity: '1', unitPrice: '0' }); setModal(true); }}><Plus size={17}/>{tab === 'suppliers' ? 'Nouveau fournisseur' : tab === 'orders' ? 'Nouveau bon de commande' : tab === 'receipts' ? 'Réceptionner une commande' : 'Nouvelle demande'}</button>}</div>
      </div>
      {notice && <div className="inline-notice"><AlertCircle size={16}/><span>{notice}</span><button className="icon-button" onClick={() => setNotice('')} aria-label="Fermer">×</button></div>}
      {!connected && <div className="inline-notice"><AlertCircle size={16}/><span>Configurez les variables la connexion aux données et connectez-vous pour charger ou enregistrer les données réelles.</span></div>}

      <div className="module-tabs">{tabs.map(([id, label]) => <button key={id} className={`module-tab ${tab === id ? 'active' : ''}`} onClick={() => setTab(id)}>{label}{id === 'requests' ? ` (${rows.length})` : id === 'suppliers' ? ` (${suppliers.length})` : id === 'orders' ? ` (${orders.length})` : ` (${receiptRows.length})`}</button>)}</div>
      <div className="table-toolbar"><div className="search-field"><Search size={17}/><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={tab === 'receipts' ? 'Réception, commande, fournisseur…' : 'Rechercher…'}/></div><span className="muted-small">{visible.length} résultat(s) dans les 500 derniers enregistrements chargés</span></div>
      <section className="data-card"><div className="table-scroll"><table><thead><tr>{headers.map((header) => <th key={header}>{header}</th>)}</tr></thead><tbody>
        {visible.map((row: Item) => <tr key={row.id}>
          {tab === 'requests' ? <>
            <td><span className="record-id">{row.request_number}</span></td><td><span className="cell-strong">{row.purpose}</span></td><td>{money(row.estimated_total)}</td><td>{date(row.requested_at)}</td><td><span className="status-pill"><i/>{purchaseStatus[row.status] || row.status}</span>{row.decision_note && <small className="payment-subline">Motif : {row.decision_note}</small>}</td>
            <td><div className="row-actions">{!isReadOnly && row.status === 'draft' && <button className="button button-secondary" disabled={busy} onClick={() => void submitForApproval(row)}>Soumettre</button>}{!isReadOnly && row.status === 'submitted' && <><button className="button button-secondary" disabled={busy} onClick={() => void decide(row, true)}>Approuver</button><button className="button button-secondary" disabled={busy} onClick={() => void decide(row, false)}>Refuser</button></>}</div></td>
          </> : tab === 'suppliers' ? <>
            <td className="cell-strong">{row.name}</td><td>{row.phone || '—'}</td><td>{row.email || '—'}</td><td><span className={`status-pill ${row.is_active ? 'status-good' : 'status-warn'}`}><i/>{row.is_active ? 'Actif' : 'Inactif'}</span></td>
            <td>{!isReadOnly && <button className="button button-secondary" disabled={busy} onClick={() => void toggleSupplier(row)}>{row.is_active ? 'Désactiver' : 'Réactiver'}</button>}</td>
          </> : tab === 'orders' ? <>
            <td><span className="record-id">{row.order_number}</span></td><td>{Array.isArray(row.suppliers) ? row.suppliers[0]?.name || '—' : row.suppliers?.name || '—'}</td><td>{date(row.ordered_on)}</td><td>{date(row.expected_delivery_on)}</td><td>{money(row.total_amount)}</td><td><span className="status-pill"><i/>{purchaseStatus[row.status] || row.status}</span></td>
          </> : <>
            <td><span className="record-id">{row.receipt_number}</span></td><td>{date(row.received_at)}</td><td>{row.order_number}</td><td>{row.supplier_name}</td><td>{row.delivery_reference || '—'}</td><td>{row.line_count}</td><td><span className={`status-pill ${row.status === 'validated' ? 'status-good' : 'status-warn'}`}><i/>{purchaseStatus[row.status] || row.status}</span></td>
          </>}
        </tr>)}
        {visible.length === 0 && <tr><td colSpan={headers.length} className="empty-cell">{busy ? 'Chargement…' : 'Aucun enregistrement. Les données réelles apparaîtront après connexion et création.'}</td></tr>}
      </tbody></table></div></section>

      {modal && !isReadOnly && <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setModal(false); }}><section className="modal">
        <div className="modal-header"><div><span className="eyebrow">GESTION DES ACHATS</span><h2>{tab === 'suppliers' ? 'Nouveau fournisseur' : tab === 'orders' ? 'Créer un bon de commande' : tab === 'receipts' ? 'Enregistrer une réception' : 'Créer une demande d’achat'}</h2></div><button className="icon-button" onClick={() => setModal(false)} aria-label="Fermer">×</button></div>
        <div className="modal-body">
          {tab === 'suppliers' ? <>{[['name','Nom du fournisseur','text'],['phone','Téléphone','tel'],['email','Adresse e-mail','email'],['address','Adresse','text'],['registration_reference','N° contribuable / référence','text'],['payment_terms','Conditions de paiement','text'],['notes','Notes','text']].map(([key,label,type]) => <label className="form-field" key={key}><span>{label}</span><input type={type} value={form[key] || ''} onChange={(event) => setForm({ ...form, [key]: event.target.value })}/></label>)}</>
          : tab === 'orders' ? <>
            <label className="form-field"><span>Demande approuvée *</span><select value={form.request_id || ''} onChange={(event) => setForm({ ...form, request_id: event.target.value })}><option value="">Choisir une demande approuvée</option>{rows.filter((row) => row.status === 'approved').map((row) => <option key={row.id} value={row.id}>{row.request_number} · {row.purpose} · {money(row.estimated_total)}</option>)}</select></label>
            <label className="form-field"><span>Fournisseur actif *</span><select value={form.supplier_id || ''} onChange={(event) => setForm({ ...form, supplier_id: event.target.value })}><option value="">Choisir un fournisseur</option>{suppliers.filter((supplier) => supplier.is_active).map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select></label>
            <label className="form-field"><span>Date de commande</span><input type="date" max={new Date().toISOString().slice(0,10)} value={form.ordered_on || new Date().toISOString().slice(0,10)} onChange={(event) => setForm({ ...form, ordered_on: event.target.value })}/></label>
            <label className="form-field"><span>Livraison prévue</span><input type="date" value={form.expected_delivery_on || ''} onChange={(event) => setForm({ ...form, expected_delivery_on: event.target.value })}/></label>
            <label className="form-field"><span>Notes</span><input value={form.notes || ''} onChange={(event) => setForm({ ...form, notes: event.target.value })}/></label>
          </> : tab === 'receipts' ? <>
            <label className="form-field"><span>Bon de commande à réceptionner *</span><select value={form.order_id || ''} onChange={(event) => setForm({ ...form, order_id: event.target.value, line_id: '', quantity_received: '' })}><option value="">Choisir une commande ouverte</option>{orders.filter((order) => ['ordered','partially_received'].includes(order.status)).map((order) => <option key={order.id} value={order.id}>{order.order_number} · {(Array.isArray(order.suppliers) ? order.suppliers[0]?.name : order.suppliers?.name) || 'Fournisseur'} </option>)}</select></label>
            <label className="form-field"><span>Ligne à réceptionner *</span><select value={form.line_id || ''} onChange={(event) => setForm({ ...form, line_id: event.target.value })}><option value="">Choisir un article restant à recevoir</option>{receiptLines.map((line) => <option key={line.id} value={line.id}>{line.description} · restant {Number(line.quantity_ordered) - Number(line.quantity_received)}{line.item_kind === 'asset' ? ' · inventaire automatique' : ''}</option>)}</select></label>
            <label className="form-field"><span>Quantité reçue *</span><input type="number" min="0.001" step="0.001" value={form.quantity_received || ''} onChange={(event) => setForm({ ...form, quantity_received: event.target.value })}/></label>
            <label className="form-field"><span>Référence du bon de livraison</span><input value={form.delivery_reference || ''} onChange={(event) => setForm({ ...form, delivery_reference: event.target.value })}/></label>
            <label className="form-field"><span>État / observations de la ligne</span><input value={form.condition_note || ''} onChange={(event) => setForm({ ...form, condition_note: event.target.value })}/></label>
            <label className="form-field"><span>Notes de réception</span><input value={form.notes || ''} onChange={(event) => setForm({ ...form, notes: event.target.value })}/></label>
            <div className="inline-notice"><CheckCircle2 size={16}/><span>Chaque immobilisation reçue crée une fiche d’inventaire. La réception n’enregistre aucun paiement ni sortie de trésorerie.</span></div>
          </> : <>
            {[[ 'purpose','Objet / besoin','text' ],[ 'description','Article ou service','text' ],[ 'cost_center','Service demandeur / centre de coût','text' ],[ 'category','Catégorie descriptive','text' ],[ 'quantity','Quantité','number' ],[ 'unitPrice','Prix unitaire (FCFA)','number' ],[ 'notes','Notes','text' ]].map(([key,label,type]) => <label className="form-field" key={key}><span>{label}</span><input type={type} min={type === 'number' ? '0' : undefined} step={key === 'quantity' ? '0.001' : key === 'unitPrice' ? '1' : undefined} value={form[key] || ''} onChange={(event) => setForm({ ...form, [key]: event.target.value })}/></label>)}
            <label className="form-field"><span>Nature de l’achat</span><select value={form.kind || 'asset'} onChange={(event) => setForm({ ...form, kind: event.target.value })}><option value="asset">Équipement / immobilisation</option><option value="stock">Stock / consommables</option><option value="service">Prestation</option><option value="other">Autre</option></select></label>
          </>}
          <p className="form-footnote">Une commande doit provenir d’une demande approuvée. Les réceptions mettent à jour les quantités reçues ; le règlement passe par Dépenses afin d’éviter les doublons de trésorerie.</p>
        </div>
        <div className="modal-footer"><button className="button button-secondary" onClick={() => setModal(false)}>Annuler</button><button className="button button-primary" onClick={() => void submit()} disabled={busy || !connected}>{busy ? 'Enregistrement…' : 'Enregistrer'}</button></div>
      </section></div>}
    </div>
  );
}

export function AssetsPage() {
  const { isReadOnly } = useEPCAccess();
  const connected = isSupabaseConfigured();
  const [tab, setTab] = useState<'assets' | 'maintenance' | 'movements'>('assets');
  const [rows, setRows] = useState<Item[]>([]);
  const [allAssets, setAllAssets] = useState<Item[]>([]);
  const [categories, setCategories] = useState<Item[]>([]);
  const [suppliers, setSuppliers] = useState<Item[]>([]);
  const [query, setQuery] = useState('');
  const [modal, setModal] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [editingAssetId, setEditingAssetId] = useState('');
  const [form, setForm] = useState<Record<string, string>>({ cost: '0', status: 'planned' });

  const load = useCallback(async () => {
    const db = supabase();
    if (!db) { setRows([]); setAllAssets([]); setCategories([]); setSuppliers([]); return; }
    setBusy(true);
    try {
      const [assetsResult, categoriesResult, suppliersResult, maintenanceResult] = await Promise.all([
        db.from('assets').select('id,asset_code,name,description,category_id,brand,model,serial_number,acquired_on,acquisition_cost,supplier_id,invoice_reference,location,status,asset_categories(name),suppliers(name)').order('created_at', { ascending: false }).limit(1000),
        db.from('asset_categories').select('id,code,name').eq('is_active', true).order('name'),
        db.from('suppliers').select('id,name').eq('is_active', true).order('name'),
        db.from('asset_maintenance').select('id,maintenance_date,description,cost,status,assets(asset_code,name),suppliers(name)').order('maintenance_date', { ascending: false }).limit(500),
      ]);
      if (assetsResult.error) throw assetsResult.error;
      if (categoriesResult.error) throw categoriesResult.error;
      if (suppliersResult.error) throw suppliersResult.error;
      if (maintenanceResult.error) throw maintenanceResult.error;
      const assets = assetsResult.data || [];
      setAllAssets(assets);
      setCategories(categoriesResult.data || []);
      setSuppliers(suppliersResult.data || []);
      if (tab === 'assets') setRows(assets);
      else if (tab === 'maintenance') setRows(maintenanceResult.data || []);
      else {
        const { data, error } = await db.from('asset_movements').select('id,moved_at,movement_kind,from_location,to_location,reason,assets(asset_code,name)').order('moved_at', { ascending: false }).limit(500);
        if (error) throw error;
        setRows(data || []);
      }
    } catch (error: any) {
      setNotice(`Chargement impossible : un problème est survenu. Vérifiez votre connexion ou contactez l’administrateur.`);
    } finally {
      setBusy(false);
    }
  }, [tab]);

  useEffect(() => { void load(); }, [load]);
  const visible = rows.filter((row) => JSON.stringify(row).toLowerCase().includes(query.toLowerCase()));

  function beginEdit(asset: Item) {
    setEditingAssetId(asset.id);
    setForm({
      asset_code: asset.asset_code || '', name: asset.name || '', description: asset.description || '',
      category_id: asset.category_id || '', brand: asset.brand || '', model: asset.model || '',
      serial_number: asset.serial_number || '', acquired_on: asset.acquired_on || '',
      cost: String(asset.acquisition_cost ?? 0), supplier_id: asset.supplier_id || '',
      invoice_reference: asset.invoice_reference || '', location: asset.location || '',
    });
    setModal(true);
  }

  async function submit() {
    const db = supabase();
    if (!db) return;
    setBusy(true);
    let succeeded = false;
    try {
      const { data: { user }, error: userError } = await db.auth.getUser();
      if (userError || !user) throw new Error('Connectez-vous avec un compte autorisé.');
      if (tab === 'assets') {
        if (!form.name?.trim() || !form.category_id) throw new Error('Désignation et catégorie sont obligatoires.');
        const acquisitionCost = Number(form.cost || 0);
        if (!Number.isSafeInteger(acquisitionCost) || acquisitionCost < 0) throw new Error('La valeur d’achat doit être un entier positif ou nul en FCFA.');
        const code = form.asset_code?.trim() || `PAT-${new Date().getFullYear()}-${Date.now().toString().slice(-7)}`;
        const payload = {
          asset_code: code, name: form.name.trim(), category_id: form.category_id,
          description: form.description || null, brand: form.brand || null, model: form.model || null,
          serial_number: form.serial_number || null, acquired_on: form.acquired_on || null,
          acquisition_cost: acquisitionCost, supplier_id: form.supplier_id || null,
          invoice_reference: form.invoice_reference || null, location: form.location || null,
          updated_at: new Date().toISOString(),
        };
        if (editingAssetId) {
          const { error } = await db.from('assets').update(payload).eq('id', editingAssetId);
          if (error) throw error;
          setNotice(`Fiche d’inventaire ${code} mise à jour.`);
        } else {
          const { error } = await db.from('assets').insert({ ...payload, status: 'active', created_by: user.id });
          if (error) throw error;
          setNotice(`Bien ${code} enregistré dans l’inventaire.`);
        }
      } else if (tab === 'maintenance') {
        if (!form.asset_id || !form.description?.trim() || !form.maintenance_date) throw new Error('Bien, date et description sont obligatoires.');
        const cost = Number(form.cost || 0);
        if (!Number.isSafeInteger(cost) || cost < 0) throw new Error('Le coût doit être un entier positif ou nul en FCFA.');
        const { error } = await db.rpc('register_asset_maintenance', {
          p_asset_id: form.asset_id, p_maintenance_date: form.maintenance_date,
          p_description: form.description.trim(), p_supplier_id: form.supplier_id || null,
          p_cost: cost, p_status: form.status || 'planned',
        });
        if (error) throw error;
        setNotice(form.status === 'in_progress'
          ? 'Maintenance enregistrée : le bien actif est passé en maintenance.'
          : form.status === 'completed'
            ? 'Maintenance terminée enregistrée. Le statut du bien a été resynchronisé si aucune autre intervention n’est en cours.'
            : 'Intervention de maintenance enregistrée.');
      } else {
        if (!form.asset_id || !form.to_location?.trim() || !form.reason?.trim()) throw new Error('Bien, destination et motif sont obligatoires.');
        const { error } = await db.rpc('transfer_asset_location', { p_asset_id: form.asset_id, p_to_location: form.to_location.trim(), p_reason: form.reason.trim() });
        if (error) throw error;
        setNotice('Transfert enregistré.');
      }
      succeeded = true;
    } catch (error: any) {
      setNotice(`Enregistrement impossible : un problème est survenu. Contactez l’administrateur.`);
    } finally {
      setBusy(false);
      if (succeeded) {
        setModal(false);
        setEditingAssetId('');
        setForm({ cost: '0', status: 'planned' });
        await load();
      }
    }
  }

  const tabs = [['assets', 'Inventaire'], ['maintenance', 'Maintenance'], ['movements', 'Mouvements']] as const;
  const headers = tab === 'assets'
    ? ['Code', 'Désignation', 'Catégorie', 'Marque / modèle', 'N° série', 'Localisation', 'Acquisition', 'Valeur', 'État', 'Action']
    : tab === 'maintenance'
      ? ['Date', 'Bien', 'Intervention', 'Prestataire', 'Coût', 'Statut']
      : ['Date', 'Bien', 'Type', 'Origine', 'Destination', 'Motif'];

  return <div className="module-workspace">
    <div className="page-heading"><div><div className="eyebrow">GESTION DES BIENS</div><h1>Patrimoine & inventaire</h1><p>Suivez les immobilisations, leurs valeurs et emplacements, ainsi que les maintenances et transferts. Les immobilisations réceptionnées depuis les commandes alimentent automatiquement cet inventaire.</p></div>
      <div className="heading-actions"><button className="button button-secondary" onClick={() => void load()} disabled={busy}><RefreshCw size={16}/> Actualiser</button>{!isReadOnly && <button className="button button-primary" onClick={() => { setEditingAssetId(''); setForm({ cost: '0', status: 'planned' }); setModal(true); }}><Plus size={17}/>{tab === 'assets' ? 'Ajouter un bien' : tab === 'maintenance' ? 'Planifier une maintenance' : 'Enregistrer un transfert'}</button>}</div>
    </div>
    {notice && <div className="inline-notice"><AlertCircle size={16}/><span>{notice}</span><button className="icon-button" onClick={() => setNotice('')} aria-label="Fermer">×</button></div>}
    {!connected && <div className="inline-notice"><AlertCircle size={16}/><span>Configurez la connexion aux données et connectez-vous pour utiliser l’inventaire réel.</span></div>}
    <div className="module-tabs">{tabs.map(([id, label]) => <button key={id} className={`module-tab ${tab === id ? 'active' : ''}`} onClick={() => setTab(id)}>{label}{id === 'assets' ? ` (${allAssets.length})` : ''}</button>)}</div>
    <div className="table-toolbar"><div className="search-field"><Search size={17}/><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Rechercher un bien, un code, une intervention…"/></div><span className="muted-small">{visible.length} résultat(s) chargés{busy ? ' · Actualisation…' : ''}</span></div>
    <section className="data-card"><div className="table-scroll"><table><thead><tr>{headers.map((header) => <th key={header}>{header}</th>)}</tr></thead><tbody>
      {visible.map((row: Item) => <tr key={row.id}>
        {tab === 'assets' ? <>
          <td><span className="record-id">{row.asset_code}</span></td><td className="cell-strong">{row.name}</td><td>{Array.isArray(row.asset_categories) ? row.asset_categories[0]?.name || '—' : row.asset_categories?.name || '—'}</td>
          <td>{[row.brand, row.model].filter(Boolean).join(' / ') || '—'}</td><td>{row.serial_number || '—'}</td><td>{row.location || '—'}</td><td>{date(row.acquired_on)}</td><td>{money(row.acquisition_cost)}</td>
          <td><span className={`status-pill ${row.status === 'active' ? 'status-good' : ['lost','damaged','disposed','retired'].includes(row.status) ? 'status-warn' : 'status-info'}`}><i/>{({ active: 'En service', under_maintenance: 'En maintenance', lost: 'Perdu', damaged: 'Endommagé', disposed: 'Sorti', retired: 'Réformé' } as any)[row.status] || row.status}</span></td>
          <td>{!isReadOnly && !['disposed','retired','lost'].includes(row.status) && <button className="button button-secondary" onClick={() => beginEdit(row)}>Modifier</button>}</td>
        </> : tab === 'maintenance' ? <>
          <td>{date(row.maintenance_date)}</td><td>{(Array.isArray(row.assets) ? row.assets[0]?.asset_code : row.assets?.asset_code) || '—'} · {(Array.isArray(row.assets) ? row.assets[0]?.name : row.assets?.name) || 'Bien inconnu'}</td><td>{row.description}</td>
          <td>{(Array.isArray(row.suppliers) ? row.suppliers[0]?.name : row.suppliers?.name) || '—'}</td><td>{money(row.cost)}</td><td><span className="status-pill"><i/>{({ planned: 'Planifiée', in_progress: 'En cours', completed: 'Terminée', cancelled: 'Annulée' } as any)[row.status] || row.status}</span></td>
        </> : <>
          <td>{date(row.moved_at)}</td><td>{(Array.isArray(row.assets) ? row.assets[0]?.asset_code : row.assets?.asset_code) || '—'} · {(Array.isArray(row.assets) ? row.assets[0]?.name : row.assets?.name) || 'Bien inconnu'}</td><td>{({ assignment: 'Affectation', transfer: 'Transfert', maintenance_out: 'Sortie maintenance', maintenance_return: 'Retour maintenance', loss: 'Perte', damage: 'Dommage', disposal: 'Sortie définitive', inventory_adjustment: 'Ajustement inventaire' } as any)[row.movement_kind] || row.movement_kind}</td><td>{row.from_location || '—'}</td><td>{row.to_location || '—'}</td><td>{row.reason}</td>
        </>}
      </tr>)}
      {!visible.length && <tr><td colSpan={headers.length} className="empty-cell">{busy ? 'Chargement…' : 'Aucun enregistrement trouvé.'}</td></tr>}
    </tbody></table></div></section>

    {modal && !isReadOnly && <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) setModal(false); }}><section className="modal">
      <div className="modal-header"><div><span className="eyebrow">PATRIMOINE</span><h2>{tab === 'assets' ? (editingAssetId ? 'Modifier la fiche d’inventaire' : 'Ajouter un bien') : tab === 'maintenance' ? 'Enregistrer une maintenance' : 'Transférer un bien'}</h2></div><button className="icon-button" onClick={() => setModal(false)} aria-label="Fermer" disabled={busy}>×</button></div>
      <div className="modal-body">
        {tab === 'assets' ? <>
          {[[ 'asset_code','Code inventaire','text' ],[ 'name','Désignation *','text' ],[ 'description','Description','text' ],[ 'brand','Marque','text' ],[ 'model','Modèle','text' ],[ 'serial_number','Numéro de série','text' ],[ 'acquired_on','Date d’acquisition','date' ],[ 'cost','Valeur d’achat (FCFA)','number' ],[ 'invoice_reference','Référence facture','text' ],[ 'location','Emplacement','text' ]].map(([key,label,type]) => <label className="form-field" key={key}><span>{label}</span><input type={type} min={type === 'number' ? '0' : undefined} value={form[key] || ''} onChange={(event) => setForm({ ...form, [key]: event.target.value })}/></label>)}
          <label className="form-field"><span>Catégorie *</span><select value={form.category_id || ''} onChange={(event) => setForm({ ...form, category_id: event.target.value })}><option value="">Choisir une catégorie</option>{categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
          <label className="form-field"><span>Fournisseur</span><select value={form.supplier_id || ''} onChange={(event) => setForm({ ...form, supplier_id: event.target.value })}><option value="">Non renseigné</option>{suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select></label>
        </> : <>
          <label className="form-field"><span>Bien *</span><select value={form.asset_id || ''} onChange={(event) => setForm({ ...form, asset_id: event.target.value })}><option value="">Sélectionner un bien</option>{allAssets.filter((asset) => !['disposed','retired','lost'].includes(asset.status)).map((asset) => <option key={asset.id} value={asset.id}>{asset.asset_code} · {asset.name}</option>)}</select></label>
          {tab === 'maintenance' ? <>
            <label className="form-field"><span>Date *</span><input type="date" value={form.maintenance_date || ''} onChange={(event) => setForm({ ...form, maintenance_date: event.target.value })}/></label>
            <label className="form-field"><span>Intervention *</span><input value={form.description || ''} onChange={(event) => setForm({ ...form, description: event.target.value })}/></label>
            <label className="form-field"><span>Coût (FCFA)</span><input type="number" min="0" step="1" value={form.cost || '0'} onChange={(event) => setForm({ ...form, cost: event.target.value })}/></label>
            <label className="form-field"><span>Statut</span><select value={form.status || 'planned'} onChange={(event) => setForm({ ...form, status: event.target.value })}><option value="planned">Planifiée</option><option value="in_progress">En cours</option><option value="completed">Terminée</option></select></label>
            <label className="form-field"><span>Prestataire</span><select value={form.supplier_id || ''} onChange={(event) => setForm({ ...form, supplier_id: event.target.value })}><option value="">Non renseigné</option>{suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select></label>
          </> : <>
            <label className="form-field"><span>Nouvel emplacement *</span><input value={form.to_location || ''} onChange={(event) => setForm({ ...form, to_location: event.target.value })}/></label>
            <label className="form-field"><span>Motif *</span><input value={form.reason || ''} onChange={(event) => setForm({ ...form, reason: event.target.value })}/></label>
          </>}
        </>}
        <p className="form-footnote">Les changements d’emplacement créent un mouvement historique. Les maintenances en cours synchronisent le statut du bien ; les réceptions d’immobilisations créent automatiquement des fiches d’inventaire.</p>
      </div>
      <div className="modal-footer"><button className="button button-secondary" onClick={() => setModal(false)} disabled={busy}>Annuler</button><button className="button button-primary" disabled={busy || !connected} onClick={() => void submit()}>{busy ? 'Enregistrement…' : 'Enregistrer'}</button></div>
    </section></div>}
  </div>;
}
