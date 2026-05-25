# Hokie Advisor — Session Handoff

> **Two-agent project.** Claude Code owns the iOS frontend (`ios/`). Codex owns the backend (`backend/`).
> This file is the communication channel between them. Both agents read it at session start and update it at session end.
> To brief Codex: paste the `/compact` block. To brief Claude: paste the same block into a new Claude Code session.

---

## Current State

App builds in Xcode. Backend (`uvicorn`) runs locally on port 8000.

**What's fully working end-to-end:**
- Transcript import → AI parse → AppState population → GPA/credits/courses displayed
- Chat streaming (SSE) with transcript context and VT grade rules
- Degree Audit: backend `POST /advisor/audit` returns full bucket breakdown; frontend `DegreeAuditView` renders it
- Backend now treats transfer/awarded credit grades (`T`, `TR`, `TRANSFER`, `P`, `CR`) as completed awarded credit for audit/chat purposes. Example: `CS 1114` with grade `T` satisfies the CS 1114 requirement.
- Backend has a new official-audit ingestion path: `POST /advisor/dars/upload` parses a uAchieve/DARS PDF or screenshot into DARS-shaped categories (`University GPA`, `Minimum Hours`, `Major`, `General Ed`, `In Major GPA`, `Electives`, `Minor(s)`).
- Transcript parser warnings/notes are no longer shown in TranscriptView, but are preserved in `AppState.transcriptNotes` and sent to chat as private LLM context.
- Backend is now prepared for Supabase as the primary persistence stack: env config, service-role REST client, health/status hooks, SQL schema/RLS migration, and a local JSON catalog sync script are in place.

**Known gaps / open work:**
- Statistics elective + CS theory elective approved course lists not in catalog data yet — those two audit buckets stay "open" until data is added
- `TranscriptView` subtitle still says "CS course history" — should be major-agnostic once multi-major support lands
- LaTeX rendering in chat now has lightweight native support for inline `$...$`, `\(...\)`, display `$$...$$`, `\[...\]`, and common matrix environments. It is not a full TeX engine.
- Frontend still needs UI for uploading/importing an official DARS/uAchieve audit report and rendering `DarsAuditResponse`. The screenshot from uachieve.es.cloud.vt.edu is the correct source-of-truth shape.

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

---

## Next Steps

### For Codex (backend)
- [x] **`transcript_notes` in chat stream** — `POST /chat/stream` body includes `transcript_notes: [String]` and backend injects them into the system prompt under "Transcript Parsing Notes" as private context.
- [ ] **DARS parser hardening** — once the user exports a real DARS PDF or screenshot, test `POST /advisor/dars/upload` against it and tune extraction for official section text
- [ ] **Supabase live setup** — create/link the Supabase project, apply `backend/supabase/migrations/001_initial_schema.sql`, set backend env vars, and run `python backend/scripts/sync_catalog_to_supabase.py`
- [ ] **Persist API outputs to Supabase** — after auth/user IDs are wired from iOS, save transcript uploads, chat sessions/messages, chat memories, degree audits, and DARS audits into the new tables
- [ ] **Statistics elective approved list** — add to `computer_science.json` so `statistics_elective` bucket resolves
- [ ] **CS theory elective approved list** — same; `cs_theory_elective` bucket currently always open
- [ ] **Multi-major support** — audit service currently throws `ValueError` for non-CS majors
- [ ] **Audit context in chat** — inject audit bucket summary into `POST /chat/stream` system prompt so the bot can answer "what do I still need?" with live audit data
- [x] **Transfer credit backend semantics** — `T`/`TR` now count as awarded credit in audit and chat context
- [x] **Transcript parser notes to chat** — raw transcript parse warnings are hidden from UI but sent to chat as private context

### For Claude (frontend)
- [ ] **DARS upload/import UI** — allow user to import official uAchieve/DARS PDF or screenshot and call `POST /advisor/dars/upload`; render DARS category bars matching Complete/In Progress/Unfulfilled/Planned (reference: screenshot of uachieve.es.cloud.vt.edu showing pie chart + horizontal category bars)
- [x] **Consume `planned_courses`** — done: `TranscriptResponse.planned_courses`, `AppState.plannedCourses`, `plannedCoursesSection` in TranscriptView, semester-aware active/upcoming split
- [ ] **Expandable `AuditBucketCard`** — tappable to reveal all `matchedCourses` + full `notes` list (currently capped at 4 courses / 1 note)
- [ ] **Home screen audit preview** — inline card showing % complete from last audit (needs audit result accessible outside of `DegreeAuditView`)
- [x] **LaTeX rendering in chat** — lightweight native renderer for inline/display math and common matrix environments. Future upgrade could replace it with full MathJax/KaTeX rendering if needed.
- [x] **Chat history / session save** — sessions auto-saved to Documents/chat_sessions.json on every assistant reply and on tab switch. `ChatHistorySheet` lets users browse, resume, and delete past chats.
- [x] **Swipe down to dismiss keyboard** — shared gesture + native interactive scroll dismissal across chat, profile/settings, onboarding, login, transcript, and chat memory editor. Chat input has a small drag handle above the prompt.
- [ ] **Face ID / Touch ID** for `appPasswordHash`
- [ ] **Dynamic chips post-audit** — after audit loads, surface chips like "Why do I need to retake CS 2114?"

### Done ✓
- [x] Hardcoded "CS '26" badge → dynamic major + grad year badges
- [x] GPA calculation and display (Home, Profile, Transcript)
- [x] Grad year syncs from transcript import AND manual entry
- [x] TranscriptView stuck-in-sheet bug — ✕ dismiss button added
- [x] Degree Audit backend + frontend (fully functional for CS B.S.)
- [x] Semester-aware transcript UI — future registered courses no longer appear as "currently enrolled"; `planned_courses` wired end-to-end

---

## Key Technical Facts

```
Stack:
  iOS:      SwiftUI, Xcode 16, PBXFileSystemSynchronizedRootGroup
            @EnvironmentObject AppState, @AppStorage for persistence
            Targets iOS 17+ (uses .sensoryFeedback, two-param .onChange)
  Backend:  FastAPI + OpenAI, Python 3.11+, uvicorn on port 8000

API endpoints:
  GET  /admin/supabase/status — Supabase config + database reachability check
  POST /advisor/dars/upload — Official DARS/uAchieve audit ingestion
                            Multipart file: PDF/PNG/JPG
                            Returns: DarsAuditResponse
  POST /advisor/audit     — Degree Audit
                            Body: {major, transcript[], in_progress_courses[]}
                            Returns: DegreeAuditResponse (see Models.swift)
  POST /chat/stream       — SSE chat, token-by-token
                            Body may include transcript_notes[] for private LLM context
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

AppStorage keys:
  onboardingComplete, studentName, vtEmail, vtPID, appPasswordHash,
  howHeardAboutUs, graduationYear, appearanceMode, transcriptData, transcriptImported

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
/compact Project: Hokie Advisor — SwiftUI iOS academic advising app for Virginia Tech. Repo: /Users/rehobothkebede/GitHub/Fcounselors. Xcode 16, bundle com.hokieadvisor.HokieAdvisor, iOS 17+.

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
- Verified backend compile. CLI xcodebuild still stops at existing Hoki.icon actool crash before full Swift diagnostics.

Session 11 — Claude chat history:
- ChatMessage is now Codable. New ChatSession struct (Identifiable, Codable) in Models.swift: id, title, date, messages[].
- New ChatHistoryStore.swift: @MainActor ObservableObject, persists sessions to Documents/chat_sessions.json. upsert() inserts/updates sorted newest-first. delete(at:) for swipe-delete. Loads on init.
- ChatViewModel: currentSessionID UUID, configure(store:), autoSave() (strips isStreaming), loadSession() (auto-saves current first), clearConversation() (saves before clearing, mints new sessionID). sendMessage() calls autoSave() after each successful stream.
- ChatView: @EnvironmentObject chatHistory. Header has clock.arrow.circlepath button → ChatHistorySheet. Pencil/compose button replaces trash (saves + starts new). onDisappear calls autoSave() (preserves partial conversation on tab switch). configure() called in onAppear.
- ChatHistorySheet: List of sessions with title, date, message count. Swipe-to-delete. Tap to resume. "New Chat" toolbar item. Empty state. Injected as .environmentObject.
- HokieAdvisorApp: @StateObject chatHistory = ChatHistoryStore(), injected into ContentView + OnboardingView.

Session 12 — Codex swipe-to-dismiss keyboard UX:
- Added KeyboardDismissal.swift with UIApplication.dismissKeyboard(), .swipeDownToDismissKeyboard(), and KeyboardDismissHandle.
- ChatView inputBar shows a small non-button drag handle above "Ask a question..." that dismisses keyboard when dragged down.
- Added swipe-down dismissal and .scrollDismissesKeyboard(.interactively) to chat, profile/settings, onboarding prompts, login, transcript, and chat memory editor. This covers text keyboards and number-pad fields like grad year.
- Validation: xcodebuild with DerivedData in /private/tmp reached Swift compilation but failed at existing Hoki.icon actool crash; no Swift diagnostics appeared before that asset failure.

Next for Claude: DARS import UI + DARS category bar rendering, expandable AuditBucketCard, home screen audit preview.
Next for Codex: test/tune DARS parser against real exported audit, statistics + theory elective course lists, multi-major support, audit context in chat.

VT Burgundy: #861F41. AppStorage keys: onboardingComplete, studentName, vtEmail, vtPID, appPasswordHash, howHeardAboutUs, graduationYear, appearanceMode, transcriptData, transcriptImported.
Endpoints: POST /advisor/dars/upload (official DARS import), POST /advisor/audit (local CS fallback), POST /chat/stream, POST /transcript/upload.
```
