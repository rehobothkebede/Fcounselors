"""
vt_scraper.py

Virginia Tech course scraper using the VT Timetable API directly.

Fetches courses for a fixed set of subjects and merges them with
structured requirement JSON files from ../data/catalog/.

Usage:
    python vt_scraper.py --term 202601
    python vt_scraper.py --term 202601 --subjects CS MATH

Writes:
    ../data/vt_catalog_{term}.json  — merged output per subject

Output format:
    {
      "SUBJECT": {
        "courses": [...],
        "requirements": {...}
      }
    }

Exit codes: 0 = success, 1 = fatal error
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from typing import Optional

import httpx

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("vt_scraper")

# ── Constants ─────────────────────────────────────────────────────────────────

TIMETABLE_API = "https://apps.cs.vt.edu/timetable/api/courses/{term}/{subject}"

FIXED_SUBJECTS = ["CS", "MATH", "ECE", "ME", "PHYS", "CHEM", "BIOL"]

REQUEST_DELAY = 0.4   # seconds between requests
MAX_RETRIES = 4

# ── Paths ─────────────────────────────────────────────────────────────────────

_SCRAPER_DIR = os.path.dirname(os.path.abspath(__file__))
_DATA_DIR = os.path.join(_SCRAPER_DIR, "..", "data")
_CATALOG_DIR = os.path.join(_DATA_DIR, "catalog")

os.makedirs(_DATA_DIR, exist_ok=True)

# Maps subject code → catalog requirement file basename (without .json)
_SUBJECT_CATALOG_MAP = {
    "CS":   "computer_science",
    "MATH": "mathematics",
    "ECE":  "ece",
    "ME":   "mechanical_engineering",
    "PHYS": None,
    "CHEM": None,
    "BIOL": None,
}


# ── HTTP helpers ──────────────────────────────────────────────────────────────

def _make_client() -> httpx.Client:
    return httpx.Client(
        timeout=20,
        follow_redirects=True,
        headers={"User-Agent": "VT-Advisor-Scraper/3.0 (educational use)"},
    )


def _get_json(url: str, client: httpx.Client) -> Optional[list | dict]:
    """GET JSON with exponential-backoff retry. Returns None on failure."""
    time.sleep(REQUEST_DELAY)
    last_exc: Exception = RuntimeError("no attempts made")
    for attempt in range(MAX_RETRIES):
        try:
            r = client.get(url)
            r.raise_for_status()
            return r.json()
        except (httpx.HTTPStatusError, httpx.TransportError, httpx.TimeoutException) as exc:
            last_exc = exc
            # 4xx errors won't be fixed by retrying
            if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code < 500:
                log.warning("  HTTP %d for %s — skipping", exc.response.status_code, url)
                return None
            wait = 2.0 ** attempt
            log.warning(
                "  Retry %d/%d for %s in %.0fs (%s)",
                attempt + 1, MAX_RETRIES, url, wait, exc,
            )
            time.sleep(wait)
        except json.JSONDecodeError as exc:
            log.warning("  Invalid JSON from %s: %s", url, exc)
            return None
    log.error("  All retries exhausted for %s: %s", url, last_exc)
    return None


# ── Course fetching ───────────────────────────────────────────────────────────

def _normalize_course(raw: dict) -> dict:
    """Extract a clean, flat course record from a raw API entry."""
    return {
        "crn":             raw.get("crn", ""),
        "code":            raw.get("subject_id", "") + " " + raw.get("course_no", ""),
        "name":            raw.get("name", ""),
        "credits":         raw.get("credit_hours", ""),
        "instructor":      raw.get("instructor", ""),
        "schedule":        raw.get("schedule", ""),
        "location":        raw.get("building", "") + " " + raw.get("room", ""),
        "seats_available": raw.get("seats_avail", ""),
        "description":     raw.get("description", ""),
        "prerequisites":   raw.get("pre_reqs", ""),
    }


def fetch_subject_courses(subject: str, term: str, client: httpx.Client) -> list[dict]:
    """Fetch and normalize all course sections for a subject from the timetable API."""
    url = TIMETABLE_API.format(term=term, subject=subject.upper())
    log.info("  Fetching %s from %s", subject, url)

    data = _get_json(url, client)
    if data is None:
        log.warning("  No data returned for %s — skipping", subject)
        return []

    raw_list: list[dict] = data if isinstance(data, list) else data.get("data", [])
    if not raw_list:
        log.info("  %s: 0 courses returned", subject)
        return []

    courses = [_normalize_course(entry) for entry in raw_list]
    log.info("  %s: %d sections fetched", subject, len(courses))
    return courses


# ── Requirement loading ───────────────────────────────────────────────────────

def load_requirements(subject: str) -> dict:
    """Load structured requirements from a catalog JSON file, if it exists."""
    catalog_key = _SUBJECT_CATALOG_MAP.get(subject.upper())
    if catalog_key is None:
        return {}

    path = os.path.join(_CATALOG_DIR, f"{catalog_key}.json")
    if not os.path.exists(path):
        log.warning("  Requirements file not found: %s", path)
        return {}

    try:
        with open(path) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as exc:
        log.warning("  Failed to load requirements for %s: %s", subject, exc)
        return {}


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    global REQUEST_DELAY  # noqa: PLW0603

    parser = argparse.ArgumentParser(
        description="Fetch VT course data and merge with requirement files.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--term", default="202601",
        help="VT term code (e.g. 202601 = Spring 2026)",
    )
    parser.add_argument(
        "--subjects", nargs="+", default=None,
        help=f"Subject codes to scrape (default: {' '.join(FIXED_SUBJECTS)})",
    )
    parser.add_argument(
        "--delay", type=float, default=0.4,
        help="Seconds between HTTP requests",
    )
    args = parser.parse_args()

    REQUEST_DELAY = args.delay

    subjects = [s.upper() for s in args.subjects] if args.subjects else FIXED_SUBJECTS

    log.info("Term: %s | Subjects: %s", args.term, ", ".join(subjects))

    output: dict[str, dict] = {}
    failed: list[str] = []

    with _make_client() as client:
        for subject in subjects:
            log.info("[%s]", subject)
            try:
                courses = fetch_subject_courses(subject, args.term, client)
            except Exception as exc:
                log.error("  Unexpected error fetching %s: %s", subject, exc)
                failed.append(subject)
                continue

            requirements = load_requirements(subject)

            output[subject] = {
                "courses":      courses,
                "requirements": requirements,
            }

    out_path = os.path.join(_DATA_DIR, f"vt_catalog_{args.term}.json")
    payload = {
        "meta": {
            "scraped_at": datetime.now(timezone.utc).isoformat(),
            "term": args.term,
            "subjects": subjects,
            "failed": failed,
        },
        **output,
    }

    try:
        with open(out_path, "w") as f:
            json.dump(payload, f, indent=2)
        log.info("Saved → %s  (%d subjects, %d failed)", out_path, len(output), len(failed))
    except OSError as exc:
        log.error("Failed to write output: %s", exc)
        return 1

    if failed:
        log.warning("Failed subjects: %s", ", ".join(failed))

    log.info("Done.")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
