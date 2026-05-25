-- Hokie Advisor Supabase foundation.
-- Apply in Supabase SQL Editor or with `supabase db push`.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  vt_pid text,
  vt_email text,
  full_name text,
  major text,
  graduation_year text,
  appearance_mode text default 'system',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.transcripts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_type text not null default 'uploaded',
  parser_model text,
  transcript_notes text[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.transcript_courses (
  id uuid primary key default gen_random_uuid(),
  transcript_id uuid not null references public.transcripts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  code text not null,
  name text not null default '',
  credits numeric,
  grade text,
  semester text,
  status text not null check (status in ('completed', 'in_progress', 'planned')),
  source jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.chat_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'New Chat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.chat_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('system', 'user', 'assistant', 'tool')),
  content text not null,
  position integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.chat_memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.degree_audits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  transcript_id uuid references public.transcripts(id) on delete set null,
  major text not null,
  degree text,
  catalog_year text,
  percent_complete integer,
  response jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.dars_audits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  student_id text,
  program text,
  program_code text,
  catalog_year text,
  prepared_on text,
  response jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.catalog_subjects (
  code text primary key,
  name text not null default '',
  url text not null default '',
  source text not null default 'local_json',
  updated_at timestamptz not null default now()
);

create table if not exists public.catalog_courses (
  subject text not null,
  code text not null,
  name text not null default '',
  credits numeric,
  description text not null default '',
  prerequisites text not null default '',
  raw jsonb not null default '{}'::jsonb,
  source text not null default 'local_json',
  updated_at timestamptz not null default now(),
  primary key (subject, code)
);

create table if not exists public.coe_courses (
  subject text not null,
  code text not null,
  name text not null default '',
  credits numeric,
  description text not null default '',
  prerequisites text not null default '',
  raw jsonb not null default '{}'::jsonb,
  source text not null default 'coe_json',
  updated_at timestamptz not null default now(),
  primary key (subject, code)
);

create table if not exists public.catalog_programs (
  key text primary key,
  name text not null default '',
  code text not null default '',
  degree text not null default '',
  url text not null default '',
  raw jsonb not null default '{}'::jsonb,
  source text not null default 'local_json',
  updated_at timestamptz not null default now()
);

create table if not exists public.catalog_requirements (
  program_key text primary key,
  name text not null default '',
  requirements jsonb not null default '{}'::jsonb,
  source text not null default 'local_json',
  updated_at timestamptz not null default now()
);

create table if not exists public.pathways_courses (
  code text not null,
  concept text not null,
  name text not null default '',
  credits numeric,
  raw jsonb not null default '{}'::jsonb,
  source text not null default 'pathways_json',
  updated_at timestamptz not null default now(),
  primary key (code, concept)
);

create index if not exists idx_transcript_courses_user_id on public.transcript_courses(user_id);
create index if not exists idx_transcript_courses_code on public.transcript_courses(code);
create index if not exists idx_chat_messages_session_id on public.chat_messages(session_id, position);
create index if not exists idx_catalog_courses_search on public.catalog_courses using gin (
  to_tsvector('english', coalesce(code, '') || ' ' || coalesce(name, '') || ' ' || coalesce(description, ''))
);
create index if not exists idx_coe_courses_search on public.coe_courses using gin (
  to_tsvector('english', coalesce(code, '') || ' ' || coalesce(name, '') || ' ' || coalesce(description, ''))
);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists transcripts_set_updated_at on public.transcripts;
create trigger transcripts_set_updated_at before update on public.transcripts
for each row execute function public.set_updated_at();

drop trigger if exists transcript_courses_set_updated_at on public.transcript_courses;
create trigger transcript_courses_set_updated_at before update on public.transcript_courses
for each row execute function public.set_updated_at();

drop trigger if exists chat_sessions_set_updated_at on public.chat_sessions;
create trigger chat_sessions_set_updated_at before update on public.chat_sessions
for each row execute function public.set_updated_at();

drop trigger if exists chat_memories_set_updated_at on public.chat_memories;
create trigger chat_memories_set_updated_at before update on public.chat_memories
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.transcripts enable row level security;
alter table public.transcript_courses enable row level security;
alter table public.chat_sessions enable row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_memories enable row level security;
alter table public.degree_audits enable row level security;
alter table public.dars_audits enable row level security;
alter table public.catalog_subjects enable row level security;
alter table public.catalog_courses enable row level security;
alter table public.coe_courses enable row level security;
alter table public.catalog_programs enable row level security;
alter table public.catalog_requirements enable row level security;
alter table public.pathways_courses enable row level security;

drop policy if exists "profiles are user owned" on public.profiles;
create policy "profiles are user owned" on public.profiles
for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "transcripts are user owned" on public.transcripts;
create policy "transcripts are user owned" on public.transcripts
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "transcript courses are user owned" on public.transcript_courses;
create policy "transcript courses are user owned" on public.transcript_courses
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "chat sessions are user owned" on public.chat_sessions;
create policy "chat sessions are user owned" on public.chat_sessions
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "chat messages are user owned" on public.chat_messages;
create policy "chat messages are user owned" on public.chat_messages
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "chat memories are user owned" on public.chat_memories;
create policy "chat memories are user owned" on public.chat_memories
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "degree audits are user owned" on public.degree_audits;
create policy "degree audits are user owned" on public.degree_audits
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "dars audits are user owned" on public.dars_audits;
create policy "dars audits are user owned" on public.dars_audits
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "catalog subjects are readable" on public.catalog_subjects;
create policy "catalog subjects are readable" on public.catalog_subjects
for select using (true);

drop policy if exists "catalog courses are readable" on public.catalog_courses;
create policy "catalog courses are readable" on public.catalog_courses
for select using (true);

drop policy if exists "coe courses are readable" on public.coe_courses;
create policy "coe courses are readable" on public.coe_courses
for select using (true);

drop policy if exists "catalog programs are readable" on public.catalog_programs;
create policy "catalog programs are readable" on public.catalog_programs
for select using (true);

drop policy if exists "catalog requirements are readable" on public.catalog_requirements;
create policy "catalog requirements are readable" on public.catalog_requirements
for select using (true);

drop policy if exists "pathways courses are readable" on public.pathways_courses;
create policy "pathways courses are readable" on public.pathways_courses
for select using (true);
