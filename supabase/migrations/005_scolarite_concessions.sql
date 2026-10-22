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
