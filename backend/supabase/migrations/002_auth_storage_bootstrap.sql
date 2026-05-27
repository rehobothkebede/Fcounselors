-- Hokie Advisor Supabase auth/storage bootstrap.
-- Apply after 001_initial_schema.sql.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id,
    vt_pid,
    vt_email,
    full_name,
    major,
    graduation_year,
    appearance_mode
  )
  values (
    new.id,
    nullif(new.raw_user_meta_data ->> 'vt_pid', ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'vt_email', ''), new.email),
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'major', ''), 'Computer Science'),
    nullif(new.raw_user_meta_data ->> 'graduation_year', ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'appearance_mode', ''), 'system')
  )
  on conflict (id) do update set
    vt_pid = excluded.vt_pid,
    vt_email = excluded.vt_email,
    full_name = excluded.full_name,
    major = excluded.major,
    graduation_year = excluded.graduation_year,
    appearance_mode = excluded.appearance_mode;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'transcripts',
    'transcripts',
    false,
    12582912,
    array[
      'application/pdf',
      'image/png',
      'image/jpeg',
      'text/plain'
    ]
  ),
  (
    'dars-audits',
    'dars-audits',
    false,
    12582912,
    array[
      'application/pdf',
      'image/png',
      'image/jpeg'
    ]
  )
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "transcript files are user owned" on storage.objects;
create policy "transcript files are user owned" on storage.objects
for all
using (
  bucket_id = 'transcripts'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'transcripts'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "dars files are user owned" on storage.objects;
create policy "dars files are user owned" on storage.objects
for all
using (
  bucket_id = 'dars-audits'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'dars-audits'
  and auth.uid()::text = (storage.foldername(name))[1]
);
