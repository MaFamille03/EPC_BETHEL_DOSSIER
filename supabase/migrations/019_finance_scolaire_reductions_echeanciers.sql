-- EPC BETHEL V1.14.0 — vocabulaire des réductions, échéanciers variables et synthèse financière.
-- À tester sur un projet Supabase de préproduction avant déploiement.

begin;

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

commit;
