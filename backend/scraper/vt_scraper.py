"""
vt_scraper.py

Virginia Tech course scraper using the VT Academic Catalog (catalog.vt.edu).

Fetches course descriptions for a fixed set of subjects and merges them with
structured requirement JSON files from ../data/catalog/.

Usage:
    python vt_scraper.py --term 202601
    python vt_scraper.py --term 202601 --preset coe
    python vt_scraper.py --term 202601 --subjects CS MATH
    python vt_scraper.py --term 202601 --preset coe --outdir ../data/coe/

Writes (single-file mode, default):
    ../data/vt_catalog_{term}.json

Writes (directory mode, --outdir):
    {outdir}/manifest.json        — index with metadata for all subjects
    {outdir}/{SUBJECT}.json       — courses + requirements per subject

Output format per subject:
    {
      "courses": [...],
      "requirements": {...}
    }

Exit codes: 0 = success, 1 = fatal error
"""

from __future__ import annotations

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
from bs4 import BeautifulSoup

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("vt_scraper")

# ── Constants ─────────────────────────────────────────────────────────────────

CATALOG_URL = "https://catalog.vt.edu/undergraduate/course-descriptions/{subject}/"

# Default subject list (general)
FIXED_SUBJECTS = ["CS", "MATH", "ECE", "ME", "PHYS", "CHEM", "BIOL"]

# Virginia Tech College of Engineering departments
COE_SUBJECTS = [
    "AOE",   # Aerospace and Ocean Engineering
    "BSE",   # Biological Systems Engineering
    "BMES",  # Biomedical Engineering & Sciences
    "CEE",   # Civil and Environmental Engineering
    "CHE",   # Chemical Engineering
    "CS",    # Computer Science
    "ECE",   # Electrical & Computer Engineering
    "ENGE",  # Engineering Education
    "ENGR",  # Engineering (general / cross-listed)
    "ESM",   # Engineering Science and Mechanics
    "ISE",   # Industrial and Systems Engineering
    "ME",    # Mechanical Engineering
    "MINE",  # Mining and Minerals Engineering
    "MSE",   # Materials Science and Engineering
]

PRESETS = {
    "coe":     COE_SUBJECTS,
    "default": FIXED_SUBJECTS,
}

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
}


# ── HTTP helpers ──────────────────────────────────────────────────────────────

def _make_client() -> httpx.Client:
    return httpx.Client(
        timeout=20,
        follow_redirects=True,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        },
    )


def _get_html(url: str, client: httpx.Client) -> Optional[str]:
    """GET HTML with exponential-backoff retry. Returns None on failure."""
    time.sleep(REQUEST_DELAY)
    last_exc: Exception = RuntimeError("no attempts made")
    for attempt in range(MAX_RETRIES):
        try:
            r = client.get(url)
            r.raise_for_status()
            return r.text
        except (httpx.HTTPStatusError, httpx.TransportError, httpx.TimeoutException) as exc:
            last_exc = exc
            if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code < 500:
                log.warning("  HTTP %d for %s — skipping", exc.response.status_code, url)
                return None
            wait = 2.0 ** attempt
            log.warning(
                "  Retry %d/%d for %s in %.0fs (%s)",
                attempt + 1, MAX_RETRIES, url, wait, exc,
            )
            time.sleep(wait)
    log.error("  All retries exhausted for %s: %s", url, last_exc)
    return None


# ── Course parsing ────────────────────────────────────────────────────────────

def _parse_courses(html: str) -> list[dict]:
    """Parse courseblock divs from catalog HTML into a list of course dicts."""
    soup = BeautifulSoup(html, "html.parser")
    results = []

    for block in soup.find_all("div", class_="courseblock"):
        # Code — e.g. "CS 1014"
        code_tag = block.find("span", class_=re.compile(r"detail-code"))
        code = code_tag.get_text(strip=True) if code_tag else ""

        # Title — strip leading "- "
        title_tag = block.find("span", class_=re.compile(r"detail-title"))
        title = title_tag.get_text(strip=True).lstrip("- ").strip() if title_tag else ""

        # Credits — e.g. "(3 credits)" → "3"
        hours_tag = block.find("span", class_=re.compile(r"detail-hours"))
        credits_raw = hours_tag.get_text(strip=True) if hours_tag else ""
        credits_match = re.search(r"(\d[\d\s\-–]*)\s*credit", credits_raw, re.IGNORECASE)
        credits = credits_match.group(1).strip() if credits_match else credits_raw

        # Description
        desc_tag = block.find("div", class_="courseblockextra")
        description = desc_tag.get_text(strip=True) if desc_tag else ""

        # Prerequisites
        prereq_tag = block.find("span", class_=re.compile(r"detail-prereq"))
        if prereq_tag:
            prereq_text = prereq_tag.get_text(separator=" ", strip=True)
            prereq_text = re.sub(r"^Prerequisite\(s\):\s*", "", prereq_text)
            prereq_text = re.sub(r"[\xa0\s]+", " ", prereq_text).strip()
        else:
            prereq_text = ""

        results.append({
            "code":          code,
            "name":          title,
            "credits":       credits,
            "description":   description,
            "prerequisites": prereq_text,
        })

    return results


def fetch_subject_courses(subject: str, client: httpx.Client) -> list[dict]:
    """Fetch and parse all courses for a subject from the VT catalog."""
    url = CATALOG_URL.format(subject=subject.lower())
    log.info("  Fetching %s from %s", subject, url)

    html = _get_html(url, client)
    if html is None:
        log.warning("  No data returned for %s — skipping", subject)
        return []

    courses = _parse_courses(html)
    log.info("  %s: %d courses parsed", subject, len(courses))
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


# ── Output helpers ────────────────────────────────────────────────────────────

def _write_single_file(payload: dict, term: str) -> bool:
    """Write all subjects into one JSON file. Returns True on success."""
    out_path = os.path.join(_DATA_DIR, f"vt_catalog_{term}.json")
    try:
        with open(out_path, "w") as f:
            json.dump(payload, f, indent=2)
        log.info("Saved → %s", out_path)
        return True
    except OSError as exc:
        log.error("Failed to write output: %s", exc)
        return False


def _write_directory(output: dict[str, dict], meta: dict, outdir: str) -> bool:
    """
    Write one JSON per subject plus a manifest.json into outdir.
    Returns True on success.
    """
    os.makedirs(outdir, exist_ok=True)

    # manifest.json — lightweight index
    manifest = {
        "meta": meta,
        "subjects": {
            subj: {
                "file":         f"{subj}.json",
                "course_count": len(data["courses"]),
                "has_requirements": bool(data["requirements"]),
            }
            for subj, data in output.items()
        },
    }
    manifest_path = os.path.join(outdir, "manifest.json")
    try:
        with open(manifest_path, "w") as f:
            json.dump(manifest, f, indent=2)
        log.info("  manifest.json written")
    except OSError as exc:
        log.error("Failed to write manifest: %s", exc)
        return False

    # One file per subject
    for subj, data in output.items():
        path = os.path.join(outdir, f"{subj}.json")
        try:
            with open(path, "w") as f:
                json.dump(data, f, indent=2)
            log.info("  %s.json  (%d courses)", subj, len(data["courses"]))
        except OSError as exc:
            log.error("Failed to write %s.json: %s", subj, exc)
            return False

    log.info("Saved directory → %s  (%d files)", outdir, len(output) + 1)
    return True


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    global REQUEST_DELAY  # noqa: PLW0603

    parser = argparse.ArgumentParser(
        description="Fetch VT course data from catalog.vt.edu and merge with requirement files.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--term", default="202601",
        help="VT term code used for output filename (e.g. 202601 = Spring 2026)",
    )
    parser.add_argument(
        "--preset", choices=list(PRESETS.keys()), default=None,
        help="Named subject preset: 'coe' = College of Engineering, 'default' = original set",
    )
    parser.add_argument(
        "--subjects", nargs="+", default=None,
        help="Explicit subject codes to scrape (overrides --preset)",
    )
    parser.add_argument(
        "--outdir", default=None,
        help="Write one JSON per subject into this directory instead of a single file",
    )
    parser.add_argument(
        "--delay", type=float, default=0.4,
        help="Seconds between HTTP requests",
    )
    args = parser.parse_args()

    REQUEST_DELAY = args.delay

    if args.subjects:
        subjects = [s.upper() for s in args.subjects]
    elif args.preset:
        subjects = PRESETS[args.preset]
    else:
        subjects = FIXED_SUBJECTS

    log.info("Term: %s | Subjects: %s", args.term, ", ".join(subjects))

    output: dict[str, dict] = {}
    failed: list[str] = []

    with _make_client() as client:
        for subject in subjects:
            log.info("[%s]", subject)
            try:
                courses = fetch_subject_courses(subject, client)
            except Exception as exc:
                log.error("  Unexpected error fetching %s: %s", subject, exc)
                failed.append(subject)
                continue

            requirements = load_requirements(subject)
            output[subject] = {"courses": courses, "requirements": requirements}

    meta = {
        "scraped_at": datetime.now(timezone.utc).isoformat(),
        "term":       args.term,
        "subjects":   subjects,
        "failed":     failed,
    }

    if args.outdir:
        success = _write_directory(output, meta, args.outdir)
    else:
        success = _write_single_file({"meta": meta, **output}, args.term)

    if not success:
        return 1

    if failed:
        log.warning("Failed subjects: %s", ", ".join(failed))

    log.info("Done.")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
