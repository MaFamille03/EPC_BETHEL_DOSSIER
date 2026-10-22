-- 002_financial_workflows_epc_bethel.sql
-- Fonctions transactionnelles de référence. Tester en environnement Supabase isolé.
-- Les fonctions sont SECURITY DEFINER et doivent être revues avant production.

create or replace function public.allocate_receipt_number(p_paid_at timestamptz default now())
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year integer;
  v_next bigint;
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then
    raise exception 'Accès refusé pour numéroter un reçu';
  end if;

  v_year := extract(year from p_paid_at)::integer;
  insert into public.receipt_sequences(sequence_year, last_value)
  values (v_year, 0)
  on conflict (sequence_year) do nothing;

  update public.receipt_sequences
     set last_value = last_value + 1,
         updated_at = now()
   where sequence_year = v_year
   returning last_value into v_next;

  return 'REC-' || v_year::text || '-' || lpad(v_next::text, 6, '0');
end $$;

create or replace function public.validate_payment(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment public.payments%rowtype;
  v_allocated bigint;
  v_account_kind public.account_kind;
  v_charge record;
  v_charge_paid bigint;
  v_installment_paid bigint;
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then
    raise exception 'Accès refusé';
  end if;

  select * into v_payment
    from public.payments
   where id = p_payment_id
   for update;

  if not found then raise exception 'Paiement introuvable'; end if;
  if v_payment.status <> 'draft' then raise exception 'Le paiement doit être en brouillon'; end if;

  select kind into v_account_kind
    from public.cash_accounts
   where id = v_payment.account_id and is_active = true
   for update;
  if not found then raise exception 'Compte de trésorerie inactif ou introuvable'; end if;

  select coalesce(sum(amount),0)::bigint into v_allocated
    from public.payment_allocations
   where payment_id = p_payment_id;

  if v_allocated <> v_payment.amount then
    raise exception 'La somme des affectations (%) doit égaler le paiement (%)', v_allocated, v_payment.amount;
  end if;

  -- Verrouillage des charges dans un ordre stable pour limiter les interblocages.
  for v_charge in
    select c.id, c.amount_due
      from public.student_charges c
     where exists (
       select 1 from public.payment_allocations pa
        where pa.charge_id = c.id and pa.payment_id = p_payment_id
     )
     order by c.id
     for update of c
  loop
    select coalesce(sum(pa.amount),0)::bigint into v_charge_paid
      from public.payment_allocations pa
      join public.payments p on p.id = pa.payment_id
     where pa.charge_id = v_charge.id
       and p.status = 'validated';

    select coalesce(sum(pa.amount),0)::bigint into v_allocated
      from public.payment_allocations pa
     where pa.payment_id = p_payment_id
       and pa.charge_id = v_charge.id;

    if v_charge_paid + v_allocated > v_charge.amount_due then
      raise exception 'Affectation supérieure au solde de la charge %', v_charge.id;
    end if;
  end loop;

  -- Vérification facultative mais stricte des plafonds d'échéance.
  for v_charge in
    select i.id, i.amount_due
      from public.installments i
      join public.payment_allocations pa on pa.installment_id = i.id
     where pa.payment_id = p_payment_id
     order by i.id
     for update of i
  loop
    select coalesce(sum(pa.amount),0)::bigint into v_installment_paid
      from public.payment_allocations pa
      join public.payments p on p.id = pa.payment_id
     where pa.installment_id = v_charge.id
       and p.status = 'validated';

    select coalesce(sum(pa.amount),0)::bigint into v_allocated
      from public.payment_allocations pa
     where pa.payment_id = p_payment_id
       and pa.installment_id = v_charge.id;

    if v_installment_paid + v_allocated > v_charge.amount_due then
      raise exception 'Affectation supérieure au solde de l’échéance %', v_charge.id;
    end if;
  end loop;

  update public.payments
     set status = 'validated',
         validated_at = now(),
         validated_by = (select auth.uid())
   where id = p_payment_id;

  insert into public.cash_transactions(
    account_id, transaction_date, direction, amount, transaction_type,
    payment_id, reference, description, status, created_by, validated_at, validated_by
  ) values (
    v_payment.account_id, v_payment.paid_at, 'in', v_payment.amount, 'payment',
    v_payment.id, v_payment.receipt_number, 'Encaissement ' || v_payment.receipt_number,
    'validated', (select auth.uid()), now(), (select auth.uid())
  );

  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values ((select auth.uid()), 'validate_payment', 'payments', p_payment_id::text,
          jsonb_build_object('amount', v_payment.amount, 'receipt_number', v_payment.receipt_number));
end $$;

create or replace function public.cancel_payment(p_payment_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment public.payments%rowtype;
  v_tx public.cash_transactions%rowtype;
begin
  if not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Annulation réservée à la direction ou à l’administrateur';
  end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'Motif d’annulation obligatoire'; end if;

  select * into v_payment from public.payments where id = p_payment_id for update;
  if not found then raise exception 'Paiement introuvable'; end if;
  if v_payment.status <> 'validated' then raise exception 'Seul un paiement validé peut être annulé'; end if;

  select * into v_tx from public.cash_transactions
   where payment_id = p_payment_id and transaction_type = 'payment' and status = 'validated'
   for update;
  if not found then raise exception 'Mouvement de trésorerie d’origine introuvable'; end if;

  insert into public.cash_transactions(
    account_id, transaction_date, direction, amount, transaction_type,
    reverses_transaction_id, reference, description, status, created_by, validated_at, validated_by
  ) values (
    v_tx.account_id, now(),
    case when v_tx.direction = 'in' then 'out' else 'in' end,
    v_tx.amount, 'reversal', v_tx.id, v_payment.receipt_number,
    'Annulation du reçu ' || v_payment.receipt_number || ' : ' || trim(p_reason),
    'validated', (select auth.uid()), now(), (select auth.uid())
  );

  update public.payments
     set status = 'cancelled', cancelled_at = now(),
         cancelled_by = (select auth.uid()), cancellation_reason = trim(p_reason)
   where id = p_payment_id;

  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values ((select auth.uid()), 'cancel_payment', 'payments', p_payment_id::text,
          jsonb_build_object('reason', trim(p_reason), 'amount', v_payment.amount,
                             'receipt_number', v_payment.receipt_number));
end $$;

create or replace function public.validate_expense(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense public.expenses%rowtype;
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then
    raise exception 'Accès refusé';
  end if;

  select * into v_expense from public.expenses where id = p_expense_id for update;
  if not found then raise exception 'Dépense introuvable'; end if;
  if v_expense.status <> 'draft' then raise exception 'La dépense doit être en brouillon'; end if;

  perform 1 from public.cash_accounts
   where id = v_expense.account_id and is_active = true for update;
  if not found then raise exception 'Compte de trésorerie inactif ou introuvable'; end if;

  update public.expenses set status = 'validated', validated_at = now(),
    validated_by = (select auth.uid()) where id = p_expense_id;

  insert into public.cash_transactions(
    account_id, transaction_date, direction, amount, transaction_type,
    expense_id, reference, description, status, created_by, validated_at, validated_by
  ) values (
    v_expense.account_id, (v_expense.expense_date::timestamp at time zone 'UTC'),
    'out', v_expense.amount, 'expense', v_expense.id, v_expense.expense_number,
    v_expense.description, 'validated', (select auth.uid()), now(), (select auth.uid())
  );

  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values ((select auth.uid()), 'validate_expense', 'expenses', p_expense_id::text,
          jsonb_build_object('amount', v_expense.amount, 'expense_number', v_expense.expense_number));
end $$;

create or replace function public.transfer_between_accounts(
  p_source_account_id uuid,
  p_destination_account_id uuid,
  p_amount bigint,
  p_transfer_date timestamptz,
  p_reference text,
  p_description text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid := gen_random_uuid();
  v_uid uuid := (select auth.uid());
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then
    raise exception 'Accès refusé';
  end if;
  if p_source_account_id = p_destination_account_id then
    raise exception 'Les comptes source et destination doivent être différents';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Montant invalide'; end if;
  if coalesce(trim(p_description),'') = '' then raise exception 'Libellé obligatoire'; end if;

  perform 1 from public.cash_accounts
   where id in (p_source_account_id, p_destination_account_id) and is_active = true
   order by id for update;
  if (select count(*) from public.cash_accounts
       where id in (p_source_account_id, p_destination_account_id) and is_active = true) <> 2 then
    raise exception 'Un compte est inactif ou introuvable';
  end if;

  insert into public.cash_transactions(
    account_id, transaction_date, direction, amount, transaction_type,
    transfer_group_id, reference, description, status, created_by, validated_at, validated_by
  ) values
  (p_source_account_id, coalesce(p_transfer_date,now()), 'out', p_amount, 'transfer',
   v_group, p_reference, 'Transfert sortant : ' || p_description, 'validated', v_uid, now(), v_uid),
  (p_destination_account_id, coalesce(p_transfer_date,now()), 'in', p_amount, 'transfer',
   v_group, p_reference, 'Transfert entrant : ' || p_description, 'validated', v_uid, now(), v_uid);

  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values (v_uid, 'transfer_between_accounts', 'cash_transactions', v_group::text,
          jsonb_build_object('source_account_id', p_source_account_id,
                             'destination_account_id', p_destination_account_id,
                             'amount', p_amount, 'reference', p_reference));
  return v_group;
end $$;

revoke all on function public.allocate_receipt_number(timestamptz) from public, anon;
revoke all on function public.validate_payment(uuid) from public, anon;
revoke all on function public.cancel_payment(uuid,text) from public, anon;
revoke all on function public.validate_expense(uuid) from public, anon;
revoke all on function public.transfer_between_accounts(uuid,uuid,bigint,timestamptz,text,text) from public, anon;

grant execute on function public.allocate_receipt_number(timestamptz) to authenticated;
grant execute on function public.validate_payment(uuid) to authenticated;
grant execute on function public.cancel_payment(uuid,text) to authenticated;
grant execute on function public.validate_expense(uuid) to authenticated;
grant execute on function public.transfer_between_accounts(uuid,uuid,bigint,timestamptz,text,text) to authenticated;

-- Avant production :
-- * remplacer les INSERT directs sur payments/allocations/expenses par des RPC serveur
--   qui créent les brouillons et les allocations dans une transaction ;
-- * vérifier que les rôles ne peuvent pas contourner les workflows par une mutation API ;
-- * tester le cas où une charge est allouée à plusieurs échéances ;
-- * ajouter le workflow de validation/annulation des dépenses et les contraintes de transfert ;
-- * auditer les politiques RLS avec des tests sous chaque rôle et sous anon.
