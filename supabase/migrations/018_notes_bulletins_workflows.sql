-- EPC BETHEL — Module Notes & bulletins : évaluations, règles configurables et publication
-- À appliquer après 017_bank_reconciliation_workflow.sql dans Supabase.
begin;

create table if not exists public.school_assessments (
  id uuid primary key default gen_random_uuid(),
  school_year_id uuid not null references public.school_years(id) on delete restrict,
  class_id uuid not null references public.classes(id) on delete restrict,
  subject_id uuid not null references public.school_subjects(id) on delete restrict,
  term text not null check (term in ('T1','T2','T3')),
  title text not null check (length(trim(title)) between 1 and 120),
  assessment_type text not null check (assessment_type in ('devoir','composition','examen','oral','autre')),
  assessment_date date not null default current_date,
  score_max numeric(6,2) not null default 20 check (score_max > 0 and score_max <= 1000),
  coefficient numeric(6,2) not null default 1 check (coefficient > 0 and coefficient <= 100),
  status text not null default 'draft' check (status in ('draft','open','locked','cancelled')),
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_year_id,class_id,subject_id,term,title)
);
create index if not exists school_assessments_filter_idx on public.school_assessments(school_year_id,class_id,term,subject_id,assessment_date desc);

alter table public.student_grades add column if not exists assessment_id uuid references public.school_assessments(id) on delete restrict;
alter table public.student_grades add column if not exists score_max numeric(6,2) not null default 20;
alter table public.student_grades add column if not exists status text not null default 'entered' check (status in ('entered','absent_excused','absent_unexcused','exempt','missing'));
alter table public.student_grades add column if not exists validated_at timestamptz;
alter table public.student_grades add column if not exists validated_by uuid references public.profiles(id) on delete restrict;
alter table public.student_grades add column if not exists updated_by uuid references public.profiles(id) on delete restrict;
alter table public.student_grades drop constraint if exists student_grades_score_check;
alter table public.student_grades add constraint student_grades_score_range_check check (score >= 0 and score <= score_max and score_max > 0);
create unique index if not exists student_grades_assessment_enrollment_unique on public.student_grades(assessment_id,enrollment_id) where assessment_id is not null;
create index if not exists student_grades_assessment_idx on public.student_grades(assessment_id,status);

create table if not exists public.school_grade_rules (
  id uuid primary key default gen_random_uuid(),
  school_year_id uuid not null references public.school_years(id) on delete restrict,
  class_id uuid references public.classes(id) on delete restrict,
  calculation_method text not null default 'coefficients' check (calculation_method in ('simple','coefficients','categories')),
  composition_weight numeric(5,2) not null default 40 check (composition_weight between 0 and 100),
  exam_weight numeric(5,2) not null default 60 check (exam_weight between 0 and 100),
  other_weight numeric(5,2) not null default 0 check (other_weight between 0 and 100),
  report_scale numeric(6,2) not null default 20 check (report_scale > 0 and report_scale <= 1000),
  is_approved boolean not null default false,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  updated_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (calculation_method <> 'categories' or composition_weight + exam_weight + other_weight = 100)
);
create unique index if not exists school_grade_rules_scope_unique on public.school_grade_rules(school_year_id,coalesce(class_id,'00000000-0000-0000-0000-000000000000'::uuid));

create table if not exists public.school_bulletins (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  term text not null check (term in ('T1','T2','T3')),
  status text not null default 'draft' check (status in ('draft','published','superseded')),
  payload jsonb not null default '{}'::jsonb,
  average numeric(8,3),
  report_scale numeric(6,2) not null default 20 check (report_scale > 0),
  generated_at timestamptz not null default now(),
  published_at timestamptz,
  published_by uuid references public.profiles(id) on delete restrict,
  supersedes_id uuid references public.school_bulletins(id) on delete restrict,
  created_by uuid references public.profiles(id) on delete restrict
);
create unique index if not exists school_bulletins_one_draft_idx on public.school_bulletins(enrollment_id,term) where status = 'draft';
create unique index if not exists school_bulletins_one_published_idx on public.school_bulletins(enrollment_id,term) where status = 'published';
create index if not exists school_bulletins_enrollment_idx on public.school_bulletins(enrollment_id,term,generated_at desc);

-- Journalisation de l'édition/publication des notes et bulletins.
create or replace function public.school_grade_set_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists school_assessments_updated_at on public.school_assessments;
create trigger school_assessments_updated_at before update on public.school_assessments for each row execute function public.school_grade_set_updated_at();
drop trigger if exists school_grade_rules_updated_at on public.school_grade_rules;
create trigger school_grade_rules_updated_at before update on public.school_grade_rules for each row execute function public.school_grade_set_updated_at();
drop trigger if exists student_grades_updated_at on public.student_grades;
create trigger student_grades_updated_at before update on public.student_grades for each row execute function public.set_updated_at();

-- Attribution automatique et journal d'audit des créations/corrections de notes.
create or replace function public.school_grade_audit_write()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, v_actor);
    new.updated_by := v_actor;
    insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
    values(v_actor,'grade.created','student_grades',new.id::text,jsonb_build_object('enrollment_id',new.enrollment_id,'subject_id',new.subject_id,'term',new.term,'assessment_id',new.assessment_id,'score',new.score,'score_max',new.score_max,'status',new.status));
    return new;
  end if;
  new.updated_by := v_actor;
  insert into public.audit_logs(actor_id,action,entity_table,entity_id,details)
  values(v_actor,'grade.updated','student_grades',new.id::text,jsonb_build_object('old_score',old.score,'new_score',new.score,'old_status',old.status,'new_status',new.status,'assessment_id',new.assessment_id,'enrollment_id',new.enrollment_id));
  return new;
end;
$$;
drop trigger if exists student_grades_audit_write on public.student_grades;
create trigger student_grades_audit_write before insert or update on public.student_grades for each row execute function public.school_grade_audit_write();

alter table public.school_assessments enable row level security;
alter table public.school_grade_rules enable row level security;
alter table public.school_bulletins enable row level security;

drop policy if exists school_assessments_read on public.school_assessments;
create policy school_assessments_read on public.school_assessments for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]));
drop policy if exists school_assessments_manage on public.school_assessments;
drop policy if exists school_assessments_insert on public.school_assessments;
drop policy if exists school_assessments_update on public.school_assessments;
create policy school_assessments_insert on public.school_assessments for insert to authenticated
with check (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]));
create policy school_assessments_update on public.school_assessments for update to authenticated
using (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]));

drop policy if exists school_grade_rules_read on public.school_grade_rules;
create policy school_grade_rules_read on public.school_grade_rules for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]));
drop policy if exists school_grade_rules_manage on public.school_grade_rules;
drop policy if exists school_grade_rules_insert on public.school_grade_rules;
drop policy if exists school_grade_rules_update on public.school_grade_rules;
create policy school_grade_rules_insert on public.school_grade_rules for insert to authenticated
with check (public.has_any_role(array['admin','direction']::public.app_role[]));
create policy school_grade_rules_update on public.school_grade_rules for update to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

drop policy if exists school_bulletins_read on public.school_bulletins;
create policy school_bulletins_read on public.school_bulletins for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','comptabilite','observateur']::public.app_role[]));
drop policy if exists school_bulletins_manage on public.school_bulletins;
drop policy if exists school_bulletins_insert on public.school_bulletins;
drop policy if exists school_bulletins_update on public.school_bulletins;
create policy school_bulletins_insert on public.school_bulletins for insert to authenticated
with check (public.has_any_role(array['admin','direction']::public.app_role[]));
create policy school_bulletins_update on public.school_bulletins for update to authenticated
using (public.has_any_role(array['admin','direction']::public.app_role[]))
with check (public.has_any_role(array['admin','direction']::public.app_role[]));

-- Lecture des nouvelles tables par le rôle applicatif Modification.
drop policy if exists school_assessments_read_modification on public.school_assessments;
create policy school_assessments_read_modification on public.school_assessments for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists school_grade_rules_read_modification on public.school_grade_rules;
create policy school_grade_rules_read_modification on public.school_grade_rules for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists school_bulletins_read_modification on public.school_bulletins;
create policy school_bulletins_read_modification on public.school_bulletins for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));

-- Lecture des référentiels nécessaires au module pour le rôle applicatif Modification.
-- Les politiques sont ajoutées séparément afin de ne pas modifier les accès des autres rôles.
drop policy if exists school_subjects_read_modification on public.school_subjects;
create policy school_subjects_read_modification on public.school_subjects for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists school_years_read_modification on public.school_years;
create policy school_years_read_modification on public.school_years for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists classes_read_modification on public.classes;
create policy classes_read_modification on public.classes for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists students_read_modification on public.students;
create policy students_read_modification on public.students for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists enrollments_read_modification on public.enrollments;
create policy enrollments_read_modification on public.enrollments for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));
drop policy if exists student_grades_read_modification on public.student_grades;
create policy student_grades_read_modification on public.student_grades for select to authenticated
using (public.has_any_role(array['modification']::public.app_role[]));

-- Étendre les droits de modification de student_grades au rôle métier Modification, sans élargir les droits de lecture.
drop policy if exists student_grades_manage on public.student_grades;
drop policy if exists student_grades_insert on public.student_grades;
drop policy if exists student_grades_update on public.student_grades;
create policy student_grades_insert on public.student_grades for insert to authenticated
with check (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]));
create policy student_grades_update on public.student_grades for update to authenticated
using (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat','modification']::public.app_role[]));
grant select, insert, update on public.school_assessments, public.school_grade_rules, public.school_bulletins to authenticated;
grant select, insert, update on public.student_grades to authenticated;

commit;
