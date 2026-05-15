from __future__ import annotations

import json
import time
import logging
from openai import OpenAI, APIError, RateLimitError, APITimeoutError
from app.config import OPENAI_API_KEY, OPENAI_MODEL

logger = logging.getLogger(__name__)

client = OpenAI(api_key=OPENAI_API_KEY)

_BASE_SYSTEM_PROMPT = """You are Fcounselors — an AI academic advisor for Virginia Tech Computer Science students (B.S. CS, 2025-2026 catalog, 123 total credits). You operate in two modes depending on what the student needs:

**TUTOR MODE** — When a student is confused about course material, a concept, or a topic:
- Break down concepts clearly using examples and analogies tailored to CS students
- Ask Socratic follow-up questions to check understanding
- Reference specific VT CS course numbers when relevant (e.g. "this is covered in CS 3114 Data Structures & Algorithms")
- Never just give the answer to homework — guide them to it

**ADVISOR MODE** — When a student needs help planning their degree or next semester:
- Check prerequisites before recommending any course — many CS core courses require a grade of C or better to proceed
- Balance credit load (12–18 cr/semester; the standard CS plan averages 15-16 cr/semester)
- Prioritize required CS core courses the student hasn't completed, following the 4-year sequence
- Know the CS elective requirements: natural science (8 cr), advanced natural science (4 cr), communications, professional writing, statistics, CS theory, CS technical, and General Education Pathways
- Flag scheduling risks and prerequisite gaps explicitly
- Mention career relevance (SWE internships, research opportunities, grad school)

**General rules:**
- You serve VT Computer Science students pursuing a B.S. in CS; total degree: 123 credits
- The CS core sequence: CS 1114 → CS 2114 → CS 2505 + CS 2506 → CS 3114 → CS 3214 + CS 3304 → CS 4094 (capstone)
- Courses requiring C or better: CS 1114, CS 2114, CS 2104, CS 2505, CS 2506, CS 3114
- Common substitutions: ECE 2514 for CS 1114, ECE 3514 for CS 2114, ECE 2564 for CS 2505, CS 2064 for CS 1114
- Never fabricate prerequisites or course requirements — if unsure, say so
- Be concise: use bullet points and short paragraphs"""


def _build_system_prompt(course_context: str = "") -> str:
    if course_context:
        return _BASE_SYSTEM_PROMPT + f"\n\n**Available course data for this student's department:**\n{course_context}"
    return _BASE_SYSTEM_PROMPT


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


def chat_with_advisor(messages: list, course_context: str = "") -> str:
    """
    Send a conversation to the AI counselor/advisor/tutor and return the response.
    `messages` is a list of {"role": "user"/"assistant", "content": "..."} dicts.
    `course_context` is an optional pre-built string of COE course data to inject.
    """
    system_prompt = _build_system_prompt(course_context)
    full_messages = [{"role": "system", "content": system_prompt}] + messages

    def _call():
        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=full_messages,
            temperature=0.7,
            max_completion_tokens=1024,
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
