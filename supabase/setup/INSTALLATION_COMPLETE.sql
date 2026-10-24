-- EPC BETHEL — SCHÉMA CONSOLIDÉ POUR NOUVELLE BASE VIDE UNIQUEMENT
-- Schéma consolidé basé sur les migrations 001 à 026 ; le bootstrap fixe par e-mail est retiré.
-- NE PAS EXÉCUTER sur une base Supabase existante ou contenant des données.
-- Pour une base existante, appliquer uniquement les migrations manquantes et dans l’ordre.
-- Chaque migration est validée séparément. Ceci est important pour les valeurs enum introduites en 010.


-- ============================================================
-- MIGRATION 001_initial_schema.sql
-- ============================================================
BEGIN;
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
COMMIT;

-- ============================================================
-- MIGRATION 002_financial_workflows.sql
-- ============================================================
BEGIN;
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
COMMIT;

-- ============================================================
-- MIGRATION 003_concessions_achats_patrimoine_auth.sql
-- ============================================================
BEGIN;
-- 003_concessions_purchases_assets_auth_epc_bethel.sql
-- Extension : auth/permissions, concessions scolaires, achats et patrimoine.
-- À exécuter après 001 et 002 en environnement de développement, puis auditer avant prod.

create type public.concession_kind as enum ('percentage','fixed_amount');
create type public.concession_status as enum ('requested','approved','rejected','revoked');
create type public.purchase_status as enum ('draft','submitted','approved','rejected','ordered','partially_received','received','closed','cancelled');
create type public.asset_status as enum ('active','under_maintenance','lost','damaged','disposed','retired');
create type public.asset_movement_kind as enum ('assignment','transfer','maintenance_out','maintenance_return','loss','damage','disposal','inventory_adjustment');

-- Permissions granulaires. Le rôle reste le profil initial, les permissions définissent les actions.
create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  label text not null,
  domain text not null
);
create table public.role_permissions (
  role public.app_role not null,
  permission_id uuid not null references public.permissions(id) on delete restrict,
  primary key(role, permission_id)
);

insert into public.permissions(code,label,domain) values
('users.manage','Gérer les comptes et rôles','security'),
('students.read','Consulter les élèves','students'),
('students.manage','Créer et modifier les élèves','students'),
('enrollments.manage','Gérer les inscriptions','enrollments'),
('concessions.request','Demander une concession scolaire','finance'),
('concessions.approve','Approuver ou révoquer une concession','finance'),
('payments.create','Créer les paiements','finance'),
('payments.validate','Valider les paiements','finance'),
('payments.cancel','Annuler les paiements','finance'),
('expenses.create','Créer les dépenses','finance'),
('expenses.validate','Valider les dépenses','finance'),
('purchases.request','Créer les demandes d’achat','purchases'),
('purchases.approve','Approuver les achats','purchases'),
('purchases.receive','Réceptionner les commandes','purchases'),
('assets.manage','Gérer le patrimoine','assets'),
('assets.dispose','Valider la sortie ou réforme d’un bien','assets'),
('reports.finance.view','Consulter les rapports financiers','reports'),
('audit.read','Consulter le journal d’audit','security')
on conflict (code) do nothing;

-- Valeurs de départ : à adapter après revue de la matrice de permissions.
insert into public.role_permissions(role, permission_id)
select r.role, p.id
from (values
 ('admin'::public.app_role,'users.manage'),
 ('admin'::public.app_role,'students.read'),
 ('admin'::public.app_role,'students.manage'),
 ('admin'::public.app_role,'enrollments.manage'),
 ('admin'::public.app_role,'concessions.request'),
 ('admin'::public.app_role,'concessions.approve'),
 ('admin'::public.app_role,'payments.create'),
 ('admin'::public.app_role,'payments.validate'),
 ('admin'::public.app_role,'payments.cancel'),
 ('admin'::public.app_role,'expenses.create'),
 ('admin'::public.app_role,'expenses.validate'),
 ('admin'::public.app_role,'purchases.request'),
 ('admin'::public.app_role,'purchases.approve'),
 ('admin'::public.app_role,'purchases.receive'),
 ('admin'::public.app_role,'assets.manage'),
 ('admin'::public.app_role,'assets.dispose'),
 ('admin'::public.app_role,'reports.finance.view'),
 ('admin'::public.app_role,'audit.read'),
 ('direction'::public.app_role,'students.read'),
 ('direction'::public.app_role,'concessions.approve'),
 ('direction'::public.app_role,'payments.cancel'),
 ('direction'::public.app_role,'purchases.approve'),
 ('direction'::public.app_role,'assets.dispose'),
 ('direction'::public.app_role,'reports.finance.view'),
 ('direction'::public.app_role,'audit.read'),
 ('secretariat'::public.app_role,'students.read'),
 ('secretariat'::public.app_role,'students.manage'),
 ('secretariat'::public.app_role,'enrollments.manage'),
 ('secretariat'::public.app_role,'concessions.request'),
 ('secretariat'::public.app_role,'purchases.request'),
 ('secretariat'::public.app_role,'assets.manage'),
 ('comptabilite'::public.app_role,'students.read'),
 ('comptabilite'::public.app_role,'payments.create'),
 ('comptabilite'::public.app_role,'payments.validate'),
 ('comptabilite'::public.app_role,'expenses.create'),
 ('comptabilite'::public.app_role,'expenses.validate'),
 ('comptabilite'::public.app_role,'purchases.receive'),
 ('comptabilite'::public.app_role,'reports.finance.view')
) as r(role, permission_code)
join public.permissions p on p.code = r.permission_code
on conflict do nothing;

-- Concessions : une décision porte sur la scolarité par défaut.
create table public.enrollment_concessions (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  scope text not null default 'scolarite'
    check (scope in ('scolarite','inscription','annexe','all_eligible')),
  kind public.concession_kind not null,
  percentage numeric(5,2),
  fixed_amount bigint,
  reason_code text not null,
  reason_detail text,
  status public.concession_status not null default 'requested',
  requested_by uuid not null references public.profiles(id) on delete restrict,
  requested_at timestamptz not null default now(),
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  valid_from date,
  valid_to date,
  attachment_path text,
  decision_note text,
  revoked_by uuid references public.profiles(id) on delete restrict,
  revoked_at timestamptz,
  revocation_reason text,
  created_at timestamptz not null default now(),
  check (
    (kind = 'percentage' and percentage between 0 and 100 and fixed_amount is null)
    or (kind = 'fixed_amount' and fixed_amount >= 0 and percentage is null)
  ),
  check (valid_to is null or valid_from is null or valid_to >= valid_from),
  check (
    (status = 'approved' and approved_by is not null and approved_at is not null)
    or status <> 'approved'
  )
);
create index enrollment_concessions_enrollment_idx
  on public.enrollment_concessions(enrollment_id, status);

create table public.concession_events (
  id bigint generated always as identity primary key,
  concession_id uuid not null references public.enrollment_concessions(id) on delete restrict,
  event_type text not null check (event_type in ('requested','approved','rejected','modified','revoked','adjustment')),
  actor_id uuid references public.profiles(id) on delete set null,
  occurred_at timestamptz not null default now(),
  reason text,
  before_data jsonb,
  after_data jsonb
);

alter table public.student_charges
  add column if not exists gross_amount bigint,
  add column if not exists discount_amount bigint not null default 0,
  add column if not exists concession_id uuid references public.enrollment_concessions(id) on delete restrict;

update public.student_charges
set gross_amount = amount_due
where gross_amount is null;

alter table public.student_charges
  alter column gross_amount set not null;

alter table public.student_charges
  add constraint student_charges_discount_nonnegative check (discount_amount >= 0),
  add constraint student_charges_discount_not_over_gross check (discount_amount <= gross_amount),
  add constraint student_charges_net_equals_gross_minus_discount
    check (amount_due = gross_amount - discount_amount);

-- Fournisseurs et achats.
create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  address text,
  registration_reference text,
  payment_terms text,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);

create table public.purchase_requests (
  id uuid primary key default gen_random_uuid(),
  request_number text not null unique,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  requested_at timestamptz not null default now(),
  purpose text not null,
  cost_center text,
  status public.purchase_status not null default 'draft',
  estimated_total bigint not null default 0 check (estimated_total >= 0),
  submitted_at timestamptz,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now()
);

create table public.purchase_request_lines (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.purchase_requests(id) on delete restrict,
  description text not null,
  item_kind text not null check (item_kind in ('asset','stock','service','other')),
  quantity numeric(12,3) not null check (quantity > 0),
  estimated_unit_price bigint not null check (estimated_unit_price >= 0),
  category text,
  notes text
);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  request_id uuid references public.purchase_requests(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  ordered_on date not null default current_date,
  expected_delivery_on date,
  status public.purchase_status not null default 'ordered',
  total_amount bigint not null check (total_amount >= 0),
  created_by uuid not null references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

create table public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  description text not null,
  item_kind text not null check (item_kind in ('asset','stock','service','other')),
  quantity_ordered numeric(12,3) not null check (quantity_ordered > 0),
  unit_price bigint not null check (unit_price >= 0),
  quantity_received numeric(12,3) not null default 0 check (quantity_received >= 0),
  check (quantity_received <= quantity_ordered)
);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  receipt_number text not null unique,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  received_at timestamptz not null default now(),
  received_by uuid not null references public.profiles(id) on delete restrict,
  delivery_reference text,
  notes text,
  status text not null default 'draft' check (status in ('draft','validated','cancelled'))
);

create table public.goods_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  goods_receipt_id uuid not null references public.goods_receipts(id) on delete restrict,
  purchase_order_line_id uuid not null references public.purchase_order_lines(id) on delete restrict,
  quantity_received numeric(12,3) not null check (quantity_received > 0),
  condition_note text,
  asset_id uuid,
  unique (goods_receipt_id, purchase_order_line_id)
);

-- Patrimoine.
create table public.asset_categories (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  useful_life_months integer check (useful_life_months is null or useful_life_months > 0),
  is_active boolean not null default true
);

create table public.assets (
  id uuid primary key default gen_random_uuid(),
  asset_code text not null unique,
  name text not null,
  category_id uuid not null references public.asset_categories(id) on delete restrict,
  description text,
  brand text,
  model text,
  serial_number text,
  acquired_on date,
  acquisition_cost bigint not null default 0 check (acquisition_cost >= 0),
  supplier_id uuid references public.suppliers(id) on delete restrict,
  purchase_order_line_id uuid references public.purchase_order_lines(id) on delete restrict,
  invoice_reference text,
  location text,
  custodian_id uuid references public.profiles(id) on delete restrict,
  status public.asset_status not null default 'active',
  photo_path text,
  qr_code_value text unique,
  disposed_on date,
  disposal_reason text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  check (
    (status not in ('disposed','retired') and disposed_on is null)
    or (status in ('disposed','retired') and disposed_on is not null)
  )
);

alter table public.goods_receipt_lines
  add constraint goods_receipt_lines_asset_fk
  foreign key (asset_id) references public.assets(id) on delete restrict;

create table public.asset_movements (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.assets(id) on delete restrict,
  movement_kind public.asset_movement_kind not null,
  moved_at timestamptz not null default now(),
  from_location text,
  to_location text,
  from_custodian_id uuid references public.profiles(id) on delete restrict,
  to_custodian_id uuid references public.profiles(id) on delete restrict,
  reason text not null,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.asset_inventory_sessions (
  id uuid primary key default gen_random_uuid(),
  inventory_number text not null unique,
  title text not null,
  started_on date not null default current_date,
  completed_on date,
  status text not null default 'draft' check (status in ('draft','in_progress','submitted','validated','cancelled')),
  responsible_id uuid not null references public.profiles(id) on delete restrict,
  validated_by uuid references public.profiles(id) on delete restrict,
  validated_at timestamptz,
  notes text
);

create table public.asset_inventory_lines (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.asset_inventory_sessions(id) on delete restrict,
  asset_id uuid not null references public.assets(id) on delete restrict,
  observed boolean not null default false,
  observed_location text,
  observed_condition text,
  variance_note text,
  checked_by uuid references public.profiles(id) on delete restrict,
  checked_at timestamptz,
  unique (session_id, asset_id)
);

create table public.asset_maintenance (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.assets(id) on delete restrict,
  maintenance_date date not null,
  description text not null,
  supplier_id uuid references public.suppliers(id) on delete restrict,
  cost bigint not null default 0 check (cost >= 0),
  expense_id uuid references public.expenses(id) on delete restrict,
  document_path text,
  status text not null default 'planned' check (status in ('planned','in_progress','completed','cancelled')),
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.purchase_expense_links (
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  expense_id uuid not null references public.expenses(id) on delete restrict,
  linked_at timestamptz not null default now(),
  linked_by uuid references public.profiles(id) on delete restrict,
  primary key (purchase_order_id, expense_id)
);

create index purchase_requests_status_idx on public.purchase_requests(status, requested_at desc);
create index purchase_orders_supplier_idx on public.purchase_orders(supplier_id, ordered_on desc);
create index assets_category_status_idx on public.assets(category_id, status);
create index asset_movements_asset_date_idx on public.asset_movements(asset_id, moved_at desc);
create index asset_inventory_lines_session_idx on public.asset_inventory_lines(session_id);

-- Mise en sécurité : RLS et politiques de lecture/gestion de départ.
do $$
declare t text;
begin
  foreach t in array array[
    'permissions','role_permissions','enrollment_concessions','concession_events',
    'suppliers','purchase_requests','purchase_request_lines','purchase_orders',
    'purchase_order_lines','goods_receipts','goods_receipt_lines','asset_categories',
    'assets','asset_movements','asset_inventory_sessions','asset_inventory_lines',
    'asset_maintenance','purchase_expense_links'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

create policy permissions_read on public.permissions for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy role_permissions_read on public.role_permissions for select to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]));
create policy role_permissions_admin on public.role_permissions for all to authenticated
using (public.has_any_role(array['admin']::public.app_role[]))
with check (public.has_any_role(array['admin']::public.app_role[]));

create policy concessions_read on public.enrollment_concessions for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy concessions_request on public.enrollment_concessions for insert to authenticated
with check (requested_by = (select auth.uid())
  and status = 'requested'
  and public.has_any_role(array['admin','secretariat','direction']::public.app_role[]));
-- Pas de mutation directe des concessions approuvées ; workflow via fonction transactionnelle à compléter.
create policy concession_events_read on public.concession_events for select to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]));

create policy suppliers_read on public.suppliers for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy suppliers_manage on public.suppliers for all to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));

create policy purchase_requests_read on public.purchase_requests for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy purchase_requests_create on public.purchase_requests for insert to authenticated
with check (requested_by = (select auth.uid()) and status = 'draft'
  and public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy purchase_requests_update_draft on public.purchase_requests for update to authenticated
using (status = 'draft' and requested_by = (select auth.uid()))
with check (status = 'draft' and requested_by = (select auth.uid()));

create policy purchase_request_lines_read on public.purchase_request_lines for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy purchase_request_lines_manage_draft on public.purchase_request_lines for all to authenticated
using (exists(select 1 from public.purchase_requests r where r.id=request_id and r.status='draft'
  and r.requested_by=(select auth.uid())))
with check (exists(select 1 from public.purchase_requests r where r.id=request_id and r.status='draft'
  and r.requested_by=(select auth.uid())));

create policy purchase_orders_read on public.purchase_orders for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy purchase_orders_manage on public.purchase_orders for all to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));

create policy purchase_order_lines_read on public.purchase_order_lines for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy purchase_order_lines_manage on public.purchase_order_lines for all to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));

create policy goods_receipts_read on public.goods_receipts for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy goods_receipts_manage on public.goods_receipts for all to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));

create policy goods_receipt_lines_read on public.goods_receipt_lines for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy goods_receipt_lines_manage on public.goods_receipt_lines for all to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));

create policy asset_categories_read on public.asset_categories for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy asset_categories_manage on public.asset_categories for all to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

create policy assets_read on public.assets for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy assets_manage on public.assets for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));

create policy asset_movements_read on public.asset_movements for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy asset_movements_manage on public.asset_movements for insert to authenticated
with check (created_by=(select auth.uid())
  and public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));

create policy inventory_sessions_read on public.asset_inventory_sessions for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));
create policy inventory_sessions_manage on public.asset_inventory_sessions for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));

create policy inventory_lines_read on public.asset_inventory_lines for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));
create policy inventory_lines_manage on public.asset_inventory_lines for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));

create policy asset_maintenance_read on public.asset_maintenance for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));
create policy asset_maintenance_manage on public.asset_maintenance for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]));

create policy purchase_expense_links_read on public.purchase_expense_links for select to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));
create policy purchase_expense_links_manage on public.purchase_expense_links for all to authenticated
using (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]));

-- À compléter impérativement avant production :
-- * fonction approve_concession() transactionnelle : validation du droit, verrouillage,
--   calcul gross/discount/net, création ou régularisation de charge et des six échéances,
--   événement d'audit, sans réécriture silencieuse des paiements historiques.
-- * fonctions de workflow achat (submit/approve/order/receive) avec seuils et séparation des tâches.
-- * politique d'approbation des biens mis au rebut et fonctions transactionnelles de mouvement.
-- * retirer les mutations directes non nécessaires sur purchase_orders, assets, inventory, maintenance ;
--   préférer des fonctions de service qui appliquent les transitions de statut.
-- * ne pas activer d'inscription publique aux comptes applicatifs ; provisionner le premier admin
--   via une procédure sécurisée et définir les rôles côté serveur.
COMMIT;

-- ============================================================
-- MIGRATION 004_scolarite_echeances_transactionnelles.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — création transactionnelle des frais de scolarité et de leurs six échéances.
-- À exécuter après les migrations 001, 002 et 003, dans un projet Supabase de développement d'abord.

create or replace function public.create_six_installments(
  p_enrollment_id uuid,
  p_amount bigint,
  p_due_dates date[],
  p_description text default 'Scolarité annuelle'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_category uuid;
  v_charge uuid;
  v_i integer;
  v_base bigint;
  v_remainder bigint;
  v_status text;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à créer une charge de scolarité';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Le montant doit être supérieur à zéro'; end if;
  if p_due_dates is null or cardinality(p_due_dates) <> 6 then raise exception 'Six dates d’échéance sont obligatoires'; end if;
  if array_position(p_due_dates, null) is not null then raise exception 'Une date d’échéance est manquante'; end if;
  for v_i in 2..6 loop
    if p_due_dates[v_i] < p_due_dates[v_i-1] then
      raise exception 'Les échéances doivent être classées par date croissante';
    end if;
  end loop;
  select status into v_status from public.enrollments where id = p_enrollment_id for update;
  if not found or v_status not in ('inscrit','reinscrit') then raise exception 'Inscription active introuvable'; end if;
  select id into v_category from public.fee_categories where code = 'SCOLARITE' and is_active = true;
  if v_category is null then raise exception 'La catégorie SCOLARITE est introuvable'; end if;

  insert into public.student_charges(
    enrollment_id, fee_category_id, description, amount_due, gross_amount,
    discount_amount, due_on, status, source, created_by
  ) values (
    p_enrollment_id, v_category, coalesce(nullif(trim(p_description),''),'Scolarité annuelle'),
    p_amount, p_amount, 0, p_due_dates[6], 'validated', 'manual', v_user
  ) returning id into v_charge;

  v_base := p_amount / 6;
  v_remainder := mod(p_amount, 6);
  for v_i in 1..6 loop
    insert into public.installments(charge_id, installment_no, amount_due, due_on, created_by)
    values (v_charge, v_i, v_base + case when v_i <= v_remainder then 1 else 0 end, p_due_dates[v_i], v_user);
  end loop;

  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values (v_user, 'create_six_installments', 'student_charges', v_charge::text,
          jsonb_build_object('enrollment_id',p_enrollment_id,'amount',p_amount,'due_dates',p_due_dates));
  return v_charge;
end;
$$;

revoke all on function public.create_six_installments(uuid,bigint,date[],text) from public;
grant execute on function public.create_six_installments(uuid,bigint,date[],text) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 005_scolarite_concessions.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — workflow transactionnel des concessions de scolarité.
-- À appliquer après 001, 002, 003 et 004, d'abord sur un projet Supabase de test.

create or replace function public.request_enrollment_concession(
  p_enrollment_id uuid,
  p_kind public.concession_kind,
  p_percentage numeric default null,
  p_fixed_amount bigint default null,
  p_reason_code text default 'autre',
  p_reason_detail text default null,
  p_valid_from date default null,
  p_valid_to date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à demander une concession';
  end if;
  if p_kind = 'percentage' and (p_percentage is null or p_percentage < 0 or p_percentage > 100 or p_fixed_amount is not null) then
    raise exception 'Pourcentage invalide';
  elsif p_kind = 'fixed_amount' and (p_fixed_amount is null or p_fixed_amount < 0 or p_percentage is not null) then
    raise exception 'Montant de concession invalide';
  end if;
  if p_valid_from is not null and p_valid_to is not null and p_valid_to < p_valid_from then
    raise exception 'La fin de validité précède le début';
  end if;
  perform 1 from public.enrollments e where e.id=p_enrollment_id and e.status in ('inscrit','reinscrit') for update;
  if not found then raise exception 'Inscription active introuvable'; end if;
  if exists (select 1 from public.enrollment_concessions c where c.enrollment_id=p_enrollment_id and c.scope='scolarite' and c.status='approved' and (c.valid_to is null or c.valid_to >= current_date) and (c.valid_from is null or c.valid_from <= current_date)) then
    raise exception 'Une concession de scolarité approuvée est déjà active pour cette inscription';
  end if;
  insert into public.enrollment_concessions(enrollment_id,scope,kind,percentage,fixed_amount,reason_code,reason_detail,status,requested_by,valid_from,valid_to)
  values (p_enrollment_id,'scolarite',p_kind,p_percentage,p_fixed_amount,coalesce(nullif(trim(p_reason_code),''),'autre'),nullif(trim(p_reason_detail),''),'requested',v_user,p_valid_from,p_valid_to)
  returning id into v_id;
  insert into public.concession_events(concession_id,event_type,actor_id,reason,after_data)
  values(v_id,'requested',v_user,coalesce(nullif(trim(p_reason_detail),''),p_reason_code),jsonb_build_object('kind',p_kind,'percentage',p_percentage,'fixed_amount',p_fixed_amount,'scope','scolarite'));
  return v_id;
end;
$$;

create or replace function public.decide_enrollment_concession(
  p_concession_id uuid,
  p_approve boolean,
  p_decision_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_concession public.enrollment_concessions%rowtype;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Seuls la direction et l’administration peuvent décider une concession';
  end if;
  select * into v_concession from public.enrollment_concessions where id=p_concession_id for update;
  if not found then raise exception 'Demande de concession introuvable'; end if;
  if v_concession.status <> 'requested' then raise exception 'Cette demande a déjà été traitée'; end if;
  perform 1 from public.enrollments where id=v_concession.enrollment_id for update;
  if p_approve and exists(select 1 from public.enrollment_concessions c where c.enrollment_id=v_concession.enrollment_id and c.id<>p_concession_id and c.scope='scolarite' and c.status='approved' and (c.valid_from is null or c.valid_from<=current_date) and (c.valid_to is null or c.valid_to>=current_date)) then
    raise exception 'Une autre concession de scolarité est déjà approuvée et active';
  end if;
  if p_approve then
    update public.enrollment_concessions set status='approved',approved_by=v_user,approved_at=now(),decision_note=nullif(trim(p_decision_note),'') where id=p_concession_id;
    insert into public.concession_events(concession_id,event_type,actor_id,reason,after_data)
    values(p_concession_id,'approved',v_user,nullif(trim(p_decision_note),''),jsonb_build_object('status','approved'));
  else
    update public.enrollment_concessions set status='rejected',decision_note=nullif(trim(p_decision_note),'') where id=p_concession_id;
    insert into public.concession_events(concession_id,event_type,actor_id,reason,after_data)
    values(p_concession_id,'rejected',v_user,nullif(trim(p_decision_note),''),jsonb_build_object('status','rejected'));
  end if;
end;
$$;

-- Remplace la fonction 004 pour appliquer uniquement une concession approuvée et valide.
create or replace function public.create_six_installments(
  p_enrollment_id uuid,
  p_amount bigint,
  p_due_dates date[],
  p_description text default 'Scolarité annuelle'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_category uuid;
  v_charge uuid;
  v_concession public.enrollment_concessions%rowtype;
  v_gross bigint;
  v_discount bigint := 0;
  v_net bigint;
  v_i integer;
  v_base bigint;
  v_remainder bigint;
  v_status text;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à créer une charge de scolarité';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Le montant brut doit être supérieur à zéro'; end if;
  if p_due_dates is null or cardinality(p_due_dates) <> 6 or array_position(p_due_dates, null) is not null then
    raise exception 'Six dates d’échéance sont obligatoires';
  end if;
  for v_i in 2..6 loop
    if p_due_dates[v_i] < p_due_dates[v_i-1] then raise exception 'Les échéances doivent être classées par date croissante'; end if;
  end loop;
  select status into v_status from public.enrollments where id=p_enrollment_id for update;
  if not found or v_status not in ('inscrit','reinscrit') then raise exception 'Inscription active introuvable'; end if;
  select id into v_category from public.fee_categories where code='SCOLARITE' and is_active=true;
  if v_category is null then raise exception 'La catégorie SCOLARITE est introuvable'; end if;
  if exists(select 1 from public.student_charges where enrollment_id=p_enrollment_id and fee_category_id=v_category and status='validated') then
    raise exception 'Une charge de scolarité validée existe déjà pour cette inscription';
  end if;
  select * into v_concession from public.enrollment_concessions c
   where c.enrollment_id=p_enrollment_id and c.scope in ('scolarite','all_eligible') and c.status='approved'
     and (c.valid_from is null or c.valid_from <= current_date)
     and (c.valid_to is null or c.valid_to >= current_date)
   order by c.approved_at desc limit 1 for update;
  v_gross := p_amount;
  if found then
    if v_concession.kind='percentage' then
      v_discount := round(v_gross * v_concession.percentage / 100.0)::bigint;
    else
      v_discount := least(v_gross,coalesce(v_concession.fixed_amount,0));
    end if;
  end if;
  v_net := v_gross-v_discount;
  insert into public.student_charges(enrollment_id,fee_category_id,description,amount_due,gross_amount,discount_amount,concession_id,due_on,status,source,created_by)
  values(p_enrollment_id,v_category,coalesce(nullif(trim(p_description),''),'Scolarité annuelle'),v_net,v_gross,v_discount,case when v_discount>0 then v_concession.id else null end,p_due_dates[6],'validated','manual',v_user)
  returning id into v_charge;
  v_base := v_net / 6;
  v_remainder := mod(v_net,6);
  for v_i in 1..6 loop
    insert into public.installments(charge_id,installment_no,amount_due,due_on,created_by)
    values(v_charge,v_i,v_base+case when v_i<=v_remainder then 1 else 0 end,p_due_dates[v_i],v_user);
  end loop;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'create_six_installments','student_charges',v_charge::text,jsonb_build_object('enrollment_id',p_enrollment_id,'gross_amount',v_gross,'discount_amount',v_discount,'net_amount',v_net,'concession_id',case when v_discount>0 then v_concession.id else null end,'due_dates',p_due_dates));
  return v_charge;
end;
$$;

revoke all on function public.request_enrollment_concession(uuid,public.concession_kind,numeric,bigint,text,text,date,date) from public;
revoke all on function public.decide_enrollment_concession(uuid,boolean,text) from public;
revoke all on function public.create_six_installments(uuid,bigint,date[],text) from public;
grant execute on function public.request_enrollment_concession(uuid,public.concession_kind,numeric,bigint,text,text,date,date) to authenticated;
grant execute on function public.decide_enrollment_concession(uuid,boolean,text) to authenticated;
grant execute on function public.create_six_installments(uuid,bigint,date[],text) to authenticated;

-- Création atomique du dossier élève et de son responsable principal.
create or replace function public.create_student_with_guardian(
  p_student_number text,
  p_last_name text,
  p_first_names text,
  p_sex text default null,
  p_birth_date date default null,
  p_birth_place text default null,
  p_guardian_name text default null,
  p_guardian_phone text default null,
  p_guardian_address text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_student uuid;
  v_guardian uuid;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à créer un dossier élève';
  end if;
  if nullif(trim(p_last_name),'') is null or nullif(trim(p_first_names),'') is null then
    raise exception 'Le nom et les prénoms sont obligatoires';
  end if;
  if p_sex is not null and p_sex not in ('F','M','X') then raise exception 'Sexe invalide'; end if;
  insert into public.students(student_number,last_name,first_names,sex,birth_date,birth_place,notes,created_by)
  values(coalesce(nullif(trim(p_student_number),''),'EPC-'||to_char(current_date,'YYYY')||'-'||upper(substr(encode(public.gen_random_bytes(4),'hex'),1,6))),trim(p_last_name),trim(p_first_names),p_sex,p_birth_date,nullif(trim(p_birth_place),''),nullif(trim(p_notes),''),v_user)
  returning id into v_student;
  if nullif(trim(p_guardian_name),'') is not null then
    insert into public.guardians(full_name,phone,address,created_by)
    values(trim(p_guardian_name),nullif(trim(p_guardian_phone),''),nullif(trim(p_guardian_address),''),v_user)
    returning id into v_guardian;
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary,receives_messages)
    values(v_student,v_guardian,'Responsable légal',true,true);
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'create_student_with_guardian','students',v_student::text,jsonb_build_object('student_number',p_student_number,'has_guardian',nullif(trim(p_guardian_name),'') is not null));
  return v_student;
end;
$$;

revoke all on function public.create_student_with_guardian(text,text,text,text,date,text,text,text,text,text) from public;
grant execute on function public.create_student_with_guardian(text,text,text,text,date,text,text,text,text,text) to authenticated;

-- Frais ponctuels : inscription/réinscription, frais annexes et autres frais.
create or replace function public.create_one_time_student_charge(
  p_enrollment_id uuid,
  p_fee_code text,
  p_description text,
  p_amount bigint,
  p_due_on date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_category uuid;
  v_charge uuid;
  v_status text;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à créer des frais';
  end if;
  if p_fee_code not in ('INSCRIPTION','ANNEXE','AUTRE') then raise exception 'Catégorie de frais ponctuels invalide'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Le montant doit être supérieur à zéro'; end if;
  if nullif(trim(p_description),'') is null then raise exception 'La désignation des frais est obligatoire'; end if;
  select status into v_status from public.enrollments where id=p_enrollment_id for update;
  if not found or v_status not in ('inscrit','reinscrit') then raise exception 'Inscription active introuvable'; end if;
  select id into v_category from public.fee_categories where code=p_fee_code and is_active=true;
  if v_category is null then raise exception 'Catégorie de frais introuvable ou inactive'; end if;
  if p_fee_code='INSCRIPTION' and exists(select 1 from public.student_charges where enrollment_id=p_enrollment_id and fee_category_id=v_category and status='validated') then
    raise exception 'Les frais d’inscription sont déjà enregistrés pour cette inscription';
  end if;
  insert into public.student_charges(enrollment_id,fee_category_id,description,amount_due,gross_amount,discount_amount,due_on,status,source,created_by)
  values(p_enrollment_id,v_category,trim(p_description),p_amount,p_amount,0,p_due_on,'validated','manual',v_user)
  returning id into v_charge;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'create_one_time_student_charge','student_charges',v_charge::text,jsonb_build_object('enrollment_id',p_enrollment_id,'fee_code',p_fee_code,'amount',p_amount,'due_on',p_due_on));
  return v_charge;
end;
$$;
revoke all on function public.create_one_time_student_charge(uuid,text,text,bigint,date) from public;
grant execute on function public.create_one_time_student_charge(uuid,text,text,bigint,date) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 006_paiements_recus.sql
-- ============================================================
BEGIN;
-- EPC BETHEL - Etape 2 : encaissements, affectation automatique, reçus et annulations contrôlées.
-- A exécuter après les migrations 001 à 005 sur un projet Supabase de développement.

create or replace function public.register_student_payment(
  p_enrollment_id uuid,
  p_amount bigint,
  p_method public.payment_method,
  p_account_id uuid,
  p_paid_at timestamptz default now(),
  p_payer_name text default null,
  p_external_reference text default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_receipt text;
  v_payment_id uuid;
  v_remaining bigint;
  v_total_due bigint;
  v_open bigint;
  v_charge record;
  v_installment record;
  v_take bigint;
  v_account public.cash_accounts%rowtype;
begin
  if v_user is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then
    raise exception 'Seul un administrateur ou la comptabilité peut enregistrer un encaissement';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Le montant doit être strictement positif'; end if;
  if p_enrollment_id is null then raise exception 'Sélectionnez une inscription'; end if;
  if p_paid_at is null then raise exception 'La date du paiement est obligatoire'; end if;

  perform 1 from public.enrollments e
   where e.id = p_enrollment_id and e.status in ('inscrit','reinscrit')
   for update;
  if not found then raise exception 'Inscription active introuvable'; end if;

  select * into v_account from public.cash_accounts
   where id = p_account_id and is_active = true for update;
  if not found then raise exception 'Compte de trésorerie inactif ou introuvable'; end if;

  -- Calcule le reste à payer sur les frais validés. Les échéances sont traitées en premier,
  -- par date puis numéro; les frais ponctuels sans échéances viennent ensuite.
  select coalesce(sum(greatest(c.amount_due - coalesce(paid.amount_paid,0),0)),0)::bigint
    into v_total_due
    from public.student_charges c
    left join lateral (
      select sum(pa.amount)::bigint as amount_paid
        from public.payment_allocations pa
        join public.payments p on p.id = pa.payment_id and p.status = 'validated'
       where pa.charge_id = c.id
    ) paid on true
   where c.enrollment_id = p_enrollment_id and c.status = 'validated';

  if p_amount > v_total_due then
    raise exception 'Le versement (%) dépasse le solde total dû (%)', p_amount, v_total_due;
  end if;
  if v_total_due <= 0 then raise exception 'Aucun frais impayé pour cette inscription'; end if;

  v_receipt := public.allocate_receipt_number(p_paid_at);
  insert into public.payments(
    receipt_number,enrollment_id,paid_at,amount,method,account_id,external_reference,
    payer_name,notes,status,created_by
  ) values (
    v_receipt,p_enrollment_id,p_paid_at,p_amount,p_method,p_account_id,
    nullif(trim(p_external_reference),''),nullif(trim(p_payer_name),''),
    nullif(trim(p_notes),''),'draft',v_user
  ) returning id into v_payment_id;

  v_remaining := p_amount;

  -- 1) Echéances de scolarité, avec vérification du montant restant de chacune.
  for v_installment in
    select i.id as installment_id, i.charge_id, i.amount_due, i.due_on, i.installment_no
      from public.installments i
      join public.student_charges c on c.id = i.charge_id
     where c.enrollment_id = p_enrollment_id and c.status = 'validated'
     order by i.due_on, i.installment_no, i.id
  loop
    exit when v_remaining = 0;
    -- Seuls les paiements validés réduisent le solde de l'échéance.
    v_open := greatest(v_installment.amount_due - coalesce((
      select sum(pa.amount)::bigint from public.payment_allocations pa
      join public.payments p on p.id=pa.payment_id and p.status='validated'
      where pa.installment_id=v_installment.installment_id
    ),0),0);
    if v_open > 0 then
      v_take := least(v_open,v_remaining);
      insert into public.payment_allocations(payment_id,charge_id,installment_id,amount,created_by)
      values(v_payment_id,v_installment.charge_id,v_installment.installment_id,v_take,v_user);
      v_remaining := v_remaining-v_take;
    end if;
  end loop;

  -- 2) Frais ponctuels qui n'ont pas d'échéances.
  for v_charge in
    select c.id,c.amount_due
      from public.student_charges c
     where c.enrollment_id=p_enrollment_id and c.status='validated'
       and not exists(select 1 from public.installments i where i.charge_id=c.id)
     order by c.due_on nulls last,c.created_at,c.id
  loop
    exit when v_remaining=0;
    select greatest(v_charge.amount_due-coalesce(sum(pa.amount) filter(where p.status='validated'),0),0)::bigint
      into v_open
      from public.payment_allocations pa join public.payments p on p.id=pa.payment_id
     where pa.charge_id=v_charge.id;
    if v_open>0 then
      v_take:=least(v_open,v_remaining);
      insert into public.payment_allocations(payment_id,charge_id,installment_id,amount,created_by)
      values(v_payment_id,v_charge.id,null,v_take,v_user);
      v_remaining:=v_remaining-v_take;
    end if;
  end loop;

  if v_remaining<>0 then raise exception 'Affectation automatique incomplète; opération annulée'; end if;
  perform public.validate_payment(v_payment_id);
  return jsonb_build_object('id',v_payment_id,'receipt_number',v_receipt,'amount',p_amount,'status','validated');
end;
$$;

revoke all on function public.register_student_payment(uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text) from public;
grant execute on function public.register_student_payment(uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text) to authenticated;

-- Annulation via cancel_payment() existante : motif obligatoire, écriture de contrepassation
-- et conservation de l'historique du reçu. Ne pas supprimer les paiements validés.
COMMIT;

-- ============================================================
-- MIGRATION 007_tresorerie_comptabilite.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — Étape 3 : trésorerie, dépenses et transferts
-- À exécuter après les migrations 001 à 006 dans un projet Supabase de développement.

create table if not exists public.expense_sequences (
  sequence_year integer primary key,
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default now()
);

insert into public.expense_categories(code,name,is_active) values
 ('FOURNITURES','Fournitures scolaires et de bureau',true),
 ('SALAIRES','Salaires et rémunérations',true),
 ('EAU_ELECTRICITE','Eau et électricité',true),
 ('ENTRETIEN','Entretien et réparations',true),
 ('TRANSPORT','Transport et déplacements',true),
 ('ACHATS','Achats et équipements',true),
 ('AUTRES','Autres dépenses',true)
on conflict (code) do nothing;

create or replace function public.current_account_balance(p_account_id uuid, p_at timestamptz default now())
returns bigint
language sql stable security invoker
set search_path = ''
as $$
  select coalesce(a.opening_balance,0)::bigint
    + coalesce(sum(case when t.direction='in' then t.amount else -t.amount end),0)::bigint
  from public.cash_accounts a
  left join public.cash_transactions t
    on t.account_id=a.id and t.status='validated' and t.transaction_date <= p_at
  where a.id=p_account_id
  group by a.id,a.opening_balance
$$;

create or replace function public.get_treasury_balances()
returns table(account_id uuid,account_code text,account_name text,account_kind public.account_kind,opening_balance bigint,balance bigint,total_in bigint,total_out bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]) then raise exception 'Accès refusé'; end if;
  return query
  select a.id,a.code,a.name,a.kind,a.opening_balance,
    (coalesce(a.opening_balance,0)+coalesce(sum(case when t.direction='in' then t.amount else -t.amount end),0))::bigint as balance,
    coalesce(sum(t.amount) filter(where t.direction='in'),0)::bigint as total_in,
    coalesce(sum(t.amount) filter(where t.direction='out'),0)::bigint as total_out
  from public.cash_accounts a left join public.cash_transactions t on t.account_id=a.id and t.status='validated'
  where a.is_active=true group by a.id,a.code,a.name,a.kind,a.opening_balance order by a.name;
end $$;

create or replace function public.create_expense(
  p_expense_date date,
  p_category_id uuid,
  p_beneficiary text,
  p_description text,
  p_amount bigint,
  p_account_id uuid,
  p_payment_method public.payment_method,
  p_external_reference text default null,
  p_document_path text default null
)
returns public.expenses
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_year integer := extract(year from coalesce(p_expense_date,current_date))::integer;
  v_next bigint;
  v_expense public.expenses%rowtype;
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then
    raise exception 'Création de dépense réservée à la comptabilité ou à l’administration';
  end if;
  if p_expense_date is null or p_category_id is null or p_account_id is null then raise exception 'Date, catégorie et compte obligatoires'; end if;
  if coalesce(trim(p_beneficiary),'')='' or coalesce(trim(p_description),'')='' then raise exception 'Bénéficiaire et désignation obligatoires'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Le montant doit être un entier positif en FCFA'; end if;
  if not exists(select 1 from public.expense_categories where id=p_category_id and is_active) then raise exception 'Catégorie inactive ou introuvable'; end if;
  if not exists(select 1 from public.cash_accounts where id=p_account_id and is_active) then raise exception 'Compte inactif ou introuvable'; end if;

  insert into public.expense_sequences(sequence_year,last_value) values(v_year,0) on conflict(sequence_year) do nothing;
  update public.expense_sequences set last_value=last_value+1,updated_at=now() where sequence_year=v_year returning last_value into v_next;

  insert into public.expenses(expense_number,expense_date,category_id,beneficiary,description,amount,account_id,payment_method,external_reference,document_path,status,created_by)
  values('DEP-'||v_year::text||'-'||lpad(v_next::text,6,'0'),p_expense_date,p_category_id,trim(p_beneficiary),trim(p_description),p_amount,p_account_id,p_payment_method,nullif(trim(p_external_reference),''),p_document_path,'draft',v_uid)
  returning * into v_expense;

  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'create_expense','expenses',v_expense.id::text,jsonb_build_object('expense_number',v_expense.expense_number,'amount',v_expense.amount,'status','draft'));
  return v_expense;
end $$;

-- Remplace la validation de dépense pour contrôler le solde disponible et l'idempotence.
create or replace function public.validate_expense(p_expense_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_expense public.expenses%rowtype;
  v_balance bigint;
  v_uid uuid := (select auth.uid());
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Accès refusé'; end if;
  select * into v_expense from public.expenses where id=p_expense_id for update;
  if not found then raise exception 'Dépense introuvable'; end if;
  if v_expense.status<>'draft' then raise exception 'Seule une dépense en brouillon peut être validée'; end if;
  perform 1 from public.cash_accounts where id=v_expense.account_id and is_active=true for update;
  if not found then raise exception 'Compte inactif ou introuvable'; end if;
  if exists(select 1 from public.cash_transactions where expense_id=v_expense.id and transaction_type='expense') then raise exception 'Un mouvement existe déjà pour cette dépense'; end if;
  v_balance := public.current_account_balance(v_expense.account_id, (v_expense.expense_date::timestamp at time zone 'UTC') + interval '1 day' - interval '1 microsecond');
  if v_balance < v_expense.amount then raise exception 'Solde insuffisant à la date de la dépense : disponible %, demandé %',v_balance,v_expense.amount; end if;

  update public.expenses set status='validated',validated_at=now(),validated_by=v_uid where id=p_expense_id;
  insert into public.cash_transactions(account_id,transaction_date,direction,amount,transaction_type,expense_id,reference,description,status,created_by,validated_at,validated_by)
  values(v_expense.account_id,(v_expense.expense_date::timestamp at time zone 'UTC'),'out',v_expense.amount,'expense',v_expense.id,v_expense.expense_number,v_expense.description,'validated',v_uid,now(),v_uid);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'validate_expense','expenses',p_expense_id::text,jsonb_build_object('amount',v_expense.amount,'expense_number',v_expense.expense_number,'account_id',v_expense.account_id));
end $$;

create or replace function public.cancel_expense(p_expense_id uuid,p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_expense public.expenses%rowtype;
  v_tx public.cash_transactions%rowtype;
  v_uid uuid := (select auth.uid());
begin
  if not public.has_any_role(array['admin','direction']::public.app_role[]) then raise exception 'Annulation réservée à la direction ou à l’administration'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Le motif d’annulation est obligatoire'; end if;
  select * into v_expense from public.expenses where id=p_expense_id for update;
  if not found then raise exception 'Dépense introuvable'; end if;
  if v_expense.status<>'validated' then raise exception 'Seule une dépense validée peut être annulée'; end if;
  select * into v_tx from public.cash_transactions where expense_id=v_expense.id and transaction_type='expense' and status='validated' for update;
  if not found then raise exception 'Mouvement d’origine introuvable'; end if;
  if exists(select 1 from public.cash_transactions where reverses_transaction_id=v_tx.id and status='validated') then raise exception 'Cette dépense a déjà été contrepassée'; end if;
  insert into public.cash_transactions(account_id,transaction_date,direction,amount,transaction_type,reverses_transaction_id,reference,description,status,created_by,validated_at,validated_by)
  values(v_tx.account_id,now(),'in',v_tx.amount,'reversal',v_tx.id,v_expense.expense_number,'Annulation dépense '||v_expense.expense_number||' : '||trim(p_reason),'validated',v_uid,now(),v_uid);
  update public.expenses set status='cancelled',cancelled_at=now(),cancellation_reason=trim(p_reason) where id=v_expense.id;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'cancel_expense','expenses',v_expense.id::text,jsonb_build_object('reason',trim(p_reason),'amount',v_expense.amount,'expense_number',v_expense.expense_number));
end $$;

-- Empêche une sortie supérieure au solde au moment du transfert.
create or replace function public.transfer_between_accounts(
  p_source_account_id uuid,p_destination_account_id uuid,p_amount bigint,p_transfer_date timestamptz,p_reference text,p_description text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_group uuid := gen_random_uuid(); v_uid uuid := (select auth.uid()); v_balance bigint; v_when timestamptz := coalesce(p_transfer_date,now());
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Accès refusé'; end if;
  if p_source_account_id=p_destination_account_id then raise exception 'Les comptes source et destination doivent être différents'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Montant invalide'; end if;
  if coalesce(trim(p_description),'')='' then raise exception 'Libellé obligatoire'; end if;
  perform 1 from public.cash_accounts where id in(p_source_account_id,p_destination_account_id) and is_active=true order by id for update;
  if (select count(*) from public.cash_accounts where id in(p_source_account_id,p_destination_account_id) and is_active=true)<>2 then raise exception 'Un compte est inactif ou introuvable'; end if;
  v_balance := public.current_account_balance(p_source_account_id,v_when);
  if v_balance<p_amount then raise exception 'Solde insuffisant pour le transfert : disponible %, demandé %',v_balance,p_amount; end if;
  insert into public.cash_transactions(account_id,transaction_date,direction,amount,transaction_type,transfer_group_id,reference,description,status,created_by,validated_at,validated_by)
  values(p_source_account_id,v_when,'out',p_amount,'transfer',v_group,nullif(trim(p_reference),''),'Transfert sortant : '||trim(p_description),'validated',v_uid,now(),v_uid),
        (p_destination_account_id,v_when,'in',p_amount,'transfer',v_group,nullif(trim(p_reference),''),'Transfert entrant : '||trim(p_description),'validated',v_uid,now(),v_uid);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details) values(v_uid,'transfer_between_accounts','cash_transactions',v_group::text,jsonb_build_object('source_account_id',p_source_account_id,'destination_account_id',p_destination_account_id,'amount',p_amount,'reference',p_reference));
  return v_group;
end $$;

revoke all on function public.current_account_balance(uuid,timestamptz) from public,anon;
revoke all on function public.get_treasury_balances() from public,anon;
revoke all on function public.create_expense(date,uuid,text,text,bigint,uuid,public.payment_method,text,text) from public,anon;
revoke all on function public.validate_expense(uuid) from public,anon;
revoke all on function public.cancel_expense(uuid,text) from public,anon;
revoke all on function public.transfer_between_accounts(uuid,uuid,bigint,timestamptz,text,text) from public,anon;
grant execute on function public.current_account_balance(uuid,timestamptz) to authenticated;
grant execute on function public.get_treasury_balances() to authenticated;
grant execute on function public.create_expense(date,uuid,text,text,bigint,uuid,public.payment_method,text,text) to authenticated;
grant execute on function public.validate_expense(uuid) to authenticated;
grant execute on function public.cancel_expense(uuid,text) to authenticated;
grant execute on function public.transfer_between_accounts(uuid,uuid,bigint,timestamptz,text,text) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 008_achats_patrimoine_workflows.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — Migration 008 : workflows Achats & Patrimoine
-- Sécurité : les fonctions SECURITY DEFINER utilisent un search_path vide et des références de schéma qualifiées.
-- À exécuter après les migrations 001 à 007, uniquement en environnement de test avant production.

-- Catégories de biens initiales, idempotentes.
insert into public.asset_categories(code, name, useful_life_months)
values
 ('INFO','Matériel informatique',48),
 ('MOB','Mobilier scolaire et de bureau',120),
 ('PED','Matériel pédagogique',60),
 ('ELEC','Équipements électriques',60),
 ('IMM','Installations et aménagements',120),
 ('AUT','Autres biens',60)
on conflict (code) do nothing;

-- RLS de décision des demandes : le demandeur ne peut pas décider sa propre demande.
create policy purchase_requests_submit_own_draft
on public.purchase_requests for update to authenticated
using (status = 'draft' and requested_by = (select auth.uid()))
with check (requested_by = (select auth.uid()) and status in ('draft','submitted'));

create policy purchase_requests_decision
on public.purchase_requests for update to authenticated
using (status = 'submitted' and public.has_any_role(array['admin','direction']::public.app_role[]))
with check (status in ('approved','rejected') and public.has_any_role(array['admin','direction']::public.app_role[]));

-- Soumission atomique d'une demande : vérifie la présence d'au moins une ligne.
create or replace function public.submit_purchase_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_request public.purchase_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  select * into v_request from public.purchase_requests where id = p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if v_request.requested_by <> auth.uid() and not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Vous ne pouvez pas soumettre cette demande';
  end if;
  if v_request.status <> 'draft' then raise exception 'Seule une demande en brouillon peut être soumise'; end if;
  if not exists(select 1 from public.purchase_request_lines where request_id = p_request_id) then
    raise exception 'Ajoutez au moins une ligne avant la soumission';
  end if;
  update public.purchase_requests set status='submitted', submitted_at=now()
  where id=p_request_id;
end;
$$;

-- Décision de la direction/admin avec note obligatoire en cas de refus.
create or replace function public.decide_purchase_request(
  p_request_id uuid, p_approve boolean, p_decision_note text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_status public.purchase_status;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Autorisation direction ou administrateur requise';
  end if;
  select status into v_status from public.purchase_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if v_status <> 'submitted' then raise exception 'La demande doit être soumise avant décision'; end if;
  if not p_approve and nullif(trim(coalesce(p_decision_note,'')),'') is null then
    raise exception 'Le motif du refus est obligatoire';
  end if;
  update public.purchase_requests
  set status = case when p_approve then 'approved'::public.purchase_status else 'rejected'::public.purchase_status end,
      approved_by = case when p_approve then auth.uid() else null end,
      approved_at = case when p_approve then now() else null end,
      decision_note = nullif(trim(coalesce(p_decision_note,'')),'')
  where id=p_request_id;
end;
$$;

-- Crée un bon de commande à partir d'une demande approuvée et copie ses lignes.
-- Aucun mouvement de trésorerie n'est créé ici : le règlement doit passer par Dépenses.
create or replace function public.create_order_from_request(
  p_request_id uuid, p_supplier_id uuid, p_order_number text,
  p_ordered_on date default current_date, p_expected_delivery_on date default null, p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_request public.purchase_requests%rowtype; v_order_id uuid; v_total bigint;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]) then
    raise exception 'Autorisation achats/comptabilité requise';
  end if;
  select * into v_request from public.purchase_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if v_request.status <> 'approved' then raise exception 'La demande doit être approuvée'; end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and is_active) then raise exception 'Fournisseur invalide ou inactif'; end if;
  if exists(select 1 from public.purchase_orders where request_id=p_request_id and status <> 'cancelled') then
    raise exception 'Un bon de commande existe déjà pour cette demande';
  end if;
  if nullif(trim(coalesce(p_order_number,'')),'') is null then raise exception 'Référence de commande obligatoire'; end if;
  select coalesce(sum(round(quantity * estimated_unit_price)),0)::bigint into v_total
  from public.purchase_request_lines where request_id=p_request_id;
  if v_total <= 0 then raise exception 'Le montant de la commande doit être positif'; end if;
  insert into public.purchase_orders(order_number,request_id,supplier_id,ordered_on,expected_delivery_on,status,total_amount,created_by,notes)
  values(trim(p_order_number),p_request_id,p_supplier_id,coalesce(p_ordered_on,current_date),p_expected_delivery_on,'ordered',v_total,auth.uid(),p_notes)
  returning id into v_order_id;
  insert into public.purchase_order_lines(purchase_order_id,description,item_kind,quantity_ordered,unit_price)
  select v_order_id,description,item_kind,quantity,estimated_unit_price
  from public.purchase_request_lines where request_id=p_request_id;
  update public.purchase_requests set status='ordered' where id=p_request_id;
  return v_order_id;
end;
$$;

revoke all on function public.submit_purchase_request(uuid) from public;
revoke all on function public.decide_purchase_request(uuid,boolean,text) from public;
revoke all on function public.create_order_from_request(uuid,uuid,text,date,date,text) from public;
grant execute on function public.submit_purchase_request(uuid) to authenticated;
grant execute on function public.decide_purchase_request(uuid,boolean,text) to authenticated;
grant execute on function public.create_order_from_request(uuid,uuid,text,date,date,text) to authenticated;

comment on function public.create_order_from_request(uuid,uuid,text,date,date,text) is
'Crée un bon de commande et ses lignes à partir d’une demande approuvée. Ne génère aucun mouvement de trésorerie.';

-- Réception partielle ou complète des lignes d'un bon de commande.
create or replace function public.receive_purchase_order(
  p_order_id uuid, p_receipt_number text, p_lines jsonb, p_delivery_reference text default null, p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_order public.purchase_orders%rowtype; v_receipt_id uuid; v_line jsonb; v_line_id uuid; v_qty numeric(12,3); v_order_line public.purchase_order_lines%rowtype; v_all_received boolean;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]) then
    raise exception 'Autorisation réception requise';
  end if;
  select * into v_order from public.purchase_orders where id=p_order_id for update;
  if not found then raise exception 'Bon de commande introuvable'; end if;
  if v_order.status not in ('ordered','partially_received') then raise exception 'Ce bon de commande ne peut pas être réceptionné'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines)=0 then raise exception 'Ajoutez au moins une ligne reçue'; end if;
  insert into public.goods_receipts(receipt_number,purchase_order_id,received_by,delivery_reference,notes,status)
  values(trim(p_receipt_number),p_order_id,auth.uid(),p_delivery_reference,p_notes,'draft') returning id into v_receipt_id;
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_id := (v_line->>'line_id')::uuid;
    v_qty := (v_line->>'quantity_received')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantité reçue invalide'; end if;
    select * into v_order_line from public.purchase_order_lines where id=v_line_id and purchase_order_id=p_order_id for update;
    if not found then raise exception 'Ligne absente de ce bon de commande'; end if;
    if v_order_line.quantity_received + v_qty > v_order_line.quantity_ordered then raise exception 'La quantité reçue dépasse la quantité commandée pour %', v_order_line.description; end if;
    insert into public.goods_receipt_lines(goods_receipt_id,purchase_order_line_id,quantity_received,condition_note)
    values(v_receipt_id,v_line_id,v_qty,nullif(v_line->>'condition_note',''));
    update public.purchase_order_lines set quantity_received=quantity_received+v_qty where id=v_line_id;
  end loop;
  update public.goods_receipts set status='validated' where id=v_receipt_id;
  select bool_and(quantity_received >= quantity_ordered) into v_all_received from public.purchase_order_lines where purchase_order_id=p_order_id;
  update public.purchase_orders set status=case when v_all_received then 'received'::public.purchase_status else 'partially_received'::public.purchase_status end where id=p_order_id;
  return v_receipt_id;
end;
$$;
revoke all on function public.receive_purchase_order(uuid,text,jsonb,text,text) from public;
grant execute on function public.receive_purchase_order(uuid,text,jsonb,text,text) to authenticated;

-- Transfert atomique : journal de mouvement et mise à jour de l'emplacement dans une transaction.
create or replace function public.transfer_asset_location(
  p_asset_id uuid, p_to_location text, p_reason text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_asset public.assets%rowtype;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Autorisation patrimoine requise';
  end if;
  if nullif(trim(coalesce(p_to_location,'')),'') is null or nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Destination et motif obligatoires';
  end if;
  select * into v_asset from public.assets where id=p_asset_id for update;
  if not found then raise exception 'Bien introuvable'; end if;
  if v_asset.status in ('disposed','retired','lost') then raise exception 'Ce bien ne peut pas être transféré'; end if;
  insert into public.asset_movements(asset_id,movement_kind,from_location,to_location,reason,created_by)
  values(p_asset_id,'transfer',v_asset.location,trim(p_to_location),trim(p_reason),auth.uid());
  update public.assets set location=trim(p_to_location),updated_at=now() where id=p_asset_id;
end;
$$;
revoke all on function public.transfer_asset_location(uuid,text,text) from public;
grant execute on function public.transfer_asset_location(uuid,text,text) to authenticated;

-- Permet à l'auteur de retirer un brouillon incomplet créé avant un échec de ligne.
create policy purchase_requests_delete_own_draft
on public.purchase_requests for delete to authenticated
using (status='draft' and requested_by=(select auth.uid()));
COMMIT;

-- ============================================================
-- MIGRATION 009_securite_parametres_imports.sql
-- ============================================================
BEGIN;
-- EPC BETHEL - Etape 5 : paramètres atomiques et permissions d'administration.
-- À appliquer après les migrations 001 à 008 sur un projet de développement.

create or replace function public.save_school_settings(
  p_school_name text,
  p_phone text default null,
  p_email text default null,
  p_address text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Autorisation insuffisante pour modifier les paramètres de l’établissement.' using errcode='42501';
  end if;
  if nullif(trim(p_school_name),'') is null or length(trim(p_school_name)) > 180 then
    raise exception 'Le nom de l’établissement est obligatoire (180 caractères maximum).';
  end if;
  if p_email is not null and trim(p_email) <> '' and p_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Adresse e-mail invalide.';
  end if;
  select id into v_id from public.school_settings order by created_at limit 1 for update;
  if v_id is null then
    insert into public.school_settings(school_name,phone,email,address)
    values(trim(p_school_name),nullif(trim(p_phone),''),nullif(trim(p_email),''),nullif(trim(p_address),'')) returning id into v_id;
  else
    update public.school_settings set school_name=trim(p_school_name),phone=nullif(trim(p_phone),''),email=nullif(trim(p_email),''),address=nullif(trim(p_address),''),updated_at=now() where id=v_id;
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(auth.uid(),'school_settings.updated','school_settings',v_id::text,jsonb_build_object('school_name',trim(p_school_name)));
  return v_id;
end; $$;

create or replace function public.save_school_year(
  p_id uuid,
  p_label text,
  p_starts_on date,
  p_ends_on date,
  p_is_current boolean default false
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Autorisation insuffisante pour modifier les années scolaires.' using errcode='42501';
  end if;
  if nullif(trim(p_label),'') is null or length(trim(p_label)) > 30 then raise exception 'Libellé d’année scolaire invalide.'; end if;
  if p_starts_on is null or p_ends_on is null or p_ends_on <= p_starts_on then raise exception 'La date de fin doit être postérieure à la date de début.'; end if;
  if p_id is null then
    insert into public.school_years(label,starts_on,ends_on,is_current,created_by)
    values(trim(p_label),p_starts_on,p_ends_on,false,auth.uid()) returning id into v_id;
  else
    update public.school_years set label=trim(p_label),starts_on=p_starts_on,ends_on=p_ends_on,is_current=false where id=p_id and not is_closed returning id into v_id;
    if v_id is null then raise exception 'Année scolaire introuvable ou clôturée.'; end if;
  end if;
  if p_is_current then
    update public.school_years set is_current=false where is_current=true and id<>v_id;
    update public.school_years set is_current=true where id=v_id;
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(auth.uid(),'school_year.saved','school_years',v_id::text,jsonb_build_object('label',trim(p_label),'is_current',p_is_current));
  return v_id;
end; $$;

revoke all on function public.save_school_settings(text,text,text,text) from public;
revoke all on function public.save_school_year(uuid,text,date,date,boolean) from public;
grant execute on function public.save_school_settings(text,text,text,text) to authenticated;
grant execute on function public.save_school_year(uuid,text,date,date,boolean) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 010_add_observateur_role.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — ajoute le rôle de consultation seule.
-- À appliquer après les migrations 001 à 009.
alter type public.app_role add value if not exists 'observateur';
-- Utilisé par le niveau d’accès Modification (tous les modules métier, sans administration des comptes).
alter type public.app_role add value if not exists 'modification';
COMMIT;

-- ============================================================
-- MIGRATION 011_auth_admin_and_observer_access.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — authentification sécurisée, rôles et accès observateur.
-- À appliquer après 010_add_observateur_role.sql sur le projet Supabase ciblé.

-- Création automatique du profil : les comptes commencent en lecture seule.
alter table public.profiles alter column role set default 'observateur'::public.app_role;
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Utilisateur'
  );
  insert into public.profiles (id, full_name, role, is_active)
  values (new.id, v_name, 'observateur'::public.app_role, true)
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_auth_user() from public;
drop trigger if exists on_auth_user_created_epc_profile on auth.users;
create trigger on_auth_user_created_epc_profile
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- Crée les profils manquants des utilisateurs déjà présents, sans privilège admin implicite.
-- Le premier administrateur sera initialisé explicitement après l'installation, via bootstrap_epc_admin().
insert into public.profiles (id, full_name, role, is_active)
select
  u.id,
  coalesce(nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''), nullif(split_part(coalesce(u.email, ''), '@', 1), ''), 'Utilisateur'),
  'observateur'::public.app_role,
  true
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;

-- Le niveau Modification autorise l'écriture dans les modules métier, comme dans GMP,
-- mais ne remplace jamais l'administrateur pour les politiques qui exigent exclusivement admin.
create or replace function public.has_any_role(allowed public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.is_active = true
      and (
        p.role = any(allowed)
        or (
          p.role = 'modification'::public.app_role
          and not (
            coalesce(cardinality(allowed), 0) = 1
            and allowed[1] = 'admin'::public.app_role
          )
        )
      )
  );
$$;
revoke all on function public.has_any_role(public.app_role[]) from public;
grant execute on function public.has_any_role(public.app_role[]) to authenticated;

-- Fonctions d'identification de l'administrateur (rôle actif en base).
create or replace function public.is_primary_epc_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.app_role
      and p.is_active = true
  );
$$;
revoke all on function public.is_primary_epc_admin() from public;
grant execute on function public.is_primary_epc_admin() to authenticated;


-- Changement de rôle et d'activation effectué avec l'identité authentifiée de l'administrateur.
create or replace function public.update_profile_access(
  p_user_id uuid,
  p_role public.app_role,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_role public.app_role;
begin
  if not public.is_primary_epc_admin() then
    raise exception 'Accès réservé à un administrateur actif.' using errcode = '42501';
  end if;
  if p_role not in ('observateur'::public.app_role, 'modification'::public.app_role) then
    raise exception 'Le rôle administrateur doit être attribué depuis Paramètres.' using errcode = '42501';
  end if;
  select p.role into v_current_role from public.profiles p where p.id = p_user_id for update;
  if not found then raise exception 'Utilisateur introuvable.' using errcode = 'P0002'; end if;
  if v_current_role = 'admin'::public.app_role then
    raise exception 'Le compte administrateur doit être transféré depuis Paramètres.' using errcode = '42501';
  end if;
  update public.profiles set role = p_role, is_active = p_is_active, updated_at = now() where id = p_user_id;
end;
$$;
revoke all on function public.update_profile_access(uuid,public.app_role,boolean) from public, anon;
grant execute on function public.update_profile_access(uuid,public.app_role,boolean) to authenticated;

-- Empêche de rétrograder/désactiver l'administrateur principal ou de créer un second admin.
create or replace function public.guard_epc_profile_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_transfer boolean := coalesce(current_setting('epc.admin_transfer', true), '') = 'on';
begin
  if new.id is distinct from old.id then
    raise exception 'L’identifiant d’un profil ne peut pas être modifié.' using errcode = '42501';
  end if;
  if v_admin_transfer then return new; end if;
  if old.role = 'admin'::public.app_role then
    if new.role is distinct from 'admin'::public.app_role or new.is_active is distinct from true then
      raise exception 'Transférez l’administration depuis Paramètres avant de modifier ce profil.' using errcode = '42501';
    end if;
  elsif new.role = 'admin'::public.app_role then
    raise exception 'Le rôle administrateur ne peut être attribué que depuis Paramètres.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_epc_profile_access() from public;
drop trigger if exists guard_epc_profile_access_trigger on public.profiles;
create trigger guard_epc_profile_access_trigger
before update of id, role, is_active on public.profiles
for each row execute function public.guard_epc_profile_access();

-- Protège aussi les INSERT directs : aucune autre identité ne peut créer un profil admin.
create or replace function public.guard_epc_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role = 'admin'::public.app_role and coalesce(current_setting('epc.admin_transfer', true), '') <> 'on' then
    raise exception 'Un profil administrateur ne peut pas être créé directement.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_epc_profile_insert() from public;
drop trigger if exists guard_epc_profile_insert_trigger on public.profiles;
create trigger guard_epc_profile_insert_trigger
before insert on public.profiles
for each row execute function public.guard_epc_profile_insert();

-- Un profil admin ne peut pas être supprimé pour éviter de perdre le contrôle du système.
create or replace function public.guard_epc_profile_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'admin'::public.app_role then
    raise exception 'Transférez l’administration avant de supprimer ce profil.' using errcode = '42501';
  end if;
  return old;
end;
$$;
revoke all on function public.guard_epc_profile_delete() from public;
drop trigger if exists guard_epc_profile_delete_trigger on public.profiles;
create trigger guard_epc_profile_delete_trigger
before delete on public.profiles
for each row execute function public.guard_epc_profile_delete();

-- Enregistre les changements de rôle/état dans le journal d'audit.
create or replace function public.audit_epc_profile_access_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (old.role is distinct from new.role or old.is_active is distinct from new.is_active)
     and (select auth.uid()) is not null then
    insert into public.audit_logs (actor_id, action, entity_table, entity_id, details)
    values (
      (select auth.uid()),
      case
        when old.role is distinct from new.role then 'profile_role_changed'
        when old.is_active and not new.is_active then 'profile_deactivated'
        else 'profile_reactivated'
      end,
      'profiles',
      new.id::text,
      jsonb_build_object(
        'old_role', old.role,
        'new_role', new.role,
        'old_is_active', old.is_active,
        'new_is_active', new.is_active
      )
    );
  end if;
  return new;
end;
$$;

revoke all on function public.audit_epc_profile_access_change() from public;
drop trigger if exists audit_epc_profile_access_change_trigger on public.profiles;
create trigger audit_epc_profile_access_change_trigger
after update of role, is_active on public.profiles
for each row execute function public.audit_epc_profile_access_change();

-- La politique historique autorisait un administrateur à toucher toutes les colonnes du profil.
-- Le garde-fou ci-dessus protège le rôle et l'état du compte principal même contre un UPDATE direct.

-- L'administration des comptes et des journaux reste réservée à l'administrateur principal,
-- même si un autre utilisateur possède le niveau Modification sur les modules métier.
drop policy if exists profiles_select_self_or_management on public.profiles;
create policy profiles_select_self_or_admin on public.profiles
for select to authenticated
using (id = (select auth.uid()) or public.is_primary_epc_admin());

drop policy if exists audit_logs_read on public.audit_logs;
create policy audit_logs_read_admin_only on public.audit_logs
for select to authenticated
using (public.is_primary_epc_admin());

drop policy if exists role_permissions_read on public.role_permissions;
create policy role_permissions_read_admin_only on public.role_permissions
for select to authenticated
using (public.is_primary_epc_admin());
drop policy if exists permissions_read on public.permissions;
create policy permissions_read_admin_only on public.permissions
for select to authenticated
using (public.is_primary_epc_admin());

-- Autorise les observateurs à consulter les données métier, sans ajouter de politiques d'écriture.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'school_settings','school_years','classes','students','guardians','student_guardians',
    'enrollments','fee_categories','student_charges','installments','cash_accounts','payments',
    'payment_allocations','expense_categories','expenses','cash_transactions','bank_statement_imports',
    'bank_statement_lines','bank_reconciliations','receipt_sequences','expense_sequences',
    'import_batches','import_rows','enrollment_concessions','concession_events','suppliers',
    'purchase_requests','purchase_request_lines','purchase_orders','purchase_order_lines',
    'goods_receipts','goods_receipt_lines','asset_categories','assets','asset_movements',
    'asset_inventory_sessions','asset_inventory_lines','asset_maintenance','purchase_expense_links'
  ] loop
    if to_regclass('public.' || v_table) is not null then
      execute format('alter table public.%I enable row level security', v_table);
      execute format('drop policy if exists epc_observer_read_only on public.%I', v_table);
      execute format(
        'create policy epc_observer_read_only on public.%I for select to authenticated using (public.has_any_role(array[''observateur'']::public.app_role[]))',
        v_table
      );
    end if;
  end loop;
end;
$$;


-- Autorise les observateurs à lire les soldes via la fonction de consultation de trésorerie.
create or replace function public.get_treasury_balances()
returns table(
  account_id uuid,
  account_code text,
  account_name text,
  account_kind public.account_kind,
  opening_balance bigint,
  balance bigint,
  total_in bigint,
  total_out bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé';
  end if;
  return query
  select
    a.id,
    a.code,
    a.name,
    a.kind,
    a.opening_balance,
    (coalesce(a.opening_balance,0) + coalesce(sum(case when t.direction='in' then t.amount else -t.amount end),0))::bigint as balance,
    coalesce(sum(t.amount) filter (where t.direction='in'),0)::bigint as total_in,
    coalesce(sum(t.amount) filter (where t.direction='out'),0)::bigint as total_out
  from public.cash_accounts a
  left join public.cash_transactions t on t.account_id=a.id and t.status='validated'
  where a.is_active=true
  group by a.id,a.code,a.name,a.kind,a.opening_balance
  order by a.name;
end;
$$;
revoke all on function public.get_treasury_balances() from public, anon;
grant execute on function public.get_treasury_balances() to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 012_school_management_completion.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — Étape 3 : gestion scolaire complète
-- Dossiers élèves modifiables, responsables légaux, inscriptions, transferts et classes.
-- À appliquer après les migrations 001 à 011 sur un environnement sauvegardé.

-- Remplace l'ancienne signature afin d'enregistrer aussi les coordonnées du responsable légal.
drop function if exists public.create_student_with_guardian(text,text,text,text,date,text,text,text,text,text);

create function public.create_student_with_guardian(
  p_student_number text,
  p_last_name text,
  p_first_names text,
  p_sex text default null,
  p_birth_date date default null,
  p_birth_place text default null,
  p_guardian_name text default null,
  p_guardian_phone text default null,
  p_guardian_address text default null,
  p_notes text default null,
  p_guardian_email text default null,
  p_guardian_occupation text default null,
  p_guardian_relationship text default 'Responsable légal'
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_student uuid;
  v_guardian uuid;
  v_number text;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à créer un dossier élève' using errcode = '42501';
  end if;
  if nullif(trim(p_last_name),'') is null or nullif(trim(p_first_names),'') is null then
    raise exception 'Le nom et les prénoms sont obligatoires';
  end if;
  if p_sex is not null and p_sex not in ('F','M','X') then raise exception 'Sexe invalide'; end if;
  if p_birth_date is not null and p_birth_date > current_date then raise exception 'La date de naissance ne peut pas être future'; end if;
  v_number := nullif(trim(p_student_number),'');
  if v_number is null then
    loop
      v_number := 'EPC-'||to_char(current_date,'YYYY')||'-'||upper(substr(replace(pg_catalog.gen_random_uuid()::text,'-',''),1,8));
      exit when not exists(select 1 from public.students s where s.student_number=v_number);
    end loop;
  end if;
  insert into public.students(student_number,last_name,first_names,sex,birth_date,birth_place,notes,created_by)
  values(v_number,trim(p_last_name),trim(p_first_names),p_sex,p_birth_date,nullif(trim(p_birth_place),''),nullif(trim(p_notes),''),v_user)
  returning id into v_student;
  if nullif(trim(p_guardian_name),'') is not null then
    insert into public.guardians(full_name,phone,email,address,occupation,created_by)
    values(trim(p_guardian_name),nullif(trim(p_guardian_phone),''),nullif(trim(p_guardian_email),''),nullif(trim(p_guardian_address),''),nullif(trim(p_guardian_occupation),''),v_user)
    returning id into v_guardian;
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary,receives_messages)
    values(v_student,v_guardian,coalesce(nullif(trim(p_guardian_relationship),''),'Responsable légal'),true,true);
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'student.created','students',v_student::text,jsonb_build_object('student_number',v_number,'has_guardian',nullif(trim(p_guardian_name),'') is not null));
  return v_student;
end;
$$;
revoke all on function public.create_student_with_guardian(text,text,text,text,date,text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.create_student_with_guardian(text,text,text,text,date,text,text,text,text,text,text,text,text) to authenticated;

-- Mise à jour atomique du dossier et du responsable légal principal.
create or replace function public.update_student_with_guardian(
  p_student_id uuid,
  p_student_number text,
  p_last_name text,
  p_first_names text,
  p_sex text default null,
  p_birth_date date default null,
  p_birth_place text default null,
  p_guardian_name text default null,
  p_guardian_phone text default null,
  p_guardian_address text default null,
  p_notes text default null,
  p_guardian_email text default null,
  p_guardian_occupation text default null,
  p_guardian_relationship text default 'Responsable légal'
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_guardian_id uuid;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à modifier un dossier élève' using errcode = '42501';
  end if;
  if p_student_id is null then raise exception 'Dossier élève manquant'; end if;
  if nullif(trim(p_student_number),'') is null or nullif(trim(p_last_name),'') is null or nullif(trim(p_first_names),'') is null then
    raise exception 'Le matricule, le nom et les prénoms sont obligatoires';
  end if;
  if p_sex is not null and p_sex not in ('F','M','X') then raise exception 'Sexe invalide'; end if;
  if p_birth_date is not null and p_birth_date > current_date then raise exception 'La date de naissance ne peut pas être future'; end if;
  update public.students
  set student_number = trim(p_student_number), last_name = trim(p_last_name), first_names = trim(p_first_names),
      sex = p_sex, birth_date = p_birth_date, birth_place = nullif(trim(p_birth_place),''),
      notes = nullif(trim(p_notes),''), updated_at = now()
  where id = p_student_id;
  if not found then raise exception 'Élève introuvable' using errcode = 'P0002'; end if;

  select sg.guardian_id into v_guardian_id
  from public.student_guardians sg
  where sg.student_id = p_student_id and sg.is_primary = true
  limit 1 for update;

  if nullif(trim(p_guardian_name),'') is null then
    delete from public.student_guardians where student_id = p_student_id and is_primary = true;
  elsif v_guardian_id is null then
    insert into public.guardians(full_name,phone,email,address,occupation,created_by)
    values(trim(p_guardian_name),nullif(trim(p_guardian_phone),''),nullif(trim(p_guardian_email),''),nullif(trim(p_guardian_address),''),nullif(trim(p_guardian_occupation),''),v_user)
    returning id into v_guardian_id;
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary,receives_messages)
    values(p_student_id,v_guardian_id,coalesce(nullif(trim(p_guardian_relationship),''),'Responsable légal'),true,true);
  else
    update public.guardians set full_name = trim(p_guardian_name), phone = nullif(trim(p_guardian_phone),''),
      email = nullif(trim(p_guardian_email),''), address = nullif(trim(p_guardian_address),''),
      occupation = nullif(trim(p_guardian_occupation),'') where id = v_guardian_id;
    update public.student_guardians set relationship = coalesce(nullif(trim(p_guardian_relationship),''),'Responsable légal'), is_primary = true
    where student_id = p_student_id and guardian_id = v_guardian_id;
  end if;

  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'student.updated','students',p_student_id::text,jsonb_build_object('student_number',trim(p_student_number),'guardian_updated',true));
end;
$$;
revoke all on function public.update_student_with_guardian(uuid,text,text,text,text,date,text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.update_student_with_guardian(uuid,text,text,text,text,date,text,text,text,text,text,text,text,text) to authenticated;

-- Création contrôlée d'une inscription ou réinscription dans une année non clôturée.
create or replace function public.create_school_enrollment(
  p_student_id uuid,
  p_school_year_id uuid,
  p_class_id uuid,
  p_enrolled_on date default current_date,
  p_enrollment_type text default 'inscrit',
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_enrollment uuid;
  v_year_label text;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à inscrire un élève' using errcode = '42501';
  end if;
  if p_student_id is null or p_school_year_id is null or p_class_id is null then
    raise exception 'L’élève, l’année scolaire et la classe sont obligatoires';
  end if;
  if p_enrollment_type is null or p_enrollment_type not in ('inscrit','reinscrit') then raise exception 'Type d’inscription invalide'; end if;
  if not exists(select 1 from public.students s where s.id=p_student_id and s.status='actif'::public.student_status) then
    raise exception 'L’élève n’existe pas ou son dossier n’est pas actif';
  end if;
  select sy.label into v_year_label from public.school_years sy where sy.id=p_school_year_id and sy.is_current and not sy.is_closed;
  if not found then raise exception 'Sélectionnez l’année scolaire active et non clôturée'; end if;
  if not exists(select 1 from public.classes c where c.id=p_class_id and c.is_active) then
    raise exception 'La classe n’existe pas ou n’est plus active';
  end if;
  insert into public.enrollments(student_id,school_year_id,class_id,enrolled_on,status,notes,created_by)
  values(p_student_id,p_school_year_id,p_class_id,coalesce(p_enrolled_on,current_date),p_enrollment_type,nullif(trim(p_notes),''),v_user)
  returning id into v_enrollment;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'enrollment.created','enrollments',v_enrollment::text,jsonb_build_object('student_id',p_student_id,'school_year_id',p_school_year_id,'school_year_label',v_year_label,'class_id',p_class_id,'status',p_enrollment_type));
  return v_enrollment;
end;
$$;
revoke all on function public.create_school_enrollment(uuid,uuid,uuid,date,text,text) from public, anon;
grant execute on function public.create_school_enrollment(uuid,uuid,uuid,date,text,text) to authenticated;

-- Changement de classe dans l'établissement : met à jour l'inscription existante et écrit l'historique.
create or replace function public.transfer_student_class(
  p_enrollment_id uuid,
  p_target_class_id uuid,
  p_transfer_date date default current_date,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_student_id uuid;
  v_year_id uuid;
  v_source_class_id uuid;
  v_status text;
  v_source_name text;
  v_target_name text;
  v_year_current boolean;
  v_year_closed boolean;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à transférer un élève' using errcode = '42501';
  end if;
  select e.student_id,e.school_year_id,e.class_id,e.status,sy.is_current,sy.is_closed,c.name
    into v_student_id,v_year_id,v_source_class_id,v_status,v_year_current,v_year_closed,v_source_name
  from public.enrollments e
  join public.school_years sy on sy.id=e.school_year_id
  join public.classes c on c.id=e.class_id
  where e.id=p_enrollment_id for update of e;
  if not found then raise exception 'Inscription introuvable' using errcode = 'P0002'; end if;
  if v_status not in ('inscrit','reinscrit') then raise exception 'Seule une inscription active peut changer de classe'; end if;
  if not v_year_current or v_year_closed then raise exception 'Le changement de classe est réservé à une année scolaire active et non clôturée'; end if;
  select c.name into v_target_name from public.classes c where c.id=p_target_class_id and c.is_active;
  if not found then raise exception 'La nouvelle classe n’existe pas ou n’est plus active'; end if;
  if v_source_class_id=p_target_class_id then raise exception 'L’élève est déjà affecté à cette classe'; end if;
  update public.enrollments set class_id=p_target_class_id,
    notes=concat_ws(E'\n',nullif(notes,''),'Changement de classe le '||coalesce(p_transfer_date,current_date)::text||' : '||v_source_name||' → '||v_target_name||case when nullif(trim(p_reason),'') is not null then ' ; motif : '||trim(p_reason) else '' end)
  where id=p_enrollment_id;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'student.class_transferred','enrollments',p_enrollment_id::text,jsonb_build_object('student_id',v_student_id,'school_year_id',v_year_id,'from_class_id',v_source_class_id,'from_class',v_source_name,'to_class_id',p_target_class_id,'to_class',v_target_name,'transfer_date',coalesce(p_transfer_date,current_date),'reason',nullif(trim(p_reason),'')));
end;
$$;
revoke all on function public.transfer_student_class(uuid,uuid,date,text) from public, anon;
grant execute on function public.transfer_student_class(uuid,uuid,date,text) to authenticated;

-- Sortie définitive ou transfert hors de l'établissement.
create or replace function public.close_school_enrollment(
  p_enrollment_id uuid,
  p_exit_status text,
  p_exit_date date default current_date,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_student_id uuid;
  v_status text;
  v_year_current boolean;
  v_year_closed boolean;
  v_student_status public.student_status;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à clôturer une inscription' using errcode = '42501';
  end if;
  if p_exit_status is null or p_exit_status not in ('transfere','sorti') then raise exception 'Type de sortie invalide'; end if;
  v_student_status := case when p_exit_status='transfere' then 'transfere'::public.student_status else 'sorti'::public.student_status end;
  select e.student_id,e.status,sy.is_current,sy.is_closed into v_student_id,v_status,v_year_current,v_year_closed
  from public.enrollments e join public.school_years sy on sy.id=e.school_year_id
  where e.id=p_enrollment_id for update of e;
  if not found then raise exception 'Inscription introuvable' using errcode = 'P0002'; end if;
  if v_status not in ('inscrit','reinscrit') then raise exception 'Cette inscription est déjà clôturée'; end if;
  if not v_year_current or v_year_closed then raise exception 'La sortie doit être enregistrée sur une année scolaire active et non clôturée'; end if;
  update public.enrollments set status=p_exit_status,
    notes=concat_ws(E'\n',nullif(notes,''),'Sortie le '||coalesce(p_exit_date,current_date)::text||' : '||case when p_exit_status='transfere' then 'transfert vers un autre établissement' else 'sortie définitive' end||case when nullif(trim(p_reason),'') is not null then ' ; motif : '||trim(p_reason) else '' end)
  where id=p_enrollment_id;
  -- Le dossier est marqué en sortie uniquement lorsqu'aucune autre inscription active ne subsiste.
  if not exists(
    select 1 from public.enrollments e
    join public.school_years sy on sy.id=e.school_year_id
    where e.student_id=v_student_id and e.id<>p_enrollment_id
      and e.status in ('inscrit','reinscrit') and sy.is_current and not sy.is_closed
  ) then
    update public.students set status=v_student_status,updated_at=now() where id=v_student_id;
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'enrollment.closed','enrollments',p_enrollment_id::text,jsonb_build_object('student_id',v_student_id,'old_status',v_status,'exit_status',p_exit_status,'exit_date',coalesce(p_exit_date,current_date),'reason',nullif(trim(p_reason),'')));
end;
$$;
revoke all on function public.close_school_enrollment(uuid,text,date,text) from public, anon;
grant execute on function public.close_school_enrollment(uuid,text,date,text) to authenticated;

-- Gestion centralisée du référentiel des classes.
create or replace function public.save_class(
  p_id uuid,
  p_code text,
  p_name text,
  p_level_order integer,
  p_is_active boolean default true
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_code text := upper(trim(coalesce(p_code,'')));
  v_name text := trim(coalesce(p_name,''));
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à gérer les classes' using errcode = '42501';
  end if;
  if v_code='' or v_name='' or length(v_code)>20 or length(v_name)>100 then raise exception 'Code et nom de classe obligatoires (20 et 100 caractères maximum)'; end if;
  if v_code !~ '^[A-Z0-9_-]+$' then raise exception 'Le code de classe ne doit contenir que des lettres, chiffres, tirets ou soulignements'; end if;
  if p_level_order is null or p_level_order<1 or p_level_order>99 then raise exception 'Ordre du niveau invalide'; end if;
  if p_id is null then
    insert into public.classes(code,name,level_order,is_active) values(v_code,v_name,p_level_order,coalesce(p_is_active,true)) returning id into v_id;
  else
    update public.classes set code=v_code,name=v_name,level_order=p_level_order,is_active=coalesce(p_is_active,true) where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Classe introuvable' using errcode = 'P0002'; end if;
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,case when p_id is null then 'class.created' else 'class.updated' end,'classes',v_id::text,jsonb_build_object('code',v_code,'name',v_name,'level_order',p_level_order,'is_active',coalesce(p_is_active,true)));
  return v_id;
end;
$$;
revoke all on function public.save_class(uuid,text,text,integer,boolean) from public, anon;
grant execute on function public.save_class(uuid,text,text,integer,boolean) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 013_financial_integrity_reporting.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — Étape 4 : intégrité financière et agrégats calculés côté base.
-- À exécuter après les migrations 001 à 012 sur un projet de développement,
-- puis à valider avec des comptes de test avant toute utilisation en production.


-- Le solde tient compte de la date d'ouverture du compte : un solde initial futur
-- ne doit pas être considéré comme disponible avant sa date d'effet.
create or replace function public.current_account_balance(
  p_account_id uuid,
  p_at timestamptz default now()
)
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$
  select
    case
      when a.opening_date <= (p_at at time zone 'UTC')::date then coalesce(a.opening_balance,0)::bigint
      else 0::bigint
    end
    + coalesce(sum(case when t.direction='in' then t.amount else -t.amount end),0)::bigint
  from public.cash_accounts a
  left join public.cash_transactions t
    on t.account_id=a.id
   and t.status='validated'
   and t.transaction_date <= p_at
  where a.id=p_account_id
  group by a.id,a.opening_balance,a.opening_date
$$;

revoke all on function public.current_account_balance(uuid,timestamptz) from public, anon;
grant execute on function public.current_account_balance(uuid,timestamptz) to authenticated;

-- Un solde courant ne doit pas inclure d'opérations datées dans le futur.
-- Les mouvements historiques validés restent pris en compte pour préserver l'historique.
create or replace function public.get_treasury_balances()
returns table(
  account_id uuid,
  account_code text,
  account_name text,
  account_kind public.account_kind,
  opening_balance bigint,
  balance bigint,
  total_in bigint,
  total_out bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé à la consultation de la trésorerie.' using errcode = '42501';
  end if;

  return query
  select
    a.id,
    a.code,
    a.name,
    a.kind,
    a.opening_balance,
    (case when a.opening_date <= current_date then coalesce(a.opening_balance,0) else 0 end
      + coalesce(sum(case when t.direction='in' then t.amount else -t.amount end)
          filter (where t.id is not null),0))::bigint as balance,
    coalesce(sum(t.amount) filter(where t.direction='in'),0)::bigint as total_in,
    coalesce(sum(t.amount) filter(where t.direction='out'),0)::bigint as total_out
  from public.cash_accounts a
  left join public.cash_transactions t
    on t.account_id = a.id
   and t.status = 'validated'
   and t.transaction_date < ((current_date + 1)::timestamp at time zone 'UTC')
  where a.is_active = true
  group by a.id,a.code,a.name,a.kind,a.opening_balance,a.opening_date
  order by a.name;
end;
$$;

revoke all on function public.get_treasury_balances() from public, anon;
grant execute on function public.get_treasury_balances() to authenticated;


-- Encaissements, validations de dépenses et transferts : les opérations datées dans le futur
-- sont refusées côté base, même si un client contourne les contrôles d'interface.
create or replace function public.register_student_payment(
  p_enrollment_id uuid,
  p_amount bigint,
  p_method public.payment_method,
  p_account_id uuid,
  p_paid_at timestamptz default now(),
  p_payer_name text default null,
  p_external_reference text default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_receipt text;
  v_payment_id uuid;
  v_remaining bigint;
  v_total_due bigint;
  v_open bigint;
  v_charge record;
  v_installment record;
  v_take bigint;
  v_account public.cash_accounts%rowtype;
begin
  if v_user is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then
    raise exception 'Seul un administrateur ou la comptabilité peut enregistrer un encaissement';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Le montant doit être strictement positif'; end if;
  if p_enrollment_id is null then raise exception 'Sélectionnez une inscription'; end if;
  if p_paid_at is null then raise exception 'La date du paiement est obligatoire'; end if;
  if (p_paid_at at time zone 'UTC')::date > current_date then raise exception 'La date du paiement ne peut pas être dans le futur.'; end if;

  perform 1 from public.enrollments e
   where e.id = p_enrollment_id and e.status in ('inscrit','reinscrit')
   for update;
  if not found then raise exception 'Inscription active introuvable'; end if;

  select * into v_account from public.cash_accounts
   where id = p_account_id and is_active = true for update;
  if not found then raise exception 'Compte de trésorerie inactif ou introuvable'; end if;

  -- Calcule le reste à payer sur les frais validés. Les échéances sont traitées en premier,
  -- par date puis numéro; les frais ponctuels sans échéances viennent ensuite.
  select coalesce(sum(greatest(c.amount_due - coalesce(paid.amount_paid,0),0)),0)::bigint
    into v_total_due
    from public.student_charges c
    left join lateral (
      select sum(pa.amount)::bigint as amount_paid
        from public.payment_allocations pa
        join public.payments p on p.id = pa.payment_id and p.status = 'validated'
         and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
       where pa.charge_id = c.id
    ) paid on true
   where c.enrollment_id = p_enrollment_id and c.status = 'validated';

  if p_amount > v_total_due then
    raise exception 'Le versement (%) dépasse le solde total dû (%)', p_amount, v_total_due;
  end if;
  if v_total_due <= 0 then raise exception 'Aucun frais impayé pour cette inscription'; end if;

  v_receipt := public.allocate_receipt_number(p_paid_at);
  insert into public.payments(
    receipt_number,enrollment_id,paid_at,amount,method,account_id,external_reference,
    payer_name,notes,status,created_by
  ) values (
    v_receipt,p_enrollment_id,p_paid_at,p_amount,p_method,p_account_id,
    nullif(trim(p_external_reference),''),nullif(trim(p_payer_name),''),
    nullif(trim(p_notes),''),'draft',v_user
  ) returning id into v_payment_id;

  v_remaining := p_amount;

  -- 1) Echéances de scolarité, avec vérification du montant restant de chacune.
  for v_installment in
    select i.id as installment_id, i.charge_id, i.amount_due, i.due_on, i.installment_no
      from public.installments i
      join public.student_charges c on c.id = i.charge_id
     where c.enrollment_id = p_enrollment_id and c.status = 'validated'
     order by i.due_on, i.installment_no, i.id
  loop
    exit when v_remaining = 0;
    -- Seuls les paiements validés réduisent le solde de l'échéance.
    v_open := greatest(v_installment.amount_due - coalesce((
      select sum(pa.amount)::bigint from public.payment_allocations pa
      join public.payments p on p.id=pa.payment_id and p.status='validated'
        and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
      where pa.installment_id=v_installment.installment_id
    ),0),0);
    if v_open > 0 then
      v_take := least(v_open,v_remaining);
      insert into public.payment_allocations(payment_id,charge_id,installment_id,amount,created_by)
      values(v_payment_id,v_installment.charge_id,v_installment.installment_id,v_take,v_user);
      v_remaining := v_remaining-v_take;
    end if;
  end loop;

  -- 2) Frais ponctuels qui n'ont pas d'échéances.
  for v_charge in
    select c.id,c.amount_due
      from public.student_charges c
     where c.enrollment_id=p_enrollment_id and c.status='validated'
       and not exists(select 1 from public.installments i where i.charge_id=c.id)
     order by c.due_on nulls last,c.created_at,c.id
  loop
    exit when v_remaining=0;
    select greatest(v_charge.amount_due-coalesce(sum(pa.amount) filter(where p.status='validated' and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')),0),0)::bigint
      into v_open
      from public.payment_allocations pa join public.payments p on p.id=pa.payment_id
     where pa.charge_id=v_charge.id;
    if v_open>0 then
      v_take:=least(v_open,v_remaining);
      insert into public.payment_allocations(payment_id,charge_id,installment_id,amount,created_by)
      values(v_payment_id,v_charge.id,null,v_take,v_user);
      v_remaining:=v_remaining-v_take;
    end if;
  end loop;

  if v_remaining<>0 then raise exception 'Affectation automatique incomplète; opération annulée'; end if;
  perform public.validate_payment(v_payment_id);
  return jsonb_build_object('id',v_payment_id,'receipt_number',v_receipt,'amount',p_amount,'status','validated');
end;
$$;
revoke all on function public.register_student_payment(uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text) from public, anon;
grant execute on function public.register_student_payment(uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text) to authenticated;

create or replace function public.create_expense(
  p_expense_date date,
  p_category_id uuid,
  p_beneficiary text,
  p_description text,
  p_amount bigint,
  p_account_id uuid,
  p_payment_method public.payment_method,
  p_external_reference text default null,
  p_document_path text default null
)
returns public.expenses
language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_year integer := extract(year from coalesce(p_expense_date,current_date))::integer;
  v_next bigint;
  v_expense public.expenses%rowtype;
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then
    raise exception 'Création de dépense réservée à la comptabilité ou à l’administration';
  end if;
  if p_expense_date is null or p_category_id is null or p_account_id is null then raise exception 'Date, catégorie et compte obligatoires'; end if;
  if p_expense_date > current_date then raise exception 'La date d’une dépense ne peut pas être dans le futur.'; end if;
  if coalesce(trim(p_beneficiary),'')='' or coalesce(trim(p_description),'')='' then raise exception 'Bénéficiaire et désignation obligatoires'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Le montant doit être un entier positif en FCFA'; end if;
  if not exists(select 1 from public.expense_categories where id=p_category_id and is_active) then raise exception 'Catégorie inactive ou introuvable'; end if;
  if not exists(select 1 from public.cash_accounts where id=p_account_id and is_active) then raise exception 'Compte inactif ou introuvable'; end if;

  insert into public.expense_sequences(sequence_year,last_value) values(v_year,0) on conflict(sequence_year) do nothing;
  update public.expense_sequences set last_value=last_value+1,updated_at=now() where sequence_year=v_year returning last_value into v_next;

  insert into public.expenses(expense_number,expense_date,category_id,beneficiary,description,amount,account_id,payment_method,external_reference,document_path,status,created_by)
  values('DEP-'||v_year::text||'-'||lpad(v_next::text,6,'0'),p_expense_date,p_category_id,trim(p_beneficiary),trim(p_description),p_amount,p_account_id,p_payment_method,nullif(trim(p_external_reference),''),p_document_path,'draft',v_uid)
  returning * into v_expense;

  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'create_expense','expenses',v_expense.id::text,jsonb_build_object('expense_number',v_expense.expense_number,'amount',v_expense.amount,'status','draft'));
  return v_expense;
end $$;
revoke all on function public.create_expense(date,uuid,text,text,bigint,uuid,public.payment_method,text,text) from public, anon;
grant execute on function public.create_expense(date,uuid,text,text,bigint,uuid,public.payment_method,text,text) to authenticated;

create or replace function public.validate_expense(p_expense_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_expense public.expenses%rowtype;
  v_balance bigint;
  v_uid uuid := (select auth.uid());
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Accès refusé'; end if;
  select * into v_expense from public.expenses where id=p_expense_id for update;
  if not found then raise exception 'Dépense introuvable'; end if;
  if v_expense.status<>'draft' then raise exception 'Seule une dépense en brouillon peut être validée'; end if;
  if v_expense.expense_date > current_date then raise exception 'Une dépense datée dans le futur ne peut pas être validée.'; end if;
  perform 1 from public.cash_accounts where id=v_expense.account_id and is_active=true for update;
  if not found then raise exception 'Compte inactif ou introuvable'; end if;
  if exists(select 1 from public.cash_transactions where expense_id=v_expense.id and transaction_type='expense') then raise exception 'Un mouvement existe déjà pour cette dépense'; end if;
  v_balance := public.current_account_balance(v_expense.account_id, (v_expense.expense_date::timestamp at time zone 'UTC') + interval '1 day' - interval '1 microsecond');
  if v_balance < v_expense.amount then raise exception 'Solde insuffisant à la date de la dépense : disponible %, demandé %',v_balance,v_expense.amount; end if;

  update public.expenses set status='validated',validated_at=now(),validated_by=v_uid where id=p_expense_id;
  insert into public.cash_transactions(account_id,transaction_date,direction,amount,transaction_type,expense_id,reference,description,status,created_by,validated_at,validated_by)
  values(v_expense.account_id,(v_expense.expense_date::timestamp at time zone 'UTC'),'out',v_expense.amount,'expense',v_expense.id,v_expense.expense_number,v_expense.description,'validated',v_uid,now(),v_uid);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'validate_expense','expenses',p_expense_id::text,jsonb_build_object('amount',v_expense.amount,'expense_number',v_expense.expense_number,'account_id',v_expense.account_id));
end $$;
revoke all on function public.validate_expense(uuid) from public, anon;
grant execute on function public.validate_expense(uuid) to authenticated;

create or replace function public.transfer_between_accounts(
  p_source_account_id uuid,p_destination_account_id uuid,p_amount bigint,p_transfer_date timestamptz,p_reference text,p_description text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_group uuid := gen_random_uuid(); v_uid uuid := (select auth.uid()); v_balance bigint; v_when timestamptz := coalesce(p_transfer_date,now());
begin
  if not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Accès refusé'; end if;
  if p_source_account_id=p_destination_account_id then raise exception 'Les comptes source et destination doivent être différents'; end if;
  if (v_when at time zone 'UTC')::date > current_date then raise exception 'La date du transfert ne peut pas être dans le futur.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Montant invalide'; end if;
  if coalesce(trim(p_description),'')='' then raise exception 'Libellé obligatoire'; end if;
  perform 1 from public.cash_accounts where id in(p_source_account_id,p_destination_account_id) and is_active=true order by id for update;
  if (select count(*) from public.cash_accounts where id in(p_source_account_id,p_destination_account_id) and is_active=true)<>2 then raise exception 'Un compte est inactif ou introuvable'; end if;
  v_balance := public.current_account_balance(p_source_account_id,v_when);
  if v_balance<p_amount then raise exception 'Solde insuffisant pour le transfert : disponible %, demandé %',v_balance,p_amount; end if;
  insert into public.cash_transactions(account_id,transaction_date,direction,amount,transaction_type,transfer_group_id,reference,description,status,created_by,validated_at,validated_by)
  values(p_source_account_id,v_when,'out',p_amount,'transfer',v_group,nullif(trim(p_reference),''),'Transfert sortant : '||trim(p_description),'validated',v_uid,now(),v_uid),
        (p_destination_account_id,v_when,'in',p_amount,'transfer',v_group,nullif(trim(p_reference),''),'Transfert entrant : '||trim(p_description),'validated',v_uid,now(),v_uid);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details) values(v_uid,'transfer_between_accounts','cash_transactions',v_group::text,jsonb_build_object('source_account_id',p_source_account_id,'destination_account_id',p_destination_account_id,'amount',p_amount,'reference',p_reference));
  return v_group;
end $$;
revoke all on function public.transfer_between_accounts(uuid,uuid,bigint,timestamptz,text,text) from public, anon;
grant execute on function public.transfer_between_accounts(uuid,uuid,bigint,timestamptz,text,text) to authenticated;

-- Liste financière des frais : les montants payés sont agrégés dans PostgreSQL
-- sur l'ensemble des paiements validés, et non à partir d'un sous-ensemble chargé dans le navigateur.
create or replace function public.get_school_fee_ledger(
  p_school_year_id uuid default null,
  p_limit integer default 100,
  p_offset integer default 0,
  p_query text default null
)
returns table(
  charge_id uuid,
  enrollment_id uuid,
  student_name text,
  student_number text,
  class_name text,
  school_year text,
  category_name text,
  description text,
  gross_amount bigint,
  discount_amount bigint,
  amount_due bigint,
  amount_paid bigint,
  balance_due bigint,
  charge_status text,
  due_on date,
  created_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé à la consultation des frais scolaires.' using errcode = '42501';
  end if;
  if p_offset is null or p_offset < 0 then raise exception 'Le décalage de pagination est invalide.'; end if;

  return query
  with charge_rows as (
    select
      c.id as charge_id,
      c.enrollment_id,
      trim(s.last_name || ' ' || s.first_names) as student_name,
      s.student_number,
      cl.name as class_name,
      sy.label as school_year,
      fc.name as category_name,
      c.description,
      coalesce(c.gross_amount,c.amount_due)::bigint as gross_amount,
      coalesce(c.discount_amount,0)::bigint as discount_amount,
      c.amount_due::bigint as amount_due,
      coalesce(paid.amount_paid,0)::bigint as amount_paid,
      greatest(c.amount_due - coalesce(paid.amount_paid,0),0)::bigint as balance_due,
      c.status::text as charge_status,
      c.due_on,
      c.created_at
    from public.student_charges c
    join public.enrollments e on e.id = c.enrollment_id
    join public.students s on s.id = e.student_id
    join public.classes cl on cl.id = e.class_id
    join public.school_years sy on sy.id = e.school_year_id
    join public.fee_categories fc on fc.id = c.fee_category_id
    left join lateral (
      select coalesce(sum(pa.amount),0)::bigint as amount_paid
      from public.payment_allocations pa
      join public.payments p on p.id = pa.payment_id and p.status = 'validated'
        and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
      where pa.charge_id = c.id
    ) paid on true
    where c.status = 'validated'
      and (p_school_year_id is null or e.school_year_id = p_school_year_id)
      and (nullif(trim(p_query),'') is null or concat_ws(' ',s.last_name,s.first_names,s.student_number,cl.name,sy.label,fc.name,c.description) ilike '%' || trim(p_query) || '%')
  ), counted as (
    select charge_rows.*, count(*) over()::bigint as total_count from charge_rows
  )
  select
    counted.charge_id,counted.enrollment_id,counted.student_name,counted.student_number,
    counted.class_name,counted.school_year,counted.category_name,counted.description,
    counted.gross_amount,counted.discount_amount,counted.amount_due,counted.amount_paid,
    counted.balance_due,counted.charge_status,counted.due_on,counted.created_at,counted.total_count
  from counted
  order by counted.created_at desc, counted.charge_id
  limit least(greatest(coalesce(p_limit,100),1),100)
  offset p_offset;
end;
$$;

revoke all on function public.get_school_fee_ledger(uuid,integer,integer,text) from public, anon;
grant execute on function public.get_school_fee_ledger(uuid,integer,integer,text) to authenticated;

-- Liste des inscriptions qui ont un solde positif, utilisée pour éviter de charger
-- tous les frais et affectations imbriqués dans l'interface des encaissements.
create or replace function public.get_enrollment_payment_options()
returns table(
  enrollment_id uuid,
  option_label text,
  balance_due bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé à la consultation des soldes élèves.' using errcode = '42501';
  end if;

  return query
  select
    e.id,
    trim(s.last_name || ' ' || s.first_names) || ' · ' || coalesce(s.student_number,'Sans matricule') || ' · ' || cl.name || ' · ' || sy.label ||
      ' · Solde ' || to_char(balance.balance_due::numeric, 'FM999G999G999G999G990') || ' FCFA',
    balance.balance_due
  from public.enrollments e
  join public.students s on s.id=e.student_id
  join public.classes cl on cl.id=e.class_id
  join public.school_years sy on sy.id=e.school_year_id
  join lateral (
    select coalesce(sum(greatest(c.amount_due - coalesce(paid.amount_paid,0),0)),0)::bigint as balance_due
    from public.student_charges c
    left join lateral (
      select coalesce(sum(pa.amount),0)::bigint as amount_paid
      from public.payment_allocations pa
      join public.payments p on p.id=pa.payment_id and p.status='validated'
        and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
      where pa.charge_id=c.id
    ) paid on true
    where c.enrollment_id=e.id and c.status='validated'
  ) balance on true
  where e.status in ('inscrit','reinscrit')
    and s.status='actif'
    and balance.balance_due > 0
  order by s.last_name,s.first_names,sy.starts_on desc;
end;
$$;

revoke all on function public.get_enrollment_payment_options() from public, anon;
grant execute on function public.get_enrollment_payment_options() to authenticated;

-- Résumé financier exact calculé côté base. Les montants affichés sur le tableau
-- de bord ne dépendent plus des limites d'API ou du nombre de lignes téléchargées.
create or replace function public.get_financial_summary(
  p_from date default null,
  p_to date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_receipts_total bigint := 0;
  v_receipts_period bigint := 0;
  v_receipts_today bigint := 0;
  v_receipt_count bigint := 0;
  v_expenses_total bigint := 0;
  v_expenses_period bigint := 0;
  v_expense_count bigint := 0;
  v_fee_gross bigint := 0;
  v_discount bigint := 0;
  v_fee_net bigint := 0;
  v_paid_allocated bigint := 0;
  v_balance_due bigint := 0;
  v_treasury bigint := 0;
  v_open_drafts bigint := 0;
  v_open_drafts_amount bigint := 0;
begin
  if not public.has_any_role(array['admin','direction','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé aux indicateurs financiers.' using errcode = '42501';
  end if;
  if p_from is not null and p_to is not null and p_to < p_from then
    raise exception 'La date de fin doit être égale ou postérieure à la date de début.';
  end if;

  select coalesce(sum(p.amount),0)::bigint, count(*)::bigint,
         coalesce(sum(p.amount) filter (
           where (p_from is null or p.paid_at >= p_from::timestamp at time zone 'UTC')
             and (p_to is null or p.paid_at < (p_to + 1)::timestamp at time zone 'UTC')
         ),0)::bigint,
         coalesce(sum(p.amount) filter (where p.paid_at >= current_date::timestamp at time zone 'UTC'
                                          and p.paid_at < (current_date + 1)::timestamp at time zone 'UTC'),0)::bigint
    into v_receipts_total,v_receipt_count,v_receipts_period,v_receipts_today
  from public.payments p
  where p.status='validated'
    and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC');

  select coalesce(sum(e.amount),0)::bigint, count(*)::bigint,
         coalesce(sum(e.amount) filter (
           where e.expense_date <= current_date
             and (p_from is null or e.expense_date >= p_from)
             and (p_to is null or e.expense_date <= p_to)
         ),0)::bigint
    into v_expenses_total,v_expense_count,v_expenses_period
  from public.expenses e where e.status='validated' and e.expense_date <= current_date;

  select coalesce(sum(coalesce(c.gross_amount,c.amount_due)),0)::bigint,
         coalesce(sum(coalesce(c.discount_amount,0)),0)::bigint,
         coalesce(sum(c.amount_due),0)::bigint,
         coalesce(sum(greatest(c.amount_due - coalesce(paid.amount_paid,0),0)),0)::bigint,
         coalesce(sum(least(coalesce(paid.amount_paid,0),c.amount_due)),0)::bigint
    into v_fee_gross,v_discount,v_fee_net,v_balance_due,v_paid_allocated
  from public.student_charges c
  left join lateral (
    select coalesce(sum(pa.amount),0)::bigint as amount_paid
    from public.payment_allocations pa
    join public.payments p on p.id=pa.payment_id and p.status='validated'
      and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
    where pa.charge_id=c.id
  ) paid on true
  where c.status='validated';

  select coalesce(sum(b.balance),0)::bigint into v_treasury
  from public.get_treasury_balances() b;

  select count(*)::bigint,coalesce(sum(e.amount),0)::bigint
    into v_open_drafts,v_open_drafts_amount
  from public.expenses e where e.status='draft';

  return jsonb_build_object(
    'receipts_total',v_receipts_total,
    'receipts_period',v_receipts_period,
    'receipts_today',v_receipts_today,
    'validated_receipt_count',v_receipt_count,
    'expenses_total',v_expenses_total,
    'expenses_period',v_expenses_period,
    'validated_expense_count',v_expense_count,
    'fees_gross',v_fee_gross,
    'discounts_total',v_discount,
    'fees_net',v_fee_net,
    'payments_allocated',v_paid_allocated,
    'outstanding_balance',v_balance_due,
    'treasury_total',v_treasury,
    'draft_expense_count',v_open_drafts,
    'draft_expense_total',v_open_drafts_amount
  );
end;
$$;

revoke all on function public.get_financial_summary(date,date) from public, anon;
grant execute on function public.get_financial_summary(date,date) to authenticated;

-- Vue d'ensemble du tableau de bord avec les recettes mensuelles calculées en base.
create or replace function public.get_financial_overview(p_months integer default 6)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_year_id uuid;
  v_year_label text;
  v_students bigint := 0;
  v_enrollments bigint := 0;
  v_months integer := least(greatest(coalesce(p_months,6),1),12);
  v_month_data jsonb;
  v_summary jsonb;
begin
  if not public.has_any_role(array['admin','direction','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé au tableau de bord financier.' using errcode = '42501';
  end if;

  select sy.id,sy.label into v_year_id,v_year_label
  from public.school_years sy where sy.is_current=true limit 1;

  select count(*)::bigint into v_students from public.students;
  if v_year_id is not null then
    select count(*)::bigint into v_enrollments
    from public.enrollments e
    where e.school_year_id=v_year_id and e.status in ('inscrit','reinscrit');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'label',case extract(month from month_start)::integer
        when 1 then 'Jan' when 2 then 'Fév' when 3 then 'Mar' when 4 then 'Avr'
        when 5 then 'Mai' when 6 then 'Juin' when 7 then 'Juil' when 8 then 'Août'
        when 9 then 'Sep' when 10 then 'Oct' when 11 then 'Nov' else 'Déc' end,
      'key',to_char(month_start,'YYYY-MM'),
      'amount',coalesce(month_total.amount,0)
    ) order by month_start
  ),'[]'::jsonb) into v_month_data
  from (
    select (date_trunc('month',current_date)::date - ((v_months - 1 - gs.n) * interval '1 month'))::date as month_start
    from generate_series(0,v_months-1) as gs(n)
  ) months
  left join lateral (
    select coalesce(sum(p.amount),0)::bigint as amount
    from public.payments p
    where p.status='validated'
      and p.paid_at >= months.month_start::timestamp at time zone 'UTC'
      and p.paid_at < (months.month_start + interval '1 month')::timestamp at time zone 'UTC'
      and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
  ) month_total on true;

  v_summary := public.get_financial_summary(null::date,null::date);
  return jsonb_build_object(
    'students',v_students,
    'enrollments',v_enrollments,
    'school_year_label',coalesce(v_year_label,'Aucune année active'),
    'months',v_month_data,
    'financial',v_summary
  );
end;
$$;

revoke all on function public.get_financial_overview(integer) from public, anon;
grant execute on function public.get_financial_overview(integer) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 014_management_reports_asset_integration.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — Étape 5 : rapports de gestion et intégration achats/patrimoine.
-- À appliquer après les migrations 001 à 013, d'abord dans un projet Supabase de test.


-- Registre paginé côté serveur pour éviter des rapports incomplets dus aux limites REST.
create or replace function public.get_management_report_rows(
  p_report_key text,
  p_from date default null,
  p_to date default null,
  p_school_year_id uuid default null,
  p_search text default null,
  p_limit integer default 100,
  p_offset integer default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb := '[]'::jsonb;
  v_total bigint := 0;
  v_limit integer := least(greatest(coalesce(p_limit,100),1),250);
  v_offset integer := greatest(coalesce(p_offset,0),0);
  v_search text := nullif(trim(coalesce(p_search,'')), '');
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]) then
    raise exception 'Accès refusé aux rapports de gestion.' using errcode = '42501';
  end if;
  if p_from is not null and p_to is not null and p_to < p_from then
    raise exception 'La date de fin doit être égale ou postérieure à la date de début.';
  end if;

  case p_report_key
    when 'fees' then
      with report_rows as (
        select
          c.id,
          s.student_number,
          trim(s.last_name || ' ' || s.first_names) as student_name,
          cl.name as class_name,
          sy.label as school_year,
          fc.name as fee_category,
          c.description,
          coalesce(c.gross_amount,c.amount_due)::bigint as gross_amount,
          coalesce(c.discount_amount,0)::bigint as discount_amount,
          c.amount_due::bigint as amount_due,
          coalesce(paid.amount_paid,0)::bigint as amount_paid,
          greatest(c.amount_due-coalesce(paid.amount_paid,0),0)::bigint as balance_due,
          c.due_on,
          c.created_at::date as created_on
        from public.student_charges c
        join public.enrollments e on e.id=c.enrollment_id
        join public.students s on s.id=e.student_id
        join public.classes cl on cl.id=e.class_id
        join public.school_years sy on sy.id=e.school_year_id
        join public.fee_categories fc on fc.id=c.fee_category_id
        left join lateral (
          select coalesce(sum(pa.amount),0)::bigint as amount_paid
          from public.payment_allocations pa
          join public.payments p on p.id=pa.payment_id
          where pa.charge_id=c.id and p.status='validated'
            and p.paid_at < ((current_date+1)::timestamp at time zone 'UTC')
        ) paid on true
        where c.status='validated'
          and greatest(c.amount_due-coalesce(paid.amount_paid,0),0)>0
          and (p_school_year_id is null or e.school_year_id=p_school_year_id)
          and (p_from is null or c.created_at::date>=p_from)
          and (p_to is null or c.created_at::date<=p_to)
          and (v_search is null or concat_ws(' ',s.student_number,s.last_name,s.first_names,cl.name,sy.label,fc.name,c.description) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by balance_due desc,student_name,created_on desc limit v_limit offset v_offset
      ) page_rows;

    when 'payments' then
      with report_rows as (
        select p.id,p.receipt_number,p.paid_at,
          s.student_number,trim(s.last_name||' '||s.first_names) as student_name,
          cl.name as class_name,sy.label as school_year,p.amount,
          p.method::text as payment_method,ca.name as account_name,p.payer_name,
          p.external_reference,p.status::text as status,p.cancellation_reason
        from public.payments p
        join public.enrollments e on e.id=p.enrollment_id
        join public.students s on s.id=e.student_id
        join public.classes cl on cl.id=e.class_id
        join public.school_years sy on sy.id=e.school_year_id
        join public.cash_accounts ca on ca.id=p.account_id
        where (p_from is null or p.paid_at >= (p_from::timestamp at time zone 'UTC'))
          and (p_to is null or p.paid_at < ((p_to+1)::timestamp at time zone 'UTC'))
          and (p_school_year_id is null or e.school_year_id=p_school_year_id)
          and (v_search is null or concat_ws(' ',p.receipt_number,s.student_number,s.last_name,s.first_names,cl.name,sy.label,ca.name,p.payer_name,p.external_reference,p.status::text) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by paid_at desc,receipt_number desc limit v_limit offset v_offset
      ) page_rows;

    when 'expenses' then
      with report_rows as (
        select e.id,e.expense_number,e.expense_date,ec.name as category,
          e.beneficiary,e.description,e.amount,ca.name as account_name,
          e.payment_method::text as payment_method,e.external_reference,
          e.status::text as status,e.cancellation_reason
        from public.expenses e
        join public.expense_categories ec on ec.id=e.category_id
        join public.cash_accounts ca on ca.id=e.account_id
        where (p_from is null or e.expense_date>=p_from)
          and (p_to is null or e.expense_date<=p_to)
          and (v_search is null or concat_ws(' ',e.expense_number,ec.name,e.beneficiary,e.description,ca.name,e.external_reference,e.status::text) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by expense_date desc,expense_number desc limit v_limit offset v_offset
      ) page_rows;

    when 'cashbook' then
      with report_rows as (
        select t.id,t.transaction_date,ca.name as account_name,t.direction,
          t.transaction_type,t.reference,t.description,t.amount,t.status::text as status,
          t.transfer_group_id
        from public.cash_transactions t
        join public.cash_accounts ca on ca.id=t.account_id
        where (p_from is null or t.transaction_date >= (p_from::timestamp at time zone 'UTC'))
          and (p_to is null or t.transaction_date < ((p_to+1)::timestamp at time zone 'UTC'))
          and (v_search is null or concat_ws(' ',ca.name,t.reference,t.description,t.transaction_type,t.direction,t.status::text) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by transaction_date desc,id limit v_limit offset v_offset
      ) page_rows;

    when 'purchases' then
      with report_rows as (
        select po.id,po.order_number,po.ordered_on,po.expected_delivery_on,
          s.name as supplier,coalesce(pr.request_number,'—') as request_number,
          po.total_amount,po.status::text as status,po.notes
        from public.purchase_orders po
        join public.suppliers s on s.id=po.supplier_id
        left join public.purchase_requests pr on pr.id=po.request_id
        where (p_from is null or po.ordered_on>=p_from)
          and (p_to is null or po.ordered_on<=p_to)
          and (v_search is null or concat_ws(' ',po.order_number,s.name,pr.request_number,po.status::text,po.notes) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by ordered_on desc,order_number desc limit v_limit offset v_offset
      ) page_rows;

    when 'receipts' then
      with report_rows as (
        select gr.id,gr.receipt_number,gr.received_at,po.order_number,
          s.name as supplier,gr.delivery_reference,gr.status,
          (select count(*)::integer from public.goods_receipt_lines grl where grl.goods_receipt_id=gr.id) as line_count,
          gr.notes
        from public.goods_receipts gr
        join public.purchase_orders po on po.id=gr.purchase_order_id
        join public.suppliers s on s.id=po.supplier_id
        where (p_from is null or gr.received_at >= (p_from::timestamp at time zone 'UTC'))
          and (p_to is null or gr.received_at < ((p_to+1)::timestamp at time zone 'UTC'))
          and (v_search is null or concat_ws(' ',gr.receipt_number,po.order_number,s.name,gr.delivery_reference,gr.status,gr.notes) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by received_at desc,receipt_number desc limit v_limit offset v_offset
      ) page_rows;

    when 'assets' then
      with report_rows as (
        select a.id,a.asset_code,a.name,c.name as category,a.brand,a.model,a.serial_number,
          a.acquired_on,a.acquisition_cost,s.name as supplier,a.location,a.status::text as status,
          a.invoice_reference,a.description
        from public.assets a
        join public.asset_categories c on c.id=a.category_id
        left join public.suppliers s on s.id=a.supplier_id
        where (p_from is null or a.acquired_on>=p_from)
          and (p_to is null or a.acquired_on<=p_to)
          and (v_search is null or concat_ws(' ',a.asset_code,a.name,c.name,a.brand,a.model,a.serial_number,s.name,a.location,a.status::text) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by acquired_on desc nulls last,asset_code limit v_limit offset v_offset
      ) page_rows;

    when 'maintenance' then
      with report_rows as (
        select m.id,m.maintenance_date,a.asset_code,a.name as asset_name,m.description,
          s.name as supplier,m.cost,m.status,m.document_path
        from public.asset_maintenance m
        join public.assets a on a.id=m.asset_id
        left join public.suppliers s on s.id=m.supplier_id
        where (p_from is null or m.maintenance_date>=p_from)
          and (p_to is null or m.maintenance_date<=p_to)
          and (v_search is null or concat_ws(' ',a.asset_code,a.name,m.description,s.name,m.status) ilike '%'||v_search||'%')
      ), counted as (
        select report_rows.*,count(*) over()::bigint as total_count from report_rows
      )
      select coalesce(jsonb_agg(to_jsonb(page_rows)-'total_count'),'[]'::jsonb),coalesce(max(page_rows.total_count),0)
      into v_rows,v_total from (
        select * from counted order by maintenance_date desc,id limit v_limit offset v_offset
      ) page_rows;

    else
      raise exception 'Type de rapport inconnu : %', p_report_key;
  end case;

  return jsonb_build_object('report',p_report_key,'rows',v_rows,'total_count',v_total,'limit',v_limit,'offset',v_offset);
end;
$$;

revoke all on function public.get_management_report_rows(text,date,date,uuid,text,integer,integer) from public, anon;
grant execute on function public.get_management_report_rows(text,date,date,uuid,text,integer,integer) to authenticated;
comment on function public.get_management_report_rows(text,date,date,uuid,text,integer,integer) is
'Rapports paginés calculés côté PostgreSQL pour les frais impayés, encaissements, dépenses, journal de caisse, achats, réceptions, inventaire et maintenance.';

-- Garde la catégorie patrimoniale de la demande jusque dans la ligne de commande.
alter table public.purchase_order_lines add column if not exists category text;

-- Version durcie du RPC de commande : copie explicitement les détails, dont la catégorie.
create or replace function public.create_order_from_request(
  p_request_id uuid,
  p_supplier_id uuid,
  p_order_number text,
  p_ordered_on date default current_date,
  p_expected_delivery_on date default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.purchase_requests%rowtype;
  v_order_id uuid;
  v_total bigint;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]) then
    raise exception 'Autorisation achats/comptabilité requise' using errcode = '42501';
  end if;
  select * into v_request from public.purchase_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if v_request.status <> 'approved' then raise exception 'La demande doit être approuvée'; end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and is_active=true) then
    raise exception 'Fournisseur invalide ou inactif';
  end if;
  if exists(select 1 from public.purchase_orders where request_id=p_request_id and status <> 'cancelled') then
    raise exception 'Un bon de commande existe déjà pour cette demande';
  end if;
  if nullif(trim(coalesce(p_order_number,'')),'') is null then raise exception 'Référence de commande obligatoire'; end if;
  if p_ordered_on is not null and p_ordered_on > current_date then
    raise exception 'La date de commande ne peut pas être dans le futur';
  end if;
  if p_expected_delivery_on is not null and p_ordered_on is not null and p_expected_delivery_on < p_ordered_on then
    raise exception 'La livraison prévue ne peut pas précéder la commande';
  end if;
  select coalesce(sum(round(quantity * estimated_unit_price)),0)::bigint into v_total
  from public.purchase_request_lines where request_id=p_request_id;
  if v_total <= 0 then raise exception 'Le montant de la commande doit être positif'; end if;
  if not exists(select 1 from public.purchase_request_lines where request_id=p_request_id) then
    raise exception 'La demande ne contient aucune ligne';
  end if;
  insert into public.purchase_orders(order_number,request_id,supplier_id,ordered_on,expected_delivery_on,status,total_amount,created_by,notes)
  values(trim(p_order_number),p_request_id,p_supplier_id,coalesce(p_ordered_on,current_date),p_expected_delivery_on,'ordered',v_total,auth.uid(),nullif(trim(coalesce(p_notes,'')),''))
  returning id into v_order_id;
  insert into public.purchase_order_lines(purchase_order_id,description,item_kind,quantity_ordered,unit_price,category)
  select v_order_id,description,item_kind,quantity,estimated_unit_price,nullif(trim(coalesce(category,'')),'')
  from public.purchase_request_lines where request_id=p_request_id;
  update public.purchase_requests set status='ordered' where id=p_request_id;
  return v_order_id;
end;
$$;
revoke all on function public.create_order_from_request(uuid,uuid,text,date,date,text) from public, anon;
grant execute on function public.create_order_from_request(uuid,uuid,text,date,date,text) to authenticated;

-- Les réceptions de lignes d'immobilisations créent automatiquement une fiche d'inventaire
-- par unité entière reçue. Aucun mouvement de trésorerie n'est créé : le règlement reste dans Dépenses.
create or replace function public.receive_purchase_order(
  p_order_id uuid,
  p_receipt_number text,
  p_lines jsonb,
  p_delivery_reference text default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.purchase_orders%rowtype;
  v_receipt_id uuid;
  v_receipt_line_id uuid;
  v_line jsonb;
  v_line_id uuid;
  v_qty numeric(12,3);
  v_asset_count integer;
  v_asset_index integer;
  v_asset_offset integer;
  v_asset_category_id uuid;
  v_asset_id uuid;
  v_first_asset_id uuid;
  v_order_line public.purchase_order_lines%rowtype;
  v_all_received boolean;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','comptabilite']::public.app_role[]) then
    raise exception 'Autorisation réception requise';
  end if;
  if nullif(trim(coalesce(p_receipt_number,'')),'') is null then
    raise exception 'Référence de réception obligatoire';
  end if;
  select * into v_order from public.purchase_orders where id=p_order_id for update;
  if not found then raise exception 'Bon de commande introuvable'; end if;
  if v_order.status not in ('ordered','partially_received') then
    raise exception 'Ce bon de commande ne peut pas être réceptionné';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'Ajoutez au moins une ligne reçue';
  end if;

  insert into public.goods_receipts(receipt_number,purchase_order_id,received_by,delivery_reference,notes,status)
  values(trim(p_receipt_number),p_order_id,auth.uid(),nullif(trim(coalesce(p_delivery_reference,'')),''),nullif(trim(coalesce(p_notes,'')),''),'draft')
  returning id into v_receipt_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_id := (v_line->>'line_id')::uuid;
    v_qty := (v_line->>'quantity_received')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantité reçue invalide'; end if;
    select * into v_order_line
      from public.purchase_order_lines
      where id=v_line_id and purchase_order_id=p_order_id
      for update;
    if not found then raise exception 'Ligne absente de ce bon de commande'; end if;
    if v_order_line.quantity_received + v_qty > v_order_line.quantity_ordered then
      raise exception 'La quantité reçue dépasse la quantité commandée pour %', v_order_line.description;
    end if;

    insert into public.goods_receipt_lines(goods_receipt_id,purchase_order_line_id,quantity_received,condition_note)
    values(v_receipt_id,v_line_id,v_qty,nullif(trim(coalesce(v_line->>'condition_note','')),''))
    returning id into v_receipt_line_id;

    if v_order_line.item_kind='asset' then
      v_asset_category_id := null;
      if v_qty <> trunc(v_qty) then
        raise exception 'La quantité réceptionnée d''une immobilisation doit être un nombre entier.';
      end if;
      v_asset_count := v_qty::integer;
      select count(*)::integer into v_asset_offset from public.assets where purchase_order_line_id=v_line_id;
      if nullif(trim(coalesce(v_order_line.category,'')),'') is not null then
        select id into v_asset_category_id
        from public.asset_categories
        where is_active=true and (lower(code)=lower(trim(v_order_line.category)) or lower(name)=lower(trim(v_order_line.category)))
        limit 1;
        if v_asset_category_id is null then
          raise exception 'Catégorie patrimoniale inconnue ou inactive : %', v_order_line.category;
        end if;
      else
        select id into v_asset_category_id from public.asset_categories where code='AUT' and is_active=true limit 1;
      end if;
      if v_asset_category_id is null then
        raise exception 'La catégorie patrimoniale « Autres biens » doit être active pour appliquer la catégorie par défaut.';
      end if;
      v_first_asset_id := null;
      for v_asset_index in 1..v_asset_count loop
        insert into public.assets(
          asset_code,name,category_id,description,acquired_on,acquisition_cost,
          supplier_id,purchase_order_line_id,location,status,created_by
        ) values (
          'PAT-'||to_char(current_date,'YYYY')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
          case when v_asset_count=1 and v_asset_offset=0 then v_order_line.description else v_order_line.description||' - '||(v_asset_offset+v_asset_index)::text end,
          v_asset_category_id,
          nullif(trim(coalesce(v_line->>'condition_note','')),''),
          current_date,v_order_line.unit_price,v_order.supplier_id,v_line_id,null,'active',auth.uid()
        ) returning id into v_asset_id;
        if v_first_asset_id is null then v_first_asset_id := v_asset_id; end if;
      end loop;
      -- La ligne de réception référence le premier bien créé ; toutes les unités restent liées
      -- à la ligne du bon de commande via assets.purchase_order_line_id.
      update public.goods_receipt_lines set asset_id=v_first_asset_id where id=v_receipt_line_id;
    end if;

    update public.purchase_order_lines set quantity_received=quantity_received+v_qty where id=v_line_id;
  end loop;

  update public.goods_receipts set status='validated' where id=v_receipt_id;
  select bool_and(quantity_received >= quantity_ordered) into v_all_received
  from public.purchase_order_lines where purchase_order_id=p_order_id;
  update public.purchase_orders
  set status=case when v_all_received then 'received'::public.purchase_status else 'partially_received'::public.purchase_status end
  where id=p_order_id;
  return v_receipt_id;
end;
$$;
revoke all on function public.receive_purchase_order(uuid,text,jsonb,text,text) from public, anon;
grant execute on function public.receive_purchase_order(uuid,text,jsonb,text,text) to authenticated;

-- Enregistre une maintenance en une transaction et synchronise le statut du bien.
create or replace function public.register_asset_maintenance(
  p_asset_id uuid,
  p_maintenance_date date,
  p_description text,
  p_supplier_id uuid default null,
  p_cost bigint default 0,
  p_status text default 'planned'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_asset public.assets%rowtype;
  v_maintenance_id uuid;
begin
  if auth.uid() is null or not public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]) then
    raise exception 'Autorisation maintenance requise';
  end if;
  if p_asset_id is null or p_maintenance_date is null or nullif(trim(coalesce(p_description,'')),'') is null then
    raise exception 'Bien, date et description de maintenance obligatoires.';
  end if;
  if coalesce(p_cost,0)<0 then raise exception 'Le coût de maintenance ne peut pas être négatif.'; end if;
  if coalesce(p_status,'planned') not in ('planned','in_progress','completed','cancelled') then
    raise exception 'Statut de maintenance invalide.';
  end if;
  select * into v_asset from public.assets where id=p_asset_id for update;
  if not found then raise exception 'Bien introuvable.'; end if;
  if v_asset.status in ('lost','disposed','retired') then
    raise exception 'Un bien perdu, sorti ou réformé ne peut pas recevoir une nouvelle maintenance.';
  end if;
  if p_supplier_id is not null and not exists(select 1 from public.suppliers where id=p_supplier_id and is_active=true) then
    raise exception 'Le prestataire est introuvable ou inactif.';
  end if;

  insert into public.asset_maintenance(asset_id,maintenance_date,description,supplier_id,cost,status,created_by)
  values(p_asset_id,p_maintenance_date,trim(p_description),p_supplier_id,coalesce(p_cost,0),coalesce(p_status,'planned'),auth.uid())
  returning id into v_maintenance_id;

  if p_status='in_progress' and v_asset.status='active' then
    update public.assets set status='under_maintenance',updated_at=now() where id=p_asset_id;
  elsif p_status='completed' and v_asset.status='under_maintenance'
    and not exists(select 1 from public.asset_maintenance m where m.asset_id=p_asset_id and m.status='in_progress' and m.id<>v_maintenance_id) then
    update public.assets set status='active',updated_at=now() where id=p_asset_id;
  end if;
  return v_maintenance_id;
end;
$$;
revoke all on function public.register_asset_maintenance(uuid,date,text,uuid,bigint,text) from public, anon;
grant execute on function public.register_asset_maintenance(uuid,date,text,uuid,bigint,text) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 015_admin_registration_code_settings.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — code d’accès administrateur configurable depuis Paramètres.
-- Exécuter une seule fois après la migration 014.
CREATE TABLE IF NOT EXISTS public.admin_access_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id = true),
  registration_code_hash text,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.admin_access_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.admin_access_settings FROM anon, authenticated, PUBLIC;
INSERT INTO public.admin_access_settings (id, registration_code_hash)
VALUES (true, NULL)
ON CONFLICT (id) DO NOTHING;
COMMIT;

-- ============================================================
-- MIGRATION 016_notes_bulletins.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — Notes et bulletins scolaires
-- À appliquer après les migrations 001 à 015 sur un environnement de test avant production.
create table if not exists public.school_subjects (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.student_grades (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  subject_id uuid not null references public.school_subjects(id) on delete restrict,
  term text not null check (term in ('T1','T2','T3')),
  assessment_label text not null,
  assessment_date date not null default current_date,
  score numeric(5,2) not null check (score >= 0 and score <= 20),
  coefficient numeric(5,2) not null default 1 check (coefficient > 0 and coefficient <= 20),
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique (enrollment_id, subject_id, term, assessment_label)
);
create index if not exists student_grades_enrollment_term_idx on public.student_grades(enrollment_id,term,subject_id);
alter table public.school_subjects enable row level security;
alter table public.student_grades enable row level security;
drop policy if exists school_subjects_read on public.school_subjects;
create policy school_subjects_read on public.school_subjects for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','observateur']::public.app_role[]));
drop policy if exists school_subjects_manage on public.school_subjects;
create policy school_subjects_manage on public.school_subjects for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));
drop policy if exists student_grades_read on public.student_grades;
create policy student_grades_read on public.student_grades for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','observateur']::public.app_role[]));
drop policy if exists student_grades_manage on public.student_grades;
create policy student_grades_manage on public.student_grades for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));
grant select, insert, update on public.school_subjects, public.student_grades to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 017_bank_reconciliation_workflow.sql
-- ============================================================
BEGIN;
-- Rapprochement bancaire transactionnel et traçable.
create or replace function public.reconcile_bank_statement_line(p_statement_line_id uuid,p_cash_transaction_id uuid,p_notes text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_line public.bank_statement_lines%rowtype; v_tx public.cash_transactions%rowtype; v_id uuid; v_uid uuid := auth.uid(); v_amount bigint;
begin
 if v_uid is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Accès réservé à l’administration et à la comptabilité'; end if;
 select * into v_line from public.bank_statement_lines where id=p_statement_line_id for update;
 if not found then raise exception 'Ligne de relevé introuvable'; end if;
 select * into v_tx from public.cash_transactions where id=p_cash_transaction_id for update;
 if not found then raise exception 'Mouvement de trésorerie introuvable'; end if;
 if v_tx.status <> 'validated' or v_tx.transaction_type not in ('payment','expense','transfer','adjustment','reversal','opening') then raise exception 'Seuls les mouvements validés peuvent être rapprochés'; end if;
 if v_line.reconciliation_status = 'matched' then raise exception 'Cette ligne est déjà rapprochée'; end if;
 if exists(select 1 from public.bank_reconciliations where statement_line_id=v_line.id and status='matched') then raise exception 'Cette ligne possède déjà un rapprochement validé'; end if;
 if exists(select 1 from public.bank_reconciliations where cash_transaction_id=v_tx.id and status='matched') then raise exception 'Ce mouvement est déjà rapproché'; end if;
 if v_tx.account_id is distinct from (select account_id from public.bank_statement_imports where id=v_line.import_id) then raise exception 'Le compte du mouvement ne correspond pas au compte du relevé'; end if;
 v_amount := case when v_tx.direction='in' then v_line.credit else v_line.debit end;
 if v_amount <= 0 or v_amount <> v_tx.amount then raise exception 'Le montant ou le sens du mouvement ne correspond pas à la ligne du relevé'; end if;
 insert into public.bank_reconciliations(statement_line_id,cash_transaction_id,matched_amount,status,notes,created_by,validated_at,validated_by)
 values(v_line.id,v_tx.id,v_amount,'matched',nullif(trim(p_notes),''),v_uid,now(),v_uid) returning id into v_id;
 update public.bank_statement_lines set reconciliation_status='matched' where id=v_line.id;
 insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
 values(v_uid,'reconcile_bank_statement_line','bank_reconciliations',v_id::text,jsonb_build_object('statement_line_id',v_line.id,'cash_transaction_id',v_tx.id,'amount',v_amount));
 return v_id;
end $$;
revoke all on function public.reconcile_bank_statement_line(uuid,uuid,text) from public,anon;
grant execute on function public.reconcile_bank_statement_line(uuid,uuid,text) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 018_notes_bulletins_workflows.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — Module Notes & bulletins : évaluations, règles configurables et publication
-- À appliquer après 017_bank_reconciliation_workflow.sql dans Supabase.

create table if not exists public.school_assessments (
  id uuid primary key default gen_random_uuid(),
  school_year_id uuid not null references public.school_years(id) on delete restrict,
  class_id uuid not null references public.classes(id) on delete restrict,
  subject_id uuid not null references public.school_subjects(id) on delete restrict,
  term text not null check (term in ('T1','T2','T3')),
  title text not null check (length(trim(title)) between 1 and 120),
  assessment_type text not null check (assessment_type in ('devoir','composition','examen','oral','autre')),
  assessment_date date not null default current_date,
  score_max numeric(6,2) not null default 20 check (score_max > 0 and score_max <= 1000),
  coefficient numeric(6,2) not null default 1 check (coefficient > 0 and coefficient <= 100),
  status text not null default 'draft' check (status in ('draft','open','locked','cancelled')),
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_year_id,class_id,subject_id,term,title)
);
create index if not exists school_assessments_filter_idx on public.school_assessments(school_year_id,class_id,term,subject_id,assessment_date desc);

alter table public.student_grades add column if not exists assessment_id uuid references public.school_assessments(id) on delete restrict;
alter table public.student_grades add column if not exists score_max numeric(6,2) not null default 20;
alter table public.student_grades add column if not exists status text not null default 'entered' check (status in ('entered','absent_excused','absent_unexcused','exempt','missing'));
alter table public.student_grades add column if not exists validated_at timestamptz;
alter table public.student_grades add column if not exists validated_by uuid references public.profiles(id) on delete restrict;
alter table public.student_grades add column if not exists updated_by uuid references public.profiles(id) on delete restrict;
alter table public.student_grades drop constraint if exists student_grades_score_check;
alter table public.student_grades add constraint student_grades_score_range_check check (score >= 0 and score <= score_max and score_max > 0);
create unique index if not exists student_grades_assessment_enrollment_unique on public.student_grades(assessment_id,enrollment_id) where assessment_id is not null;
create index if not exists student_grades_assessment_idx on public.student_grades(assessment_id,status);

create table if not exists public.school_grade_rules (
  id uuid primary key default gen_random_uuid(),
  school_year_id uuid not null references public.school_years(id) on delete restrict,
  class_id uuid references public.classes(id) on delete restrict,
  calculation_method text not null default 'coefficients' check (calculation_method in ('simple','coefficients','categories')),
  composition_weight numeric(5,2) not null default 40 check (composition_weight between 0 and 100),
  exam_weight numeric(5,2) not null default 60 check (exam_weight between 0 and 100),
  other_weight numeric(5,2) not null default 0 check (other_weight between 0 and 100),
  report_scale numeric(6,2) not null default 20 check (report_scale > 0 and report_scale <= 1000),
  is_approved boolean not null default false,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  updated_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (calculation_method <> 'categories' or composition_weight + exam_weight + other_weight = 100)
);
create unique index if not exists school_grade_rules_scope_unique on public.school_grade_rules(school_year_id,coalesce(class_id,'00000000-0000-0000-0000-000000000000'::uuid));

create table if not exists public.school_bulletins (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  term text not null check (term in ('T1','T2','T3')),
  status text not null default 'draft' check (status in ('draft','published','superseded')),
  payload jsonb not null default '{}'::jsonb,
  average numeric(8,3),
  report_scale numeric(6,2) not null default 20 check (report_scale > 0),
  generated_at timestamptz not null default now(),
  published_at timestamptz,
  published_by uuid references public.profiles(id) on delete restrict,
  supersedes_id uuid references public.school_bulletins(id) on delete restrict,
  created_by uuid references public.profiles(id) on delete restrict
);
create unique index if not exists school_bulletins_one_draft_idx on public.school_bulletins(enrollment_id,term) where status = 'draft';
create unique index if not exists school_bulletins_one_published_idx on public.school_bulletins(enrollment_id,term) where status = 'published';
create index if not exists school_bulletins_enrollment_idx on public.school_bulletins(enrollment_id,term,generated_at desc);

-- Journalisation de l'édition/publication des notes et bulletins.
create or replace function public.school_grade_set_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists school_assessments_updated_at on public.school_assessments;
create trigger school_assessments_updated_at before update on public.school_assessments for each row execute function public.school_grade_set_updated_at();
drop trigger if exists school_grade_rules_updated_at on public.school_grade_rules;
create trigger school_grade_rules_updated_at before update on public.school_grade_rules for each row execute function public.school_grade_set_updated_at();
drop trigger if exists student_grades_updated_at on public.student_grades;
create trigger student_grades_updated_at before update on public.student_grades for each row execute function public.set_updated_at();

-- Attribution automatique et journal d'audit des créations/corrections de notes.
create or replace function public.school_grade_audit_write()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, v_actor);
    new.updated_by := v_actor;
    insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
    values(v_actor,'grade.created','student_grades',new.id::text,jsonb_build_object('enrollment_id',new.enrollment_id,'subject_id',new.subject_id,'term',new.term,'assessment_id',new.assessment_id,'score',new.score,'score_max',new.score_max,'status',new.status));
    return new;
  end if;
  new.updated_by := v_actor;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_actor,'grade.updated','student_grades',new.id::text,jsonb_build_object('old_score',old.score,'new_score',new.score,'old_status',old.status,'new_status',new.status,'assessment_id',new.assessment_id,'enrollment_id',new.enrollment_id));
  return new;
end;
$$;
drop trigger if exists student_grades_audit_write on public.student_grades;
create trigger student_grades_audit_write before insert or update on public.student_grades for each row execute function public.school_grade_audit_write();

alter table public.school_assessments enable row level security;
alter table public.school_grade_rules enable row level security;
alter table public.school_bulletins enable row level security;

drop policy if exists school_assessments_read on public.school_assessments;
create policy school_assessments_read on public.school_assessments for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]));
drop policy if exists school_assessments_manage on public.school_assessments;
drop policy if exists school_assessments_insert on public.school_assessments;
drop policy if exists school_assessments_update on public.school_assessments;
create policy school_assessments_insert on public.school_assessments for insert to authenticated
with check (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]));
create policy school_assessments_update on public.school_assessments for update to authenticated
using (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]));

drop policy if exists school_grade_rules_read on public.school_grade_rules;
create policy school_grade_rules_read on public.school_grade_rules for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]));
drop policy if exists school_grade_rules_manage on public.school_grade_rules;
drop policy if exists school_grade_rules_insert on public.school_grade_rules;
drop policy if exists school_grade_rules_update on public.school_grade_rules;
create policy school_grade_rules_insert on public.school_grade_rules for insert to authenticated
with check (public.has_any_role(array['admin','direction']::public.app_role[]));
create policy school_grade_rules_update on public.school_grade_rules for update to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

drop policy if exists school_bulletins_read on public.school_bulletins;
create policy school_bulletins_read on public.school_bulletins for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]));
drop policy if exists school_bulletins_manage on public.school_bulletins;
drop policy if exists school_bulletins_insert on public.school_bulletins;
drop policy if exists school_bulletins_update on public.school_bulletins;
create policy school_bulletins_insert on public.school_bulletins for insert to authenticated
with check (public.has_any_role(array['admin','direction']::public.app_role[]));
create policy school_bulletins_update on public.school_bulletins for update to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

-- Lecture des nouvelles tables par le rôle applicatif Modification.
drop policy if exists school_assessments_read_modification on public.school_assessments;
create policy school_assessments_read_modification on public.school_assessments for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists school_grade_rules_read_modification on public.school_grade_rules;
create policy school_grade_rules_read_modification on public.school_grade_rules for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists school_bulletins_read_modification on public.school_bulletins;
create policy school_bulletins_read_modification on public.school_bulletins for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));

-- Lecture des référentiels nécessaires au module pour le rôle applicatif Modification.
-- Les politiques sont ajoutées séparément afin de ne pas modifier les accès des autres rôles.
drop policy if exists school_subjects_read_modification on public.school_subjects;
create policy school_subjects_read_modification on public.school_subjects for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists school_years_read_modification on public.school_years;
create policy school_years_read_modification on public.school_years for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists classes_read_modification on public.classes;
create policy classes_read_modification on public.classes for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists students_read_modification on public.students;
create policy students_read_modification on public.students for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists enrollments_read_modification on public.enrollments;
create policy enrollments_read_modification on public.enrollments for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists student_grades_read_modification on public.student_grades;
create policy student_grades_read_modification on public.student_grades for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));

-- Étendre les droits de modification de student_grades au rôle métier Modification, sans élargir les droits de lecture.
drop policy if exists student_grades_manage on public.student_grades;
drop policy if exists student_grades_insert on public.student_grades;
drop policy if exists student_grades_update on public.student_grades;
create policy student_grades_insert on public.student_grades for insert to authenticated
with check (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]));
create policy student_grades_update on public.student_grades for update to authenticated
using (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]));
grant select, insert, update on public.school_assessments, public.school_grade_rules, public.school_bulletins to authenticated;
grant select, insert, update on public.student_grades to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 019_finance_scolaire_reductions_echeanciers.sql
-- ============================================================
BEGIN;
-- EPC BETHEL V1.14.0 — vocabulaire des réductions, échéanciers variables et synthèse financière.
-- À tester sur un projet Supabase de préproduction avant déploiement.


-- Création d'une charge de scolarité ou d'inscription répartie sur 1 à 6 versements.
-- Les réductions approuvées ne s'appliquent automatiquement qu'à la scolarité, comme dans le workflow existant.
create or replace function public.create_installment_student_charge(
  p_enrollment_id uuid,
  p_fee_code text,
  p_description text,
  p_amount bigint,
  p_due_dates date[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_category uuid;
  v_charge uuid;
  v_concession public.enrollment_concessions%rowtype;
  v_concession_id uuid;
  v_gross bigint;
  v_discount bigint := 0;
  v_net bigint;
  v_count integer;
  v_i integer;
  v_base bigint;
  v_remainder bigint;
  v_status text;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à créer des frais scolaires';
  end if;
  if p_fee_code not in ('SCOLARITE','INSCRIPTION') then
    raise exception 'Seuls les frais de scolarité et d’inscription peuvent être répartis sur plusieurs versements';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Le montant total doit être supérieur à zéro'; end if;
  if nullif(trim(p_description),'') is null then raise exception 'La désignation des frais est obligatoire'; end if;
  if p_due_dates is null or cardinality(p_due_dates) < 1 or cardinality(p_due_dates) > 6 or array_position(p_due_dates, null) is not null then
    raise exception 'Choisissez entre un et six versements et renseignez chaque date';
  end if;
  v_count := cardinality(p_due_dates);
  for v_i in 2..v_count loop
    if p_due_dates[v_i] < p_due_dates[v_i-1] then
      raise exception 'Les dates de versement doivent être dans l’ordre chronologique';
    end if;
  end loop;

  select status into v_status
  from public.enrollments
  where id=p_enrollment_id
  for update;
  if not found or v_status not in ('inscrit','reinscrit') then
    raise exception 'Inscription active introuvable';
  end if;

  select id into v_category
  from public.fee_categories
  where code=p_fee_code and is_active=true;
  if v_category is null then raise exception 'Catégorie de frais introuvable ou inactive'; end if;

  if exists(
    select 1 from public.student_charges c
    where c.enrollment_id=p_enrollment_id and c.fee_category_id=v_category and c.status='validated'
  ) then
    if p_fee_code='SCOLARITE' then
      raise exception 'Une charge de scolarité validée existe déjà pour cette inscription';
    else
      raise exception 'Les frais d’inscription sont déjà enregistrés pour cette inscription';
    end if;
  end if;

  v_gross := p_amount;
  if p_fee_code='SCOLARITE' then
    select * into v_concession
    from public.enrollment_concessions c
    where c.enrollment_id=p_enrollment_id
      and c.scope in ('scolarite','all_eligible')
      and c.status='approved'
      and (c.valid_from is null or c.valid_from <= current_date)
      and (c.valid_to is null or c.valid_to >= current_date)
    order by c.approved_at desc
    limit 1
    for update;
    if found then
      v_concession_id := v_concession.id;
      if v_concession.kind='percentage' then
        v_discount := round(v_gross * v_concession.percentage / 100.0)::bigint;
      else
        v_discount := least(v_gross,coalesce(v_concession.fixed_amount,0));
      end if;
    end if;
  end if;
  v_net := v_gross-v_discount;

  insert into public.student_charges(
    enrollment_id,fee_category_id,description,amount_due,gross_amount,discount_amount,concession_id,due_on,status,source,created_by
  ) values (
    p_enrollment_id,v_category,trim(p_description),v_net,v_gross,v_discount,
    case when v_discount>0 then v_concession_id else null end,
    p_due_dates[v_count],'validated','manual',v_user
  ) returning id into v_charge;

  v_base := v_net / v_count;
  v_remainder := mod(v_net,v_count);
  for v_i in 1..v_count loop
    insert into public.installments(charge_id,installment_no,amount_due,due_on,created_by)
    values(v_charge,v_i,v_base+case when v_i<=v_remainder then 1 else 0 end,p_due_dates[v_i],v_user);
  end loop;

  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'create_installment_student_charge','student_charges',v_charge::text,
    jsonb_build_object('enrollment_id',p_enrollment_id,'fee_code',p_fee_code,'gross_amount',v_gross,
      'discount_amount',v_discount,'net_amount',v_net,'reduction_id',case when v_discount>0 then v_concession_id else null end,
      'installment_count',v_count,'due_dates',p_due_dates));
  return v_charge;
end;
$$;

revoke all on function public.create_installment_student_charge(uuid,text,text,bigint,date[]) from public, anon;
grant execute on function public.create_installment_student_charge(uuid,text,text,bigint,date[]) to authenticated;

-- Liste paginée avec filtres financiers calculés côté serveur.
create or replace function public.get_school_fee_ledger_filtered(
  p_school_year_id uuid default null,
  p_class_id uuid default null,
  p_fee_code text default null,
  p_payment_status text default null,
  p_limit integer default 100,
  p_offset integer default 0,
  p_query text default null
)
returns table(
  charge_id uuid,
  enrollment_id uuid,
  student_name text,
  student_number text,
  class_name text,
  school_year text,
  school_year_id uuid,
  category_name text,
  fee_code text,
  description text,
  gross_amount bigint,
  discount_amount bigint,
  amount_due bigint,
  amount_paid bigint,
  balance_due bigint,
  overdue_amount bigint,
  payment_status text,
  installment_count integer,
  due_on date,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]) then
    raise exception 'Accès refusé à la consultation des frais scolaires.' using errcode = '42501';
  end if;
  if p_offset is null or p_offset < 0 then raise exception 'Le décalage de pagination est invalide.'; end if;

  return query
  with charge_rows as (
    select
      c.id as charge_id,
      c.enrollment_id,
      trim(s.last_name || ' ' || s.first_names)::text as student_name,
      s.student_number::text as student_number,
      cl.name::text as class_name,
      sy.label::text as school_year,
      sy.id as school_year_id,
      fc.name::text as category_name,
      fc.code::text as fee_code,
      c.description::text as description,
      coalesce(c.gross_amount,c.amount_due)::bigint as gross_amount,
      coalesce(c.discount_amount,0)::bigint as discount_amount,
      c.amount_due::bigint as amount_due,
      coalesce(paid.amount_paid,0)::bigint as amount_paid,
      greatest(c.amount_due - coalesce(paid.amount_paid,0),0)::bigint as balance_due,
      coalesce(overdue.overdue_amount,0)::bigint as overdue_amount,
      coalesce(installs.installment_count,0)::integer as installment_count,
      c.due_on,
      c.created_at
    from public.student_charges c
    join public.enrollments e on e.id=c.enrollment_id
    join public.students s on s.id=e.student_id
    join public.classes cl on cl.id=e.class_id
    join public.school_years sy on sy.id=e.school_year_id
    join public.fee_categories fc on fc.id=c.fee_category_id
    left join lateral (
      select coalesce(sum(pa.amount),0)::bigint as amount_paid
      from public.payment_allocations pa
      join public.payments p on p.id=pa.payment_id and p.status='validated'
        and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
      where pa.charge_id=c.id
    ) paid on true
    left join lateral (
      select case
        when exists(select 1 from public.installments ix where ix.charge_id=c.id) then
          coalesce((
            select sum(greatest(i.amount_due-coalesce(ip.paid_amount,0),0))::bigint
            from public.installments i
            left join lateral (
              select coalesce(sum(pa.amount),0)::bigint as paid_amount
              from public.payment_allocations pa
              join public.payments p on p.id=pa.payment_id and p.status='validated'
                and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
              where pa.installment_id=i.id
            ) ip on true
            where i.charge_id=c.id and i.due_on < current_date
          ),0)::bigint
        when c.due_on is not null and c.due_on < current_date then
          greatest(c.amount_due-coalesce(paid.amount_paid,0),0)::bigint
        else 0::bigint end as overdue_amount
    ) overdue on true
    left join lateral (
      select count(*)::integer as installment_count
      from public.installments i where i.charge_id=c.id
    ) installs on true
    where c.status='validated'
      and (p_school_year_id is null or e.school_year_id=p_school_year_id)
      and (p_class_id is null or e.class_id=p_class_id)
      and (nullif(trim(p_fee_code),'') is null or fc.code=p_fee_code)
      and (nullif(trim(p_query),'') is null or concat_ws(' ',s.last_name,s.first_names,s.student_number,cl.name,sy.label,fc.name,c.description) ilike '%'||trim(p_query)||'%')
  ), classified as (
    select charge_rows.*,
      case
        when gross_amount>0 and amount_due=0 then 'exempt'
        when balance_due<=0 then 'settled'
        when overdue_amount>0 then 'overdue'
        when amount_paid<=0 then 'unpaid'
        else 'partial'
      end as payment_status
    from charge_rows
  ), filtered as (
    select * from classified
    where nullif(trim(p_payment_status),'') is null or p_payment_status='all' or payment_status=p_payment_status
  ), counted as (
    select filtered.*,count(*) over()::bigint as total_count from filtered
  )
  select counted.charge_id,counted.enrollment_id,counted.student_name,counted.student_number,
    counted.class_name,counted.school_year,counted.school_year_id,counted.category_name,counted.fee_code,
    counted.description,counted.gross_amount,counted.discount_amount,counted.amount_due,counted.amount_paid,
    counted.balance_due,counted.overdue_amount,counted.payment_status,counted.installment_count,counted.due_on,counted.total_count
  from counted
  order by counted.created_at desc,counted.charge_id
  limit least(greatest(coalesce(p_limit,100),1),100)
  offset p_offset;
end;
$$;

revoke all on function public.get_school_fee_ledger_filtered(uuid,uuid,text,text,integer,integer,text) from public, anon;
grant execute on function public.get_school_fee_ledger_filtered(uuid,uuid,text,text,integer,integer,text) to authenticated;

-- Synthèse de tous les frais répondant à l'année, à la classe et à la catégorie sélectionnées.
create or replace function public.get_school_fee_summary(
  p_school_year_id uuid default null,
  p_class_id uuid default null,
  p_fee_code text default null
)
returns table(
  gross_total bigint,
  discount_total bigint,
  amount_due_total bigint,
  amount_paid_total bigint,
  balance_due_total bigint,
  overdue_total bigint,
  charge_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]) then
    raise exception 'Accès refusé à la synthèse des frais scolaires.' using errcode = '42501';
  end if;
  return query
  with charge_rows as (
    select c.id,
      coalesce(c.gross_amount,c.amount_due)::bigint as gross_amount,
      coalesce(c.discount_amount,0)::bigint as discount_amount,
      c.amount_due::bigint as amount_due,
      coalesce(paid.amount_paid,0)::bigint as amount_paid,
      coalesce(overdue.overdue_amount,0)::bigint as overdue_amount
    from public.student_charges c
    join public.enrollments e on e.id=c.enrollment_id
    join public.fee_categories fc on fc.id=c.fee_category_id
    left join lateral (
      select coalesce(sum(pa.amount),0)::bigint as amount_paid
      from public.payment_allocations pa
      join public.payments p on p.id=pa.payment_id and p.status='validated'
        and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
      where pa.charge_id=c.id
    ) paid on true
    left join lateral (
      select case
        when exists(select 1 from public.installments ix where ix.charge_id=c.id) then
          coalesce((
            select sum(greatest(i.amount_due-coalesce(ip.paid_amount,0),0))::bigint
            from public.installments i
            left join lateral (
              select coalesce(sum(pa.amount),0)::bigint as paid_amount
              from public.payment_allocations pa
              join public.payments p on p.id=pa.payment_id and p.status='validated'
                and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
              where pa.installment_id=i.id
            ) ip on true
            where i.charge_id=c.id and i.due_on < current_date
          ),0)::bigint
        when c.due_on is not null and c.due_on < current_date then
          greatest(c.amount_due-coalesce(paid.amount_paid,0),0)::bigint
        else 0::bigint end as overdue_amount
    ) overdue on true
    where c.status='validated'
      and (p_school_year_id is null or e.school_year_id=p_school_year_id)
      and (p_class_id is null or e.class_id=p_class_id)
      and (nullif(trim(p_fee_code),'') is null or fc.code=p_fee_code)
  )
  select coalesce(sum(gross_amount),0)::bigint,
    coalesce(sum(discount_amount),0)::bigint,
    coalesce(sum(amount_due),0)::bigint,
    coalesce(sum(amount_paid),0)::bigint,
    coalesce(sum(greatest(amount_due-amount_paid,0)),0)::bigint,
    coalesce(sum(overdue_amount),0)::bigint,
    count(*)::bigint
  from charge_rows;
end;
$$;

revoke all on function public.get_school_fee_summary(uuid,uuid,text) from public, anon;
grant execute on function public.get_school_fee_summary(uuid,uuid,text) to authenticated;

-- Détail de l'échéancier d'une charge, avec paiements validés ventilés par versement.
create or replace function public.get_school_fee_installment_detail(p_charge_id uuid)
returns table(
  charge_id uuid,
  student_name text,
  student_number text,
  description text,
  gross_amount bigint,
  discount_amount bigint,
  amount_due bigint,
  installment_no integer,
  due_on date,
  installment_amount bigint,
  installment_paid bigint,
  installment_balance bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]) then
    raise exception 'Accès refusé au détail des frais scolaires.' using errcode = '42501';
  end if;
  return query
  select c.id,trim(s.last_name||' '||s.first_names)::text,s.student_number::text,c.description::text,
    coalesce(c.gross_amount,c.amount_due)::bigint,coalesce(c.discount_amount,0)::bigint,c.amount_due::bigint,
    coalesce(i.installment_no,0)::integer,coalesce(i.due_on,c.due_on),coalesce(i.amount_due,c.amount_due)::bigint,
    coalesce(paid.installment_paid,0)::bigint,
    greatest(coalesce(i.amount_due,c.amount_due)-coalesce(paid.installment_paid,0),0)::bigint
  from public.student_charges c
  join public.enrollments e on e.id=c.enrollment_id
  join public.students s on s.id=e.student_id
  left join public.installments i on i.charge_id=c.id
  left join lateral (
    select coalesce(sum(pa.amount),0)::bigint as installment_paid
    from public.payment_allocations pa
    join public.payments p on p.id=pa.payment_id and p.status='validated'
      and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
    where pa.charge_id=c.id
      and ((i.id is not null and pa.installment_id=i.id) or (i.id is null and pa.installment_id is null))
  ) paid on true
  where c.id=p_charge_id and c.status='validated'
  order by coalesce(i.installment_no,0);
end;
$$;

revoke all on function public.get_school_fee_installment_detail(uuid) from public, anon;
grant execute on function public.get_school_fee_installment_detail(uuid) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 020_fix_school_fee_ledger_ambiguity.sql
-- ============================================================
BEGIN;
-- EPC BETHEL V1.15.2 — Correction de l'ambiguïté PL/pgSQL sur gross_amount.
-- La fonction renvoie une table dont les paramètres OUT portent les mêmes noms que
-- les colonnes du CTE : toutes les références du CASE sont donc qualifiées.
-- À appliquer après la migration 019 sur les projets déjà configurés.

create or replace function public.get_school_fee_ledger_filtered(
  p_school_year_id uuid default null,
  p_class_id uuid default null,
  p_fee_code text default null,
  p_payment_status text default null,
  p_limit integer default 100,
  p_offset integer default 0,
  p_query text default null
)
returns table(
  charge_id uuid,
  enrollment_id uuid,
  student_name text,
  student_number text,
  class_name text,
  school_year text,
  school_year_id uuid,
  category_name text,
  fee_code text,
  description text,
  gross_amount bigint,
  discount_amount bigint,
  amount_due bigint,
  amount_paid bigint,
  balance_due bigint,
  overdue_amount bigint,
  payment_status text,
  installment_count integer,
  due_on date,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]) then
    raise exception 'Accès refusé à la consultation des frais scolaires.' using errcode = '42501';
  end if;
  if p_offset is null or p_offset < 0 then raise exception 'Le décalage de pagination est invalide.'; end if;

  return query
  with charge_rows as (
    select
      c.id as charge_id,
      c.enrollment_id,
      trim(s.last_name || ' ' || s.first_names)::text as student_name,
      s.student_number::text as student_number,
      cl.name::text as class_name,
      sy.label::text as school_year,
      sy.id as school_year_id,
      fc.name::text as category_name,
      fc.code::text as fee_code,
      c.description::text as description,
      coalesce(c.gross_amount,c.amount_due)::bigint as gross_amount,
      coalesce(c.discount_amount,0)::bigint as discount_amount,
      c.amount_due::bigint as amount_due,
      coalesce(paid.amount_paid,0)::bigint as amount_paid,
      greatest(c.amount_due - coalesce(paid.amount_paid,0),0)::bigint as balance_due,
      coalesce(overdue.overdue_amount,0)::bigint as overdue_amount,
      coalesce(installs.installment_count,0)::integer as installment_count,
      c.due_on,
      c.created_at
    from public.student_charges c
    join public.enrollments e on e.id=c.enrollment_id
    join public.students s on s.id=e.student_id
    join public.classes cl on cl.id=e.class_id
    join public.school_years sy on sy.id=e.school_year_id
    join public.fee_categories fc on fc.id=c.fee_category_id
    left join lateral (
      select coalesce(sum(pa.amount),0)::bigint as amount_paid
      from public.payment_allocations pa
      join public.payments p on p.id=pa.payment_id and p.status='validated'
        and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
      where pa.charge_id=c.id
    ) paid on true
    left join lateral (
      select case
        when exists(select 1 from public.installments ix where ix.charge_id=c.id) then
          coalesce((
            select sum(greatest(i.amount_due-coalesce(ip.paid_amount,0),0))::bigint
            from public.installments i
            left join lateral (
              select coalesce(sum(pa.amount),0)::bigint as paid_amount
              from public.payment_allocations pa
              join public.payments p on p.id=pa.payment_id and p.status='validated'
                and p.paid_at < ((current_date + 1)::timestamp at time zone 'UTC')
              where pa.installment_id=i.id
            ) ip on true
            where i.charge_id=c.id and i.due_on < current_date
          ),0)::bigint
        when c.due_on is not null and c.due_on < current_date then
          greatest(c.amount_due-coalesce(paid.amount_paid,0),0)::bigint
        else 0::bigint end as overdue_amount
    ) overdue on true
    left join lateral (
      select count(*)::integer as installment_count
      from public.installments i where i.charge_id=c.id
    ) installs on true
    where c.status='validated'
      and (p_school_year_id is null or e.school_year_id=p_school_year_id)
      and (p_class_id is null or e.class_id=p_class_id)
      and (nullif(trim(p_fee_code),'') is null or fc.code=p_fee_code)
      and (nullif(trim(p_query),'') is null or concat_ws(' ',s.last_name,s.first_names,s.student_number,cl.name,sy.label,fc.name,c.description) ilike '%'||trim(p_query)||'%')
  ), classified as (
    select charge_rows.*,
      case
        when charge_rows.gross_amount>0 and charge_rows.amount_due=0 then 'exempt'
        when charge_rows.balance_due<=0 then 'settled'
        when charge_rows.overdue_amount>0 then 'overdue'
        when charge_rows.amount_paid<=0 then 'unpaid'
        else 'partial'
      end as payment_status
    from charge_rows
  ), filtered as (
    select * from classified
    where nullif(trim(p_payment_status),'') is null or p_payment_status='all' or classified.payment_status=p_payment_status
  ), counted as (
    select filtered.*,count(*) over()::bigint as total_count from filtered
  )
  select counted.charge_id,counted.enrollment_id,counted.student_name,counted.student_number,
    counted.class_name,counted.school_year,counted.school_year_id,counted.category_name,counted.fee_code,
    counted.description,counted.gross_amount,counted.discount_amount,counted.amount_due,counted.amount_paid,
    counted.balance_due,counted.overdue_amount,counted.payment_status,counted.installment_count,counted.due_on,counted.total_count
  from counted
  order by counted.created_at desc,counted.charge_id
  limit least(greatest(coalesce(p_limit,100),1),100)
  offset p_offset;
end;
$$;

revoke all on function public.get_school_fee_ledger_filtered(uuid,uuid,text,text,integer,integer,text) from public, anon;
grant execute on function public.get_school_fee_ledger_filtered(uuid,uuid,text,text,integer,integer,text) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 021_treasury_account_types_and_creation.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — Distinction des comptes de trésorerie et création sécurisée.
-- À appliquer après les migrations 001 à 020 sur une base de développement,
-- puis à valider avant production.

alter type public.account_kind add value if not exists 'mobile_money';

alter table public.cash_accounts
  add column if not exists provider_name text;

comment on column public.cash_accounts.provider_name is
  'Opérateur du portefeuille Mobile Money (ex. Orange Money, MTN MoMo).';

create or replace function public.create_cash_account(
  p_code text,
  p_name text,
  p_kind public.account_kind,
  p_bank_name text default null,
  p_provider_name text default null,
  p_opening_balance bigint default 0,
  p_opening_date date default current_date
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_account_id uuid;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_name text := trim(coalesce(p_name, ''));
begin
  if not public.has_any_role(array['admin']::public.app_role[]) then
    raise exception 'Seul un administrateur peut créer un compte financier.' using errcode = '42501';
  end if;
  if v_code = '' or v_name = '' then
    raise exception 'Le code et le nom du compte sont obligatoires.';
  end if;
  if v_code !~ '^[A-Z0-9_-]{2,30}$' then
    raise exception 'Le code doit contenir 2 à 30 caractères : lettres, chiffres, tirets ou soulignés.';
  end if;
  if p_kind::text not in ('cash', 'bank', 'mobile_money') then
    raise exception 'Type de compte non pris en charge.';
  end if;
  if p_opening_balance is null or p_opening_balance < 0 then
    raise exception 'Le solde initial doit être un entier positif ou nul.';
  end if;
  if p_opening_date is null then
    raise exception 'La date d’ouverture est obligatoire.';
  end if;
  if p_kind::text = 'mobile_money' and nullif(trim(coalesce(p_provider_name, '')), '') is null then
    raise exception 'L’opérateur Mobile Money est obligatoire.';
  end if;
  if exists(select 1 from public.cash_accounts a where a.code = v_code) then
    raise exception 'Ce code de compte existe déjà.' using errcode = '23505';
  end if;

  insert into public.cash_accounts(
    code, name, kind, bank_name, provider_name,
    opening_balance, opening_date, is_active, created_by
  ) values (
    v_code, v_name, p_kind,
    nullif(trim(coalesce(p_bank_name, '')), ''),
    nullif(trim(coalesce(p_provider_name, '')), ''),
    p_opening_balance, p_opening_date, true, v_uid
  ) returning id into v_account_id;

  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values (
    v_uid, 'create_cash_account', 'cash_accounts', v_account_id::text,
    jsonb_build_object(
      'code', v_code, 'name', v_name, 'kind', p_kind::text,
      'opening_balance', p_opening_balance, 'opening_date', p_opening_date
    )
  );
  return v_account_id;
end;
$$;

revoke all on function public.create_cash_account(text,text,public.account_kind,text,text,bigint,date) from public, anon;
grant execute on function public.create_cash_account(text,text,public.account_kind,text,text,bigint,date) to authenticated;


-- Empêche d'affecter un encaissement ou une dépense au mauvais type de compte.
-- 'autre' reste libre, les modes Mobile Money/Espèces/Virement/Chèque sont typés.
create or replace function public.check_treasury_account_method_match()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_method text;
  v_account_id uuid;
  v_account_kind public.account_kind;
begin
  if tg_table_name = 'payments' then
    v_method := new.method::text;
    v_account_id := new.account_id;
  elsif tg_table_name = 'expenses' then
    v_method := new.payment_method::text;
    v_account_id := new.account_id;
  else
    raise exception 'Table non prise en charge par le contrôle de compte.';
  end if;

  select a.kind into v_account_kind
  from public.cash_accounts a
  where a.id = v_account_id and a.is_active = true;
  if not found then
    raise exception 'Le compte choisi est inactif ou introuvable.';
  end if;

  if v_method = 'especes' and v_account_kind::text <> 'cash' then
    raise exception 'Pour un paiement en espèces, choisissez un compte de caisse.';
  elsif v_method = 'mobile_money' and v_account_kind::text <> 'mobile_money' then
    raise exception 'Pour un paiement Mobile Money, choisissez un portefeuille Mobile Money.';
  elsif v_method in ('virement', 'cheque') and v_account_kind::text <> 'bank' then
    raise exception 'Pour un virement ou un chèque, choisissez un compte bancaire.';
  end if;

  return new;
end;
$$;

revoke all on function public.check_treasury_account_method_match() from public, anon, authenticated;

drop trigger if exists payments_account_method_match on public.payments;
create trigger payments_account_method_match
before insert or update of method, account_id on public.payments
for each row execute function public.check_treasury_account_method_match();

drop trigger if exists expenses_account_method_match on public.expenses;
create trigger expenses_account_method_match
before insert or update of payment_method, account_id on public.expenses
for each row execute function public.check_treasury_account_method_match();
COMMIT;

-- ============================================================
-- MIGRATION 022_cash_register_single_ledger_and_controls.sql
-- ============================================================
BEGIN;
-- EPC BETHEL — Caisse unique, moyens de paiement, comptage physique et opérations manuelles traçables.
-- À appliquer après la migration 021 en préproduction avant la production.


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
COMMIT;

-- ============================================================
-- MIGRATION 023_cash_register_edit_delete_guardrails.sql
-- ============================================================
BEGIN;
-- EPC BETHEL 1.18.0 — verrouille la modification/suppression dans le registre unique de caisse.

create or replace function public.update_manual_cash_movement(
  p_transaction_id uuid,p_direction text,p_amount bigint,p_transaction_date date,p_payment_channel text,p_reference text,p_description text,p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_tx public.cash_transactions%rowtype; v_uid uuid:=auth.uid(); v_at timestamptz; v_available bigint; v_main_cash_id uuid; v_old_channel_balance bigint;
begin
  if v_uid is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Modification réservée à l’administration ou à la comptabilité.' using errcode='42501'; end if;
  select * into v_tx from public.cash_transactions t where t.id=p_transaction_id for update;
  if not found then raise exception 'Mouvement introuvable.'; end if;
  select a.id into v_main_cash_id from public.cash_accounts a where a.is_active and a.kind::text='cash' order by (a.code='CAISSE') desc,a.created_at,a.id limit 1;
  if v_main_cash_id is null or v_tx.account_id<>v_main_cash_id then raise exception 'Cette ligne ne fait pas partie du registre unique de caisse principal.'; end if;
  if v_tx.transaction_type<>'adjustment' or v_tx.payment_id is not null or v_tx.expense_id is not null or v_tx.transfer_group_id is not null or v_tx.reverses_transaction_id is not null then
    raise exception 'Seules les lignes de caisse saisies manuellement peuvent être modifiées ici. Les reçus et dépenses doivent être corrigés dans leur module.';
  end if;
  if exists(select 1 from public.bank_reconciliations r where r.cash_transaction_id=v_tx.id and r.status='matched') then raise exception 'Ce mouvement est rapproché et ne peut plus être modifié.'; end if;
  if coalesce(p_direction,'') not in ('in','out') or p_amount is null or p_amount<=0 or p_transaction_date is null or p_transaction_date>current_date
    or coalesce(p_payment_channel,'') not in ('especes','orange_money','wave','moov_money') or coalesce(trim(p_description),'')='' or coalesce(trim(p_reason),'')='' then
    raise exception 'Vérifiez le sens, le montant, la date, le moyen de paiement, le libellé et le motif de modification.';
  end if;
  v_at := ((p_transaction_date+1)::timestamp at time zone 'UTC')-interval '1 microsecond';
  v_old_channel_balance := public.cash_method_balance(v_tx.payment_channel,now(),v_tx.id);
  if v_old_channel_balance<0 then raise exception 'Modification refusée : les mouvements postérieurs entraîneraient un solde négatif pour le moyen de paiement d’origine.'; end if;
  v_available := public.cash_method_balance(p_payment_channel,v_at,v_tx.id);
  if p_direction='out' and v_available<p_amount then raise exception 'Solde insuffisant pour ce moyen de paiement. Disponible : %, demandé : %',v_available,p_amount; end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_uid,'update_manual_cash_movement','cash_transactions',v_tx.id::text,jsonb_build_object('reason',trim(p_reason),'before',jsonb_build_object('date',v_tx.transaction_date,'direction',v_tx.direction,'amount',v_tx.amount,'channel',v_tx.payment_channel,'reference',v_tx.reference,'description',v_tx.description),'after',jsonb_build_object('date',p_transaction_date,'direction',p_direction,'amount',p_amount,'channel',p_payment_channel,'reference',p_reference,'description',p_description)));
  update public.cash_transactions set transaction_date=(p_transaction_date::timestamp at time zone 'UTC')+interval '12 hours',direction=p_direction,amount=p_amount,payment_channel=p_payment_channel,reference=nullif(trim(coalesce(p_reference,'')),''),description=trim(p_description)
  where id=v_tx.id;
  if public.cash_method_balance(v_tx.payment_channel,now(),null)<0 then raise exception 'Modification refusée : le solde du moyen de paiement d’origine deviendrait négatif.'; end if;
  if public.cash_method_balance(p_payment_channel,now(),null)<0 then raise exception 'Modification refusée : le solde du moyen de paiement choisi deviendrait négatif.'; end if;
end $$;
revoke all on function public.update_manual_cash_movement(uuid,text,bigint,date,text,text,text,text) from public,anon;
grant execute on function public.update_manual_cash_movement(uuid,text,bigint,date,text,text,text,text) to authenticated;

create or replace function public.delete_manual_cash_movement(p_transaction_id uuid,p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_tx public.cash_transactions%rowtype; v_uid uuid:=auth.uid(); v_main_cash_id uuid;
begin
  if v_uid is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Suppression réservée à l’administration ou à la comptabilité.' using errcode='42501'; end if;
  select * into v_tx from public.cash_transactions t where t.id=p_transaction_id for update;
  if not found then raise exception 'Mouvement introuvable.'; end if;
  select a.id into v_main_cash_id from public.cash_accounts a where a.is_active and a.kind::text='cash' order by (a.code='CAISSE') desc,a.created_at,a.id limit 1;
  if v_main_cash_id is null or v_tx.account_id<>v_main_cash_id then raise exception 'Cette ligne ne fait pas partie du registre unique de caisse principal.'; end if;
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
COMMIT;

-- ============================================================
-- MIGRATION 024_student_fees_tariffs_and_status.sql
-- ============================================================
BEGIN;
-- EPC BETHEL V1.19.0 — Dossier élève, tarifs par classe/année, réductions ciblées et statut d'abandon.
-- Cette migration conserve les charges existantes : les changements de tarifs futurs ne réécrivent
-- jamais les montants historiques déjà attribués aux élèves.

alter table public.students
  add column if not exists address text,
  add column if not exists contact_phone text,
  add column if not exists contact_email text,
  add column if not exists administrative_status text not null default 'active';

alter table public.students drop constraint if exists students_administrative_status_check;
alter table public.students add constraint students_administrative_status_check
  check (administrative_status in ('active','abandon'));

alter table public.enrollments drop constraint if exists enrollments_status_check;
alter table public.enrollments add constraint enrollments_status_check
  check (status in ('inscrit','reinscrit','transfere','sorti','annule','abandon'));

create table if not exists public.class_fee_tariffs (
  id uuid primary key default gen_random_uuid(),
  school_year_id uuid not null references public.school_years(id) on delete restrict,
  class_id uuid not null references public.classes(id) on delete restrict,
  fee_category_id uuid not null references public.fee_categories(id) on delete restrict,
  gross_amount bigint not null check (gross_amount >= 0),
  installment_count smallint not null default 6 check (installment_count between 1 and 6),
  due_dates date[] not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique (school_year_id,class_id,fee_category_id),
  check (cardinality(due_dates)=installment_count),
  check (array_position(due_dates,null) is null)
);
create index if not exists class_fee_tariffs_lookup_idx
  on public.class_fee_tariffs(school_year_id,class_id,is_active);

alter table public.enrollment_concessions
  add column if not exists fee_category_id uuid references public.fee_categories(id) on delete restrict;

alter table public.class_fee_tariffs enable row level security;
drop policy if exists class_fee_tariffs_read on public.class_fee_tariffs;
create policy class_fee_tariffs_read on public.class_fee_tariffs for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]));
drop policy if exists class_fee_tariffs_insert on public.class_fee_tariffs;
create policy class_fee_tariffs_insert on public.class_fee_tariffs for insert to authenticated
with check (public.has_any_role(array['admin','direction']::public.app_role[]));
drop policy if exists class_fee_tariffs_update on public.class_fee_tariffs;
create policy class_fee_tariffs_update on public.class_fee_tariffs for update to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));
grant select,insert,update on public.class_fee_tariffs to authenticated;

-- Les catégories sont paramétrables par la direction ; la désactivation est préférée à la suppression
-- afin de préserver l'historique des frais et les reçus.
drop policy if exists fee_categories_manage_admin on public.fee_categories;
create policy fee_categories_manage_admin on public.fee_categories for all to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));
grant select,insert,update on public.fee_categories to authenticated;

create or replace function public.apply_class_fee_tariffs(p_enrollment_id uuid)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_enrollment public.enrollments%rowtype;
  v_tariff record;
  v_concession public.enrollment_concessions%rowtype;
  v_charge uuid;
  v_discount bigint;
  v_net bigint;
  v_count integer;
  v_i integer;
  v_base bigint;
  v_remainder bigint;
  v_created integer := 0;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à attribuer des frais scolaires' using errcode='42501';
  end if;
  select * into v_enrollment from public.enrollments e
  where e.id=p_enrollment_id and e.status in ('inscrit','reinscrit') for update;
  if not found then raise exception 'Inscription active introuvable'; end if;
  if exists(select 1 from public.school_years y where y.id=v_enrollment.school_year_id and y.is_closed) then
    raise exception 'L’année scolaire est clôturée ; les tarifs ne peuvent pas être attribués à cette inscription';
  end if;

  for v_tariff in
    select t.*,fc.code as fee_code,fc.name as fee_name,fc.kind::text as fee_kind
    from public.class_fee_tariffs t
    join public.fee_categories fc on fc.id=t.fee_category_id and fc.is_active
    where t.school_year_id=v_enrollment.school_year_id and t.class_id=v_enrollment.class_id and t.is_active
    order by fc.kind,fc.name
  loop
    -- Un frais manuel ou issu d'un tarif déjà créé ne doit pas être dupliqué pour l'inscription.
    if exists(select 1 from public.student_charges c
      where c.enrollment_id=p_enrollment_id and c.fee_category_id=v_tariff.fee_category_id) then
      continue;
    end if;
    if cardinality(v_tariff.due_dates)<>v_tariff.installment_count or array_position(v_tariff.due_dates,null) is not null then
      raise exception 'Les échéances configurées pour % sont incomplètes',v_tariff.fee_name;
    end if;
    for v_i in 2..v_tariff.installment_count loop
      if v_tariff.due_dates[v_i] < v_tariff.due_dates[v_i-1] then
        raise exception 'Les dates des échéances de % ne sont pas chronologiques',v_tariff.fee_name;
      end if;
    end loop;

    v_discount := 0;
    v_concession := null;
    select c.* into v_concession
      from public.enrollment_concessions c
     where c.enrollment_id=p_enrollment_id and c.status='approved'
       and (c.valid_from is null or c.valid_from<=current_date)
       and (c.valid_to is null or c.valid_to>=current_date)
       and ((c.fee_category_id is not null and c.fee_category_id=v_tariff.fee_category_id)
         or (c.fee_category_id is null and (c.scope='all_eligible' or c.scope=v_tariff.fee_kind)))
     order by c.approved_at desc nulls last,c.requested_at desc
     limit 1;
    if found then
      if v_concession.kind='percentage' then
        v_discount := round(v_tariff.gross_amount*v_concession.percentage/100.0)::bigint;
      else
        -- Une réduction fixe globale est un plafond pour l'ensemble de son périmètre,
        -- pas un nouveau montant complet à répéter sur chaque catégorie.
        v_discount := least(
          v_tariff.gross_amount,
          greatest(coalesce(v_concession.fixed_amount,0) - coalesce((
            select sum(c.discount_amount)::bigint
            from public.student_charges c
            where c.concession_id=v_concession.id and c.status='validated'
          ),0),0)
        );
      end if;
    end if;
    v_discount := least(greatest(v_discount,0),v_tariff.gross_amount);
    v_net := v_tariff.gross_amount-v_discount;
    insert into public.student_charges(
      enrollment_id,fee_category_id,description,amount_due,gross_amount,discount_amount,concession_id,due_on,status,source,created_by
    ) values (
      p_enrollment_id,v_tariff.fee_category_id,v_tariff.fee_name,v_net,v_tariff.gross_amount,v_discount,
      case when v_discount>0 then v_concession.id else null end,v_tariff.due_dates[v_tariff.installment_count],
      'validated','tariff_template',v_user
    ) returning id into v_charge;
    v_count:=v_tariff.installment_count;
    v_base:=v_net/v_count;
    v_remainder:=mod(v_net,v_count);
    for v_i in 1..v_count loop
      insert into public.installments(charge_id,installment_no,amount_due,due_on,created_by)
      values(v_charge,v_i,v_base+case when v_i<=v_remainder then 1 else 0 end,v_tariff.due_dates[v_i],v_user);
    end loop;
    v_created:=v_created+1;
    insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
    values(v_user,'school_fee_tariff.applied','student_charges',v_charge::text,
      jsonb_build_object('enrollment_id',p_enrollment_id,'tariff_id',v_tariff.id,'fee_category_id',v_tariff.fee_category_id,
        'gross_amount',v_tariff.gross_amount,'discount_amount',v_discount,'amount_due',v_net,'installments',v_count));
  end loop;
  return v_created;
end;
$$;
revoke all on function public.apply_class_fee_tariffs(uuid) from public,anon;
grant execute on function public.apply_class_fee_tariffs(uuid) to authenticated;

-- Ajoute l'application atomique des tarifs lors d'une inscription. Les valeurs de tarif sont copiées
-- dans student_charges et installments ; elles ne changent donc pas lors d'une modification future.
create or replace function public.create_school_enrollment(
  p_student_id uuid,
  p_school_year_id uuid,
  p_class_id uuid,
  p_enrolled_on date default current_date,
  p_enrollment_type text default 'inscrit',
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_enrollment uuid; v_year_label text;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à inscrire un élève' using errcode='42501';
  end if;
  if p_student_id is null or p_school_year_id is null or p_class_id is null then raise exception 'L’élève, l’année scolaire et la classe sont obligatoires'; end if;
  if p_enrollment_type not in ('inscrit','reinscrit') then raise exception 'Type d’inscription invalide'; end if;
  if not exists(select 1 from public.students s where s.id=p_student_id and s.status='actif'::public.student_status) then raise exception 'L’élève n’existe pas ou son dossier n’est pas actif'; end if;
  select sy.label into v_year_label from public.school_years sy where sy.id=p_school_year_id and sy.is_current and not sy.is_closed;
  if not found then raise exception 'Sélectionnez l’année scolaire active et non clôturée'; end if;
  if not exists(select 1 from public.classes c where c.id=p_class_id and c.is_active) then raise exception 'La classe n’existe pas ou n’est plus active'; end if;
  insert into public.enrollments(student_id,school_year_id,class_id,enrolled_on,status,notes,created_by)
  values(p_student_id,p_school_year_id,p_class_id,coalesce(p_enrolled_on,current_date),p_enrollment_type,nullif(trim(p_notes),''),v_user)
  returning id into v_enrollment;
  update public.students set administrative_status='active',updated_at=now() where id=p_student_id;
  perform public.apply_class_fee_tariffs(v_enrollment);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'enrollment.created','enrollments',v_enrollment::text,jsonb_build_object('student_id',p_student_id,'school_year_id',p_school_year_id,'school_year_label',v_year_label,'class_id',p_class_id,'status',p_enrollment_type));
  return v_enrollment;
end;
$$;
revoke all on function public.create_school_enrollment(uuid,uuid,uuid,date,text,text) from public,anon;
grant execute on function public.create_school_enrollment(uuid,uuid,uuid,date,text,text) to authenticated;

-- Abandon administratif distinct : on conserve les charges et le solde ; aucune remise automatique.
create or replace function public.abandon_school_enrollment(
  p_enrollment_id uuid,
  p_exit_date date default current_date,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_student_id uuid; v_student_name text; v_year_current boolean; v_year_closed boolean;
begin
  if v_user is null or not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Accès refusé : abandon réservé à la direction, au secrétariat ou à l’administration.' using errcode='42501';
  end if;
  select e.student_id,sy.is_current,sy.is_closed,s.last_name||' '||s.first_names into v_student_id,v_year_current,v_year_closed,v_student_name
  from public.enrollments e join public.school_years sy on sy.id=e.school_year_id join public.students s on s.id=e.student_id
  where e.id=p_enrollment_id and e.status in ('inscrit','reinscrit') for update of e;
  if not found then raise exception 'Inscription active introuvable'; end if;
  if not v_year_current or v_year_closed then raise exception 'L’abandon doit être enregistré sur une année en cours non clôturée'; end if;
  update public.enrollments set status='abandon',notes=concat_ws(E'\n',nullif(notes,''),'Abandon le '||coalesce(p_exit_date,current_date)::text||case when nullif(trim(p_reason),'') is not null then ' ; motif : '||trim(p_reason) else '' end)
  where id=p_enrollment_id;
  update public.students set administrative_status='abandon',updated_at=now() where id=v_student_id;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'student.abandoned','enrollments',p_enrollment_id::text,jsonb_build_object('student_id',v_student_id,'student_name',v_student_name,'date',coalesce(p_exit_date,current_date),'reason',nullif(trim(p_reason),''),'financial_charges_preserved',true));
end;
$$;
revoke all on function public.abandon_school_enrollment(uuid,date,text) from public,anon;
grant execute on function public.abandon_school_enrollment(uuid,date,text) to authenticated;

-- Création d'un dossier et, si la classe et l'année sont fournies, de son inscription en une seule transaction.
create or replace function public.create_student_profile_with_enrollment(
  p_student_number text,
  p_last_name text,
  p_first_names text,
  p_sex text,
  p_birth_date date,
  p_birth_place text,
  p_address text,
  p_contact_phone text,
  p_contact_email text,
  p_guardian_name text,
  p_guardian_phone text,
  p_guardian_email text,
  p_guardian_occupation text,
  p_guardian_address text,
  p_guardian_relationship text,
  p_notes text,
  p_class_id uuid,
  p_school_year_id uuid,
  p_enrolled_on date,
  p_enrollment_type text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_student uuid; v_enrollment uuid; v_number text;
begin
  if v_user is null or not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then raise exception 'Accès refusé à la création du dossier élève.' using errcode='42501'; end if;
  if nullif(trim(p_last_name),'') is null or nullif(trim(p_first_names),'') is null then raise exception 'Le nom et les prénoms sont obligatoires'; end if;
  if (p_class_id is null) <> (p_school_year_id is null) then raise exception 'Pour inscrire l’élève, choisissez à la fois une classe et une année scolaire'; end if;
  v_student:=public.create_student_with_guardian(p_student_number,p_last_name,p_first_names,p_sex,p_birth_date,p_birth_place,p_guardian_name,p_guardian_phone,p_guardian_address,p_notes,p_guardian_email,p_guardian_occupation,p_guardian_relationship);
  update public.students set address=nullif(trim(p_address),''),contact_phone=nullif(trim(p_contact_phone),''),contact_email=nullif(trim(p_contact_email),'') where id=v_student;
  if p_class_id is not null then
    v_enrollment:=public.create_school_enrollment(v_student,p_school_year_id,p_class_id,coalesce(p_enrolled_on,current_date),coalesce(nullif(p_enrollment_type,''),'inscrit'),p_notes);
  end if;
  select student_number into v_number from public.students where id=v_student;
  return jsonb_build_object('student_id',v_student,'student_number',v_number,'enrollment_id',v_enrollment);
end;
$$;
revoke all on function public.create_student_profile_with_enrollment(text,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text,uuid,uuid,date,text) from public,anon;
grant execute on function public.create_student_profile_with_enrollment(text,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text,uuid,uuid,date,text) to authenticated;

create or replace function public.update_student_profile_with_guardian(
  p_student_id uuid,
  p_student_number text,
  p_last_name text,
  p_first_names text,
  p_sex text,
  p_birth_date date,
  p_birth_place text,
  p_address text,
  p_contact_phone text,
  p_contact_email text,
  p_guardian_name text,
  p_guardian_phone text,
  p_guardian_email text,
  p_guardian_occupation text,
  p_guardian_address text,
  p_guardian_relationship text,
  p_notes text
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.update_student_with_guardian(p_student_id,p_student_number,p_last_name,p_first_names,p_sex,p_birth_date,p_birth_place,p_guardian_name,p_guardian_phone,p_guardian_address,p_notes,p_guardian_email,p_guardian_occupation,p_guardian_relationship);
  update public.students set address=nullif(trim(p_address),''),contact_phone=nullif(trim(p_contact_phone),''),contact_email=nullif(trim(p_contact_email),'') where id=p_student_id;
end;
$$;
revoke all on function public.update_student_profile_with_guardian(uuid,text,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.update_student_profile_with_guardian(uuid,text,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text) to authenticated;

-- Nouvelle demande de réduction ciblée : la demande est conservée dans l'historique même si elle est refusée.
create or replace function public.request_enrollment_concession_scoped(
  p_enrollment_id uuid,
  p_fee_category_id uuid default null,
  p_scope text default 'all_eligible',
  p_kind public.concession_kind default 'percentage',
  p_percentage numeric default null,
  p_fixed_amount bigint default null,
  p_reason_code text default 'reduction_particuliere',
  p_reason_detail text default null,
  p_valid_from date default null,
  p_valid_to date default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_scope text; v_kind text; v_code text;
begin
  if v_user is null or not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Accès refusé à la demande de réduction' using errcode='42501';
  end if;
  if p_kind='percentage' and (p_percentage is null or p_percentage<0 or p_percentage>100 or p_fixed_amount is not null) then raise exception 'Pourcentage invalide'; end if;
  if p_kind='fixed_amount' and (p_fixed_amount is null or p_fixed_amount<0 or p_percentage is not null) then raise exception 'Montant de réduction invalide'; end if;
  if p_valid_from is not null and p_valid_to is not null and p_valid_to<p_valid_from then raise exception 'La date de fin précède la date de début'; end if;
  if p_scope not in ('all_eligible','scolarite','inscription','annexe') then raise exception 'Périmètre de réduction invalide'; end if;
  if p_fee_category_id is not null then
    select kind::text,code into v_kind,v_code from public.fee_categories where id=p_fee_category_id and is_active;
    if not found then raise exception 'Catégorie de frais active introuvable'; end if;
    v_scope:=case when v_kind in ('scolarite','inscription','annexe') then v_kind else 'annexe' end;
  else
    v_scope:='all_eligible';
  end if;
  perform 1 from public.enrollments e where e.id=p_enrollment_id and e.status in ('inscrit','reinscrit') for update;
  if not found then raise exception 'Inscription active introuvable'; end if;
  if exists (
    select 1 from public.enrollment_concessions c
    where c.enrollment_id=p_enrollment_id and c.status in ('requested','approved')
      and (c.valid_to is null or c.valid_to>=coalesce(p_valid_from,current_date))
      and (p_valid_to is null or c.valid_from is null or c.valid_from<=p_valid_to)
      and (p_fee_category_id is null or c.fee_category_id is null or c.fee_category_id=p_fee_category_id)
  ) then raise exception 'Une demande active couvre déjà ces frais pour une période qui se chevauche'; end if;
  insert into public.enrollment_concessions(enrollment_id,scope,fee_category_id,kind,percentage,fixed_amount,reason_code,reason_detail,status,requested_by,valid_from,valid_to)
  values(p_enrollment_id,v_scope,p_fee_category_id,p_kind,p_percentage,p_fixed_amount,
    coalesce(nullif(trim(p_reason_code),''),'reduction_particuliere'),nullif(trim(p_reason_detail),''),'requested',v_user,p_valid_from,p_valid_to)
  returning id into v_id;
  insert into public.concession_events(concession_id,event_type,actor_id,reason,after_data)
  values(v_id,'requested',v_user,coalesce(nullif(trim(p_reason_detail),''),p_reason_code),jsonb_build_object('scope',v_scope,'fee_category_id',p_fee_category_id,'kind',p_kind,'percentage',p_percentage,'fixed_amount',p_fixed_amount,'valid_from',p_valid_from,'valid_to',p_valid_to));
  return v_id;
end;
$$;
revoke all on function public.request_enrollment_concession_scoped(uuid,uuid,text,public.concession_kind,numeric,bigint,text,text,date,date) from public,anon;
grant execute on function public.request_enrollment_concession_scoped(uuid,uuid,text,public.concession_kind,numeric,bigint,text,text,date,date) to authenticated;

-- Synthèse compatible avec un filtre par code ou par type de frais (kind:scolarite, kind:annexe, etc.).
create or replace function public.get_school_fee_summary(
  p_school_year_id uuid default null,
  p_class_id uuid default null,
  p_fee_code text default null
) returns table(
  gross_total bigint, discount_total bigint, amount_due_total bigint, amount_paid_total bigint,
  balance_due_total bigint, overdue_total bigint, charge_count bigint
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]) then
    raise exception 'Accès refusé à la synthèse des frais scolaires.' using errcode='42501';
  end if;
  return query
  with charge_rows as (
    select c.id,coalesce(c.gross_amount,c.amount_due)::bigint gross_amount,
      coalesce(c.discount_amount,0)::bigint discount_amount,c.amount_due::bigint amount_due,
      coalesce(paid.amount_paid,0)::bigint amount_paid,coalesce(overdue.overdue_amount,0)::bigint overdue_amount
    from public.student_charges c
    join public.enrollments e on e.id=c.enrollment_id
    join public.fee_categories fc on fc.id=c.fee_category_id
    left join lateral (
      select coalesce(sum(pa.amount),0)::bigint amount_paid from public.payment_allocations pa
      join public.payments p on p.id=pa.payment_id and p.status='validated'
       and p.paid_at < ((current_date+1)::timestamp at time zone 'UTC') where pa.charge_id=c.id
    ) paid on true
    left join lateral (
      select case when exists(select 1 from public.installments ix where ix.charge_id=c.id) then
        coalesce((select sum(greatest(i.amount_due-coalesce(ip.paid_amount,0),0))::bigint
          from public.installments i left join lateral (
            select coalesce(sum(pa.amount),0)::bigint paid_amount from public.payment_allocations pa
            join public.payments p on p.id=pa.payment_id and p.status='validated'
             and p.paid_at < ((current_date+1)::timestamp at time zone 'UTC') where pa.installment_id=i.id
          ) ip on true where i.charge_id=c.id and i.due_on<current_date),0)::bigint
      when c.due_on is not null and c.due_on<current_date then greatest(c.amount_due-coalesce(paid.amount_paid,0),0)::bigint else 0::bigint end overdue_amount
    ) overdue on true
    where c.status='validated' and (p_school_year_id is null or e.school_year_id=p_school_year_id)
      and (p_class_id is null or e.class_id=p_class_id)
      and (nullif(trim(p_fee_code),'') is null
        or (left(trim(p_fee_code),5)='kind:' and fc.kind::text=substring(trim(p_fee_code) from 6))
        or (left(trim(p_fee_code),5)<>'kind:' and fc.code=trim(p_fee_code)))
  )
  select coalesce(sum(gross_amount),0)::bigint,coalesce(sum(discount_amount),0)::bigint,
    coalesce(sum(amount_due),0)::bigint,coalesce(sum(amount_paid),0)::bigint,
    coalesce(sum(greatest(amount_due-amount_paid,0)),0)::bigint,coalesce(sum(overdue_amount),0)::bigint,count(*)::bigint
  from charge_rows;
end;
$$;
revoke all on function public.get_school_fee_summary(uuid,uuid,text) from public,anon;
grant execute on function public.get_school_fee_summary(uuid,uuid,text) to authenticated;

-- Soldes par catégorie d'un élève ; seuls les paiements validés réduisent le reste dû.
create or replace function public.get_enrollment_fee_balances(p_enrollment_id uuid)
returns table(fee_category_id uuid,fee_code text,fee_name text,fee_kind text,gross_due bigint,discount_total bigint,net_due bigint,paid_total bigint,balance_due bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]) then raise exception 'Accès refusé' using errcode='42501'; end if;
  if not exists(select 1 from public.enrollments where id=p_enrollment_id) then raise exception 'Inscription introuvable'; end if;
  return query
  select fc.id,fc.code,fc.name,fc.kind::text,
    coalesce(sum(coalesce(c.gross_amount,c.amount_due)),0)::bigint,
    coalesce(sum(coalesce(c.discount_amount,0)),0)::bigint,
    coalesce(sum(c.amount_due),0)::bigint,
    coalesce(sum(coalesce(p.paid_amount,0)),0)::bigint,
    greatest(coalesce(sum(c.amount_due-coalesce(p.paid_amount,0)),0),0)::bigint
  from public.fee_categories fc
  join public.student_charges c on c.fee_category_id=fc.id and c.enrollment_id=p_enrollment_id and c.status='validated'
  left join lateral (select coalesce(sum(pa.amount) filter(where pm.status='validated' and pm.paid_at<((current_date+1)::timestamp at time zone 'UTC')),0)::bigint paid_amount
    from public.payment_allocations pa join public.payments pm on pm.id=pa.payment_id where pa.charge_id=c.id) p on true
  group by fc.id,fc.code,fc.name,fc.kind order by fc.kind,fc.name;
end;
$$;
revoke all on function public.get_enrollment_fee_balances(uuid) from public,anon;
grant execute on function public.get_enrollment_fee_balances(uuid) to authenticated;

-- Encaissement restreint à une catégorie précise, avec idempotence et affectation transactionnelle.
create or replace function public.register_student_payment_for_fee_with_provider(
  p_enrollment_id uuid,
  p_fee_category_id uuid,
  p_amount bigint,
  p_method public.payment_method,
  p_account_id uuid,
  p_paid_at timestamptz default now(),
  p_payer_name text default null,
  p_external_reference text default null,
  p_notes text default null,
  p_mobile_money_provider text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid:=auth.uid(); v_receipt text; v_payment_id uuid; v_existing public.payments%rowtype;
  v_remaining bigint; v_total_due bigint; v_open bigint; v_charge record; v_installment record; v_take bigint; v_account public.cash_accounts%rowtype;
begin
  if v_user is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Seule la comptabilité ou l’administration peut enregistrer un encaissement' using errcode='42501'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Le montant doit être strictement positif'; end if;
  if p_enrollment_id is null or p_fee_category_id is null then raise exception 'Sélectionnez l’inscription et la catégorie de frais'; end if;
  if p_paid_at is null or (p_paid_at at time zone 'UTC')::date>current_date then raise exception 'La date de paiement est obligatoire et ne peut pas être future'; end if;
  if p_method::text='mobile_money' and coalesce(p_mobile_money_provider,'') not in ('orange_money','wave','moov_money') then raise exception 'Sélectionnez Orange Money, Wave ou Moov Money'; end if;
  if p_method::text<>'mobile_money' and p_mobile_money_provider is not null then raise exception 'Le fournisseur Mobile Money est réservé à ce mode'; end if;
  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtext(p_idempotency_key));
    select * into v_existing from public.payments where idempotency_key=p_idempotency_key for update;
    if found then
      if v_existing.enrollment_id<>p_enrollment_id or v_existing.amount<>p_amount then raise exception 'Cette clé d’enregistrement a déjà été utilisée pour un autre paiement'; end if;
      if not exists(select 1 from public.payment_allocations pa join public.student_charges c on c.id=pa.charge_id where pa.payment_id=v_existing.id and c.fee_category_id=p_fee_category_id) then raise exception 'Cette clé d’enregistrement correspond à une autre catégorie de frais'; end if;
      return jsonb_build_object('id',v_existing.id,'receipt_number',v_existing.receipt_number,'amount',v_existing.amount,'status',v_existing.status,'duplicate',true);
    end if;
  end if;
  perform 1 from public.enrollments e where e.id=p_enrollment_id and e.status in ('inscrit','reinscrit') for update;
  if not found then raise exception 'Inscription active introuvable'; end if;
  select * into v_account from public.cash_accounts where id=p_account_id and is_active for update;
  if not found then raise exception 'Compte de trésorerie inactif ou introuvable'; end if;
  if not exists(select 1 from public.student_charges where enrollment_id=p_enrollment_id and fee_category_id=p_fee_category_id and status='validated') then raise exception 'Aucun frais validé dans cette catégorie pour cet élève'; end if;
  select coalesce(sum(greatest(c.amount_due-coalesce(paid.amount_paid,0),0)),0)::bigint into v_total_due
  from public.student_charges c left join lateral (
    select coalesce(sum(pa.amount),0)::bigint amount_paid from public.payment_allocations pa join public.payments pm on pm.id=pa.payment_id and pm.status='validated' and pm.paid_at<((current_date+1)::timestamp at time zone 'UTC') where pa.charge_id=c.id
  ) paid on true where c.enrollment_id=p_enrollment_id and c.fee_category_id=p_fee_category_id and c.status='validated';
  if v_total_due<=0 then raise exception 'Cette catégorie de frais est déjà soldée'; end if;
  if p_amount>v_total_due then raise exception 'Le versement dépasse le solde restant de cette catégorie (%)',v_total_due; end if;
  v_receipt:=public.allocate_receipt_number(p_paid_at);
  insert into public.payments(receipt_number,enrollment_id,paid_at,amount,method,account_id,external_reference,payer_name,notes,status,created_by,idempotency_key,mobile_money_provider)
  values(v_receipt,p_enrollment_id,p_paid_at,p_amount,p_method,p_account_id,nullif(trim(p_external_reference),''),nullif(trim(p_payer_name),''),nullif(trim(p_notes),''),'draft',v_user,nullif(trim(p_idempotency_key),''),p_mobile_money_provider)
  returning id into v_payment_id;
  v_remaining:=p_amount;
  for v_installment in
    select i.id installment_id,i.charge_id,i.amount_due,i.due_on,i.installment_no
    from public.installments i join public.student_charges c on c.id=i.charge_id
    where c.enrollment_id=p_enrollment_id and c.fee_category_id=p_fee_category_id and c.status='validated'
    order by i.due_on,i.installment_no,i.id
  loop
    exit when v_remaining=0;
    select greatest(v_installment.amount_due-coalesce(sum(pa.amount) filter(where pm.status='validated' and pm.paid_at<((current_date+1)::timestamp at time zone 'UTC')),0),0)::bigint into v_open
    from public.payment_allocations pa join public.payments pm on pm.id=pa.payment_id where pa.installment_id=v_installment.installment_id;
    if v_open>0 then v_take:=least(v_open,v_remaining); insert into public.payment_allocations(payment_id,charge_id,installment_id,amount,created_by) values(v_payment_id,v_installment.charge_id,v_installment.installment_id,v_take,v_user); v_remaining:=v_remaining-v_take; end if;
  end loop;
  for v_charge in
    select c.id,c.amount_due from public.student_charges c where c.enrollment_id=p_enrollment_id and c.fee_category_id=p_fee_category_id and c.status='validated' and not exists(select 1 from public.installments i where i.charge_id=c.id) order by c.due_on nulls last,c.created_at,c.id
  loop
    exit when v_remaining=0;
    select greatest(v_charge.amount_due-coalesce(sum(pa.amount) filter(where pm.status='validated' and pm.paid_at<((current_date+1)::timestamp at time zone 'UTC')),0),0)::bigint into v_open from public.payment_allocations pa join public.payments pm on pm.id=pa.payment_id where pa.charge_id=v_charge.id;
    if v_open>0 then v_take:=least(v_open,v_remaining); insert into public.payment_allocations(payment_id,charge_id,installment_id,amount,created_by) values(v_payment_id,v_charge.id,null,v_take,v_user); v_remaining:=v_remaining-v_take; end if;
  end loop;
  if v_remaining<>0 then raise exception 'Affectation de paiement incomplète ; opération annulée'; end if;
  perform public.validate_payment(v_payment_id);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details) values(v_user,'student_payment.for_fee','payments',v_payment_id::text,jsonb_build_object('fee_category_id',p_fee_category_id,'enrollment_id',p_enrollment_id,'amount',p_amount,'idempotency_key',p_idempotency_key));
  return jsonb_build_object('id',v_payment_id,'receipt_number',v_receipt,'amount',p_amount,'status','validated');
end;
$$;
revoke all on function public.register_student_payment_for_fee_with_provider(uuid,uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text,text,text) from public,anon;
grant execute on function public.register_student_payment_for_fee_with_provider(uuid,uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text,text,text) to authenticated;

-- Suppression contrôlée des notes : permission explicite et trace d’audit avant l’effacement.
create or replace function public.school_grade_audit_delete()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(auth.uid(),'grade.deleted','student_grades',old.id::text,jsonb_build_object('enrollment_id',old.enrollment_id,'subject_id',old.subject_id,'term',old.term,'assessment_label',old.assessment_label,'score',old.score,'score_max',old.score_max,'reason','Suppression depuis le formulaire de gestion des notes'));
  return old;
end;
$$;
drop trigger if exists student_grades_audit_delete on public.student_grades;
create trigger student_grades_audit_delete before delete on public.student_grades for each row execute function public.school_grade_audit_delete();
drop policy if exists student_grades_delete on public.student_grades;
create policy student_grades_delete on public.student_grades for delete to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));
grant delete on public.student_grades to authenticated;



-- Garde-fous serveur sur la modification/suppression des notes.
-- L'interface applique les mêmes règles, mais PostgreSQL doit aussi les garantir.
create or replace function public.guard_student_grade_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_school_year_closed boolean := false;
begin
  if tg_op = 'UPDATE' and new.enrollment_id is distinct from old.enrollment_id then
    raise exception 'Une note ne peut pas être déplacée vers un autre dossier élève';
  end if;

  select sy.is_closed into v_school_year_closed
  from public.enrollments e
  join public.school_years sy on sy.id=e.school_year_id
  where e.id=old.enrollment_id;
  if coalesce(v_school_year_closed,false) then
    raise exception 'Les notes d’une année scolaire clôturée ne peuvent plus être modifiées';
  end if;

  if old.assessment_id is not null and exists(
    select 1 from public.school_assessments a where a.id=old.assessment_id and a.status in ('locked','cancelled')
  ) then
    raise exception 'Cette évaluation est verrouillée ou annulée';
  end if;
  if tg_op = 'UPDATE' and new.assessment_id is not null and exists(
    select 1 from public.school_assessments a where a.id=new.assessment_id and a.status in ('locked','cancelled')
  ) then
    raise exception 'Impossible d’associer une note à une évaluation verrouillée ou annulée';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.guard_student_grade_mutation() from public,anon;
drop trigger if exists student_grades_mutation_guard on public.student_grades;
create trigger student_grades_mutation_guard
before update or delete on public.student_grades
for each row execute function public.guard_student_grade_mutation();

-- À l'approbation d'une réduction, ne pas réécrire un frais qui a déjà reçu un paiement validé.
-- Les frais non réglés sont recalculés ; un événement conserve les montants modifiés et les frais ignorés.
create or replace function public.decide_enrollment_concession(
  p_concession_id uuid,
  p_approve boolean,
  p_decision_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_concession public.enrollment_concessions%rowtype;
  v_charge record;
  v_installment record;
  v_gross bigint;
  v_discount bigint;
  v_net bigint;
  v_fixed_remaining bigint;
  v_installment_count integer;
  v_base bigint;
  v_remainder bigint;
  v_updated_count integer := 0;
  v_skipped_count integer := 0;
  v_changed jsonb := '[]'::jsonb;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Seuls la direction et l’administration peuvent décider une concession' using errcode='42501';
  end if;
  select * into v_concession from public.enrollment_concessions where id=p_concession_id for update;
  if not found then raise exception 'Demande de réduction introuvable'; end if;
  if v_concession.status <> 'requested' then raise exception 'Cette demande a déjà été traitée'; end if;
  perform 1 from public.enrollments where id=v_concession.enrollment_id for update;

  if p_approve and exists(
    select 1 from public.enrollment_concessions c
    where c.enrollment_id=v_concession.enrollment_id and c.id<>p_concession_id and c.status='approved'
      and (c.valid_from is null or c.valid_from<=coalesce(v_concession.valid_to,current_date))
      and (c.valid_to is null or c.valid_to>=coalesce(v_concession.valid_from,current_date))
      and (
        (v_concession.fee_category_id is not null and (c.fee_category_id=v_concession.fee_category_id or (c.fee_category_id is null and c.scope='all_eligible')))
        or (v_concession.fee_category_id is null and (v_concession.scope='all_eligible' or c.scope='all_eligible' or c.scope=v_concession.scope))
      )
  ) then
    raise exception 'Une réduction approuvée chevauche déjà cette catégorie ou cette période';
  end if;

  if p_approve then
    update public.enrollment_concessions
      set status='approved',approved_by=v_user,approved_at=now(),decision_note=nullif(trim(p_decision_note),'')
      where id=p_concession_id;

    if (v_concession.valid_from is null or v_concession.valid_from<=current_date)
      and (v_concession.valid_to is null or v_concession.valid_to>=current_date) then
      select count(*) into v_skipped_count
      from public.student_charges c join public.fee_categories fc on fc.id=c.fee_category_id
      where c.enrollment_id=v_concession.enrollment_id and c.status='validated'
        and coalesce(c.discount_amount,0)=0 and c.concession_id is null
        and ((v_concession.fee_category_id is not null and c.fee_category_id=v_concession.fee_category_id)
          or (v_concession.fee_category_id is null and (v_concession.scope='all_eligible' or v_concession.scope=fc.kind::text)))
        and exists(select 1 from public.payment_allocations pa join public.payments p on p.id=pa.payment_id and p.status='validated' where pa.charge_id=c.id);

      v_fixed_remaining := coalesce(v_concession.fixed_amount,0);
      for v_charge in
        select c.id,c.amount_due,c.gross_amount,c.fee_category_id,c.description
        from public.student_charges c join public.fee_categories fc on fc.id=c.fee_category_id
        where c.enrollment_id=v_concession.enrollment_id and c.status='validated'
          and coalesce(c.discount_amount,0)=0 and c.concession_id is null
          and ((v_concession.fee_category_id is not null and c.fee_category_id=v_concession.fee_category_id)
            or (v_concession.fee_category_id is null and (v_concession.scope='all_eligible' or v_concession.scope=fc.kind::text)))
          and not exists(select 1 from public.payment_allocations pa join public.payments p on p.id=pa.payment_id and p.status='validated' where pa.charge_id=c.id)
        order by c.due_on nulls last,c.created_at,c.id
        for update of c
      loop
        v_gross := coalesce(v_charge.gross_amount,v_charge.amount_due);
        if v_concession.kind='percentage' then
          v_discount := round(v_gross*coalesce(v_concession.percentage,0)/100.0)::bigint;
        else
          exit when v_fixed_remaining<=0;
          v_discount := least(v_gross,v_fixed_remaining);
        end if;
        v_discount := least(greatest(v_discount,0),v_gross);
        if v_discount<=0 then continue; end if;
        v_net := v_gross-v_discount;
        update public.student_charges
          set gross_amount=v_gross,discount_amount=v_discount,amount_due=v_net,concession_id=p_concession_id,updated_at=now()
          where id=v_charge.id;

        select count(*) into v_installment_count from public.installments where charge_id=v_charge.id;
        if v_installment_count>0 then
          v_base := v_net / v_installment_count;
          v_remainder := mod(v_net,v_installment_count);
          for v_installment in select id,installment_no from public.installments where charge_id=v_charge.id order by installment_no for update
          loop
            update public.installments set amount_due=v_base+case when v_installment.installment_no<=v_remainder then 1 else 0 end
            where id=v_installment.id;
          end loop;
        end if;
        v_updated_count := v_updated_count+1;
        v_changed := v_changed || jsonb_build_array(jsonb_build_object('charge_id',v_charge.id,'description',v_charge.description,'gross_amount',v_gross,'discount_amount',v_discount,'net_amount',v_net));
        if v_concession.kind='fixed_amount' then v_fixed_remaining := v_fixed_remaining-v_discount; end if;
      end loop;
    end if;

    insert into public.concession_events(concession_id,event_type,actor_id,reason,after_data)
    values(p_concession_id,'approved',v_user,nullif(trim(p_decision_note),''),jsonb_build_object(
      'status','approved','updated_charges',v_updated_count,'skipped_paid_charges',v_skipped_count,
      'updated_charge_details',v_changed,'valid_from',v_concession.valid_from,'valid_to',v_concession.valid_to,
      'note','Les charges ayant déjà reçu un paiement validé ne sont pas modifiées. Les échéances sans paiement sont redistribuées sans changer les dates.'
    ));
  else
    update public.enrollment_concessions set status='rejected',decision_note=nullif(trim(p_decision_note),'') where id=p_concession_id;
    insert into public.concession_events(concession_id,event_type,actor_id,reason,after_data)
    values(p_concession_id,'rejected',v_user,nullif(trim(p_decision_note),''),jsonb_build_object('status','rejected'));
  end if;
end;
$$;
revoke all on function public.decide_enrollment_concession(uuid,boolean,text) from public,anon;
grant execute on function public.decide_enrollment_concession(uuid,boolean,text) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 025_annual_payment_schedule_and_required_student_class.sql
-- ============================================================
BEGIN;
-- EPC BETHEL V1.20.0
-- Les six dates sont définies dans Paramètres, une fois par année scolaire.
-- Les charges/installments déjà attribués ne sont jamais recalculés par cette migration.

create table if not exists public.school_year_payment_schedules (
  id uuid primary key default gen_random_uuid(),
  school_year_id uuid not null unique references public.school_years(id) on delete restrict,
  due_dates date[] not null,
  is_locked boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_by uuid references public.profiles(id) on delete restrict,
  constraint school_year_payment_schedules_six_dates check (cardinality(due_dates)=6),
  constraint school_year_payment_schedules_no_null check (array_position(due_dates,null) is null)
);

alter table public.school_year_payment_schedules enable row level security;
drop policy if exists school_year_payment_schedules_read on public.school_year_payment_schedules;
create policy school_year_payment_schedules_read on public.school_year_payment_schedules for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]));
revoke all on public.school_year_payment_schedules from anon, authenticated;
grant select on public.school_year_payment_schedules to authenticated;

create or replace function public.save_school_year_payment_schedule(
  p_school_year_id uuid,
  p_due_dates date[],
  p_confirm_change boolean default false
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_year public.school_years%rowtype;
  v_existing date[];
  v_had_existing boolean := false;
  v_changed_tariffs integer := 0;
  v_i integer;
begin
  if v_user is null or not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'La configuration des échéances est réservée à l’administration ou à la direction.' using errcode='42501';
  end if;
  if p_school_year_id is null then raise exception 'Sélectionnez une année scolaire.'; end if;
  if p_due_dates is null or cardinality(p_due_dates) <> 6 or array_position(p_due_dates,null) is not null then
    raise exception 'Renseignez exactement les six échéances annuelles.';
  end if;
  for v_i in 2..6 loop
    if p_due_dates[v_i] <= p_due_dates[v_i-1] then
      raise exception 'Les six échéances doivent être des dates distinctes, classées par ordre chronologique strict.';
    end if;
  end loop;
  select * into v_year from public.school_years where id=p_school_year_id for update;
  if not found then raise exception 'Année scolaire introuvable.'; end if;
  if v_year.is_closed then raise exception 'Les échéances d’une année scolaire clôturée ne peuvent pas être modifiées.'; end if;

  select due_dates into v_existing from public.school_year_payment_schedules where school_year_id=p_school_year_id for update;
  v_had_existing := found;
  if v_had_existing and v_existing is distinct from p_due_dates and not coalesce(p_confirm_change,false) then
    raise exception 'Les échéances de cette année sont déjà fixées. Une correction exceptionnelle doit être confirmée.';
  end if;
  if not v_had_existing and coalesce(p_confirm_change,false) then
    raise exception 'Aucun calendrier existant à corriger. Configurez d’abord les échéances.';
  end if;

  insert into public.school_year_payment_schedules(school_year_id,due_dates,is_locked,created_by,updated_by)
  values(p_school_year_id,p_due_dates,true,v_user,v_user)
  on conflict (school_year_id) do update set due_dates=excluded.due_dates,is_locked=true,updated_at=now(),updated_by=v_user;

  -- Les modèles de tarifs utilisent le calendrier annuel. Les charges et versements déjà créés
  -- conservent leurs échéances enregistrées et ne sont pas modifiés ici.
  update public.class_fee_tariffs
     set due_dates=p_due_dates,installment_count=6,updated_at=now()
   where school_year_id=p_school_year_id;
  get diagnostics v_changed_tariffs = row_count;

  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,case when v_had_existing and v_existing is distinct from p_due_dates then 'school_year_payment_schedule.corrected' else 'school_year_payment_schedule.saved' end,
    'school_year_payment_schedules',p_school_year_id::text,
    jsonb_build_object('school_year_id',p_school_year_id,'due_dates',p_due_dates,'correction_confirmed',coalesce(p_confirm_change,false),'tariff_templates_updated',v_changed_tariffs,'existing_charges_unchanged',true));
  return jsonb_build_object('school_year_id',p_school_year_id,'due_dates',p_due_dates,'locked',true,'tariffs_updated',v_changed_tariffs,'existing_charges_unchanged',true);
end;
$$;
revoke all on function public.save_school_year_payment_schedule(uuid,date[],boolean) from public,anon;
grant execute on function public.save_school_year_payment_schedule(uuid,date[],boolean) to authenticated;

-- Tous les nouveaux frais manuels utilisent eux aussi le calendrier annuel configuré dans Paramètres.
create or replace function public.create_student_charge_with_annual_schedule(
  p_enrollment_id uuid,
  p_fee_code text,
  p_description text,
  p_amount bigint
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_enrollment public.enrollments%rowtype;
  v_category public.fee_categories%rowtype;
  v_dates date[];
  v_concession public.enrollment_concessions%rowtype;
  v_concession_id uuid;
  v_discount bigint := 0;
  v_net bigint;
  v_charge uuid;
  v_i integer;
  v_base bigint;
  v_remainder bigint;
begin
  if v_user is null or not public.has_any_role(array['admin','direction','secretariat','comptabilite']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à créer des frais scolaires.' using errcode='42501';
  end if;
  if p_fee_code not in ('SCOLARITE','INSCRIPTION','ANNEXE','AUTRE') then raise exception 'Catégorie de frais invalide.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Le montant doit être supérieur à zéro.'; end if;
  if nullif(trim(p_description),'') is null then raise exception 'La désignation des frais est obligatoire.'; end if;

  select * into v_enrollment from public.enrollments where id=p_enrollment_id and status in ('inscrit','reinscrit') for update;
  if not found then raise exception 'Inscription active introuvable.'; end if;
  if exists(select 1 from public.school_years where id=v_enrollment.school_year_id and is_closed) then
    raise exception 'Une année clôturée ne peut pas recevoir de nouveaux frais.';
  end if;
  select due_dates into v_dates from public.school_year_payment_schedules where school_year_id=v_enrollment.school_year_id and is_locked;
  if not found or cardinality(v_dates)<>6 or array_position(v_dates,null) is not null then
    raise exception 'Configurez d’abord les six échéances de cette année dans Paramètres.';
  end if;
  select * into v_category from public.fee_categories where code=p_fee_code and is_active=true;
  if not found then raise exception 'Catégorie de frais introuvable ou inactive.'; end if;
  if p_fee_code in ('SCOLARITE','INSCRIPTION') and exists(
    select 1 from public.student_charges where enrollment_id=p_enrollment_id and fee_category_id=v_category.id and status='validated'
  ) then raise exception 'Ces frais sont déjà enregistrés pour cette inscription.'; end if;

  select * into v_concession from public.enrollment_concessions c
   where c.enrollment_id=p_enrollment_id and c.status='approved'
     and (c.valid_from is null or c.valid_from<=current_date)
     and (c.valid_to is null or c.valid_to>=current_date)
     and ((c.fee_category_id is not null and c.fee_category_id=v_category.id)
       or (c.fee_category_id is null and (c.scope='all_eligible' or c.scope=v_category.kind::text)))
   order by c.approved_at desc nulls last,c.requested_at desc limit 1;
  if found then
    v_concession_id:=v_concession.id;
    if v_concession.kind='percentage' then
      v_discount:=round(p_amount*v_concession.percentage/100.0)::bigint;
    else
      v_discount:=least(p_amount,greatest(coalesce(v_concession.fixed_amount,0)-coalesce((
        select sum(sc.discount_amount)::bigint from public.student_charges sc where sc.concession_id=v_concession.id and sc.status='validated'
      ),0),0));
    end if;
  end if;
  v_discount:=least(greatest(v_discount,0),p_amount);
  v_net:=p_amount-v_discount;
  insert into public.student_charges(enrollment_id,fee_category_id,description,amount_due,gross_amount,discount_amount,concession_id,due_on,status,source,created_by)
  values(p_enrollment_id,v_category.id,trim(p_description),v_net,p_amount,v_discount,case when v_discount>0 then v_concession_id else null end,v_dates[6],'validated','manual',v_user)
  returning id into v_charge;

  v_base:=v_net/6; v_remainder:=mod(v_net,6);
  for v_i in 1..6 loop
    insert into public.installments(charge_id,installment_no,amount_due,due_on,created_by)
    values(v_charge,v_i,v_base+case when v_i<=v_remainder then 1 else 0 end,v_dates[v_i],v_user);
  end loop;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'create_student_charge_with_annual_schedule','student_charges',v_charge::text,
    jsonb_build_object('enrollment_id',p_enrollment_id,'fee_code',p_fee_code,'gross_amount',p_amount,'discount_amount',v_discount,'net_amount',v_net,'due_dates',v_dates,'installments',6,'existing_schedule_unchanged',true));
  return v_charge;
end;
$$;
revoke all on function public.create_student_charge_with_annual_schedule(uuid,text,text,bigint) from public,anon;
grant execute on function public.create_student_charge_with_annual_schedule(uuid,text,text,bigint) to authenticated;

-- Les tarifs actifs s’appuient sur le calendrier annuel fixe, pas sur des dates autonomes par élève.
create or replace function public.apply_class_fee_tariffs(p_enrollment_id uuid)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_enrollment public.enrollments%rowtype;
  v_tariff record;
  v_concession public.enrollment_concessions%rowtype;
  v_dates date[];
  v_has_tariffs boolean;
  v_charge uuid;
  v_discount bigint;
  v_net bigint;
  v_count integer := 6;
  v_i integer;
  v_base bigint;
  v_remainder bigint;
  v_created integer := 0;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à attribuer des frais scolaires' using errcode='42501';
  end if;
  select * into v_enrollment from public.enrollments e where e.id=p_enrollment_id and e.status in ('inscrit','reinscrit') for update;
  if not found then raise exception 'Inscription active introuvable'; end if;
  if exists(select 1 from public.school_years y where y.id=v_enrollment.school_year_id and y.is_closed) then
    raise exception 'L’année scolaire est clôturée ; les tarifs ne peuvent pas être attribués à cette inscription';
  end if;
  select exists(select 1 from public.class_fee_tariffs t where t.school_year_id=v_enrollment.school_year_id and t.class_id=v_enrollment.class_id and t.is_active) into v_has_tariffs;
  if not v_has_tariffs then return 0; end if;
  select due_dates into v_dates from public.school_year_payment_schedules where school_year_id=v_enrollment.school_year_id and is_locked;
  if not found or cardinality(v_dates)<>6 or array_position(v_dates,null) is not null then
    raise exception 'Configurez les six échéances annuelles dans Paramètres avant d’attribuer les frais.';
  end if;
  for v_i in 2..6 loop
    if v_dates[v_i] <= v_dates[v_i-1] then raise exception 'Les six échéances annuelles doivent être distinctes et strictement chronologiques.'; end if;
  end loop;

  for v_tariff in
    select t.*,fc.code as fee_code,fc.name as fee_name,fc.kind::text as fee_kind
    from public.class_fee_tariffs t join public.fee_categories fc on fc.id=t.fee_category_id and fc.is_active
    where t.school_year_id=v_enrollment.school_year_id and t.class_id=v_enrollment.class_id and t.is_active
    order by fc.kind,fc.name
  loop
    if exists(select 1 from public.student_charges c where c.enrollment_id=p_enrollment_id and c.fee_category_id=v_tariff.fee_category_id) then continue; end if;
    v_discount:=0; v_concession:=null;
    select c.* into v_concession from public.enrollment_concessions c
     where c.enrollment_id=p_enrollment_id and c.status='approved'
       and (c.valid_from is null or c.valid_from<=current_date) and (c.valid_to is null or c.valid_to>=current_date)
       and ((c.fee_category_id is not null and c.fee_category_id=v_tariff.fee_category_id)
         or (c.fee_category_id is null and (c.scope='all_eligible' or c.scope=v_tariff.fee_kind)))
     order by c.approved_at desc nulls last,c.requested_at desc limit 1;
    if found then
      if v_concession.kind='percentage' then v_discount:=round(v_tariff.gross_amount*v_concession.percentage/100.0)::bigint;
      else v_discount:=least(v_tariff.gross_amount,greatest(coalesce(v_concession.fixed_amount,0)-coalesce((select sum(c.discount_amount)::bigint from public.student_charges c where c.concession_id=v_concession.id and c.status='validated'),0),0)); end if;
    end if;
    v_discount:=least(greatest(v_discount,0),v_tariff.gross_amount); v_net:=v_tariff.gross_amount-v_discount;
    insert into public.student_charges(enrollment_id,fee_category_id,description,amount_due,gross_amount,discount_amount,concession_id,due_on,status,source,created_by)
    values(p_enrollment_id,v_tariff.fee_category_id,v_tariff.fee_name,v_net,v_tariff.gross_amount,v_discount,case when v_discount>0 then v_concession.id else null end,v_dates[6],'validated','tariff_template',v_user)
    returning id into v_charge;
    v_base:=v_net/6; v_remainder:=mod(v_net,6);
    for v_i in 1..6 loop
      insert into public.installments(charge_id,installment_no,amount_due,due_on,created_by)
      values(v_charge,v_i,v_base+case when v_i<=v_remainder then 1 else 0 end,v_dates[v_i],v_user);
    end loop;
    v_created:=v_created+1;
    insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
    values(v_user,'school_fee_tariff.applied','student_charges',v_charge::text,jsonb_build_object('enrollment_id',p_enrollment_id,'tariff_id',v_tariff.id,'fee_category_id',v_tariff.fee_category_id,'gross_amount',v_tariff.gross_amount,'discount_amount',v_discount,'amount_due',v_net,'installments',6,'due_dates',v_dates));
  end loop;
  return v_created;
end;
$$;
revoke all on function public.apply_class_fee_tariffs(uuid) from public,anon;
grant execute on function public.apply_class_fee_tariffs(uuid) to authenticated;

-- Le formulaire « Nouvel élève » crée obligatoirement une inscription avec classe + année scolaire.
create or replace function public.create_student_profile_with_enrollment(
  p_student_number text,
  p_last_name text,
  p_first_names text,
  p_sex text,
  p_birth_date date,
  p_birth_place text,
  p_address text,
  p_contact_phone text,
  p_contact_email text,
  p_guardian_name text,
  p_guardian_phone text,
  p_guardian_email text,
  p_guardian_occupation text,
  p_guardian_address text,
  p_guardian_relationship text,
  p_notes text,
  p_class_id uuid,
  p_school_year_id uuid,
  p_enrolled_on date,
  p_enrollment_type text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_student uuid; v_enrollment uuid; v_number text;
begin
  if v_user is null or not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then raise exception 'Accès refusé à la création du dossier élève.' using errcode='42501'; end if;
  if nullif(trim(p_last_name),'') is null or nullif(trim(p_first_names),'') is null then raise exception 'Le nom et les prénoms sont obligatoires'; end if;
  if p_class_id is null or p_school_year_id is null then raise exception 'Pour créer le dossier complet, choisissez obligatoirement une classe et une année scolaire.'; end if;
  if nullif(trim(p_guardian_name),'') is null or nullif(trim(p_guardian_phone),'') is null then raise exception 'Le nom et le téléphone du parent ou responsable légal sont obligatoires pour créer le dossier complet.'; end if;
  if p_birth_date is not null and p_birth_date > current_date then raise exception 'La date de naissance ne peut pas être dans le futur.'; end if;
  v_student:=public.create_student_with_guardian(p_student_number,p_last_name,p_first_names,p_sex,p_birth_date,p_birth_place,p_guardian_name,p_guardian_phone,p_guardian_address,p_notes,p_guardian_email,p_guardian_occupation,p_guardian_relationship);
  update public.students set address=nullif(trim(p_address),''),contact_phone=nullif(trim(p_contact_phone),''),contact_email=nullif(trim(p_contact_email),'') where id=v_student;
  v_enrollment:=public.create_school_enrollment(v_student,p_school_year_id,p_class_id,coalesce(p_enrolled_on,current_date),coalesce(nullif(p_enrollment_type,''),'inscrit'),p_notes);
  select student_number into v_number from public.students where id=v_student;
  return jsonb_build_object('student_id',v_student,'student_number',v_number,'enrollment_id',v_enrollment);
end;
$$;
revoke all on function public.create_student_profile_with_enrollment(text,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text,uuid,uuid,date,text) from public,anon;
grant execute on function public.create_student_profile_with_enrollment(text,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text,uuid,uuid,date,text) to authenticated;
COMMIT;

-- ============================================================
-- MIGRATION 026_transferable_admin_profile.sql
-- ============================================================
BEGIN;
-- EPC BETHEL V1.21.0 — transfert contrôlé du rôle administrateur.
-- À appliquer APRÈS les migrations 001 à 025 sur une base existante.
-- Ne pas réécrire l'historique des migrations déjà appliquées.


-- Compatibilité : conserve le nom de la fonction utilisé par les politiques RLS historiques,
-- mais l'autorisation dépend désormais du rôle actif en base et non d'une adresse e-mail fixe.
create or replace function public.is_primary_epc_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.app_role
      and p.is_active = true
  );
$$;
revoke all on function public.is_primary_epc_admin() from public, anon;
grant execute on function public.is_primary_epc_admin() to authenticated;

-- Tous les nouveaux comptes commencent en lecture seule. L'administrateur est attribué
-- uniquement par le transfert contrôlé défini plus bas.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Utilisateur'
  );

  insert into public.profiles (id, full_name, role, is_active)
  values (new.id, v_name, 'observateur'::public.app_role, true)
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_auth_user() from public, anon;

-- Le RPC historique reste réservé à l'administrateur actif et ne peut jamais attribuer admin.
create or replace function public.update_profile_access(
  p_user_id uuid,
  p_role public.app_role,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_role public.app_role;
begin
  if not public.is_primary_epc_admin() then
    raise exception 'Accès réservé à un administrateur actif.' using errcode = '42501';
  end if;
  if p_user_id is null or p_role is null or p_is_active is null then
    raise exception 'Utilisateur, rôle et état du compte sont obligatoires.' using errcode = '22004';
  end if;
  if p_role not in ('observateur'::public.app_role, 'modification'::public.app_role) then
    raise exception 'Le rôle administrateur doit être attribué depuis Paramètres.' using errcode = '42501';
  end if;

  select p.role into v_current_role
  from public.profiles p
  where p.id = p_user_id
  for update;
  if not found then
    raise exception 'Utilisateur introuvable.' using errcode = 'P0002';
  end if;
  if v_current_role = 'admin'::public.app_role then
    raise exception 'Le compte administrateur doit être transféré depuis Paramètres.' using errcode = '42501';
  end if;

  update public.profiles
  set role = p_role, is_active = p_is_active, updated_at = now()
  where id = p_user_id;
end;
$$;
revoke all on function public.update_profile_access(uuid, public.app_role, boolean) from public, anon;
grant execute on function public.update_profile_access(uuid, public.app_role, boolean) to authenticated;

-- Le drapeau transactionnel ne peut être activé que dans le RPC privilégié ci-dessous.
-- Il permet le changement atomique des deux profils, sans ouvrir la promotion admin directe.
create or replace function public.guard_epc_profile_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_transfer boolean := coalesce(current_setting('epc.admin_transfer', true), '') = 'on';
begin
  if new.id is distinct from old.id then
    raise exception 'L’identifiant d’un profil ne peut pas être modifié.' using errcode = '42501';
  end if;

  if v_admin_transfer then
    return new;
  end if;

  if old.role = 'admin'::public.app_role then
    if new.role is distinct from 'admin'::public.app_role or new.is_active is distinct from true then
      raise exception 'Transférez l’administration depuis Paramètres avant de modifier ce profil.' using errcode = '42501';
    end if;
  elsif new.role = 'admin'::public.app_role then
    raise exception 'Le rôle administrateur ne peut être attribué que depuis Paramètres.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_epc_profile_access() from public, anon;
drop trigger if exists guard_epc_profile_access_trigger on public.profiles;
create trigger guard_epc_profile_access_trigger
before update of id, role, is_active on public.profiles
for each row execute function public.guard_epc_profile_access();

create or replace function public.guard_epc_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role = 'admin'::public.app_role then
    raise exception 'Un profil administrateur ne peut pas être créé directement.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_epc_profile_insert() from public, anon;
drop trigger if exists guard_epc_profile_insert_trigger on public.profiles;
create trigger guard_epc_profile_insert_trigger
before insert on public.profiles
for each row execute function public.guard_epc_profile_insert();

create or replace function public.guard_epc_profile_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'admin'::public.app_role then
    raise exception 'Transférez l’administration avant de supprimer ce profil.' using errcode = '42501';
  end if;
  return old;
end;
$$;
revoke all on function public.guard_epc_profile_delete() from public, anon;
drop trigger if exists guard_epc_profile_delete_trigger on public.profiles;
create trigger guard_epc_profile_delete_trigger
before delete on public.profiles
for each row execute function public.guard_epc_profile_delete();

-- Transfert atomique : le nouvel administrateur doit être un profil actif déjà créé.
-- L'ancien administrateur devient Modification, reste actif et conserve l'accès métier.
create or replace function public.transfer_epc_admin(p_new_admin_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_admin_id uuid := (select auth.uid());
  v_target_role public.app_role;
  v_target_active boolean;
  v_target_confirmed boolean;
begin
  if v_current_admin_id is null or not public.is_primary_epc_admin() then
    raise exception 'Seul un administrateur actif peut transférer l’administration.' using errcode = '42501';
  end if;
  if p_new_admin_user_id is null or p_new_admin_user_id = v_current_admin_id then
    raise exception 'Sélectionnez un autre compte pour le transfert.' using errcode = '22023';
  end if;

  perform 1 from public.profiles
  where id = v_current_admin_id and role = 'admin'::public.app_role and is_active = true
  for update;
  if not found then
    raise exception 'Le profil administrateur courant est introuvable ou inactif.' using errcode = '42501';
  end if;

  select p.role, p.is_active, (u.email_confirmed_at is not null)
    into v_target_role, v_target_active, v_target_confirmed
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = p_new_admin_user_id
  for update of p;
  if not found or v_target_active is distinct from true or v_target_confirmed is distinct from true then
    raise exception 'Le compte sélectionné doit être actif et son adresse e-mail doit être confirmée.' using errcode = '22023';
  end if;
  if v_target_role = 'admin'::public.app_role then
    raise exception 'Le compte sélectionné est déjà administrateur.' using errcode = '22023';
  end if;

  perform set_config('epc.admin_transfer', 'on', true);
  update public.profiles
    set role = 'modification'::public.app_role, is_active = true, updated_at = now()
    where id = v_current_admin_id;
  update public.profiles
    set role = 'admin'::public.app_role, is_active = true, updated_at = now()
    where id = p_new_admin_user_id;
end;
$$;
revoke all on function public.transfer_epc_admin(uuid) from public, anon;
grant execute on function public.transfer_epc_admin(uuid) to authenticated;

-- Initialisation de secours uniquement pour une base neuve sans aucun profil admin.
-- Non exposée aux rôles anon/authenticated ; à appeler depuis le SQL Editor de Supabase
-- après création et confirmation du compte Auth destiné à devenir le premier administrateur.
create or replace function public.bootstrap_epc_admin(p_initial_admin_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_count integer;
  v_target_role public.app_role;
  v_target_active boolean;
  v_target_confirmed boolean;
begin
  if (select auth.uid()) is not null then
    raise exception 'Initialisez le premier administrateur depuis le SQL Editor Supabase.' using errcode = '42501';
  end if;

  select count(*) into v_admin_count
  from public.profiles p
  where p.role = 'admin'::public.app_role;
  if v_admin_count > 0 then
    raise exception 'Un profil administrateur existe déjà. Utilisez le transfert depuis Paramètres.' using errcode = '42501';
  end if;

  select p.role, p.is_active, (u.email_confirmed_at is not null)
    into v_target_role, v_target_active, v_target_confirmed
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = p_initial_admin_user_id
  for update of p;
  if not found or v_target_active is distinct from true or v_target_confirmed is distinct from true then
    raise exception 'Le compte initial doit exister, être actif et avoir une adresse e-mail confirmée.' using errcode = '22023';
  end if;

  perform set_config('epc.admin_transfer', 'on', true);
  update public.profiles
    set role = 'admin'::public.app_role, is_active = true, updated_at = now()
    where id = p_initial_admin_user_id;
end;
$$;
revoke all on function public.bootstrap_epc_admin(uuid) from public, anon, authenticated;
grant execute on function public.bootstrap_epc_admin(uuid) to service_role;
COMMIT;
