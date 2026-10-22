-- EPC BETHEL — Étape 3 : gestion scolaire complète
-- Dossiers élèves modifiables, responsables légaux, inscriptions, transferts et classes.
-- À appliquer après les migrations 001 à 011 sur un environnement sauvegardé.
begin;

-- Remplace l'ancienne signature afin d'enregistrer aussi les coordonnées du responsable légal.
drop function if exists public.create_student_with_guardian(text,text,text,text,date,text,text,text,text,text);

create function public.create_student_with_guardian(
  p_student_number text,
  p_last_name text,
  p_first_names text,
  p_sex text default null,
  p_birth_date date default null,
  p_birth_place text default null,
  p_guardian_name text default null,
  p_guardian_phone text default null,
  p_guardian_address text default null,
  p_notes text default null,
  p_guardian_email text default null,
  p_guardian_occupation text default null,
  p_guardian_relationship text default 'Responsable légal'
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_student uuid;
  v_guardian uuid;
  v_number text;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à créer un dossier élève' using errcode = '42501';
  end if;
  if nullif(trim(p_last_name),'') is null or nullif(trim(p_first_names),'') is null then
    raise exception 'Le nom et les prénoms sont obligatoires';
  end if;
  if p_sex is not null and p_sex not in ('F','M','X') then raise exception 'Sexe invalide'; end if;
  if p_birth_date is not null and p_birth_date > current_date then raise exception 'La date de naissance ne peut pas être future'; end if;
  v_number := nullif(trim(p_student_number),'');
  if v_number is null then
    loop
      v_number := 'EPC-'||to_char(current_date,'YYYY')||'-'||upper(substr(replace(pg_catalog.gen_random_uuid()::text,'-',''),1,8));
      exit when not exists(select 1 from public.students s where s.student_number=v_number);
    end loop;
  end if;
  insert into public.students(student_number,last_name,first_names,sex,birth_date,birth_place,notes,created_by)
  values(v_number,trim(p_last_name),trim(p_first_names),p_sex,p_birth_date,nullif(trim(p_birth_place),''),nullif(trim(p_notes),''),v_user)
  returning id into v_student;
  if nullif(trim(p_guardian_name),'') is not null then
    insert into public.guardians(full_name,phone,email,address,occupation,created_by)
    values(trim(p_guardian_name),nullif(trim(p_guardian_phone),''),nullif(trim(p_guardian_email),''),nullif(trim(p_guardian_address),''),nullif(trim(p_guardian_occupation),''),v_user)
    returning id into v_guardian;
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary,receives_messages)
    values(v_student,v_guardian,coalesce(nullif(trim(p_guardian_relationship),''),'Responsable légal'),true,true);
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'student.created','students',v_student::text,jsonb_build_object('student_number',v_number,'has_guardian',nullif(trim(p_guardian_name),'') is not null));
  return v_student;
end;
$$;
revoke all on function public.create_student_with_guardian(text,text,text,text,date,text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.create_student_with_guardian(text,text,text,text,date,text,text,text,text,text,text,text,text) to authenticated;

-- Mise à jour atomique du dossier et du responsable légal principal.
create or replace function public.update_student_with_guardian(
  p_student_id uuid,
  p_student_number text,
  p_last_name text,
  p_first_names text,
  p_sex text default null,
  p_birth_date date default null,
  p_birth_place text default null,
  p_guardian_name text default null,
  p_guardian_phone text default null,
  p_guardian_address text default null,
  p_notes text default null,
  p_guardian_email text default null,
  p_guardian_occupation text default null,
  p_guardian_relationship text default 'Responsable légal'
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_guardian_id uuid;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à modifier un dossier élève' using errcode = '42501';
  end if;
  if p_student_id is null then raise exception 'Dossier élève manquant'; end if;
  if nullif(trim(p_student_number),'') is null or nullif(trim(p_last_name),'') is null or nullif(trim(p_first_names),'') is null then
    raise exception 'Le matricule, le nom et les prénoms sont obligatoires';
  end if;
  if p_sex is not null and p_sex not in ('F','M','X') then raise exception 'Sexe invalide'; end if;
  if p_birth_date is not null and p_birth_date > current_date then raise exception 'La date de naissance ne peut pas être future'; end if;
  update public.students
  set student_number = trim(p_student_number), last_name = trim(p_last_name), first_names = trim(p_first_names),
      sex = p_sex, birth_date = p_birth_date, birth_place = nullif(trim(p_birth_place),''),
      notes = nullif(trim(p_notes),''), updated_at = now()
  where id = p_student_id;
  if not found then raise exception 'Élève introuvable' using errcode = 'P0002'; end if;

  select sg.guardian_id into v_guardian_id
  from public.student_guardians sg
  where sg.student_id = p_student_id and sg.is_primary = true
  limit 1 for update;

  if nullif(trim(p_guardian_name),'') is null then
    delete from public.student_guardians where student_id = p_student_id and is_primary = true;
  elsif v_guardian_id is null then
    insert into public.guardians(full_name,phone,email,address,occupation,created_by)
    values(trim(p_guardian_name),nullif(trim(p_guardian_phone),''),nullif(trim(p_guardian_email),''),nullif(trim(p_guardian_address),''),nullif(trim(p_guardian_occupation),''),v_user)
    returning id into v_guardian_id;
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary,receives_messages)
    values(p_student_id,v_guardian_id,coalesce(nullif(trim(p_guardian_relationship),''),'Responsable légal'),true,true);
  else
    update public.guardians set full_name = trim(p_guardian_name), phone = nullif(trim(p_guardian_phone),''),
      email = nullif(trim(p_guardian_email),''), address = nullif(trim(p_guardian_address),''),
      occupation = nullif(trim(p_guardian_occupation),'') where id = v_guardian_id;
    update public.student_guardians set relationship = coalesce(nullif(trim(p_guardian_relationship),''),'Responsable légal'), is_primary = true
    where student_id = p_student_id and guardian_id = v_guardian_id;
  end if;

  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'student.updated','students',p_student_id::text,jsonb_build_object('student_number',trim(p_student_number),'guardian_updated',true));
end;
$$;
revoke all on function public.update_student_with_guardian(uuid,text,text,text,text,date,text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.update_student_with_guardian(uuid,text,text,text,text,date,text,text,text,text,text,text,text,text) to authenticated;

-- Création contrôlée d'une inscription ou réinscription dans une année non clôturée.
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
  v_user uuid := auth.uid();
  v_enrollment uuid;
  v_year_label text;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à inscrire un élève' using errcode = '42501';
  end if;
  if p_student_id is null or p_school_year_id is null or p_class_id is null then
    raise exception 'L’élève, l’année scolaire et la classe sont obligatoires';
  end if;
  if p_enrollment_type is null or p_enrollment_type not in ('inscrit','reinscrit') then raise exception 'Type d’inscription invalide'; end if;
  if not exists(select 1 from public.students s where s.id=p_student_id and s.status='actif'::public.student_status) then
    raise exception 'L’élève n’existe pas ou son dossier n’est pas actif';
  end if;
  select sy.label into v_year_label from public.school_years sy where sy.id=p_school_year_id and sy.is_current and not sy.is_closed;
  if not found then raise exception 'Sélectionnez l’année scolaire active et non clôturée'; end if;
  if not exists(select 1 from public.classes c where c.id=p_class_id and c.is_active) then
    raise exception 'La classe n’existe pas ou n’est plus active';
  end if;
  insert into public.enrollments(student_id,school_year_id,class_id,enrolled_on,status,notes,created_by)
  values(p_student_id,p_school_year_id,p_class_id,coalesce(p_enrolled_on,current_date),p_enrollment_type,nullif(trim(p_notes),''),v_user)
  returning id into v_enrollment;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'enrollment.created','enrollments',v_enrollment::text,jsonb_build_object('student_id',p_student_id,'school_year_id',p_school_year_id,'school_year_label',v_year_label,'class_id',p_class_id,'status',p_enrollment_type));
  return v_enrollment;
end;
$$;
revoke all on function public.create_school_enrollment(uuid,uuid,uuid,date,text,text) from public, anon;
grant execute on function public.create_school_enrollment(uuid,uuid,uuid,date,text,text) to authenticated;

-- Changement de classe dans l'établissement : met à jour l'inscription existante et écrit l'historique.
create or replace function public.transfer_student_class(
  p_enrollment_id uuid,
  p_target_class_id uuid,
  p_transfer_date date default current_date,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_student_id uuid;
  v_year_id uuid;
  v_source_class_id uuid;
  v_status text;
  v_source_name text;
  v_target_name text;
  v_year_current boolean;
  v_year_closed boolean;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à transférer un élève' using errcode = '42501';
  end if;
  select e.student_id,e.school_year_id,e.class_id,e.status,sy.is_current,sy.is_closed,c.name
    into v_student_id,v_year_id,v_source_class_id,v_status,v_year_current,v_year_closed,v_source_name
  from public.enrollments e
  join public.school_years sy on sy.id=e.school_year_id
  join public.classes c on c.id=e.class_id
  where e.id=p_enrollment_id for update of e;
  if not found then raise exception 'Inscription introuvable' using errcode = 'P0002'; end if;
  if v_status not in ('inscrit','reinscrit') then raise exception 'Seule une inscription active peut changer de classe'; end if;
  if not v_year_current or v_year_closed then raise exception 'Le changement de classe est réservé à une année scolaire active et non clôturée'; end if;
  select c.name into v_target_name from public.classes c where c.id=p_target_class_id and c.is_active;
  if not found then raise exception 'La nouvelle classe n’existe pas ou n’est plus active'; end if;
  if v_source_class_id=p_target_class_id then raise exception 'L’élève est déjà affecté à cette classe'; end if;
  update public.enrollments set class_id=p_target_class_id,
    notes=concat_ws(E'\n',nullif(notes,''),'Changement de classe le '||coalesce(p_transfer_date,current_date)::text||' : '||v_source_name||' → '||v_target_name||case when nullif(trim(p_reason),'') is not null then ' ; motif : '||trim(p_reason) else '' end)
  where id=p_enrollment_id;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'student.class_transferred','enrollments',p_enrollment_id::text,jsonb_build_object('student_id',v_student_id,'school_year_id',v_year_id,'from_class_id',v_source_class_id,'from_class',v_source_name,'to_class_id',p_target_class_id,'to_class',v_target_name,'transfer_date',coalesce(p_transfer_date,current_date),'reason',nullif(trim(p_reason),'')));
end;
$$;
revoke all on function public.transfer_student_class(uuid,uuid,date,text) from public, anon;
grant execute on function public.transfer_student_class(uuid,uuid,date,text) to authenticated;

-- Sortie définitive ou transfert hors de l'établissement.
create or replace function public.close_school_enrollment(
  p_enrollment_id uuid,
  p_exit_status text,
  p_exit_date date default current_date,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_student_id uuid;
  v_status text;
  v_year_current boolean;
  v_year_closed boolean;
  v_student_status public.student_status;
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction','secretariat']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à clôturer une inscription' using errcode = '42501';
  end if;
  if p_exit_status is null or p_exit_status not in ('transfere','sorti') then raise exception 'Type de sortie invalide'; end if;
  v_student_status := case when p_exit_status='transfere' then 'transfere'::public.student_status else 'sorti'::public.student_status end;
  select e.student_id,e.status,sy.is_current,sy.is_closed into v_student_id,v_status,v_year_current,v_year_closed
  from public.enrollments e join public.school_years sy on sy.id=e.school_year_id
  where e.id=p_enrollment_id for update of e;
  if not found then raise exception 'Inscription introuvable' using errcode = 'P0002'; end if;
  if v_status not in ('inscrit','reinscrit') then raise exception 'Cette inscription est déjà clôturée'; end if;
  if not v_year_current or v_year_closed then raise exception 'La sortie doit être enregistrée sur une année scolaire active et non clôturée'; end if;
  update public.enrollments set status=p_exit_status,
    notes=concat_ws(E'\n',nullif(notes,''),'Sortie le '||coalesce(p_exit_date,current_date)::text||' : '||case when p_exit_status='transfere' then 'transfert vers un autre établissement' else 'sortie définitive' end||case when nullif(trim(p_reason),'') is not null then ' ; motif : '||trim(p_reason) else '' end)
  where id=p_enrollment_id;
  -- Le dossier est marqué en sortie uniquement lorsqu'aucune autre inscription active ne subsiste.
  if not exists(
    select 1 from public.enrollments e
    join public.school_years sy on sy.id=e.school_year_id
    where e.student_id=v_student_id and e.id<>p_enrollment_id
      and e.status in ('inscrit','reinscrit') and sy.is_current and not sy.is_closed
  ) then
    update public.students set status=v_student_status,updated_at=now() where id=v_student_id;
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,'enrollment.closed','enrollments',p_enrollment_id::text,jsonb_build_object('student_id',v_student_id,'old_status',v_status,'exit_status',p_exit_status,'exit_date',coalesce(p_exit_date,current_date),'reason',nullif(trim(p_reason),'')));
end;
$$;
revoke all on function public.close_school_enrollment(uuid,text,date,text) from public, anon;
grant execute on function public.close_school_enrollment(uuid,text,date,text) to authenticated;

-- Gestion centralisée du référentiel des classes.
create or replace function public.save_class(
  p_id uuid,
  p_code text,
  p_name text,
  p_level_order integer,
  p_is_active boolean default true
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_code text := upper(trim(coalesce(p_code,'')));
  v_name text := trim(coalesce(p_name,''));
begin
  if v_user is null then raise exception 'Connexion requise'; end if;
  if not public.has_any_role(array['admin','direction']::public.app_role[]) then
    raise exception 'Vous n’êtes pas autorisé à gérer les classes' using errcode = '42501';
  end if;
  if v_code='' or v_name='' or length(v_code)>20 or length(v_name)>100 then raise exception 'Code et nom de classe obligatoires (20 et 100 caractères maximum)'; end if;
  if v_code !~ '^[A-Z0-9_-]+$' then raise exception 'Le code de classe ne doit contenir que des lettres, chiffres, tirets ou soulignements'; end if;
  if p_level_order is null or p_level_order<1 or p_level_order>99 then raise exception 'Ordre du niveau invalide'; end if;
  if p_id is null then
    insert into public.classes(code,name,level_order,is_active) values(v_code,v_name,p_level_order,coalesce(p_is_active,true)) returning id into v_id;
  else
    update public.classes set code=v_code,name=v_name,level_order=p_level_order,is_active=coalesce(p_is_active,true) where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Classe introuvable' using errcode = 'P0002'; end if;
  end if;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_user,case when p_id is null then 'class.created' else 'class.updated' end,'classes',v_id::text,jsonb_build_object('code',v_code,'name',v_name,'level_order',p_level_order,'is_active',coalesce(p_is_active,true)));
  return v_id;
end;
$$;
revoke all on function public.save_class(uuid,text,text,integer,boolean) from public, anon;
grant execute on function public.save_class(uuid,text,text,integer,boolean) to authenticated;

commit;
