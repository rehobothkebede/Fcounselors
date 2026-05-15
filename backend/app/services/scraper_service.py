"""
scraper_service.py

Read-only access to the VT catalog data populated by scraper/vt_scraper.py.

Priority order for every lookup:
  1. vt_full_catalog.json  (merged dataset from full crawl)
  2. data/courses/{SUBJECT}.json  (per-subject backward-compat files)
  3. data/catalog/{major}.json    (per-major backward-compat files)

Run the scraper to populate:
    cd backend/scraper
    python vt_scraper.py --term 202601
"""

import json
import logging
import os
import re
from functools import lru_cache
from typing import Optional

from app.config import (
    CATALOG_DIR,
    COURSES_DIR,
    VT_FULL_CATALOG_PATH,
    VT_PROGRAMS_PATH,
    VT_SUBJECTS_PATH,
)

logger = logging.getLogger(__name__)


# ── Full catalog loader ───────────────────────────────────────────────────────

@lru_cache(maxsize=1)
def _load_full_catalog() -> Optional[dict]:
    """Load vt_full_catalog.json once and cache in memory."""
    if not os.path.exists(VT_FULL_CATALOG_PATH):
        return None
    try:
        with open(VT_FULL_CATALOG_PATH) as f:
            return json.load(f)
    except Exception as exc:
        logger.warning("Failed to load full catalog: %s", exc)
        return None


def get_catalog_meta() -> Optional[dict]:
    """Return the meta block from the full catalog, or None."""
    cat = _load_full_catalog()
    return cat.get("meta") if cat else None


# ── Subject helpers ───────────────────────────────────────────────────────────

def list_all_subjects() -> list[dict]:
    """
    Return all known subjects as [{"code": "CS", "name": "...", "url": "..."}].
    Prefers the full catalog; falls back to listing data/courses/*.json files.
    """
    cat = _load_full_catalog()
    if cat and cat.get("subjects"):
        return cat["subjects"]

    # Fallback: derive from cached per-subject files
    if os.path.exists(VT_SUBJECTS_PATH):
        try:
            with open(VT_SUBJECTS_PATH) as f:
                return json.load(f)
        except Exception:
            pass

    files = os.listdir(COURSES_DIR)
    return [{"code": f.replace(".json", ""), "name": "", "url": ""} for f in files if f.endswith(".json")]


def list_cached_subjects() -> list[str]:
    """Return all subject codes (strings). Used by /courses/subjects endpoint."""
    return [s["code"] for s in list_all_subjects()]


# ── Course helpers ────────────────────────────────────────────────────────────

def load_courses(subject: str) -> Optional[list]:
    """
    Return section listings for a subject code, or None if not cached.
    Checks full catalog first, then per-subject file.
    """
    code = subject.upper()

    # Full catalog
    cat = _load_full_catalog()
    if cat:
        courses = cat.get("courses", {}).get(code)
        if courses is not None:
            return courses

    # Per-subject file (backward compat)
    path = os.path.join(COURSES_DIR, f"{code}.json")
    if os.path.exists(path):
        try:
            with open(path) as f:
                return json.load(f)
        except Exception as exc:
            logger.warning("Failed to read %s: %s", path, exc)

    return None


def load_unique_courses(subject: str) -> Optional[list]:
    """
    Return deduplicated course records (one per course code) for a subject.
    Only available from the full catalog.
    """
    code = subject.upper()
    cat = _load_full_catalog()
    if cat:
        return cat.get("unique_courses", {}).get(code)
    return None


def search_courses_by_keyword(keyword: str) -> list[dict]:
    """
    Search all unique courses across all subjects for a keyword in name/description.
    Returns list of course dicts with an added 'subject' field.
    """
    cat = _load_full_catalog()
    if not cat:
        return []

    kw = keyword.lower()
    results: list[dict] = []
    for subject, courses in cat.get("unique_courses", {}).items():
        for c in courses:
            if kw in c.get("name", "").lower() or kw in c.get("description", "").lower():
                results.append({**c, "subject": subject})
    return results


# ── Program helpers ───────────────────────────────────────────────────────────

def list_all_programs() -> list[dict]:
    """
    Return all known programs (majors, minors, options).
    Prefers full catalog, falls back to vt_programs.json.
    """
    cat = _load_full_catalog()
    if cat and cat.get("programs"):
        return cat["programs"]

    if os.path.exists(VT_PROGRAMS_PATH):
        try:
            with open(VT_PROGRAMS_PATH) as f:
                return json.load(f)
        except Exception:
            pass

    return []


def search_programs(keyword: str) -> list[dict]:
    """Return programs whose name contains keyword (case-insensitive)."""
    kw = keyword.lower()
    return [p for p in list_all_programs() if kw in p.get("name", "").lower()]


# ── Catalog / requirements helpers ───────────────────────────────────────────

def _normalize_major(major: str) -> str:
    cleaned = major.lower().strip()
    cleaned = re.sub(r"\b(major|degree|bs|b\.s\.|ba|b\.a\.|program|minor|option)\b", "", cleaned).strip()
    return re.sub(r"\s+", " ", cleaned)


def _requirements_from_full_catalog(major: str) -> Optional[dict]:
    """Look up degree requirements from the full catalog's program_requirements index."""
    cat = _load_full_catalog()
    if not cat:
        return None

    index: dict = cat.get("program_requirements", {})
    key = _normalize_major(major)

    # Exact match
    if key in index:
        return index[key]

    # Prefix match on first word (e.g. "cs" → "computer science")
    first = key.split()[0] if key else ""
    for k, v in index.items():
        if first and (first in k or k.startswith(first)):
            return v

    # Substring match
    for k, v in index.items():
        if key in k or k in key:
            return v

    return None


def load_catalog(major: str) -> Optional[dict]:
    """
    Return degree requirements for a major.
    Checks full catalog first, then per-major JSON files in data/catalog/.
    """
    # Full catalog
    result = _requirements_from_full_catalog(major)
    if result is not None:
        return result

    # Per-major file (backward compat)
    safe = re.sub(r"[^\w]", "_", _normalize_major(major))
    path = os.path.join(CATALOG_DIR, f"{safe}.json")
    if os.path.exists(path):
        try:
            with open(path) as f:
                return json.load(f)
        except Exception as exc:
            logger.warning("Failed to read %s: %s", path, exc)

    return None


def scrape_vt_major_catalog(major: str) -> dict:
    """
    Return degree requirements for a major from the local cache.
    If not cached, returns an empty structure with instructions.
    Run scraper/vt_scraper.py to populate the cache.
    """
    cached = load_catalog(major)
    if cached is not None:
        return cached
    return {
        "major": major,
        "required_courses": [],
        "electives": [],
        "notes": (
            f"No cached data for '{major}'. "
            "Run `python scraper/vt_scraper.py` to populate the data cache."
        ),
    }


# ── Subject→major resolution (kept for advisor route) ────────────────────────

# Seed map for common aliases — the full catalog supplements this at runtime
# PRESERVED — non-CS subjects are commented out while the app is CS-focused.
# To expand to other majors, uncomment the relevant lines below.
MAJOR_TO_SUBJECT: dict[str, str] = {
    "computer science": "CS",
    "cs": "CS",
    # "mathematics": "MATH",
    # "math": "MATH",
    # "electrical engineering": "ECE",
    # "ece": "ECE",
    # "mechanical engineering": "ME",
    # "me": "ME",
    # "aerospace engineering": "AOE",
    # "aoe": "AOE",
    # "industrial engineering": "ISE",
    # "ise": "ISE",
    # "biomedical engineering": "BME",
    # "bme": "BME",
    # "civil engineering": "CE",
    # "physics": "PHYS",
    # "chemistry": "CHEM",
    # "biology": "BIOL",
    # "psychology": "PSYC",
    # "economics": "ECON",
    # "finance": "FIN",
    # "accounting": "ACIS",
    # "marketing": "MKTG",
    # "management": "MGT",
}


def resolve_subject_for_major(major: str) -> str:
    """
    Given a major name, return the most likely subject code.
    Checks the full catalog's program list, then falls back to the seed map.
    """
    key = _normalize_major(major)

    # Seed map fast path
    if key in MAJOR_TO_SUBJECT:
        return MAJOR_TO_SUBJECT[key]

    # Try to find a program in the full catalog and infer subject from required courses
    reqs = _requirements_from_full_catalog(major)
    if reqs and reqs.get("required_courses"):
        first_code = reqs["required_courses"][0]
        m = re.match(r"^([A-Z]{2,5})\s+\d", first_code)
        if m:
            return m.group(1)

    # Fallback: first word of major name upper-cased
    return major.strip().split()[0].upper()
