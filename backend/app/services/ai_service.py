from __future__ import annotations

import json
import time
import logging
from openai import OpenAI, APIError, RateLimitError, APITimeoutError
from app.config import OPENAI_API_KEY, OPENAI_MODEL

logger = logging.getLogger(__name__)

client = OpenAI(api_key=OPENAI_API_KEY)

SYSTEM_PROMPT = """You are Fcounselors, an AI academic advisor for Virginia Tech students.

Your role:
- Help students build realistic, personalized academic plans
- Recommend courses based on completed coursework and prerequisites
- Consider student constraints (workload, career goals, interests)
- Be honest when you lack specific VT data — never fabricate requirements

Virginia Tech context you know:
- CS major requires courses like CS 2114, CS 3114, CS 3304, CS 3744, CS 4104, CS 4234
- Math requirements typically include MATH 1225, 1226, 2114, 2214
- Prerequisites must be completed before enrolling in advanced courses
- Students typically take 15–18 credits per semester
- VT uses a 4-credit system for most courses

When recommending courses:
1. Always check if prerequisites from the student's completed list are satisfied
2. Flag courses the student is NOT yet eligible for
3. Balance difficulty — don't stack all hard courses in one semester
4. Mention career relevance when applicable (internship prep, grad school, etc.)
5. Be concise — use bullet points and short paragraphs

If you don't know a specific VT requirement, say so clearly and suggest the student verify with their official degree audit."""


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


def chat_with_advisor(messages: list) -> str:
    """
    Send a conversation to the AI advisor and return the response text.
    `messages` is a list of {"role": "user"/"assistant", "content": "..."} dicts.
    """
    full_messages = [{"role": "system", "content": SYSTEM_PROMPT}] + messages

    def _call():
        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=full_messages,
            temperature=0.7,
            max_tokens=1024,
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
            max_tokens=1024,
            response_format={"type": "json_object"},
        )
        return json.loads(response.choices[0].message.content)

    result = _call_with_retry(_call)

    # Ensure all expected keys are present
    result.setdefault("recommended_courses", [])
    result.setdefault("reasoning", "")
    result.setdefault("warnings", [])
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
