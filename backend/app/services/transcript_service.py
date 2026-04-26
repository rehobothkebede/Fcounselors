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

_EXTRACT_PROMPT = """You are parsing a Virginia Tech student academic transcript.

Extract every course from this transcript into two lists: completed courses and in-progress courses.

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
      "credits": 3
    }
  ],
  "warnings": ["list any ambiguous entries or data quality issues here"]
}

GRADE RULES — what goes where:
- Standard letter grades (A, A+, A-, B+, B, B-, C+, C, C-, D+, D, D-): → courses (COMPLETED)
- P or PASS: → courses, use grade "P"
- CR or CREDIT: → courses, use grade "CR"
- T, TR, or TRANSFER (transfer credit): → courses, use grade "TR"
- W (Withdrawal): EXCLUDE entirely — course was dropped
- I (Incomplete): EXCLUDE entirely — course not finished
- CD (Credit Disallowed): EXCLUDE entirely
- IN PROGRESS / no final grade / currently enrolled: → in_progress_courses (no grade field)
- Do NOT use quality points to decide — use the grade code only

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
- grade should be as shown on the transcript (A, B+, P, CR, TR, etc.)
- semester format: "Season YYYY" (e.g. "Fall 2023", "Spring 2024")
- If semester is unclear, omit the semester field rather than guess

COURSE NAME RULES:
- Strip any institution prefix from course names (e.g. "Blacksburg UG", "Blacksburg GR") — use only the actual course title
- Example: "Blacksburg UG Softw Des & Data Structures" → "Software Design and Data Structures"

SEMESTER RULES FOR TRANSFER / AP CREDIT:
- If a course came in as transfer credit, AP credit, or dual enrollment and has no specific VT semester, use semester "Transfer"
- Never use date ranges (e.g. "FS23-SS25") or bare years (e.g. "2025") as semester values"""


def _extract_from_text(text: str) -> dict:
    def _call():
        response = client.chat.completions.create(
            model=TRANSCRIPT_MODEL,
            messages=[
                {"role": "system", "content": _EXTRACT_PROMPT},
                {"role": "user", "content": f"Transcript text:\n\n{text[:12000]}"},
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
                        {"type": "text", "text": _EXTRACT_PROMPT},
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


def parse_transcript(file_bytes: bytes, content_type: str) -> dict:
    """
    Parse a transcript from uploaded bytes.
    content_type: "application/pdf", "image/png", or "image/jpeg"
    Returns: {"courses": [...], "warnings": [...]}
    """
    if content_type == "application/pdf":
        text = _pdf_to_text(file_bytes)
        if not text.strip():
            raise ValueError("Could not extract text from PDF — it may be a scanned image. Try uploading as PNG or JPG.")
        result = _extract_from_text(text)
    elif content_type in ("image/png", "image/jpeg", "image/jpg"):
        result = _extract_from_image(file_bytes, content_type)
    else:
        raise ValueError(f"Unsupported file type: {content_type}. Upload a PDF, PNG, or JPG.")

    result.setdefault("courses", [])
    result.setdefault("in_progress_courses", [])
    result.setdefault("warnings", [])
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
