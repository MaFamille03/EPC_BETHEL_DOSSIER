'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ArrowLeftRight,
  Download,
  RefreshCw,
  Search,
  Wallet,
  CircleAlert,
  CheckCircle2,
  X,
  Landmark,
  Smartphone,
  Plus,
  Banknote,
} from 'lucide-react';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';
import { useEPCAccess } from '@/components/access-context';

type TreasuryMode = 'cash-mobile-money' | 'bank' | 'transfers' | 'journal';
type AccountKind = 'cash' | 'bank' | 'mobile_money';
type Account = {
  id: string;
  code: string;
  name: string;
  kind: AccountKind;
  bank_name?: string | null;
  provider_name?: string | null;
  opening_balance: number;
  opening_date: string;
};
type AccountBalance = {
  account_id: string;
  account_code: string;
  account_name: string;
  account_kind: AccountKind;
  opening_balance: number;
  balance: number;
  total_in: number;
  total_out: number;
};
type Tx = {
  id: string;
  account_id: string;
  transaction_date: string;
  direction: 'in' | 'out';
  amount: number;
  transaction_type: string;
  transfer_group_id: string | null;
  reference: string | null;
  description: string;
  status: string;
  accounts_label: string;
  account_kind: AccountKind | string;
};
type TransferRecord = {
  id: string;
  groupId: string;
  date: string;
  source: string;
  destination: string;
  amount: number;
  reference: string;
  description: string;
  status: string;
};
type AccountForm = {
  code: string;
  name: string;
  kind: AccountKind;
  bank_name: string;
  provider_name: string;
  opening_balance: string;
  opening_date: string;
};

const money = (n: number) => new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(n) + ' FCFA';
const dateLabel = (s: string) => new Date(s).toLocaleDateString('fr-FR');
const typeLabel: Record<string, string> = {
  payment: 'Encaissement', expense: 'Dépense', transfer: 'Transfert',
  adjustment: 'Ajustement', reversal: 'Contrepassation', opening: 'Solde initial',
};
const kindLabel: Record<AccountKind | string, string> = {
  cash: 'Caisse', bank: 'Banque', mobile_money: 'Mobile Money',
};
const defaultAccountForm = (kind: AccountKind = 'cash'): AccountForm => ({
  code: '', name: '', kind, bank_name: '', provider_name: '',
  opening_balance: '0', opening_date: new Date().toISOString().slice(0, 10),
});
const asRelated = (value: any) => Array.isArray(value) ? value[0] : value;

export function TreasuryPage({
  title = 'Trésorerie',
  mode = 'journal',
}: {
  title?: string;
  mode?: TreasuryMode;
}) {
  const { isReadOnly, isAdmin } = useEPCAccess();
  const connected = isSupabaseConfigured();
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [accountBalances, setAccountBalances] = useState<AccountBalance[]>([]);
  const [txs, setTxs] = useState<Tx[]>([]);
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState('');
  const [query, setQuery] = useState('');
  const [selectedAccount, setSelectedAccount] = useState('all');
  const [showTransfer, setShowTransfer] = useState(false);
  const [showAccountForm, setShowAccountForm] = useState(false);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({ source: '', destination: '', amount: '', date: new Date().toISOString().slice(0, 10), reference: '', description: '' });
  const [accountForm, setAccountForm] = useState<AccountForm>(() => defaultAccountForm(mode === 'bank' ? 'bank' : 'cash'));

  const refresh = useCallback(async () => {
    const client = supabase();
    if (!client) {
      setAccounts([]); setTxs([]); setAccountBalances([]); return;
    }
    setLoading(true);
    try {
      const transactionQuery = mode === 'transfers'
        ? client.from('cash_transactions')
            .select('id,account_id,transaction_date,direction,amount,transaction_type,transfer_group_id,reference,description,status,cash_accounts(name,kind)')
            .eq('transaction_type', 'transfer').order('transaction_date', { ascending: false }).limit(2000)
        : client.from('cash_transactions')
            .select('id,account_id,transaction_date,direction,amount,transaction_type,transfer_group_id,reference,description,status,cash_accounts(name,kind)')
            .order('transaction_date', { ascending: false }).limit(1000);
      const [accountResult, transactionResult, balanceResult] = await Promise.all([
        client.from('cash_accounts')
          .select('id,code,name,kind,bank_name,provider_name,opening_balance,opening_date')
          .eq('is_active', true).order('name'),
        transactionQuery,
        client.rpc('get_treasury_balances'),
      ]);
      if (accountResult.error) throw accountResult.error;
      if (transactionResult.error) throw transactionResult.error;
      if (balanceResult.error) throw balanceResult.error;

      const nextAccounts = (accountResult.data || []) as Account[];
      const nextTxs = (transactionResult.data || []).map((row: any) => {
        const account = asRelated(row.cash_accounts);
        return {
          ...row,
          accounts_label: account?.name || 'Compte inconnu',
          account_kind: account?.kind || 'cash',
        } as Tx;
      });
      setAccounts(nextAccounts);
      setTxs(nextTxs);
      setAccountBalances((balanceResult.data || []) as AccountBalance[]);
      setForm(current => ({
        ...current,
        source: nextAccounts.some(a => a.id === current.source) ? current.source : (nextAccounts[0]?.id || ''),
        destination: nextAccounts.some(a => a.id === current.destination && a.id !== current.source)
          ? current.destination
          : (nextAccounts.find(a => a.id !== (nextAccounts[0]?.id || ''))?.id || ''),
      }));
    } catch (error: any) {
      setNotice('Chargement de la trésorerie impossible : ' + (error?.message || 'vérifiez les migrations et les autorisations.'));
    } finally {
      setLoading(false);
    }
  }, [mode]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    setQuery('');
    setSelectedAccount('all');
    setShowTransfer(false);
    setShowAccountForm(false);
    setNotice('');
  }, [mode]);

  const accountById = useMemo(() => new Map(accounts.map(account => [account.id, account] as const)), [accounts]);
  const allBalances = useMemo(() => accountBalances.map(balance => {
    const account = accountById.get(balance.account_id);
    return {
      ...balance,
      id: balance.account_id,
      name: balance.account_name,
      kind: balance.account_kind,
      bank_name: account?.bank_name || null,
      provider_name: account?.provider_name || null,
      received: Number(balance.total_in),
      spent: Number(balance.total_out),
    };
  }), [accountBalances, accountById]);

  const pageAccounts = useMemo(() => {
    if (mode === 'cash-mobile-money') return accounts.filter(account => account.kind === 'cash' || account.kind === 'mobile_money');
    if (mode === 'bank') return accounts.filter(account => account.kind === 'bank');
    return accounts;
  }, [accounts, mode]);
  const pageBalances = useMemo(() => {
    if (mode === 'cash-mobile-money') return allBalances.filter(account => account.kind === 'cash' || account.kind === 'mobile_money');
    if (mode === 'bank') return allBalances.filter(account => account.kind === 'bank');
    return allBalances;
  }, [allBalances, mode]);
  const pageAccountIds = useMemo(() => new Set(pageAccounts.map(account => account.id)), [pageAccounts]);

  const pageTransactions = useMemo(() => {
    if (mode === 'transfers') return txs.filter(transaction => transaction.transaction_type === 'transfer');
    if (mode === 'journal') return txs;
    return txs.filter(transaction => pageAccountIds.has(transaction.account_id));
  }, [mode, pageAccountIds, txs]);

  const filtered = useMemo(() => pageTransactions.filter(transaction => {
    const matchesSearch = [
      transaction.accounts_label, transaction.description, transaction.reference || '',
      typeLabel[transaction.transaction_type] || transaction.transaction_type,
      transaction.status, kindLabel[transaction.account_kind] || transaction.account_kind,
    ].join(' ').toLowerCase().includes(query.trim().toLowerCase());
    const matchesAccount = selectedAccount === 'all' || transaction.account_id === selectedAccount;
    return matchesSearch && matchesAccount;
  }), [pageTransactions, query, selectedAccount]);

  const transferRecords = useMemo<TransferRecord[]>(() => {
    const groups = new Map<string, Tx[]>();
    for (const transaction of txs) {
      if (transaction.transaction_type !== 'transfer' || !transaction.transfer_group_id) continue;
      const current = groups.get(transaction.transfer_group_id) || [];
      current.push(transaction);
      groups.set(transaction.transfer_group_id, current);
    }
    const records = [...groups.entries()].map(([groupId, rows]) => {
      const source = rows.find(row => row.direction === 'out');
      const destination = rows.find(row => row.direction === 'in');
      const chosen = source || destination || rows[0];
      const description = (source?.description || destination?.description || chosen.description)
        .replace(/^Transfert (sortant|entrant)\s*:\s*/i, '');
      return {
        id: groupId, groupId, date: chosen.transaction_date,
        source: source?.accounts_label || 'Mouvement source non chargé',
        destination: destination?.accounts_label || 'Mouvement destinataire non chargé',
        amount: Number(chosen.amount), reference: chosen.reference || '', description,
        status: rows.every(row => row.status === 'validated') ? 'validated' : chosen.status,
      };
    }).sort((a, b) => b.date.localeCompare(a.date));
    return records.filter(record => {
      const matchesSearch = [record.source, record.destination, record.description, record.reference].join(' ').toLowerCase().includes(query.trim().toLowerCase());
      const matchesAccount = selectedAccount === 'all'
        || txs.some(transaction => transaction.transfer_group_id === record.groupId && transaction.account_id === selectedAccount);
      return matchesSearch && matchesAccount;
    });
  }, [txs, query, selectedAccount]);

  const totalBalance = pageBalances.reduce((sum, account) => sum + Number(account.balance), 0);
  const totalIn = pageBalances.reduce((sum, account) => sum + Number(account.total_in), 0);
  const totalOut = pageBalances.reduce((sum, account) => sum + Number(account.total_out), 0);
  const transferVolume = transferRecords.reduce((sum, transfer) => sum + transfer.amount, 0);

  async function createAccount() {
    const client = supabase();
    if (!client || !isAdmin || isReadOnly) return;
    const openingBalance = Number(accountForm.opening_balance);
    const kindAllowed = mode === 'bank'
      ? accountForm.kind === 'bank'
      : accountForm.kind === 'cash' || accountForm.kind === 'mobile_money';
    if (!accountForm.code.trim() || !accountForm.name.trim() || !kindAllowed || !accountForm.opening_date
      || !Number.isSafeInteger(openingBalance) || openingBalance < 0
      || (accountForm.kind === 'mobile_money' && !accountForm.provider_name.trim())) {
      setNotice('Vérifiez le code, le nom, le type de compte, le solde initial et les champs obligatoires.');
      return;
    }
    setSaving(true);
    try {
      const { error } = await client.rpc('create_cash_account', {
        p_code: accountForm.code.trim().toUpperCase(),
        p_name: accountForm.name.trim(),
        p_kind: accountForm.kind,
        p_bank_name: accountForm.kind === 'bank' ? (accountForm.bank_name.trim() || null) : null,
        p_provider_name: accountForm.kind === 'mobile_money' ? accountForm.provider_name.trim() : null,
        p_opening_balance: openingBalance,
        p_opening_date: accountForm.opening_date,
      });
      if (error) throw error;
      setNotice('Compte créé. Son solde initial sera pris en compte à partir de la date d’ouverture.');
      setShowAccountForm(false);
      setAccountForm(defaultAccountForm(mode === 'bank' ? 'bank' : 'cash'));
      await refresh();
    } catch (error: any) {
      setNotice('Création du compte impossible : ' + (error?.message || 'vérifiez que la migration 021 est appliquée et que le code du compte est unique.'));
    } finally {
      setSaving(false);
    }
  }

  async function transfer() {
    const client = supabase();
    if (!client || isReadOnly) return;
    const amount = Number(form.amount);
    if (!form.source || !form.destination || form.source === form.destination || !Number.isSafeInteger(amount)
      || amount <= 0 || !form.date || !form.description.trim()) {
      setNotice('Choisissez deux comptes différents, une date, un montant entier positif et un libellé.');
      return;
    }
    setSaving(true);
    const { error } = await client.rpc('transfer_between_accounts', {
      p_source_account_id: form.source,
      p_destination_account_id: form.destination,
      p_amount: amount,
      p_transfer_date: new Date(form.date + 'T12:00:00.000Z').toISOString(),
      p_reference: form.reference || null,
      p_description: form.description,
    });
    setSaving(false);
    if (error) {
      setNotice('Transfert refusé : ' + (error.message || 'vérifiez les comptes et le solde disponible.'));
      return;
    }
    setShowTransfer(false);
    setForm(current => ({ ...current, amount: '', reference: '', description: '' }));
    setNotice('Transfert enregistré. Une sortie et une entrée liées ont été créées, sans recette ni dépense supplémentaire.');
    await refresh();
  }

  function exportCsv() {
    if (mode === 'transfers') {
      const rows = [
        ['Date', 'Compte source', 'Compte destinataire', 'Référence', 'Libellé', 'Montant FCFA', 'Statut'],
        ...transferRecords.map(transfer => [
          new Date(transfer.date).toLocaleString('fr-FR'), transfer.source, transfer.destination,
          transfer.reference, transfer.description, String(transfer.amount), transfer.status,
        ]),
      ];
      const csv = rows.map(row => row.map(value => `"${String(value ?? '').replaceAll('"', '""')}"`).join(';')).join('\n');
      const url = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' }));
      const anchor = document.createElement('a'); anchor.href = url; anchor.download = 'epc-bethel-transferts-internes.csv'; anchor.click(); URL.revokeObjectURL(url); return;
    }
    const data = [
      ['Date', 'Compte', 'Type de compte', 'Sens', 'Nature', 'Référence', 'Désignation', 'Montant FCFA', 'Statut'],
      ...filtered.map(transaction => [
        new Date(transaction.transaction_date).toLocaleString('fr-FR'), transaction.accounts_label,
        kindLabel[transaction.account_kind] || transaction.account_kind,
        transaction.direction === 'in' ? 'Entrée' : 'Sortie',
        typeLabel[transaction.transaction_type] || transaction.transaction_type,
        transaction.reference || '', transaction.description, String(transaction.amount), transaction.status,
      ]),
    ];
    const csv = data.map(row => row.map(value => `"${String(value ?? '').replaceAll('"', '""')}"`).join(';')).join('\n');
    const url = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' }));
    const anchor = document.createElement('a'); anchor.href = url; anchor.download = `epc-bethel-${mode}.csv`; anchor.click(); URL.revokeObjectURL(url);
  }

  const description = mode === 'cash-mobile-money'
    ? 'Gérez la caisse physique et les portefeuilles Mobile Money. Les comptes bancaires sont suivis dans la rubrique Banque.'
    : mode === 'bank'
      ? 'Consultez les comptes bancaires et vérifiez leurs mouvements avec les relevés importés.'
      : mode === 'transfers'
        ? 'Déplacez des fonds entre comptes actifs. Chaque transfert crée deux mouvements liés sans devenir une recette ou une dépense.'
        : 'Consultez l’historique consolidé des opérations sur tous les comptes actifs.';

  return <>
    <div className="page-heading treasury-page-heading">
      <div>
        <div className="eyebrow">GESTION FINANCIÈRE</div>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      <div className="heading-actions treasury-actions">
        <button className="button button-secondary" onClick={() => void refresh()} disabled={loading}>
          <RefreshCw size={15}/> Actualiser
        </button>
        <button className="button button-secondary" onClick={exportCsv}>
          <Download size={15}/> Exporter CSV
        </button>
        {isAdmin && !isReadOnly && (mode === 'cash-mobile-money' || mode === 'bank') && <button className="button button-primary" onClick={() => {
          setAccountForm(defaultAccountForm(mode === 'bank' ? 'bank' : 'cash'));
          setShowAccountForm(true);
        }} disabled={!connected}>
          <Plus size={15}/> Nouveau compte
        </button>}
        {!isReadOnly && mode === 'transfers' && <button className="button button-primary" onClick={() => setShowTransfer(true)} disabled={!connected || accounts.length < 2}>
          <ArrowLeftRight size={15}/> Nouveau transfert
        </button>}
      </div>
    </div>

    {!connected && <div className="inline-notice"><CircleAlert size={16}/><span>Mode aperçu : la connexion aux données doit être activée pour consulter les soldes et enregistrer des opérations.</span></div>}
    {notice && <div className="inline-notice"><CheckCircle2 size={16}/><span>{notice}</span><button onClick={() => setNotice('')} aria-label="Fermer"><X size={15}/></button></div>}

    {(mode === 'cash-mobile-money' || mode === 'bank') && <>
      <div className="metric-strip treasury-metrics">
        <div className="metric-mini"><span>Solde de {mode === 'bank' ? 'la banque' : 'caisse et Mobile Money'}</span><strong>{money(totalBalance)}</strong><small>Solde de départ et mouvements validés</small></div>
        <div className="metric-mini"><span>Entrées validées</span><strong>{money(totalIn)}</strong><small>Sur les comptes affichés</small></div>
        <div className="metric-mini"><span>Sorties validées</span><strong>{money(totalOut)}</strong><small>Sur les comptes affichés</small></div>
      </div>
      <section className="treasury-accounts-section">
        <div className="section-heading treasury-section-heading">
          <div><h2>{mode === 'bank' ? 'Comptes bancaires' : 'Caisse et portefeuilles Mobile Money'}</h2><p>{pageAccounts.length} compte{pageAccounts.length !== 1 ? 's' : ''} actif{pageAccounts.length !== 1 ? 's' : ''}</p></div>
        </div>
        {pageBalances.length > 0 ? <div className="treasury-account-grid">{pageBalances.map(account => {
          const accountIcon = account.kind === 'bank' ? Landmark : account.kind === 'mobile_money' ? Smartphone : Banknote;
          const AccountIcon = accountIcon;
          const sublabel = account.kind === 'bank' ? account.bank_name : account.kind === 'mobile_money' ? account.provider_name : 'Liquidités physiques';
          return <section className="panel treasury-account-card" key={account.id}>
            <div className="treasury-account-top"><span className="treasury-account-icon"><AccountIcon size={19}/></span><span className="status-pill status-good"><i/>{kindLabel[account.kind] || account.kind}</span></div>
            <p>{account.name}</p>
            {sublabel && <small className="treasury-account-provider">{sublabel}</small>}
            <strong>{money(Number(account.balance))}</strong>
            <div className="treasury-account-breakdown"><span>Entrées <b>{money(Number(account.total_in))}</b></span><span>Sorties <b>{money(Number(account.total_out))}</b></span></div>
          </section>;
        })}</div> : <section className="panel treasury-empty-accounts"><Wallet size={22}/><strong>Aucun compte dans cette rubrique</strong><p>{mode === 'bank' ? 'Créez un compte bancaire pour commencer le suivi et le rapprochement.' : 'Créez une caisse ou un portefeuille Mobile Money pour commencer le suivi.'}</p>{isAdmin && <button className="button button-primary" onClick={() => { setAccountForm(defaultAccountForm(mode === 'bank' ? 'bank' : 'cash')); setShowAccountForm(true); }} disabled={!connected}><Plus size={15}/> Créer un compte</button>}</section>}
      </section>
    </>}

    {mode === 'journal' && <div className="metric-strip treasury-metrics">
      <div className="metric-mini"><span>Trésorerie totale</span><strong>{money(allBalances.reduce((sum, account) => sum + Number(account.balance), 0))}</strong><small>Tous les comptes actifs</small></div>
      <div className="metric-mini"><span>Comptes actifs</span><strong>{accounts.length}</strong><small>Caisse, Mobile Money et banque</small></div>
      <div className="metric-mini"><span>Mouvements chargés</span><strong>{filtered.length}</strong><small>Derniers 1 000 mouvements au maximum</small></div>
    </div>}

    {mode === 'transfers' && <div className="metric-strip treasury-metrics treasury-transfer-metrics">
      <div className="metric-mini"><span>Transferts affichés</span><strong>{transferRecords.length}</strong><small>Une ligne par transfert lié</small></div>
      <div className="metric-mini"><span>Volume transféré affiché</span><strong>{money(transferVolume)}</strong><small>Ne constitue ni recette ni dépense</small></div>
    </div>}

    <section className="panel table-panel treasury-table-panel">
      <div className="panel-toolbar">
        <div><h2>{mode === 'transfers' ? 'Historique des transferts' : mode === 'journal' ? 'Journal de trésorerie' : mode === 'bank' ? 'Mouvements bancaires' : 'Mouvements de caisse et Mobile Money'}</h2>
          <p>{mode === 'transfers' ? `${transferRecords.length} transfert${transferRecords.length !== 1 ? 's' : ''} affiché${transferRecords.length !== 1 ? 's' : ''}` : `${filtered.length} mouvement${filtered.length !== 1 ? 's' : ''} affiché${filtered.length !== 1 ? 's' : ''}`}</p>
        </div>
        <div className="table-actions treasury-table-filters">
          <label className="treasury-account-filter"><span className="sr-only">Filtrer par compte</span><select value={selectedAccount} onChange={event => setSelectedAccount(event.target.value)}>
            <option value="all">Tous les comptes</option>
            {(mode === 'cash-mobile-money' || mode === 'bank' ? pageAccounts : accounts).map(account => <option key={account.id} value={account.id}>{account.name}</option>)}
          </select></label>
          <div className="table-search"><Search size={16}/><input value={query} onChange={event => setQuery(event.target.value)} placeholder={mode === 'transfers' ? 'Compte, libellé, référence…' : 'Compte, libellé, référence…'}/></div>
        </div>
      </div>
      {mode === 'transfers' ? <div className="table-scroll"><table><thead><tr><th>Date</th><th>Compte source</th><th>Compte destinataire</th><th>Référence</th><th>Libellé</th><th>Montant transféré</th><th>Statut</th></tr></thead><tbody>
        {transferRecords.map(transfer => <tr key={transfer.id}><td>{dateLabel(transfer.date)}</td><td>{transfer.source}</td><td>{transfer.destination}</td><td><span className="record-id">{transfer.reference || '—'}</span></td><td>{transfer.description}</td><td><strong>{money(transfer.amount)}</strong></td><td><span className={`status-pill ${transfer.status === 'validated' ? 'status-good' : 'status-info'}`}><i/>{transfer.status === 'validated' ? 'Validé' : 'En attente'}</span></td></tr>)}
        {!transferRecords.length && <tr><td colSpan={7} className="empty-cell">{loading ? 'Chargement des transferts…' : 'Aucun transfert trouvé.'}</td></tr>}
      </tbody></table></div> : <div className="table-scroll"><table><thead><tr><th>Date</th><th>Compte</th><th>Nature</th><th>Référence</th><th>Libellé</th><th>Entrée</th><th>Sortie</th><th>Statut</th></tr></thead><tbody>
        {filtered.map(transaction => <tr key={transaction.id}><td>{dateLabel(transaction.transaction_date)}</td><td><div className="treasury-tx-account">{transaction.accounts_label}<small>{kindLabel[transaction.account_kind] || transaction.account_kind}</small></div></td><td>{typeLabel[transaction.transaction_type] || transaction.transaction_type}</td><td><span className="record-id">{transaction.reference || '—'}</span></td><td>{transaction.description}</td><td>{transaction.direction === 'in' ? <strong className="money-in">{money(Number(transaction.amount))}</strong> : '—'}</td><td>{transaction.direction === 'out' ? <strong className="money-out">{money(Number(transaction.amount))}</strong> : '—'}</td><td><span className={`status-pill ${transaction.status === 'validated' ? 'status-good' : transaction.status === 'cancelled' ? 'status-warn' : 'status-info'}`}><i/>{transaction.status === 'validated' ? 'Validé' : transaction.status === 'cancelled' ? 'Annulé' : 'Brouillon'}</span></td></tr>)}
        {!filtered.length && <tr><td colSpan={8} className="empty-cell">{loading ? 'Chargement des mouvements…' : 'Aucun mouvement trouvé pour ces critères.'}</td></tr>}
      </tbody></table></div>}
      <div className="table-footer treasury-table-footer">
        <span>{mode === 'transfers' ? 'Chaque transfert est présenté une seule fois, avec ses deux comptes liés.' : mode === 'bank' ? 'Le rapprochement des relevés bancaires est disponible plus bas. Le rapprochement ne modifie pas les soldes.' : mode === 'cash-mobile-money' ? 'Les encaissements et dépenses validés alimentent automatiquement le solde du compte associé.' : 'Les transferts internes sont visibles comme une sortie et une entrée liées, mais ne sont pas des recettes ou dépenses.'}</span>
        <button className="button button-secondary" onClick={() => void refresh()} disabled={loading}><RefreshCw size={14}/> Actualiser</button>
      </div>
    </section>

    {mode === 'transfers' && showTransfer && !isReadOnly && <div className="modal-backdrop" onMouseDown={event => { if (event.target === event.currentTarget) setShowTransfer(false); }}><section className="modal"><div className="modal-header"><div><span className="eyebrow">MOUVEMENT INTERNE</span><h2>Transférer entre comptes</h2></div><button className="icon-button" onClick={() => setShowTransfer(false)} aria-label="Fermer"><X size={18}/></button></div><div className="modal-body"><div className="inline-notice payment-form-note"><ArrowLeftRight size={16}/><span>Le transfert crée deux mouvements liés, sans modifier les recettes ni les dépenses de l’établissement. Le solde du compte source est contrôlé par la base.</span></div><label className="form-field"><span>Compte source *</span><select value={form.source} onChange={event => setForm({ ...form, source: event.target.value, destination: form.destination === event.target.value ? '' : form.destination })}>{accounts.map(account => <option key={account.id} value={account.id}>{account.name}</option>)}</select></label><label className="form-field"><span>Compte destinataire *</span><select value={form.destination} onChange={event => setForm({ ...form, destination: event.target.value })}><option value="">Choisir un compte</option>{accounts.filter(account => account.id !== form.source).map(account => <option key={account.id} value={account.id}>{account.name}</option>)}</select></label><label className="form-field"><span>Montant (FCFA) *</span><input type="number" min="1" step="1" value={form.amount} onChange={event => setForm({ ...form, amount: event.target.value })} placeholder="Ex. 100000"/></label><label className="form-field"><span>Date *</span><input type="date" max={new Date().toISOString().slice(0, 10)} value={form.date} onChange={event => setForm({ ...form, date: event.target.value })}/></label><label className="form-field"><span>Référence</span><input value={form.reference} onChange={event => setForm({ ...form, reference: event.target.value })} placeholder="N° bordereau ou référence"/></label><label className="form-field"><span>Libellé du transfert *</span><input value={form.description} onChange={event => setForm({ ...form, description: event.target.value })} placeholder="Ex. Versement de caisse en banque"/></label></div><div className="modal-footer"><button className="button button-secondary" onClick={() => setShowTransfer(false)}>Annuler</button><button className="button button-primary" onClick={() => void transfer()} disabled={saving || !connected}>{saving ? 'Enregistrement…' : 'Valider le transfert'}</button></div></section></div>}

    {showAccountForm && isAdmin && !isReadOnly && (mode === 'cash-mobile-money' || mode === 'bank') && <div className="modal-backdrop" onMouseDown={event => { if (event.target === event.currentTarget) setShowAccountForm(false); }}><section className="modal"><div className="modal-header"><div><span className="eyebrow">PARAMÉTRAGE DE TRÉSORERIE</span><h2>Nouveau compte financier</h2></div><button className="icon-button" onClick={() => setShowAccountForm(false)} aria-label="Fermer"><X size={18}/></button></div><div className="modal-body treasury-account-form-body"><label className="form-field"><span>Nom du compte *</span><input value={accountForm.name} maxLength={100} onChange={event => setAccountForm(current => ({ ...current, name: event.target.value, code: current.code || event.target.value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 20) }))} placeholder="Ex. Caisse principale"/></label><label className="form-field"><span>Code unique *</span><input value={accountForm.code} maxLength={30} onChange={event => setAccountForm(current => ({ ...current, code: event.target.value.toUpperCase().replace(/[^A-Z0-9_-]/g, '') }))} placeholder="Ex. CAISSE_2"/></label>{mode === 'cash-mobile-money' && <label className="form-field"><span>Type de compte *</span><select value={accountForm.kind} onChange={event => setAccountForm(current => ({ ...current, kind: event.target.value as AccountKind }))}><option value="cash">Caisse physique</option><option value="mobile_money">Portefeuille Mobile Money</option></select></label>}{accountForm.kind === 'bank' && <label className="form-field"><span>Nom de la banque</span><input value={accountForm.bank_name} maxLength={100} onChange={event => setAccountForm(current => ({ ...current, bank_name: event.target.value }))} placeholder="Ex. Banque partenaire"/></label>}{accountForm.kind === 'mobile_money' && <label className="form-field"><span>Opérateur Mobile Money *</span><input value={accountForm.provider_name} maxLength={100} onChange={event => setAccountForm(current => ({ ...current, provider_name: event.target.value }))} placeholder="Ex. Orange Money, MTN MoMo…"/></label>}<label className="form-field"><span>Solde initial (FCFA) *</span><input type="number" min="0" step="1" value={accountForm.opening_balance} onChange={event => setAccountForm(current => ({ ...current, opening_balance: event.target.value }))}/></label><label className="form-field"><span>Date d’ouverture *</span><input type="date" value={accountForm.opening_date} onChange={event => setAccountForm(current => ({ ...current, opening_date: event.target.value }))}/><small>Le solde initial est disponible à partir de cette date.</small></label></div><div className="modal-footer"><button className="button button-secondary" onClick={() => setShowAccountForm(false)}>Annuler</button><button className="button button-primary" onClick={() => void createAccount()} disabled={saving || !connected}>{saving ? 'Création…' : 'Créer le compte'}</button></div></section></div>}
  </>;
}
