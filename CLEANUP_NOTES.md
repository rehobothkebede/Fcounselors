# Cleanup Notes

Last updated: June 16, 2026.

## Current App Structure

- `ios/HokieAdvisor/HokieAdvisor`: SwiftUI app source.
- `APIService.swift`: Hosted Supabase Edge Function calls for chat, transcript, DARS, audit, and tutoring.
- `SupabaseService.swift`: Supabase Auth, Keychain session storage, token refresh, and profile bootstrap.
- `UserDataSyncService.swift`: RLS-backed profile, transcript snapshot, audit snapshot, chat session/message, and memory sync.
- `AppState.swift` and `Models.swift`: shared app state and API/domain models.
- `HomeView.swift`, `ChatView.swift`, `TranscriptView.swift`, `SettingsView.swift`, `OnboardingView.swift`, `LoginView.swift`: primary screens and flows.
- `ContentView.swift`: app shell, shared Hokie UI primitives, audit/DARS rendering, markdown/math/graph rendering.
- `backend/app`: FastAPI fallback/parity backend for local development.
- `backend/supabase/functions`: hosted Edge Functions for `chat`, `account`, `transcript`, `dars`, `audit`, and `tutoring`.
- `backend/supabase/migrations`: Supabase Auth/Postgres/RLS/storage schema.

## How To Run

Open `ios/HokieAdvisor/HokieAdvisor.xcodeproj`, select the `HokieAdvisor`
scheme, and run on an iOS 18+ simulator or device.

Useful command-line build:

```bash
xcodebuild -project ios/HokieAdvisor/HokieAdvisor.xcodeproj -scheme HokieAdvisor -destination 'id=05377180-C117-461A-B1E9-5C8CC4FF10D0' -derivedDataPath /tmp/HokieAdvisorSimDerivedData CODE_SIGNING_ALLOWED=NO build
```

Run the local FastAPI fallback from `backend` only when needed:

```bash
uvicorn app.main:app --reload
```

## Required Environment

Local backend development expects untracked `backend/.env` values:

```bash
OPENAI_API_KEY=
OPENAI_MODEL=gpt-5.4-nano
TRANSCRIPT_MODEL=gpt-5.4-nano
APP_ENV=development
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000,http://localhost:5173,http://127.0.0.1:5173
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
```

The iOS app may ship the public Supabase URL and anon key. Do not put
`SUPABASE_SERVICE_ROLE_KEY` or `OPENAI_API_KEY` in iOS source.

## Expected Supabase Surface

Tables expected by the app and hosted functions:

- User-owned: `profiles`, `transcripts`, `transcript_courses`, `degree_audits`, `dars_audits`, `chat_sessions`, `chat_messages`, `chat_memories`.
- Global read-only catalog: `catalog_subjects`, `catalog_courses`, `catalog_programs`, `catalog_requirements`, `pathways_courses`, `coe_courses`.

Edge Functions expected by iOS:

- `chat`
- `account`
- `transcript`
- `dars`
- `audit`
- `tutoring`

Important Auth setting:

- Supabase Dashboard additional redirect URL must include `hokieadvisor://auth/callback`.

## Cleaned In This Pass

- Removed tracked `backend/supabase/.temp/*` Supabase CLI local state from source control and added it to `.gitignore`.
- Removed the stale `AccentColor` build setting so Xcode no longer points at a missing global accent color asset.
- Lowered `IPHONEOS_DEPLOYMENT_TARGET` from accidental `26.4` to `18.0`.
- Updated stale `Fcounselors` text in local backend helper scripts.
- Changed hosted `chat` and `account` function failures to log provider/admin details server-side while returning stable, non-sensitive client errors.
- Extended the iOS Supabase error decoder to read both string and coded `detail` error payloads.
- Renamed the Settings destructive action from "Clear Transcript Data" to "Clear Local Data" to match what it actually clears.
- Parsed structured error payloads for streamed chat failures and made generic API failure text feature-neutral.
- Routed account deletion through the validated/refreshed Supabase session path before calling the remote account function.
- Made the transcript import subtitle major-neutral.
- Split authenticated restore state so chat sync and student snapshot restore are tracked separately. Transcript/audit/DARS state is only cleared when Supabase successfully returns "no row"; failed subqueries preserve the current local state and can be retried.

## Remaining Work

- Apply `backend/supabase/migrations/004_user_owned_child_integrity.sql` to hosted Supabase after explicit approval. It tightens child row ownership and adds restore/sync indexes.
- Run real-device signed-in QA for profile edits, transcript restore, DARS/audit restore, chat history/memory sync, sign-out, reset account, and account recreation.
- Test DARS parsing with a real official export or screenshot and tune extraction.
- Decide whether iOS 17 support is required. Current code uses iOS 18 scroll geometry APIs.
- Split the large `ContentView.swift` into feature/UI files after the current UX stabilizes.
- Add approved statistics elective and CS theory elective data to the audit catalog.
