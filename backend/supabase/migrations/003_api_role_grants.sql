-- Explicit API grants for projects created with "Automatically expose new tables" disabled.
-- RLS policies still control row-level access; these grants only allow the API roles
-- to reach the tables.

grant usage on schema public to anon, authenticated, service_role;

grant select on
  public.catalog_subjects,
  public.catalog_courses,
  public.coe_courses,
  public.catalog_programs,
  public.catalog_requirements,
  public.pathways_courses
to anon, authenticated;

grant select, insert, update, delete on
  public.profiles,
  public.transcripts,
  public.transcript_courses,
  public.chat_sessions,
  public.chat_messages,
  public.chat_memories,
  public.degree_audits,
  public.dars_audits
to authenticated;

grant select, insert, update, delete on
  public.profiles,
  public.transcripts,
  public.transcript_courses,
  public.chat_sessions,
  public.chat_messages,
  public.chat_memories,
  public.degree_audits,
  public.dars_audits,
  public.catalog_subjects,
  public.catalog_courses,
  public.coe_courses,
  public.catalog_programs,
  public.catalog_requirements,
  public.pathways_courses
to service_role;
