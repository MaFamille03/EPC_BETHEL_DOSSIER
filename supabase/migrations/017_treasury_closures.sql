-- EPC BETHEL — clôtures journalières de caisse, historiques immuables
create table if not exists public.cash_daily_closures (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.cash_accounts(id) on delete restrict,
  closure_date date not null,
  opening_balance bigint not null,
  validated_in bigint not null default 0,
  validated_out bigint not null default 0,
  theoretical_balance bigint not null,
  counted_balance bigint not null check (counted_balance >= 0),
  variance bigint generated always as (counted_balance - theoretical_balance) stored,
  variance_reason text,
  observation text,
  closed_by uuid not null references public.profiles(id) on delete restrict,
  closed_at timestamptz not null default now(),
  unique(account_id, closure_date),
  check (variance = 0 or nullif(trim(coalesce(variance_reason,'')), '') is not null)
);
create index if not exists cash_daily_closures_date_idx on public.cash_daily_closures(closure_date desc, account_id);
alter table public.cash_daily_closures enable row level security;
drop policy if exists cash_daily_closures_read on public.cash_daily_closures;
create policy cash_daily_closures_read on public.cash_daily_closures for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
drop policy if exists cash_daily_closures_insert on public.cash_daily_closures;
create policy cash_daily_closures_insert on public.cash_daily_closures for insert to authenticated
with check (
  closed_by = (select auth.uid())
  and public.has_any_role(array['admin','comptabilite']::public.app_role[])
  and exists(select 1 from public.cash_accounts a where a.id=account_id and a.is_active and a.kind in ('cash','mobile_money'))
);
-- Pas de politique UPDATE/DELETE : une clôture enregistrée ne peut pas être réécrite silencieusement.
grant select, insert on public.cash_daily_closures to authenticated;
revoke update, delete on public.cash_daily_closures from authenticated;
