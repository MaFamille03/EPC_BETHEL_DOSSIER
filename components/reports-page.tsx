'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import * as XLSX from 'xlsx';
import {
  AlertCircle,
  ChevronLeft,
  ChevronRight,
  Download,
  Printer,
  RefreshCw,
  Search,
} from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';

type ReportKey = 'financial' | 'fees' | 'payments' | 'expenses' | 'cashbook' | 'purchases' | 'receipts' | 'assets' | 'maintenance';
type Row = Record<string, any>;
type Column = { key: string; label: string };
type YearOption = { id: string; label: string; is_current: boolean };

type ReportDefinition = { label: string; description: string; columns: Column[] };

const PAGE_SIZE = 100;
const money = (value: unknown) => `${new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(Number(value || 0))} FCFA`;
const dateOnly = (value: unknown) => {
  if (!value) return '—';
  const dateValue = new Date(`${String(value).slice(0, 10)}T12:00:00`);
  return Number.isNaN(dateValue.getTime()) ? String(value) : dateValue.toLocaleDateString('fr-FR');
};
const dateTime = (value: unknown) => {
  if (!value) return '—';
  const dateValue = new Date(String(value));
  return Number.isNaN(dateValue.getTime()) ? String(value) : dateValue.toLocaleString('fr-FR');
};

const methodLabels: Record<string, string> = {
  especes: 'Espèces',
  virement: 'Virement bancaire',
  mobile_money: 'Mobile Money',
  cheque: 'Chèque',
  autre: 'Autre',
};
const statusLabels: Record<string, string> = {
  draft: 'Brouillon',
  validated: 'Validé',
  cancelled: 'Annulé',
  archived: 'Archivé',
  active: 'En service',
  under_maintenance: 'En maintenance',
  lost: 'Perdu',
  damaged: 'Endommagé',
  disposed: 'Sorti',
  retired: 'Réformé',
  planned: 'Planifiée',
  in_progress: 'En cours',
  completed: 'Terminée',
  ordered: 'Commandée',
  partially_received: 'Partiellement reçue',
  received: 'Reçue',
  closed: 'Clôturée',
  submitted: 'À approuver',
  approved: 'Approuvée',
  rejected: 'Refusée',
  requested: 'Demandée',
};
const transactionLabels: Record<string, string> = {
  payment: 'Encaissement',
  expense: 'Dépense',
  transfer: 'Transfert',
  adjustment: 'Ajustement',
  reversal: 'Contrepassation',
  opening: 'Solde initial',
};

const reports: Record<Exclude<ReportKey, 'financial'>, ReportDefinition> = {
  fees: {
    label: 'Impayés de scolarité',
    description: 'Frais validés dont le solde reste positif, avec matricule, classe, année et montants nets.',
    columns: [
      { key: 'student_number', label: 'Matricule' }, { key: 'student_name', label: 'Élève' },
      { key: 'class_name', label: 'Classe' }, { key: 'school_year', label: 'Année scolaire' },
      { key: 'fee_category', label: 'Catégorie' }, { key: 'description', label: 'Désignation' },
      { key: 'gross_amount', label: 'Montant brut' }, { key: 'discount_amount', label: 'Réduction' },
      { key: 'amount_due', label: 'Montant net dû' }, { key: 'amount_paid', label: 'Déjà payé' },
      { key: 'balance_due', label: 'Reste à payer' }, { key: 'due_on', label: 'Échéance' },
      { key: 'created_on', label: 'Créé le' },
    ],
  },
  payments: {
    label: 'Journal des encaissements',
    description: 'Reçus, identité de l’élève, mode de paiement, compte destinataire et état de chaque opération.',
    columns: [
      { key: 'receipt_number', label: 'N° reçu' }, { key: 'paid_at', label: 'Date' },
      { key: 'student_number', label: 'Matricule' }, { key: 'student_name', label: 'Élève' },
      { key: 'class_name', label: 'Classe' }, { key: 'school_year', label: 'Année scolaire' },
      { key: 'amount', label: 'Montant' }, { key: 'payment_method', label: 'Mode' },
      { key: 'account_name', label: 'Compte' }, { key: 'payer_name', label: 'Payeur' },
      { key: 'external_reference', label: 'Référence externe' }, { key: 'status', label: 'Statut' },
      { key: 'cancellation_reason', label: 'Motif d’annulation' },
    ],
  },
  expenses: {
    label: 'Journal des dépenses',
    description: 'Dépenses en brouillon, validées ou annulées, avec la catégorie, le bénéficiaire et le compte.',
    columns: [
      { key: 'expense_number', label: 'N° dépense' }, { key: 'expense_date', label: 'Date' },
      { key: 'category', label: 'Catégorie' }, { key: 'beneficiary', label: 'Bénéficiaire' },
      { key: 'description', label: 'Désignation' }, { key: 'account_name', label: 'Compte' },
      { key: 'payment_method', label: 'Mode' }, { key: 'amount', label: 'Montant' },
      { key: 'status', label: 'Statut' }, { key: 'external_reference', label: 'Référence' },
      { key: 'cancellation_reason', label: 'Motif d’annulation' },
    ],
  },
  cashbook: {
    label: 'Journal de caisse et de banque',
    description: 'Mouvements entrants et sortants par compte, incluant les transferts internes et contrepassations.',
    columns: [
      { key: 'transaction_date', label: 'Date' }, { key: 'account_name', label: 'Compte' },
      { key: 'direction', label: 'Sens' }, { key: 'transaction_type', label: 'Nature' },
      { key: 'reference', label: 'Référence' }, { key: 'description', label: 'Libellé' },
      { key: 'amount', label: 'Montant' }, { key: 'status', label: 'Statut' },
    ],
  },
  purchases: {
    label: 'Bons de commande',
    description: 'Commandes passées aux fournisseurs, montant commandé, demande d’origine et livraison prévue.',
    columns: [
      { key: 'order_number', label: 'Bon de commande' }, { key: 'ordered_on', label: 'Date de commande' },
      { key: 'expected_delivery_on', label: 'Livraison prévue' }, { key: 'supplier', label: 'Fournisseur' },
      { key: 'request_number', label: 'Demande d’achat' }, { key: 'total_amount', label: 'Montant' },
      { key: 'status', label: 'Statut' }, { key: 'notes', label: 'Notes' },
    ],
  },
  receipts: {
    label: 'Réceptions de marchandises',
    description: 'Historique des bons de réception et références de livraison. Les réceptions ne créent pas de sortie de trésorerie.',
    columns: [
      { key: 'receipt_number', label: 'N° réception' }, { key: 'received_at', label: 'Date' },
      { key: 'order_number', label: 'Bon de commande' }, { key: 'supplier', label: 'Fournisseur' },
      { key: 'delivery_reference', label: 'Référence livraison' }, { key: 'line_count', label: 'Lignes reçues' },
      { key: 'status', label: 'Statut' }, { key: 'notes', label: 'Notes' },
    ],
  },
  assets: {
    label: 'Inventaire du patrimoine',
    description: 'Registre des immobilisations, valeur d’acquisition, emplacement, catégorie et état actuel.',
    columns: [
      { key: 'asset_code', label: 'Code inventaire' }, { key: 'name', label: 'Désignation' },
      { key: 'category', label: 'Catégorie' }, { key: 'brand', label: 'Marque' },
      { key: 'model', label: 'Modèle' }, { key: 'serial_number', label: 'N° série' },
      { key: 'acquired_on', label: 'Date d’acquisition' }, { key: 'acquisition_cost', label: 'Valeur d’achat' },
      { key: 'supplier', label: 'Fournisseur' }, { key: 'location', label: 'Emplacement' },
      { key: 'status', label: 'État' }, { key: 'invoice_reference', label: 'Facture' },
      { key: 'description', label: 'Description' },
    ],
  },
  maintenance: {
    label: 'Suivi de maintenance',
    description: 'Historique des interventions, prestataires, coûts et états des maintenances.',
    columns: [
      { key: 'maintenance_date', label: 'Date' }, { key: 'asset_code', label: 'Code inventaire' },
      { key: 'asset_name', label: 'Bien' }, { key: 'description', label: 'Intervention' },
      { key: 'supplier', label: 'Prestataire' }, { key: 'cost', label: 'Coût' },
      { key: 'status', label: 'Statut' },
    ],
  },
};

const moneyKeys = new Set(['gross_amount', 'discount_amount', 'amount_due', 'amount_paid', 'balance_due', 'amount', 'total_amount', 'acquisition_cost', 'cost']);
const dateKeys = new Set(['due_on', 'created_on', 'expense_date', 'ordered_on', 'expected_delivery_on', 'maintenance_date', 'acquired_on']);
const dateTimeKeys = new Set(['paid_at', 'transaction_date', 'received_at']);

function displayValue(key: string, value: unknown): string {
  if (value === null || value === undefined || value === '') return '—';
  if (moneyKeys.has(key)) return money(value);
  if (dateKeys.has(key)) return dateOnly(value);
  if (dateTimeKeys.has(key)) return dateTime(value);
  if (key === 'payment_method') return methodLabels[String(value)] || String(value);
  if (key === 'direction') return value === 'in' ? 'Entrée' : value === 'out' ? 'Sortie' : String(value);
  if (key === 'transaction_type') return transactionLabels[String(value)] || String(value);
  if (key === 'status') return statusLabels[String(value)] || String(value);
  return String(value);
}

function excelValue(key: string, value: unknown): string | number {
  if (value === null || value === undefined) return '';
  if (moneyKeys.has(key)) return Number(value || 0);
  return displayValue(key, value);
}

export function ReportsPage() {
  const connected = isSupabaseConfigured();
  const [reportKey, setReportKey] = useState<ReportKey>('financial');
  const [from, setFrom] = useState(() => `${new Date().getFullYear()}-${String(new Date().getMonth() + 1).padStart(2, '0')}-01`);
  const [to, setTo] = useState(() => new Date().toISOString().slice(0, 10));
  const [schoolYearId, setSchoolYearId] = useState('');
  const [yearOptions, setYearOptions] = useState<YearOption[]>([]);
  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [rows, setRows] = useState<Row[]>([]);
  const [totalRows, setTotalRows] = useState(0);
  const [page, setPage] = useState(0);
  const [summary, setSummary] = useState<Row | null>(null);
  const [loading, setLoading] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [notice, setNotice] = useState('');

  const needsSchoolYear = reportKey === 'fees' || reportKey === 'payments';
  const definition = reportKey === 'financial' ? null : reports[reportKey];
  const pageCount = Math.max(1, Math.ceil(totalRows / PAGE_SIZE));

  useEffect(() => {
    async function loadSchoolYears() {
      const client = supabase();
      if (!client) return;
      const { data, error } = await client.from('school_years').select('id,label,is_current').order('starts_on', { ascending: false });
      if (error) {
        setNotice(`Chargement des années scolaires impossible : ${error.message}`);
        return;
      }
      const items = (data || []) as YearOption[];
      setYearOptions(items);
      const current = items.find((item) => item.is_current);
      if (current) setSchoolYearId((previous) => previous || current.id);
    }
    void loadSchoolYears();
  }, []);

  const loadReport = useCallback(async () => {
    const client = supabase();
    if (!client) {
      setRows([]);
      setSummary(null);
      setTotalRows(0);
      return;
    }
    if (from && to && to < from) {
      setNotice('La date de fin doit être égale ou postérieure à la date de début.');
      return;
    }
    setLoading(true);
    setNotice('');
    try {
      if (reportKey === 'financial') {
        const { data, error } = await client.rpc('get_financial_summary', { p_from: from || null, p_to: to || null });
        if (error) throw error;
        setSummary((data || {}) as Row);
        setRows([]);
        setTotalRows(0);
      } else {
        const { data, error } = await client.rpc('get_management_report_rows', {
          p_report_key: reportKey,
          p_from: from || null,
          p_to: to || null,
          p_school_year_id: needsSchoolYear && schoolYearId ? schoolYearId : null,
          p_search: search || null,
          p_limit: PAGE_SIZE,
          p_offset: page * PAGE_SIZE,
        });
        if (error) throw error;
        const result = (data || {}) as { rows?: Row[]; total_count?: number };
        setRows(Array.isArray(result.rows) ? result.rows : []);
        setTotalRows(Number(result.total_count || 0));
        setSummary(null);
      }
    } catch (error: any) {
      setNotice(`Impossible de produire le rapport : ${error?.message || 'vérifiez les migrations et les autorisations Supabase.'}`);
      setRows([]);
      setSummary(null);
      setTotalRows(0);
    } finally {
      setLoading(false);
    }
  }, [from, to, reportKey, needsSchoolYear, schoolYearId, search, page]);

  useEffect(() => { void loadReport(); }, [loadReport]);

  const exportToExcel = useCallback(async () => {
    const client = supabase();
    if (!client) {
      setNotice('Configurez Supabase pour exporter les données réelles.');
      return;
    }
    if (from && to && to < from) {
      setNotice('La date de fin doit être égale ou postérieure à la date de début.');
      return;
    }
    setExporting(true);
    setNotice('');
    try {
      if (reportKey === 'financial') {
        const { data, error } = await client.rpc('get_financial_summary', { p_from: from || null, p_to: to || null });
        if (error) throw error;
        const s = (data || {}) as Row;
        const summaryRows = [
          ['Indicateur', 'Montant / nombre'],
          ['Recettes validées sur la période', Number(s.receipts_period || 0)],
          ['Nombre total de reçus validés', Number(s.validated_receipt_count || 0)],
          ['Dépenses validées sur la période', Number(s.expenses_period || 0)],
          ['Nombre total de dépenses validées', Number(s.validated_expense_count || 0)],
          ['Frais nets validés (toutes périodes)', Number(s.fees_net || 0)],
          ['Réductions accordées (toutes périodes)', Number(s.discounts_total || 0)],
          ['Paiements affectés (toutes périodes)', Number(s.payments_allocated || 0)],
          ['Impayés (toutes périodes)', Number(s.outstanding_balance || 0)],
          ['Trésorerie disponible', Number(s.treasury_total || 0)],
          ['Dépenses en brouillon', Number(s.draft_expense_total || 0)],
          ['Nombre de dépenses en brouillon', Number(s.draft_expense_count || 0)],
        ];
        const workbook = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(workbook, XLSX.utils.aoa_to_sheet(summaryRows), 'Synthèse financière');
        XLSX.writeFile(workbook, `EPC_BETHEL_synthese_financiere_${from || 'debut'}_${to || 'aujourdhui'}.xlsx`);
      } else if (definition) {
        const allRows: Row[] = [];
        const exportLimit = 50000;
        for (let offset = 0; offset < exportLimit; offset += 250) {
          const { data, error } = await client.rpc('get_management_report_rows', {
            p_report_key: reportKey,
            p_from: from || null,
            p_to: to || null,
            p_school_year_id: needsSchoolYear && schoolYearId ? schoolYearId : null,
            p_search: search || null,
            p_limit: 250,
            p_offset: offset,
          });
          if (error) throw error;
          const batch = Array.isArray((data as any)?.rows) ? (data as any).rows as Row[] : [];
          allRows.push(...batch);
          if (batch.length < 250) break;
        }
        if (allRows.length >= exportLimit) {
          setNotice('L’export a atteint la limite de sécurité de 50 000 lignes. Filtrez la période ou la recherche pour exporter le rapport par parties.');
        }
        const dataForSheet = allRows.map((row) => Object.fromEntries(definition.columns.map((column) => [column.label, excelValue(column.key, row[column.key])])))
          .concat(allRows.length ? [] : [Object.fromEntries(definition.columns.map((column) => [column.label, '']))]);
        const workbook = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(workbook, XLSX.utils.json_to_sheet(dataForSheet), definition.label.slice(0, 31));
        XLSX.writeFile(workbook, `EPC_BETHEL_${reportKey}_${from || 'debut'}_${to || 'aujourdhui'}.xlsx`);
      }
    } catch (error: any) {
      setNotice(`Export impossible : ${error?.message || 'erreur inconnue'}`);
    } finally {
      setExporting(false);
    }
  }, [definition, from, to, reportKey, needsSchoolYear, schoolYearId, search]);

  const searchReport = () => { setPage(0); setSearch(searchInput.trim()); };
  const currentRows = useMemo(() => rows, [rows]);

  return (
    <div className="module-workspace">
      <div className="page-heading">
        <div>
          <div className="eyebrow">PILOTAGE DE L’ÉTABLISSEMENT</div>
          <h1>Rapports & exports</h1>
          <p>Produisez des états à partir des données enregistrées dans Supabase, avec filtres, pagination et export Excel.</p>
        </div>
        <div className="heading-actions">
          <button className="button button-secondary" onClick={() => window.print()}><Printer size={16}/> Imprimer</button>
          <button className="button button-secondary" onClick={() => void exportToExcel()} disabled={!connected || exporting || loading}><Download size={16}/>{exporting ? 'Export…' : 'Exporter Excel'}</button>
          <button className="button button-primary" onClick={() => void loadReport()} disabled={!connected || loading}><RefreshCw size={16}/>{loading ? 'Actualisation…' : 'Actualiser'}</button>
        </div>
      </div>

      {!connected && <div className="inline-notice"><AlertCircle size={16}/><span>Configurez les variables Supabase et connectez-vous pour afficher les rapports réels. Aucun chiffre de démonstration n’est utilisé dans ce module.</span></div>}
      {notice && <div className="inline-notice"><AlertCircle size={16}/><span>{notice}</span><button className="icon-button" onClick={() => setNotice('')} aria-label="Fermer">×</button></div>}

      <section className="panel report-filter-panel">
        <div className="report-filters-grid">
          <label className="form-field"><span>Type de rapport</span>
            <select value={reportKey} onChange={(event) => { setReportKey(event.target.value as ReportKey); setPage(0); }}>
              <option value="financial">Synthèse financière</option>
              <option value="fees">Impayés de scolarité</option>
              <option value="payments">Journal des encaissements</option>
              <option value="expenses">Journal des dépenses</option>
              <option value="cashbook">Journal de caisse et de banque</option>
              <option value="purchases">Bons de commande</option>
              <option value="receipts">Réceptions de marchandises</option>
              <option value="assets">Inventaire du patrimoine</option>
              <option value="maintenance">Suivi de maintenance</option>
            </select>
          </label>
          <label className="form-field"><span>Date de début</span><input type="date" value={from} max={to || undefined} onChange={(event) => { setFrom(event.target.value); setPage(0); }}/></label>
          <label className="form-field"><span>Date de fin</span><input type="date" value={to} min={from || undefined} onChange={(event) => { setTo(event.target.value); setPage(0); }}/></label>
          {needsSchoolYear && <label className="form-field"><span>Année scolaire</span>
            <select value={schoolYearId} onChange={(event) => { setSchoolYearId(event.target.value); setPage(0); }}>
              <option value="">Toutes les années</option>
              {yearOptions.map((year) => <option key={year.id} value={year.id}>{year.label}{year.is_current ? ' · en cours' : ''}</option>)}
            </select>
          </label>}
          {reportKey !== 'financial' && <label className="form-field report-search-field"><span>Recherche dans le rapport</span>
            <div className="report-search-box"><Search size={16}/><input value={searchInput} onChange={(event) => setSearchInput(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') searchReport(); }} placeholder="Matricule, référence, libellé…"/><button className="button button-secondary" onClick={searchReport}>Rechercher</button></div>
          </label>}
        </div>
        {reportKey === 'fees' && <p className="form-footnote">Les dates filtrent la date de création des frais ; le solde tient compte de tous les paiements validés à date.</p>}
      </section>

      {reportKey === 'financial' ? (
        <>
          <div className="metric-strip report-metrics-grid">
            <div className="metric-mini"><span>Recettes validées · période</span><strong>{money(summary?.receipts_period)}</strong><small>Sur la période sélectionnée, calcul SQL complet</small></div>
            <div className="metric-mini"><span>Dépenses validées · période</span><strong>{money(summary?.expenses_period)}</strong><small>Sur la période sélectionnée, calcul SQL complet</small></div>
            <div className="metric-mini"><span>Impayés de scolarité</span><strong>{money(summary?.outstanding_balance)}</strong><small>Solde total restant dû, toutes années confondues</small></div>
            <div className="metric-mini"><span>Trésorerie disponible</span><strong>{money(summary?.treasury_total)}</strong><small>Soldes des comptes actifs calculés en base</small></div>
          </div>
          <section className="panel table-panel">
            <div className="panel-toolbar"><div><h2>Indicateurs complémentaires</h2><p>Les indicateurs globaux ne sont pas limités à la période du filtre.</p></div><span className="muted-small">{loading ? 'Actualisation en cours…' : 'Source : PostgreSQL / Supabase'}</span></div>
            <div className="table-scroll"><table><thead><tr><th>Indicateur</th><th>Valeur</th><th>Périmètre</th></tr></thead><tbody>
              <tr><td>Nombre de reçus validés</td><td>{new Intl.NumberFormat('fr-FR').format(Number(summary?.validated_receipt_count || 0))}</td><td>Toutes périodes</td></tr>
              <tr><td>Nombre de dépenses validées</td><td>{new Intl.NumberFormat('fr-FR').format(Number(summary?.validated_expense_count || 0))}</td><td>Toutes périodes</td></tr>
              <tr><td>Frais nets validés</td><td>{money(summary?.fees_net)}</td><td>Toutes années scolaires</td></tr>
              <tr><td>Réductions accordées</td><td>{money(summary?.discounts_total)}</td><td>Tous les frais validés</td></tr>
              <tr><td>Paiements affectés aux frais</td><td>{money(summary?.payments_allocated)}</td><td>Paiements validés</td></tr>
              <tr><td>Dépenses en brouillon</td><td>{money(summary?.draft_expense_total)} ({Number(summary?.draft_expense_count || 0)} opération(s))</td><td>À valider, sans effet sur la trésorerie</td></tr>
            </tbody></table></div>
          </section>
        </>
      ) : (
        <>
          <div className="metric-strip report-metrics-grid">
            <div className="metric-mini"><span>Enregistrements</span><strong>{new Intl.NumberFormat('fr-FR').format(totalRows)}</strong><small>Résultat complet, calculé côté base</small></div>
            <div className="metric-mini"><span>Page affichée</span><strong>{page + 1} / {pageCount}</strong><small>{PAGE_SIZE} lignes maximum par page</small></div>
            <div className="metric-mini"><span>Type de rapport</span><strong className="report-metric-label">{definition?.label || ''}</strong><small>Filtres appliqués côté PostgreSQL</small></div>
          </div>
          <section className="panel table-panel">
            <div className="panel-toolbar"><div><h2>{definition?.label}</h2><p>{definition?.description}</p></div><span className="muted-small">{loading ? 'Chargement…' : `${totalRows.toLocaleString('fr-FR')} résultat(s)`}</span></div>
            <div className="table-scroll"><table><thead><tr>{(definition?.columns || []).map((column) => <th key={column.key}>{column.label}</th>)}</tr></thead><tbody>
              {currentRows.map((row, index) => <tr key={row.id || `${reportKey}-${page}-${index}`}>
                {(definition?.columns || []).map((column) => <td key={column.key}>{moneyKeys.has(column.key) ? <strong>{displayValue(column.key, row[column.key])}</strong> : column.key === 'status' ? <span className={`status-pill ${['cancelled','rejected','lost','damaged','disposed','retired'].includes(String(row[column.key])) ? 'status-warn' : ['validated','active','received','completed','approved'].includes(String(row[column.key])) ? 'status-good' : 'status-info'}`}><i/>{displayValue(column.key, row[column.key])}</span> : displayValue(column.key, row[column.key])}</td>)}
              </tr>)}
              {!currentRows.length && <tr><td colSpan={definition?.columns.length || 1} className="empty-cell">{loading ? 'Chargement des données…' : 'Aucune donnée pour ces filtres.'}</td></tr>}
            </tbody></table></div>
            <div className="table-footer"><span>Affichage de <strong>{totalRows ? page * PAGE_SIZE + 1 : 0}–{Math.min((page + 1) * PAGE_SIZE, totalRows)}</strong> sur <strong>{totalRows.toLocaleString('fr-FR')}</strong>. L’export Excel inclut toutes les pages filtrées, jusqu’à 50 000 lignes.</span>
              <div className="pagination"><button className="icon-button bordered" onClick={() => setPage((value) => Math.max(0, value - 1))} disabled={page === 0 || loading} aria-label="Page précédente"><ChevronLeft size={16}/></button><span className="page-number active">{page + 1} / {pageCount}</span><button className="icon-button bordered" onClick={() => setPage((value) => value + 1)} disabled={loading || (page + 1) * PAGE_SIZE >= totalRows} aria-label="Page suivante"><ChevronRight size={16}/></button></div>
            </div>
          </section>
        </>
      )}
    </div>
  );
}
