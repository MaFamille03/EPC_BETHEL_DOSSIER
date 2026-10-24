-- EPC BETHEL V1.21.0 — transfert contrôlé du rôle administrateur.
-- À appliquer APRÈS les migrations 001 à 025 sur une base existante.
-- Ne pas réécrire l'historique des migrations déjà appliquées.

begin;

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

commit;
