import json
import os
from typing import Any, Iterable, Optional

from app.config import COE_DIR, DATA_DIR, VT_FULL_CATALOG_PATH, VT_PROGRAMS_PATH, VT_SUBJECTS_PATH
from app.services.supabase_service import SupabaseClient


def _chunks(rows: list[dict[str, Any]], size: int = 500) -> Iterable[list[dict[str, Any]]]:
    for i in range(0, len(rows), size):
        yield rows[i:i + size]


def _read_json(path: str, default: Any) -> Any:
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return json.load(f)


def sync_catalog_to_supabase(client: SupabaseClient) -> dict[str, int]:
    """Push local catalog JSON files into Supabase lookup tables."""
    counts: dict[str, int] = {}

    full_catalog = _read_json(VT_FULL_CATALOG_PATH, {})
    subjects = full_catalog.get("subjects") or _read_json(VT_SUBJECTS_PATH, [])
    programs = full_catalog.get("programs") or _read_json(VT_PROGRAMS_PATH, [])
    unique_courses = full_catalog.get("unique_courses") or {}
    requirements = full_catalog.get("program_requirements") or {}
    pathways = _read_json(os.path.join(DATA_DIR, "pathways.json"), {})

    subject_rows = [
        {
            "code": str(subject.get("code", "")).upper(),
            "name": subject.get("name") or subject.get("code") or "",
            "url": subject.get("url") or "",
            "source": "vt_full_catalog" if full_catalog else "vt_subjects",
        }
        for subject in subjects
        if subject.get("code")
    ]
    counts["catalog_subjects"] = _upsert_chunks(client, "catalog_subjects", subject_rows, "code")

    course_rows: list[dict[str, Any]] = []
    for subject, courses in unique_courses.items():
        for course in courses:
            code = course.get("code") or ""
            if not code:
                continue
            course_rows.append({
                "subject": str(subject).upper(),
                "code": code,
                "name": course.get("name") or "",
                "credits": _coerce_credits(course.get("credits")),
                "description": course.get("description") or "",
                "prerequisites": course.get("prerequisites") or "",
                "raw": course,
                "source": "vt_full_catalog",
            })
    counts["catalog_courses"] = _upsert_chunks(client, "catalog_courses", course_rows, "subject,code")

    program_rows = [
        {
            "key": _program_key(program),
            "name": program.get("name") or "",
            "code": program.get("code") or "",
            "degree": program.get("degree") or "",
            "url": program.get("url") or "",
            "raw": program,
            "source": "vt_full_catalog" if full_catalog else "vt_programs",
        }
        for program in programs
        if program.get("name") or program.get("code")
    ]
    counts["catalog_programs"] = _upsert_chunks(client, "catalog_programs", program_rows, "key")

    requirement_rows = [
        {
            "program_key": key,
            "name": value.get("name") or key,
            "requirements": value,
            "source": "vt_full_catalog",
        }
        for key, value in requirements.items()
        if isinstance(value, dict)
    ]
    counts["catalog_requirements"] = _upsert_chunks(
        client,
        "catalog_requirements",
        requirement_rows,
        "program_key",
    )

    pathway_rows = _pathway_rows(pathways)
    counts["pathways_courses"] = _upsert_chunks(client, "pathways_courses", pathway_rows, "code,concept")

    coe_rows = _coe_course_rows()
    counts["coe_courses"] = _upsert_chunks(client, "coe_courses", coe_rows, "subject,code")

    return counts


def _upsert_chunks(client: SupabaseClient, table: str, rows: list[dict[str, Any]], on_conflict: str) -> int:
    rows = _dedupe_by_conflict(rows, on_conflict)
    total = 0
    for chunk in _chunks(rows):
        total += client.upsert(table, chunk, on_conflict=on_conflict)
    return total


def _dedupe_by_conflict(rows: list[dict[str, Any]], on_conflict: str) -> list[dict[str, Any]]:
    keys = [key.strip() for key in on_conflict.split(",") if key.strip()]
    if not keys:
        return rows

    deduped: dict[tuple[Any, ...], dict[str, Any]] = {}
    order: list[tuple[Any, ...]] = []
    for row in rows:
        identity = tuple(row.get(key) for key in keys)
        if identity not in deduped:
            order.append(identity)
        deduped[identity] = row
    return [deduped[identity] for identity in order]


def _coerce_credits(value: Any) -> Optional[float]:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _program_key(program: dict[str, Any]) -> str:
    raw = program.get("key") or program.get("code") or program.get("name") or program.get("url")
    return str(raw).lower().strip().replace(" ", "-")


def _pathway_rows(pathways: Any) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if isinstance(pathways, dict):
        items = pathways.items()
    else:
        items = []

    for concept, courses in items:
        if not isinstance(courses, list):
            continue
        for course in courses:
            if not isinstance(course, dict) or not course.get("code"):
                continue
            rows.append({
                "concept": str(concept),
                "code": course.get("code"),
                "name": course.get("name") or course.get("title") or "",
                "credits": _coerce_credits(course.get("credits")),
                "raw": course,
                "source": "pathways_json",
            })
    return rows


def _coe_course_rows() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not os.path.exists(COE_DIR):
        return rows

    for filename in sorted(os.listdir(COE_DIR)):
        if not filename.endswith(".json") or filename == "manifest.json":
            continue
        subject = filename.replace(".json", "").upper()
        data = _read_json(os.path.join(COE_DIR, filename), {})
        for course in data.get("courses", []):
            if not isinstance(course, dict) or not course.get("code"):
                continue
            rows.append({
                "subject": subject,
                "code": course.get("code"),
                "name": course.get("name") or "",
                "credits": _coerce_credits(course.get("credits")),
                "description": course.get("description") or "",
                "prerequisites": course.get("prerequisites") or "",
                "raw": course,
                "source": "coe_json",
            })
    return rows
