from fastapi import APIRouter, HTTPException, Query
from app.services.scraper_service import (
    scrape_vt_courses,
    load_courses,
    list_cached_subjects,
    scrape_vt_catalog_page,
)
from app.services.ai_service import summarize_course_data

router = APIRouter(prefix="/courses", tags=["Courses"])


@router.get("/subjects")
def get_cached_subjects():
    """List all subject codes that have been scraped and cached locally."""
    return {"subjects": list_cached_subjects()}


@router.get("/{subject}")
def get_courses(
    subject: str,
    year_term: str = Query(default="202601", description="VT term code e.g. 202601 = Spring 2026"),
    refresh: bool = Query(default=False, description="Force re-scrape even if cached"),
):
    """
    Get course listings for a VT subject code (e.g. CS, MATH, ECE).
    Returns cached data unless refresh=true.
    """
    subject = subject.upper()

    if not refresh:
        cached = load_courses(subject)
        if cached is not None:
            return {"source": "cache", "subject": subject, "courses": cached}

    try:
        courses = scrape_vt_courses(subject, year_term)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Scrape failed: {str(e)}")

    return {"source": "scraped", "subject": subject, "courses": courses}


@router.post("/parse-url")
def parse_catalog_url(
    url: str = Query(..., description="URL of a VT catalog page to parse"),
):
    """
    Scrape a VT catalog HTML page and use AI to extract structured course data.
    Useful for one-off catalog pages not covered by the timetable API.
    """
    try:
        raw_text = scrape_vt_catalog_page(url)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Could not fetch page: {str(e)}")

    try:
        structured = summarize_course_data(raw_text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"AI parsing failed: {str(e)}")

    return {"parsed": structured}
