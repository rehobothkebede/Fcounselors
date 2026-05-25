# Supabase Backend Setup

This folder contains the Supabase foundation for Hokie Advisor.

## Environment

Add these values to the backend environment:

```bash
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
```

The backend uses `SUPABASE_SERVICE_ROLE_KEY` for trusted server-side sync and persistence. Do not ship that key in the iOS app.

## Apply Schema

Run `migrations/001_initial_schema.sql` in the Supabase SQL editor, or apply it with the Supabase CLI:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

The schema includes:

- user-owned `profiles`
- uploaded `transcripts` and `transcript_courses`
- `chat_sessions`, `chat_messages`, and `chat_memories`
- saved `degree_audits` and `dars_audits`
- public read-only catalog tables for subjects, courses, COE courses, programs, requirements, and Pathways
- RLS policies for user-owned data and public catalog reads

## Sync Existing Catalog Data

After the migration is applied:

```bash
cd backend
python scripts/sync_catalog_to_supabase.py
```

This syncs the existing local JSON data under `backend/data/` into:

- `catalog_subjects`
- `catalog_courses`
- `catalog_programs`
- `catalog_requirements`
- `pathways_courses`
- `coe_courses`

## Health Check

Start the API and call:

```bash
GET /health
GET /admin/supabase/status
```

`/admin/supabase/status` verifies that the backend can reach the Supabase REST API and that the catalog schema exists.
