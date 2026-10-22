-- EPC BETHEL — authentification sécurisée, administrateur principal et accès observateur.
-- À appliquer après 010_add_observateur_role.sql sur le projet Supabase ciblé.
begin;

-- Création automatique du profil : une seule adresse est l'administrateur principal.
-- Tous les autres comptes ont par défaut le niveau Observateur ; seul l'administrateur peut les passer en Modification.
alter table public.profiles alter column role set default 'observateur'::public.app_role;
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.app_role;
  v_name text;
begin
  v_role := case
    when lower(coalesce(new.email, '')) = 'minnhindje@gmail.com' then 'admin'::public.app_role
    else 'observateur'::public.app_role
  end;
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Utilisateur'
  );

  insert into public.profiles (id, full_name, role, is_active)
  values (new.id, v_name, v_role, true)
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public;

drop trigger if exists on_auth_user_created_epc_profile on auth.users;
create trigger on_auth_user_created_epc_profile
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- Répare les comptes déjà créés : l'adresse désignée devient admin,
-- les autres sont ramenés au rôle observateur par défaut.
insert into public.profiles (id, full_name, role, is_active)
select
  u.id,
  coalesce(nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''), nullif(split_part(coalesce(u.email, ''), '@', 1), ''), 'Utilisateur'),
  case when lower(coalesce(u.email, '')) = 'minnhindje@gmail.com' then 'admin'::public.app_role else 'observateur'::public.app_role end,
  true
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;

update public.profiles p
set role = case
      when lower(coalesce(u.email, '')) = 'minnhindje@gmail.com' then 'admin'::public.app_role
      else 'observateur'::public.app_role
    end,
    is_active = case when lower(coalesce(u.email, '')) = 'minnhindje@gmail.com' then true else coalesce(p.is_active, true) end,
    updated_at = now()
from auth.users u
where u.id = p.id;

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

-- Fonctions d'identification de l'administrateur principal (jamais fondées sur les métadonnées client).
create or replace function public.is_primary_epc_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users u
    join public.profiles p on p.id = u.id
    where u.id = (select auth.uid())
      and lower(coalesce(u.email, '')) = 'minnhindje@gmail.com'
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
  v_target_email text;
  v_current_role public.app_role;
begin
  if not public.is_primary_epc_admin() then
    raise exception 'Accès réservé à l’administrateur principal.' using errcode = '42501';
  end if;
  if p_user_id is null or p_role is null or p_is_active is null then
    raise exception 'Utilisateur, rôle et état du compte sont obligatoires.' using errcode = '22004';
  end if;
  if p_role not in ('observateur'::public.app_role,'modification'::public.app_role) then
    raise exception 'Le rôle administrateur est réservé au compte principal.' using errcode = '42501';
  end if;

  select lower(coalesce(u.email,'')), p.role
    into v_target_email, v_current_role
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = p_user_id
  for update of p;

  if not found then raise exception 'Utilisateur introuvable.' using errcode = 'P0002'; end if;
  if v_target_email = 'minnhindje@gmail.com' or v_current_role = 'admin'::public.app_role then
    raise exception 'Le compte administrateur principal est protégé.' using errcode = '42501';
  end if;

  update public.profiles
    set role = p_role, is_active = p_is_active, updated_at = now()
    where id = p_user_id;
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
  v_email text;
begin
  if new.id is distinct from old.id then
    raise exception 'L’identifiant d’un profil ne peut pas être modifié.' using errcode = '42501';
  end if;

  select lower(coalesce(u.email, '')) into v_email from auth.users u where u.id = old.id;

  if v_email = 'minnhindje@gmail.com' then
    if new.role is distinct from 'admin'::public.app_role or new.is_active is distinct from true then
      raise exception 'Le compte administrateur principal est protégé.' using errcode = '42501';
    end if;
  elsif new.role = 'admin'::public.app_role then
    raise exception 'Le rôle administrateur est réservé au compte administrateur principal.' using errcode = '42501';
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
declare
  v_email text;
begin
  select lower(coalesce(u.email, '')) into v_email from auth.users u where u.id = new.id;
  if v_email = 'minnhindje@gmail.com' then
    if new.role is distinct from 'admin'::public.app_role or new.is_active is distinct from true then
      raise exception 'Le compte administrateur principal doit garder son rôle et rester actif.' using errcode = '42501';
    end if;
  elsif new.role = 'admin'::public.app_role then
    raise exception 'Le rôle administrateur est réservé au compte administrateur principal.' using errcode = '42501';
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
declare
  v_email text;
begin
  select lower(coalesce(u.email, '')) into v_email from auth.users u where u.id = old.id;
  if v_email = 'minnhindje@gmail.com' or old.role = 'admin'::public.app_role then
    raise exception 'Le profil administrateur principal ne peut pas être supprimé.' using errcode = '42501';
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

commit;
