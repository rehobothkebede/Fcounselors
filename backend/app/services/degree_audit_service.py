from __future__ import annotations

import json
import os
import re
from functools import lru_cache
from typing import Any


DATA_DIR = os.path.join(os.path.dirname(__file__), "../../data")
CS_REQUIREMENTS_PATH = os.path.join(DATA_DIR, "catalog/computer_science.json")
PATHWAYS_PATH = os.path.join(DATA_DIR, "pathways.json")

GRADE_POINTS = {
    "A": 4.0,
    "A-": 3.7,
    "B+": 3.3,
    "B": 3.0,
    "B-": 2.7,
    "C+": 2.3,
    "C": 2.0,
    "C-": 1.7,
    "D+": 1.3,
    "D": 1.0,
    "D-": 0.7,
    "F": 0.0,
    "W": 0.0,
    "WF": 0.0,
}

NON_CREDIT_GRADES = {"F", "W", "WF", "I", "NG", None}
AWARDED_CREDIT_GRADES = {"P", "PASS", "CR", "CREDIT", "T", "TR", "TRANSFER"}


def run_degree_audit(
    *,
    major: str,
    transcript: list[dict[str, Any]],
    in_progress_courses: list[str] | None = None,
) -> dict[str, Any]:
    """Run a deterministic Hokie Advisor degree audit.

    The first implementation is intentionally data-backed and conservative:
    CS B.S. required courses, substitutions, Pathways, and known elective
    buckets are audited from local catalog JSON. Buckets without approved
    course lists are reported as remaining requirements rather than guessed.
    """
    major_normalized = major.strip().lower()
    if major_normalized not in {"computer science", "cs", "computer science bs", "computer science b.s."}:
        raise ValueError("Degree audit currently supports Computer Science B.S. only.")

    requirements = _load_cs_requirements()
    pathways = _load_pathways_index()
    courses = [_normalize_entry(entry) for entry in transcript if entry.get("code")]
    in_progress = [_normalize_code(c) for c in (in_progress_courses or []) if c]

    course_attempts = _group_attempts(courses)
    passing_courses = [c for c in courses if _is_passing(c.get("grade"))]
    passing_codes = {c["code"] for c in passing_courses}
    total_completed_credits = sum(c.get("credits") or 0 for c in passing_courses)

    required_buckets, retake_courses, satisfied_required_codes = _audit_required_courses(
        requirements=requirements,
        course_attempts=course_attempts,
        passing_codes=passing_codes,
        in_progress=set(in_progress),
    )
    elective_buckets, elective_used_codes, elective_notes = _audit_electives(
        requirements=requirements,
        passing_courses=passing_courses,
        satisfied_required_codes=satisfied_required_codes,
    )
    pathways_buckets = _audit_pathways(
        pathways=pathways,
        passing_courses=passing_courses,
        passing_codes=passing_codes,
        requirements=requirements,
    )

    total_required = float(requirements.get("total_credits", 123))
    free_required = _free_elective_credits(requirements)
    used_before_free = satisfied_required_codes | elective_used_codes
    free_completed = sum(c.get("credits") or 0 for c in passing_courses if c["code"] not in used_before_free)
    free_bucket = _bucket(
        bucket_id="free_elective",
        title="Free Electives / Overflow Credits",
        required_credits=free_required,
        completed_credits=min(free_completed, free_required),
        matched_courses=_course_labels([c for c in passing_courses if c["code"] not in used_before_free])[:12],
        missing_items=[f"{int(max(free_required - free_completed, 0))} more credits"] if free_completed < free_required else [],
        notes=["Pathways 7 is suspended for this catalog; the replacement credits are counted here."],
    )

    total_bucket = _bucket(
        bucket_id="total_credits",
        title="Total Credits",
        required_credits=total_required,
        completed_credits=total_completed_credits,
        matched_courses=[],
        missing_items=[f"{int(max(total_required - total_completed_credits, 0))} more credits"] if total_completed_credits < total_required else [],
        notes=[f"{int(total_completed_credits)} of {int(total_required)} credits completed."],
    )

    buckets = [total_bucket] + required_buckets + elective_buckets + [free_bucket] + pathways_buckets
    complete_count = sum(1 for bucket in buckets if bucket["status"] == "complete")
    percent_complete = int(round((total_completed_credits / max(total_required, 1)) * 100))

    warnings = []
    if retake_courses:
        warnings.append("Retake required: " + ", ".join(retake_courses))
    warnings.extend(elective_notes)

    return {
        "major": "Computer Science",
        "degree": requirements.get("degree", "B.S."),
        "catalog_year": requirements.get("catalog_year", "2025-2026"),
        "total_required_credits": total_required,
        "completed_credits": total_completed_credits,
        "percent_complete": min(percent_complete, 100),
        "complete_bucket_count": complete_count,
        "total_bucket_count": len(buckets),
        "buckets": buckets,
        "warnings": warnings,
    }


@lru_cache(maxsize=1)
def _load_cs_requirements() -> dict[str, Any]:
    with open(CS_REQUIREMENTS_PATH) as f:
        return json.load(f)


@lru_cache(maxsize=1)
def _load_pathways_index() -> dict[str, list[dict[str, Any]]]:
    with open(PATHWAYS_PATH) as f:
        data = json.load(f)

    index: dict[str, list[dict[str, Any]]] = {}
    for concept in data.get("pathways", []):
        for section in concept.get("sections", []):
            section_id = section.get("id", str(concept.get("concept")))
            for course in section.get("courses", []):
                codes = [course.get("code", "")]
                codes.extend(course.get("crosslists", []))
                for code in codes:
                    normalized = _normalize_code(code)
                    if not normalized:
                        continue
                    index.setdefault(normalized, []).append(
                        {
                            "id": section_id,
                            "name": _pathway_name(section_id, concept.get("name"), section.get("name")),
                            "double_counts_concept_7": bool(course.get("double_counts_concept_7")),
                        }
                    )
    return index


def _audit_required_courses(
    *,
    requirements: dict[str, Any],
    course_attempts: dict[str, list[dict[str, Any]]],
    passing_codes: set[str],
    in_progress: set[str],
) -> tuple[list[dict[str, Any]], list[str], set[str]]:
    required_courses = _required_course_map(requirements)
    substitutions = _substitution_map(requirements)
    retakes: list[str] = []
    satisfied_codes: set[str] = set()
    buckets: list[dict[str, Any]] = []

    for code, course in required_courses.items():
        required_grade = course.get("grade_required")
        attempts = course_attempts.get(code, [])
        direct_satisfied = any(_course_satisfies(attempt, required_grade) for attempt in attempts)
        substitute = _satisfied_substitute(code, substitutions, course_attempts)
        is_in_progress = code in in_progress

        matched = []
        missing = []
        notes = []
        completed_credits = 0.0
        status_override = None

        if direct_satisfied:
            best = _best_attempt(attempts)
            matched.append(_course_label(best))
            completed_credits = float(course.get("credits") or best.get("credits") or 0)
            satisfied_codes.add(code)
        elif substitute:
            matched.append(f"{substitute['code']} substitutes for {code}")
            completed_credits = float(course.get("credits") or 0)
            satisfied_codes.add(code)
        elif attempts and required_grade:
            best = _best_attempt(attempts)
            retakes.append(f"{code} ({best.get('grade', 'N/A')})")
            missing.append(f"{code} with {required_grade} or better")
            notes.append(f"{code} requires {required_grade} or better; {best.get('grade', 'N/A')} does not satisfy it.")
            status_override = "attention"
        elif attempts and not any(_is_passing(a.get("grade")) for a in attempts):
            best = _best_attempt(attempts)
            retakes.append(f"{code} ({best.get('grade', 'N/A')})")
            missing.append(code)
            notes.append(f"{code} was attempted but did not earn degree credit.")
            status_override = "attention"
        elif is_in_progress:
            missing.append(f"{code} in progress")
            notes.append("Currently enrolled; will count after a passing final grade.")
            status_override = "in_progress"
        else:
            missing.append(code)

        buckets.append(
            _bucket(
                bucket_id=f"required_{code.lower().replace(' ', '_')}",
                title=f"{code} - {course.get('name', 'Required Course')}",
                required_credits=float(course.get("credits") or 0),
                completed_credits=completed_credits,
                matched_courses=matched,
                missing_items=missing,
                notes=notes,
                status_override=status_override,
            )
        )

    return buckets, retakes, satisfied_codes


def _audit_electives(
    *,
    requirements: dict[str, Any],
    passing_courses: list[dict[str, Any]],
    satisfied_required_codes: set[str],
) -> tuple[list[dict[str, Any]], set[str], list[str]]:
    used_codes: set[str] = set()
    notes: list[str] = []
    available = [c for c in passing_courses if c["code"] not in satisfied_required_codes]
    by_code = {c["code"]: c for c in available}

    natural_codes = _option_codes(requirements, "natural_science_elective")
    advanced_science_codes = _option_codes(requirements, "advanced_natural_science_elective")
    communication_codes = _option_codes(requirements, "communications_elective")
    writing_codes = _option_codes(requirements, "professional_writing_elective")

    buckets: list[dict[str, Any]] = []
    buckets.append(_credit_bucket_from_codes("natural_science", "Natural Science Sequence", 8, natural_codes, by_code, used_codes))
    buckets.append(_credit_bucket_from_codes("advanced_natural_science", "Advanced Natural Science", 4, advanced_science_codes, by_code, used_codes))
    buckets.append(_count_bucket_from_codes("communications", "Communications Elective", 1, communication_codes, by_code, used_codes))
    buckets.append(_count_bucket_from_codes("professional_writing", "Professional Writing Elective", 1, writing_codes, by_code, used_codes))

    upper_cs = [
        c for c in available
        if c["code"] not in used_codes and _subject(c["code"]) == "CS" and _course_number(c["code"]) >= 3000
    ]
    upper_45_cs = [c for c in upper_cs if _course_number(c["code"]) >= 4000]
    buckets.append(_credit_bucket("cs_3_4_5xxx", "CS 3/4/5XXX Electives", 6, upper_cs[:2], used_codes))
    buckets.append(_credit_bucket("cs_4_5xxx", "CS 4/5XXX Elective", 3, upper_45_cs[:1], used_codes))

    technical = [
        c for c in available
        if c["code"] not in used_codes and (_subject(c["code"]) in {"CS", "ECE", "MATH", "STAT", "CMDA"} or _course_number(c["code"]) >= 3000)
    ]
    buckets.append(_credit_bucket("cs_technical", "CS Technical Elective", 3, technical[:1], used_codes))

    buckets.append(
        _bucket(
            bucket_id="statistics_elective",
            title="Statistics Elective",
            required_credits=3,
            completed_credits=0,
            matched_courses=[],
            missing_items=["approved statistics elective"],
            notes=["Approved statistics options are not in the local catalog data yet."],
        )
    )
    buckets.append(
        _bucket(
            bucket_id="cs_theory_elective",
            title="CS Theory Elective",
            required_credits=3,
            completed_credits=0,
            matched_courses=[],
            missing_items=["approved CS theory elective"],
            notes=["Approved theory options are not in the local catalog data yet."],
        )
    )
    notes.append("Statistics and CS theory elective approved lists are not loaded yet, so those buckets stay open until that data is added.")
    return buckets, used_codes, notes


def _audit_pathways(
    *,
    pathways: dict[str, list[dict[str, Any]]],
    passing_courses: list[dict[str, Any]],
    passing_codes: set[str],
    requirements: dict[str, Any],
) -> list[dict[str, Any]]:
    matched: dict[str, list[dict[str, Any]]] = {}
    for course in passing_courses:
        for section in pathways.get(course["code"], []):
            matched.setdefault(section["id"], []).append(course)

    buckets = [
        _pathway_bucket("1f", "Pathways 1F - Foundational Discourse", 6, [c for c in passing_courses if c["code"] in {"ENGL 1105", "ENGL 1106"}], ["ENGL 1105", "ENGL 1106"]),
        _pathway_bucket("1a", "Pathways 1A - Advanced Discourse", 3, matched.get("1a", []), ["3 credits advanced discourse"]),
        _pathway_bucket("2", "Pathways 2 - Humanities", 6, matched.get("2", []), ["6 credits humanities"]),
        _pathway_bucket("3", "Pathways 3 - Social Sciences", 6, matched.get("3", []), ["6 credits social sciences"]),
        _pathway_bucket("4", "Pathways 4 - Natural Sciences", 8, [c for c in passing_courses if c["code"] in _option_codes(requirements, "natural_science_elective") | _option_codes(requirements, "advanced_natural_science_elective")], ["8 credits natural sciences"]),
        _pathway_bucket("5f", "Pathways 5F - Foundational Quantitative", 8, [c for c in passing_courses if c["code"] in {"MATH 1225", "MATH 1226"}], ["MATH 1225", "MATH 1226"]),
        _pathway_bucket("5a", "Pathways 5A - Advanced Quantitative", 3, [c for c in passing_courses if c["code"] == "CS 3114"], ["CS 3114"]),
        _pathway_bucket("6a", "Pathways 6A - Arts", 3, matched.get("6a", []), ["3 credits arts"]),
        _pathway_bucket("6d", "Pathways 6D - Design", 4, [c for c in passing_courses if c["code"] in {"ENGE 1215", "ENGE 1216", "ENGE 1414"}], ["ENGE 1215 + ENGE 1216 or ENGE 1414"]),
    ]
    buckets.append(
        _bucket(
            bucket_id="pathways_7",
            title="Pathways 7 - Identity and Equity",
            required_credits=0,
            completed_credits=0,
            matched_courses=_course_labels(matched.get("7", [])),
            missing_items=[],
            notes=["Suspended as of Oct. 1, 2025 for this catalog; replacement credits count as free electives."],
            status_override="complete",
        )
    )
    return buckets


def _required_course_map(requirements: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for year in requirements.get("four_year_plan", []):
        for semester in ("fall", "spring"):
            for course in year.get(semester, {}).get("courses", []):
                code = _normalize_code(course.get("code", ""))
                if not code or code == "ELEC":
                    continue
                result.setdefault(code, {**course, "code": code})
    return result


def _free_elective_credits(requirements: dict[str, Any]) -> float:
    total = 0.0
    for year in requirements.get("four_year_plan", []):
        for semester in ("fall", "spring"):
            for course in year.get(semester, {}).get("courses", []):
                if course.get("type") == "free_elective":
                    total += float(course.get("credits") or 0)
    return total


def _substitution_map(requirements: dict[str, Any]) -> dict[str, list[str]]:
    mapping: dict[str, list[str]] = {}
    for item in requirements.get("substitutions", []):
        substitute = _extract_first_code(item.get("substitute", ""))
        replaces = [_normalize_code(code) for code in re.findall(r"[A-Z]{2,4}\s*\d{4}[A-Z]?", item.get("replaces", ""))]
        for code in replaces:
            mapping.setdefault(code, []).append(substitute)
    return mapping


def _satisfied_substitute(code: str, substitutions: dict[str, list[str]], course_attempts: dict[str, list[dict[str, Any]]]) -> dict[str, Any] | None:
    for substitute_code in substitutions.get(code, []):
        attempts = course_attempts.get(substitute_code, [])
        for attempt in attempts:
            if _course_satisfies(attempt, "C"):
                return {"code": substitute_code, "attempt": attempt}
    return None


def _course_satisfies(course: dict[str, Any], required_grade: str | None) -> bool:
    grade = course.get("grade")
    if not _is_passing(grade):
        return False
    if required_grade == "C":
        if _is_awarded_credit_grade(grade):
            return True
        return (GRADE_POINTS.get(grade or "", -1) >= 2.0)
    return True


def _is_passing(grade: str | None) -> bool:
    grade = _normalize_grade(grade)
    if grade in NON_CREDIT_GRADES:
        return False
    if grade is None:
        return False
    if _is_awarded_credit_grade(grade):
        return True
    return GRADE_POINTS.get(grade, 0.0) > 0


def _group_attempts(courses: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for course in courses:
        grouped.setdefault(course["code"], []).append(course)
    return grouped


def _best_attempt(attempts: list[dict[str, Any]]) -> dict[str, Any]:
    return max(attempts, key=lambda c: _grade_rank(c.get("grade")))


def _bucket(
    *,
    bucket_id: str,
    title: str,
    required_credits: float,
    completed_credits: float,
    matched_courses: list[str],
    missing_items: list[str],
    notes: list[str],
    required_count: int | None = None,
    completed_count: int | None = None,
    status_override: str | None = None,
) -> dict[str, Any]:
    if status_override:
        status = status_override
    elif completed_credits >= required_credits and (required_count is None or (completed_count or 0) >= required_count):
        status = "complete"
    elif completed_credits > 0 or matched_courses:
        status = "in_progress"
    else:
        status = "incomplete"
    return {
        "id": bucket_id,
        "title": title,
        "status": status,
        "required_credits": float(required_credits),
        "completed_credits": float(min(completed_credits, required_credits)) if required_credits > 0 else float(completed_credits),
        "required_count": required_count,
        "completed_count": completed_count,
        "matched_courses": matched_courses,
        "missing_items": missing_items,
        "notes": notes,
    }


def _credit_bucket_from_codes(bucket_id: str, title: str, required_credits: float, codes: set[str], by_code: dict[str, dict[str, Any]], used_codes: set[str]) -> dict[str, Any]:
    courses = [by_code[code] for code in codes if code in by_code and code not in used_codes]
    return _credit_bucket(bucket_id, title, required_credits, courses, used_codes)


def _count_bucket_from_codes(bucket_id: str, title: str, required_count: int, codes: set[str], by_code: dict[str, dict[str, Any]], used_codes: set[str]) -> dict[str, Any]:
    courses = [by_code[code] for code in codes if code in by_code and code not in used_codes]
    selected = courses[:required_count]
    used_codes.update(c["code"] for c in selected)
    return _bucket(
        bucket_id=bucket_id,
        title=title,
        required_credits=float(required_count * 3),
        completed_credits=sum(c.get("credits") or 0 for c in selected),
        required_count=required_count,
        completed_count=len(selected),
        matched_courses=_course_labels(selected),
        missing_items=[f"{required_count - len(selected)} more course"] if len(selected) < required_count else [],
        notes=[],
    )


def _credit_bucket(bucket_id: str, title: str, required_credits: float, courses: list[dict[str, Any]], used_codes: set[str]) -> dict[str, Any]:
    selected: list[dict[str, Any]] = []
    credits = 0.0
    for course in courses:
        if course["code"] in used_codes:
            continue
        if credits >= required_credits:
            break
        selected.append(course)
        credits += course.get("credits") or 0
    used_codes.update(c["code"] for c in selected)
    return _bucket(
        bucket_id=bucket_id,
        title=title,
        required_credits=required_credits,
        completed_credits=credits,
        matched_courses=_course_labels(selected),
        missing_items=[f"{int(max(required_credits - credits, 0))} more credits"] if credits < required_credits else [],
        notes=[],
    )


def _pathway_bucket(bucket_id: str, title: str, required_credits: float, courses: list[dict[str, Any]], missing_template: list[str]) -> dict[str, Any]:
    unique = _unique_courses(courses)
    credits = sum(c.get("credits") or 0 for c in unique)
    return _bucket(
        bucket_id=f"pathways_{bucket_id}",
        title=title,
        required_credits=required_credits,
        completed_credits=credits,
        matched_courses=_course_labels(unique),
        missing_items=missing_template if credits < required_credits else [],
        notes=[],
    )


def _option_codes(requirements: dict[str, Any], category: str) -> set[str]:
    cat = requirements.get("elective_categories", {}).get(category, {})
    codes: set[str] = set()
    for option in cat.get("options", []):
        if "code" in option:
            codes.add(_normalize_code(option["code"]))
        for course in option.get("courses", []):
            codes.add(_normalize_code(course.get("code", "")))
    return {c for c in codes if c}


def _unique_courses(courses: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    result: list[dict[str, Any]] = []
    for course in courses:
        if course["code"] in seen:
            continue
        seen.add(course["code"])
        result.append(course)
    return result


def _course_labels(courses: list[dict[str, Any]]) -> list[str]:
    return [_course_label(course) for course in _unique_courses(courses)]


def _course_label(course: dict[str, Any]) -> str:
    grade = course.get("grade")
    grade_suffix = f" ({grade})" if grade else ""
    credits = course.get("credits")
    credit_suffix = f" - {credits:g} cr" if isinstance(credits, (int, float)) else ""
    return f"{course['code']}{grade_suffix}{credit_suffix}"


def _normalize_entry(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "code": _normalize_code(entry.get("code", "")),
        "name": entry.get("name", "") or "",
        "grade": _normalize_grade(entry.get("grade")),
        "semester": entry.get("semester"),
        "credits": float(entry["credits"]) if entry.get("credits") is not None else 0.0,
    }


def _normalize_code(code: str) -> str:
    code = code.strip().upper().replace("-", " ")
    match = re.match(r"([A-Z]{2,4})\s*(\d{4}[A-Z]?)", code)
    if not match:
        return code
    return f"{match.group(1)} {match.group(2)}"


def _normalize_grade(grade: str | None) -> str | None:
    if not grade:
        return None
    normalized = grade.strip().upper()
    if normalized in {"TRANSFER", "TR"}:
        return "T"
    if normalized == "PASS":
        return "P"
    if normalized == "CREDIT":
        return "CR"
    return normalized


def _is_awarded_credit_grade(grade: str | None) -> bool:
    return _normalize_grade(grade) in AWARDED_CREDIT_GRADES


def _grade_rank(grade: str | None) -> float:
    normalized = _normalize_grade(grade)
    if _is_awarded_credit_grade(normalized):
        return 2.0
    return GRADE_POINTS.get(normalized or "", -1)


def _subject(code: str) -> str:
    return code.split(" ")[0] if " " in code else code


def _course_number(code: str) -> int:
    match = re.search(r"(\d{4})", code)
    return int(match.group(1)) if match else 0


def _extract_first_code(text: str) -> str:
    match = re.search(r"[A-Z]{2,4}\s*\d{4}[A-Z]?", text.upper())
    return _normalize_code(match.group(0)) if match else ""


def _pathway_name(section_id: str, concept_name: str | None, section_name: str | None) -> str:
    if section_name:
        return f"Pathways {section_id.upper()} - {section_name}"
    return f"Pathways {section_id.upper()} - {concept_name or ''}".strip()
