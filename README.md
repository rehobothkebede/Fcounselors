# Fcounselors

Reimagining academic advising through personalization, accessibility, and intelligent systems.

---

## Quick Start

### 1. Set up environment

```bash
cd backend
python -m venv .venv
source .venv/bin/activate       # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Configure API key

```bash
cp .env.example .env
# Edit .env and set your OpenAI API key:
# OPENAI_API_KEY=sk-...
```

### 3. Run the server

```bash
uvicorn app.main:app --reload
```

Server starts at `http://localhost:8000`  
Interactive docs at `http://localhost:8000/docs`

---

## API Endpoints

### Health
```
GET /health
GET /
```
Returns `{"status": "ok"}`

---

### Chat with advisor
```
POST /chat
```
```json
{
  "messages": [
    {"role": "user", "content": "What CS courses should I take sophomore year?"}
  ],
  "major": "Computer Science"
}
```
- `messages`: full conversation history (supports multi-turn)
- `major` *(optional)*: injects the department's course catalog into the AI's context (e.g. `"CS"`, `"ECE"`, `"Computer Science"`)

Returns:
```json
{"reply": "..."}
```

---

### Get personalized course plan
```
POST /advisor/plan
```
```json
{
  "completed_courses": ["CS 1114", "MATH 1225"],
  "major": "Computer Science",
  "constraints": ["light workload", "internship focus"]
}
```
Returns:
```json
{
  "recommended_courses": [
    {"code": "CS 2114", "name": "Software Design and Data Structures", "reason": "..."}
  ],
  "reasoning": "Based on your completed coursework...",
  "warnings": ["Verify prerequisites with your degree audit."]
}
```

---

### Course data (VT Timetable)
```
GET /courses/{subject}?year_term=202601&refresh=false
```
Examples: `GET /courses/CS`, `GET /courses/MATH`

Returns cached course data or scrapes live from VT's timetable API.
Falls back to cache if the VT API is unreachable.

```
GET /courses/subjects
```
Lists all locally cached subjects.

---

### Admin — COE course catalog

```
POST /admin/seed-coe
```
Writes a COE subject JSON file to disk (`data/coe/{SUBJECT}.json`). Used by deployment scripts to push scraped catalog data to the server.

```json
{
  "subject": "CS",
  "data": {"courses": [...]}
}
```

```
GET /admin/seed-coe/status
```
Returns which COE subjects are currently on disk and their course counts.

---

## Supported COE Majors

The `/chat` endpoint accepts a `major` field to inject department course data. Supported majors/aliases:

| Alias | Full Name |
|---|---|
| `CS`, `Computer Science` | Computer Science |
| `ECE`, `Electrical Engineering` | Electrical and Computer Engineering |
| `ME`, `Mechanical Engineering` | Mechanical Engineering |
| `AOE`, `Aerospace Engineering` | Aerospace Engineering |
| `ISE`, `Industrial Engineering` | Industrial and Systems Engineering |
| `BMES`, `BME`, `Biomedical Engineering` | Biomedical Engineering |
| `CEE`, `Civil Engineering` | Civil and Environmental Engineering |
| `CHE`, `Chemical Engineering` | Chemical Engineering |
| `ESM`, `Engineering Science` | Engineering Science and Mechanics |
| `ENGE`, `Engineering Education` | Engineering Education |
| `ENGR`, `General Engineering` | General Engineering |
| `MINE`, `Mining Engineering` | Mining Engineering |
| `MSE`, `Materials Science` | Materials Science and Engineering |
| `BSE`, `Biosystems Engineering` | Biosystems Engineering |

---

## Project Structure

```
backend/
├── app/
│   ├── main.py            # FastAPI app, routers, CORS
│   ├── config.py          # Central config (model, API key, paths)
│   ├── routes/
│   │   ├── chat.py        # POST /chat — AI advisor with optional COE context
│   │   ├── advisor.py     # POST /advisor/plan — personalized course plan
│   │   ├── courses.py     # GET /courses/* — VT Timetable scraper
│   │   └── admin.py       # POST /admin/seed-coe — COE catalog management
│   └── services/
│       ├── ai_service.py       # OpenAI integration with retry logic
│       ├── coe_service.py      # COE course catalog loader + major name resolver
│       └── scraper_service.py  # VT Timetable API + caching
├── data/
│   ├── courses/           # Cached VT Timetable course JSON files
│   └── coe/               # COE department course catalog JSON files
├── requirements.txt
├── .env                   # Your secrets (not committed)
└── run.py                 # Alternative: python run.py

ios/Fcounselors/
└── Fcounselors/
    ├── FcounselorsApp.swift   # App entry point
    ├── ContentView.swift      # Root view + navigation
    ├── ChatView.swift         # AI advisor chat UI
    ├── ChatViewModel.swift    # Chat state + API calls
    ├── PlanViewModel.swift    # Course plan state
    ├── APIService.swift       # Backend API client
    └── Models.swift           # Shared data models
```

---

## Configuration

All model and environment settings live in `backend/.env`:

```
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini   # Change model here — affects the entire app
APP_ENV=development
```

---

## Vision

Fcounselors aims to build an intelligent advising companion that helps students navigate their academic journey with clarity, confidence, and autonomy.

**Current focus:** Virginia Tech pilot using publicly available course data.

**Long-term goal:** Combine human mentorship, intelligent automation, and student-owned academic strategy to rethink how students receive academic guidance.

---

## Patch Notes

### 5/15/26

**UI Overhaul: Glassmorphism Design**
- Replaced all solid white/gray card backgrounds with `.ultraThinMaterial` glass panels across Transcript, Plan, and Chat views
- Added a warm-to-cool gradient page background (VT Burgundy → lavender → sky) so glass cards actually refract color
- All cards now have a directional white-gradient border stroke and soft accent-tinted shadows
- Input fields, suggestion chips, chat bubbles, and the typing indicator all updated to match the glass system
- Added a reusable `GlassCard` modifier and `LinearGradient.vtBackground` to the design system for consistent use going forward
- Fixed a crash (`Thread 1: signal SIGTERM`) caused by `AnyShapeStyle` usage which requires iOS 17+ — replaced with a `@ViewBuilder` approach that works on iOS 15+

**Pathways Data**
- Parsed both VT Pathways PDFs (at-a-glance guide + full alphabetical guide) using `pdfplumber`
- Generated `backend/data/pathways.json` with all 880 courses organized by pathway concept and subsection:
  - Pathway 1 (Discourse): 1f Foundational / 1a Advanced-Applied
  - Pathway 2 (Critical Thinking in the Humanities)
  - Pathway 3 (Reasoning in the Social Sciences)
  - Pathway 4 (Reasoning in the Natural Sciences)
  - Pathway 5 (Quantitative & Computational Thinking): 5f / 5a
  - Pathway 6 (Design and the Arts): 6a Arts / 6d Design
  - Pathway 7 (Critical Analysis of Identity & Equity in the US)
- Each course entry includes: course code, name, prerequisites (cleaned), crosslists, Pathways minor affiliations, and double-count flags
- Parser script saved to `backend/scripts/parse_pathways.py` for re-use

---

## Status

Active development — backend API and iOS app in progress.

- Backend: FastAPI with OpenAI integration, VT course scraper, COE catalog context injection, Pathways data
- iOS: SwiftUI app with glassmorphism UI connected to the backend

---

## Contributors

Student-led initiative. Open to collaboration, feedback, and experimentation.
