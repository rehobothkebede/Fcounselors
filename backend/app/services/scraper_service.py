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


def scrape_vt_courses(subject: str, year_term: str = "202509") -> list[dict]:
    """
    Fetch course listings for a VT subject code from the VT Timetable API.
    year_term format: YYYYMM — e.g. 202509 = Fall 2025, 202601 = Spring 2026.
    Returns a list of course dicts and caches them to JSON.
    """
    url = f"{VT_TIMETABLE_BASE}/courses/{year_term}/{subject.upper()}"

    with httpx.Client(timeout=15) as client:
        response = client.get(url)
        response.raise_for_status()
        raw = response.json()

    courses = []
    for entry in raw:
        course = {
            "crn": entry.get("crn"),
            "code": f"{subject.upper()} {entry.get('courseNumber', '')}",
            "name": entry.get("title", ""),
            "credits": entry.get("creditHours", ""),
            "instructor": entry.get("instructor", ""),
            "schedule": entry.get("schedule", ""),
            "location": entry.get("buildingRoom", ""),
            "seats_available": entry.get("seatsAvailable", ""),
            "description": entry.get("description", ""),
            "prerequisites": entry.get("prereqs", ""),
        }
        courses.append(course)

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
