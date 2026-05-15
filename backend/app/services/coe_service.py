"""
coe_service.py

Loads course data from backend/data/coe/*.json files (scraped VT timetable).
Each file is {"courses": [{code, name, credits, description, prerequisites}, ...]}
"""

import json
import logging
import os
from functools import lru_cache
from typing import Optional

from app.config import COE_DIR

logger = logging.getLogger(__name__)

# Map common major names / aliases → COE subject file codes
# PRESERVED — non-CS majors are commented out while the app is CS-focused.
# To re-enable other majors, uncomment the relevant lines below.
MAJOR_TO_COE: dict[str, str] = {
    "computer science": "CS",
    "cs": "CS",
    # "electrical engineering": "ECE",
    # "ece": "ECE",
    # "mechanical engineering": "ME",
    # "me": "ME",
    # "aerospace engineering": "AOE",
    # "aoe": "AOE",
    # "industrial engineering": "ISE",
    # "ise": "ISE",
    # "biomedical engineering": "BMES",
    # "bme": "BMES",
    # "bmes": "BMES",
    # "civil engineering": "CEE",
    # "cee": "CEE",
    # "chemical engineering": "CHE",
    # "che": "CHE",
    # "engineering science": "ESM",
    # "esm": "ESM",
    # "engineering education": "ENGE",
    # "enge": "ENGE",
    # "general engineering": "ENGR",
    # "engr": "ENGR",
    # "mining engineering": "MINE",
    # "mine": "MINE",
    # "materials science": "MSE",
    # "mse": "MSE",
    # "biosystems engineering": "BSE",
    # "bse": "BSE",
}

# Canonical full names for each subject code
COE_FULL_NAMES: dict[str, str] = {
    "CS": "Computer Science",
    # PRESERVED — uncomment when expanding beyond CS:
    # "ECE": "Electrical and Computer Engineering",
    # "ME": "Mechanical Engineering",
    # "AOE": "Aerospace Engineering",
    # "ISE": "Industrial and Systems Engineering",
    # "BMES": "Biomedical Engineering",
    # "CEE": "Civil and Environmental Engineering",
    # "CHE": "Chemical Engineering",
    # "ESM": "Engineering Science and Mechanics",
    # "ENGE": "Engineering Education",
    # "ENGR": "General Engineering",
    # "MINE": "Mining Engineering",
    # "MSE": "Materials Science and Engineering",
    # "BSE": "Biosystems Engineering",
}


@lru_cache(maxsize=20)
def load_coe_courses(subject: str) -> list[dict]:
    """Load all courses for a COE subject code (e.g. 'CS'). Cached in memory."""
    path = os.path.join(COE_DIR, f"{subject.upper()}.json")
    if not os.path.exists(path):
        logger.warning("COE file not found: %s", path)
        return []
    try:
        with open(path) as f:
            data = json.load(f)
        return data.get("courses", [])
    except Exception as exc:
        logger.warning("Failed to load COE file %s: %s", path, exc)
        return []


def load_all_coe_courses() -> dict[str, list[dict]]:
    """Load courses for all available COE subjects. Returns {subject: [courses]}."""
    result: dict[str, list[dict]] = {}
    if not os.path.exists(COE_DIR):
        return result
    for fname in os.listdir(COE_DIR):
        if fname.endswith(".json") and fname != "manifest.json":
            subject = fname.replace(".json", "")
            result[subject] = load_coe_courses(subject)
    return result


def resolve_coe_subject(major: str) -> Optional[str]:
    """Return a COE subject code for a given major name/abbreviation, or None if unknown."""
    key = major.lower().strip()
    return MAJOR_TO_COE.get(key)


def resolve_full_major_name(major: str) -> str:
    """Return the full human-readable major name for any alias/abbreviation.
    Falls back to the original input if no mapping exists."""
    subject = resolve_coe_subject(major)
    if subject:
        return COE_FULL_NAMES.get(subject, major)
    first = major.strip().split()[0].upper()
    return COE_FULL_NAMES.get(first, major)


def get_coe_context_for_major(major: str, max_courses: int = 40) -> str:
    """
    Build a compact course-catalog string for injecting into a system prompt.
    Returns an empty string if no COE data is found for the major.
    """
    subject = resolve_coe_subject(major)
    if not subject:
        # Try to infer from the first word
        first = major.strip().split()[0].upper()
        courses = load_coe_courses(first)
        subject = first if courses else None
    else:
        courses = load_coe_courses(subject)

    if not courses:
        return ""

    full_name = COE_FULL_NAMES.get(subject, subject)
    lines = [f"=== {full_name} ({subject}) Course Catalog ({len(courses)} courses) ==="]
    for c in courses[:max_courses]:
        prereq = c.get("prerequisites", "").strip()
        prereq_str = f" | Prereqs: {prereq}" if prereq else ""
        lines.append(
            f"  {c.get('code','')} — {c.get('name','')} ({c.get('credits','?')} cr){prereq_str}"
        )
    if len(courses) > max_courses:
        lines.append(f"  ... and {len(courses) - max_courses} more courses.")
    return "\n".join(lines)
