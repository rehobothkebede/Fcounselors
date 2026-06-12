# Supabase Backend Setup

This folder contains the Supabase foundation for Hokie Advisor. Supabase is the
production persistence/auth/storage layer; the Python API is still needed for
trusted AI work until those endpoints are moved to hosted compute.

## Environment

Add these values to the backend environment:

```bash
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
```

The backend uses `SUPABASE_SERVICE_ROLE_KEY` for trusted server-side sync and persistence. Do not ship that key in the iOS app.

## Apply Schema

Run the migrations in order in the Supabase SQL editor, or apply them with the
Supabase CLI:

```bash
cd backend
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Migration order:

1. `migrations/001_initial_schema.sql`
2. `migrations/002_auth_storage_bootstrap.sql`
3. `migrations/003_api_role_grants.sql`

The schema includes:

- user-owned `profiles`
- uploaded `transcripts` and `transcript_courses`
- `chat_sessions`, `chat_messages`, and `chat_memories`
- saved `degree_audits` and `dars_audits`
- public read-only catalog tables for subjects, courses, COE courses, programs, requirements, and Pathways
- RLS policies for user-owned data and public catalog reads
- auth bootstrap trigger that creates/updates `profiles` from Supabase Auth metadata
- private `transcripts` and `dars-audits` storage buckets with per-user path policies

## Configure Auth

In the Supabase dashboard:

1. Enable Email authentication.
2. Decide whether to require email confirmation. If confirmation is enabled,
   first sign-up will not return an app session until the student confirms.
3. Restrict production sign-ups to VT addresses if possible. The mobile app
   already collects PID and appends `@vt.edu`, but backend/dashboard policy is
   the real guardrail.
4. Keep RLS enabled. The anon key is safe in the app only because RLS owns data
   access.

## Configure iOS

Set the public project values in:

```swift
ios/HokieAdvisor/HokieAdvisor/SupabaseService.swift
```

```swift
enum SupabaseConfig {
    static let url = "https://YOUR_PROJECT_REF.supabase.co"
    static let anonKey = "YOUR_SUPABASE_ANON_KEY"
}
```

Never place `SUPABASE_SERVICE_ROLE_KEY` in the iOS app. That key belongs only in
trusted server jobs.

When `SupabaseConfig` is blank, the app keeps using local-only auth so local
Xcode work is not blocked. Once configured, onboarding signs the student up with
Supabase Auth and stores the returned session in Keychain.

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

## Current Architecture Boundary

Supabase should own:

- user identity and profile metadata
- transcript/chat/audit persistence
- uploaded transcript and DARS files
- public catalog lookup tables

Trusted AI operations still need hosted compute because the OpenAI key cannot be
shipped to iOS:

- transcript parsing
- advisor chat streaming
- DARS image/PDF extraction
- deterministic audit fallback until it is rewritten against Supabase data

The next production step is to deploy those operations as Supabase Edge
Functions or as a hosted API, then point `APIService.baseURL` at that hosted
endpoint instead of `127.0.0.1`.
