"""
vt_minors_scraper.py

Scrapes all undergraduate minors from the Virginia Tech Academic Catalog
(https://catalog.vt.edu/undergraduate/minors/) and writes them to a JSONL
file — one JSON object per line — suitable for fine-tuning or RAG ingestion.

Usage:
    python vt_minors_scraper.py
    python vt_minors_scraper.py --outfile ../data/vt_minors.jsonl
    python vt_minors_scraper.py --delay 0.6

Output format per line:
    {
      "name":          "Computer Science (CS) Minor",
      "code":          "CS",
      "url":           "https://catalog.vt.edu/undergraduate/minors/computer-science-minor/",
      "description":   "...",
      "courses":       [{"code": "CS 1114", "title": "...", "credits": "3", "note": ""}, ...],
      "total_credits": 21,
      "requirements":  "..."
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
from bs4 import BeautifulSoup, Tag

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("vt_minors_scraper")

# ── Constants ─────────────────────────────────────────────────────────────────

BASE_URL    = "https://catalog.vt.edu"
MINORS_URL  = f"{BASE_URL}/undergraduate/minors/"
REQUEST_DELAY = 0.5
MAX_RETRIES   = 4

_SCRAPER_DIR = os.path.dirname(os.path.abspath(__file__))
_DATA_DIR    = os.path.join(_SCRAPER_DIR, "..", "data")
os.makedirs(_DATA_DIR, exist_ok=True)


# ── HTTP helpers ──────────────────────────────────────────────────────────────

def _make_client() -> httpx.Client:
    return httpx.Client(
        timeout=20,
        follow_redirects=True,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:124.0) "
                "Gecko/20100101 Firefox/124.0"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        },
    )


def _get_html(url: str, client: httpx.Client) -> Optional[str]:
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
            log.warning("  Retry %d/%d for %s in %.0fs (%s)", attempt + 1, MAX_RETRIES, url, wait, exc)
            time.sleep(wait)
    log.error("  All retries exhausted for %s: %s", url, last_exc)
    return None


# ── Index parsing ─────────────────────────────────────────────────────────────

def _extract_code(name: str) -> str:
    """Pull the abbreviation out of e.g. 'Computer Science (CS) Minor' → 'CS'."""
    m = re.search(r"\(([A-Z][A-Z0-9\-]*)\)", name)
    return m.group(1) if m else ""


def fetch_minor_index(client: httpx.Client) -> list[dict]:
    """Return list of {name, code, url} for every minor on the index page."""
    log.info("Fetching minors index: %s", MINORS_URL)
    html = _get_html(MINORS_URL, client)
    if not html:
        log.error("Could not fetch minors index.")
        return []

    soup = BeautifulSoup(html, "html.parser")
    seen: set[str] = set()
    minors: list[dict] = []

    for a in soup.find_all("a", href=True):
        href: str = a["href"]
        if not re.match(r"^/undergraduate/minors/[^/]+/$", href):
            continue
        if href in seen:
            continue
        seen.add(href)
        name = re.sub(r"[​\xa0]", "", a.get_text(strip=True))  # strip zero-width spaces
        if not name or "PDF" in name:
            continue
        minors.append({
            "name": name,
            "code": _extract_code(name),
            "url":  BASE_URL + href,
        })

    log.info("Found %d minors", len(minors))
    return minors


# ── Minor page parsing ────────────────────────────────────────────────────────

def _clean(text: str) -> str:
    return re.sub(r"[​\xa0\s]+", " ", text).strip()


def _parse_course_table(table: Tag) -> tuple[list[dict], int]:
    """
    Parse an sc_courselist table into a list of course dicts and total credits.

    Each dict has:
        code, title, credits (string), note (e.g. "or", "select N of")
    """
    courses: list[dict] = []
    total_credits = 0
    current_note = ""

    for row in table.find_all("tr"):
        tds = row.find_all("td")
        if not tds:
            continue

        classes = row.get("class", [])

        # Section header comment rows (e.g. "Required Minor Courses", "Select two of:")
        if "courselistcomment" in " ".join(classes) or all(
            "courselistcomment" in (td.get("class") or []) or td.find("span", class_="courselistcomment")
            for td in tds[:1]
        ):
            span = tds[0].find("span", class_="courselistcomment")
            if span:
                current_note = _clean(span.get_text())
            continue

        # Total credits summary row
        if "listsum" in " ".join(classes):
            try:
                total_credits = int(_clean(tds[-1].get_text()))
            except ValueError:
                pass
            continue

        # Subtotal rows — skip
        if len(tds) == 2 and _clean(tds[0].get_text()).lower() == "subtotal":
            continue

        # "or" variant rows
        is_or = "orclass" in " ".join(classes)

        # Code cell
        code_td = tds[0]
        code_span = code_td.find("span", class_="courselistcomment")
        code_a = code_td.find("a")
        if code_span:
            code = _clean(code_span.get_text())
        elif code_a:
            code = _clean(code_a.get_text())
        else:
            code = _clean(code_td.get_text())

        # Title and credits
        if len(tds) >= 3:
            title   = _clean(tds[1].get_text())
            credits = _clean(tds[2].get_text())
        elif len(tds) == 2:
            title   = _clean(tds[1].get_text())
            credits = ""
        else:
            title   = ""
            credits = ""

        # Strip the "or " prefix from code when it bleeds into the text
        code = re.sub(r"^or\s+", "", code).strip()

        if not code and not title:
            continue

        courses.append({
            "code":    code,
            "title":   title,
            "credits": credits,
            "note":    ("or" if is_or else current_note),
        })

    return courses, total_credits


def _parse_requirements_text(container: Tag) -> str:
    """Extract the plain-text requirements/notes that follow the course table."""
    lines: list[str] = []
    in_reqs = False

    for tag in container.find_all(["h2", "h3", "p", "li"]):
        text = _clean(tag.get_text(separator=" "))
        if not text:
            continue
        if tag.name in ("h2", "h3"):
            in_reqs = True
            lines.append(f"\n{text}")
        elif in_reqs:
            lines.append(text)

    return "\n".join(lines).strip()


def parse_minor_page(html: str, meta: dict) -> dict:
    """Parse a minor detail page into a structured dict."""
    soup = BeautifulSoup(html, "html.parser")

    # Description (often empty)
    desc_div = soup.find("div", id="textcontainer")
    description = _clean(desc_div.get_text(separator=" ")) if desc_div else ""

    # Curriculum section
    curr_div = soup.find("div", id="programcurriculumtextcontainer")
    courses: list[dict] = []
    total_credits = 0
    requirements = ""

    if curr_div:
        table = curr_div.find("table", class_="sc_courselist")
        if table:
            courses, total_credits = _parse_course_table(table)
        requirements = _parse_requirements_text(curr_div)

    return {
        "name":          meta["name"],
        "code":          meta["code"],
        "url":           meta["url"],
        "description":   description,
        "courses":       courses,
        "total_credits": total_credits,
        "requirements":  requirements,
    }


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    global REQUEST_DELAY  # noqa: PLW0603

    parser = argparse.ArgumentParser(
        description="Scrape VT undergraduate minors into a JSONL file for fine-tuning.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--outfile", default=os.path.join(_DATA_DIR, "vt_minors.jsonl"),
        help="Path to output JSONL file",
    )
    parser.add_argument(
        "--delay", type=float, default=REQUEST_DELAY,
        help="Seconds between HTTP requests",
    )
    args = parser.parse_args()
    REQUEST_DELAY = args.delay

    failed: list[str] = []
    written = 0

    with _make_client() as client:
        minors = fetch_minor_index(client)
        if not minors:
            log.error("No minors found — aborting.")
            return 1

        try:
            out_f = open(args.outfile, "w", encoding="utf-8")
        except OSError as exc:
            log.error("Cannot open output file: %s", exc)
            return 1

        with out_f:
            for i, meta in enumerate(minors, 1):
                log.info("[%d/%d] %s", i, len(minors), meta["name"])
                html = _get_html(meta["url"], client)
                if html is None:
                    log.warning("  Skipped (no response)")
                    failed.append(meta["name"])
                    continue

                try:
                    record = parse_minor_page(html, meta)
                except Exception as exc:
                    log.error("  Parse error for %s: %s", meta["name"], exc)
                    failed.append(meta["name"])
                    continue

                out_f.write(json.dumps(record, ensure_ascii=False) + "\n")
                written += 1

    log.info("Done. %d minors written → %s", written, args.outfile)
    if failed:
        log.warning("Failed (%d): %s", len(failed), ", ".join(failed))

    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
