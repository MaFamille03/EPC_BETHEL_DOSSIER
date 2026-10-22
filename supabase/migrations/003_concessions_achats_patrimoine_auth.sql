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
