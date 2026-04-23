from __future__ import annotations

import json
import time
import logging
from openai import OpenAI, APIError, RateLimitError, APITimeoutError
from app.config import OPENAI_API_KEY, OPENAI_MODEL

logger = logging.getLogger(__name__)

client = OpenAI(api_key=OPENAI_API_KEY)

_BASE_SYSTEM_PROMPT = """You are Fcounselors — an AI academic companion for Virginia Tech College of Engineering students. You operate in two modes depending on what the student needs:

**TUTOR MODE** — When a student is confused about course material, a concept, or a topic:
- Break down concepts clearly using examples and analogies
- Ask Socratic follow-up questions to check understanding
- Reference specific VT course numbers when relevant (e.g. "this is covered in CS 3114")
- Never just give the answer to homework — guide them to it

**ADVISOR MODE** — When a student needs help planning their degree or next semester:
- Check prerequisites before recommending any course
- Balance credit load (12–18 cr/semester typical at VT)
- Prioritize required degree courses the student hasn't completed
- Flag scheduling risks and prerequisite gaps explicitly
- Mention career relevance (internships, grad school, industry)

**General rules:**
- You serve VT College of Engineering students; all course data comes from the VT timetable
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


def recommend_courses(
    completed_courses: list[str],
    major: str,
    constraints: list[str],
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

    prompt = f"""You are an academic advisor for Virginia Tech.

Student profile:
- Major: {major}
- Completed courses: {completed_str}
- Constraints / preferences: {constraints_str}
{catalog_context}
{course_context}

Task: Recommend the next semester of courses for this student.

Respond ONLY with valid JSON in this exact structure:
{{
  "recommended_courses": [
    {{"code": "CS 3114", "name": "Data Structures and Algorithms", "reason": "Core CS requirement, prereqs satisfied"}},
    ...
  ],
  "reasoning": "A short paragraph explaining the overall plan strategy.",
  "warnings": ["Any prerequisite gaps or scheduling risks go here."]
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
    "Visit office hours at least once a week — professors remember students who show up.",
    "Break each struggling topic into 20-minute focused review blocks."
  ],
  "encouragement": "A 1-2 sentence personalized motivational note for this student."
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


def summarize_course_data(raw_text: str) -> dict:
    """
    Given raw scraped course text, extract structured course info.
    Returns a dict with keys: name, code, credits, description, prerequisites.
    """
    prompt = f"""Extract structured course information from the following text.
Return ONLY valid JSON with these keys: name, code, credits, description, prerequisites (list of strings).

Text:
{raw_text[:3000]}"""

    def _call():
        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0,
            max_tokens=512,
            response_format={"type": "json_object"},
        )
        return json.loads(response.choices[0].message.content)

    return _call_with_retry(_call)
