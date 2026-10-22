-- Code secret permettant au compte administrateur principal d'autoriser UNE adresse
-- supplémentaire à devenir administrateur. Le code brut n'est jamais stocké.
create table if not exists public.admin_access_code (
  singleton boolean primary key default true check (singleton),
  target_email text not null,
  code_salt text not null,
  code_hash text not null,
  updated_by uuid references auth.users(id) on delete restrict,
  updated_at timestamptz not null default now()
);
alter table public.admin_access_code enable row level security;
revoke all on public.admin_access_code from anon, authenticated;
comment on table public.admin_access_code is 'Configuration secrète du code de promotion admin; accès serveur uniquement via service role.';
