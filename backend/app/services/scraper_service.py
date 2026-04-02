import httpx
import json
import os
from typing import Optional
from bs4 import BeautifulSoup
from app.config import COURSES_DIR

VT_TIMETABLE_BASE = "https://apps.cs.vt.edu/timetable/api"


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
