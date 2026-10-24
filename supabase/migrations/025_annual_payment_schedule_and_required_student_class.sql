-- EPC BETHEL V1.20.0
-- Les six dates sont définies dans Paramètres, une fois par année scolaire.
-- Les charges/installments déjà attribués ne sont jamais recalculés par cette migration.
begin;

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

commit;
