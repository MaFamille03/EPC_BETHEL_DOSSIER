-- EPC BETHEL ASSEMBLEES DE DIEU JEAN FOLLY
-- Migration initiale de référence (PostgreSQL / Supabase)
-- À tester sur un projet Supabase de développement avant toute production.
-- Les opérations de paiement/transfert doivent être implémentées en fonctions
-- transactionnelles dédiées avant l'ouverture de l'application.

create extension if not exists pgcrypto;

create type public.app_role as enum ('admin', 'direction', 'secretariat', 'comptabilite');
create type public.account_kind as enum ('cash', 'bank');
create type public.payment_method as enum ('especes', 'virement', 'mobile_money', 'cheque', 'autre');
create type public.charge_kind as enum ('scolarite', 'inscription', 'annexe', 'autre');
create type public.record_status as enum ('draft', 'validated', 'cancelled', 'archived');
create type public.student_status as enum ('actif', 'transfere', 'sorti', 'archive');
create type public.reconciliation_status as enum ('unmatched', 'matched', 'ignored', 'review');

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  full_name text not null,
  role public.app_role not null default 'secretariat',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.school_settings (
  id uuid primary key default gen_random_uuid(),
  school_name text not null default 'EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY',
  currency_code text not null default 'XOF' check (currency_code = 'XOF'),
  currency_label text not null default 'FCFA',
  phone text,
  email text,
  address text,
  logo_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.school_years (
  id uuid primary key default gen_random_uuid(),
  label text not null unique,
  starts_on date not null,
  ends_on date not null,
  is_current boolean not null default false,
  is_closed boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check (ends_on > starts_on)
);
create unique index one_current_school_year on public.school_years(is_current) where is_current;

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  level_order integer not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.classes(code, name, level_order) values
('MS','Moyenne Section',1),
('GSA','Grande Section A',2), ('GSB','Grande Section B',2),
('CP1A','CP1 A',3), ('CP1B','CP1 B',3),
('CP2A','CP2 A',4), ('CP2B','CP2 B',4),
('CE1A','CE1 A',5), ('CE1B','CE1 B',5),
('CE2A','CE2 A',6), ('CE2B','CE2 B',6),
('CM1A','CM1 A',7), ('CM1B','CM1 B',7),
('CM2A','CM2 A',8), ('CM2B','CM2 B',8)
on conflict (code) do nothing;

create table public.students (
  id uuid primary key default gen_random_uuid(),
  student_number text not null unique,
  last_name text not null,
  first_names text not null,
  sex text check (sex in ('F','M','X')),
  birth_date date,
  birth_place text,
  photo_path text,
  status public.student_status not null default 'actif',
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now()
);

create table public.guardians (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  email text,
  address text,
  occupation text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);

create table public.student_guardians (
  student_id uuid not null references public.students(id) on delete restrict,
  guardian_id uuid not null references public.guardians(id) on delete restrict,
  relationship text,
  is_primary boolean not null default false,
  receives_messages boolean not null default true,
  primary key (student_id, guardian_id)
);
create unique index one_primary_guardian_per_student
on public.student_guardians(student_id) where is_primary;

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete restrict,
  school_year_id uuid not null references public.school_years(id) on delete restrict,
  class_id uuid not null references public.classes(id) on delete restrict,
  enrolled_on date not null default current_date,
  status text not null default 'inscrit'
    check (status in ('inscrit','reinscrit','transfere','sorti','annule')),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique (student_id, school_year_id)
);
create index enrollments_year_class_idx on public.enrollments(school_year_id, class_id, status);

create table public.fee_categories (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  kind public.charge_kind not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
insert into public.fee_categories(code,name,kind) values
('SCOLARITE','Scolarité','scolarite'),
('INSCRIPTION','Inscription / réinscription','inscription'),
('ANNEXE','Frais annexes','annexe'),
('AUTRE','Autres frais','autre')
on conflict (code) do nothing;

create table public.student_charges (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  fee_category_id uuid not null references public.fee_categories(id) on delete restrict,
  description text not null,
  amount_due bigint not null check (amount_due >= 0),
  due_on date,
  status public.record_status not null default 'validated',
  source text not null default 'manual' check (source in ('manual','tariff_template','import')),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancellation_reason text
);
create index student_charges_enrollment_idx on public.student_charges(enrollment_id);
create index student_charges_category_idx on public.student_charges(fee_category_id, status);

create table public.installments (
  id uuid primary key default gen_random_uuid(),
  charge_id uuid not null references public.student_charges(id) on delete restrict,
  installment_no smallint not null check (installment_no between 1 and 6),
  amount_due bigint not null check (amount_due >= 0),
  due_on date not null,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique (charge_id, installment_no)
);
create index installments_due_idx on public.installments(due_on);

create table public.cash_accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  kind public.account_kind not null,
  bank_name text,
  account_reference_masked text,
  opening_balance bigint not null default 0,
  opening_date date not null default current_date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
insert into public.cash_accounts(code,name,kind) values
('CAISSE','Caisse principale','cash'),
('BANQUE','Compte bancaire principal','bank')
on conflict (code) do nothing;

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  receipt_number text not null unique,
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  paid_at timestamptz not null default now(),
  amount bigint not null check (amount > 0),
  method public.payment_method not null,
  account_id uuid not null references public.cash_accounts(id) on delete restrict,
  external_reference text,
  payer_name text,
  notes text,
  status public.record_status not null default 'draft',
  idempotency_key text unique,
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  validated_at timestamptz,
  validated_by uuid references public.profiles(id) on delete restrict,
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(id) on delete restrict,
  cancellation_reason text
);
create index payments_paid_at_idx on public.payments(paid_at);
create index payments_enrollment_idx on public.payments(enrollment_id, status);

create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete restrict,
  charge_id uuid not null references public.student_charges(id) on delete restrict,
  installment_id uuid references public.installments(id) on delete restrict,
  amount bigint not null check (amount > 0),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check (installment_id is null or charge_id is not null)
);
create index payment_allocations_payment_idx on public.payment_allocations(payment_id);
create index payment_allocations_charge_idx on public.payment_allocations(charge_id);

create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true
);
create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  expense_number text not null unique,
  expense_date date not null,
  category_id uuid not null references public.expense_categories(id) on delete restrict,
  beneficiary text not null,
  description text not null,
  amount bigint not null check (amount > 0),
  account_id uuid not null references public.cash_accounts(id) on delete restrict,
  payment_method public.payment_method not null,
  document_path text,
  external_reference text,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  validated_at timestamptz,
  validated_by uuid references public.profiles(id) on delete restrict,
  cancelled_at timestamptz,
  cancellation_reason text
);

create table public.cash_transactions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.cash_accounts(id) on delete restrict,
  transaction_date timestamptz not null default now(),
  direction text not null check (direction in ('in','out')),
  amount bigint not null check (amount > 0),
  transaction_type text not null check (transaction_type in ('payment','expense','transfer','adjustment','reversal','opening')),
  payment_id uuid references public.payments(id) on delete restrict,
  expense_id uuid references public.expenses(id) on delete restrict,
  transfer_group_id uuid,
  reverses_transaction_id uuid references public.cash_transactions(id) on delete restrict,
  reference text,
  description text not null,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  validated_at timestamptz,
  validated_by uuid references public.profiles(id) on delete restrict,
  check (
    (transaction_type = 'payment' and payment_id is not null and expense_id is null)
    or (transaction_type = 'expense' and expense_id is not null and payment_id is null)
    or (transaction_type in ('transfer','adjustment','reversal','opening'))
  )
);
create index cash_transactions_account_date_idx on public.cash_transactions(account_id, transaction_date, status);
create index cash_transactions_transfer_idx on public.cash_transactions(transfer_group_id);

create table public.bank_statement_imports (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.cash_accounts(id) on delete restrict,
  file_name text not null,
  period_start date,
  period_end date,
  imported_at timestamptz not null default now(),
  imported_by uuid references public.profiles(id) on delete restrict,
  status text not null default 'imported' check (status in ('imported','review','completed','cancelled'))
);
create table public.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.bank_statement_imports(id) on delete restrict,
  line_no integer not null,
  operation_date date not null,
  value_date date,
  label text not null,
  reference text,
  debit bigint not null default 0 check (debit >= 0),
  credit bigint not null default 0 check (credit >= 0),
  external_line_key text,
  reconciliation_status public.reconciliation_status not null default 'unmatched',
  unique (import_id, line_no),
  check (not (debit > 0 and credit > 0))
);
create table public.bank_reconciliations (
  id uuid primary key default gen_random_uuid(),
  statement_line_id uuid not null references public.bank_statement_lines(id) on delete restrict,
  cash_transaction_id uuid not null references public.cash_transactions(id) on delete restrict,
  matched_amount bigint not null check (matched_amount > 0),
  status public.reconciliation_status not null default 'matched',
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  validated_at timestamptz,
  validated_by uuid references public.profiles(id) on delete restrict,
  unique (statement_line_id, cash_transaction_id)
);

create table public.receipt_sequences (
  sequence_year integer primary key,
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_table text not null,
  entity_id text,
  occurred_at timestamptz not null default now(),
  request_id text,
  details jsonb not null default '{}'::jsonb
);
create index audit_logs_entity_idx on public.audit_logs(entity_table, entity_id, occurred_at desc);
create index audit_logs_actor_idx on public.audit_logs(actor_id, occurred_at desc);

create table public.import_batches (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  source_type text not null check (source_type in ('students','payments','guardians','other')),
  status text not null default 'uploaded' check (status in ('uploaded','validated','importing','completed','failed','cancelled')),
  total_rows integer not null default 0,
  accepted_rows integer not null default 0,
  rejected_rows integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  completed_at timestamptz
);
create table public.import_rows (
  id bigint generated always as identity primary key,
  batch_id uuid not null references public.import_batches(id) on delete restrict,
  source_row_number integer not null,
  raw_data jsonb not null,
  normalized_data jsonb,
  row_status text not null default 'pending' check (row_status in ('pending','valid','imported','rejected','duplicate')),
  errors jsonb not null default '[]'::jsonb,
  imported_entity_id uuid,
  unique (batch_id, source_row_number)
);

-- Views de lecture : les paiements validés seulement sont pris en compte.
create or replace view public.v_charge_balances as
select
  c.id as charge_id,
  c.enrollment_id,
  c.fee_category_id,
  c.description,
  c.amount_due,
  coalesce(sum(pa.amount) filter (where p.status = 'validated'), 0)::bigint as amount_paid,
  (c.amount_due - coalesce(sum(pa.amount) filter (where p.status = 'validated'), 0))::bigint as balance_due
from public.student_charges c
left join public.payment_allocations pa on pa.charge_id = c.id
left join public.payments p on p.id = pa.payment_id
where c.status = 'validated'
group by c.id;

create or replace view public.v_account_balances as
select
  a.id as account_id,
  a.code,
  a.name,
  a.kind,
  a.opening_balance
    + coalesce(sum(
        case when t.status = 'validated' and t.direction = 'in' then t.amount
             when t.status = 'validated' and t.direction = 'out' then -t.amount
             else 0 end
      ),0)::bigint as current_balance
from public.cash_accounts a
left join public.cash_transactions t on t.account_id = a.id
group by a.id;

-- Helper de rôle : fonctions SECURITY DEFINER à garder minimales.
create or replace function public.current_app_role()
returns public.app_role
language sql stable security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.id = (select auth.uid()) and p.is_active = true
$$;

create or replace function public.has_any_role(allowed public.app_role[])
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.is_active = true
      and p.role = any(allowed)
  )
$$;

revoke all on function public.current_app_role() from public;
revoke all on function public.has_any_role(public.app_role[]) from public;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.has_any_role(public.app_role[]) to authenticated;

-- RLS activée partout sur les tables applicatives.
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','school_settings','school_years','classes','students','guardians',
    'student_guardians','enrollments','fee_categories','student_charges','installments',
    'cash_accounts','payments','payment_allocations','expense_categories','expenses',
    'cash_transactions','bank_statement_imports','bank_statement_lines','bank_reconciliations',
    'receipt_sequences','audit_logs','import_batches','import_rows'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Profil : chacun lit son profil ; direction/admin peuvent consulter les profils.
create policy profiles_select_self_or_management on public.profiles
for select to authenticated
using (id = (select auth.uid()) or public.has_any_role(array['admin','direction']::public.app_role[]));
create policy profiles_admin_all on public.profiles
for all to authenticated
using (public.has_any_role(array['admin']::public.app_role[]))
with check (public.has_any_role(array['admin']::public.app_role[]));

-- Référentiels : lecture par utilisateurs actifs ; modifications admin/direction.
create policy school_settings_read on public.school_settings for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy school_settings_manage on public.school_settings for all to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

create policy school_years_read on public.school_years for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy school_years_manage on public.school_years for all to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

create policy classes_read on public.classes for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy classes_manage on public.classes for all to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

create policy students_read on public.students for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy students_manage on public.students for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));

create policy guardians_read on public.guardians for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy guardians_manage on public.guardians for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));

create policy student_guardians_read on public.student_guardians for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy student_guardians_manage on public.student_guardians for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));

create policy enrollments_read on public.enrollments for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy enrollments_manage on public.enrollments for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));

create policy fee_categories_read on public.fee_categories for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy fee_categories_manage on public.fee_categories for all to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

create policy charges_read on public.student_charges for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy charges_manage on public.student_charges for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));

create policy installments_read on public.installments for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy installments_manage on public.installments for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));

create policy accounts_read on public.cash_accounts for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy accounts_manage on public.cash_accounts for all to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

create policy payments_read on public.payments for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy payments_insert_draft on public.payments for insert to authenticated
with check (
  created_by = (select auth.uid())
  and status = 'draft'
  and public.has_any_role(array['admin','comptabilite']::public.app_role[])
);
create policy payments_update_draft on public.payments for update to authenticated
using (status = 'draft' and public.has_any_role(array['admin','comptabilite']::public.app_role[]))
with check (status = 'draft' and public.has_any_role(array['admin','comptabilite']::public.app_role[]));

create policy allocations_read on public.payment_allocations for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy allocations_insert_draft on public.payment_allocations for insert to authenticated
with check (
  public.has_any_role(array['admin','comptabilite']::public.app_role[])
  and exists (select 1 from public.payments p where p.id = payment_id and p.status = 'draft')
);
-- Aucune politique UPDATE/DELETE pour allocations : corrections par workflow contrôlé.

create policy expenses_read on public.expenses for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy expenses_insert_draft on public.expenses for insert to authenticated
with check (created_by = (select auth.uid()) and status = 'draft'
  and public.has_any_role(array['admin','comptabilite']::public.app_role[]));
create policy expenses_update_draft on public.expenses for update to authenticated
using (status = 'draft' and public.has_any_role(array['admin','comptabilite']::public.app_role[]))
with check (status = 'draft' and public.has_any_role(array['admin','comptabilite']::public.app_role[]));

create policy transactions_read on public.cash_transactions for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
-- Aucun INSERT/UPDATE/DELETE direct par les utilisateurs : les mouvements doivent être
-- écrits par les fonctions SQL transactionnelles de validation.

create policy expense_categories_read on public.expense_categories for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy expense_categories_manage on public.expense_categories for all to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

create policy bank_imports_read on public.bank_statement_imports for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy bank_imports_manage on public.bank_statement_imports for all to authenticated
using (public.has_any_role(array['admin','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','comptabilite']::public.app_role[]));

create policy bank_lines_read on public.bank_statement_lines for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy bank_lines_manage on public.bank_statement_lines for all to authenticated
using (public.has_any_role(array['admin','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','comptabilite']::public.app_role[]));

create policy reconciliations_read on public.bank_reconciliations for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy reconciliations_manage on public.bank_reconciliations for all to authenticated
using (public.has_any_role(array['admin','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','comptabilite']::public.app_role[]));

create policy receipt_sequences_read on public.receipt_sequences for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
-- Allocation de numéro réservée aux fonctions SQL de confiance.

create policy audit_logs_read on public.audit_logs for select to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]));
-- Insertion d'audit réservée aux fonctions serveur ; pas de mutation par le client.

create policy import_batches_read on public.import_batches for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy import_batches_manage on public.import_batches for all to authenticated
using (public.has_any_role(array['admin','secretariat','comptabilite']::public.app_role[]))
with check (created_by = (select auth.uid()) and public.has_any_role(array['admin','secretariat','comptabilite']::public.app_role[]));

create policy import_rows_read on public.import_rows for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy import_rows_manage on public.import_rows for all to authenticated
using (public.has_any_role(array['admin','secretariat','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','secretariat','comptabilite']::public.app_role[]));

-- Updated-at triggers.
create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger students_updated_at before update on public.students
for each row execute function public.set_updated_at();
create trigger school_settings_updated_at before update on public.school_settings
for each row execute function public.set_updated_at();
create trigger student_charges_updated_at before update on public.student_charges
for each row execute function public.set_updated_at();

-- IMPORTANT : cette migration de base fournit les tables, vues et RLS de départ.
-- Avant la production, ajouter les fonctions transactionnelles SECURITY DEFINER :
-- 1) create_and_validate_payment(...)
-- 2) cancel_payment(...)
-- 3) validate_expense(...)
-- 4) transfer_between_accounts(...)
-- 5) allocate_receipt_number(...)
-- Ces fonctions doivent valider les allocations, verrouiller les lignes FOR UPDATE,
-- générer les écritures de trésorerie, écrire audit_logs et être seules autorisées
-- à muter les tables financières validées.
