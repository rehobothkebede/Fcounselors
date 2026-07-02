from __future__ import annotations

import base64
import io
import json
import logging
import re
from datetime import date

from openai import OpenAI
from app.config import OPENAI_API_KEY, TRANSCRIPT_MODEL
from app.services.ai_service import _call_with_retry

logger = logging.getLogger(__name__)

client = OpenAI(api_key=OPENAI_API_KEY)


class TranscriptParseError(Exception):
    """User-facing transcript parsing failure with a stable app error code."""

    def __init__(self, code: str, message: str, status_code: int = 422):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code

_EXTRACT_PROMPT_TEMPLATE = """You are parsing a Virginia Tech student academic transcript.

Current date: {current_date}

Extract every course from this transcript into three lists: completed courses, in-progress courses,
and planned/future registered courses.

Return ONLY valid JSON in this exact structure:
{
  "courses": [
    {
      "code": "CS 2114",
      "name": "Software Design and Data Structures",
      "credits": 3,
      "grade": "A",
      "semester": "Fall 2023"
    }
  ],
  "in_progress_courses": [
    {
      "code": "CS 2104",
      "name": "Problem Solving in Science",
      "credits": 3,
      "semester": "Spring 2026"
    }
  ],
  "planned_courses": [
    {
      "code": "CS 2505",
      "name": "Computer Organization I",
      "credits": 3,
      "semester": "Fall 2026"
    }
  ],
  "warnings": ["list any ambiguous entries or data quality issues here"]
}

GRADE RULES — what goes where:
- Standard letter grades (A, A+, A-, B+, B, B-, C+, C, C-, D+, D, D-): → courses (COMPLETED)
- P or PASS: → courses, use grade "P"
- CR or CREDIT: → courses, use grade "CR"
- T, TR, or TRANSFER (transfer credit): → courses, use grade "T"
- W (Withdrawal): EXCLUDE entirely — course was dropped
- I (Incomplete): EXCLUDE entirely — course not finished
- CD (Credit Disallowed): EXCLUDE entirely
- IN PROGRESS / no final grade / currently enrolled AND the semester has already started:
  → in_progress_courses (no grade field)
- REGISTERED / planned / enrolled for a future semester that has not started yet:
  → planned_courses (no grade field)
- Do NOT use quality points to decide — use the grade code only

SEMESTER START HEURISTIC:
- Spring semester starts in January
- Summer semester starts in May
- Fall semester starts in August
- If the transcript shows a no-grade course for a semester after the current date, put it in planned_courses
- If it shows a no-grade course for the current semester after the start month, put it in in_progress_courses
- If unsure whether a no-grade course is in-progress or planned, put it in planned_courses and add a warning

DUPLICATE CREDIT HANDLING:
- If the same course credit appears from multiple sources (e.g. AP exam AND transfer), include only the valid entry
- If one entry is marked CD (Credit Disallowed), exclude it and keep the other
- Never include the same credit twice

COURSE CODE RULES:
- Use VT format: "SUBJECT NNNN" (e.g. "CS 2114", "MATH 2114")
- Transfer credits without a specific VT course number: use placeholder format "SUBJ 1XXX" (e.g. "CS 1XXX", "MATH 1XXX")
  — add a warning that these count as electives only, not toward core requirements
- Special pathway/bridge codes (e.g. "CS 1XXP", "MATH 1XXP"): INCLUDE — these are valid pathway credits
- credits must be a number
- grade should be normalized to VT-style codes (A, B+, P, CR, T, etc.)
- semester format: "Season YYYY" (e.g. "Fall 2023", "Spring 2024")
- If semester is unclear, omit the semester field rather than guess

COURSE NAME RULES:
- Strip any institution prefix from course names (e.g. "Blacksburg UG", "Blacksburg GR") — use only the actual course title
- Example: "Blacksburg UG Softw Des & Data Structures" → "Software Design and Data Structures"

SEMESTER RULES FOR TRANSFER / AP CREDIT:
- If a course came in as transfer credit, AP credit, or dual enrollment and has no specific VT semester, use semester "Transfer"
- Never use date ranges (e.g. "FS23-SS25") or bare years (e.g. "2025") as semester values"""


def _extract_prompt() -> str:
    return _EXTRACT_PROMPT_TEMPLATE.replace("{current_date}", date.today().isoformat())


def _extract_from_text(text: str) -> dict:
    def _call():
        response = client.chat.completions.create(
            model=TRANSCRIPT_MODEL,
            messages=[
                {"role": "system", "content": _extract_prompt()},
                {"role": "user", "content": f"Transcript text:\n\n{text[:12000]}"},
            ],
            temperature=0,
            response_format={"type": "json_object"},
        )
        return _decode_model_json(response.choices[0].message.content)

    return _call_with_retry(_call)


def _extract_from_image(image_bytes: bytes, mime_type: str) -> dict:
    b64 = base64.standard_b64encode(image_bytes).decode("utf-8")

    def _call():
        response = client.chat.completions.create(
            model=TRANSCRIPT_MODEL,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": _extract_prompt()},
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:{mime_type};base64,{b64}", "detail": "high"},
                        },
                    ],
                }
            ],
            temperature=0,
            response_format={"type": "json_object"},
        )
        return _decode_model_json(response.choices[0].message.content)

    return _call_with_retry(_call)


def _decode_model_json(content: str | None) -> dict:
    if not content:
        raise TranscriptParseError(
            "TRANSCRIPT_AI_EMPTY_RESPONSE",
            "The transcript parser returned an empty response. Please try again.",
            status_code=502,
        )
    try:
        decoded = json.loads(content)
    except json.JSONDecodeError as e:
        logger.warning("Transcript model returned invalid JSON: %s", e)
        raise TranscriptParseError(
            "TRANSCRIPT_AI_INVALID_JSON",
            "The transcript parser returned a malformed response. Please try again.",
            status_code=502,
        ) from e
    if not isinstance(decoded, dict):
        raise TranscriptParseError(
            "TRANSCRIPT_AI_INVALID_SCHEMA",
            "The transcript parser returned an unexpected response shape. Please try again.",
            status_code=502,
        )
    return decoded


def parse_transcript(file_bytes: bytes, content_type: str) -> dict:
    """
    Parse a transcript from uploaded bytes.
    content_type: "application/pdf", "image/png", or "image/jpeg"
    Returns: {"courses": [...], "warnings": [...]}
    """
    if not OPENAI_API_KEY:
        raise TranscriptParseError(
            "OPENAI_API_KEY_MISSING",
            "Transcript parsing is not configured on this server.",
            status_code=503,
        )

    if content_type == "application/pdf":
        text = _pdf_to_text(file_bytes)
        if not text.strip():
            raise TranscriptParseError(
                "TRANSCRIPT_PDF_NO_TEXT",
                "Could not extract text from this PDF. If it is a scanned transcript, upload a PNG or JPG instead.",
            )
        result = _extract_from_text(text)
    elif content_type in ("image/png", "image/jpeg", "image/jpg"):
        result = _extract_from_image(file_bytes, content_type)
    else:
        raise TranscriptParseError(
            "TRANSCRIPT_UNSUPPORTED_FILE_TYPE",
            f"Unsupported file type: {content_type}. Upload a PDF, PNG, or JPG.",
            status_code=415,
        )

    result.setdefault("courses", [])
    result.setdefault("in_progress_courses", [])
    result.setdefault("planned_courses", [])
    result.setdefault("warnings", [])
    _normalize_transcript_result(result)
    return result


def _pdf_to_text(file_bytes: bytes) -> str:
    try:
        import pdfplumber
    except ImportError as e:
        raise RuntimeError("pdfplumber is not installed. Run: pip install pdfplumber") from e

    text_parts: list[str] = []
    with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
        for page in pdf.pages:
            page_text = page.extract_text()
            if page_text:
                text_parts.append(page_text)
    return "\n".join(text_parts)


def _normalize_transcript_result(result: dict) -> None:
    """Normalize parser output and move future no-grade courses into planned_courses."""
    result["courses"] = [_normalize_completed_course(c, result["warnings"]) for c in result.get("courses", [])]
    result["in_progress_courses"] = [_normalize_open_course(c, result["warnings"]) for c in result.get("in_progress_courses", [])]
    result["planned_courses"] = [_normalize_open_course(c, result["warnings"]) for c in result.get("planned_courses", [])]

    still_in_progress = []
    for course in result["in_progress_courses"]:
        semester = course.get("semester")
        if semester and not _semester_has_started(semester, date.today()):
            result["planned_courses"].append(course)
            result["warnings"].append(
                f"{course.get('code', 'A course')} is listed for {semester}, which has not started yet; moved to planned_courses."
            )
        else:
            still_in_progress.append(course)
    result["in_progress_courses"] = still_in_progress

    result["courses"] = _dedupe_courses(result["courses"])
    result["in_progress_courses"] = _dedupe_courses(result["in_progress_courses"])
    result["planned_courses"] = _dedupe_courses(result["planned_courses"])


def _normalize_completed_course(course: dict, warnings: list[str]) -> dict:
    normalized = dict(course)
    normalized["code"] = _normalize_code(str(normalized.get("code", "")))
    _ensure_course_name(normalized, warnings)
    if normalized.get("grade"):
        normalized["grade"] = _normalize_grade(str(normalized["grade"]))
    return normalized


def _normalize_open_course(course: dict, warnings: list[str]) -> dict:
    normalized = dict(course)
    normalized["code"] = _normalize_code(str(normalized.get("code", "")))
    _ensure_course_name(normalized, warnings)
    normalized.pop("grade", None)
    return normalized


def _ensure_course_name(course: dict, warnings: list[str]) -> None:
    name = str(course.get("name") or "").strip()
    if name:
        course["name"] = name
        return

    code = str(course.get("code") or "Unknown course").strip() or "Unknown course"
    course["name"] = "Untitled course"
    warnings.append(f"{code} did not include a course title in the parser response.")


def _normalize_grade(grade: str) -> str:
    normalized = grade.strip().upper()
    if normalized in {"TRANSFER", "TR"}:
        return "T"
    if normalized == "PASS":
        return "P"
    if normalized == "CREDIT":
        return "CR"
    return normalized


def _normalize_code(code: str) -> str:
    code = code.strip().upper().replace("-", " ")
    match = re.match(r"([A-Z]{2,4})\s*(\d{4}[A-Z]?)", code)
    if not match:
        return code
    return f"{match.group(1)} {match.group(2)}"


def _semester_has_started(semester: str, today: date) -> bool:
    parts = semester.strip().split()
    if len(parts) != 2:
        return True
    season, year_text = parts
    if season.lower() == "transfer":
        return True
    try:
        year = int(year_text)
    except ValueError:
        return True

    start_month = {
        "spring": 1,
        "summer": 5,
        "fall": 8,
        "winter": 12,
    }.get(season.lower())
    if start_month is None:
        return True
    return date(year, start_month, 1) <= today


def _dedupe_courses(courses: list[dict]) -> list[dict]:
    seen: set[tuple[str, str]] = set()
    result: list[dict] = []
    for course in courses:
        key = (course.get("code", ""), course.get("semester", ""))
        if key in seen:
            continue
        seen.add(key)
        result.append(course)
    return result
