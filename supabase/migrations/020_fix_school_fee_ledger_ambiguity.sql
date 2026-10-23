-- EPC BETHEL V1.15.2 — Correction de l'ambiguïté PL/pgSQL sur gross_amount.
-- La fonction renvoie une table dont les paramètres OUT portent les mêmes noms que
-- les colonnes du CTE : toutes les références du CASE sont donc qualifiées.
-- À appliquer après la migration 019 sur les projets déjà configurés.
begin;

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

commit;
