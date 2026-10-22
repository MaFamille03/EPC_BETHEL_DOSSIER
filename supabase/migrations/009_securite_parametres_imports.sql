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
