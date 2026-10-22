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
