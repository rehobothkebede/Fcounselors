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

Extract every course the student has COMPLETED (has a final grade — ignore in-progress or withdrawn courses).

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
  "warnings": ["list any ambiguous entries or data quality issues here"]
}

Rules:
- Use the VT course code format: "SUBJECT NNNN" (e.g. "CS 2114", "MATH 2114")
- credits must be a number
- grade should be the letter grade as shown (A, A-, B+, etc.) or "CR" for credit/no-credit
- semester format: "Season YYYY" (e.g. "Fall 2023", "Spring 2024")
- If semester is unclear, omit the field rather than guess
- Do NOT include courses with grades of W, I, or any in-progress marker"""


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
