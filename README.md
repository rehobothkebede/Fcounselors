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

### 4. Run the test script

```bash
python test_api.py
```

---

## API Endpoints

### Health
```
GET /health
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
  ]
}
```
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

## Project Structure

```
backend/
├── app/
│   ├── main.py            # FastAPI app, routers, CORS
│   ├── config.py          # Central config (model, API key, paths)
│   ├── routes/
│   │   ├── chat.py        # POST /chat
│   │   ├── advisor.py     # POST /advisor/plan
│   │   └── courses.py     # GET /courses/*
│   └── services/
│       ├── ai_service.py  # OpenAI integration with retry logic
│       └── scraper_service.py  # VT Timetable API + caching
├── data/courses/          # Cached course JSON files
├── requirements.txt
├── .env                   # Your secrets (not committed)
├── .env.example           # Template
├── run.py                 # Alternative: python run.py
└── test_api.py            # Integration test script
```

---

## Configuration

All model and environment settings live in `backend/.env`:

```
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-5.4-nano   # Change model here — affects the entire app
APP_ENV=development
```

---

## Vision

Fcounselors aims to build an intelligent advising companion that helps students navigate their academic journey with clarity, confidence, and autonomy.

**Current focus:** Virginia Tech pilot using publicly available course data.

**Long-term goal:** Combine human mentorship, intelligent automation, and student-owned academic strategy to rethink how students receive academic guidance.

---

## Status

Active development — backend API layer complete.  
Next: iOS app integration via Swift/Xcode.

---

## Contributors

Student-led initiative. Open to collaboration, feedback, and experimentation.
