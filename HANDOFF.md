# Hokie Advisor Project Handoff

Last updated: August 1, 2026.

This document is the current engineering handoff for Hokie Advisor. It describes
the product as it exists in the repository today. It is not a session log, an AI
conversation transcript, or a list of historical ownership boundaries.

## Collaboration Status

Hokie Advisor is no longer a two-agent project. Claude is not part of the active
development workflow, and there is no Claude/Codex split or separate file
ownership model. All files should be treated as one shared codebase maintained
through the normal repository workflow.

Claude was previously used for selected early iOS work. Its main contributions
included:

- GPA and home-dashboard polish, haptics, profile presentation, and transcript
  sheet usability
- semester-aware transcript state and the planned-course UI
- the first local chat-history/session store and related chat-history screens

Those contributions remain ordinary project code. Claude-specific task queues,
handoff instructions, ownership lists, and the former double-agent workflow are
discontinued.

## Project Summary

Hokie Advisor is an independent SwiftUI app for Virginia Tech students. It
combines transcript-aware academic planning, a Computer Science B.S. degree
audit, official DARS/uAchieve import, AI advisor chat, tutoring guidance, and
Supabase-backed account persistence.

Current application facts:

- Platform: iOS 18.0+
- UI framework: SwiftUI
- App version: 1.0 (build 1)
- Bundle identifier: `com.hokieadvisor.HokieAdvisor`
- Xcode project: `ios/HokieAdvisor/HokieAdvisor.xcodeproj`
- Main tabs: Home, Audit, Advisor, and Profile
- Production services: Supabase Auth, Postgres, Storage, and Edge Functions
- AI provider: OpenAI, called only from trusted backend or Edge Function code
- Local backend: FastAPI parity/fallback implementation under `backend/app`

The iOS app uses hosted Supabase Edge Functions for its active chat, transcript,
DARS, audit, tutoring, and account-deletion flows. The FastAPI application is
kept for local development, endpoint parity, and service diagnostics.

## Current Product Capabilities

### Authentication and onboarding

- Email/password sign-up and sign-in through Supabase Auth
- VT PID input can be normalized to a `@vt.edu` address in the UI
- Email-confirmation deep-link handling through
  `hokieadvisor://auth/callback`
- Access and refresh sessions stored in the iOS Keychain
- Session validation and refresh before authenticated API or data-sync work
- Post-auth onboarding for name, VT PID/email, discovery source, appearance,
  and optional transcript import
- Profile bootstrap and later profile updates through user-scoped Supabase rows

### Home

- Personalized student header
- Credits, calculated GPA, completed-course count, and graduation-year cards
- Direct navigation to Audit and Advisor
- Transcript-import prompt when academic data has not been loaded
- Academic progress and tutoring-support indicators
- Static Virginia Tech planning tips

GPA is calculated from recognized letter grades on a 4.0 scale. Transfer,
pass/fail, and other non-GPA grades are excluded from the GPA calculation.

### Transcript workflow

- Import PDF, PNG, or JPEG transcript files
- Hosted AI extraction into completed, in-progress, and planned courses
- Course-code, grade, credit, semester, and title normalization
- Transfer and awarded-credit handling for `T`, `TR`, `P`, and `CR`-style grades
- Semester-aware separation of active and future registered courses
- Manual in-progress grade/status tracking for tutoring recommendations
- Transcript display grouped by semester
- Automatic graduation-year inference when usable semester data is present
- Parser notes retained as advisor context without cluttering the transcript UI
- Authenticated transcript state restored from Supabase on later launches

### Degree audit and DARS

- Deterministic Computer Science B.S. audit from the imported transcript
- Audit summary with completion percentage, credits, buckets, matched courses,
  remaining requirements, and warnings
- Virginia Tech grade semantics, including the distinction between `C` and
  `C-` for requirements that require a C or better
- Pathways, required-course, science, writing, elective, and total-credit
  buckets
- Official DARS/uAchieve PDF, PNG, or JPEG import
- DARS category summaries, status bars, requirement sections, and warnings
- Cached degree-audit and DARS results restored for authenticated users
- Tutoring-resource sheet when the student marks active courses as struggling

The deterministic audit currently supports Computer Science B.S. only. An
imported official DARS report is treated as the stronger source of truth when
available.

### Advisor and tutoring

- Streaming advisor responses over server-sent events
- Transcript, in-progress course, parser-note, major, and saved-memory context
- Academic planning plus tutoring support for CS, algorithms, graph theory,
  calculus, linear algebra, proofs, and related topics
- Native Markdown presentation
- Syntax-highlighted fenced code blocks
- Lightweight LaTeX-style inline and display math
- Native matrix, cases, and simple graph-diagram rendering
- YouTube links promoted into resource cards
- Saved chat sessions with resume, new-chat, and delete controls
- User-editable chat memories and automatic capture of selected recurring
  preferences
- Per-user local chat caches synchronized to Supabase when authenticated
- Camera, photo, and file attachment selection UI

Attachment selection is currently UI-only. The selected file name and size are
added as text context, but the attachment bytes are not sent to the advisor for
analysis. The microphone button is also a placeholder and does not yet perform
voice transcription.

### Profile and settings

- Editable name and graduation year
- System, light, and dark appearance modes
- Transcript import and transcript status
- Saved-chat and saved-memory counts
- Chat-memory editor
- Terms of Service and Privacy Policy sheets
- Sign out without deleting the authenticated user's remote account
- Clear Local Data for device-side state and caches
- Reset Account & Restart, which requests remote account deletion before
  clearing local state
- Debounced authenticated profile writeback to Supabase

### Visual system and QA support

- Virginia Tech burgundy/orange visual language
- Shared glass surfaces, page headers, compact scroll titles, icon tiles, pills,
  and a floating tab bar
- Keyboard-aware layouts and swipe-to-dismiss behavior
- Reduced-motion-aware chat animations
- Debug visual-QA launch mode with `-HokieVisualQA`
- Debug initial-tab selection with
  `-HokieInitialTab home|audit|advisor|profile`

## Architecture

| Layer | Responsibility |
|---|---|
| SwiftUI app | Authentication screens, onboarding, student UI, local state, file selection, and API orchestration |
| Supabase Auth | User identity, sign-up/sign-in, access tokens, refresh tokens, and email-confirmation callbacks |
| Supabase Postgres | Profiles, transcript data, audits, chat sessions/messages, memories, and public catalog tables |
| Supabase Storage | Private transcript and DARS upload buckets with user-scoped policies |
| Supabase Edge Functions | Hosted chat, transcript parsing, DARS parsing, audit, tutoring, and account deletion |
| OpenAI | Advisor responses and document extraction invoked from trusted server-side code |
| FastAPI | Local development fallback and parity endpoints |
| Local iOS storage | Keychain sessions, AppStorage preferences, and per-user chat/memory caches |

Primary data flow:

```text
iOS app
  ├─ Supabase Auth ──> validated user session in Keychain
  ├─ Supabase REST ──> RLS-protected profile, transcript, audit, and chat data
  └─ Edge Functions
       ├─ chat ──────> OpenAI streaming response
       ├─ transcript > OpenAI document extraction
       ├─ dars ─────> OpenAI document extraction
       ├─ audit ────> deterministic CS audit and catalog lookup
       ├─ tutoring ─> academic support resources
       └─ account ──> authenticated account deletion
```

## Backend Surface

### Supabase Edge Functions used by iOS

| Function | Purpose |
|---|---|
| `chat` | JSON and streaming advisor responses |
| `transcript` | Transcript PDF/image extraction and optional persistence |
| `dars` | Official DARS/uAchieve extraction and optional persistence |
| `audit` | Deterministic Computer Science B.S. audit |
| `tutoring` | Academic-support recommendations |
| `account` | Authenticated remote account deletion |

### FastAPI parity and development routes

- `GET /` and `GET /health`
- `POST /chat` and `POST /chat/stream`
- `POST /transcript/upload`
- `POST /advisor/plan`
- `POST /advisor/audit`
- `POST /advisor/dars/upload`
- `POST /tutoring/recommend`
- Course metadata, subject, program, requirement, and search routes under
  `/courses`
- Administrative catalog seed/status and Supabase status routes under `/admin`

The legacy `/advisor/plan` route does not currently have a dedicated active iOS
planning screen.

## Data Model

User-owned Supabase tables:

- `profiles`
- `transcripts`
- `transcript_courses`
- `degree_audits`
- `dars_audits`
- `chat_sessions`
- `chat_messages`
- `chat_memories`

Public read-only catalog tables:

- `catalog_subjects`
- `catalog_courses`
- `coe_courses`
- `catalog_programs`
- `catalog_requirements`
- `pathways_courses`

Storage buckets:

- `transcripts`
- `dars-audits`

Both buckets are intended to remain private and user-scoped. Row-level security
must remain enabled for every user-owned table.

Migration order:

1. `backend/supabase/migrations/001_initial_schema.sql`
2. `backend/supabase/migrations/002_auth_storage_bootstrap.sql`
3. `backend/supabase/migrations/003_api_role_grants.sql`
4. `backend/supabase/migrations/004_user_owned_child_integrity.sql`

Source control proves that these migrations exist; it does not prove that every
hosted environment has applied them. Confirm hosted migration state before a
release or schema-dependent test.

## Important Files

### iOS application

- `HokieAdvisorApp.swift`: app lifecycle, auth restoration, deep links, remote
  student-state restoration, and visual-QA seeding
- `AppState.swift`: shared transcript, semester, GPA, tutoring, and audit state
- `Models.swift`: request, response, transcript, audit, DARS, chat, and tutoring
  models
- `APIService.swift`: hosted Edge Function calls and chat streaming
- `SupabaseService.swift`: public client configuration, auth, session refresh,
  Keychain persistence, and profile bootstrap
- `UserDataSyncService.swift`: authenticated profile, transcript, audit, DARS,
  chat, and memory REST synchronization
- `ContentView.swift`: app shell, tab bar, audit/DARS UI, shared visual
  components, Markdown, graph, and math rendering
- `HomeView.swift`: dashboard and quick actions
- `ChatView.swift` / `ChatViewModel.swift`: advisor UI, streaming state, history,
  and attachment placeholders
- `ChatHistoryStore.swift`: local and remote chat-session/memory persistence
- `TranscriptView.swift` / `TranscriptViewModel.swift`: transcript import and
  academic-record presentation
- `LoginView.swift` / `OnboardingView.swift`: authentication and first-run setup
- `SettingsView.swift`: profile, appearance, memories, legal copy, sign-out, and
  data-reset actions
- `CodeBlockView.swift`: native code-block presentation and highlighting
- `KeyboardDismissal.swift`: shared keyboard behavior
- `Hoki.icon`: Xcode Icon Composer asset; keep its package structure intact

### Backend and data

- `backend/app/main.py`: FastAPI application and route registration
- `backend/app/routes/`: local API surface
- `backend/app/services/ai_service.py`: local advisor prompt and OpenAI access
- `backend/app/services/transcript_service.py`: local transcript extraction
- `backend/app/services/dars_audit_service.py`: local DARS extraction
- `backend/app/services/degree_audit_service.py`: deterministic CS audit
- `backend/app/services/supabase_service.py`: trusted REST client
- `backend/app/services/supabase_catalog_sync.py`: catalog transformation/sync
- `backend/supabase/functions/`: hosted production functions
- `backend/supabase/migrations/`: database, RLS, grant, storage, and ownership
  migrations
- `backend/data/catalog/`: advising guides and structured CS catalog data
- `backend/data/coe/`: College of Engineering course data
- `backend/data/pathways.json`: Pathways course data

## Local Development

### iOS

Requirements:

- macOS with Xcode 16 or newer
- An iOS 18 simulator or device

Open `ios/HokieAdvisor/HokieAdvisor.xcodeproj`, choose the `HokieAdvisor` scheme,
and run it.

Command-line simulator build:

```bash
xcodebuild \
  -project ios/HokieAdvisor/HokieAdvisor.xcodeproj \
  -scheme HokieAdvisor \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### FastAPI fallback

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload
```

Local API documentation is available at `http://localhost:8000/docs` while the
server is running.

Required local environment variables are documented in `backend/.env.example`.
The important values are:

- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `TRANSCRIPT_MODEL`
- `APP_ENV`
- `CORS_ALLOWED_ORIGINS`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

Never place `OPENAI_API_KEY` or `SUPABASE_SERVICE_ROLE_KEY` in iOS source. The
Supabase URL and anonymous client key are public client configuration and are
safe only when RLS and function authorization are correctly configured.

## Validation

Minimum checks after a change:

```bash
git diff --check

PYTHONPYCACHEPREFIX=/private/tmp/hokie-advisor-pycache \
python3 -m py_compile \
  backend/app/main.py \
  backend/app/routes/*.py \
  backend/app/services/*.py

xcodebuild \
  -project ios/HokieAdvisor/HokieAdvisor.xcodeproj \
  -scheme HokieAdvisor \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Useful manual checks:

- Cold launch with no session
- Sign up, confirmation deep link, and sign in
- Authenticated relaunch and token refresh
- Transcript upload with PDF and image inputs
- Completed, active, and planned course grouping
- Deterministic audit refresh and DARS import
- Streaming chat, chat history, and memory sync
- Sign out, Clear Local Data, and Reset Account
- Light, dark, keyboard, and reduced-motion states
- Real-device file, photo, camera, and Keychain behavior

There is no comprehensive automated iOS test suite or CI workflow in the
repository yet. `backend/test_api.py` is a development-oriented API script, not
a complete regression suite.

## Security and Privacy Requirements

- Keep all `.env` files untracked.
- Keep the OpenAI key and Supabase service-role key server-side only.
- Treat transcript and DARS files as sensitive student records.
- Keep user-owned database tables and storage paths protected by RLS.
- Require a verified user identity for operations that read or persist user
  data.
- Add authentication enforcement and/or abuse controls to costly AI functions
  before broad public use. The current function configuration permits anonymous
  flows for several endpoints.
- Confirm migration `004_user_owned_child_integrity.sql` is applied in hosted
  environments before relying on its parent/child ownership guarantees.
- Replace personal-looking values in DEBUG visual-QA fixtures with clearly
  fictional sample data.
- Before treating the repository as clean for public distribution, remove the
  historical personal transcript from Git history and complete the associated
  repository-history cleanup.
- Verify redistribution rights for bundled third-party advising PDFs and
  catalog datasets.

## Known Limitations

- The deterministic degree audit supports Computer Science B.S. only.
- Approved course lists for the statistics elective and CS theory elective are
  not encoded, so those buckets cannot be resolved automatically.
- DARS accuracy still needs testing against a wider set of official exports and
  screenshots.
- Official CollegeSource/uAchieve API integration is not implemented.
- Chat attachments are not transmitted for model analysis.
- Voice input is not implemented.
- The native LaTeX renderer supports common tutoring notation but is not a full
  TeX engine.
- Multi-major and non-CS advising require additional catalog and audit logic.
- The app has legal/privacy copy, but policy, retention, consent, and production
  compliance still require owner review before a public launch.
- `ContentView.swift` contains several large UI and rendering systems and should
  eventually be split into focused feature files.
- Hosted deployment, secret, redirect, and migration state must be verified in
  the actual Supabase project; repository files alone are not proof of remote
  configuration.

## Recommended Priorities

### Priority 0: privacy and service protection

1. Purge the historical personal transcript and other private workspace
   artifacts from public Git history.
2. Confirm exposed or previously displayed API credentials have been rotated.
3. Require authenticated users or implement strong rate limits/quotas for AI
   endpoints that can consume paid resources.
4. Apply and verify migration `004` in the hosted database.
5. Replace DEBUG sample identity values with fictional fixtures.

### Priority 1: correctness and release readiness

1. Add approved statistics and CS theory elective data.
2. Test transcript and DARS parsing with multiple real, properly protected
   document formats.
3. Verify Supabase email-confirmation and mobile redirect behavior.
4. Run signed-in lifecycle testing on a physical iPhone.
5. Add repeatable backend tests, iOS tests, and CI checks.

### Priority 2: product expansion

1. Connect chat attachment bytes to an approved multimodal analysis path.
2. Implement voice transcription or remove the placeholder control.
3. Add non-CS majors and multi-major audit support.
4. Decide whether to expose a dedicated course-plan UI for the existing plan
   route.
5. Split large SwiftUI files into feature-focused modules.

## Handoff Maintenance Rules

- Keep this file focused on current behavior and actionable next work.
- Do not restore the former Claude/Codex ownership split.
- Do not append raw session transcripts, prompt history, local machine paths,
  simulator identifiers, live project identifiers, credentials, or test-account
  details.
- Update the relevant current-state section when architecture or behavior
  changes instead of adding another chronological session entry.
- Verify claims against source before marking a capability complete.
- Keep `README.md`, `backend/supabase/README.md`, and this document aligned when
  the production architecture changes.
