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
  Pencil,
  Trash2,
  ClipboardCheck,
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
  payment_channel: string;
  payment_id: string | null;
  expense_id: string | null;
  reverses_transaction_id: string | null;
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
type CashRegisterStatus = {
  account_id: string | null;
  account_name: string;
  cash_theoretical_balance: number | null;
  cash_physical_balance: number | null;
  cash_variance: number | null;
  cash_counted_at: string | null;
  cash_count_note: string | null;
  orange_money_balance: number | null;
  wave_balance: number | null;
  moov_money_balance: number | null;
  other_mobile_money_balance: number | null;
};
type CashMovementForm = { direction: 'in' | 'out'; amount: string; date: string; payment_channel: string; reference: string; description: string; reason: string; };
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
const paymentChannelLabel: Record<string, string> = {
  especes: 'Espèces', orange_money: 'Orange Money', wave: 'Wave', moov_money: 'Moov Money',
  mobile_money: 'Mobile Money (non précisé)', virement: 'Virement bancaire', cheque: 'Chèque', autre: 'Autre',
};
const defaultCashMovementForm = (): CashMovementForm => ({ direction: 'in', amount: '', date: new Date().toISOString().slice(0, 10), payment_channel: 'especes', reference: '', description: '', reason: '' });
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
  const [cashRegisterStatus, setCashRegisterStatus] = useState<CashRegisterStatus | null>(null);
  const [selectedChannel, setSelectedChannel] = useState('all');
  const [showMovementForm, setShowMovementForm] = useState(false);
  const [editingMovementId, setEditingMovementId] = useState<string | null>(null);
  const [movementForm, setMovementForm] = useState<CashMovementForm>(defaultCashMovementForm);
  const [showCashCountForm, setShowCashCountForm] = useState(false);
  const [physicalCountForm, setPhysicalCountForm] = useState({ amount: '', note: '' });
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
      setAccounts([]); setTxs([]); setAccountBalances([]); setCashRegisterStatus(null); return;
    }
    setLoading(true);
    try {
      const transactionQuery = mode === 'transfers'
        ? client.from('cash_transactions')
            .select('id,account_id,transaction_date,direction,amount,transaction_type,transfer_group_id,reference,description,status,payment_channel,payment_id,expense_id,reverses_transaction_id,cash_accounts(name,kind)')
            .eq('transaction_type', 'transfer').order('transaction_date', { ascending: false }).limit(2000)
        : client.from('cash_transactions')
            .select('id,account_id,transaction_date,direction,amount,transaction_type,transfer_group_id,reference,description,status,payment_channel,payment_id,expense_id,reverses_transaction_id,cash_accounts(name,kind)')
            .order('transaction_date', { ascending: false }).limit(1000);
      const [accountResult, transactionResult, balanceResult, cashStatusResult] = await Promise.all([
        client.from('cash_accounts')
          .select('id,code,name,kind,bank_name,provider_name,opening_balance,opening_date')
          .eq('is_active', true).order('name'),
        transactionQuery,
        client.rpc('get_treasury_balances'),
        mode === 'cash-mobile-money' ? client.rpc('get_cash_register_status') : Promise.resolve({ data: null, error: null }),
      ]);
      if (accountResult.error) throw accountResult.error;
      if (transactionResult.error) throw transactionResult.error;
      if (balanceResult.error) throw balanceResult.error;
      if (cashStatusResult.error) throw cashStatusResult.error;

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
      const statusRows = Array.isArray(cashStatusResult.data) ? cashStatusResult.data : cashStatusResult.data ? [cashStatusResult.data] : [];
      setCashRegisterStatus((statusRows[0] || null) as CashRegisterStatus | null);
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
    setSelectedChannel('all');
    setShowTransfer(false);
    setShowMovementForm(false);
    setShowCashCountForm(false);
    setEditingMovementId(null);
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
    const matchesAccount = mode === 'cash-mobile-money' || selectedAccount === 'all' || transaction.account_id === selectedAccount;
    const matchesChannel = mode !== 'cash-mobile-money' || selectedChannel === 'all' || (transaction.payment_channel || 'autre') === selectedChannel;
    return matchesSearch && matchesAccount && matchesChannel;
  }), [mode, pageTransactions, query, selectedAccount, selectedChannel]);

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
  const balanceAfterTransaction = useMemo(() => {
    const balances = new Map<string, number>();
    if (mode === 'cash-mobile-money') {
      const currentByChannel: Record<string, number> = {
        especes: Number(cashRegisterStatus?.cash_theoretical_balance || 0),
        orange_money: Number(cashRegisterStatus?.orange_money_balance || 0),
        wave: Number(cashRegisterStatus?.wave_balance || 0),
        moov_money: Number(cashRegisterStatus?.moov_money_balance || 0),
        mobile_money: Number(cashRegisterStatus?.other_mobile_money_balance || 0),
      };
      const running = new Map<string, number>(Object.entries(currentByChannel));
      for (const tx of [...pageTransactions].sort((a,b) => b.transaction_date.localeCompare(a.transaction_date))) {
        const channel = tx.payment_channel || 'autre';
        const channelBalance = running.has(channel) ? Number(running.get(channel)) : totalBalance;
        balances.set(tx.id, channelBalance);
        if (tx.status === 'validated' && new Date(tx.transaction_date).getTime() <= Date.now()) {
          running.set(channel, channelBalance - (tx.direction === 'in' ? Number(tx.amount) : -Number(tx.amount)));
        }
      }
    }
    return balances;
  }, [mode, pageTransactions, totalBalance, cashRegisterStatus]);
  const mobileMoneyTotal = Number(cashRegisterStatus?.orange_money_balance || 0)
    + Number(cashRegisterStatus?.wave_balance || 0)
    + Number(cashRegisterStatus?.moov_money_balance || 0)
    + Number(cashRegisterStatus?.other_mobile_money_balance || 0);

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

  async function saveCashMovement() {
    const client = supabase();
    if (!client || isReadOnly) return;
    const amount = Number(movementForm.amount);
    if (!movementForm.date || !Number.isSafeInteger(amount) || amount <= 0 || !movementForm.description.trim()
      || !['especes','orange_money','wave','moov_money'].includes(movementForm.payment_channel)) {
      setNotice('Renseignez la date, le moyen de paiement, le libellé et un montant entier positif.');
      return;
    }
    if (editingMovementId && !movementForm.reason.trim()) {
      setNotice('Le motif de modification est obligatoire pour conserver la traçabilité.');
      return;
    }
    setSaving(true);
    const rpcName = editingMovementId ? 'update_manual_cash_movement' : 'create_manual_cash_movement';
    const args = editingMovementId ? {
      p_transaction_id: editingMovementId,
      p_direction: movementForm.direction,
      p_amount: amount,
      p_transaction_date: movementForm.date,
      p_payment_channel: movementForm.payment_channel,
      p_reference: movementForm.reference || null,
      p_description: movementForm.description.trim(),
      p_reason: movementForm.reason.trim(),
    } : {
      p_direction: movementForm.direction,
      p_amount: amount,
      p_transaction_date: movementForm.date,
      p_payment_channel: movementForm.payment_channel,
      p_reference: movementForm.reference || null,
      p_description: movementForm.description.trim(),
    };
    const { error } = await client.rpc(rpcName, args);
    setSaving(false);
    if (error) {
      setNotice(`${editingMovementId ? 'Modification' : 'Ajout'} impossible : ${error.message || 'vérifiez les champs et le solde du moyen de paiement.'}`);
      return;
    }
    setShowMovementForm(false);
    setEditingMovementId(null);
    setMovementForm(defaultCashMovementForm());
    setNotice(editingMovementId ? 'Ligne de caisse modifiée. Le journal et les soldes ont été recalculés.' : 'Nouvelle ligne de caisse ajoutée et enregistrée dans le journal.');
    await refresh();
  }

  async function deleteCashMovement(transaction: Tx) {
    const reason = window.prompt(`Motif obligatoire pour supprimer la ligne « ${transaction.description} » (${money(Number(transaction.amount))}) :`);
    if (!reason?.trim()) return;
    const client = supabase();
    if (!client || isReadOnly) return;
    setSaving(true);
    const { error } = await client.rpc('delete_manual_cash_movement', { p_transaction_id: transaction.id, p_reason: reason.trim() });
    setSaving(false);
    if (error) {
      setNotice('Suppression refusée : ' + (error.message || 'cette ligne peut être liée à une opération comptable.'));
      return;
    }
    setNotice('Ligne supprimée. Le motif et les anciennes valeurs restent consignés dans le journal d’audit.');
    await refresh();
  }

  function startEditCashMovement(transaction: Tx) {
    setEditingMovementId(transaction.id);
    setMovementForm({
      direction: transaction.direction,
      amount: String(transaction.amount),
      date: new Date(transaction.transaction_date).toISOString().slice(0,10),
      payment_channel: ['especes','orange_money','wave','moov_money'].includes(transaction.payment_channel) ? transaction.payment_channel : 'especes',
      reference: transaction.reference || '',
      description: transaction.description,
      reason: '',
    });
    setShowMovementForm(true);
  }

  async function recordCashCount() {
    const client = supabase();
    if (!client || isReadOnly) return;
    const amount = Number(physicalCountForm.amount);
    if (!physicalCountForm.amount.trim() || !Number.isSafeInteger(amount) || amount < 0) {
      setNotice('Saisissez le montant réellement compté en espèces (zéro ou plus).');
      return;
    }
    setSaving(true);
    const { error } = await client.rpc('record_cash_register_count', { p_counted_amount: amount, p_note: physicalCountForm.note || null });
    setSaving(false);
    if (error) {
      setNotice('Enregistrement du comptage impossible : ' + (error.message || 'vérifiez les autorisations et la migration 022.'));
      return;
    }
    setShowCashCountForm(false);
    setPhysicalCountForm({ amount: '', note: '' });
    setNotice('Comptage physique enregistré. L’écart est calculé par rapport au solde théorique au moment du comptage.');
    await refresh();
  }

  function exportCsv() {
    if (mode === 'cash-mobile-money') {
      const rows = [
        ['Référence','Date','Libellé','Moyen de paiement','Entrée FCFA','Sortie FCFA','Solde du moyen FCFA','Statut'],
        ...filtered.map(transaction => [transaction.reference || '', new Date(transaction.transaction_date).toLocaleDateString('fr-FR'), transaction.description,
          paymentChannelLabel[transaction.payment_channel] || transaction.payment_channel,
          transaction.direction === 'in' ? String(transaction.amount) : '', transaction.direction === 'out' ? String(transaction.amount) : '',
          String(balanceAfterTransaction.get(transaction.id) ?? 0), transaction.status]),
      ];
      const csv = rows.map(row => row.map(value => `"${String(value ?? '').replaceAll('"', '""')}"`).join(';')).join('\n');
      const url = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' }));
      const anchor = document.createElement('a'); anchor.href = url; anchor.download = 'epc-bethel-caisse.csv'; anchor.click(); URL.revokeObjectURL(url); return;
    }
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
    ? 'Un seul registre de caisse : chaque mouvement indique s’il est en espèces, Orange Money, Wave ou Moov Money. Les comptes bancaires restent dans Banque.'
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
        {isAdmin && !isReadOnly && mode === 'bank' && <button className="button button-primary" onClick={() => {
          setAccountForm(defaultAccountForm('bank'));
          setShowAccountForm(true);
        }} disabled={!connected}>
          <Plus size={15}/> Nouveau compte bancaire
        </button>}
        {!isReadOnly && mode === 'transfers' && <button className="button button-primary" onClick={() => setShowTransfer(true)} disabled={!connected || accounts.length < 2}>
          <ArrowLeftRight size={15}/> Nouveau transfert
        </button>}
      </div>
    </div>

    {!connected && <div className="inline-notice"><CircleAlert size={16}/><span>Mode aperçu : la connexion aux données doit être activée pour consulter les soldes et enregistrer des opérations.</span></div>}
    {notice && <div className="inline-notice"><CheckCircle2 size={16}/><span>{notice}</span><button onClick={() => setNotice('')} aria-label="Fermer"><X size={15}/></button></div>}

    {mode === 'cash-mobile-money' && <>
      <div className="metric-strip treasury-metrics cash-register-summary-grid">
        <div className="metric-mini"><span>Caisse théorique en espèces</span><strong>{money(Number(cashRegisterStatus?.cash_theoretical_balance || 0))}</strong><small>Solde calculé à partir des mouvements validés en espèces</small></div>
        <div className="metric-mini"><span>Caisse physique réelle</span><strong>{cashRegisterStatus?.cash_physical_balance == null ? 'À renseigner' : money(Number(cashRegisterStatus.cash_physical_balance))}</strong><small>{cashRegisterStatus?.cash_counted_at ? `Dernier comptage : ${new Date(cashRegisterStatus.cash_counted_at).toLocaleString('fr-FR')}` : 'Aucun comptage enregistré'}</small></div>
        <div className="metric-mini"><span>Écart au dernier comptage</span><strong className={Number(cashRegisterStatus?.cash_variance || 0) < 0 ? 'money-out' : Number(cashRegisterStatus?.cash_variance || 0) > 0 ? 'money-in' : ''}>{cashRegisterStatus?.cash_variance == null ? 'À calculer' : money(Number(cashRegisterStatus.cash_variance))}</strong><small>{cashRegisterStatus?.cash_variance == null ? 'Enregistrez un comptage physique' : 'Réel physique moins théorique au moment du comptage'}</small></div>
        <div className="metric-mini"><span>Soldes Mobile Money</span><strong>{money(mobileMoneyTotal)}</strong><small>Orange Money, Wave et Moov Money</small></div>
      </div>
      <section className="panel cash-register-panel">
        <div className="section-heading treasury-section-heading cash-register-panel-heading"><div><h2>Caisse unique et moyens de paiement</h2><p>Un seul compte de caisse. Espèces, Orange Money, Wave et Moov Money sont des moyens de règlement, pas des comptes distincts. La Banque reste séparée.</p></div><div className="cash-register-panel-actions">{!isReadOnly && <button className="button button-secondary" onClick={() => setShowCashCountForm(true)} disabled={!connected || saving}><ClipboardCheck size={15}/> Compter la caisse</button>}{!isReadOnly && <button className="button button-primary" onClick={() => { setEditingMovementId(null); setMovementForm(defaultCashMovementForm()); setShowMovementForm(true); }} disabled={!connected}><Plus size={15}/> Ajouter une ligne de caisse</button>}</div></div>
        <div className="cash-method-balances" aria-label="Soldes par moyen de paiement Mobile Money">
          <div><span className="cash-method-dot cash-dot-orange"/><span>Orange Money</span><strong>{money(Number(cashRegisterStatus?.orange_money_balance || 0))}</strong></div>
          <div><span className="cash-method-dot cash-dot-wave"/><span>Wave</span><strong>{money(Number(cashRegisterStatus?.wave_balance || 0))}</strong></div>
          <div><span className="cash-method-dot cash-dot-moov"/><span>Moov Money</span><strong>{money(Number(cashRegisterStatus?.moov_money_balance || 0))}</strong></div>
          {Number(cashRegisterStatus?.other_mobile_money_balance || 0) !== 0 && <div><span className="cash-method-dot cash-dot-other"/><span>Mobile Money non précisé</span><strong>{money(Number(cashRegisterStatus?.other_mobile_money_balance || 0))}</strong></div>}
        </div>
        <div className="inline-notice cash-register-explainer"><CircleAlert size={16}/><span>La caisse théorique et le comptage physique concernent uniquement les espèces. Les soldes Orange Money, Wave et Moov Money restent visibles séparément pour le contrôle des portefeuilles, mais toutes les opérations sont rattachées au registre unique de caisse.</span></div>
      </section>
    </>}

    {mode === 'bank' && <>
      <div className="metric-strip treasury-metrics">
        <div className="metric-mini"><span>Solde bancaire</span><strong>{money(totalBalance)}</strong><small>Soldes d’ouverture et mouvements validés</small></div>
        <div className="metric-mini"><span>Entrées validées</span><strong>{money(totalIn)}</strong><small>Sur les comptes bancaires affichés</small></div>
        <div className="metric-mini"><span>Sorties validées</span><strong>{money(totalOut)}</strong><small>Sur les comptes bancaires affichés</small></div>
      </div>
      <section className="treasury-accounts-section">
        <div className="section-heading treasury-section-heading"><div><h2>Comptes bancaires</h2><p>{pageAccounts.length} compte{pageAccounts.length !== 1 ? 's' : ''} bancaire{pageAccounts.length !== 1 ? 's' : ''} actif{pageAccounts.length !== 1 ? 's' : ''}</p></div></div>
        {pageBalances.length > 0 ? <div className="treasury-account-grid">{pageBalances.map(account => {
          const AccountIcon = Landmark;
          return <section className="panel treasury-account-card" key={account.id}><div className="treasury-account-top"><span className="treasury-account-icon"><AccountIcon size={19}/></span><span className="status-pill status-good"><i/>Banque</span></div><p>{account.name}</p>{account.bank_name && <small className="treasury-account-provider">{account.bank_name}</small>}<strong>{money(Number(account.balance))}</strong><div className="treasury-account-breakdown"><span>Entrées <b>{money(Number(account.total_in))}</b></span><span>Sorties <b>{money(Number(account.total_out))}</b></span></div></section>;
        })}</div> : <section className="panel treasury-empty-accounts"><Landmark size={22}/><strong>Aucun compte bancaire</strong><p>Créez un compte bancaire pour commencer le suivi et le rapprochement.</p>{isAdmin && !isReadOnly && <button className="button button-primary" onClick={() => { setAccountForm(defaultAccountForm('bank')); setShowAccountForm(true); }} disabled={!connected}><Plus size={15}/> Créer un compte bancaire</button>}</section>}
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
          {mode === 'cash-mobile-money' ? <label className="treasury-account-filter"><span className="sr-only">Filtrer par moyen de paiement</span><select value={selectedChannel} onChange={event => setSelectedChannel(event.target.value)}>
            <option value="all">Tous les moyens de paiement</option><option value="especes">Espèces</option><option value="orange_money">Orange Money</option><option value="wave">Wave</option><option value="moov_money">Moov Money</option><option value="mobile_money">Mobile Money non précisé</option>
          </select></label> : <label className="treasury-account-filter"><span className="sr-only">Filtrer par compte</span><select value={selectedAccount} onChange={event => setSelectedAccount(event.target.value)}>
            <option value="all">Tous les comptes</option>
            {(mode === 'bank' ? pageAccounts : accounts).map(account => <option key={account.id} value={account.id}>{account.name}</option>)}
          </select></label>}
          <div className="table-search"><Search size={16}/><input value={query} onChange={event => setQuery(event.target.value)} placeholder={mode === 'cash-mobile-money' ? 'Référence, libellé, moyen de paiement…' : 'Compte, libellé, référence…'}/></div>
        </div>
      </div>
      {mode === 'transfers' ? <div className="table-scroll"><table><thead><tr><th>Date</th><th>Compte source</th><th>Compte destinataire</th><th>Référence</th><th>Libellé</th><th>Montant transféré</th><th>Statut</th></tr></thead><tbody>
        {transferRecords.map(transfer => <tr key={transfer.id}><td>{dateLabel(transfer.date)}</td><td>{transfer.source}</td><td>{transfer.destination}</td><td><span className="record-id">{transfer.reference || '—'}</span></td><td>{transfer.description}</td><td><strong>{money(transfer.amount)}</strong></td><td><span className={`status-pill ${transfer.status === 'validated' ? 'status-good' : 'status-info'}`}><i/>{transfer.status === 'validated' ? 'Validé' : 'En attente'}</span></td></tr>)}
        {!transferRecords.length && <tr><td colSpan={7} className="empty-cell">{loading ? 'Chargement des transferts…' : 'Aucun transfert trouvé.'}</td></tr>}
      </tbody></table></div> : mode === 'cash-mobile-money' ? <div className="table-scroll"><table className="cash-movement-table"><thead><tr><th>Référence</th><th>Date</th><th>Libellé</th><th>Moyen de paiement</th><th>Entrée</th><th>Sortie</th><th>Solde</th><th>Statut</th><th>Actions</th></tr></thead><tbody>
        {filtered.map(transaction => {
          const canManageManual = transaction.account_id === cashRegisterStatus?.account_id && transaction.transaction_type === 'adjustment' && !transaction.payment_id && !transaction.expense_id && !transaction.transfer_group_id && !transaction.reverses_transaction_id;
          return <tr key={transaction.id}>
            <td><span className="record-id">{transaction.reference || '—'}</span></td>
            <td>{dateLabel(transaction.transaction_date)}</td>
            <td><span className="cell-strong">{transaction.description}</span></td>
            <td>{paymentChannelLabel[transaction.payment_channel] || transaction.payment_channel || '—'}</td>
            <td>{transaction.direction === 'in' ? <strong className="money-in">{money(Number(transaction.amount))}</strong> : '—'}</td>
            <td>{transaction.direction === 'out' ? <strong className="money-out">{money(Number(transaction.amount))}</strong> : '—'}</td>
            <td><strong className="cash-running-balance">{money(Number(balanceAfterTransaction.get(transaction.id) ?? 0))}</strong></td>
            <td><span className={`status-pill ${transaction.status === 'validated' ? 'status-good' : transaction.status === 'cancelled' ? 'status-warn' : 'status-info'}`}><i/>{transaction.status === 'validated' ? 'Validé' : transaction.status === 'cancelled' ? 'Annulé' : 'Brouillon'}</span></td>
            <td><div className="row-actions cash-row-actions">{canManageManual && !isReadOnly ? <><button className="button button-secondary" onClick={() => startEditCashMovement(transaction)} title="Modifier cette ligne"><Pencil size={14}/><span>Modifier</span></button><button className="button button-secondary button-danger-outline" onClick={() => void deleteCashMovement(transaction)} disabled={saving} title="Supprimer cette ligne"><Trash2 size={14}/><span>Supprimer</span></button></> : <small className="cash-row-locked">{transaction.payment_id ? 'Géré dans les encaissements' : transaction.expense_id ? 'Géré dans les dépenses' : transaction.transaction_type === 'transfer' ? 'Transfert lié' : 'Opération protégée'}</small>}</div></td>
          </tr>;
        })}
        {!filtered.length && <tr><td colSpan={9} className="empty-cell">{loading ? 'Chargement des mouvements…' : 'Aucun mouvement trouvé. Utilisez « Ajouter une ligne de caisse » pour saisir une opération diverse.'}</td></tr>}
      </tbody></table></div> : <div className="table-scroll"><table><thead><tr><th>Date</th><th>Compte</th><th>Nature</th><th>Référence</th><th>Libellé</th><th>Entrée</th><th>Sortie</th><th>Statut</th></tr></thead><tbody>
        {filtered.map(transaction => <tr key={transaction.id}><td>{dateLabel(transaction.transaction_date)}</td><td><div className="treasury-tx-account">{transaction.accounts_label}<small>{kindLabel[transaction.account_kind] || transaction.account_kind}</small></div></td><td>{typeLabel[transaction.transaction_type] || transaction.transaction_type}</td><td><span className="record-id">{transaction.reference || '—'}</span></td><td>{transaction.description}</td><td>{transaction.direction === 'in' ? <strong className="money-in">{money(Number(transaction.amount))}</strong> : '—'}</td><td>{transaction.direction === 'out' ? <strong className="money-out">{money(Number(transaction.amount))}</strong> : '—'}</td><td><span className={`status-pill ${transaction.status === 'validated' ? 'status-good' : transaction.status === 'cancelled' ? 'status-warn' : 'status-info'}`}><i/>{transaction.status === 'validated' ? 'Validé' : transaction.status === 'cancelled' ? 'Annulé' : 'Brouillon'}</span></td></tr>)}
        {!filtered.length && <tr><td colSpan={8} className="empty-cell">{loading ? 'Chargement des mouvements…' : 'Aucun mouvement trouvé pour ces critères.'}</td></tr>}
      </tbody></table></div>}
      <div className="table-footer treasury-table-footer">
        <span>{mode === 'transfers' ? 'Chaque transfert est présenté une seule fois, avec ses deux comptes liés.' : mode === 'bank' ? 'Le rapprochement des relevés bancaires est disponible plus bas. Le rapprochement ne modifie pas les soldes.' : mode === 'cash-mobile-money' ? 'Les lignes manuelles sont modifiables/supprimables avec un motif. Les reçus et dépenses liés se corrigent dans leur module pour conserver leur traçabilité.' : 'Les transferts internes sont visibles comme une sortie et une entrée liées, mais ne sont pas des recettes ou dépenses.'}</span>
        <button className="button button-secondary" onClick={() => void refresh()} disabled={loading}><RefreshCw size={14}/> Actualiser</button>
      </div>
    </section>

    {mode === 'cash-mobile-money' && showMovementForm && !isReadOnly && <div className="modal-backdrop" onMouseDown={event => { if (event.target === event.currentTarget) { setShowMovementForm(false); setEditingMovementId(null); } }}><section className="modal cash-movement-modal"><div className="modal-header"><div><span className="eyebrow">REGISTRE UNIQUE DE CAISSE</span><h2>{editingMovementId ? 'Modifier une ligne de caisse' : 'Ajouter une ligne de caisse'}</h2></div><button className="icon-button" onClick={() => { setShowMovementForm(false); setEditingMovementId(null); }} aria-label="Fermer"><X size={18}/></button></div><div className="modal-body">
      <div className="inline-notice payment-form-note"><CircleAlert size={16}/><span>Utilisez cette saisie pour un mouvement divers qui n’est pas déjà enregistré dans Encaissements ou Dépenses. Les mouvements sont validés immédiatement et le solde du moyen de paiement est contrôlé.</span></div>
      <label className="form-field"><span>Sens du mouvement *</span><select value={movementForm.direction} onChange={event => setMovementForm({ ...movementForm, direction: event.target.value as 'in' | 'out' })}><option value="in">Entrée d’argent</option><option value="out">Sortie d’argent</option></select></label>
      <label className="form-field"><span>Moyen de paiement *</span><select value={movementForm.payment_channel} onChange={event => setMovementForm({ ...movementForm, payment_channel: event.target.value })}><option value="especes">Espèces</option><option value="orange_money">Orange Money</option><option value="wave">Wave</option><option value="moov_money">Moov Money</option></select></label>
      <label className="form-field"><span>Montant (FCFA) *</span><input type="number" min="1" step="1" value={movementForm.amount} onChange={event => setMovementForm({ ...movementForm, amount: event.target.value })} placeholder="Ex. 15000"/></label>
      <label className="form-field"><span>Date *</span><input type="date" max={new Date().toISOString().slice(0,10)} value={movementForm.date} onChange={event => setMovementForm({ ...movementForm, date: event.target.value })}/></label>
      <label className="form-field"><span>Référence</span><input value={movementForm.reference} onChange={event => setMovementForm({ ...movementForm, reference: event.target.value })} placeholder="N° reçu, pièce ou référence"/></label>
      <label className="form-field"><span>Libellé *</span><input value={movementForm.description} onChange={event => setMovementForm({ ...movementForm, description: event.target.value })} placeholder="Expliquez l’objet du mouvement"/></label>
      {editingMovementId && <label className="form-field"><span>Motif de modification *</span><textarea rows={2} value={movementForm.reason} onChange={event => setMovementForm({ ...movementForm, reason: event.target.value })} placeholder="Pourquoi cette ligne doit-elle être modifiée ?"/></label>}
    </div><div className="modal-footer"><button className="button button-secondary" onClick={() => { setShowMovementForm(false); setEditingMovementId(null); }}>Annuler</button><button className="button button-primary" onClick={() => void saveCashMovement()} disabled={saving || !connected}>{saving ? 'Enregistrement…' : editingMovementId ? 'Enregistrer les modifications' : 'Ajouter à la caisse'}</button></div></section></div>}

    {mode === 'cash-mobile-money' && showCashCountForm && !isReadOnly && <div className="modal-backdrop" onMouseDown={event => { if (event.target === event.currentTarget) setShowCashCountForm(false); }}><section className="modal cash-count-modal"><div className="modal-header"><div><span className="eyebrow">CONTRÔLE PHYSIQUE</span><h2>Comptage réel de la caisse</h2></div><button className="icon-button" onClick={() => setShowCashCountForm(false)} aria-label="Fermer"><X size={18}/></button></div><div className="modal-body"><div className="inline-notice payment-form-note"><ClipboardCheck size={16}/><span>Comptez uniquement les espèces réellement présentes dans le tiroir ou la caisse physique. Orange Money, Wave et Moov Money sont suivis séparément.</span></div><label className="form-field"><span>Montant physique réellement présent (espèces, FCFA) *</span><input type="number" min="0" step="1" value={physicalCountForm.amount} onChange={event => setPhysicalCountForm({ ...physicalCountForm, amount: event.target.value })} placeholder="Ex. 125000"/></label><label className="form-field"><span>Observation</span><textarea rows={3} value={physicalCountForm.note} onChange={event => setPhysicalCountForm({ ...physicalCountForm, note: event.target.value })} placeholder="Facultatif : personne présente, explication d’un écart…"/></label><p className="form-footnote">Le comptage n’ajoute ni n’enlève d’argent. Il enregistre le montant physique observé et calcule l’écart avec le solde théorique au même moment.</p></div><div className="modal-footer"><button className="button button-secondary" onClick={() => setShowCashCountForm(false)}>Annuler</button><button className="button button-primary" onClick={() => void recordCashCount()} disabled={saving || !connected}>{saving ? 'Enregistrement…' : 'Enregistrer le comptage'}</button></div></section></div>}

    {mode === 'transfers' && showTransfer && !isReadOnly && <div className="modal-backdrop" onMouseDown={event => { if (event.target === event.currentTarget) setShowTransfer(false); }}><section className="modal"><div className="modal-header"><div><span className="eyebrow">MOUVEMENT INTERNE</span><h2>Transférer entre comptes</h2></div><button className="icon-button" onClick={() => setShowTransfer(false)} aria-label="Fermer"><X size={18}/></button></div><div className="modal-body"><div className="inline-notice payment-form-note"><ArrowLeftRight size={16}/><span>Le transfert crée deux mouvements liés, sans modifier les recettes ni les dépenses de l’établissement. Le solde du compte source est contrôlé par la base.</span></div><label className="form-field"><span>Compte source *</span><select value={form.source} onChange={event => setForm({ ...form, source: event.target.value, destination: form.destination === event.target.value ? '' : form.destination })}>{accounts.map(account => <option key={account.id} value={account.id}>{account.name}</option>)}</select></label><label className="form-field"><span>Compte destinataire *</span><select value={form.destination} onChange={event => setForm({ ...form, destination: event.target.value })}><option value="">Choisir un compte</option>{accounts.filter(account => account.id !== form.source).map(account => <option key={account.id} value={account.id}>{account.name}</option>)}</select></label><label className="form-field"><span>Montant (FCFA) *</span><input type="number" min="1" step="1" value={form.amount} onChange={event => setForm({ ...form, amount: event.target.value })} placeholder="Ex. 100000"/></label><label className="form-field"><span>Date *</span><input type="date" max={new Date().toISOString().slice(0, 10)} value={form.date} onChange={event => setForm({ ...form, date: event.target.value })}/></label><label className="form-field"><span>Référence</span><input value={form.reference} onChange={event => setForm({ ...form, reference: event.target.value })} placeholder="N° bordereau ou référence"/></label><label className="form-field"><span>Libellé du transfert *</span><input value={form.description} onChange={event => setForm({ ...form, description: event.target.value })} placeholder="Ex. Versement de caisse en banque"/></label></div><div className="modal-footer"><button className="button button-secondary" onClick={() => setShowTransfer(false)}>Annuler</button><button className="button button-primary" onClick={() => void transfer()} disabled={saving || !connected}>{saving ? 'Enregistrement…' : 'Valider le transfert'}</button></div></section></div>}

    {showAccountForm && isAdmin && !isReadOnly && mode === 'bank' && <div className="modal-backdrop" onMouseDown={event => { if (event.target === event.currentTarget) setShowAccountForm(false); }}><section className="modal"><div className="modal-header"><div><span className="eyebrow">PARAMÉTRAGE DE TRÉSORERIE</span><h2>Nouveau compte financier</h2></div><button className="icon-button" onClick={() => setShowAccountForm(false)} aria-label="Fermer"><X size={18}/></button></div><div className="modal-body treasury-account-form-body"><label className="form-field"><span>Nom du compte *</span><input value={accountForm.name} maxLength={100} onChange={event => setAccountForm(current => ({ ...current, name: event.target.value, code: current.code || event.target.value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 20) }))} placeholder="Ex. Caisse principale"/></label><label className="form-field"><span>Code unique *</span><input value={accountForm.code} maxLength={30} onChange={event => setAccountForm(current => ({ ...current, code: event.target.value.toUpperCase().replace(/[^A-Z0-9_-]/g, '') }))} placeholder="Ex. CAISSE_2"/></label>{mode === 'cash-mobile-money' && <label className="form-field"><span>Type de compte *</span><select value={accountForm.kind} onChange={event => setAccountForm(current => ({ ...current, kind: event.target.value as AccountKind }))}><option value="cash">Caisse physique</option><option value="mobile_money">Portefeuille Mobile Money</option></select></label>}{accountForm.kind === 'bank' && <label className="form-field"><span>Nom de la banque</span><input value={accountForm.bank_name} maxLength={100} onChange={event => setAccountForm(current => ({ ...current, bank_name: event.target.value }))} placeholder="Ex. Banque partenaire"/></label>}{accountForm.kind === 'mobile_money' && <label className="form-field"><span>Opérateur Mobile Money *</span><input value={accountForm.provider_name} maxLength={100} onChange={event => setAccountForm(current => ({ ...current, provider_name: event.target.value }))} placeholder="Ex. Orange Money, MTN MoMo…"/></label>}<label className="form-field"><span>Solde initial (FCFA) *</span><input type="number" min="0" step="1" value={accountForm.opening_balance} onChange={event => setAccountForm(current => ({ ...current, opening_balance: event.target.value }))}/></label><label className="form-field"><span>Date d’ouverture *</span><input type="date" value={accountForm.opening_date} onChange={event => setAccountForm(current => ({ ...current, opening_date: event.target.value }))}/><small>Le solde initial est disponible à partir de cette date.</small></label></div><div className="modal-footer"><button className="button button-secondary" onClick={() => setShowAccountForm(false)}>Annuler</button><button className="button button-primary" onClick={() => void createAccount()} disabled={saving || !connected}>{saving ? 'Création…' : 'Créer le compte'}</button></div></section></div>}
  </>;
}
