create extension if not exists pgcrypto with schema extensions;

do $$ begin
  create type public.course_status as enum ('draft', 'published', 'archived');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.subscription_status as enum ('pending', 'active', 'expired', 'cancelled', 'refunded');
exception when duplicate_object then null; end $$;

create table if not exists public.platform_settings (
  singleton boolean primary key default true check (singleton),
  owner_id uuid references auth.users(id) on delete restrict,
  brand_name text not null default 'مستر إياد الطيب | المؤرخ الصغير 📜',
  required_completion_percent integer not null default 90 check (required_completion_percent between 1 and 100),
  allow_playback_speed boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.platform_settings (singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text not null default '',
  phone text not null default '',
  guardian_phone text not null default '',
  grade text not null default '',
  avatar_url text,
  role text not null default 'student' check (role in ('student', 'owner')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists phone text not null default '';
alter table public.profiles add column if not exists guardian_phone text not null default '';
alter table public.profiles add column if not exists grade text not null default '';

create or replace function public.is_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_settings
    where singleton and owner_id = auth.uid()
  );
$$;

revoke all on function public.is_platform_owner() from public;
grant execute on function public.is_platform_owner() to anon, authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  account_role text := 'student';
begin
  -- Lock the singleton row so concurrent signups cannot both become owner.
  update public.platform_settings
  set owner_id = new.id, updated_at = now()
  where singleton and owner_id is null;

  if found then
    account_role := 'owner';
  end if;

  insert into public.profiles (id, email, display_name, phone, guardian_phone, grade, role)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(coalesce(new.email, ''), '@', 1)),
    coalesce(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'guardian_phone', ''),
    coalesce(new.raw_user_meta_data ->> 'grade', ''),
    account_role
  )
  on conflict (id) do update set
    email = excluded.email,
    phone = excluded.phone,
    guardian_phone = excluded.guardian_phone,
    grade = excluded.grade;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.claim_platform_owner(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Only the server may claim the platform owner';
  end if;

  update public.platform_settings
  set owner_id = p_user_id, updated_at = now()
  where singleton and owner_id is null;

  if not found then
    raise exception 'The platform owner has already been claimed';
  end if;

  update public.profiles
  set role = 'owner', display_name = 'مستر إياد الطيب | المؤرخ الصغير 📜', updated_at = now()
  where id = p_user_id;
  if not found then
    raise exception 'The selected account does not exist';
  end if;
end;
$$;

revoke all on function public.claim_platform_owner(uuid) from public, anon, authenticated;
grant execute on function public.claim_platform_owner(uuid) to service_role;

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.school_grades (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  stage text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.subjects (name, slug, sort_order) values
  ('التاريخ', 'history', 1),
  ('الدراسات الاجتماعية', 'social-studies', 2)
on conflict (slug) do nothing;

insert into public.school_grades (name, stage, sort_order) values
  ('الصف الأول الثانوي', 'ثانوي', 1),
  ('الصف الثالث الإعدادي', 'إعدادي', 2)
on conflict (name) do nothing;

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete restrict,
  grade_id uuid not null references public.school_grades(id) on delete restrict,
  title text not null,
  slug text not null unique,
  description text not null default '',
  price_minor integer not null default 0 check (price_minor >= 0),
  currency text not null default 'EGP' check (currency ~ '^[A-Z]{3}$'),
  duration_minutes integer check (duration_minutes is null or duration_minutes >= 0),
  thumbnail_path text,
  status public.course_status not null default 'draft',
  is_free boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.course_sections (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title text not null,
  description text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (course_id, sort_order)
);

create table if not exists public.lectures (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references public.course_sections(id) on delete cascade,
  title text not null,
  description text not null default '',
  summary text not null default '',
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  completion_required_percent integer not null default 90 check (completion_required_percent between 1 and 100),
  is_published boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (section_id, sort_order)
);

create table if not exists public.video_sources (
  id uuid primary key default gen_random_uuid(),
  lecture_id uuid not null unique references public.lectures(id) on delete cascade,
  provider text not null default 'youtube' check (provider = 'youtube'),
  video_id text not null check (video_id ~ '^[A-Za-z0-9_-]{11}$'),
  playback_speed_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lecture_resources (
  id uuid primary key default gen_random_uuid(),
  lecture_id uuid not null references public.lectures(id) on delete cascade,
  title text not null,
  resource_type text not null check (resource_type in ('pdf', 'summary', 'link', 'other')),
  storage_path text,
  external_url text,
  downloadable boolean not null default true,
  available_after_completion boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  check (storage_path is not null or external_url is not null)
);

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  status public.subscription_status not null default 'pending',
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at is null or starts_at is null or expires_at > starts_at)
);

create unique index if not exists subscriptions_one_active_per_course
  on public.subscriptions (student_id, course_id)
  where status = 'active';
create unique index if not exists subscriptions_one_pending_per_course
  on public.subscriptions (student_id, course_id)
  where status = 'pending';

create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  status text not null default 'active' check (status in ('active', 'completed', 'cancelled')),
  enrolled_at timestamptz not null default now(),
  unique (student_id, course_id)
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.subscriptions(id) on delete restrict,
  student_id uuid not null references public.profiles(id) on delete restrict,
  amount_minor integer not null check (amount_minor >= 0),
  currency text not null default 'EGP' check (currency ~ '^[A-Z]{3}$'),
  provider text not null,
  provider_reference text unique,
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed', 'refunded')),
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.watch_progress (
  student_id uuid not null references public.profiles(id) on delete cascade,
  lecture_id uuid not null references public.lectures(id) on delete cascade,
  current_time_seconds integer not null default 0 check (current_time_seconds >= 0),
  watched_duration_seconds integer not null default 0 check (watched_duration_seconds >= 0),
  progress_percentage numeric(5,2) not null default 0 check (progress_percentage between 0 and 100),
  completed boolean not null default false,
  last_watched_at timestamptz not null default now(),
  primary key (student_id, lecture_id)
);

create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  lecture_id uuid references public.lectures(id) on delete set null,
  title text not null,
  instructions text not null default '',
  due_at timestamptz,
  max_score numeric(7,2) not null default 100 check (max_score >= 0),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.assignment_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  submission_text text not null default '',
  file_path text,
  submitted_at timestamptz not null default now(),
  grade numeric(7,2) check (grade is null or grade >= 0),
  feedback text not null default '',
  reviewed_at timestamptz,
  unique (assignment_id, student_id)
);

create table if not exists public.quizzes (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  lecture_id uuid references public.lectures(id) on delete set null,
  title text not null,
  instructions text not null default '',
  max_attempts integer not null default 1 check (max_attempts > 0),
  duration_minutes integer check (duration_minutes is null or duration_minutes > 0),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes(id) on delete cascade,
  prompt text not null,
  question_type text not null default 'multiple_choice' check (question_type in ('multiple_choice', 'short_answer')),
  points numeric(7,2) not null default 1 check (points >= 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (quiz_id, sort_order)
);

create table if not exists public.quiz_choices (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.quiz_questions(id) on delete cascade,
  choice_text text not null,
  sort_order integer not null default 0,
  unique (question_id, sort_order),
  unique (question_id, id)
);

create table if not exists public.quiz_answer_keys (
  question_id uuid primary key references public.quiz_questions(id) on delete cascade,
  correct_choice_id uuid,
  accepted_answers text[] not null default '{}',
  updated_at timestamptz not null default now(),
  foreign key (question_id, correct_choice_id) references public.quiz_choices(question_id, id) on delete cascade
);

create table if not exists public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  attempt_number integer not null check (attempt_number > 0),
  status text not null default 'in_progress' check (status in ('in_progress', 'submitted', 'graded')),
  score numeric(7,2),
  max_score numeric(7,2) not null default 0,
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  unique (quiz_id, student_id, attempt_number)
);

create unique index if not exists quiz_attempts_one_open_attempt
  on public.quiz_attempts (quiz_id, student_id)
  where status = 'in_progress';

create table if not exists public.quiz_responses (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.quiz_attempts(id) on delete cascade,
  question_id uuid not null references public.quiz_questions(id) on delete cascade,
  selected_choice_id uuid references public.quiz_choices(id) on delete set null,
  answer_text text not null default '',
  created_at timestamptz not null default now(),
  unique (attempt_id, question_id)
);

create table if not exists public.student_grades (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  assignment_submission_id uuid references public.assignment_submissions(id) on delete cascade,
  quiz_attempt_id uuid references public.quiz_attempts(id) on delete cascade,
  score numeric(7,2) not null check (score >= 0),
  max_score numeric(7,2) not null check (max_score >= 0),
  feedback text not null default '',
  graded_at timestamptz not null default now(),
  check ((assignment_submission_id is null) <> (quiz_attempt_id is null)),
  unique (assignment_submission_id),
  unique (quiz_attempt_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  notification_type text not null default 'general',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.notification_reads (
  notification_id uuid not null references public.notifications(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (notification_id, student_id)
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  is_published boolean not null default false,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists courses_subject_grade_status_idx on public.courses (subject_id, grade_id, status, sort_order);
create index if not exists sections_course_order_idx on public.course_sections (course_id, sort_order);
create index if not exists lectures_section_order_idx on public.lectures (section_id, sort_order);
create index if not exists subscriptions_student_status_idx on public.subscriptions (student_id, status, expires_at);
create index if not exists watch_progress_student_idx on public.watch_progress (student_id, last_watched_at desc);
create index if not exists notifications_student_created_idx on public.notifications (student_id, created_at desc);
create index if not exists assignments_course_due_idx on public.assignments (course_id, due_at);
create index if not exists quizzes_course_idx on public.quizzes (course_id, is_published);

create or replace function public.has_course_access(p_course_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_owner()
    or exists (
      select 1 from public.courses c
      where c.id = p_course_id and c.status = 'published' and c.is_free
    )
    or exists (
      select 1 from public.subscriptions s
      where s.course_id = p_course_id
        and s.student_id = auth.uid()
        and s.status = 'active'
        and (s.starts_at is null or s.starts_at <= now())
        and (s.expires_at is null or s.expires_at > now())
    );
$$;

revoke all on function public.has_course_access(uuid) from public, anon;
grant execute on function public.has_course_access(uuid) to authenticated;

create or replace function public.request_course_subscription(p_course_id uuid)
returns public.subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid := auth.uid();
  v_course public.courses;
  v_existing public.subscriptions;
  v_subscription public.subscriptions;
  v_status public.subscription_status;
begin
  if v_student_id is null or public.is_platform_owner() then
    raise exception 'Student authentication is required';
  end if;

  select * into v_course from public.courses where id = p_course_id and status = 'published';
  if not found then raise exception 'Course is not available'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_student_id::text || p_course_id::text, 0));
  select * into v_existing from public.subscriptions
  where student_id = v_student_id and course_id = p_course_id and status in ('active', 'pending')
  order by case when status = 'active' then 0 else 1 end
  limit 1 for update;
  if found then return v_existing; end if;

  v_status := case when v_course.is_free then 'active'::public.subscription_status else 'pending'::public.subscription_status end;
  insert into public.subscriptions (student_id, course_id, status, starts_at)
  values (v_student_id, p_course_id, v_status, case when v_status = 'active' then now() else null end)
  returning * into v_subscription;

  if v_status = 'active' then
    insert into public.enrollments (student_id, course_id, subscription_id)
    values (v_student_id, p_course_id, v_subscription.id)
    on conflict (student_id, course_id) do update
      set subscription_id = excluded.subscription_id, status = 'active';
  end if;

  return v_subscription;
end;
$$;

revoke all on function public.request_course_subscription(uuid) from public, anon;
grant execute on function public.request_course_subscription(uuid) to authenticated;

alter table public.platform_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.subjects enable row level security;
alter table public.school_grades enable row level security;
alter table public.courses enable row level security;
alter table public.course_sections enable row level security;
alter table public.lectures enable row level security;
alter table public.video_sources enable row level security;
alter table public.lecture_resources enable row level security;
alter table public.subscriptions enable row level security;
alter table public.enrollments enable row level security;
alter table public.payments enable row level security;
alter table public.watch_progress enable row level security;
alter table public.assignments enable row level security;
alter table public.assignment_submissions enable row level security;
alter table public.quizzes enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_choices enable row level security;
alter table public.quiz_answer_keys enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.quiz_responses enable row level security;
alter table public.student_grades enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_reads enable row level security;
alter table public.announcements enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.platform_settings, public.subjects, public.school_grades, public.courses, public.course_sections, public.lectures, public.video_sources, public.lecture_resources, public.assignments, public.quizzes, public.quiz_questions, public.quiz_choices, public.announcements to anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, avatar_url) on public.profiles to authenticated;
grant update (brand_name, required_completion_percent, allow_playback_speed, updated_at) on public.platform_settings to authenticated;
grant insert, update, delete on public.subjects, public.school_grades, public.courses, public.course_sections, public.lectures, public.video_sources, public.lecture_resources, public.assignments, public.quizzes, public.quiz_questions, public.quiz_choices, public.quiz_answer_keys, public.announcements to authenticated;
grant select on public.quiz_answer_keys to authenticated;
grant select on public.subscriptions, public.enrollments, public.payments, public.watch_progress, public.assignment_submissions, public.quiz_attempts, public.quiz_responses, public.student_grades, public.notifications, public.notification_reads to authenticated;
grant insert, update, delete on public.subscriptions, public.enrollments, public.student_grades, public.notifications to authenticated;
revoke insert, update on public.assignment_submissions from authenticated;
grant insert on public.quiz_responses to authenticated;
grant insert on public.notification_reads to authenticated;
grant all on all tables in schema public to service_role;

revoke update on public.profiles from authenticated;
grant update (display_name, avatar_url) on public.profiles to authenticated;
revoke insert, update, delete on public.payments, public.watch_progress, public.quiz_attempts from anon, authenticated;
revoke update, delete on public.quiz_responses from anon, authenticated;
revoke insert, update, delete on public.subscriptions, public.enrollments, public.student_grades, public.notifications from anon;
revoke update, delete on public.quiz_answer_keys from anon;

create policy "owner reads settings" on public.platform_settings for select to authenticated using (public.is_platform_owner());
create policy "owner manages settings" on public.platform_settings for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());

create policy "read own profile or owner reads all" on public.profiles for select to authenticated using (id = auth.uid() or public.is_platform_owner());
create policy "students update own profile" on public.profiles for update to authenticated using (id = auth.uid() and not public.is_platform_owner()) with check (id = auth.uid() and not public.is_platform_owner());
create policy "owner manages profiles" on public.profiles for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());

create policy "active subjects are public" on public.subjects for select to anon, authenticated using (is_active or public.is_platform_owner());
create policy "owner manages subjects" on public.subjects for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "active school grades are public" on public.school_grades for select to anon, authenticated using (is_active or public.is_platform_owner());
create policy "owner manages school grades" on public.school_grades for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());

create policy "published course catalog is public" on public.courses for select to anon, authenticated using (status = 'published' or public.is_platform_owner());
create policy "owner manages courses" on public.courses for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "accessible sections are readable" on public.course_sections for select to authenticated using (public.has_course_access(course_id));
create policy "owner manages sections" on public.course_sections for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "accessible lectures are readable" on public.lectures for select to authenticated using (
  is_published and exists (select 1 from public.course_sections s where s.id = section_id and public.has_course_access(s.course_id))
  or public.is_platform_owner()
);
create policy "owner manages lectures" on public.lectures for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "accessible video sources are readable" on public.video_sources for select to authenticated using (
  exists (select 1 from public.lectures l join public.course_sections s on s.id = l.section_id where l.id = lecture_id and l.is_published and public.has_course_access(s.course_id))
  or public.is_platform_owner()
);
create policy "owner manages video sources" on public.video_sources for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "accessible lecture resources are readable" on public.lecture_resources for select to authenticated using (
  exists (select 1 from public.lectures l join public.course_sections s on s.id = l.section_id where l.id = lecture_id and l.is_published and public.has_course_access(s.course_id))
  or public.is_platform_owner()
);
create policy "owner manages lecture resources" on public.lecture_resources for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());

create policy "students read own subscriptions" on public.subscriptions for select to authenticated using (student_id = auth.uid() or public.is_platform_owner());
create policy "owner manages subscriptions" on public.subscriptions for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "students read own enrollments" on public.enrollments for select to authenticated using (student_id = auth.uid() or public.is_platform_owner());
create policy "owner manages enrollments" on public.enrollments for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "students read own payments" on public.payments for select to authenticated using (student_id = auth.uid() or public.is_platform_owner());
create policy "owner reads payments" on public.payments for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());

create policy "students read own progress" on public.watch_progress for select to authenticated using (student_id = auth.uid() or public.is_platform_owner());
create policy "accessible assignments are readable" on public.assignments for select to authenticated using (is_published and public.has_course_access(course_id) or public.is_platform_owner());
create policy "owner manages assignments" on public.assignments for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "students read own submissions" on public.assignment_submissions for select to authenticated using (student_id = auth.uid() or public.is_platform_owner());
create policy "owner manages submissions" on public.assignment_submissions for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());

create policy "accessible quizzes are readable" on public.quizzes for select to authenticated using (is_published and public.has_course_access(course_id) or public.is_platform_owner());
create policy "owner manages quizzes" on public.quizzes for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "accessible quiz questions are readable" on public.quiz_questions for select to authenticated using (
  exists (select 1 from public.quizzes q where q.id = quiz_id and q.is_published and public.has_course_access(q.course_id))
  or public.is_platform_owner()
);
create policy "owner manages quiz questions" on public.quiz_questions for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "accessible quiz choices are readable" on public.quiz_choices for select to authenticated using (
  exists (select 1 from public.quiz_questions q join public.quizzes z on z.id = q.quiz_id where q.id = question_id and z.is_published and public.has_course_access(z.course_id))
  or public.is_platform_owner()
);
create policy "owner manages quiz choices" on public.quiz_choices for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "only owner reads answer keys" on public.quiz_answer_keys for select to authenticated using (public.is_platform_owner());
create policy "owner manages answer keys" on public.quiz_answer_keys for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "students read own attempts" on public.quiz_attempts for select to authenticated using (student_id = auth.uid() or public.is_platform_owner());
create policy "students add attempt responses" on public.quiz_responses for insert to authenticated with check (
  exists (
    select 1 from public.quiz_attempts a
    join public.quizzes z on z.id = a.quiz_id
    join public.quiz_questions q on q.quiz_id = z.id
    where a.id = attempt_id and a.student_id = auth.uid() and a.status = 'in_progress'
      and q.id = question_id and public.has_course_access(z.course_id)
  )
);
create policy "students read own responses" on public.quiz_responses for select to authenticated using (
  exists (select 1 from public.quiz_attempts a where a.id = attempt_id and a.student_id = auth.uid())
  or public.is_platform_owner()
);
create policy "owner manages responses" on public.quiz_responses for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "students read own grades" on public.student_grades for select to authenticated using (student_id = auth.uid() or public.is_platform_owner());
create policy "owner manages student grades" on public.student_grades for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());

create policy "students read own and broadcast notifications" on public.notifications for select to authenticated using (student_id = auth.uid() or student_id is null or public.is_platform_owner());
create policy "owner manages notifications" on public.notifications for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
create policy "students read own notification receipts" on public.notification_reads for select to authenticated using (student_id = auth.uid() or public.is_platform_owner());
create policy "students insert own notification receipts" on public.notification_reads for insert to authenticated with check (
  student_id = auth.uid()
  and exists (select 1 from public.notifications n where n.id = notification_id and (n.student_id = auth.uid() or n.student_id is null))
);
create policy "owner reads notification receipts" on public.notification_reads for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows integer;
begin
  if auth.uid() is null or public.is_platform_owner() then
    raise exception 'Student authentication is required';
  end if;

  insert into public.notification_reads (notification_id, student_id, read_at)
  select n.id, auth.uid(), now()
  from public.notifications n
  where n.id = p_notification_id and (n.student_id = auth.uid() or n.student_id is null)
  on conflict (notification_id, student_id) do update set read_at = excluded.read_at;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'Notification not found'; end if;
end;
$$;

revoke all on function public.mark_notification_read(uuid) from public, anon;
grant execute on function public.mark_notification_read(uuid) to authenticated;

create policy "published announcements are public" on public.announcements for select to anon, authenticated using (is_published or public.is_platform_owner());
create policy "owner manages announcements" on public.announcements for all to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());

create or replace function public.submit_assignment(
  p_assignment_id uuid,
  p_submission_text text default '',
  p_file_path text default null
)
returns public.assignment_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid := auth.uid();
  v_course_id uuid;
  v_submission public.assignment_submissions;
begin
  if v_student_id is null or public.is_platform_owner() then
    raise exception 'Student authentication is required';
  end if;

  select course_id into v_course_id
  from public.assignments
  where id = p_assignment_id and is_published and (due_at is null or due_at >= now());
  if not found or not public.has_course_access(v_course_id) then
    raise exception 'Assignment is unavailable or the course subscription is inactive';
  end if;

  if p_file_path is not null and (
    split_part(p_file_path, '/', 1) <> v_student_id::text
    or split_part(p_file_path, '/', 2) <> p_assignment_id::text
  ) then
    raise exception 'Assignment file path is invalid';
  end if;

  insert into public.assignment_submissions (assignment_id, student_id, submission_text, file_path)
  values (p_assignment_id, v_student_id, coalesce(p_submission_text, ''), p_file_path)
  on conflict (assignment_id, student_id) do update
    set submission_text = excluded.submission_text,
        file_path = excluded.file_path,
        submitted_at = now()
  returning * into v_submission;

  return v_submission;
end;
$$;

create or replace function public.grade_assignment(
  p_submission_id uuid,
  p_grade numeric,
  p_feedback text default ''
)
returns public.assignment_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max_score numeric(7,2);
  v_course_id uuid;
  v_submission public.assignment_submissions;
begin
  if not public.is_platform_owner() then raise exception 'Only the platform owner may grade assignments'; end if;
  select a.max_score, a.course_id into v_max_score, v_course_id
  from public.assignment_submissions s
  join public.assignments a on a.id = s.assignment_id
  where s.id = p_submission_id;
  if not found then raise exception 'Assignment submission not found'; end if;
  if p_grade < 0 or p_grade > v_max_score then raise exception 'Grade is outside the assignment score range'; end if;

  update public.assignment_submissions
  set grade = p_grade, feedback = coalesce(p_feedback, ''), reviewed_at = now()
  where id = p_submission_id
  returning * into v_submission;

  insert into public.student_grades (student_id, course_id, assignment_submission_id, score, max_score, feedback)
  values (v_submission.student_id, v_course_id, v_submission.id, p_grade, v_max_score, coalesce(p_feedback, ''))
  on conflict (assignment_submission_id) do update
    set score = excluded.score,
        max_score = excluded.max_score,
        feedback = excluded.feedback,
        graded_at = now();

  return v_submission;
end;
$$;

revoke all on function public.submit_assignment(uuid, text, text) from public, anon;
grant execute on function public.submit_assignment(uuid, text, text) to authenticated;
revoke all on function public.grade_assignment(uuid, numeric, text) from public, anon;
grant execute on function public.grade_assignment(uuid, numeric, text) to authenticated;

create or replace function public.record_watch_progress(p_lecture_id uuid, p_current_time_seconds integer)
returns public.watch_progress
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid := auth.uid();
  v_course_id uuid;
  v_duration integer;
  v_required integer;
  v_now timestamptz := clock_timestamp();
  v_row public.watch_progress;
  v_elapsed integer;
  v_delta integer;
begin
  if v_student_id is null or public.is_platform_owner() then
    raise exception 'Student authentication is required';
  end if;

  select s.course_id, l.duration_seconds, l.completion_required_percent
  into v_course_id, v_duration, v_required
  from public.lectures l
  join public.course_sections s on s.id = l.section_id
  where l.id = p_lecture_id and l.is_published;

  if not found or not public.has_course_access(v_course_id) then
    raise exception 'Lecture access denied';
  end if;

  select * into v_row from public.watch_progress
  where student_id = v_student_id and lecture_id = p_lecture_id for update;

  if not found then
    insert into public.watch_progress (student_id, lecture_id, current_time_seconds, last_watched_at)
    values (v_student_id, p_lecture_id, greatest(0, least(coalesce(p_current_time_seconds, 0), v_duration)), v_now)
    returning * into v_row;
    return v_row;
  end if;

  v_elapsed := greatest(0, floor(extract(epoch from (v_now - v_row.last_watched_at)))::integer);
  v_delta := least(
    greatest(0, coalesce(p_current_time_seconds, 0) - v_row.current_time_seconds),
    v_elapsed,
    30
  );

  update public.watch_progress
  set current_time_seconds = greatest(0, least(coalesce(p_current_time_seconds, 0), v_duration)),
      watched_duration_seconds = least(v_duration, v_row.watched_duration_seconds + v_delta),
      progress_percentage = case when v_duration > 0 then round(100.0 * least(v_duration, v_row.watched_duration_seconds + v_delta) / v_duration, 2) else 0 end,
      completed = case when v_duration > 0 then 100.0 * least(v_duration, v_row.watched_duration_seconds + v_delta) / v_duration >= v_required else false end,
      last_watched_at = v_now
  where student_id = v_student_id and lecture_id = p_lecture_id
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.record_watch_progress(uuid, integer) from public, anon;
grant execute on function public.record_watch_progress(uuid, integer) to authenticated;

create or replace function public.start_quiz_attempt(p_quiz_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid := auth.uid();
  v_course_id uuid;
  v_max_attempts integer;
  v_count integer;
  v_attempt_id uuid;
begin
  if v_student_id is null or public.is_platform_owner() then raise exception 'Student authentication is required'; end if;
  select course_id, max_attempts into v_course_id, v_max_attempts
  from public.quizzes where id = p_quiz_id and is_published;
  if not found or not public.has_course_access(v_course_id) then raise exception 'Quiz access denied'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_student_id::text || p_quiz_id::text, 0));
  select count(*) into v_count from public.quiz_attempts where quiz_id = p_quiz_id and student_id = v_student_id;
  if v_count >= v_max_attempts then raise exception 'Attempt limit reached'; end if;
  insert into public.quiz_attempts (quiz_id, student_id, attempt_number)
  values (p_quiz_id, v_student_id, v_count + 1)
  returning id into v_attempt_id;
  return v_attempt_id;
end;
$$;

create or replace function public.submit_quiz_attempt(p_attempt_id uuid)
returns public.quiz_attempts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attempt public.quiz_attempts;
  v_course_id uuid;
  v_score numeric(7,2);
  v_max numeric(7,2);
begin
  select * into v_attempt from public.quiz_attempts
  where id = p_attempt_id and student_id = auth.uid() and status = 'in_progress'
  for update;
  if not found then raise exception 'Attempt not found or already submitted'; end if;
  select course_id into v_course_id from public.quizzes where id = v_attempt.quiz_id;
  if not public.has_course_access(v_course_id) then raise exception 'Quiz access denied'; end if;

  select coalesce(sum(q.points), 0) into v_max
  from public.quiz_questions q where q.quiz_id = v_attempt.quiz_id;

  select coalesce(sum(case
    when r.selected_choice_id = k.correct_choice_id then q.points
    when q.question_type = 'short_answer' and exists (
      select 1 from unnest(k.accepted_answers) accepted(answer)
      where lower(trim(accepted.answer)) = lower(trim(r.answer_text))
    ) then q.points
    else 0
  end), 0)
  into v_score
  from public.quiz_responses r
  join public.quiz_questions q on q.id = r.question_id and q.quiz_id = v_attempt.quiz_id
  left join public.quiz_answer_keys k on k.question_id = q.id
  where r.attempt_id = p_attempt_id;

  update public.quiz_attempts
  set status = 'submitted', score = v_score, max_score = v_max, submitted_at = now()
  where id = p_attempt_id returning * into v_attempt;

  insert into public.student_grades (student_id, course_id, quiz_attempt_id, score, max_score)
  values (v_attempt.student_id, v_course_id, v_attempt.id, v_score, v_max)
  on conflict (quiz_attempt_id) do update set score = excluded.score, max_score = excluded.max_score, graded_at = now();

  return v_attempt;
end;
$$;

revoke all on function public.start_quiz_attempt(uuid) from public, anon;
grant execute on function public.start_quiz_attempt(uuid) to authenticated;
revoke all on function public.submit_quiz_attempt(uuid) from public, anon;
grant execute on function public.submit_quiz_attempt(uuid) to authenticated;

create or replace function public.protect_assignment_grading()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_owner()
    and (new.grade is distinct from old.grade or new.feedback is distinct from old.feedback or new.reviewed_at is distinct from old.reviewed_at) then
    raise exception 'Only the platform owner may grade assignments';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_assignment_grading_fields on public.assignment_submissions;
create trigger protect_assignment_grading_fields
before update on public.assignment_submissions
for each row execute function public.protect_assignment_grading();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('course-resources', 'course-resources', false, 20971520, array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('assignment-submissions', 'assignment-submissions', false, 20971520, array['application/pdf'])
on conflict (id) do nothing;

create policy "students read resources for accessible courses" on storage.objects
for select to authenticated using (
  bucket_id = 'course-resources'
  and public.has_course_access(((storage.foldername(name))[1])::uuid)
);
create policy "owner manages course resources" on storage.objects
for all to authenticated using (bucket_id = 'course-resources' and public.is_platform_owner())
with check (bucket_id = 'course-resources' and public.is_platform_owner());
create policy "students upload own assignment files" on storage.objects
for insert to authenticated with check (
  bucket_id = 'assignment-submissions'
  and split_part(name, '/', 1) = auth.uid()::text
  and exists (
    select 1 from public.assignments a
    where a.id::text = split_part(name, '/', 2)
      and a.is_published
      and (a.due_at is null or a.due_at >= now())
      and public.has_course_access(a.course_id)
  )
);
create policy "students and owner read assignment files" on storage.objects
for select to authenticated using (
  bucket_id = 'assignment-submissions'
  and (
    public.is_platform_owner()
    or split_part(name, '/', 1) = auth.uid()::text
  )
);
create policy "owner manages assignment files" on storage.objects
for all to authenticated using (bucket_id = 'assignment-submissions' and public.is_platform_owner())
with check (bucket_id = 'assignment-submissions' and public.is_platform_owner());