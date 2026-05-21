# Hokie Advisor — Session Handoff

> Paste the `/compact` block at the bottom into a new Claude Code session to resume with full context.

---

## Current State

App builds and runs. Icon is working. Repo has uncommitted changes (not pushed).

```
37b618e  fix app icon crops — remove dark header border, clean panel edges
97bbe52  Update app icons to HA design from ChatGPT reference sheet
1d44883  Rename project from Fcounselors to Hokie Advisor
```

---

## App Icon — Final Working Setup

The app icon is an **Xcode 16 Icon Composer** package named `Hoki.icon`, located at:

```
ios/HokieAdvisor/HokieAdvisor/Hoki.icon/
  icon.json
  Assets/
    AppIcon-Light.png   ← light variant (opacity → 0 in dark mode)
    AppIcon-Dark.png    ← dark variant  (fill removed in dark mode, opacity 1 always)
```

`icon.json` `image-name` and `name` fields reference `AppIcon-Light` / `AppIcon-Dark` exactly.
Xcode 16's `PBXFileSystemSynchronizedRootGroup` picks this up automatically. **Do not move, rename, or delete `Hoki.icon`.**

The `Assets.xcassets` was cleared out (old AppIcon.appiconset/AccentColor.colorset removed). If Xcode complains, recreate a minimal `Assets.xcassets/Contents.json` with `{"info":{"author":"xcode","version":1}}`.

---

## What Changed Across All Sessions

### Session 1
| Change | Detail |
|---|---|
| Project rename | Fcounselors → Hokie Advisor; bundle ID `com.hokieadvisor.HokieAdvisor` |
| OnboardingView.swift | 6-step first-launch flow: name → VT email → password → how-heard → transcript → done |
| LoginView.swift | Return-launch password screen with shake animation |
| HokieAdvisorApp.swift | Dark mode fix at window level via `@AppStorage("appearanceMode")` |
| ChatView.swift | Removed major field capsule from header |
| SettingsView.swift | "Profile" nav title; VT email/PID badge; Transcript + Danger sections |
| HomeView.swift | Stats locked gray until transcript loaded; nudge card routes to Profile tab |

### Session 2
| Change | Detail |
|---|---|
| App icon | Replaced all previous icon scripts/PNGs with `Hoki.icon` (Icon Composer package) |
| Cleanup | Removed `appicon/` folder and all Python icon-processing scripts |

### Session 3
| Change | Detail |
|---|---|
| `vt_minors_scraper.py` | New scraper at `backend/scraper/vt_minors_scraper.py` — scrapes all 158 VT undergraduate minors |
| `vt_minors.jsonl` | Output at `backend/data/vt_minors.jsonl` — 158 lines, one JSON object per minor |
| Codex plugin | OpenAI Codex CLI plugin installed in Claude Code |

### Session 4
| Change | Detail |
|---|---|
| Appearance system rewrite | `WindowAppearanceSetter` (UIViewRepresentable) sets `window.overrideUserInterfaceStyle` directly |
| Appearance onboarding step | Step 5 "Pick your look" added — System / Light / Dark cards, live preview |
| Email step — PID-only | User types PID, `@vt.edu` is a static suffix; full email assembled before saving |
| Password required | No skip; Continue requires matching passwords ≥6 chars |
| Done step — transcript nudge | "Almost there!" + import nudge if no transcript; "You're all set!" if imported |
| Grad year auto-inferred | `TranscriptView` calculates grad year = earliest semester year + 4 after parse |

### Session 5
| Change | Detail |
|---|---|
| **Chat streaming (SSE)** | Backend: `POST /chat/stream` yields `data: "token"\n\n` SSE events via OpenAI `stream=True`. iOS: `APIService.streamChat()` uses `URLSession.bytes(for:)` + `AsyncThrowingStream`. `ChatViewModel` appends a live message and grows it token by token. Typing indicator shows until first token, then streaming cursor takes over. |
| **Streaming cursor** | `StreamingCursor` — burgundy blinking `\|` bar shown below AI bubble while streaming; disappears when done. |
| **Scroll-on-token** | `messageList` now has `onChange(of: vm.messages.last?.content)` so the view auto-scrolls on every token during streaming. |
| **Code block rendering** | New file `CodeBlockView.swift`. `MarkdownBody` parser now detects fenced code blocks (` ``` `). Code renders in a dark terminal-style card: language dot + label, horizontal scroll, Copy button, `SyntaxHighlighter` colors keywords/types/strings/comments/numbers in VS Code Dark+ palette. Languages: C, C++, Python, Java, Swift, JS, TS, Bash + generic fallback. |
| **Assistant bubble width** | Removed right `Spacer(minLength: 60)` from `MessageBubble` so AI responses use the full available width — important for code blocks. |
| **Tab bar overlap fix** | Removed `.ignoresSafeArea(.keyboard)` from `ContentView` ZStack. Added `.padding(.bottom, 90)` to content Group so the floating tab bar never covers input fields. Keyboard now properly pushes content up on all tabs. Reduced `PlanView` spacer from 110 → 20. |
| **Icon files renamed** | `ChatGPT Image May 18…PM (2).png` → `AppIcon-Dark.png`; `ChatGPT Image May 18…PM 2.png` → `AppIcon-Light.png`. `icon.json` updated to match. |
| **Transcript-aware chatbot** | `computer_science.json` loaded at backend startup into `_CS_REQUIREMENTS_CONTEXT` (grade cutoffs, prereqs, full 4-year sequence). `_build_student_context()` annotates each transcript course: `✓ satisfies C-or-better requirement` or `✗ MUST RETAKE`. iOS `ChatRequest` now sends `transcript[]` + `in_progress_courses[]`. `ChatViewModel` syncs from `AppState` on appear/change. |
| **Authoritative system prompt** | Bot is explicitly instructed: never say "check yourself / Hokie SPA / your advisor." Answer YES/NO first, then explain using the student's actual grades. |
| **VT grade rules baked in** | "C or better" at VT = plain C (2.0 GPA) minimum. C- (1.7) does **not** satisfy it. System prompt and transcript annotator both enforce this. Courses with no cutoff (MATH 2114, etc.) are listed explicitly — bot says "a D is passing here" instead of implying retake. |

---

## Next Steps

### High priority
- [ ] **DARS degree audit system** — parse student transcript against degree requirement buckets (Pathways, major requirements, free electives). Pathways data at `backend/data/pathways.json`.
- [ ] **Fix hardcoded "CS '26" badge** in `SettingsView` profile card — use `@AppStorage("graduationYear")` + `@AppStorage("major")`
- [ ] **Xcode display name** — verify "Hokie Advisor" shows correctly in Target → General → Display Name

### Nice to have
- [ ] Backend `/transcript/parse` endpoint — accept DARS/unofficial transcript PDF, return structured data
- [ ] LaTeX rendering in chat — inline `$…$` and block `$$…$$` math (MathJax WKWebView or LaTeXSwiftUI)
- [ ] Face ID / Touch ID option for `appPasswordHash` in onboarding
- [ ] PlanView: pull actual major requirements from backend for structured degree-audit context

---

## Key Technical Facts

```
Stack:
  iOS:      SwiftUI, Xcode 16, PBXFileSystemSynchronizedRootGroup
            @EnvironmentObject AppState, @AppStorage for persistence
  Backend:  FastAPI + OpenAI, Python, uvicorn

Chat system:
  POST /chat/stream  — SSE, token-by-token, consumed by URLSession.bytes(for:)
  POST /chat         — legacy non-streaming fallback
  Each request includes: messages[], major, transcript[], in_progress_courses[]
  Backend injects: CS requirements from computer_science.json + student transcript context

AppStorage keys:
  onboardingComplete, studentName, vtEmail, vtPID, appPasswordHash,
  howHeardAboutUs, graduationYear, appearanceMode, transcriptData, transcriptImported

Appearance:
  WindowAppearanceSetter (UIViewRepresentable) in HokieAdvisorApp.swift
  sets window.overrideUserInterfaceStyle on every render + onChange.
  Values: "system" → .unspecified, "light" → .light, "dark" → .dark

Onboarding steps (7 total):
  0: Welcome  1: Name  2: Email (PID-only, @vt.edu suffix shown)  3: Password (required)
  4: How Heard  5: Appearance picker  6: Transcript  7: Done

VT grade rules (baked into backend system prompt):
  "C or better" = plain C (2.0 GPA) minimum; C- (1.7) does NOT satisfy it
  Courses with no cutoff: MATH 2114, MATH 1225/1226/2204/2534/3134, ENGL, ENGE, and all electives

Backend data files:
  backend/data/catalog/computer_science.json  ← CS 4-year plan, prereqs, grade cutoffs
  backend/data/pathways.json                  ← Gen Ed pathways data
  backend/data/coe/CS.json                    ← COE course catalog for CS
  backend/data/vt_minors.jsonl                ← 158 VT minors (scraped)

VT Burgundy:  Color(red: 0.525, green: 0.122, blue: 0.255)  /  #861F41
Bundle ID:    com.hokieadvisor.HokieAdvisor
Xcode dir:    ios/HokieAdvisor/HokieAdvisor/
Icon:         ios/HokieAdvisor/HokieAdvisor/Hoki.icon  ← DO NOT TOUCH

PBXFileSystemSynchronizedRootGroup: Xcode 16 auto-discovers all files in
HokieAdvisor/ — new .swift files and .icon packages appear automatically.

SourceKit cross-file errors in editor are NOT real build errors.
Always compile in Xcode to see actual diagnostics.
```

---

## /compact

```
/compact Project: Hokie Advisor — SwiftUI iOS academic advising app for Virginia Tech (formerly Fcounselors). Repo: /Users/rehobothkebede/GitHub/Fcounselors. Xcode 16 project at ios/HokieAdvisor/HokieAdvisor.xcodeproj.

Session 1: renamed project, added 7-step onboarding (OnboardingView.swift), login screen (LoginView.swift), fixed dark mode with WindowAppearanceSetter, removed major field from Chat/Settings.
Session 2: replaced all icon scripts/PNGs with Hoki.icon (Xcode 16 Icon Composer at ios/HokieAdvisor/HokieAdvisor/Hoki.icon — DO NOT DELETE). Assets.xcassets cleared. Icons now named AppIcon-Light.png and AppIcon-Dark.png inside Hoki.icon/Assets/.
Session 3: vt_minors_scraper.py → backend/data/vt_minors.jsonl (158 minors). OpenAI Codex plugin installed.
Session 4: Appearance system rewrite (WindowAppearanceSetter), PID-only email step, password required, transcript nudge on Done step, grad year auto-inferred from transcript.
Session 5:
- Chat streaming: POST /chat/stream SSE endpoint (OpenAI stream=True). iOS APIService.streamChat() via URLSession.bytes. ChatViewModel streams tokens into live message. Typing indicator → streaming burgundy cursor → done.
- Code blocks: CodeBlockView.swift (new file). MarkdownBody parses fenced code blocks. Dark terminal card with language dot, Copy button, SyntaxHighlighter (VS Code Dark+ palette) for C/C++/Python/Java/Swift/JS/TS/Bash.
- Tab bar fix: removed .ignoresSafeArea(.keyboard) from ContentView ZStack, added .padding(.bottom, 90) to content group. Keyboard now pushes input bar up properly.
- Icon rename: ChatGPT Image filenames → AppIcon-Light.png / AppIcon-Dark.png. icon.json updated.
- Transcript-aware chatbot: backend loads computer_science.json at startup (grade cutoffs, prereqs, 4-year sequence). Every ChatRequest now sends transcript[] + in_progress_courses[]. _build_student_context() annotates each course. Bot answers YES/NO first, never says "check yourself." VT grade rule: C- (1.7 GPA) does NOT satisfy "C or better" — plain C (2.0) is the minimum.

Next: DARS degree audit, fix hardcoded CS '26 badge in SettingsView, LaTeX rendering in chat.
VT Burgundy: #861F41. Bundle ID: com.hokieadvisor.HokieAdvisor.
AppStorage keys: onboardingComplete, studentName, vtEmail, vtPID, appPasswordHash, howHeardAboutUs, graduationYear, appearanceMode, transcriptData, transcriptImported.
Backend chat endpoint: POST /chat/stream (primary), POST /chat (fallback). Payload: {messages, major, transcript[], in_progress_courses[]}.
```
