## Current State

App builds in Xcode. Chat/account plus hosted replacements for transcript upload, DARS upload, degree audit, and tutoring now exist as Supabase Edge Functions. The old FastAPI server can remain a local/dev fallback, but iOS no longer points transcript/DARS/audit/tutoring at port 8000. Supabase function secrets have been refreshed from `backend/.env`, and hosted transcript/DARS parsing now works against synthetic PDF uploads with no local server.

**What's fully working end-to-end:**
- Transcript import → AI parse → AppState population → GPA/credits/courses displayed
- Chat streaming (SSE) with transcript context, VT grade rules, saved chat memory, native code/math/graph rendering, and YouTube resource cards
- Degree Audit: backend `POST /advisor/audit` returns full bucket breakdown; frontend `DegreeAuditView` renders it
- Backend now treats transfer/awarded credit grades (`T`, `TR`, `TRANSFER`, `P`, `CR`) as completed awarded credit for audit/chat purposes. Example: `CS 1114` with grade `T` satisfies the CS 1114 requirement.
- Backend has a new official-audit ingestion path: `POST /advisor/dars/upload` parses a uAchieve/DARS PDF or screenshot into DARS-shaped categories (`University GPA`, `Minimum Hours`, `Major`, `General Ed`, `In Major GPA`, `Electives`, `Minor(s)`).
- Frontend now has a DARS-first Audit tab flow: Swift DARS models, `APIService.uploadDarsAudit`, PDF/PNG/JPG file import, official DARS summary cards, category status bars, section cards, and backend-error handling.
- Transcript parser warnings/notes are no longer shown in TranscriptView, but are preserved in `AppState.transcriptNotes` and sent to chat as private LLM context.
- Supabase is now the live auth/storage backend for the app. The iOS app has the hosted project URL/anon key, Supabase Auth signup/signin, profile upsert, email-confirmation deep link handling, and Keychain session storage.
- Supabase Edge Functions are deployed for chat (`chat`) and account deletion/reset (`account`). The `account` function deletes the authenticated Supabase Auth user with the service-role key server-side, causing user-owned `profiles` rows to cascade-delete.
- Supabase catalog sync has been fixed for the current local data shapes and run against the hosted project. Last confirmed sync counts: `catalog_subjects: 7`, `catalog_courses: 541`, `pathways_courses: 1134`, `coe_courses: 757`.
- A Hokie-specific visual system is now in progress across the iOS app: shared glass surfaces, `HokiePageHeader`, `HokieCompactPill`, `HokieIconTile`, VT burgundy/orange accents, a lowered floating tab bar, and non-Apple-style page headers for Home/Audit/Advisor/Profile.
- Advisor chat composer is now ChatGPT-like but Hokie-styled: plus menu for Camera/Photos/Files, mic placeholder, burgundy send state, lowered glass composer, keyboard-aware scroll spacing, and the final example prompt remains visible above the composer/footer.
- Empty Advisor no longer auto-scrolls to the bottom on tab entry/swipe. It resets to the top so the Advisor header is visible, and only scrolls the empty-state prompts down when the Advisor input is focused and the keyboard is visible.
- The resting Advisor composer has extra separation from the floating footer (`chatComposerRestingBottom = 71`) so the Ask bubble no longer looks glued to the tab bar.
- Login/sign-up now use conventional account tabs and keyboard-aware scrolling so the action button is not blocked by the keyboard.
- Visual QA mode exists for simulator screenshots: launch with `-HokieVisualQA -HokieInitialTab home|audit|advisor|profile`. The Audit tab uses a DEBUG-only sample audit in this mode so visual QA is not blocked by a local backend connection error.
- Latest simulator build command succeeded with `xcodebuild -project ios/HokieAdvisor/HokieAdvisor.xcodeproj -scheme HokieAdvisor -destination 'id=05377180-C117-461A-B1E9-5C8CC4FF10D0' -derivedDataPath /tmp/HokieAdvisorSimDerivedData CODE_SIGNING_ALLOWED=NO build`.
- Supabase Edge Functions `transcript`, `dars`, `audit`, and `tutoring` were added and deployed to project `gcmwrrrspkgawiwisunq`. `audit`, `tutoring`, `transcript`, and `dars` smoke tests pass with synthetic data, and transcript/DARS reject non-matching files with safe coded 422 errors.
- Production hardening is in progress. Supabase now has a pending idempotent migration (`004_user_owned_child_integrity.sql`) to enforce same-user parent/child ownership for `transcript_courses`→`transcripts`, `chat_messages`→`chat_sessions`, and transcript-linked `degree_audits`→`transcripts` at the database constraint/RLS level. It also adds user/time indexes for restore and sync queries. iOS chat sessions and chat memories now use per-Supabase-user local cache files and sync to the user-owned Supabase tables when authenticated. Hosted function calls, profile writes, and chat sync now use validated Supabase sessions, and the auth service refreshes expired access tokens with the stored refresh token. On authenticated restore, iOS also rehydrates profile/settings, latest transcript/courses/planned courses, and cached audit/DARS responses from the signed-in user's Supabase rows.

**Known gaps / open work:**
- Statistics elective + CS theory elective approved course lists not in catalog data yet — those two audit buckets stay "open" until data is added
- `TranscriptView` subtitle still says "CS course history" — should be major-agnostic once multi-major support lands
- LaTeX rendering in chat now has lightweight native support for inline `$...$`, `\(...\)`, display `$$...$$`, `\[...\]`, and common matrix environments. It is not a full TeX engine.
- Official CollegeSource/uAchieve API access is still unsolved and likely needs school support. The frontend is ready for the existing `/advisor/dars/upload` contract, but the backend/source integration still needs to become reliable.
- Supabase email confirmation must use the mobile redirect `hokieadvisor://auth/callback`. The app has the iOS URL scheme registered in `ios/HokieAdvisor/Info.plist`, but the Supabase Dashboard URL Configuration must also allow that redirect. Old confirmation emails may still point to `localhost:3000`; resend confirmation after changing dashboard settings.
- The Python API/local server is no longer used by iOS for transcript/DARS/audit/tutoring calls, but it remains useful as a local/dev fallback. Hosted transcript/DARS extraction now uses Supabase function secrets only.
- Root `README.md` and `backend/supabase/README.md` have been refreshed for the Hokie Advisor/Supabase hosted architecture, user-owned data model, pending migration `004`, and current validation commands. Settings legal/privacy copy has been refreshed to mention backend, Supabase, and OpenAI-powered processing.
- Root `.env` is ignored by Git but exists locally with a real OpenAI key; rotate/remove it before sharing the machine or using this repo in demos. Tracked `.DS_Store` files have been removed from the working tree/staged deletion; keep them out of future commits.
- `IPHONEOS_DEPLOYMENT_TARGET` in the Xcode project is currently `26.4`, while older notes say iOS 17+. If iOS 17 support is intended, lower the deployment target.
- Swift builds currently succeed. The chat model actor-isolation warnings introduced during user-data sync were cleaned by marking value-only chat models `nonisolated`; keep watching Swift 6 warnings as the project moves toward Swift 6 language mode.
- Remaining user-data gap: the new local migration has not been applied to hosted Supabase yet because that remote schema/RLS mutation needs explicit user approval. Profile/settings edits now write back to the authenticated user's Supabase `profiles` row from Settings, but that should still be tested on a real signed-in device/session.
- The broad UX revamp goal is still active, not proven complete. Recent screenshots verified Audit/Profile/Advisor improvements, but a final pass should still inspect every main tab, sheets, keyboard states, light/dark mode, and navigation transitions before declaring the redesign done.

---

## App Icon — Final Working Setup

The app icon is an **Xcode 16 Icon Composer** package named `Hoki.icon`, located at:

```
ios/HokieAdvisor/HokieAdvisor/Hoki.icon/
  icon.json
  Assets/
    AppIcon-Light.png
    AppIcon-Dark.png
```

**Do not move, rename, or delete `Hoki.icon`.** Xcode 16 `PBXFileSystemSynchronizedRootGroup` picks it up automatically.

If Xcode complains about Assets.xcassets: recreate a minimal `Assets.xcassets/Contents.json` with `{"info":{"author":"xcode","version":1}}`.

---

## What Changed Across All Sessions

### Sessions 1–5 (summary)
| Area | What was built |
|---|---|
| Project rename | Fcounselors → Hokie Advisor; bundle ID `com.hokieadvisor.HokieAdvisor` |
| Onboarding | 7-step flow: Welcome → Name → VT PID email → Password → How Heard → Appearance → Transcript → Done |
| Login screen | Password screen with shake animation on wrong entry |
| Chat streaming | `POST /chat/stream` SSE + iOS `URLSession.bytes` + live token-by-token rendering |
| Code blocks | `CodeBlockView.swift` with VS Code Dark+ syntax highlighting (8 languages) |
| Transcript-aware chat | Backend injects CS requirements + annotated transcript per request |
| VT grade rules | C- (1.7) does NOT satisfy "C or better"; enforced in backend system prompt and audit service |

### Session 6 — UX Polish (Claude)
| Change | Detail |
|---|---|
| **GPA calculation** | `AppState.calculatedGPA: Double?` — weighted GPA, VT 4.0 scale, P/CR/TR excluded |
| **Home stats → 2×2 grid** | Credits, GPA, Courses, Grad Year in a `LazyVGrid`. GPA colored green/blue/orange/red |
| **Time-of-day greeting** | "Good morning/afternoon/evening, [name]" based on system clock |
| **Grad year sync fix** | Stat shows whenever `@AppStorage("graduationYear")` is non-empty — no transcript required |
| **Haptics** | Tab bar: `.sensoryFeedback(.selection)`. Buttons: `UIImpactFeedbackGenerator(.medium)` |
| **Dynamic chat chips** | Suggestion chips use `appState.major` instead of hardcoded CS strings |
| **Profile card** | Dynamic badges: Virginia Tech → Major → 'YY → PID. GPA inline. Hardcoded "CS '26" removed |
| **GPA in transcript banner** | Calculated GPA shown on right side of success banner |
| **TranscriptView dismiss** | Added `@Environment(\.dismiss)` + ✕ button in header — user can always exit the sheet |
| **Shared `gpaColor` helper** | Top-level func in ContentView.swift — green ≥3.7, blue ≥3.0, orange ≥2.0, red <2.0 |

### Session 6 — Degree Audit System (Codex)
| Change | Detail |
|---|---|
| **`degree_audit_service.py`** | Deterministic CS B.S. audit. Reads `computer_science.json` + `pathways.json`. Returns bucket array with `status: complete/in_progress/incomplete/attention`. |
| **`POST /advisor/audit`** | New endpoint in `advisor.py`. Accepts `DegreeAuditRequest`, returns `DegreeAuditResponse`. |
| **Bucket types built** | Required courses (per 4-year plan), Natural Science (8cr), Advanced Natural Science (4cr), Comms (1 course), Professional Writing (1 course), CS 3/4/5xxx electives (6+3+3cr), Pathways 1F/1A/2/3/4/5F/5A/6A/6D/7(suspended), Free Electives, Total Credits |
| **`DegreeAuditViewModel`** | In `PlanViewModel.swift`. Calls `APIService.fetchDegreeAudit`. Auto-runs when transcript changes via `.task(id: auditRefreshKey)` |
| **`DegreeAuditView`** | In `ContentView.swift`. Shows `AuditSummaryCard` (% complete, progress bar, credits/buckets metrics) + bucketed sections (Needs Attention, Remaining, Completed). Refresh button. |
| **`AuditSummaryCard` + `AuditBucketCard`** | In `ContentView.swift`. Summary: percent, progress bar, credits/bucket counts. BucketCard: status icon, credits, matched courses, missing items, first note. |
| **Tab renamed** | FloatingTabBar tab 1: icon `checklist.checked`, label "Audit" |
| **ContentView switch** | `case 1: DegreeAuditView()` |

### Session 7 — Transcript/Audit Backend Fixes (Codex)
| Change | Detail |
|---|---|
| **Transfer credit counts correctly** | `degree_audit_service.py` now treats `T`, `TR`, `TRANSFER`, `P`, `PASS`, `CR`, and `CREDIT` as awarded credit. These grades satisfy degree requirements when attached to exact VT course codes, including C-or-better buckets such as `CS 1114`. |
| **Chat transcript context fixed** | `ai_service._build_student_context()` now labels transfer/awarded credit as satisfying requirements instead of leaving it as still needed. Total completed credits also count transfer/awarded credit. |
| **Transcript parser contract expanded** | `transcript_service.py` now asks the extraction model for `planned_courses` in addition to `courses` and `in_progress_courses`. Future no-grade/registered courses should go to `planned_courses`. |
| **Future-course postprocess** | Backend postprocessing moves any no-grade `in_progress_courses` whose semester has not started yet into `planned_courses` and adds a warning. Start heuristic: Spring=Jan, Summer=May, Fall=Aug. |
| **Transcript upload response expanded** | `POST /transcript/upload` now returns `planned_courses: [{code, name, credits, semester}]`. Existing Swift decoders ignore the extra field until Claude wires it into the frontend. |
| **Grade normalization** | Parser postprocess normalizes transfer grades to `T`, `PASS` to `P`, `CREDIT` to `CR`, and normalizes course codes to `SUBJ NNNN`. |

### Session 7 — Semester-Awareness Frontend (Claude)
| Change | Detail |
|---|---|
| **`AppState.plannedCourses`** | Renamed from `upcomingCourses`. Populated from `planned_courses[]` in transcript response — field name now matches backend. |
| **`TranscriptResponse.planned_courses`** | `Models.swift` field renamed `upcoming_courses` → `planned_courses` to match backend contract. |
| **Semester-awareness in AppState** | `currentVTSemester`, `isSemesterInSession`, `activeSemesterCourses`, `registeredUpcomingCourses`, semester-aware `inProgressSummary`. Spring: Jan 15–May 10; Summer: May 20–Aug 10; Fall: Aug 25–Dec 14. |
| **TranscriptView semester UI** | `inProgressSection` now uses `activeSemesterCourses` (grade buttons only for current semester). New `plannedCoursesSection` shows `registeredUpcomingCourses` without grade buttons. `semesterStatusSection` guarded behind `isSemesterInSession`. |
| **SettingsView clear actions** | Both "Clear All Data" and "Reset Account" now also clear `appState.plannedCourses`. |

### Session 8 — Official DARS/uAchieve Ingestion (Codex)
| Change | Detail |
|---|---|
| **Correct audit source identified** | User provided screenshot of official VT uAchieve/DARS audit at `uachieve.es.cloud.vt.edu`. It shows categories: University GPA, Minimum Hours, Major, General Ed, In Major GPA, Electives, Minor(s), with Complete/In Progress/Unfulfilled/Planned graph colors. Treat this as the source-of-truth audit shape. |
| **`dars_audit_service.py`** | New backend parser for official DARS/uAchieve PDF/image exports. Uses text extraction for PDFs and vision for screenshots/images. Returns DARS-shaped JSON without inferring missing requirements from local checksheet data. |
| **`POST /advisor/dars/upload`** | New multipart endpoint in `advisor.py`. Accepts PDF/PNG/JPG up to 12 MB. Returns `DarsAuditResponse`. |
| **DARS response models** | Added backend Pydantic models: `DarsAuditResponse`, `DarsCategory`, `DarsSection`. Category fields include `complete_hours`, `in_progress_hours`, `unfulfilled_hours`, `planned_hours`, `required_hours`, and optional `gpa`. |
| **Validation** | Backend compile passes. DARS normalizer test maps `Major / In Progress / 67 complete / 17 in-progress / 44 unfulfilled / 128 required` into normalized category data. Unsupported uploads return 415. |

### Session 9 — Transcript Notes Hidden from UI, Preserved for Chat (Codex)
| Change | Detail |
|---|---|
| **Transcript warning UI cleaned up** | Transcript parser warnings such as abbreviated course-title notices, transfer/AP section notes, `VTXXX` equivalent entries, and zero-credit parser details are not shown in `TranscriptView`. Claude had already removed the warning render block; Codex preserved that direction and cleared notes on re-upload/reset. |
| **Warnings kept in memory** | Raw parser warnings are stored in `AppState.transcriptNotes` when a transcript import completes. Settings reset/re-upload clears them. |
| **Chat request includes notes** | iOS `ChatRequest` already has `transcriptNotes` encoded as `transcript_notes`; `ChatViewModel` sends it and `ChatView` syncs it from `AppState`. |
| **Backend chat consumes notes** | `backend/app/routes/chat.py` accepts `transcript_notes`. `ai_service._build_student_context()` includes them as private transcript parse notes for the LLM: "use as private advising context; do not repeat unless relevant." |
| **Validation** | Backend compile passes. Focused `_build_student_context()` test confirms transcript notes are injected into chat context while transfer credit still satisfies `CS 1114`. |

### Session 11 — Chat History / Session Save (Claude)
| Change | Detail |
|---|---|
| **`ChatMessage` → `Codable`** | Added `Codable` conformance to `ChatMessage` in `Models.swift` so messages can be JSON-encoded for persistence. |
| **`ChatSession` model** | New `struct ChatSession: Identifiable, Codable` in `Models.swift`. Fields: `id: UUID`, `title: String`, `date: Date`, `messages: [ChatMessage]`. |
| **`ChatHistoryStore.swift`** | New file. `@MainActor final class ChatHistoryStore: ObservableObject`. Persists sessions as `chat_sessions.json` in the app's Documents directory. Public API: `upsert(_:)` (insert or update, sorted newest-first), `delete(at:)` (IndexSet for swipe-delete). Loads on `init()`. |
| **`ChatViewModel` — session tracking** | Added `currentSessionID: UUID`, `weak var historyStore: ChatHistoryStore?`, and `configure(store:)` method. `autoSave()` snapshots current messages (stripping `isStreaming`) and calls `historyStore.upsert()`. `loadSession(_:)` calls `autoSave()` first, then replaces messages and `currentSessionID`. `clearConversation()` calls `autoSave()` before clearing and mints a new `currentSessionID`. `sendMessage()` calls `autoSave()` after each successful streamed response. |
| **`ChatView` — history button** | Added `@EnvironmentObject var chatHistory: ChatHistoryStore` and `@State private var showHistory`. Header now has a persistent `clock.arrow.circlepath` icon that opens `ChatHistorySheet`. The trash icon is replaced by a `square.and.pencil` icon (save + new chat). `onAppear` calls `vm.configure(store: chatHistory)`. `onDisappear` calls `vm.autoSave()` (preserves partial conversation on tab switch). |
| **`ChatHistorySheet`** | New SwiftUI view in `ChatView.swift`. Full `List` of sessions with title, formatted date, and message count. Swipe-to-delete. Tapping a session calls `vm.loadSession` and dismisses. Toolbar: "Done" (close) + "New Chat" (save + clear + close). Empty state when no sessions exist. |
| **`HokieAdvisorApp`** | Added `@StateObject private var chatHistory = ChatHistoryStore()` and passes it as `.environmentObject(chatHistory)` to both `ContentView` and `OnboardingView`. |

### Session 12 — Swipe-to-Dismiss Keyboard UX (Codex, iOS)
| Change | Detail |
|---|---|
| **Shared keyboard dismissal helper** | Added `KeyboardDismissal.swift` with `UIApplication.dismissKeyboard()`, `.swipeDownToDismissKeyboard()`, and a reusable `KeyboardDismissHandle`. |
| **Advisor input handle** | `ChatView.inputBar` now shows a small non-button drag handle above "Ask a question..."; dragging it down dismisses the keyboard. |
| **Swipe-down dismissal surfaces** | Wired swipe-down keyboard dismissal into `ChatView`, `SettingsView`, `OnboardingView`, `LoginView`, `TranscriptView`, and `ChatMemoryEditorView`. |
| **Interactive scroll dismissal** | Added `.scrollDismissesKeyboard(.interactively)` to chat messages, profile/settings, onboarding step shells, transcript import/status screen, and chat memory list. This also handles number-pad fields such as profile grad year. |
| **Validation** | `xcodebuild` was attempted with DerivedData under `/private/tmp`; Swift compilation started, but the build failed at the existing `Hoki.icon` `actool` crash documented above. No Swift diagnostics appeared before that asset failure. |

### Session 13 — Supabase Backend Foundation (Codex)
| Change | Detail |
|---|---|
| **Supabase config** | `backend/app/config.py` now reads `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`; `backend/.env.example` documents them. |
| **Service-role client** | Added `backend/app/services/supabase_service.py`, a minimal PostgREST client using existing `httpx` dependency. It supports health checks, inserts, and upserts without adding a new SDK dependency. |
| **Database schema** | Added `backend/supabase/migrations/001_initial_schema.sql` with user-owned tables for profiles, transcripts/courses, chat sessions/messages/memories, degree audits, DARS audits, plus public catalog lookup tables. RLS is enabled with user-owned policies and public read policies for catalog data. |
| **Catalog migration path** | Added `backend/app/services/supabase_catalog_sync.py` and `backend/scripts/sync_catalog_to_supabase.py` to upsert local JSON data into `catalog_subjects`, `catalog_courses`, `catalog_programs`, `catalog_requirements`, `pathways_courses`, and `coe_courses`. |
| **Health/status** | `/health` now includes Supabase config status; `/admin/supabase/status` checks database reachability when credentials are present. |
| **Docs** | Added `backend/supabase/README.md` with setup, migration, sync, and health-check instructions. |
| **Validation** | Python compile passes with bytecode cache redirected to `/private/tmp`. FastAPI app import passes. Sync script correctly exits when Supabase env vars are not configured locally. |

### Session 14 — Supabase Auth/Storage Bootstrap (Codex)
| Change | Detail |
|---|---|
| **Auth/profile bootstrap migration** | Added `backend/supabase/migrations/002_auth_storage_bootstrap.sql`. It creates `public.handle_new_user()` and an `auth.users` trigger that seeds/updates `profiles` from signup metadata (`full_name`, `vt_email`, `vt_pid`, `major`, `graduation_year`, `appearance_mode`). |
| **Private storage buckets** | Same migration creates private `transcripts` and `dars-audits` buckets with 12 MB limits and per-user folder policies based on `storage.foldername(name)[1] == auth.uid()`. |
| **iOS Supabase auth client** | Added `SupabaseService.swift` with blank `SupabaseConfig.url`/`anonKey`, REST-based sign-up/sign-in against Supabase Auth, profile upsert when a session is returned, and Keychain-backed session storage. No service-role key is used in iOS. |
| **Onboarding wired to Supabase** | `OnboardingView` now creates a Supabase account with the collected VT email/password/profile metadata when configured. If not configured, it keeps the existing local password flow. |
| **Login wired to Supabase** | `LoginView` still checks the local password hash, then signs into Supabase when configured and stores the session in Keychain. |
| **Reset clears Supabase session** | Settings clear/reset actions now delete the local Supabase session from Keychain. |
| **Docs updated** | `backend/supabase/README.md` now describes migration order, dashboard auth settings, iOS public config, and the architecture boundary: Supabase owns auth/storage/persistence; trusted AI still needs hosted compute. |
| **Validation** | Python compile passes via `python3 -m py_compile`. `xcodebuild` reached Swift build work but failed at the existing `Hoki.icon` `actool` crash; no Swift diagnostics appeared before the asset failure. |

### Session 10 — Native LaTeX Chat Rendering (Codex)
| Change | Detail |
|---|---|
| **Inline math parsing** | `MarkdownBody` now runs paragraphs, headings, bullets, and numbered list text through `LaTeXFormatter.inline()`, handling `$...$` and `\(...\)` delimiters with common symbol cleanup. |
| **Display math blocks** | `MarkdownBody` now detects `$$...$$`, multi-line `$$` blocks, `\[...\]`, and standalone `\begin{...matrix}` lines as math blocks. |
| **Matrix rendering** | Added `LaTeXMathView` and `LaTeXFormatter.matrix(from:)` in `ContentView.swift`. Supports `matrix`, `bmatrix`, `pmatrix`, and `vmatrix`-style environments by parsing rows separated by `\\` and columns separated by `&`; displays them in a horizontal scroll card. |
| **Common math cleanup** | Formatter maps common LaTeX tokens like `\cdot`, `\times`, `\leq`, `\geq`, `\neq`, `\rightarrow`, `\pi`, `\theta`, `\lambda`, Greek letters, and simple `\frac{a}{b}` to readable native text. |
| **Tutor prompt updated** | Backend system prompt now instructs tutor mode to use LaTeX for math, linear algebra, calculus, proofs, algorithms, recurrence relations, and matrices. |
| **Validation** | Backend compile passes. CLI `xcodebuild` still fails at existing `Hoki.icon` `actool` crash before full Swift diagnostics complete; no Swift diagnostics appeared before that asset failure. |
| **Array/escaped delimiter fix** | User screenshot showed raw `[\beginarrayccc|c ... \endarray]`-style output. Renderer now recognizes double-escaped `\\[` / `\\]`, `array` environments, and augmented matrices with `|` divider cells. Backend prompt now tells tutor mode to prefer `bmatrix`/`pmatrix`, not `array`. |
| **Malformed matrix repair** | Renderer now repairs common malformed model output like `\beginarrayccc|c ... \endarray` into parseable `array` syntax before display, so streamed matrix examples are less likely to show raw LaTeX. |
| **Example-first tutoring** | Backend tutor prompt now says that when a student asks for an example problem, the advisor should provide a concrete example immediately before asking follow-up questions. This addresses the chat response that asked the user to send a matrix instead of generating one. |

### Session 15 — Full Repository Audit (Codex)
| Finding | Detail |
|---|---|
| **Confirmed remaining DARS frontend gap** | Backend DARS ingestion exists, but Swift has no `DarsAuditResponse`/category/section models, no `APIService.uploadDarsAudit`, and no DARS import/rendering UI yet. |
| **Chat memory is implemented** | `ChatMemory` model, `ChatHistoryStore.memories`, memory inference/capture, `ChatMemoryEditorView`, and `chat_memories` request payload are present. Backend injects `chat_memories` into private chat context. |
| **Graph/resource rendering is implemented** | `MarkdownBody` parses fenced `graph` blocks into `GraphDiagramView`; YouTube links become `ResourceLinkCard`. Backend tutor prompt asks for graph blocks on visual graph/CS topics. |
| **Supabase catalog sync bug found** | `supabase_catalog_sync._pathway_rows()` handles a flat dict, but actual `backend/data/pathways.json` is `{source,total_courses,pathways:[...]}` with nested sections. Fix before relying on `pathways_courses` sync. |
| **Catalog data status** | `vt_full_catalog.json` has only 2 subjects and no unique course/program/requirement data; `vt_programs.json` is empty. Runtime falls back to `vt_catalog_202601.json` and COE JSON files for most catalog data. |
| **Repo hygiene issues found** | Root `.env` is ignored but contains a live OpenAI key; rotate/remove it. `.DS_Store` files are tracked in several directories despite ignore rules. |
| **Docs/config drift found** | `README.md` still references Fcounselors paths/endpoints and omits current DARS/audit/Supabase/chat-memory behavior. Settings legal copy still says data is local-only even though backend/OpenAI calls process transcript/chat context. |
| **Validation** | Python source compile passed with `PYTHONPYCACHEPREFIX=/private/tmp`; JSON parsed with `jq`; Xcode `project.pbxproj` and scheme plist linted; workspace XML and `Hoki.icon/icon.json` parsed. Full Swift build was not run during this audit. |

### Session 16 — DARS Frontend Completion (Codex)
| Change | Detail |
|---|---|
| **Swift DARS models** | Added `DarsAuditResponse`, `DarsCategory`, and `DarsSection` in `Models.swift`, matching backend snake_case fields. |
| **DARS upload API method** | Added `APIService.uploadDarsAudit(fileData:mimeType:fileName:)` and generalized multipart upload handling for transcript and DARS uploads. Server `detail` errors now surface as readable messages. |
| **DARS view model** | Added `DarsAuditViewModel` in `PlanViewModel.swift` with upload/loading/error/clear state. |
| **DARS-first Audit tab** | `DegreeAuditView` now leads with "Official Audit" and an "Official DARS / CollegeSource" import card before the local CS fallback audit. |
| **Import UI** | Added PDF/PNG/JPG `fileImporter` support in `ContentView.swift`, with security-scoped file reads and MIME type mapping. |
| **Render UI** | Added official audit summary, GPA metrics, DARS category cards with Complete/In Progress/Unfulfilled/Planned bars, warnings, section cards, and a clear/replace flow. |
| **Backend not-ready state** | If the backend/source API is unavailable or returns an error, the DARS card stays usable and shows a dedicated "DARS backend not ready" message. |
| **Validation** | `xcodebuild` reached Swift compilation with no Swift diagnostics, then failed at the existing `Hoki.icon` `actool` crash. `git diff --check` passed and project plist lint passed. |

### Session 17 — Supabase Auth Redirect, Profile Recreation, and Real Account Reset (Codex)
| Change | Detail |
|---|---|
| **Root cause of localhost confirmation page** | Supabase confirmation emails were redirecting to `http://localhost:3000`, which only makes sense for a web app. Safari showed "can't connect to localhost" after confirmation because no local web server was running. |
| **Mobile auth callback added** | Added a custom iOS URL scheme and callback path: `hokieadvisor://auth/callback`. New file: `ios/HokieAdvisor/Info.plist`. Xcode now uses this plist instead of an auto-generated one. |
| **Deep link handling** | `HokieAdvisorApp.swift` now listens for `.onOpenURL`; `SupabaseAuthService.handleAuthRedirect(_:)` parses Supabase auth tokens from query/fragment and saves the session in Keychain. |
| **Signup redirect target** | `SupabaseService.swift` now sends `options.email_redirect_to = hokieadvisor://auth/callback` on signup. Supabase Dashboard must also allow this redirect. Old emails may still point to localhost; resend after changing dashboard URL settings. |
| **Local Supabase config updated** | `backend/supabase/config.toml` now uses `site_url = "hokieadvisor://auth/callback"` and includes that URL in `additional_redirect_urls`. |
| **Profiles vs Auth clarified** | `profiles` is not the actual account. The real account is in Supabase Auth (`auth.users`). Deleting a row from `profiles` manually does not delete the Auth user, so signing up again with the same email may not fire the `auth.users` trigger again. |
| **Profile recreation guardrail** | Signup/signin now calls `ensureProfile(...)`, which fetches `/auth/v1/user` if needed and upserts the `profiles` row. This fixes the case where the Auth user exists but the profile row was manually deleted. |
| **Existing-user onboarding recovery** | If signup returns an "already exists" style Supabase error, onboarding attempts signin with the same credentials and upserts the profile instead of leaving the user stuck. |
| **Real remote Reset Account** | Settings "Reset Account" now calls `SupabaseAuthService.deleteAccount()` before clearing local state. This hits a trusted Supabase Edge Function and deletes the actual Auth user; profile rows cascade-delete through the DB FK. |
| **New Edge Function** | Added and deployed `backend/supabase/functions/account/index.ts`. It accepts authenticated `DELETE`, verifies the bearer token via `/auth/v1/user`, then deletes that user through `/auth/v1/admin/users/{id}` using `SUPABASE_SERVICE_ROLE_KEY` inside Supabase only. No service-role key is shipped in iOS. |
| **Function config** | Added `[functions.account]` to `backend/supabase/config.toml` with `verify_jwt = false` because the function performs its own user-token verification before admin deletion. |
| **Deployment** | Deployed `account` to project `gcmwrrrspkgawiwisunq` with `supabase functions deploy account --project-ref gcmwrrrspkgawiwisunq`. Secrets list confirmed `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY` are present. |
| **Smoke test** | Unauthenticated `DELETE https://gcmwrrrspkgawiwisunq.supabase.co/functions/v1/account` returned `401 {"detail":"Missing bearer token."}`, confirming the function is live and not crashing. |
| **Validation** | `plutil -lint ios/HokieAdvisor/Info.plist` passed. `xcodebuild -project ios/HokieAdvisor/HokieAdvisor.xcodeproj -scheme HokieAdvisor -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build` succeeded. Remaining warnings: missing `AccentColor` asset and Swift 6 actor-isolation warnings in `SupabaseService.swift`. |
| **Testing note** | For a clean user test: deploy/run the latest iOS build, create account, confirm email via fresh email, verify row appears in `profiles`, then use Reset Account and verify both Auth user and profile row are gone. If an old broken Auth user remains and login is impossible, delete that one once from Supabase Dashboard `Authentication > Users` and retry fresh. |

### Session 18 — Supabase Chat Function + Catalog Sync Fix (Codex)
| Change | Detail |
|---|---|
| **API grants migration** | Added `backend/supabase/migrations/003_api_role_grants.sql` because the hosted project was created with automatic table exposure disabled. RLS still controls row-level access; the migration grants API roles access to the intended tables. |
| **CLI config** | Added `backend/supabase/config.toml` so Supabase CLI commands know the local project layout. |
| **Catalog sync fixed** | `backend/app/services/supabase_catalog_sync.py` now reads legacy `vt_catalog_*.json` course data and the nested `pathways[].sections[].courses[]` shape in `backend/data/pathways.json`. |
| **Catalog sync completed** | Hosted project `gcmwrrrspkgawiwisunq` was populated with `catalog_subjects: 7`, `catalog_courses: 541`, `pathways_courses: 1134`, and `coe_courses: 757`. `catalog_programs`/`catalog_requirements` remain `0` because the local source files are empty. |
| **Chat Edge Function implemented** | Replaced the default Supabase `chat` function template with `backend/supabase/functions/chat/index.ts`. It calls OpenAI from Supabase secrets, supports JSON and `/stream`, adds transcript/in-progress/notes/memory context, and pulls CS course context from Supabase `coe_courses`. |
| **iOS chat routed to Supabase** | `APIService.streamChat` and `sendChat` now call `https://gcmwrrrspkgawiwisunq.supabase.co/functions/v1/chat` with the public Supabase anon key. Other API features still use local FastAPI. |
| **Deployment/validation** | `supabase functions deploy chat` succeeded. Smoke tests returned `STATUS 200` for both `/functions/v1/chat` and `/functions/v1/chat/stream`. |
| **Security note** | User accidentally showed an OpenAI key in a screenshot. Treat it as exposed: revoke/rotate in OpenAI, then run `supabase secrets set OPENAI_API_KEY=...` and update local `backend/.env` if still used. |

### Session 19 — Hokie UX Revamp / Glass Chrome / Keyboard Polish (Codex)
| Change | Detail |
|---|---|
| **Hokie design system started** | `ContentView.swift` now includes shared Hokie styling primitives: `HokieChrome`, glass rounded/capsule/circle backgrounds, `HokiePageHeader`, `HokieCompactPill`, `HokieSignalMark`, `HokieSignalTrack`, `HokieSegmentedControl`, `HokieIconTile`, `HokieSheetHeader`, and `HokieAppBackground`. These replace the older plain Apple/iMessage-like chrome with a VT burgundy/orange, student-dashboard feel. |
| **Headers redesigned** | Home, Audit, Advisor, and Profile now use unique Hokie page headers with a vertical signal mark, monospaced eyebrow, compact title behavior, and VT-inspired accent rails. Advisor now says "Advisor" rather than "AI Advisor." Audit no longer emphasizes "Official" in the main tab title. |
| **Floating footer glass cleanup** | Floating tab bar was made glassier and lowered with `HokieChrome.floatingTabBottomPadding = -16`. `setTabWithoutPageTraversal` avoids the ugly page-by-page slide when jumping from Home directly to Profile. |
| **Header/footer black-plate work** | Native navigation/tab bars are forced transparent through `.transparentNavigationChrome()` and `NavigationBarTransparencyView`. Black plate artifacts were reduced, but keep testing headers in both light and dark mode because this was a recurring visual issue. |
| **Advisor chat composer rebuilt** | Chat composer is now a floating glass bar with plus, text field, mic placeholder, burgundy send state, attachment chip, and attachment menu. Plus menu supports Camera, Photos, and Files UI. Camera/Photos/Files are wired to native pickers, but backend attachment analysis is still placeholder UX. |
| **Advisor prompt overlap fixed** | `HokieChrome.chatComposerRestingBottom = 54` and `chatMessageRestingBottom = 232`. Empty Advisor screen scrolls so "What Computer Science courses should I take next semester?" stays visible above the composer/footer. The compact mini title is disabled on the empty prompt screen to avoid ghosting over the graph preview. |
| **Keyboard cleanup** | Keyboard dismissal accessory was removed by the user; current app relies on native `.scrollDismissesKeyboard(.interactively)`, shared swipe-down dismissal, and keyboard visibility tracking. Login/sign-up and chat both push/scroll content enough to keep action buttons/prompts visible. |
| **Login/sign-up updated** | Login now has conventional Sign In / Sign Up tabs, Supabase-backed session behavior, and keyboard-aware scrolling. Previously logged-in users should go straight into the app via restored session instead of a local password-only gate. |
| **Profile chip clipping fixed** | Profile card chips were reorganized into two rows and `profileChip` gained scaling so the `'29` / PID chips no longer clip on the right edge. |
| **Settings/legal copy refreshed** | Settings legal/privacy sheets now state that transcript, audit, chat, and profile context may be processed through backend services, Supabase, and OpenAI-powered services. |
| **Visual QA helper** | `ContentView` now supports DEBUG launch arg `-HokieInitialTab home|audit|advisor|profile|settings|0|1|2|3`, used with `-HokieVisualQA` for direct simulator screenshots. |
| **Audit visual QA fallback** | `DegreeAuditViewModel.loadVisualQASampleAudit` and `DegreeAuditResponse.visualQASample` provide a DEBUG-only sample audit when launched with `-HokieVisualQA`, avoiding backend connection errors during design QA. Production still calls `POST /advisor/audit`. |
| **Recent screenshots** | Captured simulator QA images under `/tmp`: `/tmp/hokie-qa-audit-after-sample.png`, `/tmp/hokie-qa-profile-chip-fix.png`, `/tmp/hokie-qa-advisor-final-this-pass.png`. |
| **Validation** | Latest `xcodebuild` with simulator destination `05377180-C117-461A-B1E9-5C8CC4FF10D0`, DerivedData `/tmp/HokieAdvisorSimDerivedData`, and `CODE_SIGNING_ALLOWED=NO` succeeded. |

### Session 20 — Hosted Transcript/DARS/Audit Migration (Codex)
| Change | Detail |
|---|---|
| **Hosted functions added** | Added Supabase Edge Functions: `transcript`, `dars`, `audit`, and `tutoring`, plus shared helper code in `backend/supabase/functions/_shared/academic.ts`. |
| **iOS local server dependency removed** | `APIService.swift` now calls `https://gcmwrrrspkgawiwisunq.supabase.co/functions/v1/transcript`, `/dars`, `/audit`, and `/tutoring`; the old `127.0.0.1:8000` base URL and "Start FastAPI backend on port 8000" user copy are gone. |
| **Response contracts preserved** | Hosted functions return the existing Swift shapes: `TranscriptResponse` including `planned_courses`, `DarsAuditResponse`, `DegreeAuditResponse`, and `TutoringResponse`. Error bodies keep the existing `{detail:{code,message}}` pattern. |
| **Optional Supabase persistence** | When a real user bearer token is present, functions attempt to persist transcript uploads/courses, DARS audit results, and degree audit results using the server-side service role key. Persistence failures are logged status-only and do not block user responses. |
| **Deployed** | Deployed `transcript`, `dars`, `audit`, and `tutoring` to project `gcmwrrrspkgawiwisunq`. Latest list showed `chat` v5, `account` v2, `audit` v2, `tutoring` v2, `transcript` v8, `dars` v9, all ACTIVE. |
| **Secrets fixed** | Supabase function secrets were refreshed from `backend/.env` with `supabase secrets set --env-file ../.env --project-ref gcmwrrrspkgawiwisunq`; reserved `SUPABASE_*` names were skipped by the CLI as expected. |
| **Smoke tests** | `audit` returned HTTP 200 with synthetic transcript data and counted `CS 1114` grade `T` as complete. `tutoring` returned HTTP 200. Synthetic transcript PDF returned HTTP 200 with `courses[]` and `planned_courses[]`. Synthetic DARS PDF returned HTTP 200 with DARS metadata/categories/sections. Unsupported-file checks returned HTTP 415, non-transcript/non-DARS image uploads return coded HTTP 422 parse failures, and invalid bearer token returned HTTP 401. |
| **Parser hardening** | Transcript now rejects empty parser results with `TRANSCRIPT_PARSE_FAILED`. DARS prompt examples no longer include realistic sample IDs/values, and DARS rejects unreadable/prompt-template responses with `DARS_PARSE_FAILED`. DARS status normalization now handles "In Progress" wording. |
| **Signed-in persistence verified** | Created a synthetic confirmed Supabase Auth user via the admin API, signed in with password auth, uploaded synthetic transcript/DARS PDFs with the user bearer token, and ran hosted audit. Verified rows for that user: `transcripts=1`, `transcript_courses=5`, `degree_audits=1`, `dars_audits=1`. |
| **Validation** | `xcodebuild -project ios/HokieAdvisor/HokieAdvisor.xcodeproj -scheme HokieAdvisor -destination 'id=05377180-C117-461A-B1E9-5C8CC4FF10D0' -derivedDataPath /tmp/HokieAdvisorSimDerivedData CODE_SIGNING_ALLOWED=NO build` succeeded. `git diff --check` passed. Targeted `rg` found no local transcript/DARS/audit/tutoring URL dependency in iOS/Supabase functions. |

### Session 21 — Advisor Entry Scroll Fix (Codex)
| Change | Detail |
|---|---|
| **Empty Advisor entry** | `ChatView` no longer calls the keyboard bottom-scroll helper from `.onAppear` unless the Advisor text field is focused and the keyboard is visible. Otherwise it resets the empty chat screen to `topID`, keeping the Advisor header visible when entering from the footer or by swiping. |
| **Keyboard behavior preserved** | The empty-state bottom scroll still runs when `isInputFocused && isKeyboardVisible`, so typing keeps the composer/prompts clear of the keyboard. |
| **Composer/footer gap** | Increased `HokieChrome.chatComposerRestingBottom` and the matching chat message spacer by 22pt so the resting Ask bubble floats above the footer instead of touching it. |
| **Validation** | Simulator Debug build succeeded. Visual QA screenshot in dark mode confirmed the Advisor header is visible immediately after launching `-HokieVisualQA -HokieInitialTab advisor`. |

### Session 22 — Production Hardening / User-Owned Chat Data (Codex)
| Change | Detail |
|---|---|
| **Supabase child ownership migration** | Added `backend/supabase/migrations/004_user_owned_child_integrity.sql`. It adds composite unique keys on `(id,user_id)` for `transcripts` and `chat_sessions`, composite FKs for `transcript_courses(transcript_id,user_id)` and `chat_messages(session_id,user_id)`, and tightens RLS policies so child rows must point to a parent owned by `auth.uid()`. This prevents a malicious caller from attaching their own child row to another user's parent UUID. |
| **User-scoped chat sync service** | Added `UserDataSyncService.swift`, a REST/RLS client for `chat_sessions`, `chat_messages`, and `chat_memories`. It fetches the authenticated user's latest 50 sessions and 100 memories, upserts sessions/messages/memories, and deletes sessions/memories through the user's bearer token. Service-role keys remain server-side only. |
| **Per-user local chat cache** | `ChatHistoryStore` now caches to `chat_sessions_<userID>.json` and `chat_memories_<userID>.json` once authenticated, instead of one app-wide file. Remote data merges with the user-scoped local cache; local-only user cache records are pushed to Supabase after sync. Anonymous/visual-QA data stays in a `local` cache and is not pushed. |
| **Auth/session sync hooks** | `HokieAdvisorApp` now validates/enriches the Keychain session with `/auth/v1/user` before restoring auth, configures chat sync on restore/auth deep link/auth state changes, and clears loaded chat data when signed out. |
| **Chat function auth header** | `APIService.sendChat` and `APIService.streamChat` now send the signed-in user's bearer token when available instead of always using the anon JWT. The chat Edge Function still works anonymously, but signed-in chat calls now carry identity consistently with transcript/DARS/audit/tutoring. |
| **Sign-out leakage guard** | `SettingsView.signOut()` now clears visible transcript/profile/AppState data and unloads chat history from memory without deleting the signed-out user's local chat cache. "Clear All Data" and Reset Account still erase the local cache; Reset Account still calls the remote account-deletion Edge Function first. |
| **Swift 6 warning cleanup** | Marked value-only `ChatMessage`, `ChatSession`, and `ChatMemory` models `nonisolated`, removing actor-isolation warnings from the new sync service under the project's default MainActor isolation settings. |
| **Hygiene/security checks** | `find . -name .DS_Store` returned no files. `git grep -IlE 'sk-[A-Za-z0-9_-]{20,}'` found no tracked OpenAI-style secret values. The ignored root `.env` is still known to contain a real key per earlier audit; rotate/remove before sharing. |
| **Validation** | `git diff --check` passed. Backend edited files compiled with `PYTHONPYCACHEPREFIX=/private/tmp/hokie-pycache python3 -m py_compile ...`. Simulator build succeeded twice with `xcodebuild -project ios/HokieAdvisor/HokieAdvisor.xcodeproj -scheme HokieAdvisor -destination 'id=05377180-C117-461A-B1E9-5C8CC4FF10D0' -derivedDataPath /tmp/HokieAdvisorSimDerivedData CODE_SIGNING_ALLOWED=NO build`; second build had no Swift actor-isolation warnings, only the existing AppIntents metadata note. |

### Session 23 — Authenticated AppState Rehydrate / Migration Safety (Codex)
| Change | Detail |
|---|---|
| **Idempotent ownership migration** | Updated `004_user_owned_child_integrity.sql` to wrap constraint creation in `DO $$ ... if not exists ... $$`, so the migration is safer to apply/re-run in long-lived environments where a constraint may already exist. RLS policy refresh remains explicit with `drop policy if exists`. |
| **Student snapshot restore** | Extended `UserDataSyncService.swift` with `fetchStudentSnapshot(userID:accessToken:)`. It reads the authenticated user's `profiles` row, latest `transcripts` row, linked `transcript_courses` rows split by `status`, latest `degree_audits.response`, and latest `dars_audits.response` through RLS-protected REST calls. Transcript fetch failures now throw instead of being treated as "no transcript", so slow/offline partial failure does not clear local transcript state. |
| **App launch rehydrate** | `HokieAdvisorApp` now validates/enriches the session once, then uses the same user ID/token for chat sync plus student snapshot restore. It applies profile fields into AppStorage (`studentName`, `vtEmail`, `vtPID`, `graduationYear`, `appearanceMode`), updates `AppState.major`, restores transcript/in-progress/planned courses and notes, and stores latest audit/DARS responses in `AppState`. |
| **Cached audit/DARS display** | `AppState` now has `latestDegreeAudit` and `latestDarsAudit`. `DegreeAuditView` loads cached audit/DARS results into its existing view models before making a network audit call, avoids an unnecessary audit call when a cached audit was restored, updates the cache after refresh/upload, and clears DARS cache when the user clears DARS. |
| **Stale audit cleanup** | Transcript upload/re-upload and account clearing now clear cached degree audit/DARS state where appropriate so stale results do not cross transcript or user boundaries. |
| **Force unwrap cleanup** | Replaced the force unwrap in `AppState.semesterGroups` with a guarded `compactMap`, removing an avoidable sharp edge in shared state code. |
| **Hosted migration not applied** | Attempted to request approval for `supabase db push --project-ref gcmwrrrspkgawiwisunq`, but the approval reviewer rejected the escalation because it would mutate hosted database schema/RLS without explicit user authorization. Do not attempt a workaround; ask the user directly before applying this remote migration. |
| **Validation** | `git diff --check` passed. Backend edited files compiled with `PYTHONPYCACHEPREFIX=/private/tmp/hokie-pycache python3 -m py_compile ...`. `find . -name .DS_Store` found no files. `git grep -IlE 'sk-[A-Za-z0-9_-]{20,}'` found no tracked OpenAI-style keys. `xcodebuild -project ios/HokieAdvisor/HokieAdvisor.xcodeproj -scheme HokieAdvisor -destination 'id=05377180-C117-461A-B1E9-5C8CC4FF10D0' -derivedDataPath /tmp/HokieAdvisorSimDerivedData CODE_SIGNING_ALLOWED=NO build` succeeded; only the existing AppIntents metadata note appeared. |

### Session 24 — Profile Settings Supabase Writeback (Codex)
| Change | Detail |
|---|---|
| **Profile upsert service** | Added `SupabaseUserDataService.upsertProfile(...)`, which writes `full_name`, `vt_pid`, `vt_email`, `major`, `graduation_year`, and `appearance_mode` to the authenticated user's `profiles` row through Supabase REST with the user's bearer token. This uses existing RLS and does not expose service-role credentials in iOS. |
| **Settings writeback** | `SettingsView` now schedules a debounced profile sync when the user edits name, graduation year, theme, or major context. It flushes once on disappear so edits are not left only in `@AppStorage`. Network failures are intentionally non-blocking; local settings remain usable and future edits can retry. |
| **Sign-out/reset guard** | Profile sync tasks are cancelled/suppressed during sign-out, Clear All Data, and Reset Account so clearing local account state does not race a blank profile write to Supabase. |
| **Validation** | `git diff --check` passed. Backend edited files compiled with `PYTHONPYCACHEPREFIX=/private/tmp/hokie-pycache python3 -m py_compile ...`. `find . -name .DS_Store` found no files. `git grep -IlE 'sk-[A-Za-z0-9_-]{20,}'` found no tracked OpenAI-style keys. `xcodebuild -project ios/HokieAdvisor/HokieAdvisor.xcodeproj -scheme HokieAdvisor -destination 'id=05377180-C117-461A-B1E9-5C8CC4FF10D0' -derivedDataPath /tmp/HokieAdvisorSimDerivedData CODE_SIGNING_ALLOWED=NO build` succeeded; only the existing AppIntents metadata note appeared. |

### Session 25 — Backend Config / Docs Hardening (Codex)
| Change | Detail |
|---|---|
| **Configurable FastAPI CORS** | Added `CORS_ALLOWED_ORIGINS` in `backend/app/config.py` and wired `backend/app/main.py` to register CORS only for configured origins. Development defaults cover common local web dev ports; production with no explicit origins has CORS disabled instead of wildcard `*`. |
| **Stale branding cleanup** | Renamed FastAPI metadata/root service text from `Fcounselors API` to `Hokie Advisor API` and updated the legacy chat route docstring. |
| **Docs refresh** | Replaced stale root `README.md` with a current Hokie Advisor overview covering hosted Edge Functions, Supabase Auth/Postgres/RLS ownership, pending migration `004`, local fallback setup, secret handling, and validation commands. Updated `backend/supabase/README.md` so it no longer describes transcript/chat/DARS/audit/tutoring hosting as future work. |
| **Validation** | `git diff --check` passed. Edited backend files compiled with `PYTHONPYCACHEPREFIX=/private/tmp/hokie-pycache python3 -m py_compile backend/app/config.py backend/app/main.py backend/app/routes/chat.py`. `find . -name .DS_Store` found no files. `git grep -IlE 'sk-[A-Za-z0-9_-]{20,}'` found no tracked OpenAI-style keys. Simulator build succeeded with `xcodebuild -project ios/HokieAdvisor/HokieAdvisor.xcodeproj -scheme HokieAdvisor -destination 'id=05377180-C117-461A-B1E9-5C8CC4FF10D0' -derivedDataPath /tmp/HokieAdvisorSimDerivedData CODE_SIGNING_ALLOWED=NO build`. |

### Session 26 — Validated Session / Token Refresh Hardening (Codex)
| Change | Detail |
|---|---|
| **Supabase token refresh** | `SupabaseAuthService.validatedCurrentSession()` now verifies the current access token with `/auth/v1/user` and refreshes the session through `grant_type=refresh_token` if validation fails. Refreshed sessions are saved back to Keychain and enriched with the authenticated user ID when needed. |
| **Hosted function auth headers** | `APIService.supabaseFunctionHeaders(includeUserSession:)` now uses the validated/refreshed session path instead of sending the raw cached Keychain token. If validation/refresh is unavailable, hosted functions still receive the anon key instead of a stale user bearer token. |
| **Profile/chat sync identity check** | Settings profile sync, onboarding profile completion sync, and `ChatHistoryStore.configureForAuthenticatedUser()` now use validated sessions. Chat remote sync keeps a short-lived validated token cache for the active user and revalidates periodically, avoiding both stale-user writes and repeated `/auth/v1/user` calls for every local chat save. |
| **Dead auth helper removed** | Removed the unused weaker `currentAuthenticatedSession()` helper so new code has a single user-scoped session path: `validatedCurrentSession()`. |
| **Validation** | `git diff --check` passed. `xcodebuild -project ios/HokieAdvisor/HokieAdvisor.xcodeproj -scheme HokieAdvisor -destination 'id=05377180-C117-461A-B1E9-5C8CC4FF10D0' -derivedDataPath /tmp/HokieAdvisorSimDerivedData CODE_SIGNING_ALLOWED=NO build` succeeded; only the existing AppIntents metadata note appeared. `find . -name .DS_Store` found no files. `git grep -IlE 'sk-[A-Za-z0-9_-]{20,}'` found no tracked OpenAI-style keys. |

### Session 27 — Supabase Audit Ownership / Restore Index Hardening (Codex)
| Change | Detail |
|---|---|
| **Degree audit parent ownership** | Extended pending migration `004_user_owned_child_integrity.sql` with a composite FK for `degree_audits(transcript_id,user_id)` → `transcripts(id,user_id)`, so a user-owned audit cannot point at another user's transcript UUID. The FK preserves existing behavior by setting only `transcript_id` to null when a transcript is deleted. |
| **Degree audit RLS tightened** | Replaced the `degree_audits` RLS policy so rows remain user-owned and any non-null `transcript_id` must resolve to a transcript owned by `auth.uid()`. Null `transcript_id` remains allowed for hosted audits that do not currently bind to a saved transcript row. |
| **User-scoped query indexes** | Added indexes in migration `004` for `transcripts(user_id, created_at desc)`, `chat_sessions(user_id, updated_at desc)`, `chat_memories(user_id, updated_at desc)`, `chat_messages(user_id, session_id, position)`, `degree_audits(user_id, created_at desc)`, and `dars_audits(user_id, created_at desc)` to support the app's restore/chat-sync queries without full scans as data grows. |
| **Docs updated** | Root `README.md` and `backend/supabase/README.md` now mention that migration `004` also protects transcript-linked degree audits and adds restore/sync indexes. |
| **Validation** | `git diff --check` passed. Static migration checks confirmed the degree-audit composite FK/policy and new indexes are present. `find . -name .DS_Store` found no files. `git grep -IlE 'sk-[A-Za-z0-9_-]{20,}'` found no tracked OpenAI-style keys. Attempted `supabase db lint --local --schema public --fail-on error`, but local Postgres was not reachable from the sandbox; the one-off escalation request was rejected, so hosted/local DB lint was not run. |

---

## Next Steps

### For Codex (backend)
- [x] **`transcript_notes` in chat stream** — `POST /chat/stream` body includes `transcript_notes: [String]` and backend injects them into the system prompt under "Transcript Parsing Notes" as private context.
- [ ] **Official CollegeSource/uAchieve source integration** — frontend is ready, but the reliable backend/API source for school degree-audit data is still unsolved and likely needs school support
- [ ] **DARS parser hardening** — once the user exports a real DARS PDF or screenshot or gets official source access, test `POST /advisor/dars/upload` against it and tune extraction for official section text
- [x] **Supabase live setup** — hosted project is linked at `gcmwrrrspkgawiwisunq`; iOS has URL/anon key; Edge Functions are deployed for chat and account deletion.
- [ ] **Supabase Dashboard auth redirect** — ensure `hokieadvisor://auth/callback` is saved under Authentication URL Configuration / Additional Redirect URLs. Resend confirmation emails after this change.
- [ ] **Retest account lifecycle on physical iPhone** — create account, confirm email, verify `profiles` row, tap Reset Account, verify Auth user/profile row delete, then recreate with same credentials.
- [x] **Fix Supabase Pathways sync** — `_pathway_rows()` now handles nested `pathways[].sections[].courses[]`; catalog sync has been run against hosted Supabase.
- [x] **Supabase client config** — `SupabaseConfig.url` and `anonKey` are filled in iOS. Service-role key remains server-side only.
- [x] **Hosted AI compute for transcript/DARS/audit** — hosted `transcript`, `dars`, `audit`, and `tutoring` functions are deployed; iOS points at them; synthetic transcript and DARS PDF uploads parse successfully with no local server.
- [x] **Swift 6 cleanup pass** — current simulator build has no Swift actor-isolation warnings from the edited files. Continue watching this as Swift 6 language mode gets closer.
- [x] **Persist hosted transcript/DARS/audit outputs to Supabase** — signed-in synthetic user test verified rows in `transcripts`, `transcript_courses`, `degree_audits`, and `dars_audits`.
- [x] **Chat sessions/messages/memories Supabase sync** — iOS now uses per-user local chat cache files and syncs chat sessions/messages/memories to the authenticated user's Supabase tables via RLS-protected REST calls.
- [ ] **Deploy/apply `004_user_owned_child_integrity.sql`** — apply the new Supabase migration to hosted project `gcmwrrrspkgawiwisunq`, then verify existing hosted data does not violate the new composite FKs/RLS/index additions. Requires explicit user approval because it mutates hosted schema/RLS.
- [x] **Rehydrate user state from Supabase on launch** — authenticated restore now loads profile/settings, latest transcript/courses/planned courses, latest DARS/audit result, and chat history/memories for the signed-in user.
- [x] **Profile/settings remote update path** — profile edits in Settings now debounce/flush user-scoped Supabase `profiles` upserts through the authenticated user's bearer token.
- [ ] **Real-device signed-in persistence QA** — verify Settings profile edits, transcript restore, audit/DARS restore, chat history/memory sync, sign-out, reset account, and account recreation on a real signed-in session.
- [ ] **Statistics elective approved list** — add to `computer_science.json` so `statistics_elective` bucket resolves
- [ ] **CS theory elective approved list** — same; `cs_theory_elective` bucket currently always open
- [ ] **Multi-major support** — audit service currently throws `ValueError` for non-CS majors
- [ ] **Audit context in chat** — inject audit bucket summary into `POST /chat/stream` system prompt so the bot can answer "what do I still need?" with live audit data
- [ ] **Catalog data refresh** — rebuild/replace `vt_full_catalog.json` and `vt_programs.json`; current files are mostly empty, so runtime relies on legacy/COE fallbacks
- [ ] **Secret hygiene** — rotate the OpenAI key that exists in local root `.env`, keep secrets in untracked env files only, and avoid committing or sharing them
- [x] **Repo cleanup** — tracked `.DS_Store` files are deleted in the working tree; keep `.gitignore` enforcement clean
- [x] **Docs refresh** — root `README.md` and `backend/supabase/README.md` now reflect Hokie Advisor paths, hosted Edge Functions, Supabase user-owned data, pending migration `004`, secret handling, and current validation commands
- [x] **Transfer credit backend semantics** — `T`/`TR` now count as awarded credit in audit and chat context
- [x] **Transcript parser notes to chat** — raw transcript parse warnings are hidden from UI but sent to chat as private context

### For Claude (frontend)
- [x] **DARS upload/import UI** — added Swift DARS models, multipart API call to `POST /advisor/dars/upload`, file importer for PDF/PNG/JPG, and category/section rendering matching Complete/In Progress/Unfulfilled/Planned.
- [x] **Consume `planned_courses`** — done: `TranscriptResponse.planned_courses`, `AppState.plannedCourses`, `plannedCoursesSection` in TranscriptView, semester-aware active/upcoming split
- [ ] **Expandable `AuditBucketCard`** — tappable to reveal all `matchedCourses` + full `notes` list (currently capped at 4 courses / 1 note)
- [ ] **Home screen audit preview** — inline card showing % complete from last audit (needs audit result accessible outside of `DegreeAuditView`)
- [x] **LaTeX rendering in chat** — lightweight native renderer for inline/display math and common matrix environments. Future upgrade could replace it with full MathJax/KaTeX rendering if needed.
- [x] **Graph rendering in chat** — fenced `graph` blocks render as native `GraphDiagramView`; tutor prompt asks for graph blocks for graph theory/path/tree topics.
- [x] **YouTube/resource cards in chat** — YouTube links in assistant messages render as compact resource cards.
- [x] **Chat history / session save** — sessions auto-saved to Documents/chat_sessions.json on every assistant reply and on tab switch. `ChatHistorySheet` lets users browse, resume, and delete past chats.
- [x] **Chat memory** — user messages can infer saved memories, users can edit memories in Profile, and `chat_memories` are sent to backend as private personalization context.
- [x] **Swipe down to dismiss keyboard** — shared gesture + native interactive scroll dismissal across chat, profile/settings, onboarding, login, transcript, and chat memory editor. Chat input has a small drag handle above the prompt.
- [ ] **Face ID / Touch ID** for `appPasswordHash`
- [ ] **Dynamic chips post-audit** — after audit loads, surface chips like "Why do I need to retake CS 2114?"
- [x] **Privacy/legal copy refresh** — Settings legal sheets now mention backend services, Supabase, and OpenAI-powered processing.
- [ ] **Final visual QA pass** — before marking the UX revamp complete, inspect Home/Audit/Advisor/Profile, login/sign-up, onboarding, transcript import, sheets, keyboard states, and light/dark mode screenshots for header/footer artifacts, clipping, and copied-app feel.
- [ ] **Deployment target check** — Xcode project currently targets iOS `26.4`; lower it if iOS 17+ remains the desired support range.

### Done ✓
- [x] Hardcoded "CS '26" badge → dynamic major + grad year badges
- [x] GPA calculation and display (Home, Profile, Transcript)
- [x] Grad year syncs from transcript import AND manual entry
- [x] TranscriptView stuck-in-sheet bug — ✕ dismiss button added
- [x] Degree Audit backend + frontend (fully functional for CS B.S.)
- [x] Official DARS frontend path — import UI and response rendering are ready for the backend/source API contract
- [x] Semester-aware transcript UI — future registered courses no longer appear as "currently enrolled"; `planned_courses` wired end-to-end
- [x] Chat history and chat memory are local-device persisted and included in advisor context
- [x] Native chat rendering now covers code blocks, lightweight LaTeX, graph blocks, and YouTube resource cards

---

## Key Technical Facts

```
Stack:
  iOS:      SwiftUI, Xcode 16/26 project format, PBXFileSystemSynchronizedRootGroup
            @EnvironmentObject AppState, @AppStorage for persistence
            Handoff historically said iOS 17+, but project currently sets
            IPHONEOS_DEPLOYMENT_TARGET = 26.4 in project.pbxproj.
  Backend:  FastAPI + OpenAI, Python 3.11+, uvicorn on port 8000 for local
            dev/parity fallback. iOS production calls hosted Supabase functions.
  Supabase: Hosted project gcmwrrrspkgawiwisunq. Auth/storage/Postgres are live.
            Edge Functions deployed: chat, account, transcript, dars, audit, tutoring.

API endpoints:
  Supabase Edge Functions:
  POST/stream https://gcmwrrrspkgawiwisunq.supabase.co/functions/v1/chat
                            Deployed chat advisor endpoint used by iOS APIService.
  DELETE      https://gcmwrrrspkgawiwisunq.supabase.co/functions/v1/account
                            Authenticated account deletion. Requires user bearer token.
                            Deletes auth.users row via service-role key server-side;
                            profiles cascade-delete through FK.

  Local/FastAPI endpoints:
  GET  /admin/supabase/status — Supabase config + database reachability check
  POST /advisor/dars/upload — Official DARS/uAchieve audit ingestion
                            Multipart file: PDF/PNG/JPG
                            Returns: DarsAuditResponse
  POST /advisor/audit     — Degree Audit
                            Body: {major, transcript[], in_progress_courses[]}
                            Returns: DegreeAuditResponse (see Models.swift)
  POST /chat/stream       — SSE chat, token-by-token
                            Body may include transcript_notes[] and chat_memories[]
                            for private LLM context
  POST /chat              — legacy non-streaming fallback
  POST /advisor/plan      — course plan AI recommendation (backend only, not in UI)
  POST /transcript/upload — multipart file → TranscriptResponse
                            Now includes planned_courses[] for future registered classes

Degree Audit bucket statuses:
  "complete"    — all required credits/count met
  "in_progress" — partially satisfied
  "incomplete"  — nothing matched yet
  "attention"   — attempted but grade insufficient (retake needed)

DARS/uAchieve response shape:
  DarsAuditResponse:
    student_name, student_id, program, program_code, catalog_year,
    graduation_date, prepared_on, job_id, audit_type,
    university_gpa, in_major_gpa,
    categories[], sections[], warnings[]
  DarsCategory:
    id, title, status, complete_hours, in_progress_hours,
    unfulfilled_hours, planned_hours, required_hours, gpa, notes[]
  DarsSection:
    title, status, matched_courses[], missing_items[], notes[]
  Status values:
    complete, in_progress, unfulfilled, planned, unknown
  Frontend:
    Models.swift has DarsAuditResponse/DarsCategory/DarsSection.
    APIService.uploadDarsAudit posts multipart to /advisor/dars/upload.
    DegreeAuditView renders official DARS first, local CS audit second.

AppState key computed properties:
  calculatedGPA         — Double?, weighted GPA (P/CR/TR/T excluded)
  totalCredits          — sum of all transcript course credits
  completedCourseCodes  — [String] for API payloads
  semesterGroups        — [SemesterGroup] sorted newest→oldest
  needsTutoringSupport  — true when passingAllClasses==false && !strugglingCourses.isEmpty
  transcriptNotes       — raw parser warnings/notes, hidden from TranscriptView but sent to chat

Backend transcript grade semantics:
  T / TR / TRANSFER — transfer credit awarded; normalized to T; counts as completed credit
  P / PASS          — pass credit awarded; normalized to P; counts as completed credit
  CR / CREDIT       — credit awarded; normalized to CR; counts as completed credit
  F / W / WF / I / NG / missing grade — not completed credit
  For exact VT equivalents (e.g. CS 1114 with T), awarded credit satisfies the requirement,
  including C-or-better gates. Placeholder transfer courses like CS 1XXX should count only
  as elective/free credit, not as a named core requirement.

AppStorage keys currently used:
  onboardingComplete, studentName, vtEmail, vtPID, appPasswordHash,
  howHeardAboutUs, graduationYear, appearanceMode

Supabase auth facts:
  iOS public config lives in SupabaseService.swift:
    url = https://gcmwrrrspkgawiwisunq.supabase.co
    anonKey = public anon JWT only
    authRedirectURL = hokieadvisor://auth/callback
  Never place SUPABASE_SERVICE_ROLE_KEY in iOS. It is only used inside trusted
  backend/Edge Function code.
  Email confirmation deep link requires:
    ios/HokieAdvisor/Info.plist with CFBundleURLTypes for scheme hokieadvisor
    HokieAdvisorApp.onOpenURL handler
    Supabase Dashboard auth redirect allowlist containing hokieadvisor://auth/callback

Grad year flow:
  @AppStorage("graduationYear") — shared key, default "" in ALL views (not "2027")
  TranscriptView auto-infers on upload (earliest semester year + 4)
  SettingsView text field allows manual override
  HomeView shows whenever non-empty — no transcript required

File ownership:
  Claude → HomeView.swift, ChatView.swift, ChatViewModel.swift, ChatHistoryStore.swift,
           SettingsView.swift, TranscriptView.swift, TranscriptViewModel.swift,
           OnboardingView.swift, LoginView.swift, HokieAdvisorApp.swift,
           AppState.swift, Models.swift, APIService.swift, CodeBlockView.swift
  Codex  → backend/app/routes/*.py, backend/app/services/degree_audit_service.py,
           backend/app/services/ai_service.py, backend/data/catalog/computer_science.json,
           backend/data/pathways.json, backend/app/services/supabase_service.py,
           backend/app/services/supabase_catalog_sync.py, backend/supabase/*
  Shared → ContentView.swift (Claude owns tab bar + shared helpers;
                               Codex owns DegreeAuditView + AuditSummaryCard + AuditBucketCard)

VT Burgundy:  Color(red: 0.525, green: 0.122, blue: 0.255)  /  #861F41
Bundle ID:    com.hokieadvisor.HokieAdvisor
Xcode dir:    ios/HokieAdvisor/HokieAdvisor/
Icon:         ios/HokieAdvisor/HokieAdvisor/Hoki.icon  ← DO NOT TOUCH

SourceKit cross-file errors in editor are NOT real build errors.
Always compile in Xcode to see actual diagnostics.

LaTeX chat rendering:
  Implemented in ContentView.swift:
    MarkdownBody parses math blocks and inline math.
    LaTeXMathView renders display math cards and matrix environments.
    LaTeXFormatter does lightweight symbol/fraction cleanup.
  Supported delimiters:
    inline: $...$, \(...)
    block: $$...$$, \[...\]
    matrices: \begin{bmatrix}1 & 2 \\ 3 & 4\end{bmatrix}
    arrays: \begin{array}{ccc|c}1 & 2 & 3 & 4\end{array}
  This is a native lightweight renderer, not full TeX. Good for tutoring examples,
  matrices, augmented matrices, fractions, and common symbols.
```

---

## /compact

```
/compact Project: Hokie Advisor — SwiftUI iOS academic advising app for Virginia Tech. Repo: /Users/rehobothkebede/GitHub/Fcounselors. Xcode 16/26 project format, bundle com.hokieadvisor.HokieAdvisor. Historical target note said iOS 17+, but project.pbxproj currently sets IPHONEOS_DEPLOYMENT_TARGET = 26.4.

TWO-AGENT WORKFLOW: Claude = iOS frontend (ios/HokieAdvisor/HokieAdvisor/), Codex = backend (backend/). HANDOFF.md is the comms channel — read it at session start, update it at session end.

Sessions 1–5: Rename, 7-step onboarding, login, dark mode, chat streaming (SSE), code blocks, transcript-aware chatbot, VT grade rules (C- ≠ "C or better").

Session 6 — Claude (UX polish):
- AppState.calculatedGPA (weighted, 4.0 scale, P/CR/TR excluded). Shared gpaColor() in ContentView.swift.
- Home: 2×2 LazyVGrid stats (Credits, GPA, Courses, Grad Year), time-of-day greeting.
- Grad year: @AppStorage("graduationYear") default "" everywhere. Home shows when non-empty, no transcript needed.
- Haptics: .sensoryFeedback on tab bar, UIImpactFeedbackGenerator(.medium) on action buttons and send.
- Chat chips: dynamic using appState.major, not hardcoded CS.
- SettingsView profile card: dynamic major + 'YY + PID badges, GPA inline.
- TranscriptView: @Environment(\.dismiss) + ✕ button in header — no longer stuck in sheet.

Session 6 — Codex (Degree Audit):
- backend/app/services/degree_audit_service.py — deterministic CS B.S. audit from computer_science.json + pathways.json.
- POST /advisor/audit → DegreeAuditResponse {major, degree, catalog_year, total_required_credits, completed_credits, percent_complete, complete_bucket_count, total_bucket_count, buckets[], warnings[]}.
- AuditBucket: {id, title, status(complete/in_progress/incomplete/attention), required_credits, completed_credits, matched_courses[], missing_items[], notes[]}.
- Buckets: required courses, natural science (8cr), advanced nat sci (4cr), comms (1), writing (1), CS 3/4/5xxx electives, pathways 1F/1A/2/3/4/5F/5A/6A/6D/7-suspended, free electives, total credits.
- GAPS: statistics_elective + cs_theory_elective approved lists missing from catalog data — both buckets stay open.
- ContentView: DegreeAuditView (auto-runs via .task on transcript change), AuditSummaryCard (% bar, credits, bucket counts), AuditBucketCard (status icon, credits, matched/missing). Tab 1 = "Audit" / checklist.checked.

Session 7 — Codex backend fixes:
- Transfer/awarded credit semantics fixed across backend audit + chat context. `T`, `TR`, `TRANSFER`, `P`, `PASS`, `CR`, `CREDIT` count as awarded/completed credit. Exact VT equivalent transfer credit such as `CS 1114` with `T` satisfies that requirement, including C-or-better gates.
- transcript_service prompt/normalizer now supports `planned_courses[]` for future registered/no-grade courses. Postprocess moves no-grade in_progress courses whose semester has not started into `planned_courses` and adds a warning. Start heuristic: Spring Jan, Summer May, Fall Aug.
- POST /transcript/upload response now includes planned_courses[]; existing iOS can ignore until Claude wires it.

Session 7 — Claude frontend (semester-awareness + planned_courses):
- AppState.plannedCourses (renamed from upcomingCourses). TranscriptResponse.planned_courses field aligned with backend.
- AppState: currentVTSemester, isSemesterInSession, activeSemesterCourses, registeredUpcomingCourses, semester-aware inProgressSummary.
- TranscriptView: inProgressSection uses activeSemesterCourses (grade buttons only); new plannedCoursesSection for future-semester courses (no grade buttons); semesterStatusSection guarded behind isSemesterInSession.

Session 8 — Codex official DARS ingestion:
- User showed official uAchieve/DARS screenshot from uachieve.es.cloud.vt.edu. Correct audit shape is DARS categories: University GPA, Minimum Hours, Major, General Ed, In Major GPA, Electives, Minor(s), with Complete/In Progress/Unfulfilled/Planned.
- Added backend/app/services/dars_audit_service.py.
- Added POST /advisor/dars/upload for DARS PDF/PNG/JPG upload. Returns DarsAuditResponse with metadata, categories, sections, warnings.
- Verified backend compile, DARS normalizer, and unsupported file 415.

Session 9 — Transcript notes hidden from UI, sent to chat (both agents):
- Claude: removed WarningCard display from TranscriptView. AppState.transcriptNotes stores raw parse warnings. ChatRequest encodes transcript_notes[] (snake_case). ChatViewModel + ChatView sync notes from AppState.
- Codex: backend chat.py accepts transcript_notes[]. ai_service._build_student_context() injects them as private context: "use as private advising context; do not repeat unless relevant."

Session 10 — Codex native LaTeX chat rendering:
- ContentView MarkdownBody now parses inline $...$ / \(...\), display $$...$$ / \[...\], and matrix environments.
- Added LaTeXMathView + LaTeXFormatter for lightweight native rendering of matrices, simple fractions, and common symbols. Not a full TeX engine.
- Backend tutor prompt now asks the advisor/tutor to use LaTeX for math, linear algebra, matrices, calculus, proofs, algorithms, and recurrences.
- MarkdownBody also parses fenced `graph` blocks into native GraphDiagramView and YouTube links into resource cards. Backend tutor prompt requests graph blocks for visual graph/CS topics.
- Verified backend compile. CLI xcodebuild still stops at existing Hoki.icon actool crash before full Swift diagnostics.

Session 11 — Claude chat history:
- ChatMessage is now Codable. New ChatSession struct (Identifiable, Codable) in Models.swift: id, title, date, messages[].
- New ChatHistoryStore.swift: @MainActor ObservableObject, persists sessions to Documents/chat_sessions.json. upsert() inserts/updates sorted newest-first. delete(at:) for swipe-delete. Loads on init.
- ChatMemory model and memory persistence are now present too: ChatHistoryStore persists chat_memories.json, infers memories from user messages, exposes memoryContext, and SettingsView has ChatMemoryEditorView. ChatViewModel sends chat_memories[] to backend; backend chat.py/ai_service inject them as private personalization context.
- ChatViewModel: currentSessionID UUID, configure(store:), autoSave() (strips isStreaming), loadSession() (auto-saves current first), clearConversation() (saves before clearing, mints new sessionID). sendMessage() calls autoSave() after each successful stream.
- ChatView: @EnvironmentObject chatHistory. Header has clock.arrow.circlepath button → ChatHistorySheet. Pencil/compose button replaces trash (saves + starts new). onDisappear calls autoSave() (preserves partial conversation on tab switch). configure() called in onAppear.
- ChatHistorySheet: List of sessions with title, date, message count. Swipe-to-delete. Tap to resume. "New Chat" toolbar item. Empty state. Injected as .environmentObject.
- HokieAdvisorApp: @StateObject chatHistory = ChatHistoryStore(), injected into ContentView + OnboardingView.

Session 12 — Codex swipe-to-dismiss keyboard UX:
- Added KeyboardDismissal.swift with UIApplication.dismissKeyboard(), .swipeDownToDismissKeyboard(), and KeyboardDismissHandle.
- ChatView inputBar shows a small non-button drag handle above "Ask a question..." that dismisses keyboard when dragged down.
- Added swipe-down dismissal and .scrollDismissesKeyboard(.interactively) to chat, profile/settings, onboarding prompts, login, transcript, and chat memory editor. This covers text keyboards and number-pad fields like grad year.
- Validation: xcodebuild with DerivedData in /private/tmp reached Swift compilation but failed at existing Hoki.icon actool crash; no Swift diagnostics appeared before that asset failure.

Session 15 — Codex full repository audit:
- Reviewed all project-owned files excluding .git/.venv. Confirmed DARS frontend is still absent: no Swift DARS models, no APIService.uploadDarsAudit, no import/render UI.
- Confirmed chat memory, graph rendering, and YouTube resource cards are implemented.
- Found Supabase catalog sync bug: supabase_catalog_sync._pathway_rows() expects a flat dict, but backend/data/pathways.json is nested as pathways[].sections[].courses[], so pathways_courses would sync as zero rows.
- Found catalog data drift: vt_full_catalog.json has only 2 subjects and no courses/programs/requirements; vt_programs.json is empty. Runtime mostly relies on vt_catalog_202601.json and backend/data/coe/*.json.
- Found repo hygiene/docs drift: root .env is ignored but contains a real OpenAI key (rotate/remove before sharing); .DS_Store files are tracked; README and Settings legal/privacy copy are stale about Hokie Advisor naming, current endpoints, and local-only data claims.
- Validation in audit: Python source py_compile passed with PYTHONPYCACHEPREFIX=/private/tmp; JSON parsed with jq; Xcode project.pbxproj and scheme plist linted; workspace XML and Hoki.icon/icon.json parsed. Full Swift build was not run.

Session 16 — Codex DARS frontend completion:
- Added Swift DARS models in Models.swift, APIService.uploadDarsAudit multipart upload, and DarsAuditViewModel in PlanViewModel.swift.
- DegreeAuditView now leads with "Official Audit" and an "Official DARS / CollegeSource" import card before the local CS fallback audit.
- Added PDF/PNG/JPG file import, official summary/GPA cards, Complete/In Progress/Unfulfilled/Planned category bars, section cards, warnings, replace/clear, and backend-not-ready error state.
- Build validation reached Swift compilation with no Swift diagnostics, then failed at the known Hoki.icon actool crash. git diff --check and project plist lint passed.

Session 17–18 — Supabase production-ish foundation:
- iOS Supabase auth now has hokieadvisor://auth/callback deep link handling, email_redirect_to signup, profile recreation guardrail, Keychain session storage, and real Reset Account via deployed Supabase `account` Edge Function. Dashboard must allow hokieadvisor://auth/callback.
- Supabase `chat` Edge Function is deployed and iOS chat routes to it. Hosted catalog sync was fixed and run; latest sync counts: catalog_subjects 7, catalog_courses 541, pathways_courses 1134, coe_courses 757.

Session 19 — Codex Hokie UX revamp / glass chrome / keyboard polish:
- Active goal: make the app feel original, polished, and clearly VT/Hokie-student-centered, not copied from Apple/ChatGPT/CalAI/other apps. Do not mark complete until all main screens and key states are visually verified.
- Added shared Hokie visual system in ContentView.swift: HokieChrome, glass surfaces, HokiePageHeader, HokieCompactPill, HokieSignalMark/Track, HokieSegmentedControl, HokieIconTile, HokieSheetHeader, HokieAppBackground.
- Home/Audit/Advisor/Profile headers now use unique Hokie page headers with signal mark + monospaced eyebrow + VT burgundy/orange accents. Advisor title is just "Advisor"; Audit main title is just "Audit."
- Floating tab bar made glassier/lowered (`floatingTabBottomPadding = -16`). `setTabWithoutPageTraversal` avoids sliding through intermediate pages when tapping a far tab.
- Native nav/tab black plates reduced with `.transparentNavigationChrome()` and `NavigationBarTransparencyView`; keep testing light/dark mode because header/footer plate artifacts recurred.
- Advisor composer rebuilt as floating glass bar: plus, text field, mic placeholder, burgundy send, attachment chip, Camera/Photos/Files plus menu. Native pickers are wired, but attachment analysis is placeholder UX.
- Advisor prompt overlap fixed: `chatComposerRestingBottom = 54`, `chatMessageRestingBottom = 232`. Last prompt ("What Computer Science courses should I take next semester?") stays visible above composer/footer. Empty-state compact mini title disabled to avoid ghosting over graph preview.
- Keyboard cleanup: user removed keyboardDismissalAccessory. Current app relies on native interactive scroll dismissal, shared swipe-down dismissal, and keyboard visibility tracking. Login/sign-up and chat scroll/push content to avoid keyboard blocking buttons/prompts.
- Login/sign-up now have conventional Sign In / Sign Up tabs, Supabase-backed session behavior, and keyboard-aware scrolling.
- Profile chip clipping fixed by two-row chip layout + scaling; `'29`/PID no longer clip.
- Settings legal/privacy copy now mentions backend services, Supabase, and OpenAI-powered processing.
- DEBUG visual QA: launch with `-HokieVisualQA -HokieInitialTab home|audit|advisor|profile|settings|0|1|2|3`. Audit uses DEBUG-only sample audit in visual QA to avoid local backend connection-error cards.
- Recent QA screenshots: `/tmp/hokie-qa-audit-after-sample.png`, `/tmp/hokie-qa-profile-chip-fix.png`, `/tmp/hokie-qa-advisor-final-this-pass.png`.
- Latest xcodebuild succeeded with simulator destination `05377180-C117-461A-B1E9-5C8CC4FF10D0`, DerivedData `/tmp/HokieAdvisorSimDerivedData`, CODE_SIGNING_ALLOWED=NO.

Session 20 — Codex hosted Transcript/DARS/Audit migration:
- Added Supabase Edge Functions `transcript`, `dars`, `audit`, and `tutoring`, plus shared helper `backend/supabase/functions/_shared/academic.ts`.
- iOS `APIService.swift` now calls Supabase hosted endpoints for transcript upload, DARS upload, degree audit, and tutoring. The old `127.0.0.1:8000` base URL and "Start FastAPI backend on port 8000" user copy are gone.
- Hosted functions preserve existing Swift response contracts: `TranscriptResponse` including `planned_courses`, `DarsAuditResponse`, `DegreeAuditResponse`, and `TutoringResponse`.
- Optional persistence: transcript uploads/courses, DARS audit results, and degree audit results are inserted server-side when a valid user bearer token is present. Service-role key remains only in Supabase/backend code.
- Deployed to project `gcmwrrrspkgawiwisunq`: `chat` v5, `account` v2, `audit` v2, `tutoring` v2, `transcript` v8, `dars` v9 are ACTIVE.
- Supabase function secrets were refreshed from `backend/.env` with `supabase secrets set --env-file ../.env --project-ref gcmwrrrspkgawiwisunq`; reserved `SUPABASE_*` names were skipped by the CLI as expected.
- Smoke tests: `audit` HTTP 200 with synthetic transcript and `CS 1114` grade `T` counted complete; `tutoring` HTTP 200; synthetic transcript PDF HTTP 200 with `courses[]` and `planned_courses[]`; synthetic DARS PDF HTTP 200 with metadata/categories/sections; transcript/DARS unsupported file checks HTTP 415; non-transcript/non-DARS image uploads HTTP 422 parse failures; invalid bearer token HTTP 401.
- Parser hardening: transcript rejects empty parser output, DARS no longer has realistic sample values in the prompt, unreadable/prompt-template DARS output is rejected, and DARS status normalization handles "In Progress" wording.
- Signed-in persistence verified: synthetic confirmed Supabase Auth user signed in with password auth, uploaded synthetic transcript/DARS PDFs with bearer token, and ran hosted audit. Row counts for that user: `transcripts=1`, `transcript_courses=5`, `degree_audits=1`, `dars_audits=1`.
- Validation: `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` succeeded, `git diff --check` passed, and targeted `rg` found no local transcript/DARS/audit/tutoring URL dependency in iOS/Supabase functions.

Session 21 — Codex Advisor entry scroll fix:
- Empty Advisor no longer auto-scrolls to the bottom on `.onAppear`; non-keyboard entry resets to the top so the header stays visible.
- The empty-state bottom scroll is now gated by `isInputFocused && isKeyboardVisible`, preserving the keyboard typing behavior without affecting tab entry/swipe.
- Resting Advisor composer/footer spacing increased by 22pt so the Ask bubble no longer looks attached to the tab bar.
- Validation: simulator Debug build succeeded and dark visual QA screenshot confirmed the Advisor header is visible on entry.

Session 22 — Codex production hardening / user-owned chat data:
- Added `backend/supabase/migrations/004_user_owned_child_integrity.sql` with `(id,user_id)` unique constraints, composite child FKs, and parent-ownership RLS checks for transcript courses and chat messages.
- Added `UserDataSyncService.swift` for authenticated REST/RLS sync of `chat_sessions`, `chat_messages`, and `chat_memories`.
- `ChatHistoryStore` now uses per-user local cache files (`chat_sessions_<userID>.json`, `chat_memories_<userID>.json`) and merges/pushes local user cache with Supabase on auth sync. Anonymous/visual-QA cache remains local only.
- `HokieAdvisorApp` validates/enriches Keychain sessions with `/auth/v1/user` before restore, configures chat sync on restore/deep-link/auth-state changes, and unloads chat data on sign-out.
- `APIService` sends signed-in bearer tokens for chat/stream chat when available.
- `SettingsView.signOut()` clears visible AppState/profile/transcript data and unloads chat memory without deleting the signed-out user's cache; Clear All Data and Reset Account still delete local cache.
- Marked `ChatMessage`, `ChatSession`, and `ChatMemory` nonisolated to remove Swift actor-isolation warnings.
- Validation: `git diff --check`, backend `py_compile`, `find . -name .DS_Store`, tracked secret regex filename check, and simulator `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` all passed. No tracked OpenAI-style secret values found; ignored root `.env` still needs key rotation/removal.

Session 23 — Codex authenticated AppState rehydrate / migration safety:
- Made `004_user_owned_child_integrity.sql` idempotent with `DO $$ if not exists ... $$` constraint creation. Hosted application was not applied: approval reviewer rejected `supabase db push --project-ref gcmwrrrspkgawiwisunq` because remote schema/RLS mutation needs explicit user authorization.
- `UserDataSyncService.fetchStudentSnapshot` now reads user-owned `profiles`, latest `transcripts`, linked `transcript_courses`, latest `degree_audits.response`, and latest `dars_audits.response` through RLS-protected REST. Transcript fetch failures throw instead of clearing local state as if no transcript exists.
- `HokieAdvisorApp` applies the authenticated snapshot into AppStorage/profile settings and AppState on restore/deep link/auth change, reusing the validated session token for chat sync and snapshot fetch.
- `AppState` now has `latestDegreeAudit` and `latestDarsAudit`. `DegreeAuditView` loads cached audit/DARS into the existing view models, skips an unnecessary audit network call when a cached audit was restored, and updates/clears the cache after refresh/upload/clear.
- Transcript upload/reupload and account clearing clear stale cached audit state. `AppState.semesterGroups` no longer force unwraps grouped courses.
- Validation: `git diff --check`, backend `py_compile`, `.DS_Store` check, tracked secret regex check, and simulator `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` all passed.

Session 24 — Codex profile/settings Supabase writeback:
- `UserDataSyncService.upsertProfile` writes profile/settings fields to the authenticated user's `profiles` row through RLS-protected Supabase REST.
- `SettingsView` debounces profile sync when name, grad year, theme, or major context changes, flushes on disappear, and suppresses/cancels sync during sign-out/reset/clear so blank local state is not pushed during account teardown.
- Validation: `git diff --check`, backend `py_compile`, `.DS_Store` check, tracked secret regex check, and simulator `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` all passed.

Session 25 — Codex backend config/docs hardening:
- Added `CORS_ALLOWED_ORIGINS` and changed FastAPI CORS setup so production with no explicit origins does not expose wildcard CORS; development still defaults to common localhost web-dev origins.
- Renamed FastAPI title/root service and legacy chat docstring from Fcounselors to Hokie Advisor.
- Refreshed root `README.md` and `backend/supabase/README.md` for current hosted Edge Functions, Supabase user-owned data, migration `004`, secret handling, and validation. Supabase README no longer says transcript/chat/DARS/audit/tutoring hosting is future work.
- Validation: `git diff --check`, focused backend `py_compile`, `.DS_Store` check, tracked secret regex check, and simulator `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` all passed.

Session 26 — Codex validated session / token refresh hardening:
- `SupabaseAuthService.validatedCurrentSession()` now verifies the access token with `/auth/v1/user` and refreshes through `grant_type=refresh_token` on validation failure, saving refreshed/enriched sessions back to Keychain.
- `APIService.supabaseFunctionHeaders(includeUserSession:)` now uses the validated/refreshed session path before sending user bearer tokens to hosted functions; if validation/refresh is unavailable, calls use anon headers instead of a stale user token.
- Settings profile sync, onboarding profile completion sync, and `ChatHistoryStore.configureForAuthenticatedUser()` now use validated sessions. Chat sync keeps a short-lived validated token cache for the active user to avoid stale-user writes without validating every local save.
- Removed the unused weaker `currentAuthenticatedSession()` helper so new user-scoped code should use `validatedCurrentSession()`.
- Validation: `git diff --check`, `.DS_Store` check, tracked secret regex check, and simulator `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` all passed.

Session 27 — Codex Supabase audit ownership / restore index hardening:
- Extended pending migration `004_user_owned_child_integrity.sql` with `degree_audits(transcript_id,user_id)` → `transcripts(id,user_id)` so a user-owned audit cannot reference another user's transcript UUID. The FK sets only `transcript_id` to null if the transcript is deleted, preserving existing audit-row behavior.
- Replaced the `degree_audits` RLS policy so non-null `transcript_id` must point to a transcript owned by `auth.uid()`; null `transcript_id` remains allowed for hosted audits that are not bound to a transcript row.
- Added user/time indexes for restore and sync queries: transcripts, chat sessions, chat memories, chat messages, degree audits, and DARS audits.
- Updated root `README.md` and `backend/supabase/README.md` to mention degree-audit ownership and restore/sync indexes in migration `004`.
- Validation: `git diff --check`, static migration checks, `.DS_Store` check, and tracked secret regex check all passed. `supabase db lint --local` could not run because local Postgres was unreachable from the sandbox and escalation was rejected; hosted DB was not touched.

Next frontend: final visual QA pass across Home/Audit/Advisor/Profile/login/onboarding/transcript/sheets/keyboard states/light+dark; expandable AuditBucketCard; home screen audit preview; deployment target check; Face ID/Touch ID; dynamic post-audit chips; real-device signed-in persistence QA for profile edits/transcript/audit/DARS/chat sync/sign-out/reset.
Next backend: ask explicit user approval before applying/verifying migration `004_user_owned_child_integrity.sql` on hosted Supabase, test hosted transcript/DARS/audit flows on a physical iPhone with real files, solve official CollegeSource/uAchieve source/API integration with school support, test/tune DARS parser against real exported audit/source output, statistics + theory elective lists, multi-major support, audit context in chat, catalog data refresh, secret cleanup.

VT Burgundy: #861F41. AppStorage keys currently used: onboardingComplete, studentName, vtEmail, vtPID, appPasswordHash, howHeardAboutUs, graduationYear, appearanceMode.
Endpoints: Supabase `/functions/v1/chat` and `/functions/v1/chat/stream` are live for chat. Supabase `/functions/v1/transcript`, `/functions/v1/dars`, `/functions/v1/audit`, and `/functions/v1/tutoring` are deployed and used by iOS. Local FastAPI remains a dev/fallback implementation, not the production iOS target.
```
