-- Tighten user-owned child records so callers cannot attach their own rows to
-- another user's parent transcript or chat session by guessing a UUID.

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'transcripts_id_user_id_key'
  ) then
    alter table public.transcripts
      add constraint transcripts_id_user_id_key unique (id, user_id);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'chat_sessions_id_user_id_key'
  ) then
    alter table public.chat_sessions
      add constraint chat_sessions_id_user_id_key unique (id, user_id);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'transcript_courses_transcript_owner_fkey'
  ) then
    alter table public.transcript_courses
      add constraint transcript_courses_transcript_owner_fkey
      foreign key (transcript_id, user_id)
      references public.transcripts (id, user_id)
      on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'chat_messages_session_owner_fkey'
  ) then
    alter table public.chat_messages
      add constraint chat_messages_session_owner_fkey
      foreign key (session_id, user_id)
      references public.chat_sessions (id, user_id)
      on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'degree_audits_transcript_owner_fkey'
  ) then
    alter table public.degree_audits
      add constraint degree_audits_transcript_owner_fkey
      foreign key (transcript_id, user_id)
      references public.transcripts (id, user_id)
      on delete set null (transcript_id);
  end if;
end $$;

create index if not exists idx_transcripts_user_created
  on public.transcripts (user_id, created_at desc);

create index if not exists idx_chat_sessions_user_updated
  on public.chat_sessions (user_id, updated_at desc);

create index if not exists idx_chat_memories_user_updated
  on public.chat_memories (user_id, updated_at desc);

create index if not exists idx_chat_messages_user_session_position
  on public.chat_messages (user_id, session_id, position);

create index if not exists idx_degree_audits_user_created
  on public.degree_audits (user_id, created_at desc);

create index if not exists idx_dars_audits_user_created
  on public.dars_audits (user_id, created_at desc);

drop policy if exists "transcript courses are user owned" on public.transcript_courses;
create policy "transcript courses are user owned" on public.transcript_courses
for all
using (
  auth.uid() = user_id
  and exists (
    select 1
    from public.transcripts
    where transcripts.id = transcript_courses.transcript_id
      and transcripts.user_id = auth.uid()
  )
)
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.transcripts
    where transcripts.id = transcript_courses.transcript_id
      and transcripts.user_id = auth.uid()
  )
);

drop policy if exists "chat messages are user owned" on public.chat_messages;
create policy "chat messages are user owned" on public.chat_messages
for all
using (
  auth.uid() = user_id
  and exists (
    select 1
    from public.chat_sessions
    where chat_sessions.id = chat_messages.session_id
      and chat_sessions.user_id = auth.uid()
  )
)
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.chat_sessions
    where chat_sessions.id = chat_messages.session_id
      and chat_sessions.user_id = auth.uid()
  )
);

drop policy if exists "degree audits are user owned" on public.degree_audits;
create policy "degree audits are user owned" on public.degree_audits
for all
using (
  auth.uid() = user_id
  and (
    transcript_id is null
    or exists (
      select 1
      from public.transcripts
      where transcripts.id = degree_audits.transcript_id
        and transcripts.user_id = auth.uid()
    )
  )
)
with check (
  auth.uid() = user_id
  and (
    transcript_id is null
    or exists (
      select 1
      from public.transcripts
      where transcripts.id = degree_audits.transcript_id
        and transcripts.user_id = auth.uid()
    )
  )
);
