from __future__ import annotations

import json
import os
import time
import logging
from openai import OpenAI, APIError, RateLimitError, APITimeoutError
from app.config import OPENAI_API_KEY, OPENAI_MODEL

logger = logging.getLogger(__name__)

client = OpenAI(api_key=OPENAI_API_KEY)

# ---------------------------------------------------------------------------
# Load CS degree requirements once at startup so every chat has full context
# ---------------------------------------------------------------------------

def _load_cs_requirements_context() -> str:
    """Parse computer_science.json and produce a compact, advisor-ready summary."""
    data_path = os.path.join(os.path.dirname(__file__), "../../data/catalog/computer_science.json")
    try:
        with open(data_path) as f:
            data = json.load(f)
    except Exception as e:
        logger.warning("Could not load CS requirements JSON: %s", e)
        return ""

    lines = [
        f"CS B.S. DEGREE REQUIREMENTS ({data.get('catalog_year','2025-2026')}, "
        f"{data.get('total_credits',123)} total credits required):",
        "",
        "COURSES REQUIRING C OR BETTER (C- does NOT count at VT — must earn plain C or above):",
    ]

    grade_req_codes: set[str] = set()
    all_courses: list[dict] = []

    for yr in data.get("four_year_plan", []):
        for sem in ("fall", "spring"):
            for c in yr.get(sem, {}).get("courses", []):
                if c.get("code") == "ELEC":
                    continue
                all_courses.append({**c, "year": yr.get("year"), "sem": sem})
                if c.get("grade_required"):
                    grade_req_codes.add(c["code"])
                    prereqs = ", ".join(c.get("prerequisites", [])) or "none"
                    lines.append(
                        f"  • {c['code']} ({c.get('name','')}) — "
                        f"requires {c['grade_required']}+  |  prereqs: {prereqs}"
                    )

    lines += [
        "",
        "COURSES WITH NO GRADE CUTOFF IN CS CURRICULUM (a D is passing for degree purposes):",
        "  MATH 2114, MATH 1225, MATH 1226, MATH 2204, MATH 2534, MATH 3134,",
        "  ENGL 1105, ENGL 1106, ENGE 1215, ENGE 1216, ENGE 3900,",
        "  CS 3304, CS 3214, CS 3604, CS 4094, CS 4944, CS 1944, and all electives.",
        "",
        "FULL REQUIRED SEQUENCE WITH PREREQUISITES:",
    ]

    seen: set[str] = set()
    for c in all_courses:
        if c["code"] in seen:
            continue
        seen.add(c["code"])
        prereqs = ", ".join(c.get("prerequisites", [])) or "none"
        grade_note = f"  ← MUST earn {c['grade_required']}+" if c.get("grade_required") else ""
        lines.append(
            f"  Yr{c['year']} {c['sem'].capitalize()[:2]}: {c['code']} "
            f"({c.get('name','')}, {c.get('credits','?')} cr)  prereqs: {prereqs}{grade_note}"
        )

    lines += ["", f"Notes: {data.get('notes','')}"]
    return "\n".join(lines)


_CS_REQUIREMENTS_CONTEXT = _load_cs_requirements_context()

# Grade codes that require C or better in the CS curriculum (derived from JSON above)
_GRADE_REQUIRED_CODES = {"CS 1114", "CS 2114", "CS 2104", "CS 2505", "CS 2506", "CS 3114"}

_BASE_SYSTEM_PROMPT = f"""You are Hokie Advisor — a personalized AI academic advisor for Virginia Tech \
Computer Science students (B.S. CS, 2025-2026 catalog, 123 total credits).

══════════════════════════════════════════
PRIME DIRECTIVE — YOU ARE THE ADVISOR
══════════════════════════════════════════
You have the student's complete transcript with real grades AND the full CS degree requirements \
below. NEVER say "check your transcript," "verify on Hokie SPA," "consult your advisor," or \
"you should look that up." YOU look it up and tell them definitively. If they ask "am I fine?" \
answer YES or NO first, then explain why using their actual grades.

GRADE RULING RULES (apply automatically when you have the transcript):
• "C or better" at VT means a plain C (2.0 GPA points) or higher. C- (1.7) does NOT count.
• Core course requires C or better AND student earned C, B, or A (any +/−) → FINE, say so.
• Core course requires C or better AND student earned C-, D, F, or W → MUST RETAKE before \
  progressing; say this directly.
• Course with NO grade cutoff → any passing grade (D or above) satisfies the degree requirement. \
  Do not imply they need to retake it unless GPA, a downstream prerequisite, or grad school \
  makes it relevant — and name that reason explicitly.
• Always state the ruling first ("Yes, you're fine" / "No, you need to retake this"), then explain.

══════════════════════════════════════════
OPERATING MODES
══════════════════════════════════════════

TUTOR MODE — when a student asks about course material, concepts, or debugging:
• Break down concepts with examples and analogies tailored to CS students
• Ask Socratic follow-up questions to check understanding
• Reference specific VT course numbers when relevant
• Guide toward the answer; never just hand over homework solutions

ADVISOR MODE — when a student asks about their degree plan, scheduling, or grades:
• Cross-reference their transcript (provided below each session) with the requirements
• State exactly which required courses they have left, which they have satisfied, and why
• Check prerequisites before recommending any course
• Balance credit load (12–18 cr/semester; CS plan averages 15–16 cr)
• Flag prerequisite gaps and risky grade situations explicitly by course code
• Mention career relevance (SWE internships, research, grad school) when helpful

COMMON SUBSTITUTIONS: ECE 2514 → CS 1114 | ECE 3514 → CS 2114 | ECE 2564 → CS 2505 | \
CS 2064 → CS 1114

Never fabricate requirements. Be concise — use bullet points and short paragraphs.

══════════════════════════════════════════
CS DEGREE REQUIREMENTS (always in context)
══════════════════════════════════════════
{_CS_REQUIREMENTS_CONTEXT}"""


def _build_student_context(transcript: list[dict], in_progress_courses: list[str]) -> str:
    """Build a personalized, advisor-readable context block from the student's transcript."""
    if not transcript and not in_progress_courses:
        return ""

    lines = [
        "══════════════════════════════════════════",
        "THIS STUDENT'S TRANSCRIPT (use this — do not ask them to check it)",
        "══════════════════════════════════════════",
    ]

    completed_cs_core: list[str] = []
    remaining_cs_core = list(_GRADE_REQUIRED_CODES)

    for entry in transcript:
        code  = entry.get("code", "")
        name  = entry.get("name", "") or ""
        grade = entry.get("grade") or "N/A"
        sem   = entry.get("semester") or ""
        sem_str = f" [{sem}]" if sem else ""

        if code in _GRADE_REQUIRED_CODES:
            # VT "C or better" = 2.0 GPA points minimum; C- (1.7) does NOT satisfy it
            grade_status = ""
            if grade in ("A+", "A", "A-", "B+", "B", "B-", "C+", "C"):
                grade_status = " ✓ satisfies C-or-better requirement"
                if code in remaining_cs_core:
                    remaining_cs_core.remove(code)
                    completed_cs_core.append(f"{code}({grade})")
            elif grade in ("C-", "D+", "D", "D-", "F", "W", "WF"):
                grade_status = " ✗ MUST RETAKE — C- and below do not satisfy VT's C-or-better rule"
        else:
            grade_status = " (no grade cutoff for this course in the CS curriculum)"

        lines.append(f"  {code} — {name}: Grade {grade}{sem_str}{grade_status}")

    if in_progress_courses:
        lines.append("")
        lines.append("CURRENTLY ENROLLED:")
        for c in in_progress_courses:
            lines.append(f"  {c}")

    lines.append("")
    if completed_cs_core:
        lines.append(f"CS CORE COMPLETED: {', '.join(completed_cs_core)}")
    if remaining_cs_core:
        lines.append(f"CS CORE STILL NEEDED: {', '.join(remaining_cs_core)}")

    total_credits = sum(
        (entry.get("credits") or 0) for entry in transcript
        if entry.get("grade") not in ("W", "WF", "F", None)
    )
    lines.append(f"CREDITS COMPLETED (approx): {total_credits:.0f} / 123")
    lines.append("══════════════════════════════════════════")

    return "\n".join(lines)


def _build_system_prompt(course_context: str = "", student_context: str = "") -> str:
    parts = [_BASE_SYSTEM_PROMPT]
    if student_context:
        parts.append(student_context)
    if course_context:
        parts.append(f"\nDEPARTMENT COURSE CATALOG FOR THIS MAJOR:\n{course_context}")
    return "\n\n".join(parts)


def _call_with_retry(fn, retries: int = 3, backoff: float = 1.5):
    """Call fn(), retrying on transient OpenAI errors with exponential backoff."""
    last_error = None
    for attempt in range(retries):
        try:
            return fn()
        except RateLimitError as e:
            last_error = e
            wait = backoff ** attempt
            logger.warning("Rate limited by OpenAI, retrying in %.1fs (attempt %d/%d)", wait, attempt + 1, retries)
            time.sleep(wait)
        except APITimeoutError as e:
            last_error = e
            wait = backoff ** attempt
            logger.warning("OpenAI timeout, retrying in %.1fs (attempt %d/%d)", wait, attempt + 1, retries)
            time.sleep(wait)
        except APIError as e:
            # Non-transient API error — don't retry
            raise RuntimeError(f"OpenAI API error: {e}") from e
    raise RuntimeError(f"OpenAI call failed after {retries} attempts: {last_error}") from last_error


def chat_stream_with_advisor(
    messages: list,
    course_context: str = "",
    transcript: list[dict] | None = None,
    in_progress_courses: list[str] | None = None,
):
    """Stream a chat response token by token as SSE events."""
    student_ctx = _build_student_context(transcript or [], in_progress_courses or [])
    system_prompt = _build_system_prompt(course_context, student_ctx)
    full_messages = [{"role": "system", "content": system_prompt}] + messages

    stream = client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=full_messages,
        temperature=0.7,
        max_completion_tokens=1500,
        stream=True,
    )
    for chunk in stream:
        delta = chunk.choices[0].delta
        if delta.content:
            yield f"data: {json.dumps(delta.content)}\n\n"
    yield "data: [DONE]\n\n"


def chat_with_advisor(
    messages: list,
    course_context: str = "",
    transcript: list[dict] | None = None,
    in_progress_courses: list[str] | None = None,
) -> str:
    """Send a conversation to the AI advisor and return the full response."""
    student_ctx = _build_student_context(transcript or [], in_progress_courses or [])
    system_prompt = _build_system_prompt(course_context, student_ctx)
    full_messages = [{"role": "system", "content": system_prompt}] + messages

    def _call():
        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=full_messages,
            temperature=0.7,
            max_completion_tokens=1500,
        )
        return response.choices[0].message.content

    return _call_with_retry(_call)


def _build_plan_context(major_requirements: dict) -> str:
    """Format four_year_plan, elective_categories, and substitutions into a compact prompt string."""
    parts = []

    plan = major_requirements.get("four_year_plan", [])
    if plan:
        lines = ["4-year CS sequence (* = C or better required):"]
        for yr in plan:
            y = yr.get("year")
            for sem in ("fall", "spring"):
                sem_data = yr.get(sem, {})
                courses = [c for c in sem_data.get("courses", []) if c.get("code") != "ELEC"]
                if courses:
                    labels = [
                        f"{c['code']}*" if c.get("grade_required") == "C" else c["code"]
                        for c in courses
                    ]
                    lines.append(f"  Y{y} {sem.capitalize()[:2]}: {', '.join(labels)} ({sem_data.get('total_credits', '?')}cr)")
        parts.append("\n".join(lines))

    electives = major_requirements.get("elective_categories", {})
    if electives:
        lines = ["CS elective requirements:"]
        for key, cat in electives.items():
            name = key.replace("_", " ").title()
            desc = cat.get("description", "")
            options = cat.get("options", [])
            line = f"  {name}: {desc}"
            if options:
                if isinstance(options[0], dict) and "code" in options[0]:
                    line += f" Options: {', '.join(o['code'] for o in options)}"
                elif isinstance(options[0], dict) and "group" in options[0]:
                    line += f" Choose: {' or '.join(o['group'] for o in options)}"
            lines.append(line)
        parts.append("\n".join(lines))

    subs = major_requirements.get("substitutions", [])
    if subs:
        lines = ["Approved substitutions:"]
        for s in subs:
            lines.append(f"  {s['substitute']} → replaces {s['replaces']}")
        parts.append("\n".join(lines))

    return "\n\n".join(parts)


def recommend_courses(
    completed_courses: list[str],
    major: str,
    constraints: list[str],
    in_progress_courses: list[str] | None = None,
    available_courses: list[dict] | None = None,
    major_requirements: dict | None = None,
) -> dict:
    """
    Generate a structured academic plan with course recommendations.

    Returns a dict with:
      - recommended_courses: list of {code, name, reason}
      - reasoning: overall explanation string
      - warnings: list of warning strings
    """
    completed_str = ", ".join(completed_courses) if completed_courses else "None"
    constraints_str = ", ".join(constraints) if constraints else "None"
    in_progress_str = ", ".join(in_progress_courses) if in_progress_courses else "None"

    course_context = ""
    if available_courses:
        trimmed = available_courses[:30]
        lines = [
            f"- {c.get('code', '')} | {c.get('name', '')} | Credits: {c.get('credits', '?')} | Prereqs: {c.get('prerequisites', 'None')}"
            for c in trimmed
        ]
        course_context = "\nAvailable courses from VT timetable:\n" + "\n".join(lines)

    catalog_context = ""
    if major_requirements:
        req = major_requirements.get("required_courses", [])
        elec = major_requirements.get("electives", [])
        notes = major_requirements.get("notes", "")
        if req:
            catalog_context += f"\nDegree required courses (from VT catalog): {', '.join(req)}"
        if elec:
            catalog_context += f"\nApproved electives: {', '.join(elec[:20])}"
        if notes:
            catalog_context += f"\nCatalog notes: {notes}"
        plan_context = _build_plan_context(major_requirements)
        if plan_context:
            catalog_context += "\n\n" + plan_context

    prompt = f"""You are an academic advisor for Virginia Tech.

Student profile:
- Major: {major}
- Completed courses: {completed_str}
- Currently enrolled (in-progress): {in_progress_str}
- Constraints / preferences: {constraints_str}

IN-PROGRESS COURSE RULES:
- Each in-progress course is listed as "COURSE CODE (currently enrolled, grade: X)"
- If the current grade is A, B, or C: treat as LIKELY TO COMPLETE — count toward prerequisites when planning next semester
- If the current grade is D or F: treat as AT-RISK — do NOT count as a completed prerequisite; flag in warnings
- If no grade is reported: treat conservatively — do not count as completed
{catalog_context}
{course_context}

Task: Recommend the next semester of courses for this student.

FORMATTING RULES (strictly follow these):
- The "reasoning" field MUST use markdown: use **bold** for course codes and key points, and "- " bullet points for each distinct reason or strategy. Write 3-5 bullet points minimum.
- Each item in "warnings" MUST use **bold** for course codes. Example: "**CS 3114** requires **CS 2114** which is not yet completed."
- The "reason" for each recommended course should be 1 sentence with **bold** on the course code.

Respond ONLY with valid JSON in this exact structure:
{{
  "recommended_courses": [
    {{"code": "CS 3114", "name": "Data Structures and Algorithms", "reason": "**CS 3114** is a core requirement with all prerequisites satisfied."}},
    ...
  ],
  "reasoning": "- **Overall strategy**: balanced 15-credit semester focusing on core requirements.\n- **CS 3114** is next in the CS core sequence and prereqs are met.\n- **MATH 2214** addresses a required math gap before upper-level courses.",
  "warnings": ["**CS 4234** requires **CS 3114** which is not yet completed — do not take concurrently."]
}}

Rules:
- Prioritize courses that appear in the degree required courses list and are NOT yet completed
- Only recommend courses whose prerequisites are satisfied by the completed list
- Never recommend a course the student has already completed
- Aim for 12–16 credits total (most VT courses are 3–4 credits)
- Balance workload — avoid stacking all difficult courses in one semester
- Flag prerequisite gaps or risky combinations in warnings
- If you lack data on a specific course, add a warning instead of guessing"""

    def _call():
        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.3,
            max_completion_tokens=1024,
            response_format={"type": "json_object"},
        )
        return json.loads(response.choices[0].message.content)

    result = _call_with_retry(_call)

    # Ensure all expected keys are present
    result.setdefault("recommended_courses", [])
    result.setdefault("reasoning", "")
    result.setdefault("warnings", [])
    return result


def recommend_tutoring(
    struggling_courses: list[str],
    completed_courses: list[str] | None = None,
    major: str = "",
) -> dict:
    """
    Generate tutoring and academic support recommendations for a struggling student.

    Returns a dict with:
      - resources: list of {name, type, description, link}
      - tips: list of study strategy strings
      - encouragement: short motivational string
    """
    struggling_str = ", ".join(struggling_courses)
    major_str = major or "Engineering"

    prompt = f"""You are an academic support advisor at Virginia Tech.

A student is struggling with: {struggling_str}
Their major: {major_str}

Recommend specific tutoring and academic support resources available at VT.

Return ONLY valid JSON:
{{
  "resources": [
    {{
      "name": "VT Math Emporium",
      "type": "tutoring",
      "description": "Free drop-in tutoring for math courses at the Math Emporium in Squires Student Center.",
      "link": null
    }}
  ],
  "tips": [
    "Use **bold** for key actions. Keep each tip to 1-2 sentences with a concrete action.",
    "Example: **Attend office hours** at least once a week — professors remember students who show up."
  ],
  "encouragement": "1-2 sentences with **bold** on key motivational words. Personalized to the courses they are struggling with."
}}

Resource types (use exactly): "tutoring", "study_group", "office_hours", "online", "writing_center", "ai_tutor"

Include resources for each struggling course. Cover at minimum:
- VT tutoring centers relevant to the subject (Math Emporium for math, CWTS for writing, CEED/Engineering Academic Success for CS/ECE/engineering)
- Department-specific office hours reminder
- Online resources (Khan Academy, YouTube, official textbooks) where applicable
- Peer study group suggestion
- AI tutoring reminder (Wolfram Alpha for math, etc.)

Keep descriptions concise (1-2 sentences each). Include 3-5 practical study tips."""

    def _call():
        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.4,
            max_completion_tokens=1024,
            response_format={"type": "json_object"},
        )
        return json.loads(response.choices[0].message.content)

    result = _call_with_retry(_call)
    result.setdefault("resources", [])
    result.setdefault("tips", [])
    result.setdefault("encouragement", "")
    return result
