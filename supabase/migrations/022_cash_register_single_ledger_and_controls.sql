-- EPC BETHEL — Caisse unique, moyens de paiement, comptage physique et opérations manuelles traçables.
-- À appliquer après la migration 021 en préproduction avant la production.

begin;

-- Le compte Caisse reste unique dans l'interface. Les méthodes de paiement sont distinctes des comptes.
alter table public.payments
  add column if not exists mobile_money_provider text;
alter table public.expenses
  add column if not exists mobile_money_provider text;

alter table public.payments drop constraint if exists payments_mobile_money_provider_check;
alter table public.payments add constraint payments_mobile_money_provider_check
  check (mobile_money_provider is null or mobile_money_provider in ('orange_money','wave','moov_money'));
alter table public.expenses drop constraint if exists expenses_mobile_money_provider_check;
alter table public.expenses add constraint expenses_mobile_money_provider_check
  check (mobile_money_provider is null or mobile_money_provider in ('orange_money','wave','moov_money'));

alter table public.cash_transactions
  add column if not exists payment_channel text not null default 'especes';
alter table public.cash_transactions drop constraint if exists cash_transactions_payment_channel_check;
alter table public.cash_transactions add constraint cash_transactions_payment_channel_check
  check (payment_channel in ('especes','orange_money','wave','moov_money','mobile_money','virement','cheque','autre'));

-- Reprendre le fournisseur enregistré sur les anciens portefeuilles lorsque c'est possible.
update public.payments p
set mobile_money_provider = case
  when lower(coalesce(a.provider_name,'')) like '%orange%' then 'orange_money'
  when lower(coalesce(a.provider_name,'')) like '%wave%' then 'wave'
  when lower(coalesce(a.provider_name,'')) like '%moov%' then 'moov_money'
  else null end
from public.cash_accounts a
where p.account_id=a.id and p.method::text='mobile_money' and p.mobile_money_provider is null;

update public.expenses e
set mobile_money_provider = case
  when lower(coalesce(a.provider_name,'')) like '%orange%' then 'orange_money'
  when lower(coalesce(a.provider_name,'')) like '%wave%' then 'wave'
  when lower(coalesce(a.provider_name,'')) like '%moov%' then 'moov_money'
  else null end
from public.cash_accounts a
where e.account_id=a.id and e.payment_method::text='mobile_money' and e.mobile_money_provider is null;

create or replace function public.set_cash_transaction_payment_channel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_method text;
  v_provider text;
  v_kind text;
begin
  if new.payment_id is not null then
    select p.method::text, p.mobile_money_provider, a.provider_name
      into v_method, v_provider, v_kind
    from public.payments p
    left join public.cash_accounts a on a.id=p.account_id
    where p.id=new.payment_id;
    if v_method='mobile_money' then
      new.payment_channel := coalesce(v_provider,
        case when lower(coalesce(v_kind,'')) like '%orange%' then 'orange_money'
             when lower(coalesce(v_kind,'')) like '%wave%' then 'wave'
             when lower(coalesce(v_kind,'')) like '%moov%' then 'moov_money'
             else 'mobile_money' end);
    else
      new.payment_channel := coalesce(v_method,'autre');
    end if;
  elsif new.expense_id is not null then
    select e.payment_method::text, e.mobile_money_provider, a.provider_name
      into v_method, v_provider, v_kind
    from public.expenses e
    left join public.cash_accounts a on a.id=e.account_id
    where e.id=new.expense_id;
    if v_method='mobile_money' then
      new.payment_channel := coalesce(v_provider,
        case when lower(coalesce(v_kind,'')) like '%orange%' then 'orange_money'
             when lower(coalesce(v_kind,'')) like '%wave%' then 'wave'
             when lower(coalesce(v_kind,'')) like '%moov%' then 'moov_money'
             else 'mobile_money' end);
    else
      new.payment_channel := coalesce(v_method,'autre');
    end if;
  elsif new.transaction_type='reversal' and new.reverses_transaction_id is not null then
    select t.payment_channel into new.payment_channel
    from public.cash_transactions t where t.id=new.reverses_transaction_id;
    new.payment_channel := coalesce(new.payment_channel,'autre');
  elsif new.transaction_type='transfer' then
    select a.kind::text into v_kind from public.cash_accounts a where a.id=new.account_id;
    new.payment_channel := case when v_kind='cash' and new.payment_channel in ('especes','orange_money','wave','moov_money') then new.payment_channel when v_kind='cash' then 'especes' when v_kind='bank' then 'virement' else coalesce(new.payment_channel,'autre') end;
  else
    new.payment_channel := coalesce(nullif(new.payment_channel,''),'especes');
  end if;
  return new;
end;
$$;
revoke all on function public.set_cash_transaction_payment_channel() from public, anon, authenticated;

drop trigger if exists cash_transaction_method_sync on public.cash_transactions;
create trigger cash_transaction_method_sync
before insert or update of payment_id, expense_id, transaction_type, reverses_transaction_id, account_id, direction, payment_channel
on public.cash_transactions
for each row execute function public.set_cash_transaction_payment_channel();

-- Recalculer la colonne historique sur les opérations existantes, en plusieurs passes pour les contrepassations.
update public.cash_transactions t set payment_channel = t.payment_channel where t.payment_id is not null or t.expense_id is not null;
update public.cash_transactions t set payment_channel = case
  when a.kind::text='cash' then 'especes'
  when a.kind::text='bank' then 'virement'
  else coalesce(t.payment_channel,'autre') end
from public.cash_accounts a
where a.id=t.account_id and t.transaction_type='transfer';
update public.cash_transactions t set payment_channel='especes'
where t.transaction_type in ('adjustment','opening') and (t.payment_channel is null or t.payment_channel='autre');
update public.cash_transactions t set payment_channel=coalesce(orig.payment_channel,'autre')
from public.cash_transactions orig
where t.transaction_type='reversal' and t.reverses_transaction_id=orig.id;

-- Un paiement Mobile Money peut être enregistré dans la caisse principale : ce n'est pas un compte distinct.
create or replace function public.check_treasury_account_method_match()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_method text;
  v_account_id uuid;
  v_account_kind text;
  v_main_cash_id uuid;
begin
  if tg_table_name='payments' then
    v_method := new.method::text;
    v_account_id := new.account_id;
  elsif tg_table_name='expenses' then
    v_method := new.payment_method::text;
    v_account_id := new.account_id;
  else
    raise exception 'Table non prise en charge par le contrôle de compte.';
  end if;
  select a.kind::text into v_account_kind from public.cash_accounts a where a.id=v_account_id and a.is_active=true;
  if not found then raise exception 'Le compte choisi est inactif ou introuvable.'; end if;
  if v_method in ('especes','mobile_money') then
    if v_account_kind<>'cash' then
      raise exception 'Pour les espèces ou Mobile Money, choisissez la caisse principale. L’opérateur est un moyen de paiement, pas un compte séparé.';
    end if;
    select a.id into v_main_cash_id from public.cash_accounts a
      where a.is_active and a.kind::text='cash'
      order by (a.code='CAISSE') desc,a.created_at,a.id limit 1;
    if v_main_cash_id is not null and v_account_id<>v_main_cash_id then
      raise exception 'Utilisez le compte unique Caisse principale pour les espèces et Mobile Money.';
    end if;
  elsif v_method in ('virement','cheque') and v_account_kind<>'bank' then
    raise exception 'Pour un virement ou un chèque, choisissez un compte bancaire.';
  end if;
  return new;
end;
$$;
revoke all on function public.check_treasury_account_method_match() from public, anon, authenticated;
drop trigger if exists payments_account_method_match on public.payments;
create trigger payments_account_method_match before insert or update of method,account_id on public.payments
for each row execute function public.check_treasury_account_method_match();
drop trigger if exists expenses_account_method_match on public.expenses;
create trigger expenses_account_method_match before insert or update of payment_method,account_id on public.expenses
for each row execute function public.check_treasury_account_method_match();

-- Répercuter un fournisseur précisé après l'émission du reçu par le workflow transactionnel existant.
create or replace function public.sync_provider_to_cash_transaction()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.cash_transactions t set payment_channel=case
    when new.method::text<>'mobile_money' then new.method::text
    else coalesce(new.mobile_money_provider, case
      when lower(coalesce(a.provider_name,'')) like '%orange%' then 'orange_money'
      when lower(coalesce(a.provider_name,'')) like '%wave%' then 'wave'
      when lower(coalesce(a.provider_name,'')) like '%moov%' then 'moov_money'
      else 'mobile_money' end) end
  from public.cash_accounts a
  where t.payment_id=new.id and a.id=new.account_id;
  return new;
end $$;
revoke all on function public.sync_provider_to_cash_transaction() from public,anon,authenticated;
drop trigger if exists payments_provider_to_cash_transaction on public.payments;
create trigger payments_provider_to_cash_transaction after update of mobile_money_provider on public.payments
for each row when (old.mobile_money_provider is distinct from new.mobile_money_provider)
execute function public.sync_provider_to_cash_transaction();

create or replace function public.sync_expense_provider_to_cash_transaction()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.cash_transactions t set payment_channel=case
    when new.payment_method::text<>'mobile_money' then new.payment_method::text
    else coalesce(new.mobile_money_provider, case
      when lower(coalesce(a.provider_name,'')) like '%orange%' then 'orange_money'
      when lower(coalesce(a.provider_name,'')) like '%wave%' then 'wave'
      when lower(coalesce(a.provider_name,'')) like '%moov%' then 'moov_money'
      else 'mobile_money' end) end
  from public.cash_accounts a
  where t.expense_id=new.id and a.id=new.account_id;
  return new;
end $$;
revoke all on function public.sync_expense_provider_to_cash_transaction() from public,anon,authenticated;
drop trigger if exists expenses_provider_to_cash_transaction on public.expenses;
create trigger expenses_provider_to_cash_transaction after update of mobile_money_provider on public.expenses
for each row when (old.mobile_money_provider is distinct from new.mobile_money_provider)
execute function public.sync_expense_provider_to_cash_transaction();

-- Compatibilité avec les formulaires existants : le wrapper appelle le workflow de paiement testé,
-- puis ajoute le fournisseur dans la même transaction.
create or replace function public.register_student_payment_with_provider(
  p_enrollment_id uuid,
  p_amount bigint,
  p_method public.payment_method,
  p_account_id uuid,
  p_paid_at timestamptz default now(),
  p_payer_name text default null,
  p_external_reference text default null,
  p_notes text default null,
  p_mobile_money_provider text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb; v_payment_id uuid;
begin
  if p_method::text='mobile_money' and coalesce(p_mobile_money_provider,'') not in ('orange_money','wave','moov_money') then
    raise exception 'Sélectionnez Orange Money, Wave ou Moov Money.';
  end if;
  if p_method::text<>'mobile_money' and p_mobile_money_provider is not null then
    raise exception 'Le fournisseur Mobile Money ne peut être défini que pour un paiement Mobile Money.';
  end if;
  v_result := public.register_student_payment(p_enrollment_id,p_amount,p_method,p_account_id,p_paid_at,p_payer_name,p_external_reference,p_notes);
  v_payment_id := nullif(v_result->>'id','')::uuid;
  if v_payment_id is not null and p_mobile_money_provider is not null then
    update public.payments set mobile_money_provider=p_mobile_money_provider where id=v_payment_id;
  end if;
  return v_result;
end $$;
revoke all on function public.register_student_payment_with_provider(uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text,text) from public,anon;
grant execute on function public.register_student_payment_with_provider(uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text,text) to authenticated;

create or replace function public.create_expense_with_provider(
  p_expense_date date,
  p_category_id uuid,
  p_beneficiary text,
  p_description text,
  p_amount bigint,
  p_account_id uuid,
  p_payment_method public.payment_method,
  p_external_reference text default null,
  p_document_path text default null,
  p_mobile_money_provider text default null
) returns public.expenses language plpgsql security definer set search_path = '' as $$
declare v_expense public.expenses%rowtype;
begin
  if p_payment_method::text='mobile_money' and coalesce(p_mobile_money_provider,'') not in ('orange_money','wave','moov_money') then
    raise exception 'Sélectionnez Orange Money, Wave ou Moov Money.';
  end if;
  if p_payment_method::text<>'mobile_money' and p_mobile_money_provider is not null then
    raise exception 'Le fournisseur Mobile Money ne peut être défini que pour un paiement Mobile Money.';
  end if;
  v_expense := public.create_expense(p_expense_date,p_category_id,p_beneficiary,p_description,p_amount,p_account_id,p_payment_method,p_external_reference,p_document_path);
  if p_mobile_money_provider is not null then
    update public.expenses set mobile_money_provider=p_mobile_money_provider where id=v_expense.id returning * into v_expense;
  end if;
  return v_expense;
end $$;
revoke all on function public.create_expense_with_provider(date,uuid,text,text,bigint,uuid,public.payment_method,text,text,text) from public,anon;
grant execute on function public.create_expense_with_provider(date,uuid,text,text,bigint,uuid,public.payment_method,text,text,text) to authenticated;

create table if not exists public.cash_register_counts (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.cash_accounts(id) on delete restrict,
  counted_amount bigint not null check (counted_amount>=0),
  counted_at timestamptz not null default now(),
  note text,
  created_by uuid references public.profiles(id) on delete restrict
);
create index if not exists cash_register_counts_account_date_idx on public.cash_register_counts(account_id,counted_at desc);
alter table public.cash_register_counts enable row level security;
drop policy if exists cash_register_counts_read on public.cash_register_counts;
create policy cash_register_counts_read on public.cash_register_counts for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite','observateur']::public.app_role[]));
grant select on public.cash_register_counts to authenticated;
revoke insert,update,delete on public.cash_register_counts from public,anon,authenticated;

create or replace function public.cash_method_balance(p_channel text,p_at timestamptz default now(),p_exclude_transaction_id uuid default null)
returns bigint language sql stable security definer set search_path = '' as $$
  select
    coalesce((select sum(a.opening_balance)::bigint from public.cash_accounts a
      where a.is_active and a.opening_date <= (p_at at time zone 'UTC')::date and (
        (p_channel='especes' and a.kind::text='cash' and a.id=(select ca.id from public.cash_accounts ca where ca.is_active and ca.kind::text='cash' order by (ca.code='CAISSE') desc,ca.created_at,ca.id limit 1)) or
        (p_channel='orange_money' and a.kind::text='mobile_money' and lower(coalesce(a.provider_name,'')) like '%orange%') or
        (p_channel='wave' and a.kind::text='mobile_money' and lower(coalesce(a.provider_name,'')) like '%wave%') or
        (p_channel='moov_money' and a.kind::text='mobile_money' and lower(coalesce(a.provider_name,'')) like '%moov%') or
        (p_channel='mobile_money' and a.kind::text='mobile_money' and lower(coalesce(a.provider_name,'')) not like '%orange%' and lower(coalesce(a.provider_name,'')) not like '%wave%' and lower(coalesce(a.provider_name,'')) not like '%moov%')
      )),0)
    + coalesce((select sum(case when t.direction='in' then t.amount else -t.amount end)::bigint
      from public.cash_transactions t join public.cash_accounts a on a.id=t.account_id
      where a.is_active and ((p_channel='especes' and a.id=(select ca.id from public.cash_accounts ca where ca.is_active and ca.kind::text='cash' order by (ca.code='CAISSE') desc,ca.created_at,ca.id limit 1)) or (p_channel<>'especes' and a.kind::text in ('cash','mobile_money'))) and t.status='validated'
        and t.payment_channel=p_channel and t.transaction_date<=p_at
        and (p_exclude_transaction_id is null or t.id<>p_exclude_transaction_id)),0)
$$;
revoke all on function public.cash_method_balance(text,timestamptz,uuid) from public,anon,authenticated;

create or replace function public.get_cash_register_status()
returns table(
  account_id uuid, account_name text, cash_theoretical_balance bigint, cash_physical_balance bigint,
  cash_variance bigint, cash_counted_at timestamptz, cash_count_note text,
  orange_money_balance bigint, wave_balance bigint, moov_money_balance bigint, other_mobile_money_balance bigint
) language plpgsql security definer set search_path = '' as $$
declare
  v_account public.cash_accounts%rowtype;
  v_count public.cash_register_counts%rowtype;
  v_theoretical bigint;
  v_at_count bigint;
begin
  if not public.has_any_role(array['admin','direction','comptabilite','observateur']::public.app_role[]) then raise exception 'Accès refusé à la caisse.' using errcode='42501'; end if;
  select * into v_account from public.cash_accounts a where a.is_active and a.kind::text='cash'
  order by (a.code='CAISSE') desc, a.created_at, a.id limit 1;
  if not found then
    return query select null::uuid, 'Caisse principale'::text, 0::bigint, null::bigint, null::bigint, null::timestamptz, null::text,
      public.cash_method_balance('orange_money',now(),null),public.cash_method_balance('wave',now(),null),public.cash_method_balance('moov_money',now(),null),public.cash_method_balance('mobile_money',now(),null);
    return;
  end if;
  select * into v_count from public.cash_register_counts c where c.account_id=v_account.id order by c.counted_at desc limit 1;
  v_theoretical := (case when v_account.opening_date<=current_date then v_account.opening_balance else 0 end)
    + coalesce((select sum(case when t.direction='in' then t.amount else -t.amount end)::bigint from public.cash_transactions t
      where t.account_id=v_account.id and t.status='validated' and t.payment_channel='especes' and t.transaction_date<=now()),0);
  if v_count.id is not null then
    v_at_count := (case when v_account.opening_date <= (v_count.counted_at at time zone 'UTC')::date then v_account.opening_balance else 0 end)
      + coalesce((select sum(case when t.direction='in' then t.amount else -t.amount end)::bigint from public.cash_transactions t
        where t.account_id=v_account.id and t.status='validated' and t.payment_channel='especes' and t.transaction_date<=v_count.counted_at),0);
  else
    v_at_count := null;
  end if;
  return query select v_account.id, v_account.name, v_theoretical,
    v_count.counted_amount, case when v_count.id is null then null::bigint else v_count.counted_amount-v_at_count end,
    v_count.counted_at, v_count.note,
    public.cash_method_balance('orange_money',now(),null), public.cash_method_balance('wave',now(),null),
    public.cash_method_balance('moov_money',now(),null), public.cash_method_balance('mobile_money',now(),null);
end $$;
revoke all on function public.get_cash_register_status() from public,anon;
grant execute on function public.get_cash_register_status() to authenticated;

create or replace function public.record_cash_register_count(p_counted_amount bigint,p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_account public.cash_accounts%rowtype; v_id uuid; v_uid uuid:=auth.uid();
begin
  if v_uid is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Comptage réservé à l’administration ou à la comptabilité.' using errcode='42501'; end if;
  if p_counted_amount is null or p_counted_amount<0 then raise exception 'Le montant physique doit être positif ou nul.'; end if;
  select * into v_account from public.cash_accounts a where a.is_active and a.kind::text='cash'
    order by (a.code='CAISSE') desc,a.created_at,a.id limit 1 for update;
  if not found then raise exception 'Caisse principale introuvable ou inactive.'; end if;
  insert into public.cash_register_counts(account_id,counted_amount,note,created_by)
  values(v_account.id,p_counted_amount,nullif(trim(coalesce(p_note,'')),''),v_uid) returning id into v_id;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'record_cash_register_count','cash_register_counts',v_id::text,jsonb_build_object('account_id',v_account.id,'counted_amount',p_counted_amount,'note',nullif(trim(coalesce(p_note,'')),'')));
  return v_id;
end $$;
revoke all on function public.record_cash_register_count(bigint,text) from public,anon;
grant execute on function public.record_cash_register_count(bigint,text) to authenticated;

create or replace function public.create_manual_cash_movement(
  p_direction text,p_amount bigint,p_transaction_date date,p_payment_channel text,p_reference text,p_description text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_account public.cash_accounts%rowtype; v_id uuid; v_uid uuid:=auth.uid(); v_at timestamptz;
begin
  if v_uid is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Saisie réservée à l’administration ou à la comptabilité.' using errcode='42501'; end if;
  if p_direction not in ('in','out') then raise exception 'Sens du mouvement invalide.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Le montant doit être un entier positif.'; end if;
  if p_transaction_date is null or p_transaction_date>current_date then raise exception 'La date ne peut pas être vide ou future.'; end if;
  if p_payment_channel not in ('especes','orange_money','wave','moov_money') then raise exception 'Choisissez Espèces, Orange Money, Wave ou Moov Money.'; end if;
  if coalesce(trim(p_description),'')='' then raise exception 'Le libellé est obligatoire.'; end if;
  select * into v_account from public.cash_accounts a where a.is_active and a.kind::text='cash'
    order by (a.code='CAISSE') desc,a.created_at,a.id limit 1 for update;
  if not found then raise exception 'Caisse principale introuvable ou inactive. Contactez l’administrateur.'; end if;
  v_at := ((p_transaction_date+1)::timestamp at time zone 'UTC')-interval '1 microsecond';
  if p_direction='out' and public.cash_method_balance(p_payment_channel,v_at,null)<p_amount then
    raise exception 'Solde insuffisant pour ce moyen de paiement. Disponible : %, demandé : %',public.cash_method_balance(p_payment_channel,v_at,null),p_amount;
  end if;
  insert into public.cash_transactions(account_id,transaction_date,direction,amount,transaction_type,reference,description,status,created_by,validated_at,validated_by,payment_channel)
  values(v_account.id,(p_transaction_date::timestamp at time zone 'UTC')+interval '12 hours',p_direction,p_amount,'adjustment',nullif(trim(coalesce(p_reference,'')),''),trim(p_description),'validated',v_uid,now(),v_uid,p_payment_channel)
  returning id into v_id;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'create_manual_cash_movement','cash_transactions',v_id::text,jsonb_build_object('direction',p_direction,'amount',p_amount,'payment_channel',p_payment_channel,'reference',p_reference,'description',p_description));
  return v_id;
end $$;
revoke all on function public.create_manual_cash_movement(text,bigint,date,text,text,text) from public,anon;
grant execute on function public.create_manual_cash_movement(text,bigint,date,text,text,text) to authenticated;

create or replace function public.update_manual_cash_movement(
  p_transaction_id uuid,p_direction text,p_amount bigint,p_transaction_date date,p_payment_channel text,p_reference text,p_description text,p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_tx public.cash_transactions%rowtype; v_uid uuid:=auth.uid(); v_at timestamptz; v_available bigint;
begin
  if v_uid is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Modification réservée à l’administration ou à la comptabilité.' using errcode='42501'; end if;
  select * into v_tx from public.cash_transactions t where t.id=p_transaction_id for update;
  if not found then raise exception 'Mouvement introuvable.'; end if;
  if v_tx.transaction_type<>'adjustment' or v_tx.payment_id is not null or v_tx.expense_id is not null or v_tx.transfer_group_id is not null or v_tx.reverses_transaction_id is not null then
    raise exception 'Seules les lignes de caisse saisies manuellement peuvent être modifiées ici. Les reçus et dépenses doivent être corrigés dans leur module.';
  end if;
  if exists(select 1 from public.bank_reconciliations r where r.cash_transaction_id=v_tx.id and r.status='matched') then raise exception 'Ce mouvement est rapproché et ne peut plus être modifié.'; end if;
  if p_direction not in ('in','out') or p_amount is null or p_amount<=0 or p_transaction_date is null or p_transaction_date>current_date
    or p_payment_channel not in ('especes','orange_money','wave','moov_money') or coalesce(trim(p_description),'')='' or coalesce(trim(p_reason),'')='' then
    raise exception 'Vérifiez le sens, le montant, la date, le moyen de paiement, le libellé et le motif de modification.';
  end if;
  v_at := ((p_transaction_date+1)::timestamp at time zone 'UTC')-interval '1 microsecond';
  v_available := public.cash_method_balance(p_payment_channel,v_at,v_tx.id);
  if p_direction='out' and v_available<p_amount then raise exception 'Solde insuffisant pour ce moyen de paiement. Disponible : %, demandé : %',v_available,p_amount; end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'update_manual_cash_movement','cash_transactions',v_tx.id::text,jsonb_build_object('reason',trim(p_reason),'before',jsonb_build_object('date',v_tx.transaction_date,'direction',v_tx.direction,'amount',v_tx.amount,'channel',v_tx.payment_channel,'reference',v_tx.reference,'description',v_tx.description),'after',jsonb_build_object('date',p_transaction_date,'direction',p_direction,'amount',p_amount,'channel',p_payment_channel,'reference',p_reference,'description',p_description)));
  update public.cash_transactions set transaction_date=(p_transaction_date::timestamp at time zone 'UTC')+interval '12 hours',direction=p_direction,amount=p_amount,payment_channel=p_payment_channel,reference=nullif(trim(coalesce(p_reference,'')),''),description=trim(p_description)
  where id=v_tx.id;
end $$;
revoke all on function public.update_manual_cash_movement(uuid,text,bigint,date,text,text,text,text) from public,anon;
grant execute on function public.update_manual_cash_movement(uuid,text,bigint,date,text,text,text,text) to authenticated;

create or replace function public.delete_manual_cash_movement(p_transaction_id uuid,p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_tx public.cash_transactions%rowtype; v_uid uuid:=auth.uid();
begin
  if v_uid is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Suppression réservée à l’administration ou à la comptabilité.' using errcode='42501'; end if;
  select * into v_tx from public.cash_transactions t where t.id=p_transaction_id for update;
  if not found then raise exception 'Mouvement introuvable.'; end if;
  if v_tx.transaction_type<>'adjustment' or v_tx.payment_id is not null or v_tx.expense_id is not null or v_tx.transfer_group_id is not null or v_tx.reverses_transaction_id is not null then
    raise exception 'Seules les lignes de caisse saisies manuellement peuvent être supprimées ici. Les reçus et dépenses doivent être annulés dans leur module.';
  end if;
  if exists(select 1 from public.bank_reconciliations r where r.cash_transaction_id=v_tx.id and r.status='matched') then raise exception 'Ce mouvement est rapproché et ne peut plus être supprimé.'; end if;
  if exists(select 1 from public.cash_transactions t where t.reverses_transaction_id=v_tx.id) then raise exception 'Une contrepassation existe pour ce mouvement.'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Le motif de suppression est obligatoire.'; end if;
  if public.cash_method_balance(v_tx.payment_channel,now(),v_tx.id)<0 then
    raise exception 'Suppression refusée : les mouvements postérieurs entraîneraient un solde négatif pour ce moyen de paiement.';
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'delete_manual_cash_movement','cash_transactions',v_tx.id::text,jsonb_build_object('reason',trim(p_reason),'deleted_transaction',to_jsonb(v_tx)));
  delete from public.cash_transactions where id=v_tx.id;
end $$;
revoke all on function public.delete_manual_cash_movement(uuid,text) from public,anon;
grant execute on function public.delete_manual_cash_movement(uuid,text) to authenticated;

-- Contrôle de dépense par canal : le solde espèces ne doit pas être mélangé avec les soldes Mobile Money.
create or replace function public.validate_expense(p_expense_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_expense public.expenses%rowtype;
  v_balance bigint;
  v_uid uuid := auth.uid();
  v_channel text;
  v_kind text;
  v_when timestamptz;
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Accès refusé'; end if;
  select * into v_expense from public.expenses where id=p_expense_id for update;
  if not found then raise exception 'Dépense introuvable'; end if;
  if v_expense.status<>'draft' then raise exception 'Seule une dépense en brouillon peut être validée'; end if;
  if v_expense.expense_date > current_date then raise exception 'Une dépense datée dans le futur ne peut pas être validée.'; end if;
  select a.kind::text into v_kind from public.cash_accounts a where a.id=v_expense.account_id and a.is_active=true for update;
  if not found then raise exception 'Compte inactif ou introuvable'; end if;
  if exists(select 1 from public.cash_transactions t where t.expense_id=v_expense.id and t.transaction_type='expense') then raise exception 'Un mouvement existe déjà pour cette dépense'; end if;

  v_when := ((v_expense.expense_date::timestamp at time zone 'UTC') + interval '1 day' - interval '1 microsecond');
  if v_expense.payment_method::text in ('especes','mobile_money') then
    if v_kind<>'cash' then raise exception 'Les espèces et Mobile Money doivent utiliser la caisse principale.'; end if;
    v_channel := case when v_expense.payment_method::text='especes' then 'especes' else coalesce(v_expense.mobile_money_provider,'mobile_money') end;
    if v_channel='mobile_money' then raise exception 'Précisez Orange Money, Wave ou Moov Money avant de valider cette dépense.'; end if;
    v_balance := public.cash_method_balance(v_channel,v_when,null);
  else
    v_balance := public.current_account_balance(v_expense.account_id,v_when);
  end if;
  if v_balance < v_expense.amount then raise exception 'Solde insuffisant pour le moyen de paiement choisi : disponible %, demandé %',v_balance,v_expense.amount; end if;

  update public.expenses set status='validated',validated_at=now(),validated_by=v_uid where id=p_expense_id;
  insert into public.cash_transactions(account_id,transaction_date,direction,amount,transaction_type,expense_id,reference,description,status,created_by,validated_at,validated_by,payment_channel)
  values(v_expense.account_id,(v_expense.expense_date::timestamp at time zone 'UTC'),'out',v_expense.amount,'expense',v_expense.id,v_expense.expense_number,v_expense.description,'validated',v_uid,now(),v_uid,
    case when v_expense.payment_method::text='mobile_money' then coalesce(v_expense.mobile_money_provider,'mobile_money') else v_expense.payment_method::text end);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'validate_expense','expenses',p_expense_id::text,jsonb_build_object('amount',v_expense.amount,'expense_number',v_expense.expense_number,'account_id',v_expense.account_id,'payment_channel',case when v_expense.payment_method::text='mobile_money' then v_expense.mobile_money_provider else v_expense.payment_method::text end));
end $$;
revoke all on function public.validate_expense(uuid) from public,anon;
grant execute on function public.validate_expense(uuid) to authenticated;

commit;
