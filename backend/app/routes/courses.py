from fastapi import APIRouter, HTTPException, Query
from app.routes.errors import error_detail
from app.services.scraper_service import (
    load_courses,
    load_unique_courses,
    list_all_subjects,
    list_cached_subjects,
    list_all_programs,
    search_programs,
    search_courses_by_keyword,
    get_catalog_meta,
    scrape_vt_major_catalog,
)

router = APIRouter(prefix="/courses", tags=["Courses"])


@router.get("/meta")
def get_catalog_meta_endpoint():
    """Return scrape metadata (timestamp, counts) from the full catalog."""
    meta = get_catalog_meta()
    if meta is None:
        return {"status": "no_full_catalog", "hint": "Run `python scraper/vt_scraper.py` to build the catalog."}
    return meta


@router.get("/subjects")
def get_subjects():
    """List all known VT subject codes."""
    return {"subjects": list_all_subjects()}


@router.get("/programs")
def get_programs(q: str = Query(default="", description="Filter programs by name keyword")):
    """List all discovered VT undergraduate programs. Optionally filter by keyword."""
    if q:
        programs = search_programs(q)
    else:
        programs = list_all_programs()
    return {"count": len(programs), "programs": programs}


@router.get("/programs/{major}/requirements")
def get_program_requirements(major: str):
    """Return degree requirements for a major/minor (from the full catalog or legacy cache)."""
    data = scrape_vt_major_catalog(major)
    if not data.get("required_courses") and not data.get("electives"):
        raise HTTPException(
            status_code=404,
            detail=error_detail(
                "COURSES_REQUIREMENTS_NOT_FOUND",
                f"No requirements found for '{major}'. Run the scraper or check the major name.",
            ),
        )
    return data


@router.get("/search")
def search_courses(q: str = Query(..., description="Keyword to search in course names/descriptions")):
    """Search all scraped courses by keyword across all subjects."""
    results = search_courses_by_keyword(q)
    return {"query": q, "count": len(results), "courses": results}


@router.get("/{subject}")
def get_courses(
    subject: str,
    unique: bool = Query(default=False, description="Return deduplicated course records instead of all sections"),
):
    """
    Get course listings for a VT subject code (e.g. CS, MATH, ECE).
    Use ?unique=true for one record per course code (no duplicate sections).
    """
    subject = subject.upper()
    if unique:
        courses = load_unique_courses(subject)
    else:
        courses = load_courses(subject)

    if courses is None:
        raise HTTPException(
            status_code=404,
            detail=error_detail(
                "COURSES_CACHE_MISSING",
                f"No cached data for '{subject}'. Run `python scraper/vt_scraper.py` to populate the cache.",
            ),
        )
    return {"subject": subject, "count": len(courses), "unique": unique, "courses": courses}
