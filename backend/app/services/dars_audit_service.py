from __future__ import annotations

import base64
import io
import json
import logging

from openai import OpenAI
from app.config import OPENAI_API_KEY, TRANSCRIPT_MODEL
from app.services.ai_service import _call_with_retry

logger = logging.getLogger(__name__)

client = OpenAI(api_key=OPENAI_API_KEY)


_DARS_EXTRACT_PROMPT = """You are parsing an official Virginia Tech uAchieve/DARS degree audit report.

Extract the audit exactly as the report presents it. uAchieve/DARS is the source of truth.
Do not infer missing requirements from a checksheet. Only report what is visible in the audit.

Return ONLY valid JSON in this exact structure:
{
  "student_name": "Last, First",
  "student_id": "906657868",
  "program": "BACHELOR OF SCIENCE IN COMPUTER SCIENCE",
  "program_code": "BSCS CS",
  "catalog_year": "Fall 2025",
  "graduation_date": "UNKNOWN",
  "prepared_on": "05/16/2026 05:47 PM",
  "job_id": "2613617470630316",
  "audit_type": "WHAT IF",
  "university_gpa": 3.212,
  "in_major_gpa": 3.149,
  "categories": [
    {
      "id": "major",
      "title": "Major",
      "status": "in_progress",
      "complete_hours": 67,
      "in_progress_hours": 17,
      "unfulfilled_hours": 44,
      "planned_hours": 0,
      "required_hours": 128,
      "gpa": null,
      "notes": []
    }
  ],
  "sections": [
    {
      "title": "Requirement section title",
      "status": "complete",
      "matched_courses": ["CS 1114"],
      "missing_items": [],
      "notes": []
    }
  ],
  "warnings": ["any unreadable or ambiguous data"]
}

STATUS RULES:
- Use exactly one of: "complete", "in_progress", "unfulfilled", "planned", "unknown".
- Green/complete graph regions map to complete_hours.
- Blue/in-progress graph regions map to in_progress_hours.
- Red/unfulfilled graph regions map to unfulfilled_hours.
- Purple/planned graph regions map to planned_hours.
- If a category row appears but exact numbers are not printed, estimate only if the report graph visibly labels them; otherwise use null and add a warning.

COMMON TOP-LEVEL CATEGORIES:
- University GPA
- Minimum Hours
- Major
- General Ed
- In Major GPA
- Electives
- Minor(s)

COURSE HISTORY:
- If the Course History tab or expanded sections are present, extract course codes, grades, transfer markers, and terms into sections.
- Transfer grades T/TR/TRANSFER mean awarded transfer credit.

Keep every string short and preserve official DARS wording where possible."""


def parse_dars_audit(file_bytes: bytes, content_type: str) -> dict:
    if content_type == "application/pdf":
        text = _pdf_to_text(file_bytes)
        if not text.strip():
            raise ValueError("Could not extract text from DARS PDF. Try uploading a screenshot or image export.")
        result = _extract_from_text(text)
    elif content_type in ("image/png", "image/jpeg", "image/jpg"):
        result = _extract_from_image(file_bytes, content_type)
    else:
        raise ValueError(f"Unsupported file type: {content_type}. Upload a PDF, PNG, or JPG.")

    _normalize_result(result)
    return result


def _extract_from_text(text: str) -> dict:
    def _call():
        response = client.chat.completions.create(
            model=TRANSCRIPT_MODEL,
            messages=[
                {"role": "system", "content": _DARS_EXTRACT_PROMPT},
                {"role": "user", "content": f"DARS/uAchieve audit text:\n\n{text[:15000]}"},
            ],
            temperature=0,
            response_format={"type": "json_object"},
        )
        return json.loads(response.choices[0].message.content)

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
                        {"type": "text", "text": _DARS_EXTRACT_PROMPT},
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
        return json.loads(response.choices[0].message.content)

    return _call_with_retry(_call)


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


def _normalize_result(result: dict) -> None:
    result.setdefault("student_name", None)
    result.setdefault("student_id", None)
    result.setdefault("program", None)
    result.setdefault("program_code", None)
    result.setdefault("catalog_year", None)
    result.setdefault("graduation_date", None)
    result.setdefault("prepared_on", None)
    result.setdefault("job_id", None)
    result.setdefault("audit_type", None)
    result.setdefault("university_gpa", None)
    result.setdefault("in_major_gpa", None)
    result.setdefault("categories", [])
    result.setdefault("sections", [])
    result.setdefault("warnings", [])

    result["categories"] = [_normalize_category(c) for c in result.get("categories", [])]
    result["sections"] = [_normalize_section(s) for s in result.get("sections", [])]


def _normalize_category(category: dict) -> dict:
    title = str(category.get("title") or "Unknown").strip()
    return {
        "id": str(category.get("id") or _slug(title)),
        "title": title,
        "status": _normalize_status(category.get("status")),
        "complete_hours": _number_or_none(category.get("complete_hours")),
        "in_progress_hours": _number_or_none(category.get("in_progress_hours")),
        "unfulfilled_hours": _number_or_none(category.get("unfulfilled_hours")),
        "planned_hours": _number_or_none(category.get("planned_hours")),
        "required_hours": _number_or_none(category.get("required_hours")),
        "gpa": _number_or_none(category.get("gpa")),
        "notes": list(category.get("notes") or []),
    }


def _normalize_section(section: dict) -> dict:
    title = str(section.get("title") or "Requirement").strip()
    return {
        "title": title,
        "status": _normalize_status(section.get("status")),
        "matched_courses": list(section.get("matched_courses") or []),
        "missing_items": list(section.get("missing_items") or []),
        "notes": list(section.get("notes") or []),
    }


def _normalize_status(status: str | None) -> str:
    normalized = (status or "unknown").strip().lower().replace("-", "_").replace(" ", "_")
    if normalized in {"complete", "completed", "satisfied"}:
        return "complete"
    if normalized in {"in_progress", "progress", "partial"}:
        return "in_progress"
    if normalized in {"unfulfilled", "incomplete", "missing", "not_satisfied"}:
        return "unfulfilled"
    if normalized in {"planned", "plan"}:
        return "planned"
    return "unknown"


def _number_or_none(value) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _slug(value: str) -> str:
    return "_".join(part for part in value.lower().replace("/", " ").replace("(", " ").replace(")", " ").split() if part)
