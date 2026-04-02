"""
scraper_service.py

Provides two data sources:
  1. VT Timetable API  — live course listings per subject (scrape_vt_courses)
  2. VT Degree Requirements — hardcoded curriculum DB for common majors
     (the catalog.vt.edu site uses JavaScript rendering, so a static DB is
     more reliable than live scraping).
"""

import httpx
import json
import os
import re
from typing import Optional
from bs4 import BeautifulSoup
from app.config import COURSES_DIR, CATALOG_DIR

VT_TIMETABLE_BASE = "https://apps.cs.vt.edu/timetable/api"

# ── Major name normalization ──────────────────────────────────────────────────

# Maps normalized major names → subject code used in timetable API
MAJOR_TO_SUBJECT: dict[str, str] = {
    "computer science": "CS",
    "cs": "CS",
    "mathematics": "MATH",
    "math": "MATH",
    "electrical engineering": "ECE",
    "ece": "ECE",
    "mechanical engineering": "ME",
    "me": "ME",
    "aerospace engineering": "AOE",
    "aoe": "AOE",
    "industrial engineering": "ISE",
    "ise": "ISE",
    "biomedical engineering": "BME",
    "bme": "BME",
    "civil engineering": "CE",
    "physics": "PHYS",
    "chemistry": "CHEM",
    "biology": "BIOL",
    "psychology": "PSYC",
    "economics": "ECON",
    "finance": "FIN",
    "accounting": "ACIS",
    "marketing": "MKTG",
    "management": "MGT",
}

# Maps subject code → major name (reverse lookup)
SUBJECT_TO_MAJOR: dict[str, str] = {v: k for k, v in MAJOR_TO_SUBJECT.items() if len(v) <= 5}

# ── Hardcoded degree requirements (VT catalog is JS-rendered; DB is reliable) ─

_VT_REQUIREMENTS: dict[str, dict] = {
    "computer science": {
        "required_courses": [
            "CS 1114", "CS 2114", "CS 2505", "CS 2506",
            "CS 3114", "CS 3304", "CS 3744", "CS 4104", "CS 4234",
            "MATH 1225", "MATH 1226", "MATH 2114", "MATH 2534",
            "STAT 4105",
            "ECE 2574",
        ],
        "electives": [
            "CS 3654", "CS 4244", "CS 4284", "CS 4404",
            "CS 4414", "CS 4664", "CS 4734", "CS 4824",
            "CS 4954", "CS 4984",
        ],
        "notes": (
            "Students must complete a senior project (CS 4000-level). "
            "15-credit minimum in CS 3000+ electives. "
            "Verify current requirements with your degree audit."
        ),
    },
    "mathematics": {
        "required_courses": [
            "MATH 1225", "MATH 1226", "MATH 2114", "MATH 2214",
            "MATH 2534", "MATH 3034", "MATH 3124", "MATH 4225",
            "MATH 4226", "MATH 4564",
        ],
        "electives": [
            "MATH 4124", "MATH 4134", "MATH 4324", "MATH 4334",
            "MATH 4424", "MATH 4434", "MATH 4544",
        ],
        "notes": (
            "Students choosing the applied track need STAT 4105 or STAT 4106. "
            "Pure math track requires proof-based courses at 4000-level."
        ),
    },
    "electrical engineering": {
        "required_courses": [
            "ECE 2004", "ECE 2014", "ECE 2024", "ECE 2034",
            "ECE 2074", "ECE 2564", "ECE 2574",
            "ECE 3004", "ECE 3054", "ECE 3074",
            "ECE 4524", "ECE 4534",
            "MATH 1225", "MATH 1226", "MATH 2114", "MATH 2214",
            "PHYS 2305", "PHYS 2306",
        ],
        "electives": [
            "ECE 4104", "ECE 4154", "ECE 4214", "ECE 4264",
            "ECE 4404", "ECE 4414", "ECE 4424", "ECE 4444",
        ],
        "notes": (
            "Senior design is a two-semester sequence (ECE 4524/4534). "
            "Four technical elective credits required at 4000-level."
        ),
    },
    "mechanical engineering": {
        "required_courses": [
            "ME 2004", "ME 2024", "ME 2134", "ME 3134",
            "ME 3404", "ME 3504", "ME 3514", "ME 3524",
            "ME 4024", "ME 4154", "ME 4974",
            "MATH 1225", "MATH 1226", "MATH 2114", "MATH 2214",
            "PHYS 2305", "PHYS 2306",
            "CHEM 1035", "CHEM 1045",
        ],
        "electives": [
            "ME 4214", "ME 4234", "ME 4244", "ME 4314",
            "ME 4324", "ME 4334", "ME 4344",
        ],
        "notes": "Senior Capstone Design is two semesters (ME 4024 + ME 4974).",
    },
    "aerospace engineering": {
        "required_courses": [
            "AOE 2074", "AOE 3014", "AOE 3024", "AOE 3034",
            "AOE 3044", "AOE 3054", "AOE 3094",
            "AOE 4054", "AOE 4065", "AOE 4164",
            "MATH 1225", "MATH 1226", "MATH 2114", "MATH 2214",
            "PHYS 2305", "PHYS 2306",
        ],
        "electives": [
            "AOE 4104", "AOE 4154", "AOE 4204", "AOE 4254",
        ],
        "notes": "Senior capstone is AOE 4065 (two-semester sequence).",
    },
    "industrial engineering": {
        "required_courses": [
            "ISE 2014", "ISE 2024", "ISE 3014", "ISE 3034",
            "ISE 3414", "ISE 3424", "ISE 4014", "ISE 4034",
            "MATH 1225", "MATH 1226", "MATH 2114",
            "STAT 3604", "STAT 4604",
        ],
        "electives": [
            "ISE 4154", "ISE 4164", "ISE 4174", "ISE 4314",
        ],
        "notes": "ISE 4034 is the senior design capstone.",
    },
    "physics": {
        "required_courses": [
            "PHYS 2305", "PHYS 2306", "PHYS 3305", "PHYS 3316",
            "PHYS 3406", "PHYS 4175", "PHYS 4455", "PHYS 4456",
            "MATH 1225", "MATH 1226", "MATH 2114", "MATH 2214",
        ],
        "electives": [
            "PHYS 4264", "PHYS 4274", "PHYS 4324", "PHYS 4414",
        ],
        "notes": "Senior thesis or independent research recommended for grad school track.",
    },
    "economics": {
        "required_courses": [
            "ECON 2005", "ECON 2006", "ECON 3005", "ECON 3006",
            "ECON 3104", "ECON 4005", "ECON 4006",
            "STAT 3005",
        ],
        "electives": [
            "ECON 4014", "ECON 4024", "ECON 4034", "ECON 4054",
            "ECON 4105", "ECON 4116",
        ],
        "notes": "Econometrics (ECON 4005) requires prior statistics coursework.",
    },
}


def _normalize_major(major: str) -> str:
    """Normalize various major name inputs to a canonical key."""
    cleaned = major.lower().strip()
    cleaned = re.sub(r"\b(major|degree|bs|b\.s\.|ba|b\.a\.|program)\b", "", cleaned).strip()
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned


# Explicit alias map: abbreviations / alternate names → canonical _VT_REQUIREMENTS key
_MAJOR_ALIASES: dict[str, str] = {
    "cs": "computer science",
    "ece": "electrical engineering",
    "ee": "electrical engineering",
    "me": "mechanical engineering",
    "aoe": "aerospace engineering",
    "ise": "industrial engineering",
    "bme": "biomedical engineering",
    "ce": "civil engineering",
    "math": "mathematics",
    "phys": "physics",
    "chem": "chemistry",
    "biol": "biology",
    "psyc": "psychology",
    "econ": "economics",
    "fin": "finance",
    "acis": "accounting",
    "mktg": "marketing",
    "mgt": "management",
}


def _lookup_requirements(major: str) -> Optional[dict]:
    """Return hardcoded requirements for a major, or None if not found."""
    key = _normalize_major(major)

    # Direct match
    if key in _VT_REQUIREMENTS:
        return _VT_REQUIREMENTS[key]

    # Alias match (handles "cs", "ece", etc.)
    if key in _MAJOR_ALIASES:
        return _VT_REQUIREMENTS.get(_MAJOR_ALIASES[key])

    # Subject code from first word (handles "CS 1114" style input or "CS major")
    first_word = key.split()[0].upper() if key else ""
    alias_key = first_word.lower()
    if alias_key in _MAJOR_ALIASES:
        return _VT_REQUIREMENTS.get(_MAJOR_ALIASES[alias_key])

    # Substring match (e.g. "mechanical" finds "mechanical engineering")
    for k, v in _VT_REQUIREMENTS.items():
        if key in k or k in key:
            return v

    return None


# ── Catalog public API ────────────────────────────────────────────────────────

def _catalog_file(major: str) -> str:
    safe = re.sub(r"[^\w]", "_", _normalize_major(major))
    return os.path.join(CATALOG_DIR, f"{safe}.json")


def load_catalog(major: str) -> Optional[dict]:
    """Return cached catalog data for a major, or None."""
    path = _catalog_file(major)
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return None


def save_catalog(major: str, data: dict) -> None:
    with open(_catalog_file(major), "w") as f:
        json.dump(data, f, indent=2)


def scrape_vt_major_catalog(major: str) -> dict:
    """
    Return degree requirements for a VT major.

    Checks local cache first, then the built-in curriculum database.
    The VT catalog (catalog.vt.edu) uses JavaScript rendering and cannot
    be scraped with httpx alone, so requirements come from a curated DB.

    Returns:
        {
            "major": str,
            "required_courses": list[str],
            "electives": list[str],
            "notes": str,
        }
    Never raises — returns an empty structure if the major is not found.
    """
    # Check file cache
    cached = load_catalog(major)
    if cached is not None:
        return cached

    # Look up from built-in database
    data = _lookup_requirements(major)
    if data is not None:
        result = {"major": major, **data}
        save_catalog(major, result)
        return result

    # Unknown major — return empty structure
    return {
        "major": major,
        "required_courses": [],
        "electives": [],
        "notes": (
            f"Degree requirements for '{major}' are not in the local database. "
            "Verify requirements with your official VT degree audit."
        ),
    }


# ── Courses (timetable) ──────────────────────────────────────────────────────

def _courses_file(subject: str) -> str:
    return os.path.join(COURSES_DIR, f"{subject.upper()}.json")


def load_courses(subject: str) -> Optional[list]:
    """Return cached courses for a subject, or None if not yet scraped."""
    path = _courses_file(subject)
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return None


def save_courses(subject: str, courses: list[dict]) -> None:
    with open(_courses_file(subject), "w") as f:
        json.dump(courses, f, indent=2)


def _normalize_course(entry: dict, subject: str) -> dict:
    """Normalize a raw VT API entry into a consistent course dict."""
    return {
        "crn": entry.get("crn"),
        "code": f"{subject.upper()} {entry.get('courseNumber', '')}".strip(),
        "name": entry.get("title", ""),
        "credits": entry.get("creditHours", ""),
        "instructor": entry.get("instructor", ""),
        "schedule": entry.get("schedule", ""),
        "location": entry.get("buildingRoom", ""),
        "seats_available": entry.get("seatsAvailable", ""),
        "description": entry.get("description", ""),
        "prerequisites": entry.get("prereqs", ""),
    }


def scrape_vt_courses(subject: str, year_term: str = "202509") -> list[dict]:
    """
    Fetch course listings for a VT subject code from the VT Timetable API.
    year_term format: YYYYMM — e.g. 202509 = Fall 2025, 202601 = Spring 2026.

    Falls back to cached data if the API is unreachable.
    Returns a normalized list of course dicts and caches them to JSON.
    """
    url = f"{VT_TIMETABLE_BASE}/courses/{year_term}/{subject.upper()}"

    try:
        with httpx.Client(timeout=15) as client:
            response = client.get(url)
            response.raise_for_status()
            raw = response.json()
    except Exception as e:
        cached = load_courses(subject)
        if cached is not None:
            return cached
        raise RuntimeError(f"Scrape failed and no cache available for {subject}: {e}") from e

    courses = [_normalize_course(entry, subject) for entry in raw]
    save_courses(subject, courses)
    return courses


def scrape_vt_catalog_page(url: str) -> str:
    """
    Generic scraper for a VT course catalog HTML page.
    Returns the raw text content for AI parsing.
    """
    with httpx.Client(timeout=15, follow_redirects=True) as client:
        response = client.get(url)
        response.raise_for_status()

    soup = BeautifulSoup(response.text, "html.parser")
    for tag in soup(["script", "style", "nav", "footer", "header"]):
        tag.decompose()

    return soup.get_text(separator="\n", strip=True)


def list_cached_subjects() -> list[str]:
    """Return all subject codes that have been scraped and cached."""
    files = os.listdir(COURSES_DIR)
    return [f.replace(".json", "") for f in files if f.endswith(".json")]
