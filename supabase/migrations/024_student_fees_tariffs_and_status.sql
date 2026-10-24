-- EPC BETHEL V1.19.0 — Dossier élève, tarifs par classe/année, réductions ciblées et statut d'abandon.
-- Cette migration conserve les charges existantes : les changements de tarifs futurs ne réécrivent
-- jamais les montants historiques déjà attribués aux élèves.
begin;

alter table public.students
  add column if not exists address text,
  add column if not exists contact_phone text,
  add column if not exists contact_email text,
  add column if not exists administrative_status text not null default 'active';

alter table public.students drop constraint if exists students_administrative_status_check;
alter table public.students add constraint students_administrative_status_check
  check (administrative_status in ('active','abandon'));

alter table public.enrollments drop constraint if exists enrollments_status_check;
alter table public.enrollments add constraint enrollments_status_check
  check (status in ('inscrit','reinscrit','transfere','sorti','annule','abandon'));

create table if not exists public.class_fee_tariffs (
  id uuid primary key default gen_random_uuid(),
  school_year_id uuid not null references public.school_years(id) on delete restrict,
  class_id uuid not null references public.classes(id) on delete restrict,
  fee_category_id uuid not null references public.fee_categories(id) on delete restrict,
  gross_amount bigint not null check (gross_amount >= 0),
  installment_count smallint not null default 6 check (installment_count between 1 and 6),
  due_dates date[] not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique (school_year_id,class_id,fee_category_id),
  check (cardinality(due_dates)=installment_count),
  check (array_position(due_dates,null) is null)
);
create index if not exists class_fee_tariffs_lookup_idx
  on public.class_fee_tariffs(school_year_id,class_id,is_active);

alter table public.enrollment_concessions
  add column if not exists fee_category_id uuid references public.fee_categories(id) on delete restrict;

alter table public.class_fee_tariffs enable row level security;
drop policy if exists class_fee_tariffs_read on public.class_fee_tariffs;
create policy class_fee_tariffs_read on public.class_fee_tariffs for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]));
drop policy if exists class_fee_tariffs_insert on public.class_fee_tariffs;
create policy class_fee_tariffs_insert on public.class_fee_tariffs for insert to authenticated
with check (public.has_any_role(array['admin','direction']::public.app_role[]));
drop policy if exists class_fee_tariffs_update on public.class_fee_tariffs;
create policy class_fee_tariffs_update on public.class_fee_tariffs for update to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));
grant select,insert,update on public.class_fee_tariffs to authenticated;

-- Les catégories sont paramétrables par la direction ; la désactivation est préférée à la suppression
-- afin de préserver l'historique des frais et les reçus.
drop policy if exists fee_categories_manage_admin on public.fee_categories;
create policy fee_categories_manage_admin on public.fee_categories for all to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));
grant select,insert,update on public.fee_categories to authenticated;

create or replace function public.apply_class_fee_tariffs(p_enrollment_id uuid)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_enrollment public.enrollments%rowtype;
  v_tariff record;
  v_concession public.enrollment_concessions%rowtype;
  v_charge uuid;
  v_discount bigint;
  v_net bigint;
  v_count integer;
  v_i integer;
  v_base bigint;
  v_remainder bigint;
  v_created integer := 0;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à attribuer des frais scolaires' using errcode='42501';
  end if;
  select * into v_enrollment from public.enrollments e
  where e.id=p_enrollment_id and e.status in ('inscrit','reinscrit') for update;
  if not found then raise exception 'Inscription active introuvable'; end if;
  if exists(select 1 from public.school_years y where y.id=v_enrollment.school_year_id and y.is_closed) then
    raise exception 'L’année scolaire est clôturée ; les tarifs ne peuvent pas être attribués à cette inscription';
  end if;

  for v_tariff in
    select t.*,fc.code as fee_code,fc.name as fee_name,fc.kind::text as fee_kind
    from public.class_fee_tariffs t
    join public.fee_categories fc on fc.id=t.fee_category_id and fc.is_active
    where t.school_year_id=v_enrollment.school_year_id and t.class_id=v_enrollment.class_id and t.is_active
    order by fc.kind,fc.name
  loop
    -- Un frais manuel ou issu d'un tarif déjà créé ne doit pas être dupliqué pour l'inscription.
    if exists(select 1 from public.student_charges c
      where c.enrollment_id=p_enrollment_id and c.fee_category_id=v_tariff.fee_category_id) then
      continue;
    end if;
    if cardinality(v_tariff.due_dates)<>v_tariff.installment_count or array_position(v_tariff.due_dates,null) is not null then
      raise exception 'Les échéances configurées pour % sont incomplètes',v_tariff.fee_name;
    end if;
    for v_i in 2..v_tariff.installment_count loop
      if v_tariff.due_dates[v_i] < v_tariff.due_dates[v_i-1] then
        raise exception 'Les dates des échéances de % ne sont pas chronologiques',v_tariff.fee_name;
      end if;
    end loop;

    v_discount := 0;
    v_concession := null;
    select c.* into v_concession
      from public.enrollment_concessions c
     where c.enrollment_id=p_enrollment_id and c.status='approved'
       and (c.valid_from is null or c.valid_from<=current_date)
       and (c.valid_to is null or c.valid_to>=current_date)
       and ((c.fee_category_id is not null and c.fee_category_id=v_tariff.fee_category_id)
         or (c.fee_category_id is null and (c.scope='all_eligible' or c.scope=v_tariff.fee_kind)))
     order by c.approved_at desc nulls last,c.requested_at desc
     limit 1;
    if found then
      if v_concession.kind='percentage' then
        v_discount := round(v_tariff.gross_amount*v_concession.percentage/100.0)::bigint;
      else
        -- Une réduction fixe globale est un plafond pour l'ensemble de son périmètre,
        -- pas un nouveau montant complet à répéter sur chaque catégorie.
        v_discount := least(
          v_tariff.gross_amount,
          greatest(coalesce(v_concession.fixed_amount,0) - coalesce((
            select sum(c.discount_amount)::bigint
            from public.student_charges c
            where c.concession_id=v_concession.id and c.status='validated'
          ),0),0)
        );
      end if;
    end if;
    v_discount := least(greatest(v_discount,0),v_tariff.gross_amount);
    v_net := v_tariff.gross_amount-v_discount;
    insert into public.student_charges(
      enrollment_id,fee_category_id,description,amount_due,gross_amount,discount_amount,concession_id,due_on,status,source,created_by
    ) values (
      p_enrollment_id,v_tariff.fee_category_id,v_tariff.fee_name,v_net,v_tariff.gross_amount,v_discount,
      case when v_discount>0 then v_concession.id else null end,v_tariff.due_dates[v_tariff.installment_count],
      'validated','tariff_template',v_user
    ) returning id into v_charge;
    v_count:=v_tariff.installment_count;
    v_base:=v_net/v_count;
    v_remainder:=mod(v_net,v_count);
    for v_i in 1..v_count loop
      insert into public.installments(charge_id,installment_no,amount_due,due_on,created_by)
      values(v_charge,v_i,v_base+case when v_i<=v_remainder then 1 else 0 end,v_tariff.due_dates[v_i],v_user);
    end loop;
    v_created:=v_created+1;
    insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
    values(v_user,'school_fee_tariff.applied','student_charges',v_charge::text,
      jsonb_build_object('enrollment_id',p_enrollment_id,'tariff_id',v_tariff.id,'fee_category_id',v_tariff.fee_category_id,
        'gross_amount',v_tariff.gross_amount,'discount_amount',v_discount,'amount_due',v_net,'installments',v_count));
  end loop;
  return v_created;
end;
$$;
revoke all on function public.apply_class_fee_tariffs(uuid) from public,anon;
grant execute on function public.apply_class_fee_tariffs(uuid) to authenticated;

-- Ajoute l'application atomique des tarifs lors d'une inscription. Les valeurs de tarif sont copiées
-- dans student_charges et installments ; elles ne changent donc pas lors d'une modification future.
create or replace function public.create_school_enrollment(
  p_student_id uuid,
  p_school_year_id uuid,
  p_class_id uuid,
  p_enrolled_on date default current_date,
  p_enrollment_type text default 'inscrit',
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_enrollment uuid; v_year_label text;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à inscrire un élève' using errcode='42501';
  end if;
  if p_student_id is null or p_school_year_id is null or p_class_id is null then raise exception 'L’élève, l’année scolaire et la classe sont obligatoires'; end if;
  if p_enrollment_type not in ('inscrit','reinscrit') then raise exception 'Type d’inscription invalide'; end if;
  if not exists(select 1 from public.students s where s.id=p_student_id and s.status='actif'::public.student_status) then raise exception 'L’élève n’existe pas ou son dossier n’est pas actif'; end if;
  select sy.label into v_year_label from public.school_years sy where sy.id=p_school_year_id and sy.is_current and not sy.is_closed;
  if not found then raise exception 'Sélectionnez l’année scolaire active et non clôturée'; end if;
  if not exists(select 1 from public.classes c where c.id=p_class_id and c.is_active) then raise exception 'La classe n’existe pas ou n’est plus active'; end if;
  insert into public.enrollments(student_id,school_year_id,class_id,enrolled_on,status,notes,created_by)
  values(p_student_id,p_school_year_id,p_class_id,coalesce(p_enrolled_on,current_date),p_enrollment_type,nullif(trim(p_notes),''),v_user)
  returning id into v_enrollment;
  update public.students set administrative_status='active',updated_at=now() where id=p_student_id;
  perform public.apply_class_fee_tariffs(v_enrollment);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'enrollment.created','enrollments',v_enrollment::text,jsonb_build_object('student_id',p_student_id,'school_year_id',p_school_year_id,'school_year_label',v_year_label,'class_id',p_class_id,'status',p_enrollment_type));
  return v_enrollment;
end;
$$;
revoke all on function public.create_school_enrollment(uuid,uuid,uuid,date,text,text) from public,anon;
grant execute on function public.create_school_enrollment(uuid,uuid,uuid,date,text,text) to authenticated;

-- Abandon administratif distinct : on conserve les charges et le solde ; aucune remise automatique.
create or replace function public.abandon_school_enrollment(
  p_enrollment_id uuid,
  p_exit_date date default current_date,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_student_id uuid; v_student_name text; v_year_current boolean; v_year_closed boolean;
begin
  if v_user is null or not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Accès refusé : abandon réservé à la direction, au secrétariat ou à l’administration.' using errcode='42501';
  end if;
  select e.student_id,sy.is_current,sy.is_closed,s.last_name||' '||s.first_names into v_student_id,v_year_current,v_year_closed,v_student_name
  from public.enrollments e join public.school_years sy on sy.id=e.school_year_id join public.students s on s.id=e.student_id
  where e.id=p_enrollment_id and e.status in ('inscrit','reinscrit') for update of e;
  if not found then raise exception 'Inscription active introuvable'; end if;
  if not v_year_current or v_year_closed then raise exception 'L’abandon doit être enregistré sur une année en cours non clôturée'; end if;
  update public.enrollments set status='abandon',notes=concat_ws(E'\n',nullif(notes,''),'Abandon le '||coalesce(p_exit_date,current_date)::text||case when nullif(trim(p_reason),'') is not null then ' ; motif : '||trim(p_reason) else '' end)
  where id=p_enrollment_id;
  update public.students set administrative_status='abandon',updated_at=now() where id=v_student_id;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'student.abandoned','enrollments',p_enrollment_id::text,jsonb_build_object('student_id',v_student_id,'student_name',v_student_name,'date',coalesce(p_exit_date,current_date),'reason',nullif(trim(p_reason),''),'financial_charges_preserved',true));
end;
$$;
revoke all on function public.abandon_school_enrollment(uuid,date,text) from public,anon;
grant execute on function public.abandon_school_enrollment(uuid,date,text) to authenticated;

-- Création d'un dossier et, si la classe et l'année sont fournies, de son inscription en une seule transaction.
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
  if (p_class_id is null) <> (p_school_year_id is null) then raise exception 'Pour inscrire l’élève, choisissez à la fois une classe et une année scolaire'; end if;
  v_student:=public.create_student_with_guardian(p_student_number,p_last_name,p_first_names,p_sex,p_birth_date,p_birth_place,p_guardian_name,p_guardian_phone,p_guardian_address,p_notes,p_guardian_email,p_guardian_occupation,p_guardian_relationship);
  update public.students set address=nullif(trim(p_address),''),contact_phone=nullif(trim(p_contact_phone),''),contact_email=nullif(trim(p_contact_email),'') where id=v_student;
  if p_class_id is not null then
    v_enrollment:=public.create_school_enrollment(v_student,p_school_year_id,p_class_id,coalesce(p_enrolled_on,current_date),coalesce(nullif(p_enrollment_type,''),'inscrit'),p_notes);
  end if;
  select student_number into v_number from public.students where id=v_student;
  return jsonb_build_object('student_id',v_student,'student_number',v_number,'enrollment_id',v_enrollment);
end;
$$;
revoke all on function public.create_student_profile_with_enrollment(text,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text,uuid,uuid,date,text) from public,anon;
grant execute on function public.create_student_profile_with_enrollment(text,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text,uuid,uuid,date,text) to authenticated;

create or replace function public.update_student_profile_with_guardian(
  p_student_id uuid,
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
  p_notes text
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.update_student_with_guardian(p_student_id,p_student_number,p_last_name,p_first_names,p_sex,p_birth_date,p_birth_place,p_guardian_name,p_guardian_phone,p_guardian_address,p_notes,p_guardian_email,p_guardian_occupation,p_guardian_relationship);
  update public.students set address=nullif(trim(p_address),''),contact_phone=nullif(trim(p_contact_phone),''),contact_email=nullif(trim(p_contact_email),'') where id=p_student_id;
end;
$$;
revoke all on function public.update_student_profile_with_guardian(uuid,text,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.update_student_profile_with_guardian(uuid,text,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text) to authenticated;

-- Nouvelle demande de réduction ciblée : la demande est conservée dans l'historique même si elle est refusée.
create or replace function public.request_enrollment_concession_scoped(
  p_enrollment_id uuid,
  p_fee_category_id uuid default null,
  p_scope text default 'all_eligible',
  p_kind public.concession_kind default 'percentage',
  p_percentage numeric default null,
  p_fixed_amount bigint default null,
  p_reason_code text default 'reduction_particuliere',
  p_reason_detail text default null,
  p_valid_from date default null,
  p_valid_to date default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_scope text; v_kind text; v_code text;
begin
  if v_user is null or not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Accès refusé à la demande de réduction' using errcode='42501';
  end if;
  if p_kind='percentage' and (p_percentage is null or p_percentage<0 or p_percentage>100 or p_fixed_amount is not null) then raise exception 'Pourcentage invalide'; end if;
  if p_kind='fixed_amount' and (p_fixed_amount is null or p_fixed_amount<0 or p_percentage is not null) then raise exception 'Montant de réduction invalide'; end if;
  if p_valid_from is not null and p_valid_to is not null and p_valid_to<p_valid_from then raise exception 'La date de fin précède la date de début'; end if;
  if p_scope not in ('all_eligible','scolarite','inscription','annexe') then raise exception 'Périmètre de réduction invalide'; end if;
  if p_fee_category_id is not null then
    select kind::text,code into v_kind,v_code from public.fee_categories where id=p_fee_category_id and is_active;
    if not found then raise exception 'Catégorie de frais active introuvable'; end if;
    v_scope:=case when v_kind in ('scolarite','inscription','annexe') then v_kind else 'annexe' end;
  else
    v_scope:='all_eligible';
  end if;
  perform 1 from public.enrollments e where e.id=p_enrollment_id and e.status in ('inscrit','reinscrit') for update;
  if not found then raise exception 'Inscription active introuvable'; end if;
  if exists (
    select 1 from public.enrollment_concessions c
    where c.enrollment_id=p_enrollment_id and c.status in ('requested','approved')
      and (c.valid_to is null or c.valid_to>=coalesce(p_valid_from,current_date))
      and (p_valid_to is null or c.valid_from is null or c.valid_from<=p_valid_to)
      and (p_fee_category_id is null or c.fee_category_id is null or c.fee_category_id=p_fee_category_id)
  ) then raise exception 'Une demande active couvre déjà ces frais pour une période qui se chevauche'; end if;
  insert into public.enrollment_concessions(enrollment_id,scope,fee_category_id,kind,percentage,fixed_amount,reason_code,reason_detail,status,requested_by,valid_from,valid_to)
  values(p_enrollment_id,v_scope,p_fee_category_id,p_kind,p_percentage,p_fixed_amount,
    coalesce(nullif(trim(p_reason_code),''),'reduction_particuliere'),nullif(trim(p_reason_detail),''),'requested',v_user,p_valid_from,p_valid_to)
  returning id into v_id;
  insert into public.concession_events(concession_id,event_type,actor_id,reason,after_data)
  values(v_id,'requested',v_user,coalesce(nullif(trim(p_reason_detail),''),p_reason_code),jsonb_build_object('scope',v_scope,'fee_category_id',p_fee_category_id,'kind',p_kind,'percentage',p_percentage,'fixed_amount',p_fixed_amount,'valid_from',p_valid_from,'valid_to',p_valid_to));
  return v_id;
end;
$$;
revoke all on function public.request_enrollment_concession_scoped(uuid,uuid,text,public.concession_kind,numeric,bigint,text,text,date,date) from public,anon;
grant execute on function public.request_enrollment_concession_scoped(uuid,uuid,text,public.concession_kind,numeric,bigint,text,text,date,date) to authenticated;

-- Synthèse compatible avec un filtre par code ou par type de frais (kind:scolarite, kind:annexe, etc.).
create or replace function public.get_school_fee_summary(
  p_school_year_id uuid default null,
  p_class_id uuid default null,
  p_fee_code text default null
) returns table(
  gross_total bigint, discount_total bigint, amount_due_total bigint, amount_paid_total bigint,
  balance_due_total bigint, overdue_total bigint, charge_count bigint
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]) then
    raise exception 'Accès refusé à la synthèse des frais scolaires.' using errcode='42501';
  end if;
  return query
  with charge_rows as (
    select c.id,coalesce(c.gross_amount,c.amount_due)::bigint gross_amount,
      coalesce(c.discount_amount,0)::bigint discount_amount,c.amount_due::bigint amount_due,
      coalesce(paid.amount_paid,0)::bigint amount_paid,coalesce(overdue.overdue_amount,0)::bigint overdue_amount
    from public.student_charges c
    join public.enrollments e on e.id=c.enrollment_id
    join public.fee_categories fc on fc.id=c.fee_category_id
    left join lateral (
      select coalesce(sum(pa.amount),0)::bigint amount_paid from public.payment_allocations pa
      join public.payments p on p.id=pa.payment_id and p.status='validated'
       and p.paid_at < ((current_date+1)::timestamp at time zone 'UTC') where pa.charge_id=c.id
    ) paid on true
    left join lateral (
      select case when exists(select 1 from public.installments ix where ix.charge_id=c.id) then
        coalesce((select sum(greatest(i.amount_due-coalesce(ip.paid_amount,0),0))::bigint
          from public.installments i left join lateral (
            select coalesce(sum(pa.amount),0)::bigint paid_amount from public.payment_allocations pa
            join public.payments p on p.id=pa.payment_id and p.status='validated'
             and p.paid_at < ((current_date+1)::timestamp at time zone 'UTC') where pa.installment_id=i.id
          ) ip on true where i.charge_id=c.id and i.due_on<current_date),0)::bigint
      when c.due_on is not null and c.due_on<current_date then greatest(c.amount_due-coalesce(paid.amount_paid,0),0)::bigint else 0::bigint end overdue_amount
    ) overdue on true
    where c.status='validated' and (p_school_year_id is null or e.school_year_id=p_school_year_id)
      and (p_class_id is null or e.class_id=p_class_id)
      and (nullif(trim(p_fee_code),'') is null
        or (left(trim(p_fee_code),5)='kind:' and fc.kind::text=substring(trim(p_fee_code) from 6))
        or (left(trim(p_fee_code),5)<>'kind:' and fc.code=trim(p_fee_code)))
  )
  select coalesce(sum(gross_amount),0)::bigint,coalesce(sum(discount_amount),0)::bigint,
    coalesce(sum(amount_due),0)::bigint,coalesce(sum(amount_paid),0)::bigint,
    coalesce(sum(greatest(amount_due-amount_paid,0)),0)::bigint,coalesce(sum(overdue_amount),0)::bigint,count(*)::bigint
  from charge_rows;
end;
$$;
revoke all on function public.get_school_fee_summary(uuid,uuid,text) from public,anon;
grant execute on function public.get_school_fee_summary(uuid,uuid,text) to authenticated;

-- Soldes par catégorie d'un élève ; seuls les paiements validés réduisent le reste dû.
create or replace function public.get_enrollment_fee_balances(p_enrollment_id uuid)
returns table(fee_category_id uuid,fee_code text,fee_name text,fee_kind text,gross_due bigint,discount_total bigint,net_due bigint,paid_total bigint,balance_due bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur','modification']::public.app_role[]) then raise exception 'Accès refusé' using errcode='42501'; end if;
  if not exists(select 1 from public.enrollments where id=p_enrollment_id) then raise exception 'Inscription introuvable'; end if;
  return query
  select fc.id,fc.code,fc.name,fc.kind::text,
    coalesce(sum(coalesce(c.gross_amount,c.amount_due)),0)::bigint,
    coalesce(sum(coalesce(c.discount_amount,0)),0)::bigint,
    coalesce(sum(c.amount_due),0)::bigint,
    coalesce(sum(coalesce(p.paid_amount,0)),0)::bigint,
    greatest(coalesce(sum(c.amount_due-coalesce(p.paid_amount,0)),0),0)::bigint
  from public.fee_categories fc
  join public.student_charges c on c.fee_category_id=fc.id and c.enrollment_id=p_enrollment_id and c.status='validated'
  left join lateral (select coalesce(sum(pa.amount) filter(where pm.status='validated' and pm.paid_at<((current_date+1)::timestamp at time zone 'UTC')),0)::bigint paid_amount
    from public.payment_allocations pa join public.payments pm on pm.id=pa.payment_id where pa.charge_id=c.id) p on true
  group by fc.id,fc.code,fc.name,fc.kind order by fc.kind,fc.name;
end;
$$;
revoke all on function public.get_enrollment_fee_balances(uuid) from public,anon;
grant execute on function public.get_enrollment_fee_balances(uuid) to authenticated;

-- Encaissement restreint à une catégorie précise, avec idempotence et affectation transactionnelle.
create or replace function public.register_student_payment_for_fee_with_provider(
  p_enrollment_id uuid,
  p_fee_category_id uuid,
  p_amount bigint,
  p_method public.payment_method,
  p_account_id uuid,
  p_paid_at timestamptz default now(),
  p_payer_name text default null,
  p_external_reference text default null,
  p_notes text default null,
  p_mobile_money_provider text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid:=auth.uid(); v_receipt text; v_payment_id uuid; v_existing public.payments%rowtype;
  v_remaining bigint; v_total_due bigint; v_open bigint; v_charge record; v_installment record; v_take bigint; v_account public.cash_accounts%rowtype;
begin
  if v_user is null or not public.has_any_role(array['admin','comptabilite']::public.app_role[]) then raise exception 'Seule la comptabilité ou l’administration peut enregistrer un encaissement' using errcode='42501'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Le montant doit être strictement positif'; end if;
  if p_enrollment_id is null or p_fee_category_id is null then raise exception 'Sélectionnez l’inscription et la catégorie de frais'; end if;
  if p_paid_at is null or (p_paid_at at time zone 'UTC')::date>current_date then raise exception 'La date de paiement est obligatoire et ne peut pas être future'; end if;
  if p_method::text='mobile_money' and coalesce(p_mobile_money_provider,'') not in ('orange_money','wave','moov_money') then raise exception 'Sélectionnez Orange Money, Wave ou Moov Money'; end if;
  if p_method::text<>'mobile_money' and p_mobile_money_provider is not null then raise exception 'Le fournisseur Mobile Money est réservé à ce mode'; end if;
  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtext(p_idempotency_key));
    select * into v_existing from public.payments where idempotency_key=p_idempotency_key for update;
    if found then
      if v_existing.enrollment_id<>p_enrollment_id or v_existing.amount<>p_amount then raise exception 'Cette clé d’enregistrement a déjà été utilisée pour un autre paiement'; end if;
      if not exists(select 1 from public.payment_allocations pa join public.student_charges c on c.id=pa.charge_id where pa.payment_id=v_existing.id and c.fee_category_id=p_fee_category_id) then raise exception 'Cette clé d’enregistrement correspond à une autre catégorie de frais'; end if;
      return jsonb_build_object('id',v_existing.id,'receipt_number',v_existing.receipt_number,'amount',v_existing.amount,'status',v_existing.status,'duplicate',true);
    end if;
  end if;
  perform 1 from public.enrollments e where e.id=p_enrollment_id and e.status in ('inscrit','reinscrit') for update;
  if not found then raise exception 'Inscription active introuvable'; end if;
  select * into v_account from public.cash_accounts where id=p_account_id and is_active for update;
  if not found then raise exception 'Compte de trésorerie inactif ou introuvable'; end if;
  if not exists(select 1 from public.student_charges where enrollment_id=p_enrollment_id and fee_category_id=p_fee_category_id and status='validated') then raise exception 'Aucun frais validé dans cette catégorie pour cet élève'; end if;
  select coalesce(sum(greatest(c.amount_due-coalesce(paid.amount_paid,0),0)),0)::bigint into v_total_due
  from public.student_charges c left join lateral (
    select coalesce(sum(pa.amount),0)::bigint amount_paid from public.payment_allocations pa join public.payments pm on pm.id=pa.payment_id and pm.status='validated' and pm.paid_at<((current_date+1)::timestamp at time zone 'UTC') where pa.charge_id=c.id
  ) paid on true where c.enrollment_id=p_enrollment_id and c.fee_category_id=p_fee_category_id and c.status='validated';
  if v_total_due<=0 then raise exception 'Cette catégorie de frais est déjà soldée'; end if;
  if p_amount>v_total_due then raise exception 'Le versement dépasse le solde restant de cette catégorie (%)',v_total_due; end if;
  v_receipt:=public.allocate_receipt_number(p_paid_at);
  insert into public.payments(receipt_number,enrollment_id,paid_at,amount,method,account_id,external_reference,payer_name,notes,status,created_by,idempotency_key,mobile_money_provider)
  values(v_receipt,p_enrollment_id,p_paid_at,p_amount,p_method,p_account_id,nullif(trim(p_external_reference),''),nullif(trim(p_payer_name),''),nullif(trim(p_notes),''),'draft',v_user,nullif(trim(p_idempotency_key),''),p_mobile_money_provider)
  returning id into v_payment_id;
  v_remaining:=p_amount;
  for v_installment in
    select i.id installment_id,i.charge_id,i.amount_due,i.due_on,i.installment_no
    from public.installments i join public.student_charges c on c.id=i.charge_id
    where c.enrollment_id=p_enrollment_id and c.fee_category_id=p_fee_category_id and c.status='validated'
    order by i.due_on,i.installment_no,i.id
  loop
    exit when v_remaining=0;
    select greatest(v_installment.amount_due-coalesce(sum(pa.amount) filter(where pm.status='validated' and pm.paid_at<((current_date+1)::timestamp at time zone 'UTC')),0),0)::bigint into v_open
    from public.payment_allocations pa join public.payments pm on pm.id=pa.payment_id where pa.installment_id=v_installment.installment_id;
    if v_open>0 then v_take:=least(v_open,v_remaining); insert into public.payment_allocations(payment_id,charge_id,installment_id,amount,created_by) values(v_payment_id,v_installment.charge_id,v_installment.installment_id,v_take,v_user); v_remaining:=v_remaining-v_take; end if;
  end loop;
  for v_charge in
    select c.id,c.amount_due from public.student_charges c where c.enrollment_id=p_enrollment_id and c.fee_category_id=p_fee_category_id and c.status='validated' and not exists(select 1 from public.installments i where i.charge_id=c.id) order by c.due_on nulls last,c.created_at,c.id
  loop
    exit when v_remaining=0;
    select greatest(v_charge.amount_due-coalesce(sum(pa.amount) filter(where pm.status='validated' and pm.paid_at<((current_date+1)::timestamp at time zone 'UTC')),0),0)::bigint into v_open from public.payment_allocations pa join public.payments pm on pm.id=pa.payment_id where pa.charge_id=v_charge.id;
    if v_open>0 then v_take:=least(v_open,v_remaining); insert into public.payment_allocations(payment_id,charge_id,installment_id,amount,created_by) values(v_payment_id,v_charge.id,null,v_take,v_user); v_remaining:=v_remaining-v_take; end if;
  end loop;
  if v_remaining<>0 then raise exception 'Affectation de paiement incomplète ; opération annulée'; end if;
  perform public.validate_payment(v_payment_id);
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details) values(v_user,'student_payment.for_fee','payments',v_payment_id::text,jsonb_build_object('fee_category_id',p_fee_category_id,'enrollment_id',p_enrollment_id,'amount',p_amount,'idempotency_key',p_idempotency_key));
  return jsonb_build_object('id',v_payment_id,'receipt_number',v_receipt,'amount',p_amount,'status','validated');
end;
$$;
revoke all on function public.register_student_payment_for_fee_with_provider(uuid,uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text,text,text) from public,anon;
grant execute on function public.register_student_payment_for_fee_with_provider(uuid,uuid,bigint,public.payment_method,uuid,timestamptz,text,text,text,text,text) to authenticated;

-- Suppression contrôlée des notes : permission explicite et trace d’audit avant l’effacement.
create or replace function public.school_grade_audit_delete()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(auth.uid(),'grade.deleted','student_grades',old.id::text,jsonb_build_object('enrollment_id',old.enrollment_id,'subject_id',old.subject_id,'term',old.term,'assessment_label',old.assessment_label,'score',old.score,'score_max',old.score_max,'reason','Suppression depuis le formulaire de gestion des notes'));
  return old;
end;
$$;
drop trigger if exists student_grades_audit_delete on public.student_grades;
create trigger student_grades_audit_delete before delete on public.student_grades for each row execute function public.school_grade_audit_delete();
drop policy if exists student_grades_delete on public.student_grades;
create policy student_grades_delete on public.student_grades for delete to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));
grant delete on public.student_grades to authenticated;



-- Garde-fous serveur sur la modification/suppression des notes.
-- L'interface applique les mêmes règles, mais PostgreSQL doit aussi les garantir.
create or replace function public.guard_student_grade_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_school_year_closed boolean := false;
begin
  if tg_op = 'UPDATE' and new.enrollment_id is distinct from old.enrollment_id then
    raise exception 'Une note ne peut pas être déplacée vers un autre dossier élève';
  end if;

  select sy.is_closed into v_school_year_closed
  from public.enrollments e
  join public.school_years sy on sy.id=e.school_year_id
  where e.id=old.enrollment_id;
  if coalesce(v_school_year_closed,false) then
    raise exception 'Les notes d’une année scolaire clôturée ne peuvent plus être modifiées';
  end if;

  if old.assessment_id is not null and exists(
    select 1 from public.school_assessments a where a.id=old.assessment_id and a.status in ('locked','cancelled')
  ) then
    raise exception 'Cette évaluation est verrouillée ou annulée';
  end if;
  if tg_op = 'UPDATE' and new.assessment_id is not null and exists(
    select 1 from public.school_assessments a where a.id=new.assessment_id and a.status in ('locked','cancelled')
  ) then
    raise exception 'Impossible d’associer une note à une évaluation verrouillée ou annulée';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.guard_student_grade_mutation() from public,anon;
drop trigger if exists student_grades_mutation_guard on public.student_grades;
create trigger student_grades_mutation_guard
before update or delete on public.student_grades
for each row execute function public.guard_student_grade_mutation();

-- À l'approbation d'une réduction, ne pas réécrire un frais qui a déjà reçu un paiement validé.
-- Les frais non réglés sont recalculés ; un événement conserve les montants modifiés et les frais ignorés.
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
  v_charge record;
  v_installment record;
  v_gross bigint;
  v_discount bigint;
  v_net bigint;
  v_fixed_remaining bigint;
  v_installment_count integer;
  v_base bigint;
  v_remainder bigint;
  v_updated_count integer := 0;
  v_skipped_count integer := 0;
  v_changed jsonb := '[]'::jsonb;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Seuls la direction et l’administration peuvent décider une concession' using errcode='42501';
  end if;
  select * into v_concession from public.enrollment_concessions where id=p_concession_id for update;
  if not found then raise exception 'Demande de réduction introuvable'; end if;
  if v_concession.status <> 'requested' then raise exception 'Cette demande a déjà été traitée'; end if;
  perform 1 from public.enrollments where id=v_concession.enrollment_id for update;

  if p_approve and exists(
    select 1 from public.enrollment_concessions c
    where c.enrollment_id=v_concession.enrollment_id and c.id<>p_concession_id and c.status='approved'
      and (c.valid_from is null or c.valid_from<=coalesce(v_concession.valid_to,current_date))
      and (c.valid_to is null or c.valid_to>=coalesce(v_concession.valid_from,current_date))
      and (
        (v_concession.fee_category_id is not null and (c.fee_category_id=v_concession.fee_category_id or (c.fee_category_id is null and c.scope='all_eligible')))
        or (v_concession.fee_category_id is null and (v_concession.scope='all_eligible' or c.scope='all_eligible' or c.scope=v_concession.scope))
      )
  ) then
    raise exception 'Une réduction approuvée chevauche déjà cette catégorie ou cette période';
  end if;

  if p_approve then
    update public.enrollment_concessions
      set status='approved',approved_by=v_user,approved_at=now(),decision_note=nullif(trim(p_decision_note),'')
      where id=p_concession_id;

    if (v_concession.valid_from is null or v_concession.valid_from<=current_date)
      and (v_concession.valid_to is null or v_concession.valid_to>=current_date) then
      select count(*) into v_skipped_count
      from public.student_charges c join public.fee_categories fc on fc.id=c.fee_category_id
      where c.enrollment_id=v_concession.enrollment_id and c.status='validated'
        and coalesce(c.discount_amount,0)=0 and c.concession_id is null
        and ((v_concession.fee_category_id is not null and c.fee_category_id=v_concession.fee_category_id)
          or (v_concession.fee_category_id is null and (v_concession.scope='all_eligible' or v_concession.scope=fc.kind::text)))
        and exists(select 1 from public.payment_allocations pa join public.payments p on p.id=pa.payment_id and p.status='validated' where pa.charge_id=c.id);

      v_fixed_remaining := coalesce(v_concession.fixed_amount,0);
      for v_charge in
        select c.id,c.amount_due,c.gross_amount,c.fee_category_id,c.description
        from public.student_charges c join public.fee_categories fc on fc.id=c.fee_category_id
        where c.enrollment_id=v_concession.enrollment_id and c.status='validated'
          and coalesce(c.discount_amount,0)=0 and c.concession_id is null
          and ((v_concession.fee_category_id is not null and c.fee_category_id=v_concession.fee_category_id)
            or (v_concession.fee_category_id is null and (v_concession.scope='all_eligible' or v_concession.scope=fc.kind::text)))
          and not exists(select 1 from public.payment_allocations pa join public.payments p on p.id=pa.payment_id and p.status='validated' where pa.charge_id=c.id)
        order by c.due_on nulls last,c.created_at,c.id
        for update of c
      loop
        v_gross := coalesce(v_charge.gross_amount,v_charge.amount_due);
        if v_concession.kind='percentage' then
          v_discount := round(v_gross*coalesce(v_concession.percentage,0)/100.0)::bigint;
        else
          exit when v_fixed_remaining<=0;
          v_discount := least(v_gross,v_fixed_remaining);
        end if;
        v_discount := least(greatest(v_discount,0),v_gross);
        if v_discount<=0 then continue; end if;
        v_net := v_gross-v_discount;
        update public.student_charges
          set gross_amount=v_gross,discount_amount=v_discount,amount_due=v_net,concession_id=p_concession_id,updated_at=now()
          where id=v_charge.id;

        select count(*) into v_installment_count from public.installments where charge_id=v_charge.id;
        if v_installment_count>0 then
          v_base := v_net / v_installment_count;
          v_remainder := mod(v_net,v_installment_count);
          for v_installment in select id,installment_no from public.installments where charge_id=v_charge.id order by installment_no for update
          loop
            update public.installments set amount_due=v_base+case when v_installment.installment_no<=v_remainder then 1 else 0 end
            where id=v_installment.id;
          end loop;
        end if;
        v_updated_count := v_updated_count+1;
        v_changed := v_changed || jsonb_build_array(jsonb_build_object('charge_id',v_charge.id,'description',v_charge.description,'gross_amount',v_gross,'discount_amount',v_discount,'net_amount',v_net));
        if v_concession.kind='fixed_amount' then v_fixed_remaining := v_fixed_remaining-v_discount; end if;
      end loop;
    end if;

    insert into public.concession_events(concession_id,event_type,actor_id,reason,after_data)
    values(p_concession_id,'approved',v_user,nullif(trim(p_decision_note),''),jsonb_build_object(
      'status','approved','updated_charges',v_updated_count,'skipped_paid_charges',v_skipped_count,
      'updated_charge_details',v_changed,'valid_from',v_concession.valid_from,'valid_to',v_concession.valid_to,
      'note','Les charges ayant déjà reçu un paiement validé ne sont pas modifiées. Les échéances sans paiement sont redistribuées sans changer les dates.'
    ));
  else
    update public.enrollment_concessions set status='rejected',decision_note=nullif(trim(p_decision_note),'') where id=p_concession_id;
    insert into public.concession_events(concession_id,event_type,actor_id,reason,after_data)
    values(p_concession_id,'rejected',v_user,nullif(trim(p_decision_note),''),jsonb_build_object('status','rejected'));
  end if;
end;
$$;
revoke all on function public.decide_enrollment_concession(uuid,boolean,text) from public,anon;
grant execute on function public.decide_enrollment_concession(uuid,boolean,text) to authenticated;

commit;
