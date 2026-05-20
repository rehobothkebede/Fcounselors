# Hokie Advisor — Session Handoff

> Paste the `/compact` block at the bottom into a new Claude Code session to resume with full context.

---

## Current State

App builds and runs. Icon is working. Repo has uncommitted changes (see below). 3 commits ahead of `origin/main` (not pushed).

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
    ChatGPT Image May 18, 2026 at 06_11_07 PM (2).png   ← dark variant
    ChatGPT Image May 18, 2026 at 06_50_02 PM 2.png     ← light variant
```

Xcode 16's `PBXFileSystemSynchronizedRootGroup` picks this up automatically from the source folder. **Do not move, rename, or delete `Hoki.icon`.**

The `Assets.xcassets` was cleared out (old generated AppIcon.appiconset/AccentColor.colorset removed). If Xcode complains about a missing accent color or asset catalog on the next build, recreate a minimal `Assets.xcassets/Contents.json` with `{"info":{"author":"xcode","version":1}}` — no icon set needed there.

---

## What Changed Across Both Sessions

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
| HANDOFF.md | Added mobile chat UI task to next steps; updated current state |
| Cleanup | Removed `appicon/` folder and all Python icon-processing scripts |

---

## Next Steps

### High priority
- [ ] **Mobile-optimized chat UI for advising/tutoring** — redesign `ChatView` for iPhone-first reading: bubble width capped so lines stay short, AI responses broken into multiple short sequential bubbles rather than one long wall of text, minimal vertical scrolling. Must render rich content inline: **Markdown** (bold, italic, lists, blockquotes), **LaTeX** (inline `$…$` and block `$$…$$` math via `LaTeXSwiftUI` or MathJax WKWebView fallback), and **code blocks** with syntax highlighting (e.g. `Splash` or `Highlightr`). Typing indicator (animated dots) while backend streams. Goal: feel closer to Photomath / Wolfram Alpha than a generic chat client.
- [ ] **DARS degree audit system** — parse student transcript against degree requirement buckets (Pathways, major requirements, free electives). Pathways data at `backend/data/pathways.json`. Needs major requirement data structure.
- [ ] **Fix hardcoded "CS '26" badge** in `SettingsView` profile card — use `@AppStorage("graduationYear")` + `@AppStorage("major")`
- [ ] **Xcode display name** — verify "Hokie Advisor" shows correctly in Target → General → Display Name

### Nice to have
- [ ] Backend `/transcript/parse` endpoint — accept DARS/unofficial transcript PDF, return structured completion data
- [ ] PlanView: pull actual major requirements from backend for structured degree-audit context
- [ ] Face ID / Touch ID option for `appPasswordHash` in onboarding

---

## Key Technical Facts

```
Stack:
  iOS:      SwiftUI, Xcode 16, PBXFileSystemSynchronizedRootGroup
            @EnvironmentObject AppState, @AppStorage for persistence
  Backend:  FastAPI + OpenAI, Python, uvicorn

AppStorage keys:
  onboardingComplete, studentName, vtEmail, vtPID, appPasswordHash,
  howHeardAboutUs, graduationYear, appearanceMode, transcriptData, transcriptImported

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
/compact Project: Hokie Advisor — SwiftUI iOS academic advising app for Virginia Tech (formerly Fcounselors). Repo: /Users/rehobothkebede/GitHub/Fcounselors. Xcode 16 project at ios/HokieAdvisor/HokieAdvisor.xcodeproj. Session 1: renamed project, added 6-step onboarding (OnboardingView.swift), login screen (LoginView.swift), fixed dark mode (preferredColorScheme at App level), removed major field from Chat/Settings. Session 2: replaced all icon scripts/PNGs with Hoki.icon (Xcode 16 Icon Composer package at ios/HokieAdvisor/HokieAdvisor/Hoki.icon — DO NOT DELETE). App icon working. Assets.xcassets cleared out. Next: mobile-optimized chat UI with Markdown/LaTeX/code rendering, DARS degree audit, fix hardcoded CS 26 badge. VT Burgundy: #861F41. Bundle ID: com.hokieadvisor.HokieAdvisor. AppStorage keys: onboardingComplete, studentName, vtEmail, vtPID, appPasswordHash, appearanceMode, transcriptData, graduationYear.
```
