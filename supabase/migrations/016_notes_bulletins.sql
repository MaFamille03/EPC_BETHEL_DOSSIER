-- EPC BETHEL — Notes et bulletins scolaires
-- À appliquer après les migrations 001 à 015 sur un environnement de test avant production.
begin;
create table if not exists public.school_subjects (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.student_grades (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  subject_id uuid not null references public.school_subjects(id) on delete restrict,
  term text not null check (term in ('T1','T2','T3')),
  assessment_label text not null,
  assessment_date date not null default current_date,
  score numeric(5,2) not null check (score >= 0 and score <= 20),
  coefficient numeric(5,2) not null default 1 check (coefficient > 0 and coefficient <= 20),
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique (enrollment_id, subject_id, term, assessment_label)
);
create index if not exists student_grades_enrollment_term_idx on public.student_grades(enrollment_id,term,subject_id);
alter table public.school_subjects enable row level security;
alter table public.student_grades enable row level security;
drop policy if exists school_subjects_read on public.school_subjects;
create policy school_subjects_read on public.school_subjects for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','observateur']::public.app_role[]));
drop policy if exists school_subjects_manage on public.school_subjects;
create policy school_subjects_manage on public.school_subjects for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));
drop policy if exists student_grades_read on public.student_grades;
create policy student_grades_read on public.student_grades for select to authenticated
using (public.has_any_role(array['admin','direction','secretariat','observateur']::public.app_role[]));
drop policy if exists student_grades_manage on public.student_grades;
create policy student_grades_manage on public.student_grades for all to authenticated
using (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]))
with check (public.has_any_role(array['admin','direction','secretariat']::public.app_role[]));
grant select, insert, update on public.school_subjects, public.student_grades to authenticated;
commit;
