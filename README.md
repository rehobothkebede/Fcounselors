# Hokie Advisor

Hokie Advisor is a SwiftUI academic advising app for Virginia Tech students. It combines Supabase-backed accounts and persistence with hosted AI functions for transcript parsing, DARS import, degree audit fallback, tutoring, and advisor chat.

## Current Architecture

- iOS app: `ios/HokieAdvisor/HokieAdvisor`
- Backend fallback: FastAPI in `backend/app`
- Hosted production compute: Supabase Edge Functions in `backend/supabase/functions`
- Persistence/auth: Supabase Auth, Postgres, Storage, and RLS
- Catalog data: global read-only Supabase tables populated from local JSON under `backend/data`

The iOS app currently calls hosted Supabase Edge Functions for chat, transcript upload, DARS upload, audit, tutoring, and account deletion. The FastAPI app remains useful for local development, endpoint parity, and service checks.

## Setup

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Set local development secrets in `backend/.env`. Keep `.env` untracked and never commit real API keys.

```bash
OPENAI_API_KEY=your_openai_key
OPENAI_MODEL=gpt-5.4-nano
TRANSCRIPT_MODEL=gpt-5.4-nano
APP_ENV=development
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000,http://localhost:5173,http://127.0.0.1:5173

SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=your_public_anon_key
SUPABASE_SERVICE_ROLE_KEY=server_side_only
```

Run the local FastAPI fallback:

```bash
uvicorn app.main:app --reload
```

Local docs are available at `http://localhost:8000/docs`.

## Supabase

Project schema and function source live in `backend/supabase`.

Migration order:

1. `001_initial_schema.sql`
2. `002_auth_storage_bootstrap.sql`
3. `003_api_role_grants.sql`
4. `004_user_owned_child_integrity.sql`

`004_user_owned_child_integrity.sql` tightens child-table ownership for transcript courses, chat messages, and transcript-linked degree audits. It also adds indexes for common user-scoped restore and sync queries. Apply it to hosted Supabase only during an approved deployment window because it mutates remote constraints, indexes, and RLS policies.

The iOS app ships only the public Supabase URL and anon key. The service-role key belongs only in trusted backend or Edge Function environments.

## User Data Ownership

Student-owned records must always be tied to the authenticated Supabase user:

- `profiles`
- `transcripts`
- `transcript_courses`
- `degree_audits`
- `dars_audits`
- `chat_sessions`
- `chat_messages`
- `chat_memories`

Catalog tables are global/read-only. Reset Account deletes the Supabase Auth user through the trusted `account` Edge Function so user-owned rows can cascade through database foreign keys.

## Validation

Useful local checks:

```bash
git diff --check
PYTHONPYCACHEPREFIX=/private/tmp/hokie-pycache python3 -m py_compile backend/app/routes/admin.py backend/app/routes/advisor.py backend/app/routes/chat.py backend/app/routes/courses.py backend/app/routes/errors.py backend/app/routes/transcript.py backend/app/routes/tutoring.py backend/app/services/transcript_service.py
xcodebuild -project ios/HokieAdvisor/HokieAdvisor.xcodeproj -scheme HokieAdvisor -destination 'id=05377180-C117-461A-B1E9-5C8CC4FF10D0' -derivedDataPath /tmp/HokieAdvisorSimDerivedData CODE_SIGNING_ALLOWED=NO build
```

Do not move, rename, or delete `ios/HokieAdvisor/HokieAdvisor/Hoki.icon`; Xcode 16 discovers that Icon Composer package directly.
