"""
vt_scraper.py

Full Virginia Tech undergraduate catalog crawler.

Discovers ALL subject prefixes and programs dynamically — no hardcoded dictionaries.

Usage:
    python vt_scraper.py --term 202601
    python vt_scraper.py --term 202601 --subjects CS MATH ECE
    python vt_scraper.py --term 202601 --skip-timetable
    python vt_scraper.py --term 202601 --skip-programs

Writes:
    ../data/vt_subjects.json          — all discovered subject codes
    ../data/vt_programs.json          — all discovered programs/minors/options
    ../data/vt_full_catalog.json      — merged dataset (meta + subjects + programs + courses)
    ../data/courses/{SUBJECT}.json    — per-subject course listings (backward compat)

Exit codes: 0 = success, 1 = fatal error
"""

import argparse
import json
import logging
import os
import re
import sys
import time
from datetime import datetime, timezone
from typing import Optional

import httpx
import requests as _requests
from bs4 import BeautifulSoup

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("vt_scraper")

# ── Constants ─────────────────────────────────────────────────────────────────

CATALOG_BASE = "https://catalog.vt.edu"

COURSE_CODE_RE = re.compile(r"\b([A-Z]{2,5})\s+(\d{4}[A-Z]?)\b")

# Seconds to wait between HTTP requests (rate limiting)
REQUEST_DELAY = 0.4

# Max retries per request
MAX_RETRIES = 4

# ── Paths ─────────────────────────────────────────────────────────────────────

_SCRAPER_DIR = os.path.dirname(os.path.abspath(__file__))
_DATA_DIR = os.path.join(_SCRAPER_DIR, "..", "data")
COURSES_DIR = os.path.join(_DATA_DIR, "courses")
CATALOG_DIR = os.path.join(_DATA_DIR, "catalog")

for _d in (_DATA_DIR, COURSES_DIR, CATALOG_DIR):
    os.makedirs(_d, exist_ok=True)

VT_FULL_CATALOG_PATH = os.path.join(_DATA_DIR, "vt_full_catalog.json")
VT_SUBJECTS_PATH = os.path.join(_DATA_DIR, "vt_subjects.json")
VT_PROGRAMS_PATH = os.path.join(_DATA_DIR, "vt_programs.json")


# ── HTTP helpers ──────────────────────────────────────────────────────────────

def _make_client() -> httpx.Client:
    return httpx.Client(
        timeout=20,
        follow_redirects=True,
        headers={"User-Agent": "VT-Advisor-Scraper/2.0 (educational use)"},
    )


def _get(url: str, client: httpx.Client, max_retries: int = MAX_RETRIES) -> httpx.Response:
    """GET with exponential-backoff retry and rate-limit delay.

    Handles 202 Accepted (page still generating) by polling up to max_retries times.
    """
    time.sleep(REQUEST_DELAY)
    last_exc: Exception = RuntimeError("no attempts made")
    last_202_response: Optional[httpx.Response] = None
    for attempt in range(max_retries):
        try:
            r = client.get(url)
            r.raise_for_status()
            # 202 Accepted means the server is still generating the page; poll.
            if r.status_code == 202:
                wait = 2.0 ** attempt
                log.debug("  202 Accepted for %s — retrying in %.0fs (attempt %d/%d)", url, wait, attempt + 1, max_retries)
                last_202_response = r
                last_exc = RuntimeError(f"server kept returning 202 after {max_retries} attempts (JS-rendered page?): {url}")
                time.sleep(wait)
                continue
            return r
        except (httpx.HTTPStatusError, httpx.TransportError, httpx.TimeoutException) as exc:
            last_exc = exc
            if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code < 500:
                # 4xx — no point retrying
                raise
            wait = 2.0 ** attempt
            log.warning("  Retry %d/%d for %s in %.0fs (%s)", attempt + 1, max_retries, url, wait, exc)
            time.sleep(wait)
    raise last_exc


def _page_text(soup: BeautifulSoup) -> str:
    """Strip boilerplate tags and return plain text."""
    for tag in soup(["script", "style", "nav", "footer", "header", "noscript"]):
        tag.decompose()
    return soup.get_text(separator="\n", strip=True)


# ── Subject discovery ─────────────────────────────────────────────────────────

def _discover_subjects_from_catalog(client: httpx.Client) -> list[dict]:
    """
    Scrape https://catalog.vt.edu/undergraduate/course-descriptions/ and return
    every subject entry: {"code": "CS", "name": "Computer Science", "url": "..."}.
    Returns an empty list if the page is JS-rendered or unreachable.
    """
    url = f"{CATALOG_BASE}/undergraduate/course-descriptions/"
    log.info("Discovering subjects from catalog: %s", url)
    try:
        r = _get(url, client)
    except Exception as exc:
        log.warning("Cannot reach course-descriptions index: %s", exc)
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    subjects: list[dict] = []
    seen: set[str] = set()

    # VT formats link text as "Computer Science (CS)" or "Mathematics (MATH)"
    _code_re = re.compile(r"^(.*?)\s*\(([A-Z]{2,5})\)\s*$")

    for a in soup.find_all("a", href=True):
        href: str = a["href"]
        if "/course-descriptions/" not in href:
            continue
        text = a.get_text(strip=True)
        m = _code_re.match(text)
        if not m:
            continue
        name = m.group(1).strip()
        code = m.group(2)
        if code in seen:
            continue
        seen.add(code)
        full_url = href if href.startswith("http") else f"{CATALOG_BASE}{href}"
        subjects.append({"code": code, "name": name, "url": full_url})

    log.info("  Found %d subject codes from catalog", len(subjects))
    return subjects


def discover_subjects(client: httpx.Client) -> list[dict]:
    """
    Return every subject as {"code": "CS", "name": "Computer Science", "url": "..."}.
    Source: catalog HTML index page. If the page is JS-rendered (returns 202 or empty),
    subject discovery fails — use --subjects to specify codes explicitly.
    """
    subjects = _discover_subjects_from_catalog(client)
    if not subjects:
        log.warning("Catalog subject discovery returned nothing (page may be JS-rendered).")
        log.warning("Use --subjects CS MATH ECE ... to specify subject codes directly.")
    return subjects


# ── Program discovery ─────────────────────────────────────────────────────────

def _extract_program_links(soup: BeautifulSoup, base: str, prog_type: str) -> list[dict]:
    """Pull all unique program links from a parsed page."""
    results: list[dict] = []
    seen: set[str] = set()
    for a in soup.find_all("a", href=True):
        href: str = a["href"]
        # Skip anchors, external, and bare index pages
        if not href or href.startswith("#") or href.startswith("http") and CATALOG_BASE not in href:
            continue
        if href in ("/undergraduate/", "/", ""):
            continue
        full_url = href if href.startswith("http") else f"{CATALOG_BASE}{href}"
        if full_url in seen:
            continue
        seen.add(full_url)
        name = a.get_text(strip=True)
        if not name or len(name) < 3:
            continue
        results.append({"name": name, "url": full_url, "type": prog_type, "raw_text": "", "required_courses": [], "electives": []})
    return results


def _scrape_program_page(url: str, client: httpx.Client) -> tuple[str, list[str], list[str]]:
    """
    Fetch a program page and return (raw_text, required_courses, electives).
    Extracts course codes like 'CS 1114' from the page text.
    """
    try:
        r = _get(url, client)
    except Exception as exc:
        log.debug("    Skipping program page %s: %s", url, exc)
        return "", [], []

    soup = BeautifulSoup(r.text, "html.parser")
    text = _page_text(soup)

    # Find all course codes in the text
    all_codes = [f"{m.group(1)} {m.group(2)}" for m in COURSE_CODE_RE.finditer(text)]

    # Heuristic: codes near "required" → required; near "elective" → elective
    required: list[str] = []
    electives: list[str] = []
    lower = text.lower()

    # Find section offsets
    req_pos = [m.start() for m in re.finditer(r"\brequired\b", lower)]
    elec_pos = [m.start() for m in re.finditer(r"\belective\b", lower)]

    for m in COURSE_CODE_RE.finditer(text):
        code = f"{m.group(1)} {m.group(2)}"
        pos = m.start()
        # Distance to nearest "required" vs "elective" header
        nearest_req = min((abs(pos - p) for p in req_pos), default=999999)
        nearest_elec = min((abs(pos - p) for p in elec_pos), default=999999)
        if nearest_req <= nearest_elec and nearest_req < 2000:
            if code not in required:
                required.append(code)
        elif nearest_elec < 2000:
            if code not in electives:
                electives.append(code)
        else:
            # Default: treat as required if no elective context found
            if not elec_pos and code not in required:
                required.append(code)

    return text, required, electives


def discover_programs(client: httpx.Client, scrape_pages: bool = True) -> list[dict]:
    """
    Discover all VT undergraduate programs from three sources:
      1. /program-explorer/
      2. /undergraduate/  (college/dept navigation)
      3. /undergraduate/minors/
    Then optionally fetch each program page for requirements.
    """
    all_programs: dict[str, dict] = {}  # keyed by URL to dedupe

    def _register(entries: list[dict]) -> None:
        for e in entries:
            if e["url"] not in all_programs:
                all_programs[e["url"]] = e

    # ── Source 1: program-explorer ────────────────────────────────────────────
    log.info("Discovering programs from program-explorer...")
    try:
        r = _get(f"{CATALOG_BASE}/program-explorer/", client)
        soup = BeautifulSoup(r.text, "html.parser")
        _register(_extract_program_links(soup, CATALOG_BASE, "major"))
    except Exception as exc:
        log.warning("  program-explorer unavailable: %s", exc)

    # ── Source 2: undergraduate index ─────────────────────────────────────────
    log.info("Discovering programs from undergraduate index...")
    try:
        r = _get(f"{CATALOG_BASE}/undergraduate/", client)
        soup = BeautifulSoup(r.text, "html.parser")
        college_links = [
            a["href"] for a in soup.find_all("a", href=True)
            if re.search(r"/undergraduate/[^/]+/?$", a["href"])
            and "course-descriptions" not in a["href"]
            and "minors" not in a["href"]
        ]
        log.info("  Found %d college/dept links", len(college_links))
        for href in college_links[:30]:  # cap depth
            dept_url = href if href.startswith("http") else f"{CATALOG_BASE}{href}"
            try:
                r2 = _get(dept_url, client)
                soup2 = BeautifulSoup(r2.text, "html.parser")
                _register(_extract_program_links(soup2, CATALOG_BASE, "major"))
            except Exception as exc:
                log.debug("  Skipping %s: %s", dept_url, exc)
    except Exception as exc:
        log.warning("  Undergraduate index unavailable: %s", exc)

    # ── Source 3: minors ──────────────────────────────────────────────────────
    log.info("Discovering minors...")
    try:
        r = _get(f"{CATALOG_BASE}/undergraduate/minors/", client)
        soup = BeautifulSoup(r.text, "html.parser")
        minor_entries = [
            e for e in _extract_program_links(soup, CATALOG_BASE, "minor")
            if "/minors/" in e["url"] and e["url"] != f"{CATALOG_BASE}/undergraduate/minors/"
        ]
        _register(minor_entries)
        log.info("  Found %d minor links", len(minor_entries))
    except Exception as exc:
        log.warning("  Minors page unavailable: %s", exc)

    programs = list(all_programs.values())

    # Filter to only undergraduate catalog paths (skip external/irrelevant)
    programs = [
        p for p in programs
        if CATALOG_BASE in p["url"]
        and "/undergraduate/" in p["url"]
        and p["url"] != f"{CATALOG_BASE}/undergraduate/"
    ]

    log.info("Total unique programs discovered: %d", len(programs))

    # ── Fetch individual program pages ────────────────────────────────────────
    if scrape_pages:
        log.info("Fetching %d program pages for requirements...", len(programs))
        for i, prog in enumerate(programs, 1):
            if i % 20 == 0:
                log.info("  Progress: %d/%d", i, len(programs))
            text, required, electives = _scrape_program_page(prog["url"], client)
            prog["raw_text"] = text
            prog["required_courses"] = required
            prog["electives"] = electives

    return programs


# ── Timetable course fetching (via py-vt / Banner) ───────────────────────────

_timetable = pyvt.Timetable()


def _normalize_section(section: pyvt.Section) -> dict:
    days = " ".join(section.days) if isinstance(section.days, list) else (section.days or "")
    schedule = f"{days} {section.begin_time}-{section.end_time}".strip() if (section.begin_time or days) else ""
    return {
        "crn": section.crn,
        "code": section.code,
        "name": section.name,
        "credits": section.credits,
        "instructor": section.instructor,
        "schedule": schedule,
        "location": section.location,
        "seats_available": section.capacity,
        "description": "",
        "prerequisites": "",
    }


def fetch_subject_courses(subject: str, term: str, client: httpx.Client) -> list[dict]:
    """Fetch all sections for a subject via py-vt (Banner)."""
    try:
        raw = _timetable.subject_lookup(subject.upper(), term_year=term, open_only=False)
    except Exception as exc:
        log.warning("  Timetable fetch failed for %s: %s", subject, exc)
        return []

    if raw is None:
        return []

    sections = [_normalize_section(s) for s in raw]

    # Write per-subject cache (backward compat)
    path = os.path.join(COURSES_DIR, f"{subject.upper()}.json")
    with open(path, "w") as f:
        json.dump(sections, f, indent=2)

    return sections


def dedupe_courses(sections: list[dict]) -> list[dict]:
    """Collapse multiple sections into unique course records."""
    seen: dict[str, dict] = {}
    for s in sections:
        code = s["code"]
        if code not in seen:
            seen[code] = {
                "code": code,
                "name": s["name"],
                "credits": s["credits"],
                "description": s["description"],
                "prerequisites": s["prerequisites"],
                "section_count": 1,
            }
        else:
            seen[code]["section_count"] += 1
    return list(seen.values())


# ── Merge & save ──────────────────────────────────────────────────────────────

def build_program_requirements_index(programs: list[dict]) -> dict:
    """
    Build a flat lookup: normalized_name → {required_courses, electives, notes, url}.
    Used by the advisor service for "what courses does X require?"
    """
    index: dict[str, dict] = {}
    for p in programs:
        key = re.sub(r"\s+", " ", p["name"].lower().strip())
        key = re.sub(r"\b(major|degree|bs|b\.s\.|ba|b\.a\.|program|minor|option)\b", "", key).strip()
        if not key:
            continue
        index[key] = {
            "name": p["name"],
            "type": p.get("type", "major"),
            "url": p["url"],
            "required_courses": p.get("required_courses", []),
            "electives": p.get("electives", []),
            "notes": f"Requirements scraped from {p['url']}. Verify with your degree audit.",
        }
    return index


def save_outputs(
    subjects: list[dict],
    programs: list[dict],
    courses_by_subject: dict[str, list[dict]],
    term: str,
) -> None:
    """Write vt_subjects.json, vt_programs.json, vt_full_catalog.json."""

    # Strip raw_text from programs for the slim programs file
    slim_programs = [
        {k: v for k, v in p.items() if k != "raw_text"}
        for p in programs
    ]

    with open(VT_SUBJECTS_PATH, "w") as f:
        json.dump(subjects, f, indent=2)
    log.info("Saved %d subjects → %s", len(subjects), VT_SUBJECTS_PATH)

    with open(VT_PROGRAMS_PATH, "w") as f:
        json.dump(slim_programs, f, indent=2)
    log.info("Saved %d programs → %s", len(slim_programs), VT_PROGRAMS_PATH)

    # Build unique-course map per subject
    unique_courses: dict[str, list[dict]] = {}
    for subject, sections in courses_by_subject.items():
        unique_courses[subject] = dedupe_courses(sections)

    total_sections = sum(len(v) for v in courses_by_subject.values())
    total_unique = sum(len(v) for v in unique_courses.values())

    catalog = {
        "meta": {
            "scraped_at": datetime.now(timezone.utc).isoformat(),
            "term": term,
            "subject_count": len(subjects),
            "program_count": len(programs),
            "total_sections": total_sections,
            "unique_course_count": total_unique,
        },
        "subjects": subjects,
        "programs": slim_programs,
        "courses": courses_by_subject,
        "unique_courses": unique_courses,
        "program_requirements": build_program_requirements_index(programs),
    }

    with open(VT_FULL_CATALOG_PATH, "w") as f:
        json.dump(catalog, f, indent=2)
    log.info(
        "Saved full catalog → %s  (%d subjects, %d programs, %d sections, %d unique courses)",
        VT_FULL_CATALOG_PATH, len(subjects), len(programs), total_sections, total_unique,
    )


# ── CLI entry point ───────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Crawl the full VT undergraduate catalog and timetable API.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--term", default="202601", help="VT term code (e.g. 202601 = Spring 2026)")
    parser.add_argument("--subjects", nargs="+", default=None, help="Only scrape these subject codes")
    parser.add_argument("--skip-timetable", action="store_true", help="Skip timetable API calls")
    parser.add_argument("--skip-programs", action="store_true", help="Skip program discovery")
    parser.add_argument("--skip-program-pages", action="store_true", help="Discover programs but skip fetching individual pages")
    parser.add_argument("--delay", type=float, default=0.4, help="Seconds between requests")
    args = parser.parse_args()

    global REQUEST_DELAY
    REQUEST_DELAY = args.delay

    courses_by_subject: dict[str, list[dict]] = {}
    programs: list[dict] = []

    with _make_client() as client:

        # ── 1. Discover subjects ──────────────────────────────────────────────
        if args.subjects:
            subjects = [{"code": s.upper(), "name": s.upper(), "url": ""} for s in args.subjects]
            log.info("Using %d user-specified subjects", len(subjects))
        else:
            subjects = discover_subjects(client)
            if not subjects:
                log.error("Subject discovery returned nothing — aborting.")
                return 1

        # ── 2. Discover programs ──────────────────────────────────────────────
        if not args.skip_programs:
            programs = discover_programs(
                client,
                scrape_pages=not args.skip_program_pages,
            )
        else:
            log.info("Skipping program discovery (--skip-programs)")

        # ── 3. Fetch timetable courses ────────────────────────────────────────
        if not args.skip_timetable:
            log.info("Fetching timetable courses for term %s (%d subjects)...", args.term, len(subjects))
            for i, subj in enumerate(subjects, 1):
                code = subj["code"]
                log.info("  [%d/%d] %s", i, len(subjects), code)
                try:
                    sections = fetch_subject_courses(code, args.term, client)
                    if sections:
                        courses_by_subject[code] = sections
                        log.info("    → %d sections", len(sections))
                    else:
                        log.info("    → 0 sections (skipped)")
                except Exception as exc:
                    log.warning("    FAILED %s: %s", code, exc)
        else:
            log.info("Skipping timetable fetch (--skip-timetable)")

        # ── 4. Merge & save ───────────────────────────────────────────────────
        save_outputs(subjects, programs, courses_by_subject, args.term)

    log.info("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
